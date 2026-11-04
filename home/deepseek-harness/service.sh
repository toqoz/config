#!/bin/bash
set -euo pipefail
umask 077

TAILSCALE="@tailscale@"
JQ="@jq@"
PORT=@port@
export DEEPSEEK_HARNESS_HOME="@dataDir@"
export DSH_HOME=${DSH_HOME:-"$DEEPSEEK_HARNESS_HOME/state"}
BACKEND="http://127.0.0.1:$PORT"

fail() {
  echo "deepseek-harness-service: $*" >&2
  exit 1
}

# launchd retries startup after Tailscale login or connectivity recovers.
status=$("$TAILSCALE" status --json) || fail "Tailscale status unavailable"
dns=$(printf '%s' "$status" | "$JQ" -ers '
  select(length == 1) | .[0]
  | select(.BackendState == "Running") | .Self.DNSName
  | select(type == "string") | rtrimstr(".")
  | select(length <= 253)
  | select(test("\\A[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+\\z"))
') || fail "Tailscale must be Running with a valid Self.DNSName"
host_port="$dns:$PORT"

serve=$("$TAILSCALE" serve status --json) || fail "cannot inspect Tailscale Serve configuration"
printf '%s' "$serve" | "$JQ" -es --arg port "$PORT" --arg host "$host_port" --arg backend "$BACKEND" '
  def on_port: to_entries | map(select(.key | endswith(":" + $port)));
  def unused:
    ((.TCP // {} | has($port)) | not)
    and ((.Web // {} | on_port | length) == 0)
    and ((.AllowFunnel // {} | on_port | length) == 0);
  def same_proxy:
    .TCP[$port] == {HTTPS: true}
    and ((.Web // {} | on_port) == [{key: $host, value: {Handlers: {"/": {Proxy: $backend}}}}])
    and (.AllowFunnel // {} | on_port | all(.value == false));
  length == 1 and (.[0] |
  type == "object"
  and (unused or same_proxy)
  and (.Foreground // {} | all(.[]; unused)))
' >/dev/null || fail "Serve port $PORT is occupied or its configuration is invalid; refusing to change it"

"$TAILSCALE" serve --bg --yes --https="$PORT" "$BACKEND" || fail "could not configure Tailscale HTTPS Serve"
exec "$(dirname "$0")/dsh" web --no-open --host 127.0.0.1 --port "$PORT" \
  --public-url "https://$host_port/" --trusted-host "$host_port"
