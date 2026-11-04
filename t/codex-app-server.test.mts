import { test, type TestContext } from 'node:test';
import { strict as assert } from 'node:assert';
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const DNS = 'forge01.tail123.ts.net';

function evaluate() {
  const r = spawnSync('nix', ['eval', '--impure', '--json', '--expr', `
    let
      flake = builtins.getFlake ("git+file://" + toString ./.);
      home = flake.darwinConfigurations.forge01.config.home-manager.users.agent;
      pkgs = flake.inputs.nixpkgs.legacyPackages.aarch64-darwin;
      guard = pkgs.callPackage (flake.outPath + "/packages/tailscale-serve.nix") {};
    in {
      activation = home.home.activation.prepareCodexAppServer;
      stateDir = home.xdg.stateHome + "/codex-app-server";
      helper = flake.inputs.home-manager.outPath + "/lib/bash/home-manager.sh";
      bash = pkgs.bash.outPath + "/bin/bash";
      guard = toString guard;
      guardText = builtins.readFile guard;
      serviceText = builtins.readFile (builtins.head home.launchd.agents.codex-app-server.config.ProgramArguments);
      codex = flake.inputs.nixpkgs.lib.getExe flake.inputs.llm-agents.packages.aarch64-darwin.codex;
    }
  `], { cwd: REPO, encoding: 'utf8', timeout: 90_000 });
  assert.equal(r.status, 0, r.stderr);
  return JSON.parse(r.stdout);
}

