---
name: tui-acceptance-checks
description: Toolkit for verifying TUI / interactive CLI behavior by driving the program through a tmux pane and asserting on captured pane content. Use whenever TUI or interactive CLI code changes and automated coverage does not cover the change — interactive prompts, key bindings, redraw behavior, signal handling, full-screen UIs (ncurses, blessed, bubbletea, etc.). Do not use for webapps (use `webapp-acceptance-checks`) or for stepping through implementation lines in a debugger (use `step-through-code`).
---

# TUI Acceptance Checks

Drive a TUI or interactive CLI through a tmux pane and verify behavior against captured pane content. The pane is the observation layer — equivalent to the browser in `webapp-acceptance-checks`.

**Helper Scripts Available**:
- `scripts/tui-helpers.lib.sh` — sourceable shell functions (`tui::new`, `tui::send`, `tui::sendl`, `tui::capture`, `tui::wait`, `tui::wait_shell`, `tui::run`, `tui::kill`)
- `scripts/init-session.sh` — scaffold an artifact directory with templates (optional)

**Always run scripts with `--help` first**. Prefer sourcing `tui-helpers.lib.sh` over reimplementing the primitives.

## When To Use

- Interactive prompts (`readline`, `inquirer`, `fzf`-style pickers)
- Key bindings and chords (including special keys: `Enter`, `Escape`, `C-c`, `C-d`, arrow keys)
- Signal / interrupt behavior (Ctrl-C while running, SIGTERM cleanup)
- Full-screen TUI frames (ncurses, blessed, bubbletea, ratatui, textual, etc.)
- Programs whose output differs when stdout is a TTY vs a pipe
- Interactive shell integrations (zsh widgets, prompt hooks)
- Any behavior that `node --test` or `go test` alone cannot reach

## When NOT To Use

- Pure functions or non-interactive CLIs — write a unit / integration test instead
- Webapps with browser UIs — use `webapp-acceptance-checks`
- Stepping through implementation lines to verify variable state — use `step-through-code`
- Non-deterministic UIs where pane content cannot be reliably asserted

## Decision Tree

```
Change affects TUI / interactive CLI behavior?
    ├─ No  → stop (wrong skill)
    └─ Yes → Is the behavior reachable from a plain subprocess + stdin/stdout?
        ├─ Yes → prefer a unit / integration test (spawnSync, exec.Command, …)
        └─ No  → use this skill to drive it through tmux
```

A program is only reachable from plain stdio if it does not care about TTY, cursor control, key chords, or async redraws. When in doubt, prototype with tmux — the helpers below are cheap.

## Pane Primitives

All interaction goes through four commands: `tmux new-session`, `send-keys`, `capture-pane`, `kill-session`. Source `scripts/tui-helpers.lib.sh` to get these as shell functions. The rules below apply whether you call `tmux` directly or via the helpers.

### Session lifecycle

Always use a **detached** session with a fixed size — the default size follows the attaching terminal, which makes captures non-deterministic:

```bash
tmux new-session -d -s "$SESSION" -x 120 -y 40
# ... interact ...
# Do NOT kill the session at the end of a successful run.
```

Name the session uniquely per test run (include `$$` or a counter) so parallel runs do not collide.

**Server isolation is opt-in.** By default the helpers target the user's default tmux server so `tmux ls` / eye-on-glass stays easy. When the tested code touches server-wide state — `switch-client`, `kill-server`, global `set -g`, any client-targeting command — call `tui::isolate <name>` before `tui::new`; the helper pins all subsequent calls to a workspace-local socket at `./.agents/tmux/<name>.sock` that the agent sandbox can write. The name keys the socket, so parallel runs get independent servers. Callers pass only the name; the path is the helper's concern. Emit `tui::attach_hint "$session"` at the end of a run — it resolves to the right `tmux -S …` invocation whether you isolated or not, so observability survives either mode.

**Leave the session alive when the run finishes.** The user may be attached via another pane to observe the TUI live, and killing the session disconnects them mid-inspection. At the end of a run, print the session name (and an `tmux attach -t <session>` hint) so the user can inspect it on their own schedule. Only call `tui::kill` / `tmux kill-session` when:

- recovering from a stale session with a colliding name before a new run, or
- the user has explicitly asked you to tear it down.

Stale detached sessions are cheap; a lost observation window is not.

### Input

- **Named keys** go unquoted: `send-keys -t "$SESSION" Enter`, `Escape`, `C-c`, `C-d`, `Up`, `Down`, `Tab`, `BSpace`. Multiple keys can be chained.
- **Shell commands** are sent as a single argument followed by `Enter`:
  ```bash
  tmux send-keys -t "$SESSION" "echo hello" Enter
  ```
- **Literal text** (no tmux key parsing, no execution) uses `-l`. This is essential when testing prefill behavior or pasting text that contains key names:
  ```bash
  tmux send-keys -t "$SESSION" -l "echo should-not-run"
  ```
- **Never** rely on shell metacharacters inside `send-keys`. Quote the entire command and let the receiving shell parse it.

### Output capture

- Always pass `-p` (print to stdout) and `-J` (join wrapped lines). Without `-J`, wrapping at the pane edge breaks substring matches:
  ```bash
  tmux capture-pane -t "$SESSION" -p -J
  ```
