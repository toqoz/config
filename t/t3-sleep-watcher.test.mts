import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SleepPolicy, parseThread, includePendingApprovals } from '../home/t3-sleep-watcher/policy.mts';
import { ShellState } from '../home/t3-sleep-watcher/source.mts';
import { Lease, type Run } from '../home/t3-sleep-watcher/lease.mts';

const row = (fields: object = {}) => ({ id: 'root', status: 'running', pendingRuntimeRequest: null, pendingBackgroundTasks: [], ...fields });
const input = (createdAt: number, fields: object = {}) => ({ id: 'question', kind: 'user_input', createdAt: new Date(createdAt).toISOString(), ...fields });

test('completion grace starts once and expires after five minutes', () => {
  const policy = new SleepPolicy();
  assert.equal(policy.evaluate([parseThread(row())], 1000).hold, true);
  assert.equal(policy.evaluate([], 2000).hold, true);
  assert.equal(policy.evaluate([], 301999).hold, true);
  assert.equal(policy.evaluate([], 302000).hold, false);
});

test('starting idle does not hold the machine awake', () => {
  assert.equal(new SleepPolicy().evaluate([], 1000).hold, false);
});

test('blocking input expires ten minutes after the request, without extra grace', () => {
  const policy = new SleepPolicy();
  policy.evaluate([parseThread(row())], 1000);
  const waiting = parseThread(row({ status: 'waiting', pendingRuntimeRequest: input(2000) }));
  assert.equal(policy.evaluate([waiting], 2000).reason, 'input-grace');
  assert.equal(policy.evaluate([waiting], 601999).hold, true);
  assert.equal(policy.evaluate([waiting], 602000).hold, false);
});

test('a future-dated input does not slide its deadline on every update', () => {
  const policy = new SleepPolicy();
  const waiting = parseThread(row({ pendingRuntimeRequest: input(1_000_000) }));
  assert.equal(policy.evaluate([waiting], 0).hold, true);
  assert.equal(policy.evaluate([waiting], 600000).hold, false);
});

test('async questions do not time out an agent that continues working', () => {
  const thread = parseThread(row({ pendingRuntimeRequest: input(0, { blocking: false }) }));
  assert.equal(new SleepPolicy().evaluate([thread], 700000).hold, true);
});

test('approval continues indefinitely, even on a terminal parent', () => {
  const thread = parseThread(row({ status: 'completed', pendingRuntimeRequest: { kind: 'permission' } }));
  assert.equal(new SleepPolicy().evaluate([thread], 99_000_000).hold, true);
});

test('a newer input request cannot hide an older pending approval', () => {
  const thread = parseThread(row({ status: 'waiting', pendingRuntimeRequest: input(0) }));
  const complete = includePendingApprovals(thread, { runtimeRequests: [
    { kind: 'permission', status: 'pending' },
    { kind: 'user_input', status: 'pending' },
  ] });
  assert.equal(new SleepPolicy().evaluate([complete], 700000).hold, true);
  const resolved = includePendingApprovals(thread, { runtimeRequests: [{ kind: 'permission', status: 'resolved' }] });
  assert.equal(new SleepPolicy().evaluate([resolved], 700000).hold, false);
});

test('a working child holds a completed parent awake', () => {
  const threads = [parseThread(row({ status: 'completed' })), parseThread(row({ id: 'child' }))];
  assert.equal(new SleepPolicy().evaluate(threads, 0).hold, true);
});

test('a parent waiting on a child question respects the child input deadline', () => {
  const parent = parseThread(row({ status: 'waiting', blockedOnThreadWait: true, pendingBackgroundTasks: [{ kind: 'subagent', childThreadId: 'child' }] }));
  const child = parseThread(row({ id: 'child', status: 'waiting', pendingRuntimeRequest: input(0) }));
  const policy = new SleepPolicy();
  assert.equal(policy.evaluate([parent, child], 0).hold, true);
  assert.equal(policy.evaluate([parent, child], 600000).hold, false);
});

