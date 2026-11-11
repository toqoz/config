#!/usr/bin/env bash
# Applies the DS Bot fork to the DSH profile the running app loads.
#
# The morning import runs inside a Bot sandbox, which cannot write the profile it
# runs from: the profile sits under the DSH data root, and DS Bot refuses to grant
# a Bot write access there. The Bot therefore leaves a marker inside its own
# checkout, and this helper runs from launchd, outside that sandbox, where the
# profile and launchd itself are writable.
#
# A failed apply keeps the marker, so the next interval retries it and the log
# shows what the Bot could not do itself. Nothing runs while the marker is absent.
set -uo pipefail

checkout=${DS_BOT_APPLY_CHECKOUT:-$HOME/src/github.com/toqoz/DS-Bot}
marker=${DS_BOT_APPLY_MARKER:-$checkout/.agents/state/apply-pending}
restart=${DS_BOT_APPLY_RESTART:-launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.deepseek-harness"}

[ -e "$marker" ] || exit 0

printf '=== %s applying %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$marker"

cd "$checkout" || exit 0
if ! output=$(bash .git/wt/ops/.agents/skills/ds-bot-personal-fork/scripts/apply.sh 2>&1); then
  printf '%s\n' "$output"
  echo "apply failed; keeping the marker for the next interval"
  exit 1
fi
printf '%s\n' "$output"

# Only a release change needs the restart: a reload picks up the browser half,
# while a loaded plugin keeps the host half it started with.
case "$output" in
  *"upgraded the profile to ds-bot"*)
    echo "restarting DSH to load the new release"
    if ! eval "$restart"; then
      echo "restart failed; keeping the marker for the next interval"
      exit 1
    fi
    ;;
esac

rm -f "$marker"
echo "applied"
