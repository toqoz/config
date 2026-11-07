# tmux capture adapter

Use the repo's existing terminal harness first. These helpers supply deterministic
captures where the generic control-cli recipe does not. They are sourceable,
not an executable to run with `--help`:

```bash
source <skill>/scripts/tui-helpers.lib.sh
SESSION="tui-$$"
tui::new "$SESSION"
tui::wait "$SESSION" '<actual-ready-pattern>' 15000
tui::sendl "$SESSION" 'literal text, not executed'
tui::send "$SESSION" Enter
tui::wait "$SESSION" '<actual-result-pattern>' 15000
tui::capture "$SESSION" 500
tui::attach_hint "$SESSION"
```

Replace `<skill>` with the installed skill path. Defaults are 120 columns and
40 rows; set `TUI_COLS` / `TUI_ROWS` before creating the session when needed.
Choose a fresh session name rather than taking over an existing one. Captures
use `capture-pane -p -J` to join wrapped lines; the optional argument selects
scrollback depth. Save the final screen even when a wait fails.

## Isolation and ownership

Helpers use the default tmux server for discoverability. Before creating the
session, call `tui::isolate <unique-name>` if the target touches server-wide
settings, clients, or sessions. It selects a workspace-local socket and exports
`TUI_SOCKET`; all subsequent helpers use that socket. `tui::attach_hint` prints
the correct default or isolated attach command.

Keep successful observation sessions alive under the local skill policy.
`tui::kill <session>` is for requested teardown or a known owned stale session,
not a blanket cleanup command. Never kill the user's default tmux server.

## Keys, waits, and command boundaries

- `tui::send` forwards named keys as separate arguments (`Enter`, `Escape`,
  `C-c`, `C-d`, `Up`, `Down`, `Tab`, `BSpace`). A shell command is one quoted
  argument followed by `Enter`; its receiving shell interprets that command.
- `tui::sendl` sends literal text with `-l`. Capture the prefill before sending
  `Enter` when checking that no command/effect runs prematurely.
- `tui::wait <session> <regex> [timeout-ms]` uses bounded backoff, prints the
  final capture, and returns 0 on match or 1 on timeout. Check its return code.
  `tui::wait_shell` is only a heuristic shell-prompt convenience; it does not
  establish application readiness. Prefer the actual target's ready marker.
- `tui::run <session> <shell-command> [timeout-ms]` brackets one command with
  START/END markers whose PID suffix is expanded by the receiving shell. The
  echoed command's literal `$$` cannot satisfy the numeric completion marker.
  It returns the bracketed output so earlier screen residue does not count.
  Its return status indicates marker completion, not the tested command's
  exit status: capture/assert that status explicitly when it is the contract.

For long/noisy scenarios, retain sufficient scrollback or capture incrementally
so the start marker is not lost. Text alone does not establish every terminal
property; verify cursor/layout/resize behavior through the actual terminal
surface when that is what changed. Assertions must refer to the current action,
not a generic prompt or a word left on screen by an earlier run.
