#!/usr/bin/env python3
"""Collect AI subscription quota usage and ship it to OTel as OTLP metrics.

Each source is read-only: credentials are never refreshed and log files are
only opened for reading. A source that is missing, expired, or unparseable is
skipped; its previous observation stays visible through
`quota_observed_at_seconds` so a stalled source shows up as stale data.

Run with `--once` for a single pass, otherwise it loops forever.
"""

from __future__ import annotations

import glob
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

CLAUDE_CREDENTIAL_SERVICE = "Claude Code-credentials"
CLAUDE_USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
OLLAMA_BASE_URL = "http://127.0.0.1:11434"
OPENCODE_USAGE_URL = "https://opencode.ai/inference/go/v1/usage"
SECURITY = "/usr/bin/security"

DEFAULT_ENDPOINT = "http://forge01:4318/v1/metrics"
DEFAULT_INTERVAL = 60
# Some providers sit behind a bot filter that rejects urllib's default agent.
USER_AGENT = "quota-collector/1"

# Token logs are only re-read for files touched this recently, and a file seen
# for the first time contributes only the tail of that window.
TOKEN_HISTORY_SECONDS = 7 * 24 * 3600
CLAUDE_PROJECTS = "~/.claude/projects"
CODEX_SESSIONS = "~/.codex/sessions"
PI_SESSIONS = "~/.pi/agent/sessions"
TOKEN_KINDS = ("input", "output", "cache_read", "cache_write")

# Nominal window lengths, used to compare usage against elapsed time. Monthly
# has no single length in any API, so it is approximated as 30 days; Ollama
# overrides it with the billing period it reports.
WINDOW_SECONDS = {
    "5h": 5 * 3600,
    "weekly": 7 * 24 * 3600,
    "monthly": 30 * 24 * 3600,
    "spend": 30 * 24 * 3600,
}

# Codex reports rate-limit windows in minutes; map them onto the shared
# service/window vocabulary. Anything longer than a month is treated as
# monthly so an unexpected window still lands somewhere sensible.
CODEX_WINDOWS = [(60 * 6, "5h"), (60 * 24 * 14, "weekly"), (60 * 24 * 62, "monthly")]

# The Claude usage endpoint rate-limits aggressive polling, so read it less
# often than the other sources.
CLAUDE_MIN_INTERVAL = 300

# Sources that report errors, so a healthy one keeps sending a zero counter.
SOURCES = ("claude_code", "ollama_cloud", "opencode_go", "codex")

# Walk at most this many Codex session logs before giving up on the newest
# `rate_limits`, so a brand-new session without one does not hide the previous.
CODEX_SESSIONS_TO_SCAN = 20


class SourceError(Exception):
    """A source could not be read this pass."""


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def http_json(url: str, headers: dict[str, str] | None = None, timeout: float = 10):
    request_headers = {"User-Agent": USER_AGENT, "Accept": "application/json"}
    request_headers.update(headers or {})
    request = urllib.request.Request(url, headers=request_headers)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def to_epoch(value) -> float | None:
    """Accept unix seconds, unix milliseconds, or ISO-8601 timestamps."""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        number = float(value)
        return number / 1000 if number > 1e11 else number
    text = str(value).strip()
    if not text:
        return None
    try:
        return to_epoch(float(text))
    except ValueError:
        pass
    try:
        from datetime import datetime

        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
        return parsed.timestamp()
    except ValueError:
        return None


def _int_leaves(value) -> dict:
    """Rebuild nested dicts with integer leaves from JSON state."""
    if not isinstance(value, dict):
        return {}
    result = {}
    for key, item in value.items():
        if isinstance(item, dict):
            nested = _int_leaves(item)
            if nested:
                result[key] = nested
        elif isinstance(item, int):
            result[key] = item
    return result


