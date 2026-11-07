---
name: webapp-test-strategy
description: >
  Choose test levels and improve existing coverage for server-side web apps
  with browser frontends. Use when adding or reviewing tests, deciding between
  unit, integration, and end-to-end coverage, or simplifying a test suite.
  Prefer integration coverage for application behavior and a narrow E2E layer.
---

# Webapp test strategy

Choose the smallest test that includes the boundaries needed to verify the
behavior credibly. Optimize for useful confidence, actionable failures, and
maintenance cost, rather than test count or a prescribed coverage percentage.

## Choose the level

- Use existing type, lint, compiler, and schema checks for the properties they
  enforce. Avoid runtime tests that only repeat those guarantees. Static types
  do not establish the validity of untrusted runtime inputs.
- Use unit tests for concentrated pure logic: calculations, transformations,
  parsing, validation, and policy decisions. Cover important edge cases cheaply.
- Default to integration tests for application behavior across meaningful
  boundaries: routing/middleware through responses and persistence, jobs through
  state changes, or component interactions with real framework behavior.
- Use browser/component tests or E2E when the failure depends on that runtime.
  Reserve full E2E journeys for critical wiring, browser-dependent behavior,
  and regressions lower levels cannot catch. A UI alone does not justify E2E;
  a component test running in a browser is not automatically a full E2E journey.
- Add accessibility, visual regression, or external contract checks when their
  particular risk warrants them; they are not mandatory layers for every change.

Include the boundary responsible for the risk: authorization checks need the
relevant middleware, and persistence checks need the relevant database behavior.
Do not mock away the connection the test is meant to prove to make it smaller.

## Dependencies and assertions

Use real internal dependencies that participate in the behavior: routing,
middleware, application services, persistence, and framework integration.
Replace external payment, messaging, third-party API, LLM, or analytics services
at their boundary. Assert the outgoing request and the application's handling
of success and failure. Use contract/adapter tests when that external boundary
itself needs verification.

Read and apply pstack's `principle-test-behavior-not-implementation` when writing,
revising, or deciding to keep individual tests; it owns assertion quality.
For a bug fix, use `tdd` when its failing-before workflow applies. An expensive
integration setup can make a new regression test impractical; that does not
make integration tests categorically undesirable.

## Improve or remove existing tests

Within the requested work, review tests touched by the change as well as tests
you add. A request to audit a suite can broaden that scope; ordinary feature
work does not authorize unrelated suite cleanup.

- Identify the contract and failure mode each test protects. Investigate unclear
  purpose before deleting it. Rewrite weak assertions, implementation coupling,
  excessive mocks, or broad snapshots into focused behavior checks under the
  pstack principle above.
- Consolidate or remove duplicate coverage only when it adds no distinct failure
  signal. Similar assertions can belong at multiple levels when they protect
  different risks, such as calculation, server authorization, and browser wiring.
- Remove tests for retired behavior or guarantees already enforced elsewhere.
  Before removing or moving a still-relevant test, identify what coverage would
  be lost and verify the replacement catches that failure mode. Keep unique
  regression protection rather than deleting a test merely because it is costly.
- Fix flaky tests: diagnose timing, isolation, fixtures, and environment; narrow
  or move the check when appropriate. Do not normalize ignored failures or
  remove a uniquely needed runtime check just to make the suite green.

## Verification and reporting

This skill chooses permanent coverage. It does not waive repository requirements
for browser, TUI, or debugger verification of the current change. Choosing not
to add E2E is separate from performing required acceptance checks.

Run affected checks after changes. Where a placement, rewrite, or deletion needs
explanation, briefly state the behavior/failure mode, boundaries included, and
coverage retained or gaps left. Routine decisions need no checklist report.
