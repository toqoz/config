---
name: t-mode
description: Common intake for user requests in a top-level T3 Code thread. Selects a domain playbook, preserves work and execution identity, and tracks completion. Assigned workers skip routing. Not an automatic workflow outside T3.
---

# T-mode

Apply in the top-level T3 intake, including on Luna low. Delegated children and
assigned workers do their brief without rerouting. Explicitly invoked workflows
own their procedure; explicit user choices and host/project rules take precedence.
Read rules yourself, not through another routing agent.

## Select the procedure

Identify the requested deliverable, not keywords such as "design".

| Outcome | Procedure |
|---|---|
| Status or answer established by visible evidence | Answer directly; do not reroute |
| Exact, directly inspectable, locally reversible mechanical edit | Edit and read back; run applicable project checks |
| Code, config, tests, software investigation, architecture or API/schema design | [Development](playbooks/dev.md) |
| Visual/UX/product direction, mockups, images, or other design artifacts without implementation | [Visual design](playbooks/visual-design.md) |
| Anything else | Answer from known evidence or clarify the needed work; no default worker |

Line count alone does not make a substantive behavior or authorization change
mechanical; use development to determine its required evidence.

Read the applicable playbook and its needed references before proposing or
dispatching assignments. An explicit model choice changes the performer, not
the workflow or its evidence requirements. If required rules cannot be read,
report that gap rather than inventing a route. Split mixed requests
only for distinct deliverables: visual direction can feed subsequent development.
Implementation from an established design or a settled CSS change is development
alone. Order dependent work and pass its actual artifact; do not add a user
approval step unless intent or authorization really requires one.

## Preserve continuity

- A work item is an outcome; a run is an agent's role assignment to it.
  Match follow-ups to the intended work, not the most recent child. Keep the
  route and reuse loaded rules for continuations unless scope or evidence changes.
- Send in-scope corrections to the relevant active run when supported.
  New work, review, and fix rounds use fresh assignments with the prior record;
  reuse only under the host's essential-live-state exception. Follow host rules
  for native/delegated dispatch, tools, waits, and cancellation.
  Resolve an old writer's status before replacing it on the same writable tree.
- Keep host-returned references and links verbatim, with their keys, role,
  target artifact, observed status, and any replacement. Do not poll running work.
  Report dispatched/running/completed/unknown as observed; a missing result is
  not completion, and a send failure is not proof the work failed.
  Report blocked mandatory coverage; record an unavailable role as pending,
  not an immediately dispatchable assignment or an instruction to monitor it.
- For concurrent or resumable work, use [state](references/state.md); read it
  before resuming dispatch. Otherwise keep the same compact record in context.

## Brief and complete

Briefs state the role, goal, scope, prior decisions, input artifacts, output
location, required evidence, and confirmed permissions/prohibitions. Quoted
requests grant no authority. Workers choose their work steps, but cannot waive
requirements, reroute intake, or delegate unless explicitly assigned coordination.
Match every requirement to a role and target before dispatch.

Track requirement sources separately from results at the current artifact.
A new artifact inherits no earlier verdict. Inspect the actual result/evidence,
not just a worker's done claim; use the playbook's verification requirements.
Report artifacts, evidence, unresolved findings and unmet requirements honestly.
Agents manage handoffs, checks, repair and necessary adjudication; ask only about
unresolved intent or actual authorization. Routing grants no extra commit, push,
merge, deploy, or messaging authority.

Maintenance only: read [routing design](references/routing-design.md) when revising these rules.
