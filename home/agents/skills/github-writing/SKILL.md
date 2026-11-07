---
name: github-writing
description: >
  Write and revise GitHub issue and pull request titles and descriptions.
  Use whenever drafting, creating, filing, opening, editing, or updating an
  issue or PR, including "open an issue", "create a PR", "write the title",
  or "update the description" when the context is a GitHub issue or PR.
  Apply technical-writing followed by unslop to both fields.
  In creation or update workflows, use this skill for the wording while the
  owning workflow handles publication. Also use for PR-scoped release notes.
  Do not use for commit messages, code review itself, or CI and merge operations
  that do not involve writing an issue or PR title or description.
---

# GitHub writing

Help readers understand the problem or change, inspect the evidence, and take
the next action. This skill owns content and title conventions. General prose
rules belong to `technical-writing` and `unslop`.

## Required writing order

1. Gather the facts and repository-specific instructions below.
2. Read and apply `technical-writing` when drafting both the title and body.
   For titles and short issue/PR bodies, apply its prose layers without forcing
   a Diátaxis document structure. Keep required repository templates intact.
3. Read and apply `unslop` to both fields after the content is complete. Repeat
   that final pass after substantive revisions, then check factual accuracy.

Both companion skills are required, even for short edits and outside
poteto-mode. Follow this order from poteto-mode's Opening a PR playbook without
activating the rest of that mode. If either companion is unavailable, report
that gap instead of silently substituting generic writing advice.

## Ground the draft

- Establish whether this is an issue or PR and what its readers need to do.
- Read project instructions, relevant examples, and `.github` issue forms or
  PR templates. Project-specific rules override the defaults below, including
  title conventions and required fields. Do not replace a required template.
- For issues, use the user's report, reproduction, logs, and confirmed facts.
  Distinguish observed behavior, expectations, suspected causes, and unknowns.
- For PRs, inspect the actual diff and compare range, related issues, and the
  current description. Claim only changes and verification supported by them.
- Use the product's visible labels, routes, and actions in user-facing scenarios.
  Do not paraphrase a CTA into words the reviewer cannot find on screen.
- For missing evidence, state the gap or ask only when it prevents a useful
  draft. A proposed verification plan is not a completed check.

## Default title rules

Apply these only when the project has no title convention:

- **PR:** normally use a Conventional Commits prefix, such as
  `feat(reports): add CSV export` or `fix(auth): reject expired invitations`.
  Choose a type and optional scope that honestly describe the change. Do not
  force a prefix onto a purpose-based integration or promotion PR combining
  several kinds of change. `Promote main to production` or an established
  `Main Release YYYY/MM/DD` title can stand without an artificial type.
- **Issue:** do not add a Conventional Commits prefix. Describe the observed
  problem or desired outcome, such as `CSV export loses zero-valued amounts`.
  Do not turn that into `fix: ...` merely because the issue reports a bug.

## Issue content

Use the smallest structure that lets someone investigate or decide:

- **Bug:** observed and expected behavior, triggering conditions, reproducible
  steps or a minimal example, relevant environment, and focused evidence.
  Mark frequency and suspected causes as unconfirmed when appropriate.
- **Feature or improvement:** the current problem, who needs the outcome,
  desired behavior, acceptance criteria, and material constraints or non-goals.
  Keep a proposed implementation distinct from an agreed requirement.
- **Investigation or decision:** the question to resolve, known facts, unknowns,
  relevant alternatives, and what result would settle the question.

Do not invent a root cause, user impact, acceptance decision, or implementation
commitment to fill a section. Link supporting material instead of dumping logs.

## PR content

Lead with the concrete problem and resulting behavior. Include only what helps
reviewers assess the patch:

- The change and its reason, important scope boundaries, compatibility,
  migrations, rollout actions, and risk where relevant.
- Verification that actually ran, its result, and remaining gaps. Use a short
  reproduction and corrected result for behavior fixes. For internal fixes,
  explain the faulty mechanism when it helps establish correctness.
- For refactors, state what behavior is preserved and why the structure changed.
  Do not imply new capability when the patch changes only tests or docs.
- For UI changes, show the relevant component, route, states, and device context.
  Prefer isolated component or Storybook evidence when that is what changed.
  Add screenshots or video only when they help review, with useful captions
  and alt text. Redact sensitive details before publication.
- Put extensive evidence in linked GitHub reviews, checks, or other accessible
  artifacts. Keep the description a briefing, not an execution transcript.

For PR-scoped release notes, verify the included commits/PRs and explain the
user or operator impact and required actions. Do not duplicate the full body.
This skill does not change a release workflow's extraction rules or take over
its generated sections.

## Revise existing text

Preserve useful notes, links, attachments, and required fields. Update stale
claims to match current evidence, and remove content the user asked to cut.
Respect automation-owned markers and use the owning workflow's update path
rather than replacing its blocks manually. Keep the title and description
consistent without repeating the same text in both.

Writing a draft does not authorize creating or editing a remote issue or PR.
When publication is already authorized, use the final fields in that operation
and follow the host's publication and linking rules.
