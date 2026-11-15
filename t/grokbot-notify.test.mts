import { strict as assert } from 'node:assert';
import { execFileSync, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

test('Grok Bot notification admission, lifecycle, durable delivery and HTTP behavior', () => {
  const result = spawnSync('python3', ['-B', '-W', 'error::ResourceWarning', '-m', 'unittest',
    'discover', '-s', fileURLToPath(new URL('../home/agents/grokbot-notify', import.meta.url)),
    '-p', 'test_*.py', '-v'], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stdout + result.stderr);
});

test('each host wires synchronous hooks to a stable command and a separate delivery worker', () => {
  const hosts = JSON.parse(execFileSync('nix', ['eval', '--json', '.#darwinConfigurations', '--apply',
    `(hosts: builtins.mapAttrs (_: host: let hm = builtins.head (builtins.attrValues host.config.home-manager.users); in {
      command = hm.my.grokbotNotify.command;
      claude = hm.programs.claude-code.settings.hooks;
      pi = hm.home.file.".pi/agent/extensions/grokbot-notify.ts".text;
      worker = hm.launchd.agents.grokbot-notify.config;
      stateHome = hm.xdg.stateHome;
    }) hosts)`], { encoding: 'utf8' }));
  for (const name of Object.keys(hosts)) {
    const host = hosts[name];
    assert.ok(!host.command.startsWith('/nix/store/'), 'hook trust must survive package updates');
    for (const event of ['UserPromptSubmit', 'Stop', 'StopFailure', 'PreToolUse']) {
      const hook = host.claude[event][0].hooks[0];
      assert.equal(hook.command, `${host.command} hook claude`);
      assert.notEqual(hook.async, true);
    }
    assert.ok(host.pi.includes(JSON.stringify(host.command)));
    assert.ok(!host.pi.includes('@GROKBOT_NOTIFY@'));
    assert.equal(host.worker.ProgramArguments.at(-1), 'drain');
    assert.equal(host.worker.EnvironmentVariables.XDG_STATE_HOME, host.stateHome);
    assert.ok(host.worker.StartInterval > 0);
  }
});
