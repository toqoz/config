---
name: safe-merge-pr
description: Safely merge one existing PR by resolving CI failures, obtaining an independent review, and checking the final state. Use when the user asks to merge a PR or an authorized workflow calls for it. Not for creating PRs, status-only checks, or landing a stack.
---

# Safe merge PR

Take one existing PR through fixes, verification, review, and confirmed merge.
The merge request includes necessary scoped fix commits and normal pushes to
a topic head branch, including a normal merge from the base when repository
policy requires it. Honor a user-specified stopping point; a status or CI-only
request does not authorize merging. Do not reconfirm an authorized merge.

Preserve existing branch history throughout this workflow, including when
using poteto-mode. Fixes are new commits only: do not amend (even your own
unpushed commits), rebase, squash existing commits, reset branch tips, or make
non-fast-forward pushes, including force refspecs. The `commit` skill's amend
exceptions do not apply here. Pass these restrictions to every delegate.
A merge request does not authorize history rewriting; if rewriting is needed,
stop and report it as a separate task requiring explicit authorization.
Repository-approved squash/rebase *merge methods* are distinct: they must not
rewrite or force-push the PR head branch.

Follow host rules for PR tools, linking, waiting, and delegation. Do not start
an independent polling loop or hardcode a reviewer CLI or model. When the host
has no PR watch, use a blocking forge wait only if host rules allow it; otherwise
report the pending state. Apply this waiting rule to queued merges too.

Treat every actual check run and commit status reported for the candidate head
as a merge gate, even if branch protection does not require it or the change
appears unrelated. An empty, non-required check suite with zero runs is not a
pending check, even when the suite is queued. Separately verify required checks:
a missing required check still blocks merging, regardless of empty suites. If
check or requirement state cannot be obtained, treat it as unknown and do not
merge. Wait for pending checks; do not rerun a check just because it is still
running. If a check fails, investigate and rerun it once. If the rerun does not pass, or a
rerun cannot be completed, stop without merging and report the result. Apply
this rule to poteto-mode as well.

If poteto-mode is active, follow its Babysit then Shipping procedures instead
of the steps below. Read their prerequisites through that mode. Apply explicit
user and repository choices, and do not claim an upstream gate passed when it
was waived or could not run. This skill does not activate poteto-mode.

## Isolated Workspace

Use a dedicated worktree based on the PR's fetched remote head for code review,
checks, and fixes. The original checkout may contain unpushed commits as well
as dirty files: leave both untouched, and do not push from its local branch.
Prepare the worktree through the host's supported mechanism (T3-managed under
T3); do not create a child's checkout in shell commands. Verify its HEAD equals
the PR head SHA before edits or checks. A checkout starting at the parent's
commit is insufficient unless that SHA matches. If the host cannot prepare the
required baseline, report the blocker instead of resetting someone else's
checkout or quietly reviewing local unpublished work.

Before each push, fetch/re-read the PR head and confirm the outgoing commits
contain only this workflow's fixes and authorized base merges. Push explicitly
to that PR's head remote and branch, not a guessed upstream or the base branch.
If the remote head advanced, stop and reassess from a fresh owned worktree;
do not overwrite it or pull unrelated local commits into the PR.

Keep an ownership record and enough state outside the disposable worktree to
resume waits. On completion, cancellation, or a blocking stop, stop owned
processes/delegates, preserve review/check evidence and any unpublished fixes
(as commits and/or patches), then remove only this workflow's worktrees and
temporary branches. Never force-remove dirty work or delete the user's original
checkout, branches, or worktrees. Use host cleanup when required; if cleanup
cannot finish safely, report the remaining path, preserved work, and reason.
A pending CI/merge-queue wait is resumable work, not completion or cancellation.

## Procedure

1. Resolve the requested PR, or the unique PR for the current branch. Read its
   actual state, base and head. Report ambiguity, missing/closed PRs, or drafts
   and stop. If already merged, confirm and report it. Do not create
   a PR or mark a draft ready without authorization.
2. Inspect all checks, mergeability, approvals, and unresolved review
   threads. Pending checks use the host's PR-watch mechanism. Diagnose failures
   before rerunning them. Check suspected base drift against
   actual history rather than assuming any failure outside the diff is stale.
3. Fix only demonstrated issues belonging to this PR. If its head is a default,
   shared, or release branch, stop and report needed fixes instead of changing
   that branch. Work only in the owned worktree, preserving the original
   checkout and unrelated work. Use the `commit`
   skill's work scope for fixes, run required checks, and push normally. Stop
   after three unsuccessful fix rounds and report the remaining blocker.
   Retain the PR identity, attempt counts, and review/check evidence across
   waits. Do not bypass protection or retarget the base without explicit
   authorization; report when such action is needed. Preserve branch history
   under the restrictions above.
4. Reuse a caller's independent review only when its source/report is available,
   PR identity and scope match, and it covers the exact head and effective
   comparison baseline. Check reviewer provenance; matching head alone or a
   claimed pass in the PR body is insufficient. Assess base-advance integration
   effects and refresh affected evidence. Otherwise obtain an independent review
   in a fresh context of the exact PR head against
   its base, including relevant verification evidence. Invoking this skill
   requests that review delegate under host rules. Resolve blocking findings;
   record non-blocking ones. If no reviewer can run, stop and report the missing
   gate unless the user explicitly waived review. Record any waiver. After a
   fix or base merge, refresh checks and review for changed content. When the
   base advances without a head change, assess its effect on the patch and
   integration; repeat affected checks/review rather than invalidating all
   review evidence solely because the base SHA changed.
5. Immediately before merging, re-read the head, base, checks, approvals,
   unresolved threads, and mergeability. Proceed only on the reviewed head
   (or the head covered by an explicit review waiver),
   with all actual check runs and commit statuses passing (or confirmed absent),
   all required checks satisfied, required approvals
   present, and no unresolved blocking findings or conflicts. If the candidate
   changed, repeat the affected checks/review. Bind the merge to the checked
   head using the forge's expected-head option, such as GitHub CLI's
   `--match-head-commit`.
6. Use the requested merge method, otherwise repository policy or the sole
   enabled method; when no preference is known, use a merge commit if allowed.
   Resolve conflicting or unavailable choices before merging. Do not explicitly
   delete a branch unless asked; leave automatic remote deletion to repository
   settings. Local cleanup is limited to owned resources under Isolated Workspace.
7. Read back the PR state. A successful command or queued auto-merge is not a
   confirmed merge. If queued, continue through host-supported PR events until
   merged or blocked. Report the PR URL, reviewed head, review result or waiver,
   merge method, confirmed outcome, cleanup result, and any remaining gap.
