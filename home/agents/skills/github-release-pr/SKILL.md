---
name: github-release-pr
description: Create or safely refresh an environment-promotion release PR between two branches, wait for CI, and record an independent integration review. Use for release PR creation or updates. Merge only when separately authorized, through safe-merge-pr.
---

# Release PR

Default outcome: an existing or new release PR with current CI and a recorded
independent integration review. Keep the PR body brief: a focused summary and
a link to the published GitHub review, not a transcript or full review dump.
Creating or refreshing a release PR does not
imply permission to merge it or promote to another environment.

Preserve merge-commit-based release listings. Do not replace this operational
flow with squash-commit or whole-history release notes. Do not modify release
branches, amend, rebase, reset existing tips, force-push, bypass protection, or
silently expand the release scope. Resolve failures by reporting them, not by
fixing shared heads. Follow the host's PR tools, linking, waiting, and delegation
rules. This skill requests an independent review delegate.

## Publication Helper

Resolve this skill's actual directory; script paths are relative to that
location, not the working repository. From the target repository, run:

```bash
bash <skill-dir>/scripts/create-release-pr <base> <head> --dry-run
```

Requires Python 3, git, and authenticated `gh`. The Bash entrypoint uses Python
standard-library helpers for body handling; it does not invoke an agent.
Origin must match the GitHub repository. The helper fetches remote refs and
pins `head_sha`, `base_sha`, and `merge_base`; it never checks out or writes a
branch. The fetched base tip is authoritative; a PR API base OID is not used
as the current base tip. A missing ref or ambiguous open PR stops before any
publication.

When host tools support PR creation/editing, use the dry-run payload with those
tools instead of the helper's publication mode. Re-read the expected PR body,
title, state, and head/base snapshot immediately before writing; regenerate the
payload if any changed. Dry-run also saves the old body (`backup`) and an
unpublished candidate with evidence (`prepared_record`) in durable local state.
Follow host PR linking rules as the next action after creation or update.
Then confirm the actual publication and clean up that prepared update:

```bash
bash <skill-dir>/scripts/create-release-pr <base> <head> --confirm-prepared <prepared_record> --pr-url <actual-pr-url>
```

This reads GitHub back and deletes only the helper-owned temporary payload and
backup after verifying body, title, head/base snapshot, and any review source.
A prepared record alone is not proof of publication. On a mismatch it retains
recovery files and stops; do not force cleanup or overwrite newer user edits.

Otherwise run the same command without `--dry-run`. It creates or refreshes the
open PR for that pair and returns JSON with `number`, `url`, `action`, snapshot,
and `body_review_claim`. That field only describes editable body metadata; it
is not a verified review result or a merge-readiness signal. Use the actual
independent report and provenance for any handoff. Identical content is not
edited. `no-changes` means head has no commits ahead; report it and stop. Direct commits ahead with no matching PR
merges are explicitly listed as `(no matching merge commits)`; do not silently
claim that list covers all code changes. Review the entire release diff.

## Body Ownership

- Only `github-release-pr:list` and `github-release-pr:review` marker blocks
  are generated. Text outside them is preserved; edits inside are overwritten
  on refresh. Broken, duplicate, or mismatched markers stop publication.
- The list keeps PR merge subjects, authors, and PR titles. Only exact generated
  `XXX Release YYYY/MM/DD` titles are excluded as release merges, independently
  of the current head name (for example Main, Prod, or Production). XXX is any
  single non-whitespace name, matching a branch-derived title. Titles merely
  mentioning the phrase remain included. Custom-titled releases cannot be
  reliably identified from this convention and need manual inspection.
- An existing `<Base> Release YYYY/MM/DD` title gets its date refreshed; a
  manually changed title is preserved. Custom release titles may no longer be
  recognized as upstream releases by downstream extraction.
- Recognizable legacy generated lists migrate in place. Old Agent Review text
  remains under `Previous Agent Review (unverified)`; unknown text is not deleted.
  Unmarked reviews are not current review evidence. A wholly handwritten body
  requires approval before appending managed blocks (`--append-managed`).
