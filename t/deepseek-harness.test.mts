// Verify home/deepseek-harness install.sh and dsh.sh with a real git origin
// and stub node/pnpm inside a tempdir. The tests render the Nix
// @placeholders@ with test-controlled values, so production pins never leak
// into behavior under test.
//
// Run from the repo root:
//   node --test t/*.test.mts

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { spawnSync } from 'node:child_process';
import {
  mkdtempSync,
  mkdirSync,
  writeFileSync,
  readFileSync,
  chmodSync,
  existsSync,
  lstatSync,
  readlinkSync,
  readdirSync,
  realpathSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, dirname, join, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const MODULE_NIX = `${REPO}/home/deepseek-harness/default.nix`;
const INSTALL_SH = `${REPO}/home/deepseek-harness/install.sh`;
const DSH_SH = `${REPO}/home/deepseek-harness/dsh.sh`;
const UPSTREAM_REV = '767265cf34e09b57dcace16035adc51a7308e6d6';

const VERSION = '0.0.0-test';

type RunResult = { status: number | null; stdout: string; stderr: string };

type World = {
  root: string;
  home: string;
  origin: string;
  revA: string;
  revB: string;
  log: string;
  bin: string;
  env: NodeJS.ProcessEnv;
};

function git(cwd: string, ...args: string[]): string {
  const r = spawnSync('git', args, { cwd, encoding: 'utf8' });
  assert.equal(r.status, 0, `git ${args.join(' ')}: ${r.stderr}`);
  return (r.stdout ?? '').trim();
}

function render(srcPath: string, vars: Record<string, string>, destDir: string): string {
  mkdirSync(destDir, { recursive: true });
  let text = readFileSync(srcPath, 'utf8');
  for (const [key, value] of Object.entries(vars)) {
    text = text.replaceAll(`@${key}@`, value);
  }
  assert.ok(!/@[a-z]+@/.test(text), `${srcPath} has unrendered placeholders`);
  const out = join(destDir, basename(srcPath));
  writeFileSync(out, text);
  chmodSync(out, 0o755);
  return out;
}

// Build a world: an origin repo whose default branch HEAD is revB (the pin
// revA is its parent), plus stub node/pnpm that log cwd and argv to STUB_LOG.
function makeWorld(): World {
  const root = mkdtempSync(join(tmpdir(), 'dsh-test-'));
  const home = join(root, 'data');
  const origin = join(root, 'origin');
  const bin = join(root, 'bin');
  const log = join(root, 'stub.log');
  mkdirSync(origin, { recursive: true });
  mkdirSync(bin);

  git(origin, 'init', '-b', 'main');
  git(origin, 'config', 'user.email', 'test@example.com');
  git(origin, 'config', 'user.name', 'test');
  mkdirSync(join(origin, 'apps/cli/src'), { recursive: true });
  writeFileSync(join(origin, 'apps/cli/src/bin.ts'), '// rev A\n');
  git(origin, 'add', '.');
  git(origin, 'commit', '-m', 'a');
  const revA = git(origin, 'rev-parse', 'HEAD');
  writeFileSync(join(origin, 'apps/cli/src/bin.ts'), '// rev B\n');
  git(origin, 'add', '.');
  git(origin, 'commit', '-m', 'b');
  const revB = git(origin, 'rev-parse', 'HEAD');

  writeFileSync(
    join(bin, 'node'),
    `#!/usr/bin/env bash
{
  echo "node cwd=$PWD"
  echo "node state=\${DSH_HOME:-}"
  echo "node argv=$*"
} >> "$STUB_LOG"
if [ "$1" = '-e' ]; then exec '${process.execPath}' "$@"; fi
case " $* " in
  *" --version "*) printf '%s\\n' "\${STUB_CLI_VERSION:-${VERSION}}" ;;
esac
exit "\${STUB_NODE_EXIT:-0}"
`,
  );
  writeFileSync(
    join(bin, 'pnpm'),
    `#!/usr/bin/env bash
echo "pnpm cwd=$PWD argv=$*" >> "$STUB_LOG"
case "$1" in
  install)
    if [ "\${STUB_PNPM_INSTALL_EXIT:-0}" -ne 0 ]; then exit "$STUB_PNPM_INSTALL_EXIT"; fi
    exit 0
    ;;
  run)
    mkdir -p apps/cli/lib
    cp apps/cli/src/bin.ts apps/cli/lib/bin.js
    exit "\${STUB_PNPM_RUN_EXIT:-0}"
    ;;
esac
exit 2
`,
  );
  chmodSync(join(bin, 'node'), 0o755);
  chmodSync(join(bin, 'pnpm'), 0o755);

  return {
    root,
    home,
    origin,
    revA,
    revB,
    log,
    bin,
    env: {
      ...process.env,
      DEEPSEEK_HARNESS_HOME: home,
      STUB_LOG: log,
    },
  };
}

function renderScripts(w: World, rev: string): { install: string; dsh: string } {
  const vars = {
    url: w.origin,
    dataDir: w.home,
    rev,
    version: VERSION,
    git: 'git',
    node: join(w.bin, 'node'),
    pnpm: join(w.bin, 'pnpm'),
  };
  const destDir = join(w.root, `rendered-${rev.slice(0, 8)}`);
  return {
    install: render(INSTALL_SH, vars, destDir),
    dsh: render(DSH_SH, vars, destDir),
  };
}

function run(script: string, args: string[], opts: { cwd: string; env: NodeJS.ProcessEnv }): RunResult {
  const r = spawnSync('bash', [script, ...args], {
    cwd: opts.cwd,
    env: opts.env,
    encoding: 'utf8',
  });
  return {
    status: r.status,
    stdout: String(r.stdout ?? ''),
    stderr: String(r.stderr ?? ''),
  };
}

function attemptDirs(w: World): string[] {
  if (!existsSync(w.home)) return [];
  return readdirSync(w.home).filter((d) => d.startsWith('attempt.'));
}

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

test('default.nix keeps the fork pin as the single source of truth', () => {
  const nix = readFileSync(MODULE_NIX, 'utf8');
  assert.match(nix, /url = "https:\/\/github\.com\/shiguredo\/deepseek-harness\.git"/);
  assert.match(nix, /rev = "767265cf34e09b57dcace16035adc51a7308e6d6"/);
  assert.match(nix, /version = "0\.2\.2-alpha\.3"/);
  assert.match(nix, /node-v24\.21\.0-darwin-arm64\.tar\.gz/);
  assert.match(nix, /pnpm-11\.28\.5\.tgz/);
  for (const script of [INSTALL_SH, DSH_SH]) {
    assert.ok(
      !readFileSync(script, 'utf8').includes(UPSTREAM_REV),
      `${script} must take the rev from Nix rendering, not a hardcoded copy`,
    );
  }
});

test('install checks out the pin, runs frozen install/build/smoke, and publishes ready', () => {
  const w = makeWorld();
  const { install } = renderScripts(w, w.revA);
  const neutral = realpathSync(mkdtempSync(join(tmpdir(), 'dsh-cwd-')));

  const r = run(install, [], { cwd: neutral, env: w.env });
  assert.equal(r.status, 0, r.stderr);

  const ready = join(w.home, 'ready');
  assert.ok(lstatSync(ready).isSymbolicLink(), 'ready must be a symlink');
  assert.match(readlinkSync(ready), /^builds\//);
  assert.equal(readFileSync(join(ready, '.dsh-rev'), 'utf8').trim(), w.revA);
  assert.equal(readFileSync(join(ready, 'apps/cli/src/bin.ts'), 'utf8'), '// rev A\n');
  assert.equal(readdirSync(join(w.home, 'builds')).length, 1);

  assert.equal(git(ready, 'rev-parse', 'HEAD'), w.revA);

  const log = readFileSync(w.log, 'utf8');
  assert.match(log, /argv=install --frozen-lockfile/);
  assert.match(log, /argv=run build/);
  assert.match(log, new RegExp(`node cwd=${escapeRegExp(neutral)}`));
  assert.match(log, /node argv=\S+\/apps\/cli\/lib\/bin\.js --version/);
  assert.match(log, /node argv=\S+\/apps\/cli\/lib\/bin\.js web --help/);

  assert.deepEqual(attemptDirs(w), [], 'attempt dir must be removed after publish');
});

test('install is idempotent while the pin is published', () => {
  const w = makeWorld();
  const { install } = renderScripts(w, w.revA);

  assert.equal(run(install, [], { cwd: w.root, env: w.env }).status, 0);
  const logAfterFirst = readFileSync(w.log, 'utf8');
  const second = run(install, [], { cwd: w.root, env: w.env });
  assert.equal(second.status, 0, second.stderr);
  assert.match(second.stdout, /already installed/);
  assert.equal(readFileSync(w.log, 'utf8'), logAfterFirst, 'pnpm/node must not rerun');
  assert.equal(readdirSync(join(w.home, 'builds')).length, 1);
});

test('a failed install publishes nothing and cleans the attempt', () => {
  const w = makeWorld();
  const { install } = renderScripts(w, w.revA);
  const env = { ...w.env, STUB_PNPM_INSTALL_EXIT: '9' };

  const r = run(install, [], { cwd: w.root, env });
  assert.notEqual(r.status, 0);
  assert.ok(!existsSync(join(w.home, 'ready')), 'no ready symlink may be published');
  assert.deepEqual(attemptDirs(w), [], 'attempt dir must be removed');
  assert.match(r.stderr, /failed; removed the attempt, prior ready build untouched/);
});

test('a failed rebuild preserves the prior ready build', () => {
  const w = makeWorld();
  const { install: installA } = renderScripts(w, w.revA);
  assert.equal(run(installA, [], { cwd: w.root, env: w.env }).status, 0);
  const readyTarget = readlinkSync(join(w.home, 'ready'));

  const { install: installB } = renderScripts(w, w.revB);
  const env = { ...w.env, STUB_PNPM_RUN_EXIT: '7' };
  const r = run(installB, [], { cwd: w.root, env });
  assert.notEqual(r.status, 0);

  assert.equal(readlinkSync(join(w.home, 'ready')), readyTarget);
  assert.equal(readFileSync(join(w.home, 'ready/.dsh-rev'), 'utf8').trim(), w.revA);
  assert.equal(readdirSync(join(w.home, 'builds')).length, 1);
  assert.deepEqual(attemptDirs(w), []);
  assert.match(r.stderr, /failed; removed the attempt, prior ready build untouched/);
});

test('a successful upgrade replaces the ready symlink without modifying the prior generation', () => {
  const w = makeWorld();
  const a = renderScripts(w, w.revA);
  assert.equal(run(a.install, [], { cwd: w.root, env: w.env }).status, 0);
  const prior = realpathSync(join(w.home, 'ready'));
  const b = renderScripts(w, w.revB);
  const stale = run(b.dsh, ['web'], { cwd: w.root, env: w.env });
  assert.equal(stale.status, 1);
  assert.match(stale.stderr, /installed revision differs/);
  const result = run(b.install, [], { cwd: w.root, env: w.env });
  assert.equal(result.status, 0, result.stderr);
  assert.notEqual(realpathSync(join(w.home, 'ready')), prior);
  assert.equal(readFileSync(join(w.home, 'ready/.dsh-rev'), 'utf8').trim(), w.revB);
  assert.equal(readFileSync(join(prior, '.dsh-rev'), 'utf8').trim(), w.revA);
});

test('a failed smoke does not publish', () => {
  const w = makeWorld();
  const { install } = renderScripts(w, w.revA);
  const env = { ...w.env, STUB_CLI_VERSION: '9.9.9-wrong' };

  const r = run(install, [], { cwd: w.root, env });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /expected version/);
  assert.ok(!existsSync(join(w.home, 'ready')));
  assert.deepEqual(attemptDirs(w), []);
});

test('dsh execs the fixed ready generation without changing cwd', () => {
  const w = makeWorld();
  const { install, dsh } = renderScripts(w, w.revA);
  assert.equal(run(install, [], { cwd: w.root, env: w.env }).status, 0);

  const caller = realpathSync(mkdtempSync(join(tmpdir(), 'dsh-caller-')));
  const r = run(dsh, ['web', '--no-open'], { cwd: caller, env: w.env });
  assert.equal(r.status, 0, r.stderr);

  const lines = readFileSync(w.log, 'utf8').trim().split('\n');
  const argvLine = lines.filter((l) => l.startsWith('node argv=')).at(-1)!;
  const cwdLine = lines.filter((l) => l.startsWith('node cwd=')).at(-1)!;
  assert.equal(
    argvLine,
    `node argv=${realpathSync(join(w.home, 'ready'))}/apps/cli/lib/bin.js web --no-open`,
  );
  assert.equal(cwdLine, `node cwd=${caller}`);
});

test('default install and dsh use the configured activation data directory without session XDG variables', () => {
  const w = makeWorld();
  const { install, dsh } = renderScripts(w, w.revA);
  const env = { ...w.env, XDG_DATA_HOME: join(w.root, 'unrelated-data') };
  delete env.DEEPSEEK_HARNESS_HOME;
  delete env.DSH_HOME;
  assert.equal(run(install, [], { cwd: w.root, env }).status, 0);
  assert.equal(run(dsh, ['web'], { cwd: w.root, env }).status, 0);
  assert.match(readFileSync(w.log, 'utf8'), new RegExp(`node state=${escapeRegExp(join(w.home, 'state'))}`));
  assert.equal(lstatSync(w.home).mode & 0o777, 0o700);
  const isolated = join(w.root, 'isolated-state');
  assert.equal(run(dsh, ['web'], { cwd: w.root, env: { ...env, DSH_HOME: isolated } }).status, 0);
  assert.match(readFileSync(w.log, 'utf8'), new RegExp(`node state=${escapeRegExp(isolated)}`));
});

test('dsh fails clearly when no ready build exists', () => {
  const w = makeWorld();
  const { dsh } = renderScripts(w, w.revA);

  const r = run(dsh, ['web'], { cwd: w.root, env: w.env });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /no ready build.*run deepseek-harness-install first/);
  assert.ok(!existsSync(w.log), 'node must not be invoked');
});
