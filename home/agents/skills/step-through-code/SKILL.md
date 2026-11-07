---
name: step-through-code
description: >-
  Step through changed code line-by-line in a real debugger, confirming each
  variable and branch behaves as expected — before bugs appear. Use after
  implementing high-risk code paths with branching, side effects, async
  behavior, or browser-visible consequences. Supports CLI tools (node inspect),
  server-side code (node inspect / CDP), and browser JavaScript (CDP). Uses
  `agent-browser` for trigger actions, `webapp-acceptance-checks` for browser
  verification. Supported languages: JavaScript/TypeScript (when source maps
  are trustworthy). Not for type-only changes, config edits, or trivial pure
  functions.
---

# step-through-code

## Intent

Step through every executed owned line of changed code in a real debugger, verifying that each variable, branch, and side effect behaves as expected — proactively, before bugs appear.

This is a verification skill, not a debugging skill. Use it to confirm correctness of code you just wrote.

**Limitation**: Transpilation, bundling, and optimizer passes may cause source-map misalignment, line coalescing, or duplicate execution (e.g., React dev-mode re-renders). "Every line" means every line that the debugger can reliably map to your source. When mapping is unreliable, verify the result instead of the individual steps.

## References

- Steve McConnell, *Code Complete* 2nd ed., Chapter 22 "Developer Testing" — advocates stepping through every line in a debugger as a standard developer practice, not a last resort.

## When To Use

- Changed Node.js code with non-trivial branching or control flow
- Code with side effects (DB writes, API calls, file I/O)
- Async code paths where ordering matters
- Request handlers with browser-visible consequences
- Client-side event handlers, initialization logic, or conditional rendering branches
- Full-stack flows where server action and client re-render must be verified together
- When `coding-practice` verification guidance demands more than tests or manual checks

## When NOT To Use

- Pure type/interface changes
- Static config changes, text-only edits
- Trivial pure functions better covered by a unit test
- Non-deterministic paths that cannot be reliably triggered
- Transpiled code without trustworthy source maps
- Scenarios exceeding ~40 executed owned lines — split into smaller scenarios first

## Preconditions

Before starting, confirm ALL of these:

1. You are running inside a tmux session
2. You have a deterministic trigger command (CLI invocation, HTTP request, etc.)
3. The target code runs directly as Node.js (not transpiled without source maps)
4. The verification envelope (see below) is small enough (≤40 owned lines per scenario)

If any precondition fails, fall back to tests or manual verification.

## Verification Envelope

The **envelope** defines what you step through. It MUST be scoped tightly:

- Changed/new lines in owned code
- Immediate callers/callees that are also owned code
- **NEVER** step into `node_modules`, framework internals, or Node built-ins

If suspicion moves outside the envelope during stepping, **stop this skill** and switch to `debugging-practice`. Do not expand the envelope ad hoc.

## tmux Debugger Control

Interact with the debugger exclusively through direct tmux commands. This is more reliable than wrapper scripts because `node inspect` output timing is unpredictable.

### Pane management

```bash
# Start: split a pane and launch node inspect
tmux split-window -d -v -l '30%' "node inspect <entry-file> [args...]"

# Identify the debugger pane (note the pane id from split-window output,
# or use tmux list-panes to find it)

# Stop: kill the debugger pane when done
tmux kill-pane -t <pane-id>
```

### Sending commands and reading output

Send a command, then poll with exponential backoff until the expected prompt appears:

```bash
# Send a debugger command
tmux send-keys -t <dbg-pane> "<command>" Enter

# Poll for the prompt with exponential backoff (0.2s → 0.4s → 0.8s → ... → cap 3s)
w=200; for _ in 1 2 3 4 5 6 7 8; do
  sleep "$(awk "BEGIN{printf \"%.1f\",$w/1000}")"
  if tmux capture-pane -t <dbg-pane> -p | tail -1 | grep -q 'debug>\|cdp>'; then break; fi
  w=$((w * 2)); [ $w -gt 3000 ] && w=3000
done
tmux capture-pane -t <dbg-pane> -p -S -    # -S - captures full scrollback
```

This responds in ~0.2s for fast commands (`exec`, `list`) while waiting up to ~20s total for slow operations (`cont` to a distant breakpoint, `next` over a network call). The prompt check is best-effort — if the debugger outputs an exception or log line instead of a prompt, the loop will time out and capture whatever is visible.