- For noisy tests, add scrollback headroom so START markers do not roll off:
  ```bash
  tmux capture-pane -t "$SESSION" -p -J -S -500
  ```
- Pane content is cumulative within a session. Use markers (below) to isolate the output of a single command from prior residue.

### Waiting for content (exponential backoff)

Never use a fixed `sleep` before capturing. TUI timing is unpredictable — poll with backoff and an overall cap:

```bash
# wait up to 15s for a regex to appear in the pane
tui::wait "$SESSION" 'prompt-pattern' 15000
```

The helper polls at 100ms, doubles up to 2s, and returns the current pane content whether or not the pattern matched. Treat a miss as a failure signal in the caller, not a silent timeout.

To wait for a shell prompt before sending the next command, match `\$|%|>` then a brief settling sleep:

```bash
tui::wait_shell "$SESSION" 10000
```

### Isolating command output with markers

The pane is cumulative, so a naive `capturePane().includes("hello")` can match output from a previous command. Wrap each command in START / END markers that contain `$$` (PID substitution):

```bash
START="TUI_START_$(date +%s%N)"
END="TUI_END_$(date +%s%N)"
tmux send-keys -t "$SESSION" "echo ${START}_\$\$; my-command; echo ${END}_\$\$" Enter
tui::wait "$SESSION" "${END}_[0-9]+" 15000
```

Then slice the captured pane between the two marker matches. The literal `$$` in the sent text cannot match `\d+`, so the **echoed** command line never satisfies the wait pattern — only the **executed** line (where the shell substituted the PID) can. This eliminates the two historical sources of flake: prior pane residue, and matching the echo instead of the output.

`tui::run` implements this pattern; prefer it over hand-rolled versions.

## Test Records

Save all artifacts under `./.agents/cache/testing/YYYYMMDD-<short-title>/`.

- **Create the directory** at the start of the session (e.g. `./.agents/cache/testing/20260420-esc-interrupt/`).
- **Pane snapshots** go under `panes/` with zero-padded sequential prefixes: `01-before-esc.txt`, `02-after-esc.txt`. Capture with `tmux capture-pane -p -J -S -` (full scrollback) at each decision point.
- **Action log (`log.md`)**: record each step as it happens — action, expected pane state, observed pane snapshot filename, pass/fail. Example:

  ```markdown
  ## 1. Launch mock agent
  - Action: `send-keys "node mock-agent.js" Enter`
  - Expected: line containing `[mock-agent] working`
  - Snapshot: panes/01-agent-running.txt
  - Result: matched at line 3. **OK**

  ## 2. Send ESC
  - Action: `send-keys Escape`
  - Expected: `interrupted by user` + resume hint
  - Snapshot: panes/02-after-esc.txt
  - Result: both strings present. **OK**
  ```

- **Summary (`summary.md`)**: result table (item / result / notes) and any bugs found.
- **Redact secrets** (tokens, keys, session cookies) before saving pane snapshots — full-screen TUIs sometimes echo env vars.
- **Visibility for reviewers**: leave a summary of what was tested in the PR description so reviewers can confirm coverage.

## Common Patterns

### Verifying a key binding does nothing until committed

Send with `-l` to prefill without executing, then assert the text is present but the effect is not:

```bash
tui::sendl "$SESSION" "echo should-not-run"
sleep 0.3
pane=$(tui::capture "$SESSION")
# 'echo should-not-run' must appear; 'should-not-run' on its own line must not
```

### Verifying signal handling (Ctrl-C, ESC)

1. Start the program, wait for a steady-state marker in the pane.
2. Send the interrupt key.
3. Poll for the expected response (exit message, resume hint, prompt return).
4. Assert both the response appeared **and** the program no longer produces output.

### Verifying TTY-gated behavior

If a program behaves differently under a TTY, tmux gives you a real one for free — no `unbuffer` / `script` needed. Run the same command outside tmux (via `spawnSync`) to confirm the non-TTY path, and inside a tmux pane to confirm the TTY path.

### Preconditions and skip guards

Check for external dependencies before asserting. Matches the sence pattern (`hasTmux`, `hasFence`):

```javascript
describe("…", { skip: !hasTmux() && "tmux not available" }, () => { … });
```

Failing noisily because `tmux` is missing is worse than skipping with a clear reason.

## Integration

- **`step-through-code`** — use when you also need to inspect internal variable state line-by-line. `step-through-code` already depends on tmux for its debugger pane; this skill is complementary and handles the E2E / acceptance half independently.
- **`webapp-acceptance-checks`** — sibling skill for browser-based webapps. Same artifact layout (`log.md`, `summary.md`, per-step snapshots), different driver.
- **`coding-practice`** — verification guidance may invoke this skill when the change lacks automated TUI coverage.
- **`debugging-practice`** — use this skill to reproduce a reported TUI bug deterministically before root-causing.

## Reference Implementation

For a worked example of the patterns above, see `~/src/github.com/toqoz/sence/tests/interactive.test.js` and `integration.test.js` — they use the marker-based `runAndCapture`, `waitForContent` with backoff, and fixed 120×40 session geometry.
