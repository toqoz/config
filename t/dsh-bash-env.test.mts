// The harness runs every shell command as a fresh, non-login `bash -c`, so
// there is no shell hook to lean on (bash has no chpwd) and no pi-style command
// prefix in the bash tool's config. direnv is loaded through BASH_ENV instead.
//
// These tests pin the properties that make that safe:
// - the hook loads the project environment, follows `cd`, and leaves again;
// - it does not recurse when direnv evaluates `.envrc` with bash, which reads
//   BASH_ENV a second time (a naive version hangs);
// - it stays out of the way of ordinary commands, `set -euo pipefail`, and
//   shells that have no direnv;
// - the launcher exports the managed hook rather than accepting one from a
//   project file, which the harness refuses on purpose.
import { test, type TestContext } from 'node:test';
import { strict as assert } from 'node:assert';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const HOOK = join(REPO, 'home/deepseek-harness/bash-env.sh');

// A stand-in for direnv: it records each call, emulates the bash process
// direnv starts to evaluate `.envrc` (the recursion path), and emits the
// exports direnv would print for the current directory.
const FAKE_DIRENV = `#!${process.execPath}
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const args = process.argv.slice(2);
fs.appendFileSync(process.env.FAKE_CALLS, JSON.stringify({
  args,
  cwd: process.cwd(),
  logFormat: process.env.DIRENV_LOG_FORMAT ?? null,
}) + '\\n');

const depth = Number(process.env.FAKE_DEPTH || 0);
if (process.env.FAKE_RECURSE === '1' && depth < 3) {
  spawnSync('bash', ['-c', 'true'], {
    stdio: 'ignore',
    env: { ...process.env, FAKE_DEPTH: String(depth + 1) },
  });
}

if (fs.existsSync(path.join(process.cwd(), '.envrc'))) {
  process.stdout.write(
    "export DIRENV_DIR='-" + process.cwd() + "'\\n" +
    "export FAKE_PROJECT='" + path.basename(process.cwd()) + "'\\n",
  );
} else {
  process.stdout.write('unset FAKE_PROJECT DIRENV_DIR\\n');
}
`;

function makeWorkspace(t: TestContext) {
  const cache = join(REPO, '.agents/cache/dsh-bash-env-tests');
  mkdirSync(cache, { recursive: true });
  const root = mkdtempSync(join(cache, 'run-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const bin = join(root, 'bin');
  const calls = join(root, 'calls.jsonl');
  mkdirSync(bin);
  for (const project of ['proj-a', 'proj-b']) {
    mkdirSync(join(root, project));
    writeFileSync(join(root, project, '.envrc'), `export PROJECT=${project}\n`);
  }
  writeFileSync(join(bin, 'direnv'), FAKE_DIRENV);
  chmodSync(join(bin, 'direnv'), 0o755);

  const env = (extra: NodeJS.ProcessEnv = {}): NodeJS.ProcessEnv => ({
    ...process.env,
    BASH_ENV: HOOK,
    PATH: `${bin}:${process.env.PATH}`,
    FAKE_CALLS: calls,
    FAKE_RECURSE: '1',
    ...extra,
  });
  const run = (cwd: string, command: string, extra: NodeJS.ProcessEnv = {}) =>
    spawnSync('/bin/bash', ['-c', command], { cwd, encoding: 'utf8', timeout: 20_000, env: env(extra) });
  const recorded = (): { args: string[]; cwd: string; logFormat: string | null }[] =>
    existsSync(calls)
      ? readFileSync(calls, 'utf8').trim().split('\n').filter(Boolean).map((line) => JSON.parse(line))
      : [];
  const reset = (): void => rmSync(calls, { force: true });
  return { root, bin, calls, env, run, recorded, reset };
}

test('loads the project environment in a fresh bash -c without recursing', (t) => {
  const w = makeWorkspace(t);
  const result = w.run(join(w.root, 'proj-a'), 'printf "%s\\n" "${FAKE_PROJECT:-unset}"');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), 'proj-a');
  // Exactly one call: the bash direnv started to evaluate `.envrc` must not
  // load the hook again, or the export recurses until it hangs.
  assert.equal(w.recorded().length, 1);
  assert.deepEqual(w.recorded()[0].args, ['export', 'bash']);
  // The loading line the harness would otherwise merge into every result.
  assert.equal(w.recorded()[0].logFormat, '');
});

test('follows cd and pushd inside one command', (t) => {
  const w = makeWorkspace(t);
  const result = w.run(join(w.root, 'proj-a'), 'cd ../proj-b && printf "%s\\n" "$FAKE_PROJECT"');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), 'proj-b');
  assert.equal(w.recorded().length, 2);

  w.reset();
  const pushed = w.run(join(w.root, 'proj-a'), 'pushd ../proj-b >/dev/null && printf "%s\\n" "$FAKE_PROJECT"');
  assert.equal(pushed.status, 0, pushed.stderr);
  assert.equal(pushed.stdout.trim(), 'proj-b');
});

