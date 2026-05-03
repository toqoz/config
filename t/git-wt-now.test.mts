// Verify home/scripts/git-wt-now subcommands (create, rename, merge) using a
// real git repo in a tempdir, with stub `gh` (always failing, so the
// fallback path picks a local branch) and stub `codex` (writes a
// caller-controlled string to the file passed via `-o`). HOME is
// overridden so the personal-repo path prefix used by `merge` resolves
// inside the tempdir.
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
  chmodSync,
  existsSync,
  realpathSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const SCRIPT = `${REPO}/home/scripts/git-wt-now`;

type RunResult = {
  status: number | null;
  stdout: string;
  stderr: string;
};

type Env = Record<string, string>;

function run(
  args: string[],
  opts: { cwd: string; env: Env; input?: string },
): RunResult {
  const r = spawnSync('bash', [SCRIPT, ...args], {
    cwd: opts.cwd,
    env: opts.env,
    input: opts.input,
    encoding: 'utf8',
  });
  return {
    status: r.status,
    stdout: (r.stdout ?? '').toString(),
    stderr: (r.stderr ?? '').toString(),
  };
}

function git(cwd: string, env: Env, ...args: string[]): RunResult {
  const r = spawnSync('git', args, { cwd, env, encoding: 'utf8' });
  return {
    status: r.status,
    stdout: (r.stdout ?? '').toString().trim(),
    stderr: (r.stderr ?? '').toString(),
  };
}

// Build stubs for `gh` (always fails) and `codex` (echoes STUB_CODEX_OUT
// to the file passed via -o, exits with STUB_CODEX_EXIT or 0).
function makeStubs(dir: string): string {
  const bin = join(dir, 'stub-bin');
  mkdirSync(bin, { recursive: true });

  writeFileSync(
    join(bin, 'gh'),
    `#!/usr/bin/env bash\nexit 1\n`,
  );
  chmodSync(join(bin, 'gh'), 0o755);

  writeFileSync(
    join(bin, 'codex'),
    `#!/usr/bin/env bash
out=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
# Drain stdin so the producer doesn't get SIGPIPE
cat >/dev/null || true
if [ -n "$out" ]; then
  printf '%s' "\${STUB_CODEX_OUT:-}" > "$out"
fi
exit "\${STUB_CODEX_EXIT:-0}"
`,
  );
  chmodSync(join(bin, 'codex'), 0o755);
  return bin;
}

// Initialise a git repo inside `repoDir` with `wt.basedir = .git/wt`,
// a `main` branch, and one initial commit.
function initRepo(repoDir: string, env: Env): void {
  mkdirSync(repoDir, { recursive: true });
  git(repoDir, env, 'init', '--initial-branch=main', '-q');
  git(repoDir, env, 'config', 'user.email', 'test@example.com');
  git(repoDir, env, 'config', 'user.name', 'Test');
  git(repoDir, env, 'config', 'wt.basedir', '.git/wt');
  writeFileSync(join(repoDir, 'README.md'), '# init\n');
  git(repoDir, env, 'add', 'README.md');
  git(repoDir, env, 'commit', '-q', '-m', 'init');
}

type Sandbox = {
  root: string;
  home: string;
  repo: string;
  env: Env;
};

// Set up an isolated test sandbox:
//   - HOME at $root/home
//   - "personal" repo at $root/home/src/github.com/toqoz/repo
//   - stub gh+codex prepended to PATH
function setupSandbox(personal = true): Sandbox {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'git-wt-now-test-')));
  const home = join(root, 'home');
  const personalParent = join(home, 'src/github.com/toqoz');
  mkdirSync(personalParent, { recursive: true });

  const repo = personal
    ? join(personalParent, 'repo')
    : join(root, 'other/repo');
  if (!personal) mkdirSync(dirname(repo), { recursive: true });

  const stubBin = makeStubs(root);

  const env: Env = {
    ...process.env,
    HOME: home,
    PATH: `${stubBin}:${process.env.PATH ?? ''}`,
    GIT_CONFIG_GLOBAL: '/dev/null',
    GIT_CONFIG_SYSTEM: '/dev/null',
    // Disable any inherited stub state
    STUB_CODEX_OUT: '',
    STUB_CODEX_EXIT: '0',
  } as Env;

  initRepo(repo, env);

  return { root, home, repo, env };
}

// Convenience: run git-wt-now (bare) inside the repo and return the
// printed worktree path.
function createWtNow(sb: Sandbox): { branch: string; path: string } {
  const r = run([], { cwd: sb.repo, env: sb.env });
  assert.equal(r.status, 0, `create failed: ${r.stderr}`);
  const path = r.stdout.trim();
  assert.ok(existsSync(path), `worktree path missing: ${path}`);
  const branch = git(path, sb.env, 'symbolic-ref', '--short', 'HEAD').stdout;
  return { branch, path };
}

function commitInWt(wtPath: string, env: Env, file: string, msg: string): void {
  writeFileSync(join(wtPath, file), 'content\n');
  git(wtPath, env, 'add', file);
  git(wtPath, env, 'commit', '-q', '-m', msg);
}

// ---- create ----

