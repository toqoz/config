// Real-debugger tests: every case spawns a real `serve` session that drives a
// real Node target over CDP. Fixtures live in per-test temp dirs.
import { spawn, spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { request } from './step-driver.mjs';

const DRIVER = fileURLToPath(new URL('./step-driver.mjs', import.meta.url));

function tmpdir() {
  return fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'stc-')));
}

function write(dir, name, text) {
  const file = path.join(dir, name);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, text);
  return file;
}

function startServe(sessionDir, nodeArgs) {
  const proc = spawn(process.execPath, [DRIVER, 'serve', sessionDir, '--', ...nodeArgs], { stdio: ['ignore', 'pipe', 'pipe'] });
  let stdout = '';
  let stderr = '';
  proc.stdout.on('data', (d) => { stdout += d; });
  proc.stderr.on('data', (d) => { stderr += d; });
  const exited = new Promise((resolve) => proc.on('close', (code, signal) => resolve({ code, signal, stdout, stderr })));
  return { proc, exited };
}

async function withSession(nodeArgs, fn, { fixtures = {} } = {}) {
  const root = tmpdir();
  const files = Object.fromEntries(Object.entries(fixtures).map(([name, text]) => [name, write(root, name, text)]));
  const sessionDir = path.join(root, 's');
  const serve = startServe(sessionDir, nodeArgs.map((a) => files[a] ?? a.replaceAll('{root}', root)));
  const send = async (...argv) => request(sessionDir, argv);
  try {
    await fn({ root, files, sessionDir, serve, send });
  } finally {
    if (serve.proc.exitCode === null && serve.proc.signalCode === null) {
      serve.proc.kill('SIGTERM');
      await serve.exited;
    }
    fs.rmSync(root, { recursive: true, force: true });
  }
}

function alive(pid) {
  try { process.kill(pid, 0); return true; } catch (err) { return err.code !== 'ESRCH'; }
}

