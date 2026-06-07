---
name: slack
description: |
  Slack operations: read/send/edit/delete messages, browse channel history, search messages/files,
  add/remove reactions, draft messages in a rich-text editor, and list channels.
  Use this skill — not agent-slack — for all Slack tasks.
---

# Slack skill

**SKILL Bundled Scripts**: `./scripts/slack-cli`

## Prerequisites

Import credentials from Slack Desktop (macOS, one-time):

```bash
./scripts/slack-cli auth import-desktop
```

List configured workspaces and verify each credential with `auth.test`:

```bash
./scripts/slack-cli auth list
```

## Message operations

### Fetch a single message
```bash
# By Slack URL
./scripts/slack-cli \
  message get "https://team.slack.com/archives/C123/p1700000000000000"

# By channel + timestamp
./scripts/slack-cli \
  message get general --ts 1700000000.000000
```

### List messages (channel history or thread)
```bash
# Channel history (last 25 messages)
./scripts/slack-cli \
  message list general --limit 25

# Thread replies — URL with thread_ts auto-detected
./scripts/slack-cli \
  message list "https://team.slack.com/archives/C123/p1700000000000000?thread_ts=1699999999.000000"

# Thread replies — channel + explicit thread-ts
./scripts/slack-cli \
  message list general --thread-ts 1700000000.000000
```

### Draft (browser rich-text editor)
Opens a Slack-styled editor in the **user's default browser**. The command
blocks until the user sends the message or the idle timeout (10 minutes) fires.
Send button posts to Slack and shows a "View in Slack" link.

**Agent workflow:** The command opens a browser window for the *user*, not for
the agent. Do **not** try to open the draft URL with `agent-browser`. Run the
command with `run_in_background: true` and wait for the background task
notification — when it completes, the user has sent (or dismissed) the draft.

```bash
# Post to channel
./scripts/slack-cli \
  message draft general "Here is my draft text"

# Reply in thread
./scripts/slack-cli \
  message draft "https://team.slack.com/archives/C123/p1700000000000000"
```

### Send, edit, delete, react
```bash
# Send
./scripts/slack-cli \
  message send general "Hello, world"

# Reply in thread (URL → posts as reply)
./scripts/slack-cli \
  message send "https://team.slack.com/archives/C123/p1700000000000000" "I can take this"

# Edit
./scripts/slack-cli \
  message edit "https://team.slack.com/archives/C123/p1700000000000000" "Updated text"

# Delete
./scripts/slack-cli \
  message delete "https://team.slack.com/archives/C123/p1700000000000000"

# React
./scripts/slack-cli \
  message react add "https://team.slack.com/archives/C123/p1700000000000000" eyes

./scripts/slack-cli \
  message react remove "https://team.slack.com/archives/C123/p1700000000000000" eyes
```

---

## Channel operations

```bash
# List joined channels (default, most useful for agents)
./scripts/slack-cli channel list

# List all public channels in workspace
./scripts/slack-cli channel list --all --limit 200

# Paginate
./scripts/slack-cli \
  channel list --cursor <next_cursor>
```

---

## Search operations

Requires a user token (`xoxc` or `xoxp`). Bot tokens (`xoxb`) lack `search:read`.

```bash
# Search messages
./scripts/slack-cli \
  search messages "deploy failed" --channel alerts --after 2026-04-01

# Search files
./scripts/slack-cli \
  search files "Q4 report" --limit 10

# Search messages + files
./scripts/slack-cli \
  search all "incident postmortem" --after 2026-01-01

# Scoped to a user
./scripts/slack-cli \
  search messages "PR review" --user @alice
```

---

## File operations

### Download a file by permalink

Downloads land in `./.agents/cache/slack-cli/files/<file_id>-<name>`
(cwd-relative). The file-ID prefix prevents collisions when multiple files
share a name.

```bash
./scripts/slack-cli \
  file download "https://team.slack.com/files/U01234567/F0ABCDE/screenshot.png"
```

The resolved `path` is included in the JSON output for downstream commands.

---

## Multi-workspace

When multiple workspaces are configured, **always pass `--workspace`**. The CLI does not infer the workspace from Slack URLs — omitting the flag silently falls back to the first workspace, which causes `channel_not_found` errors or sends messages to the wrong workspace.

Extract the workspace from the Slack URL subdomain (e.g. `https://<team>.slack.com/...` → `--workspace <team>`).

```bash
./scripts/slack-cli \
  message list general --workspace <team>
```

`--workspace` accepts a URL substring (e.g. `myteam` matches `https://myteam.slack.com`).

---

## Reply policy

- **Always use `message draft`** to compose replies. Never use `message send` directly unless the user explicitly says to skip the draft (e.g. "send it directly", "no draft").
- The draft editor shows the destination channel and the message being replied to, so the user can verify before sending.

## Bash command rules (Claude Code permission system)

1. **No `#` in the command string.** Use bare channel names (`general`, not `#general`).
2. **Each script invocation is a single Bash tool call.** Do not chain with `&&` or `||`.
3. **No `>` file redirects.** Process JSON output directly with `jq` if needed.
4. **JSON output is printed to stdout.** Errors go to stderr; exit code non-zero on failure.
