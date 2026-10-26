import { strict as assert } from 'node:assert';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { test } from 'node:test';

const moduleText = readFileSync(new URL('../home/pi/default.nix', import.meta.url), 'utf8');
const revision = moduleText.match(/pstackRevision = "([a-f0-9]{40})";/)![1];
const source = `git:github.com/michael-denyer/pstack-claude@${revision}`;
const block = moduleText.slice(moduleText.indexOf('    source="git:'), moduleText.indexOf("\n  '';", moduleText.indexOf('    source="git:')))
  .replaceAll('${pstackRevision}', revision);

function run(packages: unknown[], checkoutRevision: string, installExit = 0) {
  const cache = new URL('../.agents/cache/', import.meta.url);
  mkdirSync(cache, { recursive: true });
  const dir = mkdtempSync(new URL('pi-pstack-test-', cache).pathname);
  try {
    const settings = join(dir, 'settings.json');
    writeFileSync(settings, JSON.stringify({ packages }));
    writeFileSync(join(dir, 'git'), '#!/bin/bash\nprintf "%s" "$CHECKOUT_REVISION"\n', { mode: 0o755 });
    writeFileSync(join(dir, 'pi'), '#!/bin/bash\nprintf "%s\\n" "$@"\nexit "$INSTALL_EXIT"\n', { mode: 0o755 });
    return spawnSync('/bin/bash', ['-e', '-c', block], {
      encoding: 'utf8',
      env: {
        ...process.env,
        HOME: dir,
        PATH: `${dir}:${process.env.PATH}`,
        settings,
        CHECKOUT_REVISION: checkoutRevision,
        INSTALL_EXIT: String(installExit),
      },
    });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

for (const entry of [source, { source, skills: [] }]) {
  test(`skips an installed pin with a ${typeof entry} settings entry`, () => {
    const result = run([entry], revision);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /already installed/);
    assert.doesNotMatch(result.stdout, /^install$/m);
  });
}

for (const [name, packages, checkout] of [
  ['fresh install', [], ''],
  ['unregistered checkout', [], revision],
  ['missing checkout', [source], ''],
  ['different revision', [source], 'old-revision'],
] as const) {
  test(`installs the pinned source: ${name}`, () => {
    const result = run([...packages], checkout);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, `install\n${source}\n`);
  });
}

test('propagates installation failure', () => {
  assert.equal(run([], '', 1).status, 1);
});
