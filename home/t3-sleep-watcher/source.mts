import { execFile } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { promisify } from 'node:util';
import { includePendingApprovals, parseThread, type Thread } from './policy.mts';

const exec = promisify(execFile);
export const command = async (file: string, args: string[]) => (await exec(file, args, { timeout: 15_000, maxBuffer: 4 * 1024 * 1024 })).stdout;

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function object(value: unknown): Record<string, unknown> {
  if (!isObject(value)) throw new Error('Expected RPC object');
  return value;
}

export class ShellState {
  private rows = new Map<string, Thread>();
  private sequence: number | null = null;
  private synchronized = false;
  apply(value: unknown): readonly Thread[] | null {
    const item = object(value);
    if (item.kind === 'snapshot') {
      // Marked snapshots refresh project metadata; their empty thread lists
      // are not an authoritative replacement of the thread state.
      if (item.resolvedRepositoryIdentityRoots !== undefined) return null;
      const snapshot = object(item.snapshot);
      if (!Array.isArray(snapshot.threads) || !Array.isArray(snapshot.archivedThreads) || typeof snapshot.snapshotSequence !== 'number') throw new Error('Invalid snapshot');
      const rows = [...snapshot.threads, ...snapshot.archivedThreads].map(parseThread);
      this.rows = new Map(rows.map(t => [t.id, t]));
      this.sequence = snapshot.snapshotSequence;
      return this.synchronized ? [...this.rows.values()] : null;
    }
    if (item.kind === 'synchronized') {
      if (this.sequence === null) throw new Error('Synchronized before snapshot');
      this.synchronized = true;
      return [...this.rows.values()];
    }
    if (typeof item.sequence !== 'number' || this.sequence === null) throw new Error('Missing event sequence');
    if (item.sequence <= this.sequence) return null;
    // Shell sequence numbers can skip events that do not change the shell.
    this.sequence = item.sequence;
    switch (item.kind) {
      case 'thread.updated': {
        const thread = parseThread(item.thread);
        this.rows.set(thread.id, thread);
        break;
      }
      case 'thread.removed':
        if (typeof item.threadId !== 'string') throw new Error('Invalid removed thread');
        this.rows.delete(item.threadId);
        break;
      case 'project.updated':
      case 'project.removed': return null;
      default: throw new Error(`Unsupported shell event: ${String(item.kind)}`);
    }
    return this.synchronized ? [...this.rows.values()] : null;
  }
}

