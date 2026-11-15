import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';

const command = "@GROKBOT_NOTIFY@";
const entryType = 'grokbot-notify-run';

async function persist(event: object): Promise<string | null> {
  const output = await new Promise<string>((resolve, reject) => {
    const child = spawn(command, ['hook', 'pi'], { stdio: ['pipe', 'pipe', 'ignore'] });
    let text = '';
    const timer = setTimeout(() => { child.kill(); reject(new Error('notification_state_timeout')); }, 8000);
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', (chunk: string) => { text += chunk; });
    child.on('error', reject);
    child.stdin.on('error', reject);
    child.on('close', (code) => {
      clearTimeout(timer);
      if (code === 0) resolve(text);
      else reject(new Error('notification_state_failed'));
    });
    child.stdin.end(JSON.stringify(event));
  });
  const reply: unknown = JSON.parse(output);
  if (typeof reply !== 'object' || reply === null || !('run_id' in reply) ||
      (reply.run_id !== null && typeof reply.run_id !== 'string')) {
    throw new Error('notification_reply_invalid');
  }
  return reply.run_id;
}

export default function (pi: ExtensionAPI) {
  let runId: string | null = null;
  let messageEntryId: string | null = null;

  pi.on('session_start', (_event, ctx) => {
    runId = null;
    messageEntryId = null;
    for (const entry of ctx.sessionManager.getBranch()) {
      if (entry.type !== 'custom' || entry.customType !== entryType) continue;
      const data: unknown = entry.data;
      if (typeof data === 'object' && data !== null && 'session' in data &&
          data.session === ctx.sessionManager.getSessionId() && 'runId' in data &&
          (typeof data.runId === 'string' || data.runId === null)) {
        runId = data.runId;
      }
    }
  });

  pi.on('input', async (event, ctx) => {
    const busy = !ctx.isIdle();
    try {
      const next = await persist({ hook_event_name: 'input', session_id: ctx.sessionManager.getSessionId(),
        run_id: randomUUID(), active_run_id: busy ? runId : null, text: event.text });
      runId = next;
      if (!busy) messageEntryId = null;
      if (runId) pi.appendEntry(entryType, { session: ctx.sessionManager.getSessionId(), runId });
    } catch {
      ctx.ui.notify('Grok Bot notification registration failed; input was not submitted.', 'error');
      return { action: 'handled' };
    }
  });

  pi.on('turn_end', (event) => {
    if (runId && event.message.role === 'assistant') messageEntryId = event.messageEntryId;
  });

  pi.on('agent_settled', async (event, ctx) => {
    if (!runId) return;
    try {
      const entries = ctx.sessionManager.buildSessionProjection().entries;
      const index = entries.findIndex((entry) => entry.sourceEntry.id === messageEntryId);
      const message = index < 0 ? null : entries.slice(index).flatMap((entry) => entry.messages)
        .findLast((item) => item.role === 'assistant') ?? null;
      await persist({ hook_event_name: 'agent_settled', session_id: ctx.sessionManager.getSessionId(),
        run_id: runId, aborted: event.aborted, message });
      runId = null;
      messageEntryId = null;
      pi.appendEntry(entryType, { session: ctx.sessionManager.getSessionId(), runId });
    } catch {
      ctx.ui.notify('Grok Bot notification could not be queued; check the local state log.', 'error');
    }
  });
}
