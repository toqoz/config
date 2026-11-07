---
name: coding-practice
description: Default workflow for non-trivial coding tasks. Covers task clarification, constrained execution, design choices, and concrete verification.
---

# Coding practice

- Identify the problem, constraints, and success criteria from available context.
  Ask only for missing information that prevents progress.
  An adoption evaluation does not authorize integrating the candidate; complete
  the comparison and keep independently authorized changes separate.
- Read the code that owns the behavior, its contracts, and existing tests before
  changing it. Names and paths are clues, not proof of behavior. Existing code
  is not proof of correctness; fit the intended structure without copying flaws.
- Keep the change within the task. Avoid broad rewrites, unrelated cleanup,
  and speculative extension points.
- Compare viable approaches by dependencies, layers of indirection, clear input
  and output contracts, explicit failure behavior, hidden state, testability in
  isolation, and ease of replacement or removal. Use judgment rather than a
  rigid ranking, and work with the framework.
- Add dependencies, helpers, or abstractions only for a present benefit: reducing
  real complexity, replacing error-prone custom logic, serving existing callers,
  or removing harmful duplication. Popularity and hypothetical reuse do not
  justify them.
- Preserve behavior outside the requested change. Explain intentional behavior
  changes and compatibility impacts.
- Verify the actual result with relevant tests or reproducible checks. Follow
  repository requirements for webapp and TUI acceptance checks.
