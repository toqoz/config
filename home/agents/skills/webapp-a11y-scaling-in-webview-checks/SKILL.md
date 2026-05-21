---
name: webapp-a11y-scaling-in-webview-checks
description: Verify how a webapp renders inside an Android WebView (the engine apps like LINE embed for in-app browsing) under max accessibility text scaling. Boots a shared Pixel 4a emulator, applies a per-host-app calibrated preset (`wm density` + `WebSettings.setTextZoom`) that exercises the worst realistic a11y scaling without triggering per-zone pan/overflow, and exposes the WebView over CDP so `agent-browser` can drive it (snapshot, click, fill, screenshot). Currently ships a LINE MiniApp preset; add a new preset section when targeting another in-app WebView. Use `webapp-a11y-scaling-checks` for the Chrome-browser-side check instead.
allowed-tools: Bash(agent-browser:*), Bash(adb:*), Bash(emulator:*), Bash(avdmanager:*), Bash(curl:*), Bash(nix:*), Bash(jq:*)
---

# Webapp A11y Scaling Checks (Android WebView)

Many host apps (LINE, Slack, Twitter, …) embed an Android **WebView**
rather than handing off to Chrome. The WebView shares Chromium's engine
but is driven by different a11y inputs: `WebSettings.setTextZoom(percent)`
is text-only zoom that leaves the layout frozen, so it exposes overflow
bugs Chrome-based checks miss. Combined with `wm density` (the Android
Display Size lever), the content reflows while text scales further,
which matches what users with Android font scale at max actually see
inside the host app.

This skill ships a bare WebView harness (`wvtest/app.apk`) plus a set of
**presets** — one per host app of interest — that pin the
`density × textZoom` combination known to mirror that app's a11y
treatment. Pick a preset by reading the relevant section below.

## When to use

- In-app WebView mobile-web acceptance — verify a page renders OK under
  a realistic "Android font size at max + large Display Size" user of the
  host app.
- Reproducing a11y bugs reported by users of a specific host app.

## When NOT to use

- Chrome-in-a-browser-tab acceptance → use `webapp-a11y-scaling-checks`
  (separate Chrome a11y pipeline).
- Host-app SDK integration where the page needs the real host app
  context (e.g. LINE Login tokens, `liff.init()` bridges, Slack OAuth
  postMessage). This skill loads the page in a bare WebView without the
  host client.

## Skill Dependencies

This skill drives the live WebView through `agent-browser`'s CDP
session, both for the interactive single-emulator flow and inside
parallel exploration sub-agents. The dependency lives outside this
repo:

