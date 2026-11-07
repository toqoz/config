---
name: commit
description: Create a git commit with a well-structured conventional commit message. Use this skill whenever the user asks to commit, create a commit, write a commit message, or stage and commit changes — including only the current work, only staged changes, or everything, even if they just say "commit this" or "let's commit". Always use this skill rather than ad-hoc git commit commands.
---

# Commit

Create coherent commits that explain what changed and why.

## Authorization and Branches

A commit request covers the current work, not commits for later work, unless
an authorized workflow includes them. Push and PR creation require an explicit
request; a previous request does not carry over to later fixes.

Before committing or pushing, inspect the branch. Treat the repository's
default branch and shared branches such as `main`, `master`, `develop`, `dev`,
`staging`, `prod`, `production`, and release/stable branches as protected.
Do not commit directly there unless project or user instructions permit it;
otherwise create a topic branch under the repository's branching rules.
Ask before pushing a protected branch unless the user explicitly requested
pushing that branch.

## Arguments

- `--push`: push after committing. Check the remote and upstream first;
  use `git push -u origin HEAD` when no upstream exists, otherwise `git push`.
- `--pr`: implies push, then create a PR with the host's PR tool when
  available, otherwise the repository's forge CLI. Follow `github-writing`
  for wording and any active workflow's PR procedure. Follow host rules for
  PR linking and reporting; do not start a PR workflow for a commit-only ask.

If a post-commit prerequisite is missing, retain the completed commit and
report what blocked the requested push or PR.

## Commit Scope

Choose the scope from the user's request before changing the index:

| Request | Scope |
|---------|-------|
| "commit", "commit this work", or no explicit scope | **Work (default):** changes belonging to the work discussed in this conversation, or the specific work the user names. |
| "commit staged", "commit the index" | **Staged only:** the existing index exactly as selected. |
| "commit everything", "commit all changes" | **All:** all staged, unstaged, and untracked changes. |

Infer the work from the conversation; ask only when the intended scope or a
change's ownership cannot be determined. An existing index does not override
the default work scope. An empty selected scope is a no-op; report it rather
than falling back to another scope. For contradictory scope requests, clarify.

For work scope, classify files and hunks as belonging to the selected work,
other work, or uncertain. Include only the selected work, including relevant
new files. Preserve unrelated working-tree changes. If unrelated changes are
already staged, stop before modifying the index and ask how to handle them;
do not silently unstage or commit them. Summarize inclusions and exclusions.

Check whether the selected changes depend on excluded uncommitted work
(e.g. imports or symbols introduced elsewhere). If they do, explain the
specific dependency and ask whether to include it, commit it first, or
restructure the work. Do not silently broaden the scope. Verify the selected
result independently of excluded changes where practical; a passing check on
the full working tree alone does not prove the selected commit works.
Use a disposable checkout of the selected tree for isolated checks; do not
stash or rewrite the active working tree to hide excluded changes.

For staged-only scope, do not add, remove, or rewrite index entries. Inspect
unstaged changes and report related changes that will be excluded. If the
index is incomplete or should be split, explain and ask before changing it.
An empty index means there is nothing to commit.

For all scope, include every uncommitted change unless repository rules
exclude it; report any such exclusion. Plan coherent commits rather than
assuming all changes belong in one commit.

## Workflow

1. Inspect `git status --short`, staged and unstaged diffs (including binary,
   rename and mode summaries), and `git ls-files --others --exclude-standard`.
2. Select the scope above and plan coherent commit units. Account for existing
   staging; ask before unstaging or repartitioning related staged changes.
3. Apply pre-commit gates required by repository instructions or an active
   workflow, such as a cleanup pass. This skill does not activate those
   workflows or duplicate their trigger lists. Limit cleanup to the selected
   changes, preserving excluded work. In staged-only scope, report proposed
   cleanup and ask before applying edits or restaging.
4. Stage one unit at a time under Staging below. Skip staging for staged-only.
5. Inspect `git diff --staged` and run `git diff --staged --check`. Run the
   repository's required pre-commit checks against the selected tree; use a
   disposable checkout when excluded changes could affect the result. Do not
   stash or rewrite the active working tree for verification.
6. Write the message under Message Format, applying any active workflow's
   writing standards. Commit through stdin:
   ```bash
   git commit -F - <<'EOF'
   type(scope): short description

   Explain the reason and relevant decisions.
   EOF
   ```
7. Repeat for the remaining selected units. Regenerate patches after every
   commit. Any cleanup, hook output, or review fix that changes selected
   content invalidates affected checks and reviews; rerun required checks
   before committing and do not claim an earlier review covers unseen edits.
8. Perform requested push/PR actions, inspect `git status`, and report commits,
   amendments, and intentionally excluded staged or unstaged changes.

## Staging

- Do not use whole-file `git add` for text changes. Stage inspected patches
  with `git apply --cached`, running `--check --recount` before applying.
- If a path has no staged changes and every change belongs to the current
  commit unit, apply its inspected patch unchanged. Do not retype its hunks.
- For mixed files, select only the relevant hunks from the captured patch.
  Verify the staged diff matches the intended content after any patch edits.