let contract: ReturnType<typeof evaluate>;
function workspace(t: TestContext) {
  contract ??= evaluate();
  const cache = join(REPO, '.agents/cache/codex-app-server-tests');
  mkdirSync(cache, { recursive: true });
  const root = mkdtempSync(join(cache, 'service-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  return root;
}

test('evaluated activation preserves a private token, rejects invalid files, and does nothing in dry-run', (t) => {
  const root = workspace(t);
  assert.deepEqual(contract.activation.after, ['linkGeneration', 'mergeCodexConfig']);
  assert.deepEqual(contract.activation.before, ['setupLaunchAgents']);
  const env = { ...process.env, HOME: root };
  delete env.DRY_RUN;
  const activate = (data: string, dry = false) => spawnSync(contract.bash, ['-c',
    `set -euo pipefail\nsource '${contract.helper}'\n${contract.activation.data.replaceAll(contract.stateDir, data)}`,
  ], { encoding: 'utf8', timeout: 5_000, env: { ...env, ...(dry ? { DRY_RUN: '1' } : {}) } });
  const data = join(root, 'state');
  const dry = activate(data, true);
  assert.equal(dry.status, 0, dry.stderr);
  assert.ok(!existsSync(data));
  const first = activate(data);
  assert.equal(first.status, 0, first.stderr);
  const tokenFile = join(data, 'capability-token');
  const token = readFileSync(tokenFile, 'utf8');
  assert.match(token, /^[0-9a-f]{64}\n$/);
  for (const dir of [data, join(data, 'log')]) {
    assert.equal(statSync(dir).mode & 0o777, 0o700);
    chmodSync(dir, 0o755);
  }
  for (const file of [tokenFile, join(data, 'log/stdout.log'), join(data, 'log/stderr.log')]) {
    assert.equal(statSync(file).mode & 0o777, 0o600);
    chmodSync(file, 0o644);
  }
  writeFileSync(join(data, 'log/stdout.log'), 'existing log');
  const dryExisting = activate(data, true);
  assert.equal(dryExisting.status, 0, dryExisting.stderr);
  assert.equal(statSync(tokenFile).mode & 0o777, 0o644);
  const second = activate(data);
  assert.equal(second.status, 0, second.stderr);
  assert.equal(readFileSync(tokenFile, 'utf8'), token);
  assert.equal(readFileSync(join(data, 'log/stdout.log'), 'utf8'), 'existing log');
  for (const dir of [data, join(data, 'log')]) assert.equal(statSync(dir).mode & 0o777, 0o700);
  for (const file of [tokenFile, join(data, 'log/stdout.log'), join(data, 'log/stderr.log')]) {
    assert.equal(statSync(file).mode & 0o777, 0o600);
  }
  for (const r of [dry, first, dryExisting, second]) {
    assert.ok(!`${r.stdout}${r.stderr}`.includes(token.trim()), 'activation must not disclose the token');
  }
  for (const [i, invalid] of ['', 'a'.repeat(63), 'g'.repeat(64), `${'a'.repeat(64)}\nother`, `${'a'.repeat(64)}\0`].entries()) {
    const dir = join(root, `invalid-${i}`);
    mkdirSync(dir);
    const file = join(dir, 'capability-token');
    writeFileSync(file, invalid);
    const r = activate(dir);
    assert.equal(r.status, 1, r.stderr);
    assert.match(r.stderr, /invalid capability token/);
    assert.equal(readFileSync(file, 'utf8'), invalid);
    if (invalid) assert.ok(!`${r.stdout}${r.stderr}`.includes(invalid));
  }
  for (const kind of ['directory', 'symlink', 'dangling-symlink']) {
    const dir = join(root, kind);
    mkdirSync(dir);
    const file = join(dir, 'capability-token');
    if (kind === 'directory') mkdirSync(file);
    else symlinkSync(kind === 'symlink' ? tokenFile : join(root, 'missing'), file);
    const r = activate(dir);
    assert.equal(r.status, 1, r.stderr);
    assert.match(r.stderr, /regular file, not a symlink/);
    assert.equal(readFileSync(tokenFile, 'utf8'), token);
  }
});

test('evaluated service uses capability auth on loopback 4500 and leaves DeepSeek 3080 intact', (t) => {
  const root = workspace(t);
  const calls = join(root, 'calls.jsonl');
  const serve = join(root, 'serve.json');
  const result = join(root, 'result.json');
  const tokenFile = join(root, 'capability token');
  const secret = 'a'.repeat(64);
  writeFileSync(tokenFile, secret);
  const deepseek = {
    TCP: { '3080': { HTTPS: true } },
    Web: { [`${DNS}:3080`]: { Handlers: { '/': { Proxy: 'http://127.0.0.1:3080' } } } },
  };
  writeFileSync(serve, JSON.stringify(deepseek));
  const tailscale = join(root, 'Tailscale');
  writeFileSync(tailscale, `#!${process.execPath}
const fs = require('node:fs');
const args = process.argv.slice(2);
fs.appendFileSync(process.env.CALLS, JSON.stringify(args) + '\\n');
if (args.join(' ') === 'status --json') {
  console.log(JSON.stringify({ BackendState: 'Running', Self: { DNSName: '${DNS}.' } }));
} else if (args.join(' ') === 'serve status --json') {
  process.stdout.write(fs.readFileSync(process.env.SERVE));
} else {
  if (args.join(' ') !== 'serve --bg --yes --https=4500 http://127.0.0.1:4500') process.exit(90);
  console.log('Tailscale configured HTTPS');
}
`);
  chmodSync(tailscale, 0o755);
  const guard = join(root, 'tailscale-serve');
  writeFileSync(guard, contract.guardText.replaceAll('/Applications/Tailscale.app/Contents/MacOS/Tailscale', tailscale));
  chmodSync(guard, 0o755);
  const codex = join(root, 'codex');
  writeFileSync(codex, `#!${process.execPath}
require('node:fs').writeFileSync(process.env.RESULT, JSON.stringify({
  args: process.argv.slice(2), home: process.env.HOME, cwd: process.cwd(), umask: process.umask()
}));
process.exit(Number(process.env.CODEX_EXIT || 0));
`);
  chmodSync(codex, 0o755);
  const service = join(root, 'service');
  writeFileSync(service, contract.serviceText.replaceAll(contract.guard, guard)
    .replaceAll(contract.codex, codex).replaceAll(`${contract.stateDir}/capability-token`, tokenFile));
  const run = (extra: NodeJS.ProcessEnv = {}) => spawnSync(contract.bash, [service], {
    cwd: root, encoding: 'utf8', timeout: 5_000,
    env: { ...process.env, HOME: root, CALLS: calls, SERVE: serve, RESULT: result, ...extra },
  });
  const r = run();
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, `wss://${DNS}:4500/\n`);
  assert.match(r.stderr, /Tailscale configured HTTPS/);
  assert.ok(!`${r.stdout}${r.stderr}`.includes(secret));
  assert.deepEqual(JSON.parse(readFileSync(result, 'utf8')), {
    args: ['app-server', '--listen', 'ws://127.0.0.1:4500', '--ws-auth', 'capability-token', '--ws-token-file', tokenFile],
    home: root, cwd: root, umask: 0o077,
  });
  assert.deepEqual(readFileSync(calls, 'utf8').trim().split('\n').map((line) => JSON.parse(line)), [
    ['status', '--json'], ['serve', 'status', '--json'],
    ['serve', '--bg', '--yes', '--https=4500', 'http://127.0.0.1:4500'],
  ]);
  assert.equal(readFileSync(serve, 'utf8'), JSON.stringify(deepseek));
  assert.equal(run({ CODEX_EXIT: '23' }).status, 23);
  const matching = {
    TCP: { ...deepseek.TCP, '4500': { HTTPS: true } },
    Web: { ...deepseek.Web, [`${DNS}:4500`]: { Handlers: { '/': { Proxy: 'http://127.0.0.1:4500' } } } },
  };
  writeFileSync(serve, JSON.stringify(matching));
  assert.equal(run().status, 0);
  rmSync(result);
  const exposed = { ...matching, AllowFunnel: { [`${DNS}:4500`]: true } };
  writeFileSync(serve, JSON.stringify(exposed));
  const blocked = run();
  assert.equal(blocked.status, 1);
  assert.equal(blocked.stdout, '');
  assert.ok(!existsSync(result));
  assert.equal(readFileSync(serve, 'utf8'), JSON.stringify(exposed));
});
