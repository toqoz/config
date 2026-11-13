---
name: grokbot-notify
description: Send a Grokbot webhook notification for the current T3 Code thread. Use when the user invokes /grokbot-notify <grok_bot_id> or explicitly asks to notify a Grokbot bot.
disable-model-invocation: false
argument-hint: <grok_bot_id>
---

# Notify Grokbot

Send one notification for the bot ID supplied by the user.

## Configure credentials

Read credentials through the bundled script from
`~/.config/grokbot-webhook/credentials.json`. The file contains:

```json
{
	"url": "https://example.com/webhook",
	"key": "your-webhook-key"
}
```

`url` is the webhook URL (`GROKBOT_WEBHOOK_URL`), and `key` is its bearer token
(`GROKBOT_WEBHOOK_KEY`). Keep both values in this file rather than shell arguments
or environment variables. Do not print the file or include its contents in chat.
If the file is missing, show the expected path and JSON field names without
asking the user to paste credentials into chat.

## Send the notification

1. Take exactly one bot ID from the invocation. If it is missing, ask for it.
2. Run the bundled script with the bot ID as one quoted argument. Resolve the
   script path relative to this `SKILL.md`, and keep the current working directory.
   For Codex, choose the execution permissions below before sending.

   ```sh
   python3 /absolute/path/to/grokbot-notify/scripts/notify.py 'GROK_BOT_ID'
   ```

### Execute with Codex

If the session permits network access, use the normal command execution tool.
If the sandbox restricts network access and the active approval policy permits
escalation requests, call `exec_command` with these arguments for the first send:

```json
{
	"cmd": "python3 /absolute/path/to/grokbot-notify/scripts/notify.py 'GROK_BOT_ID'",
	"sandbox_permissions": "require_escalated",
	"justification": "Send the requested Grokbot webhook notification for the current T3 Code thread."
}
```

`sandbox_permissions` is an execution-tool argument. Do not pass it to Python
or add it to the skill frontmatter. Request permission only for this notification
command, and do not request a persistent command-prefix rule.

T3 Code's `runtimeMode: "auto"` routes eligible requests through automatic review.
The caller selects that mode. This skill does not change the thread's runtime mode,
and review can deny the request.

If the active policy is `never` or the tool prohibits escalation requests, do not
set `sandbox_permissions`. If network access is also restricted, report that the
notification cannot run under the current permissions. If review denies a request,
report the denial and its reason without trying another execution path.

### Execute with other agents

For Claude Code and other agents, use their shell tool under its active permission
policy. Do not copy Codex-specific execution arguments into those tools.

## Verify the result

The script reads the current T3 Code thread ID from `T3CODE_THREAD_ID`. If it is
missing, report the error. Do not substitute a Codex or Claude Code session ID,
invent an ID, or select another thread.

The script sends a JSON POST to `url` with these values:

```text
Authorization: Bearer <key>
Content-Type: application/json

{"grok_bot_id": "<grok_bot_id>", "t3_code_thread_id": "<T3CODE_THREAD_ID>"}
```

Report success only when the script exits successfully after an HTTP 2xx
response. On failure, report the script's error. Do not retry automatically:
the server might have received the notification even if the response was lost.