test('unobserved children and explicitly awaited work keep the machine awake', () => {
  for (const task of [{ kind: 'subagent', childThreadId: 'unknown' }, { kind: 'command', awaited: true }]) {
    const thread = parseThread(row({ status: 'completed', pendingBackgroundTasks: [task] }));
    assert.equal(new SleepPolicy().evaluate([thread], 0).hold, true);
  }
  const server = parseThread(row({ status: 'completed', pendingBackgroundTasks: [{ kind: 'command' }] }));
  assert.equal(new SleepPolicy().evaluate([server], 0).hold, false);
});

test('unsupported or incomplete payloads fail instead of becoming idle', () => {
  assert.throws(() => parseThread(row({ status: 'unknown' })));
  assert.throws(() => parseThread({ id: 'missing', status: 'idle' }));
  assert.throws(() => parseThread(row({ pendingRuntimeRequest: input(0, { createdAt: 'invalid' }) })));
});

test('snapshot and event stream includes archived and child rows', () => {
  const state = new ShellState();
  const snapshot = state.apply({ kind: 'snapshot', snapshot: { snapshotSequence: 10, threads: [row()], archivedThreads: [row({ id: 'archive' })] } });
  assert.equal(snapshot, null);
  assert.equal(state.apply({ kind: 'synchronized' })?.length, 2);
  const updated = state.apply({ kind: 'thread.updated', sequence: 11, thread: row({ id: 'child' }) });
  assert.equal(updated?.length, 3);
  assert.equal(state.apply({ kind: 'thread.removed', sequence: 12, threadId: 'root' })?.length, 2);
  assert.equal(state.apply({ kind: 'thread.updated', sequence: 11, thread: row() }), null);
});

test('project enrichment snapshots never clear threads or advance their sequence', () => {
  const state = new ShellState();
  state.apply({ kind: 'snapshot', snapshot: { snapshotSequence: 10, threads: [row()], archivedThreads: [] } });
  assert.equal(state.apply({ kind: 'snapshot', resolvedRepositoryIdentityRoots: ['/repo'], snapshot: { snapshotSequence: 20, threads: [], archivedThreads: [] } }), null);
  assert.equal(state.apply({ kind: 'synchronized' })?.length, 1);
  assert.equal(state.apply({ kind: 'thread.updated', sequence: 11, thread: row({ id: 'child' }) })?.length, 2);
});

test('lease acquires, heartbeats the same UUID, then releases', async () => {
  const calls: string[][] = [];
  const run: Run = async args => { calls.push(args); return { code: 0, active: true }; };
  const lease = new Lease();
  assert.equal(await lease.update(true, 0, run), 'held');
  assert.equal(await lease.update(true, 30000, run), 'held');
  assert.equal(await lease.update(false, 60000, run), 'released');
  assert.deepEqual(calls.map(c => c[1]), ['acquire', 'heartbeat', 'release']);
  assert.equal(calls[0][3], calls[1][3]);
  assert.equal(calls[1][3], calls[2][3]);
  assert.ok(calls[0].includes('90'));
});

test('revocation and disabled automation are not fought by reacquiring', async () => {
  for (const code of [3, 4]) {
    const lease = new Lease();
    await lease.update(true, 0, async () => ({ code: 0, active: true }));
    assert.equal(await lease.update(true, 30000, async () => ({ code, active: false })), 'revoked-or-expired');
    assert.equal(await lease.update(true, 60000, async () => { throw new Error('must not call'); }), 'disabled-until-restart');
  }
});

test('Keepresso safety pause is reported, not treated as an active sleep assertion', async () => {
  const lease = new Lease();
  assert.equal(await lease.update(true, 0, async () => ({ code: 0, active: false })), 'safety-paused');
});

test('six-day rotation acquires a new lease before releasing the old one', async () => {
  const lease = new Lease();
  const calls: string[][] = [];
  const run: Run = async args => { calls.push(args); return { code: 0, active: true }; };
  await lease.update(true, 0, run);
  await lease.update(true, 6 * 86400000, run);
  assert.deepEqual(calls.map(c => c[1]), ['acquire', 'heartbeat', 'acquire', 'release']);
  assert.notEqual(calls[0][3], calls[2][3]);
  assert.equal(calls[0][3], calls[3][3]);
});
