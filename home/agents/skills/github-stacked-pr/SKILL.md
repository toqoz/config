---
name: github-stacked-pr
description: Create stacked PRs by splitting a large change into a chain of independently-reviewable pull requests using gh-stack. Use this skill whenever the user wants to split a large task into multiple PRs, mentions "stacked PRs", "PR stack", "split into PRs", "break into layers", or wants to create a series of dependent pull requests where each targets the branch below it. Always invoke this skill rather than manually wiring up branches and PRs one-by-one.
---

# Stacked PR Skill

A stacked PR is a chain of pull requests where each PR targets the branch of the PR below it, and the bottom PR targets the repository's default branch (e.g. `main`). The benefit: reviewers can evaluate each focused layer independently, rather than wading through one enormous diff.

This skill uses [gh-stack](https://github.github.com/gh-stack/) (`gh stack ...`) to manage the stack.

## Prerequisites

Verify before doing any work:

```bash
gh auth status                          # gh installed and authenticated
gh stack --help >/dev/null              # gh-stack extension present
git remote -v | grep github.com         # GitHub remote exists
gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'  # resolve base branch
```

On ToQoz machines, `gh-stack` is managed declaratively in `~/src/github.com/toqoz/config/home/gh.nix` via `programs.gh.extensions = [ pkgs.gh-stack ];`. If `gh stack` is missing, stop and ask the user to activate/update the Nix config; do not run `gh extension install` silently.

If `gh` or auth is missing, stop and describe the missing prerequisite.

## Workflow

### 1. Inspect repo state

```bash
git branch --show-current
git status --short
git log <base-branch>..HEAD --oneline   # commits already on this branch
git diff <base-branch>..HEAD --stat     # files changed
```

Distinguish between:
- Uncommitted changes (working tree / index)
- Commits already on the branch (already committed, possibly needs rewriting)
- Clean working tree (easiest starting point)

If the working tree is dirty, require a clean tree before branch surgery. Either stash or commit first — never proceed with untracked modifications silently.

### 2. Identify logical layers

Good split boundaries:
- Shared refactors or renames first (mechanical, easy to review)
- Schema / API / interface changes before callers
- Feature implementation after its prerequisites
- Tests belong with the layer that makes them pass (not deferred to the last layer)

Bad split boundaries:
- Mixing unrelated concerns in one layer
- Tests-only layers that only pass at the top of the stack
- Splitting a type change from its callsite when neither compiles standalone

### 3. Propose the stack plan

Before touching any branches, present the proposed plan to the user:

```
Stack plan:
  Base: main

  Layer 1: <branch-name> — <PR title>
    Files: src/db/schema.go, migrations/001_add_users.sql
    Summary: Add users table and migration

  Layer 2: <branch-name> — <PR title>
    Files: src/api/users.go, src/api/users_test.go
    Summary: Implement users CRUD API

  Layer 3: <branch-name> — <PR title>
    Files: src/ui/users.tsx
    Summary: Add users UI

  Draft PRs? yes (gh-stack default)
  Proceed?
```

Wait for confirmation unless the user explicitly asked for autonomous execution (e.g. "split and submit without asking").

#### Branch naming

Use a shared stack slug derived from the overall feature name, with a numeric prefix per layer:

```
<username>/<stack-slug>-01-<layer-slug>
<username>/<stack-slug>-02-<layer-slug>
<username>/<stack-slug>-03-<layer-slug>
```

Example: `toqoz/auth-refactor-01-schema`, `toqoz/auth-refactor-02-api`, `toqoz/auth-refactor-03-ui`

Check for branch name collisions before creating:
```bash
git branch -a | grep <proposed-name>
```

### 4. Execute

#### 4a. Commit each layer

If starting from uncommitted changes, stage and commit each layer in turn using hunk-level staging (same approach as the `commit` skill — see its SKILL.md for patch surgery details if needed). Each commit should be coherent and leave the repo in a working state.

If starting from existing commits on the branch, inspect `git log base..HEAD` and decide whether to:
- Preserve commits as-is (if they already map cleanly to layers)
- Split or reorder commits (requires `git rebase -i` — ask before rewriting published commits)

#### 4b. Initialize the stack

From the default branch (e.g. `main`):

```bash
# create bottom layer branch and commit
git checkout -b <layer-1-branch> <base-branch>
# ... stage and commit layer 1 changes ...

# initialize the stack
gh stack init <layer-1-branch>

# add subsequent layers
gh stack add <layer-2-branch>
# ... stage and commit layer 2 changes on the new branch ...

gh stack add <layer-3-branch>
# ... stage and commit layer 3 changes ...
```

#### 4c. Push and submit

```bash
gh stack push       # push all stack branches to origin
gh stack submit     # create/update draft PRs for all layers
```

`gh stack submit` will open PRs where each PR targets the branch below it. The bottom PR targets the base branch. New PRs are drafts by default; pass `--open` only when the user wants ready-for-review PRs.

Use `--auto` when non-interactive PR title generation is acceptable:
```bash
gh stack submit --auto
```

### 5. PR body

`gh stack submit` creates PRs automatically. After creation, update each PR body to include lightweight stack metadata — this helps reviewers who open a PR directly via notification or link, where the native stack map UI may not be visible:

```markdown
> **Stack**: Part 1 of 3 — auth-refactor
> **Next**: #124 (users API)

[main PR description here]
```

For non-bottom PRs, also add:
```markdown
> **Depends on**: #123 (schema migration)
```

Update using:
```bash
gh pr edit <number> --body "$(cat <<'EOF'
...
EOF
)"
```

### 6. Output execution log

After completing, report:
- Base branch
- Each layer: branch name, commit SHA, PR URL, draft/ready status
- Any layers that were skipped or had issues
- Recovery commands (see below)

## Error handling

### Rebase conflicts

If `gh stack rebase` fails with conflicts:
1. Stop immediately — do not push or submit.
2. Show conflicted files: `git status --short`
3. Show which branch/layer is mid-rebase: `git branch --show-current`
4. Tell the user how to abort: `gh stack rebase --abort`
5. Ask whether to resolve manually or let Claude attempt resolution.

Claude may resolve straightforward textual conflicts, but should not guess at semantic conflicts. After resolution, continue with `gh stack rebase --continue`, then rerun `gh stack push`.

### Partial failures

If `gh stack push` or `gh stack submit` fails partway through:
- Do not retry blindly.
- Inspect which layers pushed/didn't: `gh stack view` or `gh pr list`
- Fix the specific failure and rerun only what's needed.

## Recovery commands

```bash
gh stack view           # current state of the stack
gh stack push           # re-push after fixing a layer
gh stack submit         # re-create or update missing PRs
gh stack rebase         # rebase entire stack after base branch updated
gh stack rebase --abort # abort a stuck stack rebase
gh pr list --head <branch>  # find PR for a specific layer
```

## Flags

| Flag | Effect |
|---|---|
| `gh stack submit` default | Submit new PRs as drafts |
| `gh stack submit --open` | Mark new and existing PRs as ready for review |
| `gh stack init --base <branch>` | Use a different base branch instead of the default |
| `--no-confirm` | Skill-level convention: skip the plan confirmation prompt and execute immediately |
