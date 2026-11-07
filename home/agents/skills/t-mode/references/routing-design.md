# Routing Design and Maintenance

Read when revising t-mode, not for ordinary task execution. This file preserves
the design basis discussed with the user and Opus on 2026-11-07/08. It contains
design judgments and open hypotheses, not measured routing performance.

## Objective

Maximize useful outcomes for the total resources consumed, including provider
quota and waiting time. Minimize neither worker count nor reasoning effort in
isolation. Keep always-loaded instructions small after the richer design is
understood. This conversation's detailed skill-design discussion is exceptional;
normal development must not require human approval of every step or model choice.

## Separate three layers

1. Describe the task's properties without assuming phases or models.
2. Derive necessary activities, ownership boundaries, and independent evaluation.
3. Compare viable routes and select models that meet their role requirements.

Worker count is an output of this comparison. A model pool is supply, not a task
class or fixed workflow. Several routes may meet the same task's requirements.

## Describe the task

| Property | Distinctions worth preserving |
|---|---|
| Specification determinacy | Settled by the request, discoverable from evidence, requires trials, or requires a human intent decision |
| Construction difficulty and volume | Reasoning needed to create a correct result, separately from how much work there is |
| Error detectability | Independent oracle, source/context inspection, runtime observation, or reasoning as difficult as construction |
| Consequences of error | Severity, reversibility, repair locality, and delay before discovery |
| Work structure | Dependencies, delivery order, context size, parallelism, and consumers of shared decisions |
| Time constraints | Interactive response, asynchronous completion, or substantial waiting acceptable |

These are descriptive groups, not six mandatory scores. Some contain several
independent properties; do not multiply them into a giant runtime lookup table.
The former breadth/uncertainty/impact axes are useful summaries but conflate
properties. Their 27 combinations were an offline coverage exercise, not proof
that a universal phase sequence or a particular number of model pools follows.

## Derive activities and ownership

Determine what must become known, what result is requested, and what evidence
would establish success. Reading, experimenting, creating, and checking may stay
within one coherent assignment. Split when independence, shared decisions,
parallelism, context limits, or cheaper bulk execution justify the handoff.
Do not presume either one worker or multiple phases is the efficient default.

Independent evaluation can serve three different purposes:

- reduce residual risk after the author's own checks;
- compensate for choosing a cheaper author;
- satisfy an explicit requirement, such as the user's requested capable review
  of DeepSeek development work.

Another viewpoint may need only a cheap reviewer. Compensating for an author
requires a reviewer capable of detecting that author's likely errors, and a
repair path capable of fixing them. Vendor diversity alone does not establish
either capability. Preserve the user's explicit independent-review requirements.

## Compare routes, not authors alone

Include author work, review, duplicated context, true findings and repairs,
false findings and rebuttals, retries, new errors introduced during repair,
waiting, and defects escaping the whole route. Quota scarcity changes the
relative consumption cost; do not assume an API/subscription billing path.

Cheaper author plus capable review is attractive when checking is easier than
construction and repairs are local and reliable. A stronger author may win when
review is equally difficult, repair loops are expensive, or waiting is costly.
Neither is a universal winner. Reviewer agreement and author-written test passes
are not substitutes for independently established outcome quality.

The current user preference Codex > Claude approximately equal to DeepSeek is
headroom information, not a permanent model ranking. Keep changing preferences
and model candidates in models.md, not in the always-read instructions.

## Status and revision path

The handoff and workbook are reference opinions, not a record of agreed bans.
Earlier drafts incorrectly promoted their model/effort exclusions into policy.
The user clarified this on 2026-11-08. There is no agreed mechanical-only ban
on Luna or categorical DeepSeek role ban from those documents. Keep model
weakness claims and untested combinations labeled as hypotheses.

The user clarified that avoiding micromanagement means the user should not have
to manage agents step by step. It does not mean minimizing agent coordination.
Necessary investigation, review, non-author runtime verification, adjudication,
repair, and confirmation should be managed autonomously by the agents.

The runtime rules now distinguish completion requirements from work steps:
intake sets and tracks the former; workers choose the latter. Intake's authority
comes from prescribed rules and independence, not superior technical intelligence.
Luna low is the intended intake model. Bounded specialist assessment handles
technical classification or adjudication only when rules and evidence do not
settle it. Worker feedback can add a requirement, not silently remove one.

Nontrivial changes normally receive independent evaluation. Solo execution needs
an externally justified exception, such as a limited change covered by an existing
independent oracle. Repair includes evaluator confirmation at the new artifact,
not just the author's done message. Confirmation is scoped to the repair unless
new behavior expands it. Consequential rebuttals need independent resolution.

Author-plus-review can be the economical primary route. Compare route economics
when maintaining the starting assignments, then give intake concrete rules to
apply rather than requiring a runtime cost calculation. R0-R3 are provisional
candidate pools, not proof of four universal categories. Concrete pairings are
starting choices, not measured optimal routes. Preserve actual user directions,
project rules, and host constraints. Poteto is a handoff, not a second concurrent
orchestration layer; its permissions and completion requirements travel with it.

Evaluate representative tasks by route-level total consumption, waiting, repair
rounds, and escaped defects against acceptance criteria the author did not
invent. Do not report unavailable token/quota counters as measured. Compress
runtime instructions after the decision framework is coherent; avoid mandatory
task logs, review panels, or human checkpoints without demonstrated benefit.

When changing the design, record the reason and evidence here, update workflows
and candidate pools together where needed, and label unresolved hypotheses.
Do not make transient conversation artifacts the only source of this rationale.

## Preserve the record at handoff

A six-turn synthetic Luna-low comparison (two conversations per condition) found
that both the current rules and an origin-retention reminder handled review,
artifact changes, and revoked permissions. Both produced short handoff verdicts
that omitted check origins and reviewers. Four summary-only restarts could not
recover those details; two restarts given the existing state records recovered
the checks, origins, reviewers, results, and permissions. One correctly noted that
the latest B artifact was not explicit. These small, tool-free trials support
passing the current record instead of regenerating a verdict-only handoff;
they do not establish long-context reliability or token savings. The output
schema already requested sources in both conditions, and no context-limit or
automatic-compaction test occurred. Keep the record compact and avoid requiring
a separate log file: an in-context record or an accessible path can be handed on.
