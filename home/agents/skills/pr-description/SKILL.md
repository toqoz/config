---
name: pr-description
description: >
  Write or revise high-signal GitHub pull request titles, bodies, and PR-scoped release-note snippets. Use only when the task is specifically about PR wording: drafting a PR title/body, preparing text for gh pr create or gh pr edit, updating a PR description, writing a changelog-style note for a PR, or responding to critique of PR copy. Do not use as the workflow controller for creating, merging, release, or stacked-PR flows; use the relevant GitHub workflow skill for those operations and apply this skill only to the wording.
---

# PR Description

Write PR descriptions for reviewers, future maintainers, and release readers. A good PR body explains what changed, why it matters, how to review it, and what evidence supports it — without narrating the agent's process.

Use this skill when drafting or editing PR title/body text, including the title/body fields passed to `gh pr create` and `gh pr edit`. If the user asks to create, release, stack, merge, or monitor a PR workflow, use the relevant GitHub workflow skill for that operation and apply this skill only to the wording.

## Core principles

- Optimize for the reviewer's next action: understand the change, inspect the right areas, and trust the verification.
- Describe product behavior in user terms when the change affects users.
- Describe implementation details only when they are needed to understand risk, architecture, or review focus.
- Keep headings concrete. Avoid meta headings like `UI review context`; write the UI review content directly under `Summary`, `Screenshots`, `Review notes`, or `Verification`.
- Do not include internal deliberation, false starts, tool chatter, or why an earlier draft was changed.
- Do not over-template. Use the smallest structure that covers the change.

## Gather evidence before writing

Read the source of truth before composing. Do not invent impact, verification, screenshots, or rollout notes.

- Inspect the relevant diff, commits, issue, or existing PR body so the title and first summary bullet match the actual change.
- Check `.github/pull_request_template*` or repository-specific PR guidance. Preserve required template fields even when choosing a shorter structure.
- Collect the verification that actually happened: commands, tests, browser checks, Storybook checks, screenshots, logs, or reproduction notes.
- For PR-scoped release-note snippets, inspect the compare range, included PRs or commits, breaking changes, migrations, rollout flags, and user/operator actions before summarizing release impact.
- For user-facing or UI changes, read the visible UI copy, route names, component/story names, button labels, form labels, and error/empty-state text. Acceptance-flow wording should use the same labels and CTAs a reviewer sees in the product.
- For visual changes, collect or request the screenshots/design references needed to compare the changed state. Component-only changes usually need Storybook or isolated browser evidence, not just a full-page screenshot.
- If evidence is missing, ask for it or mark the item as not verified. Never phrase an unchecked assumption as completed verification.

## First classify the PR

Before writing, classify the change by reviewer focus. Mixed PRs can combine sections, but one focus should usually lead.

| PR type | Lead with | Useful supporting detail | Usually omit |
| --- | --- | --- | --- |
| UI / visual change | What the reviewer should see and compare | Screenshots, Figma/design references, viewport/device notes, states covered, cropped component captures when useful | Low-level CSS mechanics unless risky |
| User-facing feature | New capability and user workflow | Entry points, UI labels/CTA wording, permissions, edge cases, rollout/migration notes | Implementation trivia not relevant to behavior |
| Behavior-focused bugfix | User-visible wrong behavior and corrected behavior | Reproduction summary, affected scenarios, regression test/manual check | Deep root-cause detail unless it changes review risk |
| Implementation-focused bugfix | Faulty internal mechanism and why the fix is correct | Root cause, invariant restored, failure mode, targeted tests | Product claims that were not verified |
| Refactor | Preserved behavior and reason for restructuring | Before/after boundaries, migration path, safety checks | Feature-like language suggesting behavior changed |
| Config / infra / CI | Operational effect and blast radius | Commands, environment, rollback, compatibility | User-facing screenshots unless relevant |
| Tests only | Coverage added and bug/risk guarded | Test level, fixture changes, what remains untested | Claims of product change |
| Docs only | Reader task enabled by the docs | Audience, moved/removed docs, source of truth | Code verification unrelated to docs |

