---
name: commit-staged
description: Commit only the already-staged changes with a well-structured conventional commit message. Use this skill whenever the user asks to commit staged changes, says "commit what's staged", "commit the index", or "commit these staged files" — and wants to leave any unstaged changes untouched. Always use this skill rather than ad-hoc git commit commands when the intent is to commit staged changes only.
---

# Commit-Staged Skill

Commit exactly what is already in the index — nothing more. The user has already decided what belongs in this commit by staging it; your job is to understand those changes and write a message that explains them well.

## Arguments

| Flag     | Effect                                           |
|----------|--------------------------------------------------|
| `--push` | Run `git push` after committing                  |
| `--pr`   | Push (if needed), then create a PR with `gh pr create`. Implies `--push`. |

> **Important:** Push (and PR creation) only happens when the user explicitly
> requests it in the current message. A prior "commit and push" instruction does
> **not** carry over to subsequent fix requests.

### `--push`

Check for an upstream before pushing. If no upstream is set:

```bash
git push -u origin HEAD
```

Otherwise:

```bash
git push
```

Before pushing, if the current branch matches `main`, `master`, `develop`, `dev`,
`prod`, `production`, `release`, or similar shared/protected names, ask for
confirmation unless the user explicitly requested pushing that branch.

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

Use the commit subject as the PR title and body as the PR description.
Before opening the PR, verify `gh` is installed and authenticated.

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

1. **Check the staged diff:**
   ```bash
   git diff --staged
   git diff --staged --stat
   ```
   If the index is empty, stop and tell the user — there is nothing to commit.

2. **Note unstaged and untracked changes** so you can mention them afterward:
   ```bash
   git status --short
   ```
   Do not stage any of them.

3. **Craft the commit message** based solely on the staged diff (see Message Format below).

4. **Verify staged changes are clean:**
   ```bash
   git diff --staged --check   # catch whitespace errors and conflict markers
   ```
   Report any issues but do not auto-fix them.

5. **Commit** — pass the message via stdin to preserve formatting:
   ```bash
   git commit -F - <<'EOF'
   type(scope): short description

   Body explaining what changed and why.
   EOF
   ```

6. **Post-commit actions** — execute any actions required by flags (see Arguments).

7. **Final report** — run `git status` and mention any remaining unstaged or
   untracked changes that were intentionally left out.

### Handling pre-commit hooks

If `git commit` fails because a hook changed files, inspect `git status`,
`git diff`, and `git diff --staged`. Do not assume the commit happened. Stage
only hook-generated changes that belong to this commit, then create a **new**
commit (never amend). If hooks fail due to tests or lint errors, report the
failure and the relevant output.

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
- For breaking changes, add `!` after type/scope: `feat(api)!: require idempotency keys`

### Body rules

- Wrap lines at 72 characters
- Separate from subject with a blank line
- Use a body whenever the reason, tradeoff, or root cause isn't obvious from
  the subject. Subject-only commits are fine for mechanical or self-evident changes.