class Collector:
    def __init__(self, host: str, state_path: str | None = None) -> None:
        self.host = host
        self.state_path = state_path
        self.points: list[dict] = []
        self.errors: dict[str, int] = {}
        self.tokens: dict[str, dict[str, int]] = {}
        self.live: dict[str, dict[str, int]] = {}
        self.buckets: dict[int, dict[str, dict[str, int]]] = {}
        self.offsets: dict[str, dict] = {}
        self.now = time.time()
        self.claude_next_at = 0.0
        self._load_state()

    # -- counters ---------------------------------------------------------
    def _load_state(self) -> None:
        """Keep error counters monotonic across daemon restarts."""
        if not self.state_path:
            return
        try:
            with open(self.state_path, encoding="utf-8") as handle:
                stored = json.load(handle)
        except (OSError, ValueError):
            return
        for source, count in (stored.get("errors") or {}).items():
            if isinstance(count, int) and count >= 0:
                self.errors[source] = count
        self.tokens = _int_leaves(stored.get("tokens"))
        self.live = _int_leaves(stored.get("live"))
        for hour, services in (stored.get("buckets") or {}).items():
            try:
                hour_key = int(hour)
            except (TypeError, ValueError):
                continue
            converted = _int_leaves(services)
            if converted:
                self.buckets[hour_key] = converted
        for path, entry in (stored.get("offsets") or {}).items():
            if isinstance(entry, dict) and isinstance(entry.get("offset"), int):
                self.offsets[path] = entry

    def _save_state(self) -> None:
        if not self.state_path:
            return
        try:
            directory = os.path.dirname(self.state_path)
            if directory:
                os.makedirs(directory, mode=0o700, exist_ok=True)
            temporary = f"{self.state_path}.tmp"
            with open(temporary, "w", encoding="utf-8") as handle:
                json.dump(
                    {
                        "errors": self.errors,
                        "tokens": self.tokens,
                        "live": self.live,
                        "buckets": {str(hour): value for hour, value in self.buckets.items()},
                        "offsets": self.offsets,
                    },
                    handle,
                )
            os.replace(temporary, self.state_path)
        except OSError as error:
            log(f"state {self.state_path}: {error}")

    # -- emission ---------------------------------------------------------
    def emit(self, name: str, value, attrs: dict[str, str]) -> None:
        if value is None:
            return
        self.points.append({"name": name, "value": value, "attrs": attrs})

    def quota(
        self,
        service: str,
        window: str,
        used_percent=None,
        resets_at=None,
        observed_at=None,
        scope: str | None = None,
        window_seconds: float | None = None,
    ) -> None:
        attrs = {"service": service, "window": window}
        if scope:
            attrs["scope"] = scope
        self.emit("quota_used_percent", used_percent, attrs)
        if resets_at is not None:
            self.emit("quota_resets_at_seconds", resets_at, attrs)
        if observed_at is not None:
            self.emit("quota_observed_at_seconds", observed_at, attrs)
        length = window_seconds if window_seconds is not None else WINDOW_SECONDS.get(window)
        if length:
            self.emit("quota_window_seconds", length, attrs)

    def fail(self, source: str, error: Exception) -> None:
        self.errors[source] = self.errors.get(source, 0) + 1
        log(f"{source}: {error}")

    # -- sources ----------------------------------------------------------
    def claude_due(self) -> bool:
        return self.now >= self.claude_next_at

    def collect_claude(self) -> None:
        if not self.claude_due():
            return
        # Retry after a rate limit, not on the next pass.
        self.claude_next_at = self.now + CLAUDE_MIN_INTERVAL
        try:
            credentials = json.loads(
                subprocess.run(
                    [SECURITY, "find-generic-password", "-s", CLAUDE_CREDENTIAL_SERVICE, "-w"],
                    capture_output=True,
                    text=True,
                    timeout=10,
                    check=True,
                ).stdout
            )
            oauth = credentials["claudeAiOauth"]
            expires_at = to_epoch(oauth.get("expiresAt"))
            if expires_at is not None and expires_at <= self.now:
                raise SourceError("OAuth token expired; waiting for Claude Code to refresh it")
            data = http_json(
                CLAUDE_USAGE_URL,
                headers={
                    "Authorization": f"Bearer {oauth['accessToken']}",
                    "anthropic-beta": "oauth-2025-04-20",
                    "Content-Type": "application/json",
                },
            )
        except (SourceError, KeyError, OSError, subprocess.SubprocessError, urllib.error.URLError) as error:
            self.fail("claude_code", error)
            return

        observed = self.now
        windows = {"session": "5h", "weekly": "weekly"}
        for limit in data.get("limits") or []:
            window = windows.get(limit.get("group") or "", limit.get("group") or "")
            if not window:
                continue
            scope = None
            scope_model = (limit.get("scope") or {}).get("model") or {}
            if limit.get("kind") == "weekly_scoped":
                scope = scope_model.get("display_name") or scope_model.get("id")
            self.quota(
                "claude_code",
                window,
                used_percent=limit.get("percent"),
                resets_at=to_epoch(limit.get("resets_at")),
                observed_at=observed,
                scope=scope,
            )

        spend = data.get("spend") or {}
        if spend.get("enabled") and spend.get("limit"):
            used = (spend.get("used") or {}).get("amount_minor")
            limit = spend.get("limit", {}).get("amount_minor")
            exponent = 10 ** int(spend.get("limit", {}).get("exponent") or 2)
            attrs = {"service": "claude_code", "window": "spend"}
            if used is not None:
                self.emit("quota_used_usd", used / exponent, attrs)
            if limit is not None:
                self.emit("quota_limit_usd", limit / exponent, attrs)
            self.emit("quota_used_percent", spend.get("percent"), attrs)
            self.emit("quota_observed_at_seconds", observed, attrs)

    def collect_ollama(self) -> None:
        try:
            balance = http_json(f"{OLLAMA_BASE_URL}/api/balance")
        except (OSError, urllib.error.URLError, json.JSONDecodeError) as error:
            self.fail("ollama_cloud", error)
            return

        observed = self.now
        included = balance.get("included") or {}
        allowance = included.get("allowance_usd")
        remaining = included.get("balance_usd")
        period = included.get("period") or {}
        period_start = to_epoch(period.get("from"))
        period_end = to_epoch(period.get("until"))
        period_seconds = None
        if period_start is not None and period_end is not None and period_end > period_start:
            period_seconds = period_end - period_start
        attrs = {"service": "ollama_cloud", "window": "monthly"}
        if period_seconds:
            self.emit("quota_window_seconds", period_seconds, attrs)
        if allowance and remaining is not None:
            used = allowance - remaining
            self.emit("quota_used_usd", used, attrs)
            self.emit("quota_limit_usd", allowance, attrs)
            self.emit("quota_used_percent", used / allowance * 100, attrs)
        if period_end is not None:
            self.emit("quota_resets_at_seconds", period_end, attrs)
        self.emit("quota_observed_at_seconds", observed, attrs)

        purchased = (balance.get("purchased") or {}).get("balance_usd")
        if purchased is not None:
            self.emit("credit_balance_usd", purchased, {"service": "ollama_cloud"})


    def collect_opencode(self) -> None:
        try:
            with open(os.path.expanduser("~/.pi/agent/auth.json"), encoding="utf-8") as handle:
                key = json.load(handle)["opencode-go"]["key"]
            data = http_json(
                OPENCODE_USAGE_URL,
                headers={"Authorization": f"Bearer {key}"},
            )
        except (OSError, KeyError, json.JSONDecodeError, urllib.error.URLError) as error:
            self.fail("opencode_go", error)
            return

        windows = {"rolling": "5h", "weekly": "weekly", "monthly": "monthly"}
        for key_name, window in windows.items():
            entry = data.get("usage", {}).get(key_name)
            if not entry:
                continue
            self.quota(
                "opencode_go",
                window,
                used_percent=entry.get("percent"),
                resets_at=to_epoch(entry.get("resetsAt")),
                observed_at=self.now,
            )

    def collect_codex(self) -> None:
        try:
            sessions = codex_sessions(CODEX_SESSIONS_TO_SCAN)
            if not sessions:
                raise SourceError("no session logs")
            found = None
            for path, mtime in sessions:
                try:
                    found = last_codex_rate_limits(path)
                except OSError as error:
                    log(f"codex: skipping {path}: {error}")
                    continue
                if found:
                    observed = found["observed_at"] or mtime
                    break
            if not found:
                raise SourceError("no rate_limits in recent sessions")
            rate_limits = found["rate_limits"]
        except (OSError, SourceError) as error:
            self.fail("codex", error)
            return

        for slot, label in (("primary", None), ("secondary", None)):
            entry = rate_limits.get(slot)
            if not entry:
                continue
            window = codex_window(entry.get("window_minutes"))
            resets_at = to_epoch(entry.get("resets_at"))
            if resets_at is None and entry.get("resets_in_seconds") is not None:
                resets_at = observed + float(entry["resets_in_seconds"])
            length = None
            if entry.get("window_minutes") is not None:
                length = float(entry["window_minutes"]) * 60
            self.quota(
                "codex",
                window,
                used_percent=entry.get("used_percent"),
                resets_at=resets_at,
                observed_at=observed,
                window_seconds=length,
            )

    def collect_tokens(self) -> None:
        """Accumulate token totals from the Claude Code and Codex logs."""
        cutoff = self.now - TOKEN_HISTORY_SECONDS
        sources = (
            ("claude_code", os.path.expanduser(CLAUDE_PROJECTS), claude_token_deltas),
            ("codex", os.path.expanduser(CODEX_SESSIONS), codex_token_deltas),
            ("pi", os.path.expanduser(PI_SESSIONS), pi_token_deltas),
        )
        for service, root, deltas_of in sources:
            try:
                files = [
                    os.path.join(directory, name)
                    for directory, _, names in os.walk(root)
                    for name in names
                    if name.endswith(".jsonl")
                ]
            except OSError as error:
                self.fail(f"tokens_{service}", error)
                continue
            for path in files:
                try:
                    os.stat(path)
                except OSError:
                    continue
                try:
                    mtime = os.path.getmtime(path)
                except OSError:
                    continue
                entry = self.offsets.get(path)
                if entry is None and mtime <= cutoff:
                    continue
                try:
                    if entry is None:
                        self._scan_first_time(service, path, deltas_of, cutoff)
                    elif mtime > cutoff:
                        self._scan_tail(service, path, deltas_of, entry)
                except OSError as error:
                    self.fail(f"tokens_{service}", error)
                    continue
                if entry is not None and mtime <= cutoff:
                    self.offsets.pop(path, None)

        cutoff_hour = int((self.now - TOKEN_HISTORY_SECONDS) // 3600) * 3600
        for hour in [key for key in self.buckets if key < cutoff_hour]:
            del self.buckets[hour]

        # The counter starts at zero so its first hour does not look like a
        # spike; window totals come from the buckets instead.
        for service, providers in self.live.items():
            for provider, models in providers.items():
                for model, kinds in models.items():
                    for kind in TOKEN_KINDS:
                        self.emit(
                            "tokens_total",
                            kinds.get(kind, 0),
                            {
                                "service": service,
                                "provider": provider,
                                "model": model,
                                "kind": kind,
                            },
                        )

        # Window sums are computed here, not in PromQL: `increase`/`delta`
        # extrapolate to the requested range, which inflates the numbers until
        # a full window of samples exists.
        for window, span in (("1d", 24 * 3600), ("7d", 7 * 24 * 3600)):
            since = self.now - span
            totals: dict[tuple[str, str, str, str], int] = {}
            for hour, services in self.buckets.items():
                if hour + 3600 <= since:
                    continue
                for service, providers in services.items():
                    for provider, models in providers.items():
                        for model, kinds in models.items():
                            for kind, value in kinds.items():
                                key = (service, provider, model, kind)
                                totals[key] = totals.get(key, 0) + value
            for service in self.tokens:
                for provider, models in self.tokens[service].items():
                    for model in models:
                        for kind in TOKEN_KINDS:
                            self.emit(
                                "tokens_window_total",
                                totals.get((service, provider, model, kind), 0),
                                {
                                    "service": service,
                                    "provider": provider,
                                    "model": model,
                                    "kind": kind,
                                    "window": window,
                                },
                            )

    @staticmethod
    def _accumulate(store: dict, service: str, provider: str, model: str, deltas) -> None:
        kinds = (
            store.setdefault(service, {})
            .setdefault(provider, {})
            .setdefault(model, {})
        )
        for kind in TOKEN_KINDS:
            kinds[kind] = kinds.get(kind, 0) + int(deltas.get(kind, 0))

    def _add_tokens(
        self,
        service: str,
        provider: str,
        model: str,
        deltas: dict[str, int],
        occurred: float | None,
        live: bool,
    ) -> None:
        if live:
            self._accumulate(self.live, service, provider, model, deltas)
        self._accumulate(self.tokens, service, provider, model, deltas)
        hour = int((occurred if occurred is not None else self.now) // 3600) * 3600
        self._accumulate(self.buckets.setdefault(hour, {}), service, provider, model, deltas)

    def _scan_first_time(self, service: str, path: str, deltas_of, cutoff: float) -> None:
        """Count the last week of a file seen for the first time, then follow it."""
        size = os.path.getsize(path)
        offset = 0
        last_id = None
        context: dict[str, str] = {}
        while offset < size:
            lines, offset = read_from_offset(path, offset)
            if not lines:
                break
            for raw in lines:
                try:
                    record = json.loads(raw)
                except json.JSONDecodeError:
                    continue
                occurred = to_epoch(record.get("timestamp"))
                if occurred is not None and occurred < cutoff:
                    continue
                if service == "claude_code":
                    message = record.get("message") or {}
                    identifier = message.get("id") if isinstance(message, dict) else None
                    if identifier and identifier == last_id:
                        continue
                    last_id = identifier or last_id
                provider, model = token_context(service, record, context)
                deltas = deltas_of(record)
                if deltas:
                    self._add_tokens(service, provider, model, deltas, occurred, live=False)
        self.offsets[path] = {"offset": size, "last_id": last_id, **context}

    def _scan_tail(self, service: str, path: str, deltas_of, entry: dict) -> None:
        size = os.path.getsize(path)
        offset = entry.get("offset", 0)
        if size < offset:
            offset = 0
            entry["last_id"] = None
        last_id = entry.get("last_id")
        while offset < size:
            lines, offset = read_from_offset(path, offset)
            if not lines:
                break
            for raw in lines:
                try:
                    record = json.loads(raw)
                except json.JSONDecodeError:
                    continue
                if service == "claude_code":
                    message = record.get("message") or {}
                    identifier = message.get("id") if isinstance(message, dict) else None
                    if identifier and identifier == last_id:
                        continue
                    last_id = identifier or last_id
                provider, model = token_context(service, record, entry)
                deltas = deltas_of(record)
                if deltas:
                    self._add_tokens(
                        service, provider, model, deltas,
                        to_epoch(record.get("timestamp")), live=True,
                    )
        entry["offset"] = offset
        entry["last_id"] = last_id
        self.offsets[path] = entry

    # -- transport --------------------------------------------------------
    def otlp_body(self) -> dict:
        metrics: dict[str, dict] = {}
        for point in self.points:
            attributes = [
                {"key": key, "value": {"stringValue": str(value)}}
                for key, value in sorted(point["attrs"].items())
            ]
            value = point["value"]
            if isinstance(value, bool) or not isinstance(value, (int, float)):
                value = float(value)
            if isinstance(value, int) and point["name"] in {
                "quota_resets_at_seconds",
                "quota_observed_at_seconds",
            }:
                state = {"asInt": str(value)}
            else:
                state = {"asDouble": float(value)}
            data_point = dict(state, timeUnixNano=str(int(self.now * 1e9)), attributes=attributes)
            metric = metrics.setdefault(
                point["name"], {"name": point["name"], "gauge": {"dataPoints": []}}
            )
            metric["gauge"]["dataPoints"].append(data_point)

        metrics["collector_errors_total"] = {
            "name": "collector_errors_total",
            "sum": {
                "isMonotonic": True,
                "aggregationTemporality": 2,
                "dataPoints": [
                    {
                        "asInt": str(self.errors.get(source, 0)),
                        "timeUnixNano": str(int(self.now * 1e9)),
                        "attributes": [{"key": "source", "value": {"stringValue": source}}],
                    }
                    for source in SOURCES
                ],
            },
        }

        return {
            "resourceMetrics": [
                {
                    "resource": {
                        "attributes": [
                            {"key": "host.name", "value": {"stringValue": self.host}},
                            {"key": "service.name", "value": {"stringValue": "quota-collector"}},
                        ]
                    },
                    "scopeMetrics": [
                        {
                            "scope": {"name": "quota-collector", "version": "1"},
                            "metrics": list(metrics.values()),
                        }
                    ],
                }
            ]
        }

    def send(self, endpoint: str) -> bool:
        body = json.dumps(self.otlp_body()).encode("utf-8")
        request = urllib.request.Request(
            endpoint,
            data=body,
            headers={"Content-Type": "application/json", "User-Agent": USER_AGENT},
        )
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                response.read()
            self._save_state()
            return True
        except (OSError, urllib.error.URLError) as error:
            log(f"endpoint {endpoint}: {error}")
            return False

    def run_once(self, endpoint: str) -> bool:
        self.now = time.time()
        self.points = []
        for collect in (
            self.collect_claude,
            self.collect_ollama,
            self.collect_opencode,
            self.collect_codex,
            self.collect_tokens,
        ):
            try:
                collect()
            except Exception as error:  # noqa: BLE001 - one source must not stop the rest
                self.fail(collect.__name__.removeprefix("collect_"), error)
        if not (self.points or self.errors):
            return True
        return self.send(endpoint)


def codex_window(minutes) -> str:
    try:
        minutes = float(minutes)
    except (TypeError, ValueError):
        return "weekly"
    for limit, window in CODEX_WINDOWS:
        if minutes <= limit:
            return window
    return "monthly"


def codex_sessions(limit: int, root: str | None = None) -> list[tuple[str, float]]:
    """Return (path, mtime) tuples newest first."""
    root = root or os.path.expanduser("~/.codex/sessions")
    sessions: list[tuple[str, float]] = []
    for directory, _, files in os.walk(root):
        for name in files:
            if not name.endswith(".jsonl"):
                continue
            path = os.path.join(directory, name)
            try:
                sessions.append((path, os.path.getmtime(path)))
            except OSError:
                continue
    sessions.sort(key=lambda entry: entry[1], reverse=True)
    return sessions[:limit]


def read_tail_lines(path: str, max_lines: int, max_bytes: int = 2_000_000) -> list[str]:
    """Read whole lines from the end of a file without loading all of it."""
    with open(path, "rb") as handle:
        handle.seek(0, os.SEEK_END)
        size = handle.tell()
        block = min(size, max_bytes)
        handle.seek(size - block)
        data = handle.read()
    lines = data.splitlines()
    if block < size and lines:
        with open(path, "rb") as handle:
            handle.seek(size - block - 1)
            preceded_by_newline = handle.read(1) == b"\n"
        if not preceded_by_newline:
            lines = lines[1:]
    return [line.decode("utf-8", "replace") for line in lines[-max_lines:]]


def read_from_offset(path: str, offset: int, max_bytes: int = 8_000_000) -> tuple[list[bytes], int]:
    """Read complete lines starting at a byte offset; return them and the new offset."""
    with open(path, "rb") as handle:
        handle.seek(offset)
        data = handle.read(max_bytes)
    if not data:
        return [], offset
    lines = data.split(b"\n")
    partial = lines.pop() if not data.endswith(b"\n") else None
    consumed = len(data) - (len(partial) if partial is not None else 0)
    return lines, offset + consumed


def claude_token_deltas(record: dict) -> dict[str, int] | None:
    """Token usage of one assistant message, keyed by kind."""
    message = record.get("message")
    if not isinstance(message, dict):
        return None
    usage = message.get("usage")
    if not isinstance(usage, dict):
        return None
    return {
        "input": int(usage.get("input_tokens") or 0),
        "output": int(usage.get("output_tokens") or 0),
        "cache_read": int(usage.get("cache_read_input_tokens") or 0),
        "cache_write": int(usage.get("cache_creation_input_tokens") or 0),
    }


def codex_token_deltas(record: dict) -> dict[str, int] | None:
    """Token usage of one Codex turn, keyed by kind."""
    payload = record.get("payload") or {}
    if payload.get("type") != "token_count":
        return None
    usage = (payload.get("info") or {}).get("last_token_usage")
    if not isinstance(usage, dict):
        return None
    cached = int(usage.get("cached_input_tokens") or 0)
    return {
        "input": max(int(usage.get("input_tokens") or 0) - cached, 0),
        "output": int(usage.get("output_tokens") or 0),
        "cache_read": cached,
    }


def token_context(service: str, record: dict, state: dict) -> tuple[str, str]:
    """Provider and model for a log record, updating the running context."""
    if service == "codex":
        payload = record.get("payload") or {}
        if record.get("type") == "session_meta":
            provider = payload.get("model_provider")
            if isinstance(provider, str) and provider:
                state["provider"] = provider
        if record.get("type") == "turn_context":
            model = payload.get("model")
            if isinstance(model, str) and model:
                state["model"] = model
        return state.get("provider") or "openai", state.get("model") or "unknown"
    message = record.get("message")
    if not isinstance(message, dict):
        return "unknown", "unknown"
    if service == "claude_code":
        return "anthropic", message.get("model") or "unknown"
    return message.get("provider") or "unknown", message.get("model") or "unknown"


def pi_token_deltas(record: dict) -> dict[str, int] | None:
    """Token usage of one Pi assistant message, keyed by kind."""
    if record.get("type") != "message":
        return None
    message = record.get("message")
    if not isinstance(message, dict) or message.get("role") != "assistant":
        return None
    usage = message.get("usage")
    if not isinstance(usage, dict):
        return None
    return {
        "input": int(usage.get("input") or 0),
        "output": int(usage.get("output") or 0),
        "cache_read": int(usage.get("cacheRead") or 0),
        "cache_write": int(usage.get("cacheWrite") or 0),
    }


def last_codex_rate_limits(path: str, max_lines: int = 5000) -> dict | None:
    """Return the newest token_count rate limits and its event timestamp."""
    for line in reversed(read_tail_lines(path, max_lines)):
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        payload = record.get("payload") or {}
        if record.get("type") == "event_msg" and payload.get("type") == "token_count":
            rate_limits = payload.get("rate_limits")
            if rate_limits:
                return {
                    "rate_limits": rate_limits,
                    "observed_at": to_epoch(record.get("timestamp")),
                }
    return None


def main(argv: list[str]) -> int:
    endpoint = os.environ.get("QUOTA_ENDPOINT", DEFAULT_ENDPOINT)
    host = os.environ.get("QUOTA_HOST") or os.uname().nodename.split(".")[0]
    interval = int(os.environ.get("QUOTA_INTERVAL", DEFAULT_INTERVAL))
    state_path = os.environ.get("QUOTA_STATE_FILE") or os.path.join(
        os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
        "quota-dashboard",
        "collector-state.json",
    )
    collector = Collector(host, state_path)
    if "--once" in argv:
        return 0 if collector.run_once(endpoint) else 1
    while True:
        collector.run_once(endpoint)
        time.sleep(interval)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
