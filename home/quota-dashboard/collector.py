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


class Collector:
    def __init__(self, host: str, state_path: str | None = None) -> None:
        self.host = host
        self.state_path = state_path
        self.points: list[dict] = []
        self.errors: dict[str, int] = {}
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
                stored = json.load(handle).get("errors") or {}
        except (OSError, ValueError):
            return
        for source, count in stored.items():
            if isinstance(count, int) and count >= 0:
                self.errors[source] = count

    def _save_state(self) -> None:
        if not self.state_path:
            return
        try:
            directory = os.path.dirname(self.state_path)
            if directory:
                os.makedirs(directory, mode=0o700, exist_ok=True)
            temporary = f"{self.state_path}.tmp"
            with open(temporary, "w", encoding="utf-8") as handle:
                json.dump({"errors": self.errors}, handle)
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