### Chaining command + capture (simple form)

For commands that are known to be fast (< 1s), the simple form is acceptable:

```bash
tmux send-keys -t <dbg-pane> "next" Enter && sleep 1 && tmux capture-pane -t <dbg-pane> -p | tail -10
```

Use `tail -N` to focus on the relevant output. Typical useful ranges: `tail -5` for a single value, `tail -10` for context around the current line, `tail -20` for larger output.

For commands with unpredictable latency (`cont`, `next` over async/network calls), always use the backoff pattern above.

### Next.js / webpack dev server (CDP required)

`node inspect` cannot set breakpoints in webpack-bundled code because `eval-source-map` produces ambiguous script names. Use Chrome DevTools Protocol (CDP) directly instead.

**Setup:**

1. Start the dev server with `NODE_OPTIONS='--inspect'`:
   ```bash
   tmux send-keys -t <e2e-pane> "NODE_OPTIONS='--inspect' npm run dev" Enter
   ```
   Note the WebSocket URL from "Debugger listening on ws://...". Next.js prints two ports — use the **router server port** (the one mentioned in "should be inspected at port XXXX").

2. **Trigger the target route once** (e.g., `curl http://localhost:3000/api/your-route`) to force webpack to load the module. Breakpoints on unloaded scripts have no effect.

3. Use a CDP client script (see `references/cdp-debug.js`) to connect and set breakpoints:
   ```bash
   tmux send-keys -t <dbg-pane> "NODE_PATH=./node_modules node /path/to/cdp-debug.js '<ws-url>'" Enter
   ```

**Setting breakpoints:**

CDP breakpoints use `Debugger.setBreakpointByUrl` with a URL regex pattern. Use the source filename (not the full path):
```
bp session/route.ts 107
```
This matches `webpack-internal:///(rsc)/./app/api/session/route.ts`.

**Key differences from `node inspect`:**
- Breakpoint line numbers are 0-indexed in CDP, but the `cdp-debug.js` helper handles this.
- `eval` works the same way — evaluate expressions in the paused call frame.
- `list` shows the webpack-compiled source with source-map applied.
- HMR reloads create new scriptIds — re-set breakpoints after code changes.

**Fallback: `debugger` statement:**

If CDP breakpoints don't hit (e.g., due to webpack chunking or process mismatch), temporarily insert a `debugger` statement in the source code. Rules:

1. Use only after CDP `setBreakpointByUrl` has been tried and confirmed not to pause.
2. Remove the statement immediately after verification — do not commit it.
3. Record in `summary.md` that verification used an instrumented source, not the original code.
4. Be aware that inserting `debugger` triggers HMR, which may change execution timing or cause duplicate invocations (e.g., React re-renders). Verify that the behavior under `debugger` matches the behavior without it.

## Procedure

This is a strict sequence. Do not skip or reorder steps.

### Phase 1: Plan

1. **Identify the target**: the function, handler, or code path to verify.
2. **Define the scenario**: exact inputs, trigger command, expected observable outcome.
3. **Define the envelope**: list every file and line range in scope.
4. **Plan breakpoints** — set them only at these classes of locations:
   - Target function entry
   - First line after each async boundary (`await` resume, callback entry)
   - Branch entry points worth validating (if/else, switch cases taken)
   - Lines with side effects (writes, mutations, external calls)
   - Response/return/exit line

   If you cannot name *why* a breakpoint exists, do not set it.

5. **Initialize artifacts**: create the session directory:
   ```bash
   mkdir -p ./.agents/cache/verification/YYYYMMDD-<short-title>/screenshots
   ```
   Create `session.md` with target, scenario, envelope, and breakpoint table.

### Phase 2: Launch

Use two tmux panes: one for the **E2E execution** (the actual program running as a user would run it) and one for the **debugger** (attached to the running process). This is the core pattern — you observe real E2E behavior while inspecting internal state.

6. **Create two panes**:
   ```bash
   # E2E pane — runs the program
   tmux split-window -d -h -l '50%' -P -F '#{pane_id}' "cd <project-dir> && exec zsh"
   # Debugger pane — attaches to the running process
   tmux split-window -d -v -l '50%' -P -F '#{pane_id}' "cd <project-dir> && exec zsh"
   ```