test('create makes wt-now/<base>/<ts> branch with wtNowBase config', () => {
  const sb = setupSandbox();
  const { branch, path } = createWtNow(sb);

  assert.match(branch, /^wt-now\/main\/\d{8}-\d{6}$/);
  assert.ok(path.startsWith(`${sb.repo}/.git/wt/${branch}`),
    `worktree path mismatch: ${path}`);

  const base = git(sb.repo, sb.env, 'config', '--get',
    `branch.${branch}.wtNowBase`).stdout;
  assert.equal(base, 'main');
});

// ---- rename ----

test('rename aborts when worktree is dirty', () => {
  const sb = setupSandbox();
  const { path } = createWtNow(sb);
  writeFileSync(join(path, 'dirty.txt'), 'x');

  const r = run(['rename'], { cwd: path, env: sb.env });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /dirty/);
});

test('rename aborts when no commits on the branch', () => {
  const sb = setupSandbox();
  const { path } = createWtNow(sb);

  const r = run(['rename'], { cwd: path, env: sb.env });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /no commits/);
});

test('rename aborts when codex returns an invalid name', () => {
  const sb = setupSandbox();
  const { path } = createWtNow(sb);
  commitInWt(path, sb.env, 'a.txt', 'work a');

  const env = { ...sb.env, STUB_CODEX_OUT: 'NotAValid' };
  const r = run(['rename'], { cwd: path, env });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /invalid name/);
});

test('rename aborts when codex exits non-zero', () => {
  const sb = setupSandbox();
  const { path } = createWtNow(sb);
  commitInWt(path, sb.env, 'a.txt', 'work a');

  const env = { ...sb.env, STUB_CODEX_OUT: 'feat/foo', STUB_CODEX_EXIT: '7' };
  const r = run(['rename'], { cwd: path, env });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /codex exec failed/);
});

test('rename happy path renames branch, moves worktree, preserves wtNowBase', () => {
  const sb = setupSandbox();
  const { branch: oldBranch, path: oldPath } = createWtNow(sb);
  commitInWt(oldPath, sb.env, 'a.txt', 'work a');

  const env = { ...sb.env, STUB_CODEX_OUT: 'feat/the-new-thing\n' };
  const r = run(['rename'], { cwd: oldPath, env });
  assert.equal(r.status, 0, `rename failed: ${r.stderr}`);

  const newPath = `${sb.repo}/.git/wt/feat/the-new-thing`;
  assert.ok(existsSync(newPath), `new worktree path missing: ${newPath}`);

  // Old branch gone, new branch present
  assert.equal(
    git(sb.repo, sb.env, 'rev-parse', '--verify', `refs/heads/${oldBranch}`).status,
    128,
  );
  assert.equal(
    git(sb.repo, sb.env, 'rev-parse', '--verify',
      'refs/heads/feat/the-new-thing').status,
    0,
  );

  // wtNowBase carried to new branch
  assert.equal(
    git(sb.repo, sb.env, 'config', '--get',
      'branch.feat/the-new-thing.wtNowBase').stdout,
    'main',
  );
  // Old config gone
  assert.notEqual(
    git(sb.repo, sb.env, 'config', '--get',
      `branch.${oldBranch}.wtNowBase`).status,
    0,
  );
});

// ---- merge ----

test('merge aborts outside personal repo prefix', () => {
  const sb = setupSandbox(false /* personal */);
  const { path } = createWtNow(sb);
  commitInWt(path, sb.env, 'a.txt', 'work a');

  const r = run(['merge'], { cwd: path, env: sb.env });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /personal repos/);
});

test('merge aborts when worktree is dirty', () => {
  const sb = setupSandbox();
  const { path } = createWtNow(sb);
  commitInWt(path, sb.env, 'a.txt', 'work a');
  writeFileSync(join(path, 'dirty.txt'), 'x');

  const r = run(['merge'], { cwd: path, env: sb.env });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /dirty/);
});

test('merge aborts when no commits on the branch', () => {
  const sb = setupSandbox();
  const { path } = createWtNow(sb);

  const r = run(['merge'], { cwd: path, env: sb.env });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /no commits/);
});

test('merge happy path: ff-merges into base, removes wt and branch', () => {
  const sb = setupSandbox();
  const { branch, path } = createWtNow(sb);
  commitInWt(path, sb.env, 'a.txt', 'work a');
  commitInWt(path, sb.env, 'b.txt', 'work b');
  const tip = git(path, sb.env, 'rev-parse', 'HEAD').stdout;

  const r = run(['merge'], { cwd: path, env: sb.env });
  assert.equal(r.status, 0, `merge failed: ${r.stderr}`);

  // main now points at the rebased tip
  assert.equal(
    git(sb.repo, sb.env, 'rev-parse', 'refs/heads/main').stdout,
    tip,
  );
  // worktree gone
  assert.equal(existsSync(path), false);
  // branch gone
  assert.equal(
    git(sb.repo, sb.env, 'rev-parse', '--verify', `refs/heads/${branch}`).status,
    128,
  );
  // wtNowBase config gone
  assert.notEqual(
    git(sb.repo, sb.env, 'config', '--get',
      `branch.${branch}.wtNowBase`).status,
    0,
  );
});

// ---- dispatch ----

test('unknown subcommand exits 64', () => {
  const sb = setupSandbox();
  const r = run(['bogus'], { cwd: sb.repo, env: sb.env });
  assert.equal(r.status, 64);
  assert.match(r.stderr, /unknown subcommand/);
});
