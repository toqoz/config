#!/usr/bin/env python3
"""Read-only JSON snapshot of subscription quota usage.

The Grafana dashboard answers the same questions with PromQL, but a fixed
shape is easier to consume from a script or another agent. Everything here is
derived from the Prometheus that ships inside otel-lgtm.
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DEFAULT_PROMETHEUS = "http://127.0.0.1:9090"
DEFAULT_PORT = 3371
FRESH_SECONDS = 21600

# Same freshness rule as the dashboard: ignore observations older than six
# hours before picking the per-window maximum across hosts.
FRESH = (
    "and on (host_name, service, window, scope) "
    f"(time() - last_over_time(quota_observed_at_seconds[7d]) < {FRESH_SECONDS})"
)


def prometheus_query(base: str, query: str, timeout: float = 10) -> list[dict]:
    url = f"{base.rstrip('/')}/api/v1/query?" + urllib.parse.urlencode({"query": query})
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        payload = json.loads(response.read().decode("utf-8"))
    if payload.get("status") != "success":
        raise RuntimeError(f"prometheus error: {payload.get('error')}")
    return payload["data"]["result"]


def series_key(metric: dict) -> tuple[str, str, str]:
    return (
        metric.get("service", ""),
        metric.get("window", ""),
        metric.get("scope", ""),
    )


def as_vectors(result: list[dict]) -> dict[tuple[str, str, str], float]:
    vectors: dict[tuple[str, str, str], float] = {}
    for entry in result:
        try:
            vectors[series_key(entry["metric"])] = float(entry["value"][1])
        except (KeyError, IndexError, TypeError, ValueError):
            continue
    return vectors


def build_quotas(
    used: dict[tuple[str, str, str], float],
    resets: dict[tuple[str, str, str], float],
    observed: dict[tuple[str, str, str], float],
    windows: dict[tuple[str, str, str], float],
    now: float,
) -> list[dict]:
    quotas = []
    for key, used_percent in used.items():
        service, window, scope = key
        resets_at = resets.get(key)
        window_seconds = windows.get(key)
        elapsed_percent = None
        overage_points = None
        if resets_at is not None and window_seconds:
            remaining = max(resets_at - now, 0)
            elapsed_percent = max(0.0, min(100.0, (window_seconds - remaining) / window_seconds * 100))
            overage_points = round(used_percent - elapsed_percent, 1)
            elapsed_percent = round(elapsed_percent, 1)
        quotas.append(
            {
                "service": service,
                "window": window,
                "scope": scope or None,
                "used_percent": round(used_percent, 1),
                "resets_at": int(resets_at) if resets_at is not None else None,
                "elapsed_percent": elapsed_percent,
                "overage_points": overage_points,
                "age_seconds": int(observed[key]) if key in observed else None,
            }
        )
    quotas.sort(key=lambda entry: (entry["service"], entry["window"], entry["scope"] or ""))
    return quotas


def build_tokens(day: list[dict], week: list[dict]) -> list[dict]:
    def totals(result: list[dict]) -> dict[tuple[str, str, str], float]:
        sums: dict[tuple[str, str, str], float] = {}
        for entry in result:
            metric = entry["metric"]
            key = (
                metric.get("service", ""),
                metric.get("provider", ""),
                metric.get("model", ""),
            )
            try:
                sums[key] = sums.get(key, 0.0) + float(entry["value"][1])
            except (KeyError, IndexError, TypeError, ValueError):
                continue
        return sums

    day_totals, week_totals = totals(day), totals(week)
    rows = []
    for key in set(day_totals) | set(week_totals):
        service, provider, model = key
        rows.append(
            {
                "service": service,
                "provider": provider,
                "model": model,
                "tokens_1d": int(day_totals.get(key, 0)),
                "tokens_7d": int(week_totals.get(key, 0)),
            }
        )
    rows.sort(key=lambda row: (-row["tokens_7d"], row["service"], row["provider"], row["model"]))
    return rows


def collect(prometheus: str, now: float | None = None) -> dict:
    now = time.time() if now is None else now

    def query(expression: str) -> list[dict]:
        return prometheus_query(prometheus, expression)

    used = as_vectors(query(f"max by (service, window, scope) (last_over_time(quota_used_percent[7d]) {FRESH})"))
    resets = as_vectors(
        query(f"max by (service, window, scope) (last_over_time(quota_resets_at_seconds[7d]) {FRESH})")
    )
    observed = as_vectors(
        query("time() - max by (service, window, scope) (last_over_time(quota_observed_at_seconds[7d]))")
    )
    windows = as_vectors(
        query(f"max by (service, window, scope) (last_over_time(quota_window_seconds[7d]) {FRESH})")
    )
    day = query('sum by (service, provider, model) (tokens_window_total{window="1d"})')
    week = query('sum by (service, provider, model) (tokens_window_total{window="7d"})')

    return {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
        "quotas": build_quotas(used, resets, observed, windows, now),
        "tokens": {"windows": ["1d", "7d"], "rows": build_tokens(day, week)},
    }


class Handler(BaseHTTPRequestHandler):
    prometheus = DEFAULT_PROMETHEUS
    server_version = "quota-api/1"

    def do_GET(self) -> None:  # noqa: N802 - http.server API
        if self.path.split("?")[0] != "/quota":
            self.send_error(404)
            return
        try:
            body = json.dumps(collect(self.prometheus), ensure_ascii=False).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except (OSError, RuntimeError, urllib.error.URLError, ValueError) as error:
            payload = json.dumps({"error": str(error)}).encode("utf-8")
            self.send_response(502)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

    def do_HEAD(self) -> None:  # noqa: N802 - http.server API
        self.do_GET()

    def log_message(self, format: str, *args) -> None:
        print(f"{self.address_string()} {format % args}", file=sys.stderr, flush=True)


def main() -> int:
    port = int(os.environ.get("QUOTA_API_PORT", DEFAULT_PORT))
    Handler.prometheus = os.environ.get("QUOTA_PROMETHEUS_URL", DEFAULT_PROMETHEUS)
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"quota-api listening on 127.0.0.1:{port}", file=sys.stderr, flush=True)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