export async function subscribe(onThreads: (threads: readonly Thread[]) => void, signal: AbortSignal): Promise<void> {
  const issued = object(JSON.parse(await command('t3', ['auth', 'session', 'issue', '--scope', 'orchestration:read', '--ttl', '1h', '--label', 't3-sleep-watcher', '--json'])));
  if (typeof issued.token !== 'string' || typeof issued.sessionId !== 'string') throw new Error('Invalid issued session');
  let socket: WebSocket | undefined;
  try {
    const runtime = object(JSON.parse(await readFile(`${homedir()}/.t3/userdata/server-runtime.json`, 'utf8')));
    if (typeof runtime.origin !== 'string' || new URL(runtime.origin).hostname !== '127.0.0.1') throw new Error('Expected loopback T3 server');
    const response = await fetch(`${runtime.origin}/api/auth/websocket-ticket`, { method: 'POST', headers: { Authorization: `Bearer ${issued.token}` }, signal: AbortSignal.any([signal, AbortSignal.timeout(10_000)]) });
    if (!response.ok) throw new Error(`Ticket HTTP ${response.status}`);
    const ticket = object(await response.json());
    if (typeof ticket.ticket !== 'string') throw new Error('Missing WebSocket ticket');
    const url = new URL('/ws', runtime.origin);
    url.protocol = 'ws:';
    url.searchParams.set('wsTicket', ticket.ticket);
    url.searchParams.set('orchestrationProtocol', '2');
    await new Promise<void>((resolve, reject) => {
      const state = new ShellState();
      let finished = false;
      let nextRequest = 2;
      let publishing = Promise.resolve();
      const pending = new Map<string, { resolve: (value: unknown) => void; reject: (error: Error) => void; timer: ReturnType<typeof setTimeout> }>();
      let lastFrame = Date.now();
      const startedAt = lastFrame;
      let receivedSnapshot = false;
      const stop = () => finish();
      const health = setInterval(() => {
        if (Date.now() - lastFrame > 20_000 || (!receivedSnapshot && Date.now() - startedAt > 25_000)) finish(new Error('T3 stream timed out'));
        else if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ _tag: 'Ping' }));
      }, 5000);
      // Reconnect before the bearer expires; each connection starts with a full snapshot.
      const rotation = setTimeout(() => finish(), 30 * 60_000);
      function finish(error?: Error) {
        if (finished) return;
        finished = true;
        clearInterval(health);
        clearTimeout(rotation);
        signal.removeEventListener('abort', stop);
        for (const request of pending.values()) {
          clearTimeout(request.timer);
          request.reject(new Error('T3 connection ended'));
        }
        pending.clear();
        error ? reject(error) : resolve();
      }
      function projection(threadId: string): Promise<unknown> {
        const id = String(nextRequest++);
        return new Promise((resolve, reject) => {
          const timer = setTimeout(() => { pending.delete(id); reject(new Error('Thread detail timeout')); }, 10_000);
          pending.set(id, { resolve, reject, timer });
          socket?.send(JSON.stringify({ _tag: 'Request', id, tag: 'orchestration.getThreadProjection', payload: { threadId }, headers: [] }));
        });
      }
      function publish(rows: readonly Thread[]) {
        publishing = publishing.then(async () => {
          if (finished) return;
          // The shell exposes only the newest pending request. A newer input
          // must not hide an older approval and let its ten-minute timer win.
          const complete: Thread[] = [];
          for (const thread of rows) complete.push(thread.input ? includePendingApprovals(thread, await projection(thread.id)) : thread);
          if (!finished) { receivedSnapshot = true; onThreads(complete); }
        }).catch(() => finish(new Error('Could not read pending approvals')));
      }
      signal.addEventListener('abort', stop, { once: true });
      socket = new WebSocket(url);
      socket.onopen = () => socket?.send(JSON.stringify({ _tag: 'Request', id: '1', tag: 'orchestration.subscribeShell', payload: { requestCompletionMarker: true }, headers: [] }));
      socket.onerror = () => finish(new Error('T3 WebSocket failed'));
      socket.onclose = () => finish(new Error('T3 WebSocket closed'));
      socket.onmessage = ({ data }) => {
        try {
          const parsed: unknown = JSON.parse(String(data));
          const frames = Array.isArray(parsed) ? parsed : [parsed];
          for (const value of frames) {
            const frame = object(value);
            lastFrame = Date.now();
            if (frame._tag === 'Ping') { socket?.send(JSON.stringify({ _tag: 'Pong' })); continue; }
            if (frame._tag === 'Chunk') {
              if (!Array.isArray(frame.values)) throw new Error('Invalid RPC chunk');
              for (const item of frame.values) {
                const rows = state.apply(item);
                if (rows) publish(rows);
              }
              socket?.send(JSON.stringify({ _tag: 'Ack', requestId: frame.requestId }));
            } else if (frame._tag === 'Exit') {
              const request = pending.get(String(frame.requestId));
              if (!request) throw new Error('T3 subscription ended');
              clearTimeout(request.timer);
              pending.delete(String(frame.requestId));
              const exit = object(frame.exit);
              if (exit._tag === 'Success') request.resolve(exit.value);
              else request.reject(new Error('T3 detail request failed'));
            } else if (frame._tag === 'Defect') throw new Error('T3 RPC defect');
          }
        } catch { finish(new Error('Invalid or unsupported T3 stream')); }
      };
      if (signal.aborted) finish();
    });
  } finally {
    socket?.close();
    await command('t3', ['auth', 'session', 'revoke', issued.sessionId]);
  }
}
