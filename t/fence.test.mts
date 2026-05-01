// Verify packages/fence.bash injects worktree-aware allowWrite into the
// fence settings file and forwards every other argument unchanged. Uses a
// stub `fence` binary (via FENCE_BIN env) that records its own argv and
// the contents of the file referenced by `--settings`, so the real fence
// sandbox is never invoked.
//
// Run from the repo root:
//   node --test t/*.test.mts

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, chmodSync, realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const SCRIPT = `${REPO}/packages/fence.bash`;

type StubResult = {
  status: number;
  stderr: string;
  stdout: string;
  config: any | null;
  argv: string[] | null;
};

// Build a stub fence in `dir/bin/fence` that writes a JSON dump of its
// full argv plus the contents of the file passed via --settings to
// `dir/dump.json`.
function makeStub(dir: string): string {
  const bin = join(dir, 'bin');
  mkdirSync(bin, { recursive: true });
  const dump = join(dir, 'dump.json');
  const stub = `#!/usr/bin/env bash
set -euo pipefail
settings=""
argv=("$@")
i=0
while (( i < $# )); do
  if [[ "\${argv[$i]}" == "--settings" ]]; then
    settings="\${argv[$((i+1))]}"
    break
  fi
  i=$((i+1))
done
cfg=$(cat "$settings")
${'jq -nc'} --arg cfg "$cfg" --argjson argv "$(printf '%s\\n' "\${argv[@]+"\${argv[@]}"}" | jq -R . | jq -s .)" \\
  '{config: ($cfg|fromjson), argv: $argv}' > "${dump}"
`;
  const path = join(bin, 'fence');
  writeFileSync(path, stub);
  chmodSync(path, 0o755);
  return path;
}

function readDump(stubDir: string): { config: any; argv: string[] } | null {
  const p = join(stubDir, 'dump.json');
  try {
    return JSON.parse(readFileSync(p, 'utf8'));
  } catch {
    return null;
  }
}

function runFence(opts: {
  cwd: string;
  args: string[];
  stub: string;
  env?: Record<string, string>;
}): StubResult {
  const env: Record<string, string> = {
    ...process.env,
    FENCE_BIN: opts.stub,
    ...(opts.env ?? {}),
  } as any;
  const r = spawnSync('bash', [SCRIPT, ...opts.args], {
    cwd: opts.cwd,
    env,
    encoding: 'utf8',
  });
  const dump = readDump(dirname(dirname(opts.stub)));
  return {
    status: r.status ?? -1,
    stderr: r.stderr,
    stdout: r.stdout,
    config: dump?.config ?? null,
    argv: dump?.argv ?? null,
  };
}

function gitInit(dir: string) {
  const env = { ...process.env, GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_SYSTEM: '/dev/null' };
  execFileSync('git', ['init', '-q', '-b', 'main', dir], { env });
  execFileSync('git', ['-C', dir, 'config', 'user.email', 't@example.com'], { env });
  execFileSync('git', ['-C', dir, 'config', 'user.name', 'T'], { env });
  execFileSync('git', ['-C', dir, 'commit', '-q', '--allow-empty', '-m', 'init'], { env });
}

function makeWorkspace() {
  const root = mkdtempSync(join(tmpdir(), 'fence-test-'));
  return realpathSync(root);
}

test('plain checkout: synthesizes settings with code template + .git path', () => {
  const ws = makeWorkspace();
  const repo = join(ws, 'repo');
  mkdirSync(repo);
  gitInit(repo);
  const stub = makeStub(ws);

  const r = runFence({ cwd: repo, args: ['--', 'echo', 'hi'], stub });
  assert.equal(r.status, 0, `stderr=${r.stderr}`);
  assert.equal(r.config.extends, 'code');
  const writes: string[] = r.config.filesystem.allowWrite;
  assert.ok(writes.includes('.'), JSON.stringify(writes));
  assert.ok(writes.some((w) => w.endsWith('/.git')), JSON.stringify(writes));
  // git-dir == common-dir in plain checkout, so dedup leaves [".", ".../.git"]
  assert.equal(writes.length, 2, JSON.stringify(writes));
  // `--` and the inner command pass through verbatim
  assert.deepEqual(r.argv?.slice(-3), ['--', 'echo', 'hi']);
});

test('worktree: allowWrite includes both per-worktree and common .git', () => {
  const ws = makeWorkspace();
  const repo = join(ws, 'repo');
  mkdirSync(repo);
  gitInit(repo);
  const wtPath = join(ws, 'wt-feature');
  execFileSync('git', ['-C', repo, 'worktree', 'add', '-q', wtPath, '-b', 'feature'], {
    env: { ...process.env, GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_SYSTEM: '/dev/null' },
  });
  const stub = makeStub(ws);

  const r = runFence({ cwd: wtPath, args: ['--', 'true'], stub });
  assert.equal(r.status, 0, `stderr=${r.stderr}`);
  const writes: string[] = r.config.filesystem.allowWrite;
  assert.ok(writes.includes('.'), JSON.stringify(writes));
  assert.ok(
    writes.some((w) => w.endsWith('/.git/worktrees/wt-feature')),
    JSON.stringify(writes),
  );
  assert.ok(
    writes.some((w) => w.endsWith('/.git') && !w.endsWith('/worktrees/wt-feature')),
    JSON.stringify(writes),
  );
});

