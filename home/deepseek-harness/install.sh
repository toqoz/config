#!/usr/bin/env bash
# Keep completed generations intact; publish only after a successful build.
# pnpm inherits the user's registry and minimumReleaseAge policy.
set -euo pipefail
umask 077

REPO_URL="@url@"
REV="@rev@"
VERSION="@version@"
CLI_ENTRY=apps/cli/lib/bin.js

GIT=${DEEPSEEK_HARNESS_GIT:-@git@}
NODE=${DEEPSEEK_HARNESS_NODE:-@node@}
PNPM=${DEEPSEEK_HARNESS_PNPM:-@pnpm@}

HOME_DIR=${DEEPSEEK_HARNESS_HOME:-@dataDir@}
BUILDS=$HOME_DIR/builds
READY=$HOME_DIR/ready

fail() {
  echo "deepseek-harness-install: $*" >&2
  exit 1
}

attempt=
cleanup() {
  if [ -n "$attempt" ] && [ -d "$attempt" ]; then
    rm -rf "$attempt"
    echo "deepseek-harness-install: failed; removed the attempt, prior ready build untouched" >&2
  fi
}
trap cleanup EXIT

# Fast path: the pinned revision is already the published build.
if [ -L "$READY" ] && [ -d "$READY" ] && [ "$(cat "$READY/.dsh-rev" 2>/dev/null || true)" = "$REV" ]; then
  echo "deepseek-harness $VERSION ($REV) is already installed"
  trap - EXIT
  exit 0
fi

if [ -e "$READY" ] && [ ! -L "$READY" ]; then
  fail "$READY exists and is not a symlink; refusing to replace it"
fi

mkdir -p "$HOME_DIR"
attempt=$(mktemp -d "$HOME_DIR/attempt.XXXXXXXX")
echo "==> cloning $REPO_URL at $REV"
"$GIT" clone --filter=blob:none --no-checkout "$REPO_URL" "$attempt"
"$GIT" -C "$attempt" checkout --detach "$REV"
[ "$("$GIT" -C "$attempt" rev-parse HEAD)" = "$REV" ] || fail "checkout did not converge onto $REV"

# Build scripts resolve node and node_modules/.bin via PATH.
PATH=$(dirname "$NODE"):$PATH
export PATH

echo "==> pnpm install --frozen-lockfile"
(
  cd "$attempt"
  "$PNPM" install --frozen-lockfile
  echo "==> pnpm run build"
  "$PNPM" run build
)

echo "==> smoke: built CLI --version and web --help"
smoke=$("$NODE" "$attempt/$CLI_ENTRY" --version) || fail "built CLI failed"
case $smoke in
  *"$VERSION"*) ;;
  *) fail "source launch reported '$smoke', expected version $VERSION" ;;
esac
DSH_HOME="$attempt/.smoke-home" "$NODE" "$attempt/$CLI_ENTRY" web --help >/dev/null || fail "Web profile failed to boot"
rm -rf "$attempt/.smoke-home"

echo "==> publishing $VERSION"
mkdir -p "$BUILDS"
build_id=$VERSION-$(date -u +%Y%m%d%H%M%S)-$$
echo "$REV" > "$attempt/.dsh-rev"
mv "$attempt" "$BUILDS/$build_id"
attempt=
ln -s "builds/$build_id" "$READY.new.$$"
"$NODE" -e 'require("node:fs").renameSync(process.argv[1], process.argv[2])' "$READY.new.$$" "$READY"

trap - EXIT
echo "deepseek-harness $VERSION installed at $READY; run 'dsh web' to start the Web UI"
