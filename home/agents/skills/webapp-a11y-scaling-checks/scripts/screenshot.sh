#!/usr/bin/env bash
# One-shot: boot emulator if needed, apply max a11y settings, open URL in
# Chrome, capture a device screenshot, and print the output path.
#
# Usage:
#   screenshot.sh [--physical] <url> [out.png]
#
# With --physical, use the single connected physical Android device
# instead of booting the dedicated emulator. Physical-device mode restores
# the original density and font_scale after capture.

set -euo pipefail

PHYSICAL=0
if [ "${1:-}" = "--physical" ]; then
  PHYSICAL=1
  shift
fi

URL="${1:?url required}"
OUT="${2:-/tmp/webapp-a11y-screenshot.png}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=sdkenv.sh
source "$SCRIPT_DIR/sdkenv.sh"

mkdir -p "$(dirname "$OUT")"

# Default Chrome app-locale for this one-shot path. The launcher does
# not pick a default — wrappers do. Override by exporting CHROME_LOCALE
# before invoking this script (set to '' to opt out of the override).
export CHROME_LOCALE="${CHROME_LOCALE-ja-JP}"

ORIGINAL_FONT_SCALE=""
ORIGINAL_DENSITY_OVERRIDE=""
ORIGINAL_DENSITY_PHYSICAL=""

restore_physical_settings() {
  [ "$PHYSICAL" = 1 ] || return 0
  [ -n "${SERIAL:-}" ] || return 0

  if [ -n "$ORIGINAL_FONT_SCALE" ] && [ "$ORIGINAL_FONT_SCALE" != "null" ]; then
    adb -s "$SERIAL" shell settings put system font_scale "$ORIGINAL_FONT_SCALE" >/dev/null 2>&1 || true
  else
    adb -s "$SERIAL" shell settings delete system font_scale >/dev/null 2>&1 || true
  fi

  if [ -n "$ORIGINAL_DENSITY_OVERRIDE" ]; then
    adb -s "$SERIAL" shell wm density "$ORIGINAL_DENSITY_OVERRIDE" >/dev/null 2>&1 || true
  else
    adb -s "$SERIAL" shell wm density reset >/dev/null 2>&1 || true
  fi
}
trap restore_physical_settings EXIT

if [ "$PHYSICAL" = 1 ]; then
  SERIAL=$("$SCRIPT_DIR/select_physical_device.sh")
  density_before=$(adb -s "$SERIAL" shell wm density 2>/dev/null | tr -d '\r')
  ORIGINAL_DENSITY_PHYSICAL=$(awk -F': ' '/Physical density/{print $2}' <<<"$density_before")
  ORIGINAL_DENSITY_OVERRIDE=$(awk -F': ' '/Override density/{print $2}' <<<"$density_before")
  ORIGINAL_FONT_SCALE=$(adb -s "$SERIAL" shell settings get system font_scale 2>/dev/null | tr -d '\r')

  "$SCRIPT_DIR/apply_a11y.sh" "$SERIAL" >&2
  "$SCRIPT_DIR/launch_chrome.sh" "$SERIAL" "$URL"
else
  SERIAL=$("$SCRIPT_DIR/boot_emulator.sh")
  # Clear any stale density override so FRE dialogs remain easy to dismiss.
  "$SCRIPT_DIR/apply_a11y.sh" "$SERIAL" --reset >&2
  "$SCRIPT_DIR/launch_chrome.sh" "$SERIAL" "$URL"
  # Apply a11y after FRE is cleared, then re-launch so the page picks up
  # the new density/font scale.
  "$SCRIPT_DIR/apply_a11y.sh" "$SERIAL" >&2
  "$SCRIPT_DIR/launch_chrome.sh" "$SERIAL" "$URL"
fi

# `adb shell screencap` captures what a user actually sees — unlike the
# CDP full-page screenshot, which tiles pathologically on Android Chrome
# (`Page.captureScreenshot` with `captureBeyondViewport`).
adb -s "$SERIAL" shell screencap -p > "$OUT"

# Sidecar with the inputs needed to re-derive this shot. Cheap
# reproducibility / audit trail: paired by filename so callers can do
# `for png in *.png; do jq . "${png}.json"; done`.
density=$(adb -s "$SERIAL" shell wm density 2>/dev/null \
          | awk -F': ' '
              /Override density/{o=$2}
              /Physical density/{p=$2}
              END{print (o!="") ? o : p}' \
          | tr -d '\r')
font_scale=$(adb -s "$SERIAL" shell settings get system font_scale 2>/dev/null | tr -d '\r')
jq -n \
  --arg url           "$URL" \
  --arg out           "$OUT" \
  --arg ts            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg serial        "$SERIAL" \
  --arg density       "${density:-unknown}" \
  --arg font_scale    "${font_scale:-unknown}" \
  --arg chrome_locale "${CHROME_LOCALE-<unset>}" \
  --arg system_image  "${ANDROID_SYSTEM_IMAGE:-<unset>}" \
  --arg device_kind   "$([ "$PHYSICAL" = 1 ] && echo physical || echo emulator)" \
  --arg original_density_physical "${ORIGINAL_DENSITY_PHYSICAL:-}" \
  --arg original_density_override "${ORIGINAL_DENSITY_OVERRIDE:-}" \
  --arg original_font_scale "${ORIGINAL_FONT_SCALE:-}" \
  '{url: $url, out: $out, ts: $ts, serial: $serial,
    device_kind: $device_kind,
    density: $density, font_scale: $font_scale,
    chrome_locale: $chrome_locale, system_image: $system_image,
    original_density_physical: $original_density_physical,
    original_density_override: $original_density_override,
    original_font_scale: $original_font_scale}' \
  > "${OUT}.json"

echo "$OUT"
