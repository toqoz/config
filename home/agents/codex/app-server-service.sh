#!/bin/bash
set -euo pipefail
umask 077

host_port=$("@tailscaleServe@" @port@)
printf 'wss://%s/\n' "$host_port"
exec "@codex@" app-server --listen ws://127.0.0.1:@port@ \
  --ws-auth capability-token --ws-token-file "@tokenFile@"
