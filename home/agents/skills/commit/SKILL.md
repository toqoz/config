---
name: commit
description: Create a git commit with a well-structured conventional commit message. Use this skill whenever the user asks to commit, create a commit, write a commit message, or stage and commit changes — even if they just say "commit this" or "let's commit". Always use this skill rather than ad-hoc git commit commands.
---

# Commit Skill

Create meaningful git commits that explain not just what changed, but why — giving future readers enough context to understand the decision.

## Arguments

| Flag     | Effect                                           |
|----------|--------------------------------------------------|
| `--push` | Run `git push` after committing                  |
| `--pr`   | Push (if needed), then create a PR with `gh pr create`. Implies `--push`. |

> **Important:** Push (and PR creation) only happens when the user explicitly
> requests it in the current message. A prior "commit and push" instruction does
> **not** carry over to subsequent fix requests. Each commit request is
> independent — do not push unless the user asks for it again.

### `--push`

Check for an upstream before pushing. If no upstream is set:

```bash
git push -u origin HEAD
```

Otherwise:

```bash
git push
```

Before pushing, check the current branch name. If it matches `main`, `master`,
`develop`, `dev`, `prod`, `production`, `release`, or similar shared/protected
branch names, ask for confirmation unless the user explicitly requested pushing
that branch.

### `--pr`

Determine the repository's default branch non-interactively:

```bash
gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'
```

Push first if the branch has no upstream, then create the PR:

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

If exactly one commit was created, use its subject as the PR title and body as
the PR description. If multiple commits were created, write a PR title that
summarizes the branch and a body that lists the combined motivation and changes
of all commits.

Before opening the PR, verify `gh` is installed and authenticated. For `--push`
and `--pr`, verify a remote exists. If prerequisites are missing, stop after the
commit and report the exact missing prerequisite.

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

1. **Inspect repository state:**
   ```bash
   git status --short
   git diff --staged
   git diff --summary
   git diff --find-renames
   git ls-files --others --exclude-standard
   ```

2. **Handle staged changes** — If changes are already staged, treat the index
   as the user's selected commit by default. Do not add more changes unless the
   user explicitly requested it or the staged diff is obviously incomplete and
   the user confirms. Always inspect `git diff` too, and mention any related
   unstaged changes that are being left out.

3. **Plan commits** — If nothing is staged, group all modified, deleted,
   renamed, and untracked changes into logical units. Each commit should be
   coherent, reviewable, revertable, and leave the repository in a working
   state.

4. **Stage one logical unit at a time** — Prefer patch surgery with
   `git apply --cached`. See the Staging section below. Always run
   `git apply --cached --check --recount PATCH` before the actual apply.

5. **Verify the staged result:**
   ```bash
   git diff --staged          # confirm only the intended hunks are staged
   git diff --staged --check  # catch whitespace errors and conflict markers
   ```

6. **Commit** — Pass the message via stdin to preserve formatting:
   ```bash
   git commit -F - <<'EOF'
   type(scope): short description

   Body explaining what changed and why.
   EOF
   ```

7. **Repeat** for each remaining logical unit. After each commit, regenerate
   the working diff from the current state — do not reuse stale patches from
   an earlier capture if earlier commits touched the same files:
   ```bash
   git diff --binary --full-index --find-renames > ./.agents/cache/patches/<YYYYMMMDD>-<short-title>.patch
   ```
   where `<short-title>` is a 2–4 word kebab-case summary of the remaining
   changes (e.g. `fix-token-validation`, `add-retry-logic`).

8. **Post-commit actions** — Execute any actions required by the flags passed
   (see Arguments).

9. **Final check** — After all commits, run `git status`. There should be no
   staged changes. Any remaining unstaged changes were intentionally excluded;
   call them out to the user.

## Staging via Patch Surgery

**Never use `git add <file>` for text changes** — staging a whole file risks
bundling unrelated changes into one commit, which defeats revertability. Always
stage at the hunk level.

The preferred non-interactive method for this skill is **patch surgery**:
extract the hunks you want into a sub-patch, then apply it directly to the
index.

### Non-text and metadata changes

Before staging, inspect `git status --short` and `git diff --summary`.

Text hunks can be staged with patch surgery. For binary files, renames,
deletes, mode changes, symlinks, and submodules, either:

- Generate a complete patch with `git diff --binary --full-index --find-renames`
  and apply it with `git apply --cached`, or
- If the change is indivisible and clearly belongs wholly to the commit,
  stage that exact path with `git add` and state your reasoning explicitly.

Never silently omit these changes.

### Step-by-step

**1. Prepare the patches directory and capture all unstaged changes:**

Choose a `<short-title>` — a 2–4 word kebab-case label that describes the
overall scope of work (e.g. `refactor-auth-middleware`, `add-retry-logic`).
This label is reused for sub-patches so the directory stays navigable.

```bash
mkdir -p ./.agents/cache/patches
git diff --binary --full-index --find-renames > "./.agents/cache/patches/<YYYYMMMDD>-<short-title>.patch"
```

