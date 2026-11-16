# quota-dashboard

One Grafana screen for the usage limits of the AI coding subscriptions this
machine can see, plus a single OTel stack (`grafana/otel-lgtm`) that also
receives Claude Code and Codex telemetry.

| Host | Collects | Hosts the stack |
| --- | --- | --- |
| forge01 | yes (posts to `127.0.0.1:4318`) | yes |
| remilis | yes (posts to `forge01:4318`) | no |

Grafana: `http://forge01:3000` from the tailnet, or `http://localhost:3000`
on forge01 itself. Dashboard login is disabled on purpose: the image default
is `admin`/`admin`, which would allow dashboard edits from the local network.
Anonymous access is Viewer only, and dashboards come from this repository via
provisioning. Reachable hosts are whatever can route to forge01, so keep 3000 off the public
internet. Anonymous Viewer is bigger than it sounds: it can run arbitrary read
queries against every datasource behind Grafana (Prometheus, Loki, Tempo,
Pyroscope), and the OTLP ports 4317/4318 accept writes from the same network.
Treat the whole host as tailnet-only.

## Data sources

All sources are read-only. Nothing refreshes a token.

| Metric source | Where the data comes from | Notes |
| --- | --- | --- |
| `claude_code` | `GET https://api.anthropic.com/api/oauth/usage` with the OAuth token in the login Keychain (`Claude Code-credentials`) | Account level, includes five-hour, weekly, model-scoped weekly, and spend. An expired token is skipped; Claude Code refreshes it on its next run. |
| `codex` | Newest `~/.codex/sessions/**/*.jsonl`, last `token_count` event's `rate_limits` | Scans sessions newest-first until one has `rate_limits`. Observation time is the event's own `timestamp` (file mtime as fallback). |
| `ollama_cloud` | Local Ollama server: `/api/usage?range=24h` and `/api/balance` | The server holds the cloud login, so no API key is needed. |
| `opencode_go` | `GET https://opencode.ai/inference/go/v1/usage` with the `opencode-go` key from `~/.pi/agent/auth.json` | `rolling` / `weekly` / `monthly` percentages and reset times. |

Grok Build is intentionally not collected yet.

## Metrics

Gauges, all carrying `host_name` (OTel resource `host.name`) and
`service_name = quota-collector`:

| Metric | Labels | Meaning |
| --- | --- | --- |
| `quota_used_percent` | `service`, `window`, optional `scope` | Used percentage (0–100) |
| `quota_resets_at_seconds` | `service`, `window`, optional `scope` | Reset time (Unix seconds) |
| `quota_observed_at_seconds` | `service`, `window`, optional `scope` | When the source was last read |
| `quota_used_usd`, `quota_limit_usd` | `service`, `window` | Money-based windows |
| `credit_balance_usd` | `service` | Purchased credit balance |
| `usage_window_usd` | `service`, `window` | Ollama `usage_usd` for the rolling 24h window |
| `collector_errors_total` | `source` | Cumulative read failures per source; persisted in `~/.local/state/quota-dashboard/collector-state.json` so a restart does not reset the counter |

`window` is one of `5h`, `weekly`, `monthly`, `spend`.

**Quotas are not summed across hosts.** They are account level, so the
dashboard uses `max by (...)`. Token/cost counters from OTel are per host and
can be summed, which is why `host_name` is always attached.

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
QUOTA_ENDPOINT=http://forge01:4318/v1/metrics QUOTA_HOST=remilis \
  python3 home/quota-dashboard/collector.py --once

# Inspect what arrived (run on forge01)
curl -s --get http://localhost:3000/api/datasources/uid/prometheus/resources/api/v1/query \
  --data-urlencode 'query=max by (service, window) (quota_used_percent)'
```

## Known gaps

- Claude Code and Codex token/cost telemetry is not wired up yet, so the usage
  panels only cover Ollama's money-based usage. `CLAUDE_CODE_ENABLE_TELEMETRY`
  plus cumulative temporality and Codex's `[otel]` tables are the next step.
- The Claude OAuth usage endpoint and the OpenCode Go usage endpoint are not
  documented public APIs; a change on their side shows up as a stale value and
  a rising `collector_errors_total`.
- OpenCode's endpoint sits behind a bot filter that rejects urllib's default
  User-Agent, so the collector sends its own.
