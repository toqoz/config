import { strict as assert } from 'node:assert';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const script = fileURLToPath(new URL('../home/deepseek-harness/ds-bot-apply.sh', import.meta.url));
const applyPath = '.git/wt/ops/.agents/skills/ds-bot-personal-fork/scripts/apply.sh';

// A stub apply.sh keeps these cases about the helper's own decisions: whether it
// runs at all, whether a failure keeps the marker, and when it restarts the app.
function layout(t, applyBody: string) {
  const root = mkdtempSync(join(tmpdir(), 'ds-bot-apply-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const checkout = join(root, 'checkout');
  mkdirSync(join(checkout, '.git/wt/ops/.agents/skills/ds-bot-personal-fork/scripts'), { recursive: true });
  writeFileSync(join(checkout, applyPath), `#!/usr/bin/env bash\n${applyBody}\n`);
  const marker = join(checkout, '.agents/state/apply-pending');
  mkdirSync(join(checkout, '.agents/state'), { recursive: true });
  const restarted = join(root, 'restarted');
  return { checkout, marker, restarted };
}

function run(checkout: string, marker: string, restart: string) {
  return spawnSync('bash', [script], {
    encoding: 'utf8',
    env: { ...process.env, DS_BOT_APPLY_CHECKOUT: checkout, DS_BOT_APPLY_MARKER: marker, DS_BOT_APPLY_RESTART: restart },
  });
}

test('nothing happens without the marker the import leaves', (t) => {
  const { checkout, marker, restarted } = layout(t, 'echo applied');
  const result = run(checkout, marker, `touch ${restarted}`);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, '');
  assert.equal(existsSync(restarted), false);
});

test('a successful apply removes the marker without restarting', (t) => {
  const { checkout, marker, restarted } = layout(t, 'echo "applied toqoz/main (ds-bot 0.3.2)"');
  writeFileSync(marker, '');
  const result = run(checkout, marker, `touch ${restarted}`);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /applied toqoz\/main/);
  assert.equal(existsSync(marker), false);
  assert.equal(existsSync(restarted), false);
});

test('a release change restarts the app', (t) => {
  const { checkout, marker, restarted } = layout(t, 'echo "apply.sh: upgraded the profile to ds-bot 0.3.2"');
  writeFileSync(marker, '');
  const result = run(checkout, marker, `touch ${restarted}`);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(existsSync(restarted), true);
  assert.equal(existsSync(marker), false);
});

test('a failed apply keeps the marker for the next interval', (t) => {
  const { checkout, marker } = layout(t, 'echo "apply.sh: no installed ds-bot" >&2; exit 1');
  writeFileSync(marker, '');
  const result = run(checkout, marker, 'exit 0');
  assert.equal(result.status, 1);
  assert.match(result.stdout, /no installed ds-bot/);
  assert.match(result.stdout, /keeping the marker/);
  assert.equal(existsSync(marker), true);
});

test('a failed restart keeps the marker so the next run retries', (t) => {
  const { checkout, marker } = layout(t, 'echo "apply.sh: upgraded the profile to ds-bot 0.3.2"');
  writeFileSync(marker, '');
  const result = run(checkout, marker, 'false');
  assert.equal(result.status, 1);
  assert.match(result.stdout, /restart failed/);
  assert.equal(existsSync(marker), true);
});
