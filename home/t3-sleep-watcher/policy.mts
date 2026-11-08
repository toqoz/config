export type Thread = {
  id: string;
  status: string;
  input: { id: string; createdAt: number; blocking: boolean } | null;
  approval: boolean;
  background: boolean;
  children: string[];
  blockedOnChildren: boolean;
};

const active = new Set(['queued', 'preparing', 'starting', 'running', 'waiting']);
const terminal = new Set(['idle', 'completed', 'failed', 'interrupted', 'cancelled', 'rolled_back']);

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function object(value: unknown): Record<string, unknown> {
  if (!isObject(value)) throw new Error('Expected object');
  return value;
}

export function parseThread(value: unknown): Thread {
  const row = object(value);
  if (typeof row.id !== 'string' || typeof row.status !== 'string') throw new Error('Invalid thread');
  if (!active.has(row.status) && !terminal.has(row.status)) throw new Error(`Unsupported status: ${row.status}`);
  let input: Thread['input'] = null;
  let approval = false;
  if (row.pendingRuntimeRequest !== null) {
    const request = object(row.pendingRuntimeRequest);
    if (typeof request.kind !== 'string') throw new Error('Invalid request kind');
    if (request.kind === 'user_input') {
      if (typeof request.id !== 'string' || typeof request.createdAt !== 'string' || !Number.isFinite(Date.parse(request.createdAt))) throw new Error('Invalid input request');
      if (request.blocking !== undefined && typeof request.blocking !== 'boolean') throw new Error('Invalid blocking flag');
      input = { id: request.id, createdAt: Date.parse(request.createdAt), blocking: request.blocking !== false };
    } else {
      // Permission, command, file and MCP requests require the user's decision.
      approval = true;
    }
  }
  if (!Array.isArray(row.pendingBackgroundTasks)) throw new Error('Missing background task list');
  const children: string[] = [];
  let background = false;
  for (const value of row.pendingBackgroundTasks) {
    const task = object(value);
    if (task.kind === 'subagent') {
      if (typeof task.childThreadId === 'string') children.push(task.childThreadId);
      else background = true;
    } else if (task.awaited === true) background = true;
  }
  return { id: row.id, status: row.status, input, approval, background, children, blockedOnChildren: row.blockedOnThreadWait === true };
}

export function includePendingApprovals(thread: Thread, projection: unknown): Thread {
  const detail = object(projection);
  if (!Array.isArray(detail.runtimeRequests)) throw new Error('Missing runtime requests');
  const approval = detail.runtimeRequests.some(value => {
    const request = object(value);
    if (typeof request.status !== 'string' || typeof request.kind !== 'string') throw new Error('Invalid runtime request');
    return request.status === 'pending' && request.kind !== 'user_input';
  });
  return { ...thread, approval: thread.approval || approval };
}

export class SleepPolicy {
  private wasWorking = false;
  private completedUntil = 0;
  private inputDeadlines = new Map<string, number>();

  evaluate(threads: readonly Thread[], now: number): { hold: boolean; reason: string } {
    const knownIds = new Set(threads.map(t => t.id));
    const working = threads.some(t => t.approval || t.background || t.children.some(id => !knownIds.has(id)) || (active.has(t.status) && !t.blockedOnChildren && !(t.input?.blocking)));
    const deadlines = new Map<string, number>();
    for (const thread of threads) {
      if (thread.input) deadlines.set(thread.input.id, this.inputDeadlines.get(thread.input.id) ?? Math.min(now, thread.input.createdAt) + 600_000);
    }
    this.inputDeadlines = deadlines;
    const inputUntil = Math.max(0, ...deadlines.values());
    if (working) {
      this.wasWorking = true;
      this.completedUntil = 0;
      return { hold: true, reason: 'working-or-approval' };
    }
    if (this.wasWorking) {
      this.wasWorking = false;
      // An input timeout gets no additional completion grace.
      this.completedUntil = inputUntil > 0 ? 0 : now + 300_000;
    }
    if (now < inputUntil) return { hold: true, reason: 'input-grace' };
    if (now < this.completedUntil) return { hold: true, reason: 'completion-grace' };
    return { hold: false, reason: 'idle' };
  }
}
