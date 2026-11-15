# Grok Bot harness notifications

Harness hooks save notification routes and events to SQLite. A launchd worker
delivers the outbox every 30 seconds, outside the model's command sandbox.
The model does not invoke a notification skill or request escalated execution.

This change covers config only. The Grok Bot prompt builder and webhook receiver
in `kidscannon/grokbot` still need the protocol changes below before rollout.

## Registration

Grok Bot puts this block at the beginning of each new native session's prompt:

```text
<grokbot-notify>
{"grok_bot_id":"BOT_ID","t3_code_thread_id":"T3_THREAD_ID"}
</grokbot-notify>
Work instructions follow here.
```

The parser accepts leading whitespace. It ignores examples quoted later in the
prompt and rejects malformed leading blocks. No `request_id` or `version` is
accepted. If `T3CODE_THREAD_ID` is present, it must match the registered thread.

Routes belong to T3 threads. A separate binding maps each provider's native
session to a route. Blockless continuations keep an existing binding across
process restarts. A new native session requires a block even when its environment
names an already registered T3 thread. Provider switching therefore requires a
new block. Native session IDs are never substituted for T3 thread IDs.

A new block updates the route for subsequent runs. Runs already admitted keep
their original bot and thread. Busy Pi input updates the next run's route.
Neither success nor failure removes registration.

To revoke a session's route, submit a leading block containing only
`{"unregister":true}`. To revoke by T3 thread without sending a model prompt:

```sh
grokbot-notify unregister --t3-thread 'T3_THREAD_ID'
```

Revocation cancels pending notifications and invalidates old runs. Re-registering
does not revive them. A request already being transmitted cannot be retracted.
The block is explicit opt-in metadata, not sender authentication.

## Webhook protocol

Credentials retain the existing location and fields:
`~/.config/grokbot-webhook/credentials.json`, containing `url` and `key`.
The worker sends JSON with HTTP POST and `Authorization: Bearer <key>`.
It rejects redirects so credentials do not follow a redirect to another server.

Every payload has these six fields:

```json
{
	"grok_bot_id": "BOT_ID",
	"t3_code_thread_id": "T3_THREAD_ID",
	"provider": "codex",
	"status": "attempt_failed",
	"reason": "model_request_failed",
	"message": "A Codex model request failed. The run may continue."
}
```

| Status | Meaning | Sources |
| --- | --- | --- |
| `response_finished` | The harness has settled. This does not guarantee task completion. | Pi `agent_settled`, final assistant `stopReason=stop` |
| `response_observed` | A Stop hook observed an answer. Another Stop hook can continue the same run. | Codex and Claude `Stop` |
| `attempt_failed` | A model attempt failed. The run may retry or remain stopped. | Codex `PostModelRequest(status=failed)` |
| `stopped` | The harness reported a terminal error or cancellation. | Claude `StopFailure`; Pi settlement with `error`, `length`, or `aborted` |
| `input_requested` | A question tool was invoked. Check T3 pending requests for the actual request and current wait state. | Claude `AskUserQuestion`; Codex `request_user_input` and `request_user_input_async` |

Responses have `reason=null` and visible assistant text. Missing response text
uses `The response text was unavailable.` Thinking blocks are excluded.
Failures use a fixed message rather than raw provider error text.
Claude preserves typed reasons such as `rate_limit`, `billing_error`, or
`unknown`. Pi uses `provider_error`, `max_output_tokens`, and `aborted`.
Codex always uses `model_request_failed`; error prose cannot prove usage limits.

Questions use `question_invoked`, or `async_question` for the explicitly async
Codex tool. Hook input does not establish whether the whole agent is waiting.
The message includes question text and option labels. A PreToolUse notification
can precede creation of the T3 pending request and can precede tool rejection.
Native tool IDs are used internally for deduplication, not as T3 request IDs.

T3 MCP exposes `t3_pending_request`: use `action="list"` with `threadId`, then
`action="read"` with the returned `requestId`. Respond with `action="respond"`,
the same request ID, and `answers` keyed by the question IDs returned by read.
Values are strings or arrays of strings. T3 also turns Codex async agent-message
questions into pending requests. Use the IDs from list and read for both kinds.
This endpoint does not approve execution permissions. No automatic answers or
Grok Bot caller changes are implemented here.

## Persistence and delivery

