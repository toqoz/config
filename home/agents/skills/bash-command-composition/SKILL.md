---
name: bash-command-composition
description: Apply the user's command-separation preference when combining multiple shell operations in agent tool calls or considering an && chain. Use for multi-command composition, not individual shell commands.
user-invocable: false
---

# Compose Shell Commands

- Run independent operations as separate tool calls. Use the host's parallel-call mechanism when appropriate.
- Use `&&` only when the next operation genuinely depends on the previous operation succeeding, such as `mkdir -p "$dir" && cp "$source" "$dir/"`.
- Independent file reads or checks do not become dependent merely because stopping on the first failure is convenient.
- Do not replace an unnecessary `&&` chain with semicolons just to keep independent operations in one tool call.
