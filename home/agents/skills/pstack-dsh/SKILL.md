---
name: pstack-dsh
description: Translates pstack skill instructions (Claude Code tool names, model aliases, subagent types) into DeepSeek Harness tools. Read before running any pstack skill such as poteto-mode.
---

# pstack on DeepSeek Harness

pstack's skills are written in Claude Code's tool language. On DSH they load
unchanged, and this file is the adapter that maps each Claude Code concept to
the DSH tool that replaces it. It plays the same role as pstack's
`pi-tools.md` and `codex-tools.md`.

When a pstack skill names a tool, a model, or a file path that DSH does not
have, use this file instead of guessing.

## Tools

| pstack / Claude Code | DSH |
|---|---|
| `Skill` (invoke another skill) | `skill` |
| `Read` `Write` `Edit` | `read` `write` `edit` |
| `Bash` | `bash` |
| `Grep` `Glob` `LS` | `grep` `glob` `bash` (`ls`) |
| `WebFetch` `WebSearch` | `web_fetch` `web_search` |
| `TodoWrite` | `todo_write` |
| `AskUserQuestion` | `ask_user_question` |
| `ScheduleWakeup` | `schedule_create` — DSH schedules are cron-like and deliver a message to a session; there is no self-paced single wakeup. Prefer finishing the turn over scheduling. |
| `Agent` / `Task` | `subagent`, `subagent_codex`, or `subagent_claude_code` (see below) |
| `SendMessage` | `send_message` |
| `list_agents` | `list_agents` |
| `stop_agent` | `interrupt_agent` |

## Subagents

The Claude Code `Agent` call is split across three DSH tools:

- `subagent` — an in-process child on the session's LLM route. Takes
  `provider`, `model`, and `reasoning_effort` per call (subject to the profile's
  authorized routes).
- `subagent_codex` — a fresh Codex process. The model is fixed by the profile
  configuration, not by the call.
- `subagent_claude_code` — a fresh Claude Code process. The model is fixed by
  the profile configuration, not by the call.

Translate the dispatch fields as follows.

- `subagent_type: "general-purpose"` or no type → `subagent`, with no extra
  preamble.
- `subagent_type: "pstack:<name>"` → prepend the body of
  `~/.agents/pstack-src/plugins/pstack/agents/<name>.md` to the prompt, then
  pick the tool by model (below). DSH has no agent-type registry, so that file
  is the role definition.
- `model` → the backend in the aliases table. Product backends ignore a
  per-call model, so the choice of tool *is* the model choice.
- `@<effort>` suffix (for example `opus @xhigh`) → drop it. Product backends
  take no per-call effort, and the session's effort applies.
- `readonly: true` → DSH has no read-only child; say "do not modify files" in
  the prompt.
- `run_in_background: true` → `subagent` and the product backends return an id
  immediately and deliver the result as a message when the child finishes. Do
  not poll, and do not `sleep`.
- `isolation: worktree` → set the child's `cwd` to a worktree you create first
  with `git worktree add`. DSH has no automatic isolation.
- Follow-up messages (`SendMessage`) work only for `subagent` children.
  `subagent_codex` and `subagent_claude_code` are one-shot: they accept no
  follow-up, no steering, and no resume.

## Model aliases

pstack names models with family aliases. Resolve them to backends, not to model
ids:

| pstack alias | Role in pstack | DSH backend |
|---|---|---|
| `opus` | default, strongest judgment, bug fixes | `subagent_claude_code` |
| `fable` | second strongest | `subagent_codex` |
| `sonnet` | worker (feature work, refactoring, exploration) | `subagent` (profile default route) |
| `haiku` | cheap fourth panel slot | `subagent_codex` or `subagent` |

Two rules keep panel diversity intact: never send every panel entry to the
same backend, and record which backend actually ran when reporting a panel's
result. If a backend is unavailable (Claude is not installed on every host),
substitute the next strongest distinct backend and say so in the response.

Do not read `~/.pi/agent/pstack-models.md`. That sheet is read by the Pi
extension; on DSH this table is authoritative.

## Working notes

- pstack speaks of "bundled skills" at `../<name>/SKILL.md` and of plugin
  assets under `plugins/pstack/`. On DSH the skills live in
  `~/.agents/skills/<name>/` and the rest of the checkout is at
  `~/.agents/pstack-src/`.
- Claude Code's transcript paths (`~/.claude/projects/...`) do not exist here.
  DSH keeps sessions under `$DSH_HOME/sessions/`.
- After writing prose, load `unslop`. After leaving a diff, load `deslop`.