State lives in `$XDG_STATE_HOME/grokbot-notify/state.sqlite3`, defaulting to
`~/.local/state/grokbot-notify/state.sqlite3`. Directories are private and the
database is mode 0600. The database includes response text; it contains neither
webhook URL nor key.

Registration, run creation, revocation, and outbox writes use SQLite
transactions. Run identity is `(provider, native session, native turn)`.
Codex uses `turn_id`; Claude uses `prompt_id`; Pi generates an input UUID before
model work and retains it through retries. Missing IDs produce diagnostics
instead of a session-wide fallback. Subagent hooks with `agent_id` are ignored.

Duplicate question callbacks are suppressed by tool-call ID. Stop observations
are deduplicated by visible-text hash within the run, allowing a changed answer
after another hook continues it. Other event kinds are emitted once per run.
In particular, Codex emits at most one `attempt_failed` per run because its hook
does not provide a model-request ID. Continuing in a new turn emits new events.

Workers claim events with a 120-second lease and acknowledge only HTTP 2xx.
Each event gets at most five attempts, including attempts interrupted by crashes.
Retries wait 5, 30, 120, then 600 seconds. Network errors, HTTP 408, 429, and 5xx
are retryable; other HTTP errors and TLS verification failures are terminal.
Missing credentials can be repaired before a later attempt. Dead events remain
in state for inspection. There is no automatic reset of their attempt budget.

If delivery succeeds but its acknowledgement is lost, a retry can duplicate the
notification. Receiver deduplication would require a separate protocol change.
Events not yet persisted when a process is killed cannot be reconstructed from
hook absence. The worker retries persisted events after restart.

```sh
grokbot-notify status
grokbot-notify drain
```

`status` shows routes, delivery states, attempt counts, and safe error codes.
`drain` sends due events and is intended for delivery maintenance. Hook diagnostic
codes go to `grokbot-notify/diagnostics.log` beside the database. Worker startup
errors also go to `~/Library/Logs/grokbot-notify.log`. URLs, tokens, provider error
details, and HTTP response bodies are excluded from diagnostics.

## Installed harness boundaries

Verified against Codex 0.167.0, Claude Code 2.1.318, Pi 1.5.0, and T3 0.1.7.

- Codex can compact before `UserPromptSubmit`. Registration therefore precedes
  ordinary answering, but cannot precede every compaction request. Codex has no
  terminal-failure hook. It emits `attempt_failed` even for actual usage limits.
- Claude `StopFailure` does not cover every crash or user interruption. In a
  one-shot `claude -p` process, it can be lost during process exit. The persistent
  stream-json process used by T3 was verified with a loopback fake API.
- Pi records results at `turn_end` and resolves their final session projection
  at `agent_settled`, after retries and continuation handlers. Preflight failures
  without settlement do not produce an invented terminal event.
- T3's ordinary provider launches load user hooks or extensions. Auxiliary
  capability, title, and fork paths can disable them. Extension discovery does
  not start notification delivery. Custom settings-source overrides or extension
  exclusion lists can prevent loading.

Codex hooks are inline in managed `config.toml`; existing Orca `hooks.json` is
preserved. Codex warns when both sources contain hooks. After activation, review
and trust these hooks with `/hooks` in Codex. Untrusted hooks are skipped.
The hook command uses the stable Home Manager profile path, and activation
preserves `hooks.state` so ordinary package updates do not reset trust.

The old `/grokbot-notify` skill and its execution allow-list have been removed.
Complete the Grok Bot prompt and receiver migration before activating with
`nix run .#switch-forge01` or `nix run .#switch-remilis` from committed `main`.

## Verification

`node --test t/grokbot-notify.test.mts t/codex-config.test.mts` runs the common
notification and HTTP tests plus the real Nix activation merge in isolated homes.
Tests cover routing, opt-in, revocation, native identity, deduplication,
concurrent claims, expired leases, stale acknowledgements, and bounded retry.

Offline probes of installed harnesses used isolated user state and OS network
restrictions. Codex probes covered simulated usage limits, retry then success,
misleading error prose, and a question answered by the app-server test client.
Claude probes covered response, terminal API failure, question tools, and no
opt-in with the persistent stream-json transport. Pi probes covered success, retries, exhaustion,
abort, resume, and extension discovery. No real webhook or model API was called.
Live T3 end-to-end delivery and forge01 activation remain unverified.