7. **Start the program with `--inspect-brk`** in the E2E pane:
   ```bash
   tmux send-keys -t <e2e-pane> "node --inspect-brk <entry-file> [args...]" Enter
   ```
   The process pauses on the first line and prints: `Debugger listening on ws://127.0.0.1:9229/...`

8. **Attach the debugger** from the debugger pane:
   ```bash
   tmux send-keys -t <dbg-pane> "node inspect 127.0.0.1:9229" Enter
   ```
   Wait for `debug>` prompt. You are now controlling the E2E process from the debugger pane. Output (stdout/stderr) appears in the E2E pane.

9. **Set breakpoints**:
   ```bash
   tmux send-keys -t <dbg-pane> "setBreakpoint('<file>', <line>)" Enter
   sleep 1
   tmux capture-pane -t <dbg-pane> -p | tail -8   # confirm breakpoint set
   ```
   Repeat for each planned breakpoint.

10. **Trigger the code path**: send `cont` to run to the first breakpoint.

**Why two panes?** The E2E pane shows exactly what a user would see (stdout, stderr, exit code). The debugger pane lets you inspect variables, step through lines, and verify internal state. You cross-reference both: "the E2E pane shows exit 56 — the debugger confirms `execResult.exitCode === 56`."

#### Lightweight alternative: single-pane `node inspect`

For simple scripts or isolated functions (not full CLI E2E), you can use a single pane:

```bash
tmux split-window -d -v -l '30%' -P -F '#{pane_id}' "node inspect <entry-file>"
```

This is simpler but you lose the E2E observation — program output mixes with debugger output. Prefer the two-pane pattern for CLI tools and servers.

#### Detach and re-run

After a debugging session, detach (`.exit` in the debugger pane) and run the same scenario without `--inspect-brk` in the E2E pane to confirm clean E2E behavior. Then start a new `--inspect-brk` session for the next scenario.

### Phase 3: Step Through

For every executed owned line in the scenario, repeat this loop. All debugger commands go to `<dbg-pane>`. Cross-reference E2E output in `<e2e-pane>` at key points.

11. **Read the current line**:
    ```bash
    tmux send-keys -t <dbg-pane> "list(1)" Enter && sleep 1 && tmux capture-pane -t <dbg-pane> -p | tail -8
    ```

12. **State your expectation** — before executing, write down what you expect this line to do and what variable state should result. Record this in `steps.md` under the "Expected" column.

13. **Execute one step**:
    ```bash
    tmux send-keys -t <dbg-pane> "next" Enter && sleep 1 && tmux capture-pane -t <dbg-pane> -p | tail -10
    ```

14. **Inspect actual state**:
    ```bash
    tmux send-keys -t <dbg-pane> "exec <expr>" Enter && sleep 1 && tmux capture-pane -t <dbg-pane> -p | tail -5
    ```
    For complex objects, use `exec JSON.stringify(<expr>)`.

15. **Cross-reference E2E output** — at points where the program produces visible output (stderr messages, stdout data, exit), check the E2E pane:
    ```bash
    tmux capture-pane -t <e2e-pane> -p -S - | tail -10
    ```
    Verify that the internal state you just inspected matches what the user would actually see.

13. **Compare and record** — write the actual state in `steps.md`. Mark match (✓) or mismatch (✗). On mismatch, also append a JSON event to `events.jsonl`:
    ```json
    {"step":N,"file":"f.js","line":L,"expected":"...","actual":"...","match":false}
    ```

14. **Continue** — repeat from step 9 for the next line.

#### Stepping Rules

- **`next`** (step over): default. Use for all lines unless entering an owned callee.
- **`step`** (step into): only when the callee is owned code within the envelope.
- **`cont`** (continue): use to jump to the next breakpoint when crossing async boundaries or skipping non-owned code.
- **Never** step into `node_modules` or Node internals. If you accidentally enter one, immediately `out` back.

#### Breakpoints in Recursive Functions

Breakpoints inside recursive functions fire on **every** recursive call, not just the first. This makes stepping through recursive code very noisy. Preferred strategies:

1. Set the breakpoint at the **return line** instead of the entry, to inspect the result of each recursion level.
2. Set the breakpoint, inspect the first call, then **clear it** (`clearBreakpoint('<file>', <line>)`) and use `cont` to a downstream breakpoint.
3. Avoid breakpoints inside the recursive body entirely — set one just after the call site and inspect the final result.

#### node inspect Limitations

