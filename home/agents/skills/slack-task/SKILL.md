---
name: slack-task
description: |
  Handle low-complexity work requests from Slack messages end-to-end: read the request,
  assess risk, execute the task, verify, create and merge PRs, and report completion back
  to Slack. Use this skill whenever the user says /slack-task or wants to process a Slack
  work request automatically.
disable-model-invocation: true
---

# slack-task

Process a low-complexity Slack work request safely and automatically.

Usage: `/slack-task <SLACK_URL>`

This skill orchestrates existing skills into a strict sequential workflow. Each step has explicit entry conditions, actions, and exit conditions. The goal is to minimize user interruptions during normal flow while ensuring safety at every decision point.

## Guiding Principles

- **Ask only when genuinely uncertain.** The user has delegated this task to you because they want automation, not a Q&A session. Excessive questions defeat the purpose — reserve them for real ambiguity or real risk.
- **Fail safe, not fail silent.** If something is risky or unclear, stop and ask rather than guess. But "risky" means data loss, wrong environment, breaking changes, or scope beyond what was requested — not routine code changes.
- **Use existing skills.** Each step delegates to a specific skill. Follow that skill's own workflow faithfully.

---

## Workflow

Execute these steps strictly in order. Do not skip steps. Do not reorder steps.

### STEP 1 — Analyze the Request

**Goal:** Understand what is being asked and whether it is safe to automate.

1. **Read the Slack message.** Invoke the `/slack` skill to fetch the message at `<SLACK_URL>`, including thread context if present.

2. **Classify the request.** Determine:
   - What is the concrete task? (e.g., fix a bug, change copy, update config)
   - Which repository and codebase area does it affect?
   - Is the scope small and well-defined?

3. **Risk gate.** Proceed only if ALL of the following are true:
   - The task is unambiguous enough to implement without guessing
   - The change is small and localized (not a cross-cutting refactor or architecture change)
   - No database migrations, permission changes, billing logic, or destructive operations are involved
   - The request does not contradict existing code, tests, or documentation

   If ANY condition fails → ask the user to confirm before proceeding. Explain which condition failed and why.

4. **Clarification (if needed).** When you need more information:
   - Formulate the specific question.
   - Ask the user. Let them choose whether to answer directly or relay the question to the requester (if relaying, use `/slack` to draft the message).
   - Wait for the answer before proceeding.

**Exit condition:** You have a clear, low-risk task description and enough context to implement it.

---

### STEP 2 — Execute the Task

**Goal:** Implement the requested change.

1. Invoke the `/ambiguous-request-resolver` skill with the task description derived from STEP 1.
2. Follow that skill's full workflow (translate → ground → decide → change → verify).

**Exit condition:** The code change is complete and you believe it is correct.

---

### STEP 3 — Verify the Change

**Goal:** Confirm the change is correct before creating a PR.

Run the applicable checks in order. Skip a check only if it genuinely does not apply (e.g., no tests exist, not a webapp).

1. **Static analysis.** Run the project's lint and format checks.
   - If the project has a lint/format command (e.g., `npm run lint`, `make lint`), run it.
   - Fix any issues introduced by your change. Do not fix pre-existing issues.

2. **Automated tests.** If the project has tests:
   - Run the full test suite (or the relevant subset if the suite is large).
   - Fix any failures caused by your change.

3. **Visual/functional verification.** If this is a webapp change:
   - Invoke the `/webapp-acceptance-checks` skill.
   - Verify the affected behavior in the browser.

**Exit condition:** All applicable checks pass. The change is ready for review.

---

### STEP 4 — Finalize

**Goal:** Get the change merged and, if needed, into the appropriate release pipeline.

#### 4a. Create PR and Merge

1. Invoke `/commit --pr` to commit, push, and create a pull request.
2. Invoke `/safe-merge-pr` to wait for CI, review, and merge the PR.

#### 4b. Release PR (if needed)

After the merge in 4a, check: **was the merge target a release branch?**

A "release branch" is one that feeds directly into a deployment (e.g., `dev`, `staging`, `production`, `release/*`). If the PR in 4a already merged into such a branch, skip this sub-step.

If the merge target was NOT a release branch (e.g., it was `main` or a feature branch):

1. Invoke `/github-release-pr` targeting the **lowest environment branch** (e.g., if the project has `dev` → `staging` → `production`, target `dev`).
2. Evaluate whether to auto-merge this release PR:
   - **Auto-merge** (invoke `/safe-merge-pr` with the published release review URL and
     snapshot, rechecking their scope and current head) if BOTH conditions are true:
     - The target is a non-production environment (e.g., `dev`, `staging` — not `production` or `prod`)
     - The release PR contains ONLY changes from this task (no other commits mixed in)
   - **Otherwise:** Notify the user that the release PR is ready and needs manual merge. Provide the PR URL. Wait for the user to confirm it has been merged before proceeding.

**Exit condition:** The change is merged into the appropriate branch. If a release PR was created, it is either merged or the user has been notified.

---

### STEP 5 — Report Completion

**Goal:** Close the loop with the requester on Slack.

1. **Wait for deployment** (if applicable). Some projects need time for CI/CD to deploy after merge. Wait approximately 10 minutes, or check deployment status if a mechanism exists, before reporting.

2. **Send completion notice.** Use `/slack` to draft a reply in the original thread:
   - Briefly state what was done
   - Include the PR URL
   - If the change is deployed, mention where it can be verified

   Follow the `/slack` skill's draft-before-send rule — draft first, then send only after confirming the content.

**Exit condition:** The requester has been notified.
