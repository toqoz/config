---
name: triage
description: Lightly assess issues, improvements, and friction found during routine work. Use when something may deserve follow-up outside the current task, or when the user asks to triage a finding. Decide whether to act now, file it in the project's backlog, dismiss it, or escalate to reflect.
---

# Triage

Assess the finding briefly in the current agent.

1. State what was observed, its consequence, and the evidence available. Distinguish an observed problem from a suspected improvement.
2. Choose the next action:
   - **Act now** when the change is small, within the authorized task, and verifiable. Do it as part of that task.
   - **File** when an out-of-scope finding has a concrete follow-up and enough context for someone to investigate. A single observation is sufficient; mark uncertainty when the cause or impact is unconfirmed.
   - **Dismiss** when there is no actionable consequence, the concern is unsupported speculation, or an existing item already covers it. Link an existing item when useful.
   - **Reflect** when deciding what to change requires deeper analysis of recurring behavior, conflicting instructions, or broader working practices. Read the `reflect` skill and pass the finding and evidence into its workflow. For routine backlog filing, choose **File**, not **Reflect**, and register the item directly.
3. For filing, use the project's or team's established external backlog and relevant user instructions. Inspect relevant connected capabilities before asking if needed. If no destination is established, ask where to file. File within the host's external-write authorization rules, reusing existing authorization. If filing is blocked, report it as pending.
4. Search for an existing item before creating one. Keep the item short: what was observed, why it matters, evidence pointers, uncertainty, and the next useful investigation or action.

Report the decision and the filed item's link, or what remains pending.