## Recommended body shapes

Choose one of these, then trim sections that do not add value. If the repository has a PR template, keep its required fields and adapt the content inside that structure instead of replacing it wholesale.

### UI / visual PR

```markdown
## Summary

- What changed visually or interactively
- Which page/component/state is affected
- Any important scope boundary

## Screenshots

### [Storybook story / route / viewport / state]

<img src="..." alt="Clear description of the UI state" width="...">

## Verification

- Static checks / tests
- Browser or Storybook checks, with exact story/route, states, and viewports covered
```

Good UI body text says what to review directly:

- Good: `The reservation day-list rows now fill the content frame, while other reservation views keep their existing page padding.`
- Avoid: `UI review context: the Figma frame places rows across the content column.`

For component-only changes, prefer Storybook or isolated browser screenshots of the changed component/state. Crop screenshots to the relevant component or changed region when a full-page capture would make the reviewer hunt for the difference. Include wider page screenshots only when layout context is part of the review.

When comparison matters, add only the useful comparison aid:

```markdown
## Before / After

- Before: ...
- After: ...

## Design reference

- Figma: ...
- Intentional difference: ...
```

### User-facing feature PR

```markdown
## Summary

- User can now ...
- This is available from ...
- Important limitations or unchanged behavior ...

## Behavior

- Main flow, using the same visible labels, CTAs, and page/component names users see
- Empty/error/permission/edge states, if relevant

## Verification

- Automated tests
- Manual acceptance checks for critical flows, written with the same UI wording a reviewer will follow
```

Use `Behavior` when the workflow has multiple states. For a small feature, keep everything in `Summary`. Acceptance-flow wording should line up with the UI: prefer `Open Settings, choose “Team invites”, then select “Resend invite”` over paraphrases that do not appear on screen.

### Behavior-focused bugfix PR

```markdown
## Summary

- Fixed [wrong behavior] when [condition]
- Users now see / can do [correct behavior]

## Verification

- Regression test or reproduction check
- Related static checks
```

Add `Before / After` only when it makes the fix easier to review:

```markdown
## Before / After

- Before: ...
- After: ...
```

### Implementation-focused bugfix PR

```markdown
## Summary

- Fixed [internal failure mode]
- Restored [invariant/contract]
- Affected callers/components ...

## Root cause

[Short explanation of the incorrect assumption or broken mechanism.]

## Verification

- Targeted tests proving the invariant
- Broader checks if relevant
```

Keep `Root cause` short. If the cause is obvious from `Summary`, omit it.

### Refactor PR

```markdown
## Summary

- Moved / split / renamed ...
- Preserved behavior for ...
- Motivation: ...

## Safety

- Equivalence check, tests, typecheck, or hash/build comparison
- Known non-goals
```

Use `Safety` instead of `Verification` when the main reviewer question is "did behavior stay the same?".

### Config / infra / CI PR

```markdown
## Summary

- Operational change
- Scope / environments affected
- Rollback or compatibility note, if relevant

## Verification

- Commands run
- CI/build evidence
```

### Tests-only PR

```markdown
## Summary

- Coverage added or changed
- Bug, invariant, or risk the tests guard
- Important fixture or test-data changes, if relevant

## Coverage

- Test level: unit / integration / browser / fixture / contract
- Scenarios now covered
- Known gaps or non-goals, if useful

## Verification

- Test command or CI evidence
```

Do not imply product behavior changed unless the PR actually changes product code.

### Docs-only PR

```markdown
## Summary

- Reader task or confusion addressed
- Docs added, moved, removed, or made source-of-truth
- Audience: users / operators / contributors / maintainers

## Reader impact

- What a reader can now understand or do
- Important redirects, removed pages, or source-of-truth changes

## Verification

- Link check, docs build, preview, spell check, or reviewer read-through
```

Avoid code verification that is unrelated to the docs. If the docs describe behavior, mention the source used to confirm that behavior.

## Titles

Use the project's title convention when present. Otherwise prefer Conventional Commits style:

