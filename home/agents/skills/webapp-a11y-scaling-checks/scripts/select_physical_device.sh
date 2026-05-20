#!/usr/bin/env bash
# Print the serial for a connected physical Android device.
# Fails if none or more than one physical device is available.

set -euo pipefail

if [ -n "${ANDROID_SERIAL:-}" ] && [[ "$ANDROID_SERIAL" != emulator-* ]]; then
  echo "$ANDROID_SERIAL"
  exit 0
fi

mapfile -t devices < <(
  adb devices | awk 'NR > 1 && $2 == "device" {print $1}' | grep -v '^emulator-' || true
)

case "${#devices[@]}" in
  0)
    echo "select_physical_device: no authorized physical device found (check adb devices)." >&2
    exit 1
    ;;
  1)
    echo "${devices[0]}"
    ;;
  *)
    echo "select_physical_device: multiple physical devices found; set ANDROID_SERIAL to choose one:" >&2
    printf '  %s\n' "${devices[@]}" >&2
    exit 1
    ;;
esac
