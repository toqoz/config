# quota-dashboard

One Grafana screen for the usage limits of the AI coding subscriptions this
machine can see, plus a single OTel stack (`grafana/otel-lgtm`) that also
receives Claude Code and Codex telemetry.

| Host | Collects | Hosts the stack |
| --- | --- | --- |
| forge01 | yes (posts to `127.0.0.1:4318`) | yes |
| remilis | yes (posts to `forge01:4318`) | no |

Grafana: `https://forge01.<tailnet>.ts.net:3370/` from the tailnet, or
`http://localhost:3370` on forge01 itself. Grafana binds loopback only and the
`quota-grafana-serve` agent publishes it with
`tailscale serve --https=3370`, which uses the tailnet certificate (the tailnet
must have HTTPS enabled). Keep the port in the URL: the tailnet root is shared
with other services instead of being claimed for this one.
`stack.rootUrl` is set to the same URL so Grafana-generated links stay on
HTTPS.
OTLP is on 43180 (HTTP) and 43170 (gRPC); the non-standard host ports keep the
stack clear of other local OTel collectors. Dashboard login is disabled on purpose: the image default
is `admin`/`admin`, which would allow dashboard edits from the local network.
Anonymous access is Viewer only, and dashboards come from this repository via
provisioning. Grafana itself is loopback only, so the HTTPS endpoint is the only way in from
another host. Anonymous Viewer is bigger than it sounds: it can run arbitrary
read queries against every datasource behind Grafana (Prometheus, Loki, Tempo,
Pyroscope), and the OTLP ports 43170/43180 accept writes from the local network.
Treat the whole host as tailnet-only.

## Data sources

All sources are read-only. Nothing refreshes a token.

| Metric source | Where the data comes from | Notes |
| --- | --- | --- |
| `claude_code` | `GET https://api.anthropic.com/api/oauth/usage` with the OAuth token in the login Keychain (`Claude Code-credentials`) | Account level, includes five-hour, weekly, model-scoped weekly, and spend. Polled every 5 minutes because the endpoint rate-limits tighter loops. An expired token is skipped; Claude Code refreshes it on its next run. |
| `codex` | Newest `~/.codex/sessions/**/*.jsonl`, last `token_count` event's `rate_limits` | Scans sessions newest-first until one has `rate_limits`. Observation time is the event's own `timestamp` (file mtime as fallback). |
| `ollama_cloud` | Local Ollama server: `/api/balance` | The server holds the cloud login, so no API key is needed. |
| `opencode_go` | `GET https://opencode.ai/inference/go/v1/usage` with the `opencode-go` key from `~/.pi/agent/auth.json` | `rolling` / `weekly` / `monthly` percentages and reset times. |
| `tokens` | Claude Code `~/.claude/projects/**/*.jsonl`, Codex `~/.codex/sessions/**/*.jsonl`, Pi `~/.pi/agent/sessions/**/*.jsonl` | Tokens are counted from each log once, tracked by byte offset. Claude repeats every assistant message twice; the duplicate id is skipped. Pi is counted under `service="pi"` whatever provider it called. |

Grok Build is intentionally not collected yet.

## Metrics

Gauges, all carrying `host_name` (OTel resource `host.name`) and
`service_name = quota-collector`:

| Metric | Labels | Meaning |
| --- | --- | --- |
| `quota_used_percent` | `service`, `window`, optional `scope` | Used percentage (0–100) |
| `quota_resets_at_seconds` | `service`, `window`, optional `scope` | Reset time (Unix seconds) |
| `quota_observed_at_seconds` | `service`, `window`, optional `scope` | When the source was last read |
| `quota_window_seconds` | `service`, `window`, optional `scope` | Nominal length of the window, so usage can be compared with elapsed time |
| `quota_used_usd`, `quota_limit_usd` | `service`, `window` | Money-based windows |
| `credit_balance_usd` | `service` | Purchased credit balance |
| `tokens_window_total` | `service`, `provider`, `model`, `window` | Tokens in the last 24h (`1d`) or 7d (`7d`), computed from hourly buckets |
| `tokens_total` | `service`, `provider`, `model`, `kind` | Monotonic counter since the collector started, used for the hourly chart |
| `collector_errors_total` | `source` | Cumulative read failures per source; persisted in `~/.local/state/quota-dashboard/collector-state.json` so a restart does not reset the counter |

`window` is one of `5h`, `weekly`, `monthly`, `spend`.

