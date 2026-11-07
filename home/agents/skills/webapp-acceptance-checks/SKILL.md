---
name: webapp-acceptance-checks
description: >
  Verify changed webapp behavior in the real browser when automated coverage
  is insufficient, including user interactions, rendering, and visible results.
  Reuse project verification skills and pstack control-ui for the harness;
  this skill defines acceptance evidence and task/session ownership.
---

# Webapp acceptance checks

Verify the changed behavior through the user's actual surface. A successful
build, HTTP response, or internal state setter is not browser acceptance.
Follow the repository's coverage exemptions and verification requirements.

## Reuse the harness

- Prefer a working project-local verification skill and its mapped journeys.
  Use existing browser tests, Storybook/component harnesses, and launch commands
  where they reach the changed behavior. For a missing harness, read and apply
  pstack's `control-ui`; do not duplicate its generic setup or CDP recipes here.
- When a reusable project skill is needed, use `create-verification-skill`;
  use `maintain-verification-skill` for drift in an existing one. Neither is a
  mandatory detour for a small check. This skill does not activate poteto-mode.
- Follow the host's browser selection rules. Under T3, use its preview tools
  when browser work is requested; use agent-browser when the host permits it
  or the user requests it. Load the installed agent-browser skill and current
  CLI guide before use, and use a task-owned named session. Do not take over
  another agent's or the user's browser session.

## Keep the application available

Reuse an existing instance only after checking its URL, build, configuration,
and app-specific readiness. An open port alone can belong to another app.
When starting an instance, use the project's foreground launch command through
a host-managed long-lived command/terminal session. Retain its session identity,
PID/ownership, port or URL, and logs across browser tool calls. For several
services, follow the project's dependency order and readiness checks.

Do not wrap a single `agent-browser open` or snapshot command in a server
lifetime: those commands finish before the later click or verification call.
Keep the server alive for the whole scenario. Wait for the actual usable route,
authentication, seed state, and required dependencies, not a fixed delay or TCP
connection. Read startup failures from logs; do not kill a port occupant or
silently verify a different instance. Static pages may need no server, but use
the real app origin when routing, modules, cookies, or network behavior depends
on it.

## Drive and observe

1. Define the scenario, inputs, expected visible behavior, and relevant effects.
   Include changed loading, empty, error, and success states where applicable.
2. Inspect the current page and choose controls from a fresh accessibility
   snapshot: prefer roles, visible labels, and stable project selectors.
3. Perform actual user actions, wait for their concrete result, and inspect the
   updated page. Confirm relevant requests/responses and persisted effects as
   well as visible state. A final screenshot alone does not prove the action.
4. Capture decisive before/after states. Prefer viewport-fit screenshots; use
   full-page capture only when it serves the scenario. Read back saved images
   before publishing so blank margins, missing states, or bad crops are caught.
5. For genuinely human-only login/consent, use the supported visible browser
   handoff, report the exact blocker, and resume from confirmed state. Do not
   fabricate credentials or claim an unobserved authenticated journey passed.

## Evidence and completion

Keep one concise record under `.agents/cache/testing/<run>/`: target revision,
URL/configuration, scenario, actions, expected/observed outcomes, artifact paths,
and pass/fail or remaining gaps. Link relevant screenshots or filtered network
logs; redact tokens, cookies, and other secrets before saving or publishing.
Reuse the project harness's record instead of maintaining duplicate logs.
Put durable results in `.agents/share/` or the authorized review surface when
needed; do not publish remotely merely because verification produced evidence.

Stop only owned application instances, browser tabs/sessions, and temporary
profiles after the scenario, following host rules. Preserve evidence and leave
pre-existing user resources untouched. Report tested behavior, results, gaps,
and cleanup; starting the browser or opening a page is not completed acceptance.