function transcript(sessionDir) {
  return fs.readFileSync(path.join(sessionDir, 'transcript.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
}

// Event-driven wait for a transcript record (fs.watch, bounded).
function waitForRecord(sessionDir, pred, ms = 5000) {
  const file = path.join(sessionDir, 'transcript.jsonl');
  return new Promise((resolve, reject) => {
    const check = () => { const r = transcript(sessionDir).find(pred); if (r) { done(); resolve(r); } };
    const watcher = fs.watch(file, check);
    const timer = setTimeout(() => { done(); reject(new Error('transcript record not written')); }, ms);
    const done = () => { clearTimeout(timer); watcher.close(); };
    check();
  });
}

const TS_FIXTURE = `type Item = { id: number; qty: number };
const writes: string[] = [];
export async function applyDiscount(items: Item[], code: string): Promise<number> {
  let total = 0;
  for (const it of items) {
    total += it.qty * 10;
  }
  if (code === 'HALF') {
    total = total / 2;
  }
  await new Promise((r) => setTimeout(r, 5));
  writes.push(\`total=\${total}\`);
  console.log('user-visible total', total);
  return total;
}
applyDiscount([{ id: 1, qty: 2 }, { id: 2, qty: 3 }], process.argv[2] ?? 'NONE').then((t) => {
  process.exitCode = t > 30 ? 0 : 3;
});
`;

test('initial pause, TypeScript line alignment, moved/resolved breakpoints and hits', async () => {
  await withSession(['fixture.ts', 'HALF'], async ({ files, send, sessionDir, serve }) => {
    const url = pathToFileURL(files['fixture.ts']).href;
    const start = await send('where');
    assert.equal(start.state, 'paused');
    assert.equal(start.reason, 'Break on start');
    assert.equal(start.url, url);

    const moved = (await send('bp', 'fixture.ts', '3')).breakpoint;
    assert.equal(moved.status, 'moved');
    assert.deepEqual(moved.locations.map((l) => l.line), [4]);
    const exact = (await send('bp', files['fixture.ts'], '9')).breakpoint;
    assert.equal(exact.status, 'resolved');
    assert.equal(exact.requested.url, url);

    const first = await send('continue', '--expect', 'stops at let total = 0 (bp moved from 3 to 4)');
    assert.equal(first.outcome, 'paused');
    assert.deepEqual(first.after.hitBreakpoints, [moved.id]);
    assert.equal(first.after.line, 4);

    const second = await send('continue', '--expect', 'HALF branch: stops at total = total / 2');
    assert.deepEqual(second.after.hitBreakpoints, [exact.id]);
    const sourceLine = fs.readFileSync(files['fixture.ts'], 'utf8').split('\n')[8];
    assert.equal(second.after.code, sourceLine, 'stripped TS keeps line text and position');
    assert.equal((await send('eval', 'total')).value, 50);

    const src = await send('source', '--context', '1');
    assert.deepEqual(src.lines.map((l) => l.line), [8, 9, 10]);
    assert.ok(src.lines[1].current);
    assert.equal((await send('stack')).frames[0].function, 'applyDiscount');

    const end = await send('continue', '--expect', 'prints total 25 and exits 3');
    assert.equal(end.outcome, 'exited');
    assert.deepEqual(end.after, { state: 'exited', code: 3, signal: null });
    const report = await send('report');
    assert.equal(report.stdout.text, 'user-visible total 25\n');
    assert.deepEqual(report.breakpoints.map((b) => b.hits), [1, 1]);

    const stopped = await send('stop');
    assert.equal(stopped.killed, false);
    assert.equal((await serve.exited).code, 0);
    assert.equal(fs.existsSync(path.join(sessionDir, 'ctl.sock')), false);
  }, { fixtures: { 'fixture.ts': TS_FIXTURE } });
});

test('pending breakpoint resolves and hits later; ambiguous suffix is rejected', async () => {
  const fixtures = {
    'main.mjs': `import { a } from './a/util.mjs';\nimport { b } from './b/util.mjs';\nconst { lazy } = await import('./lazy.mjs');\nconsole.log(a + b + lazy());\n`,
    'a/util.mjs': 'export const a = 1;\n',
    'b/util.mjs': 'export const b = 2;\n',
    'lazy.mjs': 'export function lazy() {\n  return 40;\n}\n',
  };
  await withSession(['main.mjs'], async ({ send }) => {
    // ESM: the initial pause is in the first evaluated module, before later modules are parsed.
    const start = await send('where');
    assert.equal(start.reason, 'Break on start');
    assert.match(start.url, /\/a\/util\.mjs$/);

    const pending = (await send('bp', 'lazy.mjs', '2')).breakpoint;
    assert.equal(pending.accepted, true);
    assert.equal(pending.status, 'pending');
    assert.equal(pending.hits, 0);

    const hit = await send('continue', '--expect', 'lazy.mjs loads, pauses at return 40');
    assert.equal(hit.outcome, 'paused');
    assert.deepEqual(hit.after.hitBreakpoints, [pending.id]);
    assert.match(hit.after.url, /\/lazy\.mjs$/);
    const bp = (await send('bps')).breakpoints.find((b) => b.id === pending.id);
    assert.equal(bp.status, 'resolved');
    assert.equal(bp.hits, 1);

    // Both util.mjs scripts are loaded now, so the bare suffix is ambiguous.
    const ambiguous = await send('bp', 'util.mjs', '1');
    assert.equal(ambiguous.ok, false);
    assert.match(ambiguous.error, /ambiguous: .*a\/util\.mjs, .*b\/util\.mjs/);
    assert.equal((await send('bp', 'b/util.mjs', '1')).breakpoint.status, 'resolved');
  }, { fixtures });
});

test('eval is side-effect-free: assignment and mutation are blocked', async () => {
  const fixtures = { 'main.js': 'let x = 2;\nconst arr = [];\nx += 1;\narr.push(x);\nconsole.log(x, arr.length);\n' };
  await withSession(['main.js'], async ({ send }) => {
    await send('bp', 'main.js', '4');
    await send('continue', '--expect', 'pauses before arr.push with x = 3');
    for (const expr of ['x = 5', 'arr.push(9)', 'globalThis.leak = 1']) {
      const r = await send('eval', expr);
      assert.equal(r.sideEffectBlocked, true, expr);
    }
    assert.equal((await send('eval', 'x * 2')).value, 6);
    assert.equal((await send('eval', 'arr.length')).value, 0);
    await send('continue', '--expect', 'prints 3 1 and exits 0');
    assert.equal((await send('report')).stdout.text, '3 1\n');
  }, { fixtures });
});

test('movement requires --expect and the prediction is logged before the target moves', async () => {
  const fixtures = { 'main.js': 'let n = 1;\nn = n + 1;\nn = n * 10;\nconsole.log(n);\n' };
  await withSession(['main.js'], async ({ send, sessionDir }) => {
    const refused = await send('next');
    assert.equal(refused.ok, false);
    assert.match(refused.error, /--expect/);
    assert.equal((await send('where')).line, 1, 'refused move must not advance');
    assert.equal(transcript(sessionDir).filter((r) => r.kind === 'predict').length, 0);

    const moved = await send('next', '--expect', 'line 2, n is 1');
    assert.equal(moved.after.line, 2);
    const records = transcript(sessionDir);
    const predict = records.findIndex((r) => r.kind === 'predict' && r.move === 1);
    const actual = records.findIndex((r) => r.kind === 'actual' && r.move === 1);
    assert.ok(predict >= 0 && predict < actual);
    assert.equal(records[predict].expect, 'line 2, n is 1');
    assert.equal(records[predict].before.line, 1);
    assert.equal(records[actual].after.line, 2);
  }, { fixtures });
});

const TIMER_FIXTURE = 'setTimeout(() => {\n  const late = "late";\n  console.log(late);\n}, 600);\n';

test('commands are serialized: a concurrent command is rejected while one is in flight', async () => {
  await withSession(['main.js'], async ({ send, sessionDir }) => {
    await send('bp', 'main.js', '2');
    const inflight = send('continue', '--expect', 'timer fires, pauses at const late', '--timeout-ms', '5000');
    await waitForRecord(sessionDir, (r) => r.kind === 'predict');
    const busy = await send('where');
    assert.deepEqual(busy, { ok: false, error: 'busy', busyWith: 'continue' });
    const done = await inflight;
    assert.equal(done.outcome, 'paused');
    assert.equal(done.after.line, 2);
    // Each reply reflects the state produced by that command, not the previous one.
    for (const line of [3, 4]) {
      const r = await send('next', '--expect', `line ${line}`);
      assert.equal(r.after.line, line);
      assert.equal((await send('where')).line, line);
    }
  }, { fixtures: { 'main.js': TIMER_FIXTURE } });
});

test('timeout reports a running target truthfully, then wait recovers the pause', async () => {
  await withSession(['main.js'], async ({ send }) => {
    await send('bp', 'main.js', '2');
    const r = await send('continue', '--expect', 'timer pauses at line 2', '--timeout-ms', '50');
    assert.equal(r.outcome, 'timeout');
    assert.equal(r.after.state, 'running');
    assert.equal((await send('eval', '1')).ok, false);
    const w = await send('wait', '--timeout-ms', '5000');
    assert.equal(w.outcome, 'paused');
    assert.equal(w.line, 2);
    const end = await send('continue', '--expect', 'prints late, exits 0');
    assert.deepEqual(end.after, { state: 'exited', code: 0, signal: null });
  }, { fixtures: { 'main.js': TIMER_FIXTURE } });
});

test('nonzero exit code, separated stdout/stderr without inspector banners, and cleanup', async () => {
  const fixtures = { 'main.js': 'console.log("out-line");\nconsole.error("err-line");\nprocess.exitCode = 3;\n' };
  await withSession(['main.js'], async ({ send, sessionDir, serve }) => {
    const end = await send('continue', '--expect', 'prints out-line/err-line, exits 3');
    assert.deepEqual(end.after, { state: 'exited', code: 3, signal: null });
    const report = await send('report');
    assert.equal(report.stdout.text, 'out-line\n');
    assert.equal(report.stderr.text, 'err-line\n');
    const stopped = await send('stop');
    assert.equal(stopped.killed, false);
    assert.equal((await serve.exited).code, 0);
    assert.equal(alive(serve.proc.pid), false);
    assert.equal(fs.existsSync(path.join(sessionDir, 'ctl.sock')), false);
    assert.equal(JSON.parse(fs.readFileSync(path.join(sessionDir, 'session.json'), 'utf8')).reason, 'stop');
    const after = await send('where');
    assert.equal(after.error, 'session ended');
  }, { fixtures });
});

test('stop while paused kills the target before any remaining code runs', async () => {
  const fixtures = { 'main.js': `const fs = require('node:fs');\nconst out = process.argv[2];\nfs.writeFileSync(out, 'written');\n` };
  await withSession(['main.js', '{root}/OUT'], async ({ root, send, serve }) => {
    const out = path.join(root, 'OUT');
    await send('bp', 'main.js', '3');
    const paused = await send('continue', '--expect', 'pauses before writeFileSync');
    assert.equal(paused.after.line, 3);
    const pid = transcript(path.join(root, 's')).find((r) => r.kind === 'spawn').pid;
    const stopped = await send('stop');
    assert.equal(stopped.killed, true);
    assert.equal(stopped.signal, 'SIGKILL');
    assert.equal((await serve.exited).code, 0);
    assert.equal(alive(pid), false);
    assert.equal(fs.existsSync(out), false, 'remaining write must not run');
  }, { fixtures });
});

test('target that exits early during startup still yields a session with its real exit', async () => {
  await withSession(['missing.js'], async ({ send }) => {
    const where = await send('where');
    assert.equal(where.state, 'exited');
    assert.equal(where.code, 1);
    assert.match((await send('report')).stderr.text, /Cannot find module/);
  });
});

test('startup failure ends the session and reports it to clients', async () => {
  await withSession(['--no-such-node-flag', 'x.js'], async ({ send, serve, sessionDir }) => {
    const r = await send('where');
    assert.equal(r.ok, false);
    assert.equal(r.error, 'session ended');
    assert.equal(r.session.reason, 'startup-failed');
    assert.equal((await serve.exited).code, 1);
    assert.equal(fs.existsSync(path.join(sessionDir, 'ctl.sock')), false);
  });
});

test('a session dir in use or with unknown files is never taken over', async () => {
  await withSession(['main.js'], async ({ root, send, sessionDir }) => {
    assert.equal((await send('where')).state, 'paused');
    const second = startServe(sessionDir, [path.join(root, 'main.js')]);
    const r = await second.exited;
    assert.notEqual(r.code, 0);
    assert.match(r.stderr, /not empty/);
    assert.equal((await send('where')).state, 'paused', 'first session unaffected');

    const foreign = path.join(root, 'foreign');
    write(foreign, 'keep.txt', 'mine');
    const third = await startServe(foreign, [path.join(root, 'main.js')]).exited;
    assert.notEqual(third.code, 0);
    assert.deepEqual(fs.readdirSync(foreign), ['keep.txt']);
  }, { fixtures: { 'main.js': 'console.log(1);\n' } });
});

test('SIGTERM to serve kills the paused target and removes the socket', async () => {
  const fixtures = { 'main.js': `require('node:fs').writeFileSync(process.argv[2], 'x');\n` };
  await withSession(['main.js', '{root}/OUT'], async ({ root, send, serve, sessionDir }) => {
    assert.equal((await send('where')).state, 'paused');
    const pid = transcript(sessionDir).find((r) => r.kind === 'spawn').pid;
    serve.proc.kill('SIGTERM');
    assert.equal((await serve.exited).code, 143);
    assert.equal(alive(pid), false);
    assert.equal(fs.existsSync(path.join(root, 'OUT')), false);
    assert.equal(fs.existsSync(path.join(sessionDir, 'ctl.sock')), false);
    assert.equal(JSON.parse(fs.readFileSync(path.join(sessionDir, 'session.json'), 'utf8')).reason, 'signal:SIGTERM');
  }, { fixtures });
});

test('CLI smoke: --help and a client command', async () => {
  assert.match(spawnSync(process.execPath, [DRIVER, '--help'], { encoding: 'utf8' }).stdout, /serve <dir>/);
  await withSession(['main.js'], async ({ sessionDir }) => {
    const r = spawnSync(process.execPath, [DRIVER, sessionDir, 'where'], { encoding: 'utf8' });
    assert.equal(r.status, 0, r.stderr);
    assert.equal(JSON.parse(r.stdout).reason, 'Break on start');
    const bad = spawnSync(process.execPath, [DRIVER, sessionDir, 'next'], { encoding: 'utf8' });
    assert.equal(bad.status, 1);
    const stop = spawnSync(process.execPath, [DRIVER, sessionDir, 'stop'], { encoding: 'utf8' });
    assert.equal(JSON.parse(stop.stdout).stopped, true);
  }, { fixtures: { 'main.js': 'console.log(1);\n' } });
});


test('target exit and stop are confirmed even when a descendant holds stderr open', async () => {
  const fixture = `const fs = require('node:fs');
const { spawn } = require('node:child_process');
const worker = spawn(process.execPath, ['-e', 'setTimeout(() => {}, 30000)'], { detached: true, stdio: ['ignore', 'ignore', 'inherit'] });
fs.writeFileSync(process.argv[2], String(worker.pid));
worker.unref();
debugger;
process.exitCode = 7;
`;
  for (const abort of [false, true]) {
    await withSession(['main.js', '{root}/worker.pid'], async ({ root, send, sessionDir, serve }) => {
      const pidFile = path.join(root, 'worker.pid');
      try {
        const paused = await send('continue', '--expect', 'worker starts, then pauses at debugger');
        assert.equal(paused.outcome, 'paused');
        assert.equal(paused.after.line, 6);
        const targetPid = transcript(sessionDir).find((r) => r.kind === 'spawn').pid;
        if (!abort) {
          const end = await send('continue', '--expect', 'direct target exits 7 while descendant retains stderr');
          assert.equal(end.outcome, 'exited');
          assert.deepEqual(end.after, { state: 'exited', code: 7, signal: null });
        }
        const stopped = await send('stop');
        assert.equal(stopped.ok, true);
        assert.equal(stopped.state, 'exited');
        assert.equal(stopped.stopped, true);
        assert.equal(stopped.killed, abort);
        assert.equal(stopped.code, abort ? null : 7);
        assert.equal(stopped.signal, abort ? 'SIGKILL' : null);
        assert.equal(alive(targetPid), false);
        assert.ok(transcript(sessionDir).some((r) => r.kind === 'stderr-held-open'));
        assert.equal((await serve.exited).code, 0);
      } finally {
        if (fs.existsSync(pidFile)) {
          const pid = Number(fs.readFileSync(pidFile, 'utf8'));
          try { process.kill(pid, 'SIGKILL'); } catch (err) { if (err.code !== 'ESRCH') throw err; }
        }
      }
    }, { fixtures: { 'main.js': fixture } });
  }
});