```text
feat(scope): add reservation status filters
fix(dash): show reservation row statuses
refactor(api): split session refresh helpers
```

Title guidance:

- Name the affected area in the scope when useful.
- Use the user-visible behavior for user-facing changes.
- Use the internal mechanism for implementation-only fixes.
- Avoid vague titles like `update UI`, `fix bug`, or `misc changes`.

## Screenshots and images

Include screenshots when visuals, layout, screenshots in a PR template, or reviewer confidence depends on them.

- Use meaningful captions: Storybook story or route, viewport, state, scenario, theme, and any important data setup.
- Use alt text that describes the UI state, not the filename.
- For UI component changes, include Storybook or isolated browser screenshots when available. Cover the changed states rather than only the happy path.
- Crop screenshots to the changed component or region when the surrounding page is noise; keep the full page only when page-level layout context matters.
- Before uploading or embedding screenshots, redact tokens, cookies, customer data, personal information, internal URLs, unreleased confidential content, and any other sensitive details.
- Include only enough images to review the change; avoid dumping every capture.
- If local images need GitHub URLs, use the `github-pr-images` skill, then embed the returned URLs yourself.

## Verification section

Verification should be concrete and scoped to the PR.

Good examples:

```markdown
## Verification

- `npm run tsc`
- `npm run lint`
- Storybook browser check: `ReservationStatusRow/AllStatuses` at tablet viewport; cropped screenshot shows the row fills the 904px container and all status variants are visible
```

```markdown
## Verification

- Added regression test for expired invitation reservations
- Manual acceptance: opened `Reservations`, selected `Expired invitations`, and confirmed the visible status text changed from `Pending` to `Expired`
```

Avoid vague evidence:

- `Tested locally`
- `Looks good`
- `Should work`

## PR-scoped release notes

Use release-note style wording only when the PR body, template, or user asks for it. Keep the audience in mind: release notes are usually for users or operators, not code reviewers.

- Lead with the user-visible or operational outcome, not the implementation mechanism.
- Keep it shorter than the PR summary unless the release template requires detail.
- Mention migrations, rollout flags, breaking changes, or follow-up actions when they affect the release reader.
- For release PRs or changelog notes, verify the compare range and included PRs/commits before claiming what shipped.
- Do not duplicate a full PR body under a `Release notes` heading.

Good release-note snippets:

```markdown
- Added CSV export for reservation reports. Operators can export filtered results from `Reports` > `Reservations` without requesting a database pull.
- Breaking: removed support for legacy invite tokens. Existing tokens created before 2026-06-01 must be regenerated after deploy.
```

Avoid release-note snippets that are implementation-only or unverifiable:

```markdown
- Refactored reservation service internals.
- Various fixes and improvements.
```

## Review notes

Use `Review notes` sparingly when the reviewer needs directed attention that does not fit in `Summary`.

Good uses:

- Design tradeoff chosen between two plausible approaches
- Deliberate non-goal
- Risky area worth extra attention
- Migration or rollout concern

Do not create a review-notes section just to explain normal implementation details.

## Editing an existing PR body

When revising a PR body after user feedback:

1. Preserve useful existing content and links.
2. Remove sections the user says are unnecessary.
3. Convert meta-context headings into direct reviewer-facing prose.
4. Keep screenshots and verification current with the latest pushed commit.
5. Re-read the final body once as a reviewer: it should answer "what changed, how do I review it, and what evidence exists?" quickly.

## Final checklist

Before publishing the body, check:

- Is the PR classified correctly?
- Does the title match the actual change?
- Does the first bullet/paragraph say the most important reviewer-facing fact?
- Are behavior changes written from the user's perspective when applicable?
- For user-facing flows, do acceptance/manual steps use the same visible UI labels, CTAs, and page/component names a reviewer will see?
- Are implementation details included only where they help review?
- For UI component changes, are Storybook or isolated browser screenshots included when useful, with changed states covered and crops focused on the relevant region?
- Are screenshots included only when useful, with clear captions and alt text?
- Is verification concrete and limited to checks that actually ran?
- Is there any agent/process/meta wording that should be removed?
