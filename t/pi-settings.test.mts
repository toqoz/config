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
    defaultProvider: 'openai-codex',
    defaultModel: 'gpt-6.1-sol',
    defaultThinkingLevel: 'medium',
    extensions: ['-builtin:mcp'],
    packages: [],
  });
});

test('removes old pstack registrations while preserving other packages and settings', () => {
  const kept = [
    'git:github.com/michael-denyer/pstack-claude-tools@main',
    'git:github.com/another-owner/pstack-claude@main',
  ];
  const removed = [
    'npm:pi-intercom@0.18.1',
    { source: 'npm:pi-subagents@0.82.1', extensions: ['custom.ts'] },
    'git:github.com/michael-denyer/pstack-claude@356c6e0f978df729eb16f227d795f34d221c5aad',
    { source: 'git:github.com/michael-denyer/pstack-claude@main', skills: [] },
    'git:https://github.com/michael-denyer/pstack-claude.git#main',
    'git:github.com/michael-denyer/pstack-claude',
  ];
  const result = configure({ packages: [...removed, ...kept], extensions: ['local.ts'], theme: 'dark' });
  assert.deepEqual(result.packages, kept);
  assert.deepEqual(result.extensions, ['local.ts', '-builtin:mcp']);
  assert.equal(result.theme, 'dark');
});

test('repeated activation does not change the resulting settings', () => {
  const once = configure({ packages: ['npm:another-package@1.0.0'], extensions: ['-builtin:mcp'] });
  assert.deepEqual(configure(once), once);
});
