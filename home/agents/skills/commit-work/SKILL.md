---
name: commit-work
description: Commit only the changes related to a specific piece of work, leaving other uncommitted changes untouched. Use this skill when the user says "commit this work", "commit the changes for X", "commit what I just did", or otherwise wants to selectively commit changes that belong to a particular effort — especially when the working tree contains mixed changes from multiple work streams. Do not use for committing everything (use commit) or committing already-staged changes as-is (use commit-staged).
---

# Commit-Work Skill

Selectively commit only the changes that belong to a specific piece of work,
even when the working tree contains unrelated changes from other efforts. The
user tells you what the work is; your job is to identify which changes belong
to it, verify they can be committed independently, and create a clean commit.

## Arguments

| Flag     | Effect                                           |
|----------|--------------------------------------------------|
| `--push` | Run `git push` after committing                  |
| `--pr`   | Push (if needed), then create a PR with `gh pr create`. Implies `--push`. |

> **Important:** Push (and PR creation) only happens when the user explicitly
> requests it in the current message. Each commit request is independent.

### `--push`

Check for an upstream before pushing. If no upstream is set:

```bash
git push -u origin HEAD
```

Otherwise:

```bash
git push
```

Before pushing, if the current branch matches `main`, `master`, `develop`,
`dev`, `prod`, `production`, `release`, or similar shared/protected names,
ask for confirmation unless the user explicitly requested pushing that branch.

### `--pr`

Determine the default branch non-interactively:

```bash
gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'
```

Push first if needed, then create the PR:

```bash
git push -u origin HEAD

gh pr create \
  --base DEFAULT_BRANCH \
  --head "$(git branch --show-current)" \
  --title "type(scope): short description" \
  --body "$(cat <<'EOF'
PR description derived from commit body.
EOF
)"
```

## Branch Guard

Before committing, check the current branch:

```bash
git branch --show-current
```

If it matches `main`, `master`, `develop`, `dev`, `staging`, `prod`,
`production`, `release`, or any other release/stable branch name, **stop
and refuse the commit**. Ask the user to create a topic branch first.

This guard may be relaxed when the active project or user instruction files
(`CLAUDE.md`, `AGENTS.md`, or equivalent harness-provided guidance) explicitly
permit direct commits to that branch.

## Workflow

### 1. Understand the work

The user describes a piece of work — e.g., "adding the commit-work skill",
"fixing the auth bug", "refactoring the logger". This is your scope.

If the user's description is vague, ask them to clarify before proceeding.

### 2. Inspect all uncommitted changes

```bash
git status --short
git diff
git diff --staged
git diff --summary
git diff --find-renames
git ls-files --others --exclude-standard
```

If changes are already staged, treat them as part of the user's intent but
still verify they match the described work.

### 3. Classify changes

Go through every changed, deleted, renamed, and untracked file/hunk and
classify it:

- **Belongs to this work** — directly related to the described effort
- **Belongs to other work** — clearly part of a different effort
- **Ambiguous** — could go either way

Present a summary to the user showing what you plan to include and what
you plan to leave out. For ambiguous changes, ask the user to decide.

### 4. Check scope

If the set of changes belonging to this work is large (many files, multiple
logical concerns, or would result in a commit that is hard to review as a
single unit), stop and ask the user whether to:

- Commit as a single large commit
- Split into multiple commits (hand off to the `commit` skill)
- Narrow the scope

A commit should be coherent, reviewable, and independently revertable. If
the work naturally produces a large but cohesive change (e.g., a new feature
with its tests), that is fine. But if it spans unrelated concerns, flag it.

**Layer separation rule:** Changes that cross layer boundaries must be
in separate commits, even when they are part of the same work. If two
changes have different review concerns or revert granularity, they
belong in different commits. Examples: instruction files vs application
code, schema migrations vs application logic, infrastructure vs
application, build config vs source code.

### 5. Check for dependencies

Before staging, check whether the changes you plan to commit depend on
other uncommitted changes that belong to different work:

- Does the code being committed import, call, or reference symbols that
  only exist in other uncommitted changes?
- Does the code being committed modify files that also have uncommitted
  changes from other work in the same hunks or adjacent lines?

If dependencies are found, **stop and explain the situation to the user**.
Do not attempt to resolve the dependency yourself. Let the user decide
whether to:

- Commit the dependency first
- Include the dependency in this commit
- Restructure the changes

This is critical — committing in the wrong order can create broken
intermediate states or confusing history.

### 6. Stage the work's changes

Use patch surgery to stage only the relevant hunks. **Never use
`git add <file>` for text changes** — staging a whole file risks bundling
unrelated hunks.

**Capture all unstaged changes:**

```bash
mkdir -p ./.agents/cache/patches
git diff --binary --full-index --find-renames > "./.agents/cache/patches/<YYYYMMMDD>-<short-title>.patch"
```

**For untracked files that belong to this work:**

```bash
git diff --no-index /dev/null path/to/new-file > "./.agents/cache/patches/<YYYYMMMDD>-<short-title>-new-files.patch"
```

**Write a sub-patch** containing only the hunks for this work, dry-run,
then apply:

```bash
git apply --cached --check --recount "./.agents/cache/patches/<YYYYMMMDD>-<commit-title>.patch"
git apply --cached --recount "./.agents/cache/patches/<YYYYMMMDD>-<commit-title>.patch"
```

For binary files, renames, deletes, and mode changes that belong wholly to
this work, use `git add <path>` and state your reasoning.

### 7. Verify the staged result

```bash
git diff --staged          # confirm only the intended hunks are staged
git diff --staged --check  # catch whitespace errors and conflict markers
```

### 8. Commit

```bash
git commit -F - <<'EOF'
type(scope): short description

Body explaining what changed and why.
EOF
```

### 9. Post-commit actions

Execute any actions required by flags (see Arguments).

### 10. Final report

```bash
git status
```

Report what was committed and what remains uncommitted. Explicitly list
the remaining changes and which work streams they likely belong to, so the
user knows what is left.

## Recovery from failed patch application

If `git apply --cached --check` or `git apply --cached` fails:

1. Do not retry blindly.
2. Run `git diff` and `git diff --staged` to understand the current state.
3. Regenerate the patch from the current state.
4. Rebuild the sub-patch with more context or fewer edits.
5. If the index was partially changed, inspect and fix it without discarding
   unrelated changes.

## Handling pre-commit hooks

If `git commit` fails because hooks changed files, inspect `git status`,
`git diff`, and `git diff --staged`. Do not assume the commit happened.
Stage only hook-generated changes that belong to this work, then create a
**new** commit (never amend). If hooks fail due to tests or lint errors,
report the failure and the relevant output.

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
- For breaking changes, add `!` after type/scope

### Body rules

- Wrap lines at 72 characters
- Separate from subject with a blank line
- Use a body whenever the reason, tradeoff, or root cause isn't obvious
  from the subject. Subject-only commits are fine for mechanical or
  self-evident changes.
