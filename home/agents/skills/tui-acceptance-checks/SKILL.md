---
name: tui-acceptance-checks
description: >
  Verify changed TUI and interactive CLI behavior through a real terminal when
  automated coverage is insufficient: prompts, keys, redraws, interrupts, and
  TTY-dependent output. Reuse project harnesses and pstack control-cli, retaining
  the local tmux capture and live-observation conventions.
---

# TUI acceptance checks

Exercise the user's terminal surface, not just functions beneath it. Follow
repository verification rules; in this config, the required surface is a tmux
pane. A pipe-based subprocess does not prove TTY, cursor, key, or redraw behavior.

## Harness and scenario

Prefer a working project-local verification skill or interactive test harness.
If none reaches the behavior, read and apply pstack's `control-cli` to establish
one. Use `create-verification-skill` for a reusable project harness when needed,
not as a mandatory step for every check. This skill does not activate a mode.
Pure non-interactive behavior belongs in ordinary tests; internal debugger
observations belong in `step-through-code` and do not replace terminal checks.

Define the command/build, working directory, terminal size/environment, inputs,
and expected screen and effects. Start an owned, uniquely named terminal with
fixed geometry, and wait for an app-specific ready state before each action.
For tmux, use the bundled [capture helpers](references/tmux.md), preserving:

- Named keys versus literal text: prefilling a command must not execute it.
- Joined screen captures and per-command markers: old output and echoed input
  must not satisfy the current assertion.
- Bounded waits with timeout treated as a failed/incomplete observation.
- A separate tmux server when the target changes server-wide state.

Send one action at a time and observe its result before proceeding. Check key
bindings, navigation, redraw/resize, interrupts, and exit behavior where changed.
For negative assertions, wait through the relevant event or bounded observation
window; one immediate capture cannot prove a later effect never occurs.
For interrupts, confirm process/output cessation as well as a printed message.
Compare TTY and pipe behavior when the change distinguishes them.

## Evidence and observation sessions

Keep a concise action/expected/result record and numbered screen captures under
`.agents/cache/testing/<run>/`. Record the terminal/session identity and relevant
exit status or side effects. Reuse existing harness output rather than copying
it into multiple logs; the optional `scripts/init-session.sh` can scaffold a log,
summary, and `panes/` directory. Redact secrets before preserving output.

Retain the local live-observation convention: leave a successful tmux observation
session available and print its attach command so the user can inspect it.
This is the local exception to control-cli's generic session cleanup. Do not
kill a session the user may be watching. Reclaim a colliding name only when it
is known to be stale and owned; otherwise choose a fresh name. Tear down the
retained session when requested, and report any retained process/resource.
A failed or interrupted run still needs an honest partial result and resource
status; do not silently abandon a running command or label it as passed.

Report actual scenarios, observed results, evidence paths, remaining gaps, and
the retained attach hint. A missing tmux/terminal dependency may justify a test
skip, but that skip does not satisfy a required acceptance gate.