- [`agent-browser`](https://github.com/vercel-labs/agent-browser/tree/main/skills/agent-browser)
  — fast browser automation over CDP. Used by every sub-agent
  (`snapshot`, `click`, `fill`, `screenshot`). Each sub-agent should
  use a unique session name (`agent-browser --session "wv-<agent_id>"`)
  to keep CDP state independent. Run `agent-browser skills get core`
  once per machine to fetch its full syntax reference.

## Prerequisites

- An **Android SDK** discoverable by `scripts/sdkenv.sh`. It tries, in
  order:
  1. `$ANDROID_HOME` / `$ANDROID_SDK_ROOT`,
  2. Android Studio defaults (`~/Library/Android/sdk` on macOS,
     `~/Android/Sdk` on Linux),
  3. android-nixpkgs at `~/.local/share/android`.
  If none match, the scripts print install instructions (install Android
  Studio and complete its setup wizard).
- A **JDK** (for `build_apk.sh` only). `sdkenv.sh` tries:
  1. a working `javac` on PATH,
  2. Android Studio's bundled JBR
     (`/Applications/Android Studio.app/.../jbr` etc.),
  3. `nix build nixpkgs#jdk21` if `nix` is available.
- Inside the resolved SDK, **at least one** of each: a system-image
  (`google_apis_playstore` + host ABI), a `build-tools/*`, and a
  `platforms/android-*`. `sdkenv.sh` auto-detects the host ABI
  (`arm64-v8a` on Apple Silicon, `x86_64` on Intel/Linux) and picks the
  newest installed of each, exporting:
  `ANDROID_HOST_ABI`, `ANDROID_SYSTEM_IMAGE`, `ANDROID_PLATFORM_API`,
  `ANDROID_PLATFORM_JAR`, `ANDROID_BUILD_TOOLS_DIR`. Pre-set any of
  these to override.
- The shared AVD `webapp-a11y-pixel-4a` (Pixel 4a class — see
  `references/device-profiles.md`) is reused from
  `webapp-a11y-scaling-checks` and auto-created on first run using the
  detected system image.

## One-shot screenshot (preferred)

```bash
scripts/screenshot.sh https://example.com/foo [out.png]
```

Boots the emulator, builds and installs the bundled WebView harness
(`wvtest/app.apk`) if absent, applies the **default preset** (LINE
MiniApp — see below), opens the URL, captures the device screen via
`adb shell screencap`, prints the path. To use a non-default preset,
drive the building blocks directly (next section) with that preset's
values.

## Interactive flow (snapshot / click / fill)

```bash
SERIAL=$(scripts/boot_emulator.sh)
scripts/apply_a11y.sh "$SERIAL" --font-scale 1.0 --density-multiplier <M>
scripts/launch_webview.sh "$SERIAL" https://example.com/foo <ZOOM>
PORT=$(scripts/connect_cdp.sh "$SERIAL")
agent-browser --session wv connect "$PORT"
agent-browser --session wv snapshot -i
agent-browser --session wv click @e3
```

`<M>` and `<ZOOM>` come from the preset for the host app you are
targeting. Run `agent-browser skills get core` once if you need its full
syntax.

### Local development servers and `adb reverse`

When opening a local development app in the emulator WebView, determine
which host ports the page itself and its browser-visible backends depend
on before launching. Prefer reversing those ports and loading the app as
`http://localhost:<web_port>` inside the WebView.

Discovery steps:

1. Find the web app URL/port from the project's documented dev command,
   compose file, run script, or currently listening ports.
2. Inspect browser-visible config for API/base URLs, for example:
   `NEXT_PUBLIC_*`, `PUBLIC_*`, frontend config files, compose
   environment variables, or generated runtime config.
3. Reverse every host port that the WebView will access:

   ```bash
   adb -s "$SERIAL" reverse tcp:<host_port> tcp:<host_port>
   ```

4. Launch the WebView with `http://localhost:<web_port>`.

Use `http://10.0.2.2:<port>` only when the app and all browser-visible
API/config URLs are also set to `10.0.2.2`. A common failure mode is that
the initial page loads via `10.0.2.2`, but client-side requests still
point to `localhost`; inside the emulator that means the emulator itself,
not the host machine, so login/session/API flows fail.

When done, restore defaults:

```bash
scripts/apply_a11y.sh "$SERIAL" --reset
```

## Presets

Each preset pins `density-multiplier × textZoom` to a calibrated point
that reflects the host app's a11y treatment. Pick one based on which
host app's WebView you are simulating.

### LINE MiniApp (default)

| Lever | Value | Why |
|---|---|---|
| `wm density` | 440 × 1.1 = 484 | Reflows layout into a narrower CSS viewport (mimics Android Display Size ≈ "Larger" inside LINE) |
| `WebSettings.setTextZoom(n)` | 200 | Matches Android's accessibility font-size max (2.0x) as typically applied by LINE's WebView |
| AVD | `webapp-a11y-pixel-4a` | Shared with `webapp-a11y-scaling-checks` — 1080×2340 @ 440 dpi base, ~393 CSS px wide at default density |

`density × 1.1 + textZoom 200` is the sweet spot that maximises the
page's scrollable region while suppressing the side-effects of
text-only max zoom (fixed-width buttons overflowing, content below
the fold being pushed off-screen). Higher density multipliers start
clipping the bottom nav / modal buttons.

This preset is wired in as the `screenshot.sh` default. `apply_a11y.sh
--density-multiplier 1.1` + `launch_webview.sh … 200` reproduces it for
the interactive flow.

### Adding a new preset

When you discover that another host app's WebView needs different
scaling (e.g. Slack's WebView clamps `textZoom` differently), add a new
`### <Host app name>` subsection above with the same table shape, the
calibration target page, and how to apply it via the building blocks. If
the new preset becomes the more common case, also update `screenshot.sh`
to use it as the default.

For the **device** part of a new preset, consult
`references/device-profiles.md` for the per-device CSS-px width (the
lever that decides reflow / clip behavior) and pick from the
**Default — modern mid-range** bucket (~411 CSS px, e.g. `pixel_8a`)
unless you explicitly want a narrower or wider viewport. The current
LINE MiniApp preset is calibrated against the slightly narrower
`pixel_4a` (~393 CSS px) — kept as-is so its calibration figure remains
valid.

## Parallel exploratory screenshots

For full-page-coverage exploration (e.g. "screenshot every screen of
this mini-app at max a11y"), drive the work through sub-agents in
parallel. The orchestrator (this main agent) does **no driving and no
screen capture itself** — it sets up the snapshot, fans work out, and
does the final rename pass.

### Workflow

```
┌──────────────────────────────────────────────────────────────┐
│ 1. Onboarding sub-agent (sequential, single emulator)        │
│    ─ boot master normally, apply a11y, launch webview at URL │
│    ─ drive past auth + any one-time onboarding dialogs       │
│    ─ take screenshots while doing so (main_step = 01)        │
│    ─ exit when "main feature accessible, no blocking         │
│      dialogs" — DOES NOT kill the emulator                   │
├──────────────────────────────────────────────────────────────┤
│ 2. Save snapshot, then kill master                           │
│    ─ SNAP=agent-snap-$(uuidgen | tr '[:upper:]' '[:lower:]'  │
│           | head -c 8)                                       │
│    ─ scripts/snapshot_save.sh "$MASTER" "$SNAP"              │
│    ─ trap 'scripts/snapshot_cleanup.sh <avd> "$SNAP"' \      │
│        EXIT INT TERM                                         │
│    ─ adb -s "$MASTER" emu kill                               │
│      (read-only clones cannot coexist with a non-read-only   │
│       master — the emulator's AVD lock blocks them.)         │
├──────────────────────────────────────────────────────────────┤
│ 3. Decide split — N sub-agents, one area each                │
│    ─ N = scripts/parallelism_hint.sh (1..8 by free RAM)      │
│    ─ Reasonable example splits: one per main bottom-nav tab; │
│      or one per top-level feature (e.g. catalogue / search / │
│      settings); or one per auth-gated section found in #1.   │
├──────────────────────────────────────────────────────────────┤
│ 4. Spawn parallel sub-agents (one Agent call per area)       │
│    ─ Each is assigned: agent_id (02, 03, …), area scope,     │
│      adb port (5554 + 2*idx), CDP port (9222 + idx).         │
│    ─ Each boots its own read-only emulator from $SNAP.       │
│    ─ Stagger spawn by ~5s if N ≥ 4 to smooth boot RAM spike. │
├──────────────────────────────────────────────────────────────┤
│ 5. Final rename pass + INDEX.md (main, after sub-agents)     │
│    ─ Rename each NN-MM-*.png to NN-MM-<UI-aligned title in   │
│      user's preferred language>-<state>.png. Keep the NN-MM  │
│      prefix and the trailing -open/-closed/-(none) state.    │
│    ─ Generate INDEX.md from report.jsonl + dir listing       │
│      (see "Artifact contract" below).                        │
└──────────────────────────────────────────────────────────────┘
```

### Filename convention

`{main_step:02d}-{sub_step:02d}-<title>[-<state>].png`

- `main_step` = onboarding is `01`, parallel sub-agents are `02`, `03`, …
  in spawn order.
- `sub_step` = within one sub-agent, sequential capture order
  (`01`, `02`, …).
- `<title>` = before rename, working English slug (e.g. `terms-modal`);
  after final rename, UI-aligned title in the user's preferred language.
  The numeric prefix is **always preserved**.
- `<state>` (optional) = `open` / `closed` for dismissable-dialog pairs,
  omitted otherwise. **Stays in English even after rename** so the
  open/closed pairing is machine-parseable from filenames alone.

Two-state rule for dismissable dialogs: capture both `…-open.png` and
`…-closed.png` (sub_step increments between them) so the part hidden
behind the dialog is also visible. Apply this even to one-shot dialogs
(cookie consent, notification permission) since they cannot be re-opened
later. Non-dismissable states (loading, required onboarding) get a
single shot with no `-state` suffix.

### Artifact contract

The artifact directory ends up with three things, in this order:

1. **PNG screenshots** — named per the convention above, post-rename.
2. **`report.jsonl`** — append-only event log, one JSON object per line.
   Sub-agents write it via `scripts/append_event.sh`. Schema:

   | field | always? | example |
   |---|---|---|
   | `agent_id`     | yes | `"03"` |
   | `event`        | yes | `"capture"`, `"retry"`, `"read_only_refused"`, `"timeout"`, `"manual_step"` |
   | `screen`       | capture | `"terms-modal"` (working English slug, pre-rename) |
   | `state`        | capture | `"open"` / `"closed"` / omitted |
   | `pair_id`      | capture | `"03-terms-modal"` (groups open/closed shots) |
   | `file`         | capture | `"03-01-terms-modal-open.png"` (pre-rename name) |
   | `reason` / `action` / `retry_count` | event-specific | — |
   | `ts`, `pid`    | auto    | filled by `append_event.sh` |

3. **`INDEX.md`** — emitted by main after the rename pass. Sections:

   - A table of all captures: `# | Area | Screen | State | File`,
     ordered by `NN-MM`, with open/closed pairs adjacent (sorted by
     `pair_id`). Translate the headers to the user's preferred
     language when emitting INDEX.md.
   - A "Failures" section listing every non-`capture` event from
     `report.jsonl` (retries, read-only refusals, timeouts, manual
     steps), each with the responsible `agent_id` and a one-line
     description. Section is omitted if empty.
   - A "Sub-agents" section: `agent_id` → area scope.

   Filenames in the table are **post-rename**; main resolves them by
   matching `pair_id` (and `state` if present) from `report.jsonl`
   against the renamed files in the directory.

### Sub-agent prompt template

Use this template for every Agent call. Fill in the bracketed slots.
Keep the body verbatim so the contract stays consistent across the
session.

```
You are a parallel exploration sub-agent for the
webapp-a11y-scaling-in-webview-checks skill. Drive an Android WebView
at max a11y scaling and capture screenshots of one specific area.

Context
- Target URL          : <URL>
- Target description  : <one-sentence "what this app/page is">
- Skill scripts dir   : <absolute path to scripts/>
- Artifact dir        : <absolute path; create if missing>
- Preferred language  : <e.g. ja>
- AVD name            : <e.g. webapp-a11y-pixel-4a>
- Snapshot name       : <SNAP — empty for the onboarding sub-agent>
- agent_id            : <02-digit, e.g. 03>
- adb port            : <e.g. 5560>      (serial = emulator-<port>)
- CDP port            : <e.g. 9224>
- Area scope          : <one paragraph describing what to cover>
- Stop criterion      : <e.g. "every screen reachable from the
                        'Settings' tab is screenshotted">

Setup (in order)
1. SERIAL=$(<scripts>/boot_emulator.sh --port <adb_port> \
            [--snapshot <SNAP> --read-only] <AVD>)
2. (Onboarding sub-agent only — others inherit from snapshot)
   <scripts>/apply_a11y.sh "$SERIAL" --font-scale 1.0 \
     --density-multiplier <preset M>
   <scripts>/launch_webview.sh "$SERIAL" "<URL>" <preset ZOOM>
3. <scripts>/connect_cdp.sh "$SERIAL" <CDP port>
4. agent-browser --session "wv-<agent_id>" connect <CDP port>

Capture loop
- Number files {agent_id}-{NN}-<title>[-<state>].png starting NN=01.
- For every dismissable dialog: take "<title>-open.png" first, then
  dismiss and take "<title>-closed.png" (NN increments). Use the same
  pair_id ("<agent_id>-<title>") for both events.
- Use adb -s "$SERIAL" shell screencap -p for full-screen captures
  (CDP full-page screenshots tile on Android Chrome).
- After every capture, log it:
    <scripts>/append_event.sh "$ART" agent_id=<id> event=capture \
      screen=<title> [state=open|closed pair_id=<id>-<title>] \
      file=<filename>
- Log notable failures inline:
    <scripts>/append_event.sh "$ART" agent_id=<id> event=retry \
      reason="<short>" retry_count=<n>
    <scripts>/append_event.sh "$ART" agent_id=<id> \
      event=read_only_refused action="<what was attempted>"
    <scripts>/append_event.sh "$ART" agent_id=<id> event=timeout \
      reason="<short>"
- Never type credentials via agent-browser fill or adb input text — if
  authentication is needed, ask the user and wait for "done". Log the
  pause as event=manual_step with reason="<what>".

Cleanup
- (Onboarding sub-agent) leave emulator RUNNING — main will snapshot
  AND then kill it before fanning out parallel clones.
- (Parallel sub-agent) adb -s "$SERIAL" emu kill on the way out.

Report (≤300 chars, returned to orchestrator)
- Coverage summary: areas reached / blocked.
- One-line note on any non-`capture` events you logged (so main knows
  to re-spawn writeable, surface a manual step, etc.).
- Do NOT echo the file list — main reads it from `report.jsonl` + the
  artifact directory.
```

### Read-only first, writeable on demand

Sub-agents boot read-only by default — disk writes (form submissions,
preference toggles, anything stored server-side keyed on a session)
live in an ephemeral overlay and vanish at exit. If a scope needs to
verify a post-write screen (e.g. "after submitting the form, this
confirmation appears"), the sub-agent's report flags it and main
re-spawns that one scope WITHOUT `--read-only`, on its own port,
booting from the same snapshot. Writes still vanish on exit — only
the captures persist in `artifact_dir`.

### Cleanup safety

The orchestrator MUST `trap 'scripts/snapshot_cleanup.sh <avd> "$SNAP"
"$ONBOARD_SERIAL"' EXIT INT TERM` before saving the snapshot, so a
crash mid-fanout doesn't leave an `agent-snap-*` directory under
`~/.android/avd/<avd>.avd/snapshots/` consuming gigabytes.

## Authentication

This harness is a bare WebView — it does **not** embed any host-app SDK
bridge (LIFF, Slack JS bridge, etc.), so OAuth handshakes that need the
host app to broker the token will fail. Two practical workarounds:

1. **Use the page's guest / login-less path** if the page exposes one
   (a "use without signing in", "continue as guest", or equivalent
   entry point). Proceed through it with `agent-browser`.
2. **Ask the user** to complete authentication manually in the emulator
   window, then resume automated checks. State clearly which credentials
   are needed, wait for the user's "done" reply, and verify the
   post-auth URL before driving further actions. Never send credentials
   via `agent-browser fill` or `adb shell input text` — route them
   through the emulator UI under the user's direct control.

## Why not just use Chrome?

Chrome uses its own rendering pipeline and its own accessibility
font-scale path (`font_scale` × browser text-scale preference). WebView
shares the same Chromium engine but is driven by different inputs
(`setTextZoom`, sometimes tied to system `font_scale` by the embedding
app). Concretely, a host-app bug like "speech-bubble text overflows a
fixed-size graphic at max font scale" shows up only in the WebView path;
the Chrome skill's density + font_scale compound scales the image too.

## Artifacts

Save screenshots and a step log under
`./.agents/cache/testing/YYYYMMDD-<short-title>/`,
consistent with the sibling skills. Record which preset was used (and
the density multiplier + textZoom values) so the conditions are
reproducible.

## Limitations

- Bare WebView, no host-app SDK bridges (LIFF, LINE Login, Slack JS
  bridge, etc.).
- Single device profile (Pixel 4a class). For other viewport sizes,
  create a separate AVD and pass its name to `boot_emulator.sh`.
- Network requests originate from the emulator; host `localhost:PORT`
  must be addressed as `http://10.0.2.2:PORT`.
- Modals whose buttons rely on absolute positioning occasionally land
  below the viewport at extreme text scales — drive via CDP
  (`agent-browser scrollintoview + click`) rather than `adb input tap`
  when that happens.

## Files

```
SKILL.md
scripts/
  sdkenv.sh            — resolve Android SDK + JDK (4-step fallback chain)
  boot_emulator.sh     — AVD boot (default reuse-or-boot; --port +
                         --read-only + --snapshot for parallel mode)
  apply_a11y.sh        — apply/reset wm density + font_scale
  build_apk.sh         — build wvtest/app.apk (idempotent)
  launch_webview.sh    — install + launch wvtest with URL and textZoom
  connect_cdp.sh       — adb forward webview_devtools_remote → tcp:9222
  screenshot.sh        — one-shot orchestrator (default preset)
  snapshot_save.sh     — adb emu avd snapshot save (parallel workflow)
  snapshot_cleanup.sh  — adb-then-fs delete; safe to call from a trap
  parallelism_hint.sh  — recommended sub-agent count (1..8) by free RAM
  append_event.sh      — sub-agent JSONL logger for report.jsonl
references/
  device-profiles.md   — Pixel-family AVD dimensions + per-bucket
                         recommendation (consult when adding a preset)
wvtest/
  AndroidManifest.xml
  src/com/example/wvtest/MainActivity.java
```
