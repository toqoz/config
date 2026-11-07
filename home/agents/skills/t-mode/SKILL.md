---
name: t-mode
description: Route development tasks to execution, independent evaluation, and completion requirements. Applies to code, debugging, refactoring, investigation, tests, and configuration. Assigned workers follow their brief without rerouting. Reuse the route for continuations; explicit workflows take precedence.
---

# T-mode

T3 intake classifies the request and applies the rules, even on Luna low.
It owns completion requirements, assignments, finding resolution, and procedural
closure. Authors choose how to work but cannot waive those requirements.
Host rules and project checks take precedence; do not spawn another router.

## Route and complete

1. Identify the requested outcome and observable task properties: how settled
   it is, construction difficulty/volume, error detectability, consequences and
   repair locality, dependencies/context, and waiting tolerance. Do not score
   everything or ask the user to classify the task.
2. Read [workflows](references/workflows.md). Apply its route and evidence rules;
   do not invent a fresh cost model for each task. If a decisive technical
   property is unknown, obtain a bounded assessment rather than guess or stall.
3. Read [models](references/models.md) when assigning roles. Select author and
   evaluator separately, preserving independence and known quota preferences.
4. Before dispatch, match every required check to an assigned role and target
   artifact. A requirement stated only in reasoning is not an assignment.
   Give each worker the outcome, scope, relevant evidence, permissions, and
   required checks. Track assignments, requirement sources/results, and changes in
   context. A worker may request added checks, not remove required ones.
5. Run the required evaluations, route findings through repair and confirmation,
   then report the result and evidence. Unmet requirements remain unmet; an
   author's done message is not an independent verdict.

Reuse loaded rules for continuations. Re-route on material changes, not each
message. The user should not micromanage: agents manage investigation, handoffs,
review, repair, and necessary adjudication themselves. Ask only for unresolved
intent or actual authorization needs. Do not seek approval for routine routing.
Routing grants no additional commit, push, merge, deploy, or messaging authority.

Maintenance only: read [routing design](references/routing-design.md) when revising these rules.
