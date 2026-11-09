import { strict as assert } from 'node:assert';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const hook = fileURLToPath(new URL('../home/zsh/agent-direnv.zsh', import.meta.url));

test('T3 non-interactive zsh loads and unloads direnv on directory changes', () => {
  const root = mkdtempSync(join(tmpdir(), 'agent-direnv-'));
  try {
    const project = join(root, 'project');
    mkdirSync(project);
    writeFileSync(join(project, '.envrc'), 'export AGENT_DIRENV_TEST=loaded\n');
    const env = { ...process.env, XDG_DATA_HOME: join(root, 'data'), XDG_CONFIG_HOME: join(root, 'config'), DIRENV_LOG_FORMAT: '', T3CODE_THREAD_ID: 'test', AGENT_HOOK: hook, AGENT_PROJECT: project, AGENT_ROOT: root };
    delete env.DIRENV_DIR;
    delete env.DIRENV_DIFF;
    delete env.DIRENV_WATCHES;
    const allow = spawnSync('direnv', ['allow', project], { env, encoding: 'utf8' });
    assert.equal(allow.status, 0, allow.stderr);
    const script = 'source "$AGENT_HOOK"; print -r -- "${AGENT_DIRENV_TEST-unset}"; cd "$AGENT_PROJECT"; print -r -- "${AGENT_DIRENV_TEST-unset}"; cd "$AGENT_ROOT"; print -r -- "${AGENT_DIRENV_TEST-unset}"';
    const result = spawnSync('zsh', ['-f', '-c', script], { cwd: root, env, encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, 'unset\nloaded\nunset\n');
    const startInProject = spawnSync('zsh', ['-f', '-c', 'source "$AGENT_HOOK"; print -r -- "${AGENT_DIRENV_TEST-unset}"'], { cwd: project, env, encoding: 'utf8' });
    assert.equal(startInProject.status, 0, startInProject.stderr);
    assert.equal(startInProject.stdout, 'loaded\n');
    const noAgent = spawnSync('zsh', ['-f', '-c', script], { cwd: root, env: { ...env, T3CODE_THREAD_ID: '' }, encoding: 'utf8' });
    assert.equal(noAgent.status, 0, noAgent.stderr);
    assert.equal(noAgent.stdout, 'unset\nunset\nunset\n');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
