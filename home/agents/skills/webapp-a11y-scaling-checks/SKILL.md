---
name: webapp-a11y-scaling-checks
description: Verify how a webapp renders on a real Android Chrome instance with Display Size and Font Size accessibility settings turned up to maximum. Boots a dedicated Pixel 4a-class Android emulator, applies the a11y settings via `adb`, opens Chrome at a target URL, and captures the screen — or hands the live page to `agent-browser` over CDP for interactive snapshot/click/fill flows. Use this when ground-truth Android Chrome a11y rendering is needed.
allowed-tools: Bash(agent-browser:*), Bash(adb:*), Bash(emulator:*), Bash(curl:*), Bash(jq:*)
---

# Webapp A11y Scaling Checks (Android, Real Chrome)

Verify a webapp's mobile rendering inside the real Android Chrome browser
on an emulator that has **Display Size set to maximum** and **Font Size
set to maximum** — i.e. the worst-realistic accessibility scaling a real
user might pick.

## When to use

- Confirming that a webapp's mobile layout survives max Display Size +
  max Font Size on Android Chrome.
- Visual regression on real Android Chrome (not desktop emulation).
- Reproducing a11y bugs reported on Android.

## When NOT to use

- iOS Safari behavior → out of scope, would need an iOS Simulator skill.
- Driving anything other than a webapp inside Chrome (Android-native UI,
  WebView in custom app, …).

## Skill Dependencies

This skill drives the live page through `agent-browser`'s CDP session.
The dependency lives outside this repo:

- [`agent-browser`](https://github.com/vercel-labs/agent-browser/tree/main/skills/agent-browser)
  — fast browser automation over CDP. Used in the Interactive flow for
  `snapshot`, `click`, `fill`, and `screenshot`. Run
  `agent-browser skills get core` once per machine to fetch its full
  syntax reference.

## Prerequisites

- An **Android SDK** discoverable by `scripts/sdkenv.sh`. It tries, in
  order:
  1. `$ANDROID_HOME` / `$ANDROID_SDK_ROOT`,
  2. Android Studio defaults (`~/Library/Android/sdk` on macOS,
     `~/Android/Sdk` on Linux),
  3. android-nixpkgs at `~/.local/share/android`.
  If none match, the scripts print install instructions (install Android
  Studio and complete its setup wizard).
- Inside the resolved SDK, **at least one** of each: a system-image
  (`google_apis_playstore` + host ABI), a `build-tools/*`, and a
  `platforms/android-*`. `sdkenv.sh` auto-detects the host ABI
  (`arm64-v8a` on Apple Silicon, `x86_64` on Intel/Linux) and picks the
  newest installed of each, exporting `ANDROID_HOST_ABI`,
  `ANDROID_SYSTEM_IMAGE`, `ANDROID_PLATFORM_API`, `ANDROID_PLATFORM_JAR`.
  Pre-set any of these to override.
- The dedicated AVD `webapp-a11y-pixel-4a` (Pixel 4a class) is
  auto-created on first run using the detected system image.

## One-shot screenshot (preferred)

For a single screenshot at max a11y, use the orchestrator:

```bash
scripts/screenshot.sh https://example.com [out.png]
scripts/screenshot.sh --physical https://example.com [out.png]
```

By default, it boots the emulator (if not running), applies max a11y,
advances past Chrome's first-run flow, and writes the device screenshot
via `adb shell screencap`. With `--physical`, it selects the single
connected authorized non-emulator device from `adb devices`, applies the
same a11y settings, captures, and restores that device's original density
and font scale before exiting. **No CDP session is opened.** This is the
right default — it's faster, simpler, and not subject to CDP quirks on
Android Chrome.

Each capture also writes a sidecar `<out>.png.json` with the
inputs needed to re-derive the shot: `url`, `ts`, `serial`,
`device_kind`, `density`, `font_scale`, `chrome_locale`, `system_image`,
and physical-device original settings when applicable. Cheap audit trail;
pair PNGs with `for png in *.png; do jq . "${png}.json"; done`.

## Interactive flow (snapshot / click / fill)

When you need to drive the page (not just screenshot it), compose the
building blocks and let `agent-browser` connect over CDP:

```bash
SERIAL=$(scripts/boot_emulator.sh)
scripts/apply_a11y.sh "$SERIAL"                   # default: 1.30x / 1.30x
CHROME_LOCALE=ja-JP scripts/launch_chrome.sh "$SERIAL" https://example.com
PORT=$(scripts/connect_cdp.sh "$SERIAL")
agent-browser --session a11y connect "$PORT"
agent-browser --session a11y snapshot -i
agent-browser --session a11y click @e3
agent-browser --session a11y screenshot --full out.png
```

Set `CHROME_LOCALE` to the target page's language (e.g. `ja-JP`,
`en-US`) so Chrome's "Translate this page?" infobar does not overlay
captures. Set to empty (`CHROME_LOCALE=`) to skip the override
explicitly. Unset = warning + no override.

