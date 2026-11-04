#!/bin/bash
set -euo pipefail
umask 077

PORT=@port@
export DEEPSEEK_HARNESS_HOME="@dataDir@"
export DSH_HOME=${DSH_HOME:-"$DEEPSEEK_HARNESS_HOME/state"}
host_port=$("@tailscaleServe@" "$PORT")
exec "$(dirname "$0")/dsh" web --no-open --host 127.0.0.1 --port "$PORT" \
  --public-url "https://$host_port/" --trusted-host "$host_port"