**Quotas are not summed across hosts.** They are account level, so the
dashboard uses `max by (...)`. Token/cost counters from OTel are per host and
can be summed, which is why `host_name` is always attached.

## API

`quota-api` answers a single JSON snapshot for scripts and agents:

```sh
curl -s https://forge01.<tailnet>.ts.net:3371/quota | jq .
```

```json
{
  "generated_at": "2026-11-25T00:01:27Z",
  "quotas": [
    {"service": "claude_code", "window": "weekly", "scope": null,
     "used_percent": 4.0, "resets_at": 1795820399,
     "elapsed_percent": 57.8, "overage_points": -53.8, "age_seconds": 59}
  ],
  "tokens": {"windows": ["1d", "7d"],
             "rows": [{"service": "pi", "provider": "opencode-go",
                       "model": "deepseek-v4.1-flash", "tokens_1d": 5535507,
                       "tokens_7d": 77587907}]}
}
```

It reuses the dashboard's rules (account-level maximum across hosts, six-hour
freshness cut-off, `elapsed_percent` from the window length). Prometheus is
published on `127.0.0.1:9090` for it, and the API is loopback-only plus
`tailscale serve --https=3371`.

## Dashboard panels

1. One table per service/window: usage as a bar, the points by which usage is ahead of the elapsed window (`超過`; positive means burning faster than the clock), the countdown, the absolute reset time, and how long ago the data was observed. Rows are sorted by service, window, and scope, never by value, so the order does not jump between refreshes.
2. Trends: weekly and five-hour usage.
3. Token totals for the last 24h and 7d, a breakdown table by tool, provider and model, and an hourly chart.
4. Health: collection errors per source.

## Tokens

Claude Code, Codex, and Pi write per-request token counts to their own JSONL
logs.
The collector reads only the bytes it has not seen yet, keyed by file offset in
the state file, and stores hourly buckets for the last eight days.

On first sight of a file it counts up to a week of history, so the 24h/7d
numbers are populated from the start. A brand-new file starts at its end.

Each record is attributed to a provider and model: Claude messages carry it in
`message.model` (provider `anthropic`), Codex takes the provider from
`session_meta` and the model from the latest `turn_context`, and Pi messages
carry both. The dashboard sums the per-host series by service/provider/model,
so the breakdown covers both machines.

Window sums are computed in the collector rather than with `increase()`:
PromQL extrapolates to the requested range, which inflates a 24h sum when only
minutes of samples exist. The hourly chart does use the counter, so its first
hour is sparse.

## Operating

- The collector runs from launchd (`quota-collector`) in the `gui` domain so it
  can read the login Keychain, and loops every 60 s.
- The stack agent (`quota-otel-lgtm`, forge01 only) waits for OrbStack's Docker
  socket, then runs `docker compose up -d`. `restart: unless-stopped` brings the
  container back after an OrbStack restart.
- Data lives in `~/.local/share/quota-dashboard/data` (mounted at `/data`) with
  90-day Prometheus retention. Removing that directory deletes history.
- The image tag is pinned in `my.quotaDashboard.stack.image`; bump it
  deliberately.
- Dashboards are provisioned from `dashboards/dashboard.json` (
  `provider.yaml` registers the folder). UI edits are not persisted.

### Manual check

```sh
# Collect once and print nothing on success (non-zero if the POST fails)
QUOTA_ENDPOINT=http://forge01:43180/v1/metrics QUOTA_HOST=remilis \
  python3 home/quota-dashboard/collector.py --once

# Inspect what arrived (run on forge01)
curl -s --get http://localhost:3370/api/datasources/uid/prometheus/resources/api/v1/query \
  --data-urlencode 'query=max by (service, window) (quota_used_percent)'
```

## Known gaps

- Codex and Claude Code request logs may be pruned by the tools themselves;
  token counts only cover what is still on disk (up to a week).
- Token counts are tokens processed, so cached input is counted each turn and
  totals are much larger than billable tokens. `CLAUDE_CODE_ENABLE_TELEMETRY`
  plus cumulative temporality and Codex's `[otel]` tables are the next step.
- The Claude OAuth usage endpoint and the OpenCode Go usage endpoint are not
  documented public APIs; a change on their side shows up as a stale value and
  a rising `collector_errors_total`.
- OpenCode's endpoint sits behind a bot filter that rejects urllib's default
  User-Agent, so the collector sends its own.
- Monthly window length is assumed to be 30 days except for Ollama, which
  reports its billing period, so a monthly pace can be a day or two off.