Run `agent-browser skills get core` once before issuing
`agent-browser` commands if you need its full syntax reference.

When done, restore the emulator:

```bash
scripts/apply_a11y.sh "$SERIAL" --reset
```

## Authentication flows

If the target page requires a login (OAuth, SSO, form-based, MFA, …),
**do not try to automate the auth step.** The emulator window is already
on the user's desktop — the user can complete auth there directly.

Flow:

1. Automate up to the authentication boundary (navigate to the login
   page, take a snapshot/screenshot showing the prompt).
2. Pause and ask the user to complete authentication **inside the
   emulator window**. State clearly which credentials / provider are
   needed, and wait for the user to reply that they're done.
3. After the user confirms, verify the auth succeeded (check URL,
   cookies, or expected post-login element) before resuming automated
   checks.

Do not proceed past the auth boundary on the user's behalf, and do not
send credentials through `agent-browser fill` / `adb shell input text`
even if the user provides them in chat — those leave traces in shell
history and scrollback. Always route credentials through the emulator UI
under the user's direct control.

## Settings semantics

| Setting | Lever | Default (Pixel 4a) | Stock max | Accessibility max |
|---|---|---|---|---|
| Display Size | `adb shell wm density <dpi>` | 440 | 1.30x = 572 | 1.50x = 660 |
| Font Size | `adb shell settings put system font_scale <v>` | 1.0 | 1.30 | 2.0 |

`apply_a11y.sh` defaults to stock max for both. Pass
`--font-scale` / `--density-multiplier` to push to accessibility-max
levels.

## Test records

Save artifacts and a step log under
`./.agents/cache/testing/YYYYMMDD-<short-title>/`,
following the same convention as `webapp-acceptance-checks`. Include the
`font_scale` and density values used in the log so the conditions are
reproducible.

## Suppressing Chrome's "Translate this page?" infobar

Chrome on Android shows a translate prompt whenever the page language
doesn't match the device's accept-languages. That infobar overlays the
top of the viewport and corrupts a11y screenshots. `launch_chrome.sh`
works around it by setting Chrome's per-app locale to match the target
content before navigation:

```bash
CHROME_LOCALE=ja-JP scripts/launch_chrome.sh "$SERIAL" https://…  # default
CHROME_LOCALE=en-US scripts/launch_chrome.sh "$SERIAL" https://…  # English sites
```

The setting persists in the framework's `LocaleManager` — once applied
it survives Chrome relaunches and emulator reboots. Default is `ja-JP`.

## Limitations

- Emulator mode uses a single hard-coded device profile: Pixel 4a-class
  (1080×2340 @ 440 dpi base, ~393 CSS px wide at default density).
- Physical-device mode requires exactly one authorized non-emulator device
  in `adb devices`, unless `ANDROID_SERIAL` is set to the target serial.
- Network requests originate from the emulator, not the host. To target
  `http://localhost:PORT` on the host machine, use `http://10.0.2.2:PORT`
  (the emulator's loopback alias).
- `agent-browser set viewport` / `set device` are no-ops against real
  Android Chrome — the device is physical. Change the effective viewport
  via `apply_a11y.sh --density-multiplier` instead.
- `agent-browser screenshot --full` against Android Chrome can tile
  pathologically; prefer `adb shell screencap` (what `screenshot.sh`
  uses) when you only need the visible area.