Also detect untracked files:
```bash
git ls-files --others --exclude-standard
```

For new text files, generate a patch with:
```bash
git diff --no-index /dev/null path/to/new-file > "./.agents/cache/patches/<YYYYMMMDD>-<short-title>-new-files.patch"
```

**2. Inspect and plan:**
Read the patch. Each hunk starts with a `@@` line. Decide which hunks belong to
each logical commit.

**3. Write a sub-patch for one logical unit:**

Keep the file header(s) and only the hunks you want. Example:

```diff
diff --git a/src/auth/token.go b/src/auth/token.go
index abc1234..def5678 100644
--- a/src/auth/token.go
+++ b/src/auth/token.go
@@ -10,6 +10,8 @@ func Validate(token string) error {
 	if token == "" {
 		return ErrEmpty
 	}
+	if len(token) > maxTokenLen {
+		return ErrTooLong
+	}
 	return nil
 }
```

Name the sub-patch after the planned commit's type, scope, and subject in
kebab-case (e.g. `fix-token-validate-empty`, `feat-auth-refresh-rotation`).
Save it to `"./.agents/cache/patches/<YYYYMMMDD>-<commit-title>.patch"`.

**4. Dry-run, then stage:**
```bash
git apply --cached --check --recount "./.agents/cache/patches/<YYYYMMMDD>-<commit-title>.patch"   # dry-run first
git apply --cached --recount "./.agents/cache/patches/<YYYYMMMDD>-<commit-title>.patch"           # actual apply
```

- `--cached` — stages into the index without touching the working tree
- `--recount` — recalculates line numbers, tolerates minor offsets in the patch

**5. Verify, then commit.**

**6. Repeat** for each remaining logical unit, regenerating the patch after
each commit.

### Patch file structure

```
diff --git a/path/to/file b/path/to/file   ← file header (required)
index <hash>..<hash> <mode>
--- a/path/to/file
+++ b/path/to/file
@@ -L,S +L,S @@ context                    ← hunk header
 context line (space-prefixed)
-removed line (minus-prefixed)
+added line (plus-prefixed)
 context line
```

To drop a hunk from a sub-patch, delete everything from its `@@` line up to
(but not including) the next `@@` or end of file. If all hunks for a file are
dropped, remove its `diff --git` header too. Use `--recount` so you don't have
to manually fix the `+L,S` counts.

### Splitting within a hunk

If one hunk contains changes for multiple logical commits, edit the hunk so
only the desired added/removed lines remain, preserving enough unchanged context
for `git apply` to match. Then run `git apply --cached --check --recount` before
applying.

If the edited hunk cannot apply safely, stop and ask the user whether to commit
the combined hunk or make a temporary working-tree edit to separate the changes.

### Recovery from failed patch application

If `git apply --cached --check` or `git apply --cached` fails:

1. Do not retry blindly.
2. Run `git diff` and `git diff --staged` to understand the current index state.
3. Regenerate the patch from the current state.
4. Rebuild the sub-patch with more context or fewer edits.
5. If the index was partially changed, inspect and fix it without discarding
   unrelated user changes.

### Deciding where to split

The guiding question is: **"If I revert this commit, does it undo exactly one
thing?"** If reverting would also undo something unrelated, split further.
Shared type, scope, or file is not sufficient reason to bundle — only tight
logical coupling is.

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

### Handling pre-commit hooks

If `git commit` fails because hooks changed files, inspect `git status`,
`git diff`, and `git diff --staged`. Do not assume the commit happened. Stage
only hook-generated changes that belong to the same logical commit, then create
a **new** commit (never amend). If hooks fail due to tests or lint errors,
report the failure and relevant output.

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

## Examples

**Minimal (subject only):**
```
docs: fix typo in README
```

**Breaking change:**
```
feat(api)!: require idempotency keys on order submission

Previous API accepted duplicate POSTs without error, leading to
duplicate orders on network retries.

All POST /orders requests must now include an `Idempotency-Key`
header. Requests without the header receive 400.

BREAKING CHANGE: clients must send an `Idempotency-Key` header
with every POST /orders request.
Closes #482
```

**Feature with context:**
```
feat(auth): add JWT refresh token rotation

Previous implementation reused the same refresh token indefinitely,
making it impossible to detect replay attacks.

Each refresh now issues a new token and invalidates the old one.
The token family concept (Auth0 pattern) is used so that reuse of
a revoked token invalidates the entire family, forcing re-login.

Impacts: clients must persist the new refresh token returned on each
use. Old single-use tokens are revoked immediately after refresh.
```

**Bug fix with root cause:**
```
fix(api): prevent duplicate order submission on network retry

Users could place duplicate orders when a slow network caused the
frontend to retry a POST that had already succeeded server-side.

Added idempotency key (client-generated UUID) checked against a
Redis cache with 24h TTL. Duplicate requests return the original
response without re-processing.

Potential impact: requires Redis to be available; circuit-breaker
falls back to rejecting retries rather than risking duplicates.
Closes #482
```
