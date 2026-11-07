---
name: step-through-code
description: >
  Proactively step through all changed executable owned code in a real debugger,
  predicting and inspecting its behavior before considering verification done.
  Use when asked to step through code, or when verifying non-trivial changed
  JavaScript/TypeScript control flow, side effects, or async behavior. Not a
  substitute for browser/TUI acceptance checks or a proof of race freedom.
---

# Step through code

Follow the practice in Steve Maguire's *Writing Solid Code*: run the code you
wrote under a debugger, predict what it will do, and check what it actually does.
The goal is all of the target code, not a sample of important breakpoints.

## Define the work

- Identify the changed executable owned statements and immediate owned calls
  needed to understand them. Include branch bodies, guards, exception paths,
  async resumptions, and callbacks. Record the source revision and target in a
  short coverage checklist under `.agents/cache/verification/<task>/`.
- Choose inputs/scenarios that collectively execute the entire target. Split
  large scenarios without dropping lines. Each statement and branch outcome
  needs a scenario and an observed result, not merely a breakpoint or test hit.
  Blank lines, comments, types, and declarations with no executable behavior do
  not require a debugger stop. One runtime location can cover several source
  expressions only when their mapping and effects are understood and inspected.
- Scope does not include framework/library internals. Do not exclude owned code
  merely because it is hard to trigger. Investigate allegedly unreachable code:
  fix a genuine defect or explain why the case is impossible; unresolved reachability
  remains unfinished work. Do not demand every combination or loop iteration.
- Use disposable fixtures and controlled dependencies for writes and failures,
  preserving the actual implementation and relevant contracts. Control retries
  and reset state between scenarios so paused requests cannot duplicate effects.

## Establish trustworthy observation

Use the host's command/session lifecycle, with separate program output and
debugger control. No tmux is required. For directly executed Node.js code,
including supported TypeScript type stripping, use the bundled
[driver](references/node-driver.md). Other runtimes need an appropriate real
debugger with the same prediction, stepping, and evidence requirements.
For bundles, servers, or browser code read
[runtime mapping and web applications](references/runtime-mapping.md).

Check the actual process, loaded script URL, source text, and stopped location
against the current target before trusting any step. An accepted breakpoint is
not necessarily resolved, and a resolved breakpoint has not necessarily hit.
Repair stale builds, wrong processes, optimizations, and source-map mismatches
until you can observe the intended code correctly. Arrange a faithful debug
build or run the original source directly when appropriate; do not copy the
logic into a simplified substitute and call that verification of the application.
A green test does not discharge a missing debugger observation.

## Predict, step, inspect, compare

For each executed target statement:

1. Before advancing, record the expected control flow, values, and effects.
   The Node driver requires `--expect` and records it before moving.
2. Step over by default; step into owned calls inside the target. Use continue
   only across already inspected code or non-owned scheduling to a verified
   breakpoint. Do not jump over target statements and mark them complete.
3. Inspect the resulting locals, branch choice, return/exception, and effects.
   Use read-only evaluation in the paused frame. Do not mutate values, invoke
   business operations, or re-run a request to inspect its result.
4. Compare against the expectation and link the observed location/state to the
   checklist. Loop bodies may need zero/one/many inputs; async code needs both
   pre-suspension and resumed/callback state. Keep unobserved paths outstanding.

On a mismatch, preserve the paused location, relevant stack and values. Decide
whether the expectation, implementation, or observation setup is wrong. Diagnose
with `debugging-practice` as needed, correct the cause, and step the affected
code again against the revised source. Do not redefine the expectation merely
to match the observed value or discard earlier discrepancies.

## Finish the verification

- Reconcile the checklist against actual debugger observations. No complete
  claim while target statements, branch outcomes, mapping, or discrepancies
  remain unresolved. Closing a scenario is not closing the target.
- Run the same scenarios without debugger pauses and inspect actual output and
  effects. This checks interference from stepping; it does not replace stepping.
  A paused async trace shows one execution order, not freedom from races.
- Stop owned targets before disconnecting an incomplete debugger session:
  detaching can execute the remaining code. Use the driver's `stop`; let a
  completed target exit normally so its real exit code is preserved. Stop the
  host command session afterward. Do not kill another developer's process.
- Report the target/revision, scenarios, inspected outcomes, discrepancies and
  repairs, output/effect checks, and cleanup. Keep a concise checklist and the
  driver's actual transcript; no duplicate per-line hand-written log is needed.
  Preserve useful results in `.agents/share/` when worth keeping.

Difficulty observing is work to resolve, not a reason to stop at “unverified.”
Try the relevant process/build/mapping remedies and continue. If an external
constraint truly prevents completion, report the concrete blocker, attempts,
and outstanding target. Do not invent coverage or silently substitute tests.
