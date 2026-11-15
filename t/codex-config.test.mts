import { strict as assert } from 'node:assert';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test, type TestContext } from 'node:test';

const repo = fileURLToPath(new URL('..', import.meta.url));
const cache = join(repo, '.agents/cache/codex-config-tests');
const activation = execFileSync('nix', [
  'eval', '--raw',
  `${repo}#darwinConfigurations.remilis.config.home-manager.users.toqoz.home.activation.mergeCodexConfig.data`,
], { encoding: 'utf8' });

function fixture(t: TestContext, live?: string, managed = 'model = "managed"\n') {
  mkdirSync(cache, { recursive: true });
  const home = mkdtempSync(join(cache, 'case-'));
  t.after(() => rmSync(home, { recursive: true, force: true }));
  const directory = join(home, '.codex');
  mkdirSync(directory);
  writeFileSync(join(directory, 'config.managed.toml'), managed);
  const config = join(directory, 'config.toml');
  if (live !== undefined) writeFileSync(config, live);
  const apply = () => {
    const result = spawnSync('bash', ['-c', activation], {
      env: { ...process.env, HOME: home }, encoding: 'utf8',
    });
    assert.equal(result.status, 0, result.stderr);
    return readFileSync(config, 'utf8');
  };
  const read = (): unknown => JSON.parse(execFileSync('python3', [
    '-c', 'import json,sys,tomllib; print(json.dumps(tomllib.load(open(sys.argv[1], "rb"))))',
    config,
  ], { encoding: 'utf8' }));
  return { apply, read, config };
}

test('Codex activation preserves hook trust and project choices alongside managed settings', t => {
  const f = fixture(t, `model = "old"
[projects."/repo with spaces"]
trust_level = "trusted"
[hooks.state."file:/home/.codex/hooks.json:Stop:0:0"]
enabled = false
trusted_hash = "reviewed-declaration"
trusted_content_hash = "reviewed-content"
`);
  f.apply();
  assert.deepEqual(f.read(), {
    model: 'managed',
    projects: { '/repo with spaces': { trust_level: 'trusted' } },
    hooks: { state: {
      'file:/home/.codex/hooks.json:Stop:0:0': {
        enabled: false,
        trusted_hash: 'reviewed-declaration',
        trusted_content_hash: 'reviewed-content',
      },
    } },
  });
  assert.equal(statSync(f.config).mode & 0o777, 0o600);
});

test('Codex activation keeps hook state stable across repeated applications', t => {
  const f = fixture(t, `[hooks.state.example]
enabled = true
trusted_hash = "reviewed"
`);
  const first = f.apply();
  assert.equal(f.apply(), first);
  assert.deepEqual(f.read(), {
    model: 'managed',
    hooks: { state: { example: { enabled: true, trusted_hash: 'reviewed' } } },
  });
});

test('new or malformed Codex configuration does not grant hook trust', t => {
  for (const live of [undefined, '[broken', 'hooks = "invalid"', '[hooks]\nstate = "invalid"']) {
    const f = fixture(t, live);
    f.apply();
    assert.deepEqual(f.read(), { model: 'managed' });
  }
});

test('managed inline hooks and existing hook trust remain valid TOML together', t => {
  const f = fixture(t, '[hooks.state.reviewed]\nenabled = true\ntrusted_hash = "reviewed"\n',
    '[[hooks.Stop]]\n[[hooks.Stop.hooks]]\ntype = "command"\ncommand = "/stable/grokbot-notify hook codex"\n');
  const first = f.apply();
  assert.equal(f.apply(), first);
  assert.deepEqual(f.read(), {
    hooks: {
      Stop: [{ hooks: [{ type: 'command', command: '/stable/grokbot-notify hook codex' }] }],
      state: { reviewed: { enabled: true, trusted_hash: 'reviewed' } },
    },
  });
});