- State lives under `.agents/state/github-release-pr/<repo-id>/` in the
  primary checkout (the parent of the git common directory), shared across
  worktrees. It is temporary recovery state, not a permanent evidence archive.
  It survives a disposable worktree until publication is confirmed, then the
  helper removes its own prepared files and backups. Dry-run retains them until
  `--confirm-prepared` succeeds. Empty lock files coordinate local operations.
  The helper re-reads body and
  remote tips before publication, retries preparation once on a race, and checks
  afterward. GitHub body writes have no compare-and-swap guarantee: this narrows
  and detects races but cannot eliminate the final read/write window. Do not
  overwrite a newer edit to repair a mismatch; retain evidence and report it.

## Branch Resolution

Use an explicitly supplied base/head pair directly after validating both remote branches.
When `env` is provided, resolve it as the base and use the immediately preceding
branch in the project's promotion chain as head. Preserve actual remote names;
ask if aliases collide or the requested environment is outside the known chain.
Do not substitute a different environment or widen the branch pair.

When `env` is **omitted**, resolve the branch pair interactively:

### Step 1 — Fetch and list remote branches

```bash
git fetch origin
git branch -r --list 'origin/*' --sort=-committerdate | sed 's|origin/||' | grep -vE 'HEAD|dependabot/|renovate/'
```

### Step 2 — Detect the branching model

Normalize remote branch names using this alias table:

| Canonical | Matches |
|---|---|
| `main` | `main`, `master` |
| `develop` | `develop`, `development` |
| `dev` | `dev` |
| `staging` | `staging`, `stg` |
| `production` | `production`, `prod` |

Use the **first matching** model below (ordered by specificity):

#### GitLab Flow (environment promotion from main)

**Condition:** `main` exists AND at least two of {`dev`, `staging`, `production`} exist.

Promotion chain (skip any missing link): `main` → `dev` → `staging` → `production`

Example pairs: `main` → `dev`, `dev` → `staging`, `staging` → `production`

#### Environment promotion (without main as source)

**Condition:** `develop` exists AND at least one of {`staging`, `production`} exists.

Promotion chain (skip any missing link): `develop` → `staging` → `production`

#### Git Flow

**Condition:** `main` exists AND (`develop` or `dev`) exists AND none of {`staging`, `production`} exist as separate environment branches.

Promotion chain: `develop` (or `dev`) → `main`

#### Fallback

No pattern matched — skip to step 4.

**Important:** When generating pairs from the matched chain, always use the **actual remote branch name** (e.g. `stg` not `staging`) in all git commands and PR creation.

### Step 3 — Present candidates

From the matched chain, generate candidate pairs for adjacent branches. A valid pair `(head → base)` must satisfy:
- Both branches exist on the remote.
- `head` has commits ahead of `base` (`git rev-list --count origin/<base>..origin/<head>` > 0).

Use a sole valid candidate and report the pair. If there are multiple valid
candidates, ask the user to choose, with commit counts:

```
Release PR の対象ブランチを選んでください:

1. main → dev (3 commits ahead)
2. dev → stg (7 commits ahead)
```

### Step 4 — Manual fallback

If no valid candidate pairs are found, list all remote branches and ask the user to specify `<base>` and `<head>` manually.

Proceed to the workflow below once the base and head branches are determined.

## Workflow

1. Resolve the pair above and create/refresh the PR. Keep the returned snapshot
   and PR identity across waits. If publication reports `snapshot_current: false`
   or `body_confirmed: false`, report the discrepancy and refresh safely before
   continuing; do not treat publication as verified.
2. Read CI for that exact head. Wait through host PR events; never start a CLI
   watch loop when the host forbids it. If the host lacks events, use only its
   permitted waiting mechanism. Missing/unverifiable checks or CI failures stop
   this workflow with an explicit report; do not auto-fix release branches.
