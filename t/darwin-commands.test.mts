import { strict as assert } from 'node:assert';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

function evaluate(attribute: string, expression: string): unknown {
  const result = spawnSync('nix', ['eval', '--json', attribute, '--apply', expression], {
    encoding: 'utf8',
    timeout: 120_000,
  });
  assert.equal(result.status, 0, result.stderr);
  return JSON.parse(result.stdout);
}

test('Darwin apps require a host and forward the selected host and arguments', () => {
  const scripts = evaluate('.#packages.aarch64-darwin', 'ps: builtins.mapAttrs (_: p: p.text) ps');
  const apps = evaluate('.#apps.aarch64-darwin', 'apps: builtins.mapAttrs (_: app: app.program) apps');
  assert.ok(scripts && typeof scripts === 'object');
  assert.ok(apps && typeof apps === 'object');
  const names = ['build-forge01', 'build-remilis', 'switch-forge01', 'switch-remilis'];
  assert.deepEqual(Object.keys(scripts).sort(), names);
  assert.deepEqual(Object.keys(apps).sort(), [...names, 'gc'].sort());

  for (const [name, script] of Object.entries(scripts)) {
    assert.equal(typeof script, 'string');
    const program: unknown = Reflect.get(apps, name);
    assert.ok(typeof program === 'string');
    assert.ok(program.endsWith(`/bin/darwin-${name}`));
    const separator = name.indexOf('-');
    const command = name.slice(0, separator);
    const host = name.slice(separator + 1);
    const result = spawnSync('bash', ['-c', `
      exec() { "$@"; }
      darwin-rebuild() { printf '%s\\n' "$@"; }
      sudo() { printf 'sudo\\n'; "$@"; }
      ${script}
    `, name, '--show-trace', 'argument with spaces'], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(result.stdout.trimEnd().split('\n'), [
      ...(command === 'switch' ? ['sudo'] : []),
      command,
      '--flake',
      `${realpathSync('.')}#${host}`,
      '--show-trace',
      'argument with spaces',
    ]);
  }
});

test('switch supplies its rebuild tool before nix-darwin is activated', () => {
  const build = spawnSync('nix', ['build', '--no-link', '--print-out-paths', '.#packages.aarch64-darwin.switch-forge01'], {
    encoding: 'utf8',
    timeout: 120_000,
  });
  assert.equal(build.status, 0, build.stderr);
  const directory = mkdtempSync(join(tmpdir(), 'darwin-command-'));
  try {
    const sudo = join(directory, 'sudo');
    writeFileSync(sudo, '#!/bin/sh\nprintf "%s\\n" "$@"\n');
    chmodSync(sudo, 0o755);
    const result = spawnSync(join(build.stdout.trim(), 'bin/darwin-switch-forge01'), ['--show-trace'], {
      encoding: 'utf8',
      env: { ...process.env, PATH: `${directory}:/usr/bin:/bin` },
      timeout: 30_000,
    });
    assert.equal(result.status, 0, result.stderr);
    const [rebuild, ...args] = result.stdout.trimEnd().split('\n');
    assert.match(rebuild, /^\/nix\/store\/[^/]+\/bin\/darwin-rebuild$/);
    assert.deepEqual(args, ['switch', '--flake', `${realpathSync('.')}#forge01`, '--show-trace']);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
