import { execFile } from 'node:child_process';
import { setTimeout as delay } from 'node:timers/promises';
import { SleepPolicy, type Thread } from './policy.mts';
import { subscribe } from './source.mts';
import { Lease, type Run } from './lease.mts';

const flags = new Set(process.argv.slice(2));
if ([...flags].some(flag => !['--once', '--watch', '--lease'].includes(flag)) || (flags.has('--once') && flags.has('--watch')) || (flags.has('--lease') && !flags.has('--watch'))) {
  process.stderr.write('Usage: node main.mts [--once | --watch [--lease]]\n');
  process.exit(2);
}
const once = !flags.has('--watch');
const live = flags.has('--lease');
const stop = new AbortController();
process.once('SIGINT', () => stop.abort());
process.once('SIGTERM', () => stop.abort());
const policy = new SleepPolicy();
const lease = new Lease();
const state: { rows: readonly Thread[] | null } = { rows: null };
let previous = '';
let lastLeaseUpdate = 0;
let lastHold: boolean | null = null;
const log = (value: object) => process.stderr.write(`${JSON.stringify({ at: new Date().toISOString(), ...value })}\n`);
const run: Run = args => new Promise((resolve, reject) => {
  execFile(process.env.KEEPRESSO_CLI ?? 'keepresso', args, { timeout: 10_000 }, (error, stdout) => {
    if (error && (!('code' in error) || typeof error.code !== 'number')) { reject(new Error('Keepresso CLI could not run')); return; }
    const code = error && 'code' in error && typeof error.code === 'number' ? error.code : 0;
    try {
      const result: unknown = JSON.parse(stdout);
      resolve({ code, active: typeof result === 'object' && result !== null && 'isActive' in result && result.isActive === true });
    } catch { reject(new Error('Invalid Keepresso CLI response')); }
  });
});

async function observe() {
  while (!stop.signal.aborted) {
    try {
      await subscribe(threads => {
        state.rows = threads;
        if (once) {
          log({ mode: 'dry-run', threads: threads.length, ...policy.evaluate(threads, Date.now()) });
          stop.abort();
        }
      }, stop.signal);
    } catch {
      log({ event: 'source-unavailable', action: 'stop-renewing-until-reconnected' });
      if (once) { process.exitCode = 1; stop.abort(); }
    } finally { state.rows = null; }
    if (!stop.signal.aborted) await delay(5000, undefined, { signal: stop.signal }).catch(() => {});
  }
}

const observer = observe();
try {
  if (!once) while (!stop.signal.aborted) {
    const rows = state.rows;
    if (rows !== null) {
      const decision = policy.evaluate(rows, Date.now());
      try {
        let status = live ? 'unchanged' : 'dry-run';
        if (live && (lastHold !== decision.hold || Date.now() - lastLeaseUpdate >= 30_000)) {
          status = await lease.update(decision.hold, Date.now(), run);
          lastLeaseUpdate = Date.now();
          lastHold = decision.hold;
        } else if (live) {
          await delay(1000, undefined, { signal: stop.signal }).catch(() => {});
          continue;
        }
        const summary = JSON.stringify({ ...decision, status });
        if (summary !== previous) { log({ ...decision, status, threads: rows.length }); previous = summary; }
      } catch { log({ event: 'lease-error', action: 'stop-renewing' }); stop.abort(); process.exitCode = 1; }
    }
    await delay(1000, undefined, { signal: stop.signal }).catch(() => {});
  }
} finally {
  await observer;
  // Failure, disconnect and termination all leave the bounded lease to expire.
}