test('--template forwards and seeds extends in synthesized settings', () => {
  const ws = makeWorkspace();
  const repo = join(ws, 'repo');
  mkdirSync(repo);
  gitInit(repo);
  const stub = makeStub(ws);

  const r = runFence({
    cwd: repo,
    args: ['--template', 'code-strict', '--', 'claude'],
    stub,
  });
  assert.equal(r.status, 0, `stderr=${r.stderr}`);
  assert.equal(r.config.extends, 'code-strict');
  // Forwarded verbatim — fence still sees --template even though we also
  // baked it into the settings file.
  assert.ok(r.argv?.includes('--template'));
  assert.equal(r.argv?.[r.argv.indexOf('--template') + 1], 'code-strict');
  assert.deepEqual(r.argv?.slice(-2), ['--', 'claude']);
});

test('existing --settings: augments allowWrite, preserves other fields', () => {
  const ws = makeWorkspace();
  const repo = join(ws, 'repo');
  mkdirSync(repo);
  gitInit(repo);
  const policy = join(ws, 'policy.json');
  writeFileSync(
    policy,
    JSON.stringify({
      extends: 'strict',
      filesystem: { allowWrite: ['/tmp/seed'] },
      network: { allowHosts: ['example.com'] },
    }),
  );
  const stub = makeStub(ws);

  const r = runFence({ cwd: repo, args: ['--settings', policy, '--', 'true'], stub });
  assert.equal(r.status, 0, `stderr=${r.stderr}`);
  // Existing fields untouched
  assert.equal(r.config.extends, 'strict');
  assert.deepEqual(r.config.network, { allowHosts: ['example.com'] });
  // allowWrite gets seeded entries plus worktree paths, deduped
  const writes: string[] = r.config.filesystem.allowWrite;
  assert.ok(writes.includes('/tmp/seed'), JSON.stringify(writes));
  assert.ok(writes.includes('.'), JSON.stringify(writes));
  assert.ok(writes.some((w) => w.endsWith('/.git')), JSON.stringify(writes));
  // The wrapper substitutes its own tmp path, so the value passed to fence
  // should NOT be the original policy path.
  const settingsArg = r.argv?.[r.argv.indexOf('--settings') + 1];
  assert.notEqual(settingsArg, policy);
});

test('sence-style argv: monitor flags pass through, --settings is rewritten', () => {
  const ws = makeWorkspace();
  const repo = join(ws, 'repo');
  mkdirSync(repo);
  gitInit(repo);
  const policy = join(ws, 'sence-policy.json');
  writeFileSync(policy, JSON.stringify({ extends: 'code', filesystem: { allowWrite: [] } }));
  const stub = makeStub(ws);

  const r = runFence({
    cwd: repo,
    args: [
      '-m',
      '--fence-log-file',
      '/dev/fd/3',
      '--settings',
      policy,
      '--template',
      'code',
      '--',
      'claude',
      '--permission-mode',
      'auto',
    ],
    stub,
  });
  assert.equal(r.status, 0, `stderr=${r.stderr}`);
  // Every monitor / template flag survives, in order, with the inner cmd intact.
  assert.deepEqual(r.argv?.slice(-9), [
    '-m',
    '--fence-log-file',
    '/dev/fd/3',
    '--template',
    'code',
    '--',
    'claude',
    '--permission-mode',
    'auto',
  ]);
  // --settings is the wrapper's tmp file, not the original sence policy.
  const settingsArg = r.argv?.[r.argv.indexOf('--settings') + 1];
  assert.notEqual(settingsArg, policy);
  // Worktree paths landed in the rewritten settings.
  const writes: string[] = r.config.filesystem.allowWrite;
  assert.ok(writes.some((w) => w.endsWith('/.git')), JSON.stringify(writes));
});

test('non-git directory: only `.` is seeded, no git paths injected', () => {
  const ws = makeWorkspace();
  const stub = makeStub(ws);
  const nongit = join(ws, 'plain');
  mkdirSync(nongit);

  const r = runFence({ cwd: nongit, args: ['--', 'true'], stub });
  assert.equal(r.status, 0, `stderr=${r.stderr}`);
  const writes: string[] = r.config.filesystem.allowWrite;
  assert.deepEqual(writes, ['.'], JSON.stringify(writes));
});

test('missing value for --settings fails with helpful message', () => {
  const ws = makeWorkspace();
  const repo = join(ws, 'repo');
  mkdirSync(repo);
  gitInit(repo);
  const stub = makeStub(ws);

  const r = runFence({ cwd: repo, args: ['--settings'], stub });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /missing value for --settings/);
});

test('unreadable --settings path errors instead of silently dropping it', () => {
  const ws = makeWorkspace();
  const repo = join(ws, 'repo');
  mkdirSync(repo);
  gitInit(repo);
  const stub = makeStub(ws);

  const r = runFence({
    cwd: repo,
    args: ['--settings', join(ws, 'does-not-exist.json'), '--', 'true'],
    stub,
  });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /settings file not readable/);
});