test('leaves the project when a command moves outside any .envrc', (t) => {
  const w = makeWorkspace(t);
  const result = w.run(join(w.root, 'proj-a'), 'cd .. && printf "%s\\n" "${FAKE_PROJECT:-unset}"');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), 'unset');
  assert.equal(w.recorded().length, 2);
});

test('skips the export in a nested bash that did not change directory', (t) => {
  const w = makeWorkspace(t);
  const result = w.run(join(w.root, 'proj-a'), 'bash -c \'printf "%s\\n" "$FAKE_PROJECT"\'');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), 'proj-a');
  assert.equal(w.recorded().length, 1);
});

test('keeps set -euo pipefail commands working and still follows cd', (t) => {
  const w = makeWorkspace(t);
  const result = w.run(
    join(w.root, 'proj-a'),
    'set -euo pipefail; cd ../proj-b; printf "%s\\n" "$FAKE_PROJECT"',
  );
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), 'proj-b');
});

test('reports a failing cd as a failure', (t) => {
  const w = makeWorkspace(t);
  const result = w.run(join(w.root, 'proj-a'), 'cd /nonexistent && echo "should not run"');
  assert.notEqual(result.status, 0);
  assert.doesNotMatch(result.stdout, /should not run/);
});

test('restores an absent DIRENV_LOG_FORMAT after the export', (t) => {
  const w = makeWorkspace(t);
  const result = w.run(join(w.root, 'proj-a'), 'printf "%s\\n" "${DIRENV_LOG_FORMAT-unset}"');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), 'unset');
});

test('leaves shells alone when direnv is not installed', (t) => {
  const w = makeWorkspace(t);
  const result = spawnSync('/bin/bash', ['-c', 'echo ok'], {
    cwd: join(w.root, 'proj-a'),
    encoding: 'utf8',
    timeout: 20_000,
    // Only the hook file, no fake direnv on PATH.
    env: { ...process.env, BASH_ENV: HOOK, PATH: '/usr/bin:/bin' },
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), 'ok');
  assert.equal(w.recorded().length, 0);
});

test('the launcher exports the managed hook and nothing from the project', (t) => {
  const w = makeWorkspace(t);
  const data = join(w.root, 'data');
  mkdirSync(join(data, 'ready', 'apps', 'cli', 'lib'), { recursive: true });
  writeFileSync(join(data, 'ready', 'apps', 'cli', 'lib', 'bin.js'), '');
  const node = join(w.root, 'node');
  const result = join(w.root, 'launch.json');
  writeFileSync(node, `#!${process.execPath}
const fs = require('node:fs');
fs.writeFileSync(process.env.LAUNCH_RESULT, JSON.stringify({
  // A shebang script shifts argv by one; the launcher's own argv starts here.
  args: process.argv.slice(3),
  bashEnv: process.env.BASH_ENV,
  dshHome: process.env.DSH_HOME,
}));
`);
  chmodSync(node, 0o755);

  let text = readFileSync(join(REPO, 'home/deepseek-harness/dsh.sh'), 'utf8');
  for (const [key, value] of Object.entries({ node, dataDir: data, bashEnv: HOOK })) {
    text = text.replaceAll(`@${key}@`, value);
  }
  assert.doesNotMatch(text, /@[a-zA-Z]+@/);
  const script = join(w.root, 'dsh');
  writeFileSync(script, text);
  chmodSync(script, 0o755);

  const launched = spawnSync('/bin/bash', [script, 'web'], {
    cwd: w.root,
    encoding: 'utf8',
    timeout: 20_000,
    env: {
      ...process.env,
      DSH_HOME: '',
      DEEPSEEK_HARNESS_HOME: data,
      DEEPSEEK_HARNESS_NODE: node,
      LAUNCH_RESULT: result,
    },
  });
  assert.equal(launched.status, 0, launched.stderr);
  const launcher = JSON.parse(readFileSync(result, 'utf8'));
  assert.equal(launcher.bashEnv, HOOK);
  assert.deepEqual(launcher.args, ['web']);
  assert.equal(launcher.dshHome, join(data, 'state'));

  // The harness refuses BASH_ENV from a discovered `.env`; the launcher is the
  // only place it may come from, so it must be wired in the module, not passed
  // through a file a cloned project could write.
  const module = readFileSync(join(REPO, 'home/deepseek-harness/default.nix'), 'utf8');
  assert.match(module, /bashEnv = pkgs\.writeText "dsh-bash-env\.sh" \(builtins\.readFile \.\/bash-env\.sh\)/);
  assert.match(module, /inherit bashEnv/);
});
