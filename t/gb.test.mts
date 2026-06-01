// Verify home/scripts/gb enforces its dependencies and arguments.
//
// The interactive fzf path (vim-like nav + the `,` parent walk) is
// exercised via tui-acceptance-checks; here we cover only the
// branches reachable without a TTY.
//
// Run from the repo root:
//   node --test t/*.test.mts

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const SCRIPT = `${REPO}/home/scripts/gb`;

function emptyDir(): string {
  return mkdtempSync(join(tmpdir(), 'gb-'));
}

function fakeBin(dir: string, name: string, body: string): void {
  const p = join(dir, name);
  writeFileSync(p, `#!/usr/bin/env bash\n${body}\n`, { mode: 0o755 });
}

test('no args falls into the tmux picker without launching real fzf', () => {
  // With no args, gb pipes `git ls-files` into fzf. Use a fake fzf so
  // the unit test does not open an interactive tmux popup when the test
  // runner itself is inside tmux.
  const dir = emptyDir();
  const fzfArgs = join(dir, 'fzf-args.log');
  const fzfInput = join(dir, 'fzf-input.log');
  fakeBin(dir, 'fzf', 'printf "%s\\n" "$@" > "$GB_TEST_FZF_ARGS"\ncat > "$GB_TEST_FZF_INPUT"\nexit 130');
  fakeBin(dir, 'delta', 'cat >/dev/null');
  fakeBin(dir, 'gh', 'exit 0');

  const r = spawnSync('/bin/bash', [SCRIPT], {
    encoding: 'utf8',
    env: {
      ...process.env,
      PATH: `${dir}:${process.env.PATH ?? ''}`,
      TMUX: 'test-tmux',
      GB_TEST_FZF_ARGS: fzfArgs,
      GB_TEST_FZF_INPUT: fzfInput,
    },
  });

  assert.equal(r.status, 130, `stdout=${r.stdout} stderr=${r.stderr}`);
  assert.doesNotMatch(r.stderr, /Usage: gb/);
  assert.equal(readFileSync(fzfArgs, 'utf8'), '--tmux\ncenter,80%\n');
  assert.match(readFileSync(fzfInput, 'utf8'), /(^|\n)t\/gb\.test\.mts\n/);
});

test('exits 2 with usage when too many args', () => {
  const r = spawnSync('/bin/bash', [SCRIPT, 'a', 'b', 'c'], {
    encoding: 'utf8',
  });
  assert.equal(r.status, 2);
  assert.match(r.stderr, /Usage: gb/);
});

test('--help exits 0 with usage on stdout', () => {
  const r = spawnSync('/bin/bash', [SCRIPT, '--help'], { encoding: 'utf8' });
  assert.equal(r.status, 0);
  assert.match(r.stdout, /Usage: gb/);
});

test('exits 2 when fzf is missing', () => {
  const dir = emptyDir();
  const r = spawnSync('/bin/bash', [SCRIPT, 'somefile'], {
    encoding: 'utf8',
    env: { PATH: dir },
  });
  assert.equal(r.status, 2, `stdout=${r.stdout} stderr=${r.stderr}`);
  assert.match(r.stderr, /fzf not found/);
});

test('exits 2 when delta is missing', () => {
  const dir = emptyDir();
  fakeBin(dir, 'fzf', 'cat >/dev/null');
  const r = spawnSync('/bin/bash', [SCRIPT, 'somefile'], {
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
  const r = spawnSync('/bin/bash', [SCRIPT, 'somefile'], {
    encoding: 'utf8',
    env: { PATH: dir },
  });
  assert.equal(r.status, 2, `stdout=${r.stdout} stderr=${r.stderr}`);
  assert.match(r.stderr, /gh not found/);
});