- **Block-scoped destructuring variables** (e.g., `for (const [k, v] of ...)`) may not be accessible via `exec` at the `for` line itself. Step into the loop body first (`next` once), then `exec` the variable.
- **Complex objects** display as `[ Object ]` or `[Object]`. Always use `exec JSON.stringify(<expr>)` for reliable inspection.
- **`exec` runs in the paused frame's scope.** If you accidentally step out of a function, you lose access to its locals.
- **ESM modules**: `require()` is not available in `exec`. Use the module's own imports or inline expressions only.

#### Async Rules

- Before an `await`: record the current state, note "async boundary".
- Use `next` to step over the `await`. Do NOT step into Promise internals.
- After resume: verify the resolved value and any state changes.
- For callbacks/event handlers: set a breakpoint at the callback entry, use `cont` to reach it.
- Mark async boundaries explicitly in the log: `[async: before await]`, `[async: resumed]`, `[async: callback entry]`.

### Phase 4: WebApp Verification (if applicable)

Only for web application code paths. Skip for CLI-only scenarios.

**Browser interaction** uses two levels depending on purpose:

- **Trigger-only actions** (open page, click button, submit form — just to reach a breakpoint): use `agent-browser` directly. Load its command syntax first with `agent-browser skills get agent-browser`.
- **Verification actions** (screenshots, accessibility tree inspection, network monitoring, structured test records): use `webapp-acceptance-checks`, which provides the conventions and artifact patterns.

This skill does not contain browser command syntax — load it from `agent-browser` or `webapp-acceptance-checks` as appropriate.

WebApp verification has **two stepping targets**: server-side code and client-side code. Both are stepped through with a debugger; the browser provides the E2E observation layer — equivalent to the E2E pane in CLI mode.

#### Server-side stepping

Targets: server actions, API route handlers, middleware, data fetching.

1. Start the dev server with `--inspect-brk` (or `--inspect` if the server stays running):
   ```bash
   tmux send-keys -t <e2e-pane> "node --inspect <server-entry>" Enter
   ```
2. Attach from `<dbg-pane>` as in Phase 2.
3. Set breakpoints in the handler/action under test.
4. **Trigger the request** from the browser (open page, click, submit form — use `agent-browser` directly for trigger-only actions).
5. The debugger pauses in the server handler. Step through server-side logic, inspecting variables.
6. **After the response is committed** (`res.end()`, return from server action, etc.), `cont` past the response.
7. **Then** verify the browser state — use `webapp-acceptance-checks` for screenshots, accessibility tree inspection, and network request checks.

**Important**: Do NOT take browser screenshots while the server is paused at a breakpoint. The browser can only show the pre-request state or a pending/loading state. Always `cont` past the response first.

#### Client-side stepping

Targets: event handlers, initialization logic, conditional rendering branches, state transitions.

Client-side code runs in the browser, not in the Node.js server process. Use Chrome DevTools Protocol (CDP) via the browser's built-in debugger.

**What to step through:**

| Target | Example | Stepping approach |
|---|---|---|
| Event handlers | `onClick`, `onSubmit`, form validation | Breakpoint at handler entry, step through logic |
| Initialization | `useEffect` setup, data fetching on mount | Breakpoint in the effect body |
| Conditional rendering | `if (isAdmin) return <AdminPanel />` | Breakpoint at the branch, verify which path is taken |
| State transitions | `setState`, reducer dispatch | Breakpoint after state update, inspect new state |

**What NOT to step through:**

| Avoid | Why |
|---|---|
| React's reconciliation/rendering loop | Framework internal — dozens of opaque frames. Set breakpoints in your component's render body, not in React's scheduler. |
| Virtual DOM diffing | Same — framework internal. Verify the rendered result via screenshot/snapshot instead. |
| Framework hooks internals (`useState`, `useEffect` internals) | Step over, not into. Inspect the return value or effect result. |
| Library event dispatch (synthetic events, router transitions) | Set breakpoints at your handler entry, not at the framework's event system. |

**Practical pattern for client-side:**

1. Open the page via `agent-browser`.
2. In the browser console or via CDP, set breakpoints in the target source file.
3. Trigger the action (click, navigation, form submit) via `agent-browser`.
4. The browser pauses. Inspect variables via the console or CDP `Runtime.evaluate`.
5. Step through owned code. When a frame enters `node_modules` or framework code, step out immediately.
6. After the handler completes, take a screenshot and snapshot to verify the UI result.

