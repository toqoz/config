---
name: debugging-practice
description: Use this for debugging, reproduction, and root-cause analysis. Suspect recent changes and local assumptions before blaming external systems.
---

# Debugging practice

- Before forming a theory, establish the observed behavior, expected behavior,
  and triggering conditions. Share these when they help explain the diagnosis.
- Attempt a small, reliable reproduction before fixing the problem. Keep the
  inputs, environment, and commands needed to repeat it. If reproduction is
  unavailable, keep the cause unconfirmed.
- Investigate recent changes, configuration, assumptions, and integration
  boundaries first. Check local inputs and outputs before attributing a defect
  to an external system; report the evidence for that conclusion.
- Give each hypothesis a concrete check. Change one thing at a time while
  diagnosing, and revert changes based on a refuted hypothesis.
- Trace where behavior first becomes wrong and fix the fault there. If providing
  a workaround instead, identify it as such rather than claiming a root-cause fix.
- Verify the fix against the original reproduction. Report the cause and the
  verification, or state what remains unknown and the next discriminating check.
