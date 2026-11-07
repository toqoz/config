# Runtime mapping and web applications

This is the same full-target step-through method; a different runtime is not
permission to narrow it to a few checkpoints. The bundled Node driver does not
provide attach mode, source-map translation, or browser automation. Establish
the required debugger transport with supported host tools or a small local
adapter, and verify that adapter against the actual target before relying on
it. Do not claim these integrations were tested by the Node driver tests.

## Repair mapping

1. Identify the process/worker actually serving the scenario, loaded script URL,
   current revision, and executed script text. Inspect actual locations, not
   source filenames alone. Lazy loading and HMR can change the loaded scripts.
2. When bundled positions differ, repair the debug build and source maps or
   use a faithful non-minified build. Confirm source-to-runtime correspondence
   for every target executable statement. A textual anchor in generated code
   can help diagnose mapping; a nearby matching line is not sufficient proof
   that the original target is fully observed.
3. TypeScript type stripping can preserve positions for supported syntax;
   verify the actual runtime source. It is not equivalent to arbitrary bundler
   transforms. Preserve the original implementation, imports, and relevant
   runtime behavior when arranging direct execution.
4. Rebind and check actual breakpoint locations after reloads. Re-observe
   affected statements after changes. If instrumentation such as `debugger` is
   necessary, keep it narrow, record the alteration, remove it, and confirm
   behavior without it. Instrumentation alone cannot fix an unknown mapping.

## Browser and server coordination

Follow the host's current browser-tool rules and the project's acceptance
checks. This skill does not choose a competing browser or override host limits.
Use a supported debugger connection for code inspection; page interaction or
console logging alone is not stepping. Use the browser's paused call frame for
read-only evaluation, not a global context that happens to have similar names.

Start owned debug servers on loopback with distinct ports. Avoid globally
inherited inspector flags that cause workers to contend for one port; identify
the correct worker from its runtime and route, not a framework-specific port
claim. For an existing user-owned server, don't kill, restart, or resume it
without accounting for its ownership and current work.

Set breakpoints before triggering writes. Do not send a warm-up mutation merely
to load a lazy module. Use pending breakpoints, harmless loading, or disposable
fixtures. Track client retries while a server is paused and disable/reconcile
them for the scenario so they cannot duplicate writes.

For full-stack work, inspect changed client handlers, changed server work, and
changed response/render code in sequence, then resume them past the response
before checking final browser state. A screenshot while a response is held
proves only a pending state. Existing `webapp-acceptance-checks` handles the UI
acceptance evidence; debugger observations handle internal execution. For TTY
behavior use host PTY control or `tui-acceptance-checks` as appropriate. Neither
acceptance method replaces unfinished internal step-through verification.


## Evaluated browser/bundle recipe

A local Chromium + esbuild debug-bundle fixture was exercised with real CDP,
including a browser managed by `agent-browser`.
This validates this recipe, not a browser adapter in the bundled Node driver
or arbitrary framework/HMR builds:

1. Discover the loopback CDP endpoint and list page targets. Select by exact
   origin/URL, then validate a page-specific DOM marker in that target. The
   page title or target-list order is insufficient. Record the chosen target ID.
2. Enable Runtime/Debugger and identify the bundle in `Debugger.scriptParsed`.
   Read its actual bytes with `Debugger.getScriptSource`; compare the running
   script with the intended build. Resolve `sourceMapURL` relative to its URL.
3. Load the map with a real Source Map v3 consumer. In the fixture, Node's
   `node:module` `SourceMap.findEntry(generatedLine, generatedColumn)` translated
   actual V8 locations. Both inputs and returned original offsets are 0-based;
   convert once when presenting source positions. It does not set breakpoints.
4. Inspect `Debugger.getPossibleBreakpoints` in the executed script, translate
   the candidate locations, and bind with `Debugger.setBreakpoint` at the
   generated location. Check `actualLocation`, hit ID, original statement,
   and paused-frame values. Do not pass an original TS line straight to a
   generated-script breakpoint API.
5. Step and compare mapped locations and state across all scenarios. When a
   step throws or returns, await either another pause or completion of the
   triggered invocation. A browser stays alive after the invocation finishes;
   waiting only for another pause can hang after a correctly caught exception.
6. Remove breakpoints, repeat without stepping, and verify the DOM/result.
   Close only owned targets/profiles and the fixture server.

The negative checks rejected a wrong same-title page, stale source content,
and shifted mappings with apparently current source content. Rebuilding the
same original sources with a matching non-minified bundle/map repaired the
mismatch before verification continued. Real application transforms need their
own correspondence checks; this fixture is not blanket source-map support.


## Reuse agent-browser for browser management

When host rules permit `agent-browser`, prefer reusing its browser lifecycle
and page actions over writing another Chromium launcher. Read its installed
CLI skill first, use a task-owned named session, then obtain the running
browser's CDP endpoint:

```bash
agent-browser --session <task-session> open <fixture-url>
agent-browser --session <task-session> get cdp-url --json
```

The evaluated CLI exposes `data.cdpUrl` for a separate CDP client. Its browser
connection/page commands do not themselves supply the step/paused-frame
commands used here: the small client still sends `Debugger.*` requests and
collects pause/completion events. Use the CLI for trigger/acceptance actions
and close the owned session with `agent-browser --session <task-session> close`.

T3 preview tabs and an agent-browser session are different browser targets;
this endpoint does not attach to a preview tab. Follow the host's browser
selection/fallback rules, preserve user-owned tabs, and validate the actual
selected target before stepping. An absent preview Debugger API does not make
console evaluation equivalent to a real debugger.