**Key rule**: React rendering is like Node's event loop — it's the scheduler, not your code. Set breakpoints in what your code does (components, handlers, effects), never in how React decides to call it.

#### Coordinating server + client stepping

For full-stack scenarios (e.g., form submit → server action → re-render):

1. Set server breakpoints in the handler.
2. Set client breakpoints in the submit handler and the post-response rendering branch.
3. Trigger the action via `agent-browser`.
4. **Client pauses first** (submit handler) → step through client validation/preparation → `cont`.
5. **Server pauses** → step through server logic → `cont` past response.
6. **Client pauses again** (if breakpoint in re-render/effect) → verify updated state → `cont`.
7. Take final screenshot. Cross-reference all three phases in `steps.md`.

### Phase 5: Wrap Up

18. **Stop the debugger**: `.exit` in the debugger pane, then kill both panes:
    ```bash
    tmux send-keys -t <dbg-pane> ".exit" Enter
    tmux kill-pane -t <dbg-pane>
    tmux kill-pane -t <e2e-pane>
    ```

19. **Write summary** — fill in `summary.md`:
    - Overall result (all matched / discrepancies found)
    - List of discrepancies with step numbers
    - Confidence level
    - Follow-up actions (bug fix, additional test, further investigation)

20. **Report to user** — summarize the verification result. If discrepancies were found, list them with file:line references.

## Stop Conditions

**Abort this skill immediately** if:

- A discrepancy suggests the bug is outside the envelope → switch to `debugging-practice`
- The scenario is taking more than ~40 owned-line steps → split into smaller scenarios
- The debugger becomes unresponsive → kill the pane, report partial results
- Source maps are unreliable (line numbers don't match source) → fall back to tests

## Required Artifacts

A verification is only valid if ALL of these exist in the session directory:

| File | Content |
|---|---|
| `session.md` | Target, scenario, envelope, breakpoints — filled before stepping |
| `steps.md` | Per-line log with expected/actual for every stepped line |
| `events.jsonl` | Machine-readable step events (at minimum, all mismatches) |
| `summary.md` | Result, discrepancies, confidence, follow-ups |
| `screenshots/` | Browser screenshots (WebApp only) |

**No log means no claim of verification.** If artifacts are missing, the verification is incomplete.

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| `address already in use` on inspect port | Another debugger or previous session still bound | Kill the old process, or use `--inspect=0` for a random port |
| Breakpoint set but never hits | Script not loaded yet (lazy loading) | Trigger the code path once without the debugger to force module load, then re-set the breakpoint |
| Breakpoint hits in wrong file | Ambiguous script name (webpack `eval-source-map`) | Use CDP `setBreakpointByUrl` with a more specific URL pattern, or fall back to `debugger` statement |
| HMR reloads lose breakpoints | Code edit creates a new scriptId | Re-set breakpoints after each HMR reload |
| Source map mismatch (line numbers don't match source) | Transpiler/bundler optimization | Verify with `list` that the displayed code matches your source. If not, fall back to tests |
| Stepping lands in `node_modules` or framework code | `step` entered a non-owned callee | Immediately `out` back to owned code. Use `next` by default |
| Server paused but browser times out | Breakpoint holds the response | `cont` past the response, then check browser state |

## Integration

- **`coding-practice`** verification guidance may invoke this skill for high-risk Node.js paths.
- **`debugging-practice`** may invoke this skill after isolating a suspect code path, to confirm the fix.
- **`webapp-acceptance-checks`** provides structured browser verification (screenshots, a11y inspection, network monitoring, test records). Use it when the browser interaction is verification, not just triggering.
- **`tui-acceptance-checks`** provides structured TUI / interactive CLI verification through tmux (send-keys, capture-pane, marker-isolated runs). Use it when the acceptance check does not need debugger-level introspection — this skill and that one are complementary, not overlapping.
- **`agent-browser`** is the low-level browser automation primitive. Use it directly for trigger-only actions (open, click, submit) that exist solely to reach a breakpoint or exercise a code path. Load its command syntax with `agent-browser skills get agent-browser` before first use.

## Helper Scripts

| Script | Purpose |
|---|---|
| `scripts/init-session.sh` | Scaffold session directory with artifact templates (optional — direct `mkdir` + manual file creation is equally valid) |
