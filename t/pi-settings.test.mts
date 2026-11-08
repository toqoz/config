import { strict as assert } from 'node:assert';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const filter = fileURLToPath(new URL('../home/pi/settings.jq', import.meta.url));

function configure(settings: unknown) {
  const result = spawnSync('jq', ['-f', filter], {
    input: JSON.stringify(settings),
    encoding: 'utf8',
  });
  assert.equal(result.status, 0, result.stderr);
  return JSON.parse(result.stdout);
}

test('new Pi settings retain the configured provider and MCP adapter behavior', () => {
  assert.deepEqual(configure(null), {
    defaultProvider: 'ollama',
    defaultModel: 'deepseek-v4.1-flash:cloud',
    defaultThinkingLevel: 'low',
    extensions: ['-builtin:mcp'],
    packages: [],
  });
});

test('preserves existing packages and settings', () => {
  const packages = ['npm:another-package@1.0.0', { source: 'npm:custom@1.0.0', extensions: ['custom.ts'] }];
  const result = configure({ packages, extensions: ['local.ts'], theme: 'dark' });
  assert.deepEqual(result.packages, packages);
  assert.deepEqual(result.extensions, ['local.ts', '-builtin:mcp']);
  assert.equal(result.theme, 'dark');
});

test('repeated activation does not change the resulting settings', () => {
  const once = configure({ packages: ['npm:another-package@1.0.0'], extensions: ['-builtin:mcp'] });
  assert.deepEqual(configure(once), once);
});
