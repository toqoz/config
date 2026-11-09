import { test, type TestContext } from 'node:test';
import { strict as assert } from 'node:assert';
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const DNS = 'forge01.tail123.ts.net';
const HOST = `${DNS}:3080`;
const PROXY = { Handlers: { '/': { Proxy: 'http://127.0.0.1:3080' } } };
const MATCHING = { TCP: { '3080': { HTTPS: true } }, Web: { [HOST]: PROXY } };

function makeService(t: TestContext) {
  const cache = join(REPO, '.agents/cache/deepseek-service-tests');
  mkdirSync(cache, { recursive: true });
  const root = mkdtempSync(join(cache, 'service-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const dataDir = join(root, 'private data');
  const calls = join(root, 'calls.jsonl');
  const status = join(root, 'status.json');
  const serve = join(root, 'serve.json');
  writeFileSync(status, JSON.stringify({ BackendState: 'Running', Self: { DNSName: `${DNS}.` } }));
  writeFileSync(serve, '{}');
  const tailscale = join(root, 'Tailscale');
  writeFileSync(tailscale, `#!${process.execPath}
const fs = require('node:fs');
const args = process.argv.slice(2);
fs.appendFileSync(process.env.CALLS, JSON.stringify(args) + '\\n');
if (args[0] === 'status') {
  process.stdout.write(fs.readFileSync(process.env.STATUS));
  process.exit(Number(process.env.STATUS_EXIT || 0));
}
if (args.join(' ') === 'serve status --json') {
  process.stdout.write(fs.readFileSync(process.env.SERVE));
  process.exit(Number(process.env.SERVE_STATUS_EXIT || 0));
}
if (args.join(' ') !== 'serve --bg --yes --https=3080 http://127.0.0.1:3080') process.exit(90);
console.log('Tailscale configured HTTPS');
process.exit(Number(process.env.SERVE_EXIT || 0));
`);
  chmodSync(tailscale, 0o755);
  writeFileSync(join(root, 'dsh'), `#!${process.execPath}
const fs = require('node:fs');
fs.writeFileSync(process.env.DSH_RESULT, JSON.stringify({
  args: process.argv.slice(2), cwd: process.cwd(),
  home: process.env.DEEPSEEK_HARNESS_HOME, state: process.env.DSH_HOME,
  umask: process.umask()
}));
console.log('One-time login URL: https://${HOST}/?token=test-secret');
process.exit(Number(process.env.DSH_EXIT || 0));
`);
  chmodSync(join(root, 'dsh'), 0o755);
  const script = join(root, 'service');
  const jq = spawnSync('which', ['jq'], { encoding: 'utf8' });
  assert.equal(jq.status, 0, 'jq is required for service tests');
  const tailscaleServe = join(root, 'tailscale-serve');
  const guard = readFileSync(join(REPO, 'packages/tailscale-serve.bash'), 'utf8')
    .replaceAll('@tailscale@', tailscale).replaceAll('@jq@', jq.stdout.trim());
  writeFileSync(tailscaleServe, `#!/bin/bash\n${guard}`);
  chmodSync(tailscaleServe, 0o755);
  let text = readFileSync(join(REPO, 'home/deepseek-harness/service.sh'), 'utf8');
  for (const [key, value] of Object.entries({ tailscaleServe, port: '3080', dataDir })) {
    text = text.replaceAll(`@${key}@`, value);
  }
  assert.doesNotMatch(text, /@[a-zA-Z]+@/);
  writeFileSync(script, text);
  const result = join(root, 'result.json');
  return {
    root, dataDir, status, serve, result, tailscaleServe,
    calls: (): string[][] => existsSync(calls)
      ? readFileSync(calls, 'utf8').trim().split('\n').map((line) => JSON.parse(line)) : [],
    run: (extra: NodeJS.ProcessEnv = {}) => spawnSync('/bin/bash', [script], {
      cwd: root,
      encoding: 'utf8',
      timeout: 5_000,
      env: { ...process.env, DSH_HOME: '', CALLS: calls, STATUS: status, SERVE: serve, DSH_RESULT: result, ...extra },
    }),
  };
}

test('service configures only HTTPS 3080 and execs the loopback backend with durable private state', (t) => {
  const w = makeService(t);
  const r = w.run();
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(w.calls(), [
    ['status', '--json'],
    ['serve', 'status', '--json'],
    ['serve', '--bg', '--yes', '--https=3080', 'http://127.0.0.1:3080'],
  ]);
  assert.deepEqual(JSON.parse(readFileSync(w.result, 'utf8')), {
    args: ['web', '--no-open', '--host', '127.0.0.1', '--port', '3080', '--public-url', `https://${HOST}/`, '--trusted-host', HOST],
    cwd: w.root, home: w.dataDir, state: join(w.dataDir, 'state'), umask: 0o077,
  });
  assert.equal(statSync(w.result).mode & 0o777, 0o600);
  assert.match(r.stdout, /One-time login URL: .*token=test-secret/);
  assert.doesNotMatch(r.stdout, /Tailscale configured/);
  assert.match(r.stderr, /Tailscale configured HTTPS/);
});

test('shared Serve guard validates its port and reserves stdout for DNS:port', (t) => {
  const w = makeService(t);
  const env = { ...process.env, CALLS: join(w.root, 'calls.jsonl'), STATUS: w.status, SERVE: w.serve };
  for (const args of [[], [''], ['0'], ['01'], ['-1'], ['65536'], ['9'.repeat(100)], ['4500x'], ['3080', '4500']]) {
    const r = spawnSync('/bin/bash', [w.tailscaleServe, ...args], { encoding: 'utf8', env });
    assert.equal(r.status, 1, JSON.stringify(args));
    assert.equal(r.stdout, '');
    assert.deepEqual(w.calls(), []);
  }
  const r = spawnSync('/bin/bash', [w.tailscaleServe, '3080'], { encoding: 'utf8', env });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, `${HOST}\n`);
  assert.match(r.stderr, /Tailscale configured HTTPS/);
});

test('explicit runtime home overrides remain available for isolated troubleshooting', (t) => {
  const w = makeService(t);
  const state = join(w.root, 'isolated-state');
  const r = w.run({ DSH_HOME: state });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(JSON.parse(readFileSync(w.result, 'utf8')).state, state);
});

test('restarts accept the exact same root proxy without reset, funnel, or broad config writes', (t) => {
  const w = makeService(t);
  const config = { ...MATCHING, AllowFunnel: { [HOST]: false } };
  writeFileSync(w.serve, JSON.stringify(config));
  for (let i = 0; i < 2; i++) assert.equal(w.run().status, 0);
  assert.equal(w.calls().filter((args) => args.includes('--bg')).length, 2);
  assert.equal(readFileSync(w.serve, 'utf8'), JSON.stringify(config));
});

test('other Serve ports and service VIPs remain untouched', (t) => {
  const w = makeService(t);
  const config = {
    TCP: { '443': { HTTPS: true } },
    Web: { [`${DNS}:443`]: { Handlers: { '/other': { Proxy: 'http://127.0.0.1:9000' } } } },
    AllowFunnel: { [`${DNS}:443`]: true },
    Foreground: { session: { TCP: { '8443': { TCPForward: 'localhost:9001' } } } },
    Services: { 'svc:other': MATCHING },
  };
  writeFileSync(w.serve, JSON.stringify(config));
  const r = w.run();
  assert.equal(r.status, 0, r.stderr);
  assert.equal(readFileSync(w.serve, 'utf8'), JSON.stringify(config));
  assert.deepEqual(w.calls().at(-1), ['serve', '--bg', '--yes', '--https=3080', 'http://127.0.0.1:3080']);
});

const collisions = [
  { TCP: { '3080': { TCPForward: '127.0.0.1:9000' } } },
  { TCP: { '3080': { HTTP: true } } },
  { ...MATCHING, Web: { [HOST]: { Handlers: { '/': { Proxy: 'http://127.0.0.1:9000' } } } } },
  { ...MATCHING, Web: { [HOST]: { Handlers: { ...PROXY.Handlers, '/other': { Text: 'private' } } } } },
  { ...MATCHING, Web: { [HOST]: PROXY, 'other.tail123.ts.net:3080': PROXY } },
  { ...MATCHING, AllowFunnel: { [HOST]: true } },
  { AllowFunnel: { [HOST]: true } },
  { Web: { [HOST]: PROXY } },
  { Foreground: { session: MATCHING } },
  { ...MATCHING, Foreground: { session: MATCHING } },
];
for (const [i, config] of collisions.entries()) {
  test(`Serve occupant ${i + 1} fails closed without changing configuration or starting dsh`, (t) => {
    const w = makeService(t);
    writeFileSync(w.serve, JSON.stringify(config));
    const r = w.run();
    assert.equal(r.status, 1, r.stderr);
    assert.match(r.stderr, /refusing to change/);
    assert.equal(w.calls().length, 2);
    assert.equal(readFileSync(w.serve, 'utf8'), JSON.stringify(config));
    assert.ok(!existsSync(w.result));
  });
}

for (const bad of ['{', 'null', '[]', '{} {}', '{"TCP":{"3080":null}}']) {
  test(`invalid Serve config ${bad} fails closed`, (t) => {
    const w = makeService(t);
    writeFileSync(w.serve, bad);
    assert.equal(w.run().status, 1);
    assert.equal(w.calls().length, 2);
    assert.ok(!existsSync(w.result));
  });
}

for (const bad of [
  '{', '{} {}',
  JSON.stringify({ BackendState: 'Stopped', Self: { DNSName: DNS } }),
  JSON.stringify({ BackendState: 'NeedsLogin', Self: { DNSName: DNS } }),
  ...['', 'bad name.ts.net', '-bad.ts.net', 'localhost', 'bad.ts.net/evil', 'a'.repeat(64) + '.ts.net'].map(
    (DNSName) => JSON.stringify({ BackendState: 'Running', Self: { DNSName } }),
  ),
]) {
  test(`offline or invalid DNS status ${bad} exits for launchd retry without Serve writes`, (t) => {
    const w = makeService(t);
    writeFileSync(w.status, bad);
    const r = w.run();
    assert.equal(r.status, 1, r.stderr);
    assert.equal(w.calls().length, 1);
    assert.ok(!existsSync(w.result));
  });
}

test('a late Tailscale login succeeds on the next invocation, not in an installer retry loop', (t) => {
  const w = makeService(t);
  writeFileSync(w.status, JSON.stringify({ BackendState: 'NeedsLogin' }));
  assert.equal(w.run().status, 1);
  writeFileSync(w.status, JSON.stringify({ BackendState: 'Running', Self: { DNSName: DNS } }));
  assert.equal(w.run().status, 0);
  assert.equal(w.calls().length, 4);
});

for (const env of [{ STATUS_EXIT: '7' }, { SERVE_STATUS_EXIT: '8' }, { SERVE_EXIT: '9' }]) {
  test(`Tailscale command failure ${JSON.stringify(env)} prevents backend startup`, (t) => {
    const w = makeService(t);
    assert.equal(w.run(env).status, 1);
    assert.ok(!existsSync(w.result));
  });
}

test('exec propagates a backend crash so launchd can restart it', (t) => {
  const w = makeService(t);
  assert.equal(w.run({ DSH_EXIT: '23' }).status, 23);
});

test('evaluated activation is dry-run safe and prepares private data before launchd setup', (t) => {
  const w = makeService(t);
  const evaluated = spawnSync('nix', ['eval', '--impure', '--json', '--expr', `
    let
      flake = builtins.getFlake ("git+file://" + toString ./.);
      home = flake.darwinConfigurations.forge01.config.home-manager.users.agent;
      remilis = flake.darwinConfigurations.remilis.config.home-manager.users.toqoz;
      package = builtins.head (builtins.filter (p: (p.pname or "") == "deepseek-harness") home.home.packages);
    in {
      activation = home.home.activation.installDeepseekHarness;
      agent = home.launchd.agents.deepseek-harness;
      helper = flake.inputs.home-manager.outPath + "/lib/bash/home-manager.sh";
      bash = flake.inputs.nixpkgs.legacyPackages.aarch64-darwin.bash.outPath + "/bin/bash";
      dataDir = home.xdg.dataHome + "/deepseek-harness";
      node = home.home.sessionVariables.DSH_NODE;
      service = package.outPath + "/bin/deepseek-harness-service";
      remilisAbsent = !(remilis.home.activation ? installDeepseekHarness) && !(remilis.launchd.agents ? deepseek-harness);
    }
  `], { cwd: REPO, encoding: 'utf8', timeout: 90_000 });
  assert.equal(evaluated.status, 0, evaluated.stderr);
  const contract = JSON.parse(evaluated.stdout);
  assert.deepEqual(contract.activation.after, ['writeBoundary', 'linkGeneration']);
  assert.deepEqual(contract.activation.before, ['setupLaunchAgents']);
  assert.equal(contract.remilisAbsent, true);
  assert.equal(contract.agent.enable, true);
  assert.equal(contract.agent.domain, 'gui');
  // The gui domain relies on the Aqua session, where the login keychain is
  // unlocked; the Background session type would break keychain-backed tools
  // such as gh and the git credential helper.
  assert.equal(contract.agent.config.LimitLoadToSessionType, null);
  assert.deepEqual(contract.agent.config.ProgramArguments, [contract.service]);
  assert.equal(contract.agent.config.WorkingDirectory, '/Users/agent');
  for (const path of ['/etc/profiles/per-user/agent/bin', '/Users/agent/.local/share/home-scripts/bin', '/run/current-system/sw/bin', '/usr/bin', '/bin']) {
    assert.ok(contract.agent.config.EnvironmentVariables.PATH.split(':').includes(path));
  }
  assert.equal(contract.agent.config.RunAtLoad, true);
  assert.equal(contract.agent.config.KeepAlive, true);
  assert.equal(contract.agent.config.ThrottleInterval, 10);
  assert.equal(contract.agent.config.Umask, 0o077);
  assert.equal(contract.agent.config.StandardOutPath, `${contract.dataDir}/log/stdout.log`);
  assert.equal(contract.agent.config.StandardErrorPath, `${contract.dataDir}/log/stderr.log`);

  const data = join(w.root, 'activation-data');
  assert.equal(contract.agent.config.EnvironmentVariables.DSH_NODE, contract.node);
  const body = contract.activation.data.replaceAll(contract.dataDir, data);
  const activation = `set -euo pipefail\nsource '${contract.helper}'\n${body}`;
  const dry = spawnSync(contract.bash, ['-c', activation], {
    encoding: 'utf8', env: { ...process.env, DRY_RUN: '1' },
  });
  assert.equal(dry.status, 0, dry.stderr);
  assert.ok(!existsSync(data), 'dry-run must not create data directories');
  assert.match(dry.stdout, /deepseek|activation-data/);
  const env = { ...process.env };
  delete env.DRY_RUN;
  const live = spawnSync(contract.bash, ['-c', activation], { encoding: 'utf8', env });
  assert.equal(live.status, 0, live.stderr);
  for (const path of [data, join(data, 'state'), join(data, 'log')]) {
    assert.equal(statSync(path).mode & 0o777, 0o700);
  }
  for (const name of ['stdout.log', 'stderr.log']) {
    const log = join(data, 'log', name);
    assert.equal(statSync(log).mode & 0o777, 0o600);
    writeFileSync(log, 'existing login token');
    chmodSync(log, 0o644);
  }
  const repeat = spawnSync(contract.bash, ['-c', activation], { encoding: 'utf8', env });
  assert.equal(repeat.status, 0, repeat.stderr);
  for (const name of ['stdout.log', 'stderr.log']) {
    const log = join(data, 'log', name);
    assert.equal(statSync(log).mode & 0o777, 0o600);
    assert.equal(readFileSync(log, 'utf8'), 'existing login token');
  }
});
