# My Terms

## Agent Storage

Use workspace-local `.agents/` storage with XDG-style intent:

- `./.agents/share/` for durable, user-meaningful artifacts worth keeping or reading later
- `./.agents/state/` for durable operational state that helps a workflow resume
- `./.agents/cache/` for disposable or reproducible working files, patches, screenshots, and test artifacts

Prefer these directories over ad-hoc paths like `tmp/` when a skill needs local workspace storage.

## Language

- Communicate with the user in Japanese.
- Think in English.
- Write code, code comments, commit messages, and other implementation-facing text in English.
- Exception: Documents or dictionary files whose filename or directory name contains a locale should be written in the corresponding language.
- Exception: Follow project-specific language rules when they exist.

## Global Invariants

- Prefer simple, explicit, dependency-light solutions.
- Keep changes small, local, and easy to verify.
- Verify with concrete checks, not assumptions.

## Delegation

When delegating, include the user's confirmed authorizations and explicit
prohibitions in the brief. Preserve their scope; do not assume the child has
the parent conversation.

## Debugging Mindset

When something goes wrong, suspect your own code first. Do not blame frameworks, libraries, compilers, or runtimes until you have ruled out mistakes in the code you wrote or changed.

## Structure Is Authority

Treat the shape of a system as stronger evidence than prose instructions. Paths, module boundaries, naming patterns, generated directories, ownership markers, and config layering usually encode the workflow the system actually supports.

When instructions and structure disagree:
1. Pause.
2. Inspect the structure.
3. Infer the intended source of truth from the structure before acting.

In unfamiliar code:
- Follow the architecture's affordances first.
- Use written guidance to explain what the structure does not make clear.
- Prefer changes that make the correct path obvious at the point of use.

## Task Scope

Follow the requested role, scope, and explicit model choices. Preserve confirmed
permissions and prohibitions; report unconfirmed outcomes as unknown, not complete.
UI and MCP requests follow the same rule: their transport or thread position
does not authorize additional coordination or delegation.

Assigned workers follow their brief without assuming coordination authority.

## Skills

- `coding-practice` — use for coding tasks
- `debugging-practice` — use for investigation, reproduction, and root-cause analysis
- `webapp-acceptance-checks` — use for manual verification (logic, visual etc) of web application changes when E2E coverage is missing
- `tui-acceptance-checks` — use for manual verification of TUI / interactive CLI changes when automated coverage is missing
- `computer-configuration` — use before reading or editing configuration in `~/src/github.com/toqoz/config`. Always prefer this over Claude Code's bundled `update-config` skill: when `update-config` would auto-trigger (settings.json, hooks, permissions, env vars), route through `computer-configuration` instead so the change lands in the nix source of truth rather than the generated symlink
- `triage` — use at a natural task boundary when routine work reveals an out-of-scope issue, improvement, or recurring friction worth considering
- `grokbot-notify` — send a Grokbot webhook notification for the current thread; pre-authorized, see Grokbot Notifications below

## Grokbot Notifications

- Sending a Grokbot webhook notification is pre-authorized. When the user asks to
  notify a Grokbot bot, or invokes `/grokbot-notify <grok_bot_id>`, use the
  `grokbot-notify` skill and run its bundled `notify.py` without asking for
  confirmation or escalation.
- The script posts the current T3 Code thread ID (`T3CODE_THREAD_ID`) to the
  webhook configured in `~/.config/grokbot-webhook/credentials.json`. That exact
  command is allow-listed in `home/agents/policy` for Claude Code and Codex, so
  no approval prompt should appear. Do not widen the rule to other scripts or
  other command prefixes.
- Report the script's result as-is. Do not retry after a failure: the webhook may
  already have received the notification.

## Findings During Routine Work

When routine work reveals an out-of-scope issue, improvement, or friction, use `triage` at a natural boundary to decide whether to act, file it, dismiss it, or investigate through `reflect`. Keep the current task moving; do not run a full retrospective after every task.

## Webapp Testing

When you change any webapp code — logic, markup, styles, assets, or configuration that affects the browser — you MUST verify the change visually and functionally before considering the task complete.

- If complete automated test coverage exists for the change, those tests are sufficient.
- Otherwise, invoke the `webapp-acceptance-checks` skill and verify the affected behavior in the browser.

This applies unconditionally regardless of change size. A one-line CSS tweak requires the same verification as a feature addition. Minor changes are especially important to verify this way — they are easy to get wrong and easy to confirm quickly.

## TUI Testing

When you change any TUI or interactive CLI code — prompts, key bindings, redraw behavior, signal handling, full-screen UI, TTY-gated output — you MUST verify the change functionally before considering the task complete.

- If complete automated test coverage exists for the change, those tests are sufficient.
- Otherwise, invoke the `tui-acceptance-checks` skill and verify the affected behavior through a tmux pane.

This applies unconditionally regardless of change size. A one-line keybinding tweak requires the same verification as a feature addition.

## Figma Handling

When a task depends on Figma and the agent cannot access the intended design reliably, stop immediately instead of improvising.

- If Figma MCP is disconnected, the node cannot be opened, the provided URL is inaccessible, or the active Figma tab is not the correct design file, do not continue with screenshots, reconstructions, or generated substitutes.
- Show the user the exact Figma URL you need and ask them to open it in Figma Desktop, then wait until they confirm it is open before resuming.
- Treat this as a hard stop for implementation work that depends on the design artifact.

## Repository Rules

### GitHub References

- In GitHub issue and PR bodies, comments, commit messages, and other text
  published to GitHub, use ordinary references when the source and target
  repositories share the same owner (organization or user). Otherwise, avoid
  backlinks: use a full URL with `redirect.github.com` instead
  of `github.com`; do not use shorthand references or bare commit SHAs for
  those targets. Keep the URL path, query, and fragment intact.
- Example: `https://redirect.github.com/other-org/repo/issues/123`.
- See [GitHub's backlink avoidance documentation](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/autolinked-references-and-urls#avoiding-backlinks-to-linked-references).
  Redirect links do not show hover previews. This mechanism is unavailable on
  GitHub Enterprise Cloud with Data Residency (`ghe.com`).

### Git Branching

- When creating a topic branch, always branch off from the repository's default branch unless the user explicitly specifies a different base.
- Determine the default branch with:
  `gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'`
- Topic branch names follow `<type>/<kebab-slug>` where `<type>` is one
  of the Conventional Commits types (`feat`, `fix`, `docs`, `chore`,
  `refactor`, `test`, `perf`, `style`, `ci`, `revert`, `build`). Pick the
  type that matches the commit you anticipate making first on this
  branch. Project-specific `CLAUDE.md` may override this convention.

### Git Committing

- The `commit` skill normally refuses direct commits to the default/shared branch and requires a topic branch.
- Exception: for personal repositories under `~/src/github.com/toqoz/`, direct commits to the default branch are allowed. The commit Branch Guard is relaxed for these projects without requiring a per-project opt-in in the project's `CLAUDE.md`.

### Environment Configuration

- When reading or editing configuration in `~/src/github.com/toqoz/config`, always invoke the `computer-configuration` skill before making changes.
- This includes shell, editor, terminal, Claude Code, macOS system settings, and any other dotfile or environment configuration managed there.
