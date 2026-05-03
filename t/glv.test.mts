// Verify home/scripts/glv enforces its dependencies.
//
// The interactive fzf path is exercised via tui-acceptance-checks; here
// we cover only the dependency-check branches that are reachable
// without a TTY.
//
// Run from the repo root:
//   node --test t/*.test.mts

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const SCRIPT = `${REPO}/home/scripts/glv`;

function emptyDir(): string {
  return mkdtempSync(join(tmpdir(), 'glv-'));
}

function fakeBin(dir: string, name: string, body: string): void {
  const p = join(dir, name);
  writeFileSync(p, `#!/usr/bin/env bash\n${body}\n`, { mode: 0o755 });
}

test('exits 2 when fzf is missing', () => {
  const dir = emptyDir();
  // Absolute /bin/bash so the spawn itself does not need PATH; the
  // restricted PATH only affects glv's own command lookups.
  const r = spawnSync('/bin/bash', [SCRIPT], {
    encoding: 'utf8',
    env: { PATH: dir },
  });
  assert.equal(r.status, 2, `stdout=${r.stdout} stderr=${r.stderr}`);
  assert.match(r.stderr, /fzf not found/);
});

test('exits 2 when delta is missing', () => {
  const dir = emptyDir();
  fakeBin(dir, 'fzf', 'cat >/dev/null');
  const r = spawnSync('/bin/bash', [SCRIPT], {
    encoding: 'utf8',
    env: { PATH: dir },
  });
  assert.equal(r.status, 2, `stdout=${r.stdout} stderr=${r.stderr}`);
  assert.match(r.stderr, /delta not found/);
});

test('exits 2 when gh is missing', () => {
  const dir = emptyDir();
  fakeBin(dir, 'fzf', 'cat >/dev/null');
  fakeBin(dir, 'delta', 'cat >/dev/null');
  const r = spawnSync('/bin/bash', [SCRIPT], {
    encoding: 'utf8',
    env: { PATH: dir },
  });
  assert.equal(r.status, 2, `stdout=${r.stdout} stderr=${r.stderr}`);
  assert.match(r.stderr, /gh not found/);
});
