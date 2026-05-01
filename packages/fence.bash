#!/usr/bin/env bash
# Wrap `fence` so any caller — interactive shell, scripts, or compiled
# binaries (e.g. `sence`) — gets the workspace allowWrite paths injected
# into the fence policy. The wrapper always seeds '.', and when the CWD
# is inside a git work tree it additionally seeds --git-dir and
# --git-common-dir; in a worktree those point outside the worktree's
# CWD and templates like `code` scope writes to the workspace tree, so
# ordinary git operations (commit, branch, fetch) would otherwise fail
# under fence. Outside any git repo the wrapper still works — only '.'
# is seeded.
#
# This wrapper aligns with fence's real CLI rather than wrapping it. It
# only inspects two flags:
#
#   --settings <path>   Existing fence settings file. The wrapper reads
#                       it, appends the seed paths to
#                       .filesystem.allowWrite (deduped), writes a tmp
#                       file, and substitutes that path in the call.
#   --template <name>   Used as the `extends:` target when the wrapper
#                       has to synthesize a fresh settings file. Also
#                       forwarded to fence verbatim. Defaults to "code".
#
# Every other argument — including unknown flags such as `-m`,
# `--fence-log-file`, and the `--` inner-command separator — passes
# through to fence unchanged. This keeps the wrapper composable with
# callers like `sence` that drive fence with a richer argv.
set -euo pipefail

die() { echo "fence: $*" >&2; exit 2; }

settings_in=""
have_settings=false
template="code"
forwarded=()

while (( $# )); do
  case "$1" in
    --settings)
      (( $# >= 2 )) || die "missing value for --settings"
      settings_in=$2
      have_settings=true
      shift 2
      ;;
    --template)
      (( $# >= 2 )) || die "missing value for --template"
      template=$2
      forwarded+=("$1" "$2")
      shift 2
      ;;
    --)
      forwarded+=("$@")
      break
      ;;
    *)
      forwarded+=("$1")
      shift
      ;;
  esac
done

seeds=(".")
if git rev-parse --git-dir >/dev/null 2>&1; then
  seeds+=(
    "$(cd "$(git rev-parse --git-dir)" && pwd)"
    "$(cd "$(git rev-parse --git-common-dir)" && pwd)"
  )
fi
seeds_json=$(printf '%s\n' "${seeds[@]}" | jq -R . | jq -sc .)

tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT

if $have_settings; then
  [[ -r $settings_in ]] || die "settings file not readable: $settings_in"
  jq \
    --argjson seeds "$seeds_json" \
    '.filesystem //= {}
     | .filesystem.allowWrite = (((.filesystem.allowWrite // []) + $seeds) | unique)' \
    "$settings_in" > "$tmp"
else
  jq -nc \
    --arg t "$template" \
    --argjson seeds "$seeds_json" \
    '{extends: $t, filesystem: {allowWrite: ($seeds | unique)}}' \
    > "$tmp"
fi

exec "${FENCE_BIN:-fence}" --settings "$tmp" ${forwarded[@]+"${forwarded[@]}"}
