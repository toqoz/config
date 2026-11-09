#!/usr/bin/env bash
# Launch the built CLI from a fixed generation without changing caller cwd.
set -euo pipefail
umask 077

NODE=${DEEPSEEK_HARNESS_NODE:-@node@}
HOME_DIR=${DEEPSEEK_HARNESS_HOME:-@dataDir@}
export DSH_HOME=${DSH_HOME:-"$HOME_DIR/state"}
READY=$HOME_DIR/ready

if [ ! -e "$READY/apps/cli/lib/bin.js" ]; then
  echo "dsh: no ready build at $READY; run sync.sh --install in the fork checkout first" >&2
  exit 1
fi

READY=$(cd "$READY" && pwd -P)
export PATH="$(dirname "$NODE"):$PATH"
exec "$NODE" "$READY/apps/cli/lib/bin.js" "$@"
