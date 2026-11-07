# Node debugger driver

Requires Node.js 24 or later and Unix sockets. No npm packages or tmux.
The driver owns one spawned Node process; it does not attach to an existing
server or browser, apply source maps, or calculate source/branch coverage.
It records evidence; the agent compares values and reconciles coverage.

## Start and control

Run `serve` as a long-lived foreground command through the host command tool.
Keep its session ID. Do not daemonize it or terminate its host session before
stopping its target. Use a new empty session directory. Keep its absolute path
short enough for the Unix socket (the driver checks the platform limit).

```bash
node <skill>/scripts/step-driver.mjs serve .agents/cache/stc-01 -- ./entry.mjs input
```

A second command-tool call sends one request and waits for the corresponding
pause, exit, or bounded timeout; no sleeps or prompt scraping:

```bash
node <skill>/scripts/step-driver.mjs .agents/cache/stc-01 where
node <skill>/scripts/step-driver.mjs .agents/cache/stc-01 source
node <skill>/scripts/step-driver.mjs .agents/cache/stc-01 bp /absolute/path/entry.mjs 12
node <skill>/scripts/step-driver.mjs .agents/cache/stc-01 next --expect 'total becomes 30; next statement is the guard'
node <skill>/scripts/step-driver.mjs .agents/cache/stc-01 eval 'total'
node <skill>/scripts/step-driver.mjs .agents/cache/stc-01 report
node <skill>/scripts/step-driver.mjs .agents/cache/stc-01 stop
```

Replace `<skill>` with the skill's actual path. Resolve all relative paths from
one working directory; target processes inherit the serve command's cwd.
For a deeply nested checkout use a short workspace cache location (for example
an ancestor workspace's `.agents/cache/`) and absolute script/target paths.
Do not introduce a new process manager or scheduler.

Commands: `where`, `source [--context N]`, `stack`, `bp <target> <line>`, `bps`,
`eval <expression>`, `next|step|out|continue --expect <prediction>`,
`wait [--timeout-ms N]`, `report`, `stop`. Movement also accepts `--timeout-ms`.
Line and column numbers are 1-based. An exact URL or absolute path avoids
suffix ambiguity. Inspect moved breakpoint locations. Pending means no runtime
location resolved: distinguish a lazy-loaded script from a wrong path or an
out-of-range line before trusting it. Even resolved locations can refer to
wrappers rather than the intended statement. Only `hitBreakpoints` / hit counts
prove actual breakpoint hits; inspect the stopped source as well.
ESM can first pause inside an imported module rather than the main entry.

The JSON `ok` flag means the command was handled; inspect `outcome`, target
`state`, and real exit `code` too. Timeout does not stop a running target: use
`wait` to collect its next pause/exit or `stop` to abort. Concurrent commands are
rejected as busy. `eval` uses `throwOnSideEffect`; rejected expressions are not
observations of the requested value. Inspect simpler fields instead. Don't
bypass that protection to obtain a prettier object dump.

## Evidence and cleanup

`transcript.jsonl` contains predictions, actual pauses, evaluations, and exits.
`program.stdout` / `program.stderr` separate user output from inspector banners;
`report` returns their tails and paths. `session.json` records the end state.
Retain the checklist outside the empty per-process session directory. Use a
fresh session after source changes and for each scenario requiring fresh state.

`stop` kills the owned target before disconnecting, then closes the session.
SIGINT/TERM/HUP to serve also request target cleanup. Never SIGKILL the driver:
the target can resume when its inspector disconnects. Aborting does not count
as a normal completed program run. If cleanup reports a timeout, verify the
recorded PID and resolve the remaining process; do not claim cleanup succeeded.
After the direct target exits, stderr drains for up to 500ms. If a descendant
still holds the pipe, the driver closes that capture and records
`stderr-held-open`; later descendant output is not evidence from this run.
The driver owns only the direct target: arrange explicit ownership and cleanup
for subprocesses the application creates.

Limitations: inspector completion is detected from Node's stderr banner;
a program emitting the exact same banner can interfere. Programs depending on
TTY input need a PTY-capable adapter. The bundled driver ignores target stdin;
it is for controlled scripts and non-interactive execution. Preserve meaningful
TTY behavior through the host's PTY tooling, not by treating pipes as equivalent.

Run real-CDP regression tests with:

```bash
node --test <skill>/scripts/step-driver.test.mjs
```
