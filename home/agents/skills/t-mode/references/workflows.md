# Routes and Completion Requirements

Intake applies these rules; it does not decide technical correctness. Explicit
user choices and stronger project requirements win. Keep simple work in context;
parallel or resumable work uses the compact record in [state](state.md).
No per-action log or score table is required.

## Choose the route from visible properties

| Observable task | Assignment and completion requirements |
|---|---|
| Question settled by visible evidence | Answer directly. Do not turn an explanation into implementation. |
| Trivial deterministic edit, exact target known, directly inspectable and locally reversible | Intake edits and reads back the result; run applicable project checks. No reviewer solely for the edit. |
| Read-only technical question requiring investigation | One investigator returns a cited answer and evidence. Do not implement. Add independent checking when conclusions support a consequential decision or the user requests it. |
| Nontrivial bounded change | Author implements and checks; one different-vendor evaluator checks the result. Cheap author plus capable evaluation is a primary route. |
| Local change with an already-established independent oracle covering the contract and limited, readily repairable consequences | Author plus that oracle can suffice. Intake records the basis before waiving independent review; the author's new assertions alone do not qualify. |
| Unknown cause or feasibility | Assign investigation/trials with an explicit evidence outcome. Investigation may include a local fix if already authorized. Split later execution when the result changes scope or unlocks substantial cheaper work. Keep review required for resulting changes. |
| Small difficult decision followed by substantial bounded execution, or a decision shared by several workers | Assign the decision first, capture the resulting contract, then execution and independent evaluation. No user approval between these steps unless genuinely needed. |
| Independent workstreams or expensive trials that benefit from concurrency | Separate ownership and runtime resources, then integrate and verify the combined result. Delegate only when the role brief authorizes coordination under host rules. |
| Dependent deliverables requiring sustained ordering and coordination | Hand off to poteto as below. File count alone does not require a coordinator. |

If review applicability is unclear, proceed with one standard different-vendor
evaluation, not maximum effort or a user questionnaire. If classifying the scope
or evidence actually needs technical analysis, use one bounded read-only assessor
that returns those properties and recommended checks. Reuse that assessment in
execution/evaluation briefs rather than commissioning a duplicate analysis.

A solo-author exception removes a reviewer, not the author assignment. Intake
only directly edits trivial deterministic text; delegate substantive code even
when an independent oracle permits author-only completion.

## Set the evidence before dispatch

Use independent review by default for nontrivial changes; the specific solo
exception above must be justified outside the author. A stronger author alone
is eligible only when the required independent evidence is otherwise satisfied.

- If source and context reveal the likely errors, require a defect review.
- If errors depend on runtime and consequences affect users, compatibility,
  shared defaults, data, authorization, or billing, require non-author runtime
  verification on the affected surface. The same evaluator can review and run
  the change; this need not add a second reviewer.
- For high consequences, use the high-consequence evaluation row in models.md,
  not the standard review row merely because it is another vendor.
  For high consequences or subtle hard-to-detect failure modes, require a strong
  evaluator covering the decision, behavior, and failure paths. Prefer a vendor
  different from consequential design decisions as well as implementation.
- Author tests and real-surface checks remain required by project instructions;
  independent evaluation does not replace them.
- DeepSeek development receives capable Sol/Sonnet review as requested. Let that
  review also satisfy the independent requirement rather than duplicating it.

An independent oracle is pre-existing evidence or an independently established
contract that covers the change, not merely tests authored to match the new code.
Intake can recognize an explicit existing requirement; whether it actually covers
an unfamiliar contract is a technical assessment, not a persuasive author claim.

## Run evaluation, repair, and confirmation

Give the evaluator the request, exact diff/tree identity, relevant context,
author evidence, and completion requirements. Ask for concrete defects with
scenarios, expected versus actual behavior, and evidence, or an explicit pass.
A narrow second look excludes style and speculative rewrites; prioritize up to
five consequential findings without suppressing additional blockers.

Send findings to a fresh run of the authoring role for repair or evidence-backed
rebuttal, preserving the scope and prior decisions. Then obtain the evaluator's
confirmation of the changed diff and disputed findings at the new tree identity.
Use a fresh review delegate with the prior finding record under host rules;
reuse only for essential live state when permitted. Do not rerun a full review
unchanged; expand verification if the repair introduces new behavior or risk.

Intake never accepts the author's rebuttal as its own technical ruling. Have the
evaluator examine it. If a consequential dispute remains, use a discriminating
check, or a bounded independent adjudicator if judgment is still needed. A
low-consequence unresolved point can be reported explicitly, not marked resolved
by intake. Only a genuine product-intent decision goes back to the user.

Repeated unsuccessful repair or unproductive review is a re-route signal: change
the appropriate model/role using the evidence, not by relaxing checks. No fixed
retry count or automatic infinite review cycle. Host model-replacement rules apply.

## Change requirements and declare completion

Keep one compact current record: work ID, latest artifact, each check's originating
requirement, assigned role, result and target, and action permissions. On handoff,
pass that record or an accessible path with the brief, not a replacement verdict
such as "all checks passed". Keep requirement sources separate from result evidence.
If a source is missing, retrieve it; a prior pending flag alone establishes
neither a new check nor grounds to waive one.

Workers may surface new risks; intake adds the applicable checks. Removing or
weakening a check needs evidence independent of its author: objective evidence
can be matched to a rule; adequacy requiring judgment goes to an evaluator.
Record the reason in context and final reporting. Missing tools, quota, or a
model do not establish that a check is unnecessary.

Intake checks that each requirement has a result for the artifact being delivered,
that findings were confirmed resolved or explicitly reported, and that no required
check was silently dropped. Continue useful authorized reversible work when a
check is blocked, but report incomplete verification and do not claim completion
or deliver through a gate that remains unmet. Honor actual action permissions.

## Poteto handoff

Read the installed poteto entrypoint and dispatch one coordinator with its
absolute path, the user's goal and permissions, completed work/evidence, and
open requirements. Explicitly authorize coordination. Poteto owns its playbooks,
model preferences, and capability gates. Intake retains its record's sole
write ownership, links poteto's plan/trail, and incorporates returned results;
include the state path in the brief when one exists. Preserve user/project
completion requirements rather than running two orchestration layers.
Workers report expansion to intake instead of spawning another coordinator.