- Include binary, rename, deletion, mode, symlink, and submodule changes when
  they belong to the unit; do not silently omit them. For indivisible metadata
  or non-text changes, exact-path `git add` is allowed with an explanation.
- If application fails, inspect index and working-tree state and regenerate
  the patch; do not retry blindly or discard unrelated changes.

Read [Patch staging](references/patch-surgery.md) when preparing patches,
including new files, partial hunks, or unusual filenames.

## Amending

Amend a commit only when all of these are true:

- You created it in this session and have not pushed or shared it.
- You created it in the current turn and have not reported it to the user.
- The fix only completes the stated change, such as a typo, formatting,
  lint, or a missed part of the same change.

Otherwise keep the correction in a new commit that explains what changed and
why. User-feedback corrections and correctness bugs found by reviews or tests
get separate commits, even before reporting. When visibility is uncertain,
treat the commit as already reported. Say when you amend.

Explicit requests to split, amend, or squash override these defaults. Reorder
or squash existing commits only when requested or included in an authorized
history-cleanup workflow; preserve correction commits otherwise. Do not
rewrite pushed or shared history without explicit authorization. These rules
do not grant permission to commit: leave fixes uncommitted when committing
has not been authorized.

## Hook Failures

If `git commit` fails, inspect status and both diffs and check whether HEAD
moved. If it did not, the attempted commit does not exist: fix the failure
and run a new `git commit`. Do not amend the previous commit by mistake.
If HEAD moved, inspect the actual commit and apply Amending to any follow-up.
Only stage hook output belonging to the selected unit; staged-only still
requires permission to change the index. Rerun affected required checks after
hook edits. Report unresolved test or lint failures.

## Deciding where to split

The guiding question is: **"If I revert this commit, does it undo exactly one
thing?"** If reverting would also undo something unrelated, split further.
Shared type, scope, or file is not sufficient reason to bundle — only tight
logical coupling is.

Changes across layers belong in separate commits, even within the same
work: instruction/skill files vs application code, schema migrations vs
application logic, infrastructure vs application, and build config vs source.
If this conflicts with keeping each commit working independently, explain
the dependency before choosing a commit plan.

Order prerequisites first so each commit works independently.

Concrete examples:

- Bug fix and a refactor that touched the same function → two commits
- New feature and its tests → one commit (inseparable: the test validates the
  feature)
- Dependency upgrade and required compatibility changes may be one commit if
  neither builds independently; split only when each commit can be reverted
  independently.
- Adding a new entry to a list **and** reordering the list → two commits: one
  for the addition (capability change), one for the reorder (style/cosmetic).
  They are independently revertable and serve different purposes.
- Multiple new files that serve independent purposes (e.g. two unrelated skill
  files) → one commit per file. Reverting one should not touch the other.

When in doubt, prefer smaller commits, but each commit must be coherent,
reviewable, and leave the repository in a working state.

## Message Format

Follow [Conventional Commits](https://www.conventionalcommits.org/).

```
type(scope): short description          ← max 72 chars, imperative mood

Why this change was needed (the problem or motivation).

What was changed and how the solution addresses it.
Explain implementation decisions that aren't obvious from the diff.
Note any potential impacts: behaviour changes, performance,
compatibility, or things to watch out for downstream.

BREAKING CHANGE: description (if applicable)
Closes #123 (if applicable)
```

### Types

| Type       | When to use                                      |
|------------|--------------------------------------------------|
| `feat`     | New feature or capability                        |
| `fix`      | Bug fix                                          |
| `refactor` | Code change that neither adds a feature nor fixes a bug |
| `perf`     | Performance improvement                          |
| `test`     | Adding or updating tests                         |
| `docs`     | Documentation only                               |
| `chore`    | Build process, tooling, dependency updates       |
| `ci`       | CI/CD configuration changes                      |
| `style`    | Formatting, whitespace (no logic change)         |
| `revert`   | Reverts a previous commit                        |

### Subject line rules

- Max 72 characters (including `type(scope): `)
- Imperative mood: "add feature" not "added feature"
- No trailing period
- Scope is optional but helpful when the change is isolated to one area
- Prefer scopes that match package, app, command, subsystem, or config names
  already used in the repo; avoid vague scopes like `misc`, `changes`, or
  `updates`
- For breaking changes, add `!` after the type/scope: `feat(api)!: require
  idempotency keys`

### Body rules

- Do not restate the subject in the body.
- Wrap lines at 72 characters
- Separate from subject with a blank line
- Use a body whenever the reason, tradeoff, migration impact, or root cause is
  not obvious from the subject. Subject-only commits are only for mechanical or
  self-evident changes.
- Answer these questions as applicable:
  - **Problem/motivation** — why was this change necessary?
  - **Solution** — what approach was taken and why?
  - **Implementation details** — decisions that aren't obvious from the diff
  - **Impacts** — behaviour changes, performance effects, migration notes

### Footers

Footers come after the body, separated by a blank line. Use one footer per line:

```
BREAKING CHANGE: config files must now include `version`.
Closes #123
```

If the repository convention uses trailers such as `Co-authored-by`,
`Signed-off-by`, or AI attribution trailers, preserve that convention. Do not
invent trailers if the repository does not use them.
