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

   ```sh
   python3 /absolute/path/to/grokbot-notify/scripts/notify.py 'GROK_BOT_ID'
   ```

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