3. Reuse an existing published independent review only after checking its
   actual source, scope, comparison, and current head; body metadata alone is
   insufficient. Otherwise obtain a fresh-context integration review through
   host delegation and the user's model preferences. No provider, model, or CLI is
   fixed here. Give the reviewer the full `merge_base..head_sha` diff and code
   via SHA-addressed `git show`, the branch pair, list, and verification evidence.
   Include migration/configuration interactions and environment differences;
   do not assume every individual PR was reviewed. Review is read-only, without
   commit, push, or merge permission. If code must run, use a host-managed exact-
   head worktree, verify HEAD, and clean up only owned resources after saving
   results. Otherwise no review worktree is needed. Do not use the local branch
   tip or dirty checkout as release contents.
4. Publish the necessary review findings and verification limits as a GitHub
   PR review on `head_sha`, using host review tools or `gh api` with a JSON file.
   Use `event: "COMMENT"` for the agent report, not an artificial approval.
   Include one hidden metadata line in that review's body:
   ```markdown
   <!-- release-review-source {"head_sha":"...","base_sha":"...","merge_base":"...","reviewer":"...","scope":"release-integration","independent":true,"outcome":"pass"} -->
   ```
   `outcome` is `pass`, `notes`, or `blocking` based on the actual review. These
   fields record observed provenance; they do not certify independence on their
   own. Omit incidental debugging transcripts and redundant logs. If a matching
   published review already exists, reuse it after inspection rather than
   posting duplicates. Confirm GitHub returns its body, commit, and submitted
   state before discarding any local source report.
5. Make a temporary JSON record containing `repo`, PR `url`, `base`, `head`, the
   three SHAs, reviewer, scope, independent flag, outcome, and `source` set to
   the actual GitHub review URL (`...#pullrequestreview-<id>`). Put only the key
   conclusion, blocking findings, and unverified risks into a short summary
   file (at most 1200 characters and 12 lines):
   ```bash
   bash <skill-dir>/scripts/create-release-pr <base> <head> --review-record <record.json> --review-summary <summary.md>
   ```
   Use `--dry-run` plus host tools and `--confirm-prepared` when required. The
   helper checks that the GitHub review is published on this PR/head and its
   comparison metadata matches. It writes the summary and a details link into
   the managed body, leaving the complete necessary report on GitHub. It cleans
   up its own successful update; on failure it reports retained recovery data.
   Do not treat `body_review_claim` as verified review quality. Keep blocking
   findings blocking. Review unavailable means stop, unless explicitly waived;
   never fabricate a passing review to represent a waiver.
6. A changed head or merge-base resets the managed summary to pending. Previous
   detailed reviews remain on GitHub. A base-only advance preserves the summary
   with `body_review_claim: "base-advanced"`; assess integration effects and
   rerun affected checks/review before relying on it. Once GitHub publication is
   confirmed, delete only this task's local record, summary, and source-report
   files; pass GitHub URLs and snapshot metadata to the next workflow. Keep
   recovery data only while publication is failed or unconfirmed, and resolve
   its disposition before claiming cleanup complete. Do not sweep unrelated
   saved files or publish old backup bodies as noisy PR comments.
7. Report the PR URL, actual snapshot, CI status, review findings or missing
   gate, and next action. Do not automatically open a browser.

## Optional Merge Handoff

Merge only if the user explicitly authorized this PR/pair or an authorized
caller supplies a satisfied merge condition. `slack-task` may authorize a
non-production release containing only that task's changes; recheck that
condition if the release contents change. Never carry authorization to a
higher environment. Its lowest environment means the first destination after
the chain's source branch.

Pass the published GitHub review URL, concise outcome, CI check URLs, and
current snapshot to
`safe-merge-pr`. It may reuse actual independent evidence only after checking
PR identity, review scope, reviewer provenance, head, and comparison baseline;
head equality alone is insufficient. Re-read current checks and approvals.
Review reuse does not imply merge readiness, and merge authorization does not
permit repairs to shared/release branches. Without merge authorization, stop
at the release report.

## Verification of This Skill

The local regression suite uses temporary git repositories and a fake `gh`;
it does not write to GitHub:

```bash
python3 -B -m unittest discover -s <skill-dir>/scripts -p 'test_*.py' -v
```
