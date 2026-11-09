import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, readlinkSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

test('links the decrypted identity and protects existing files', () => {
  const root = mkdtempSync(join(tmpdir(), 'git-identity-'));
  try {
    const context = join(root, 'context');
    const base = join(root, 'github');
    const target = join(base, 'example-org');
    mkdirSync(join(context, 'gh'), { recursive: true });
    mkdirSync(target, { recursive: true });
    writeFileSync(join(context, 'org'), 'example-org');
    writeFileSync(join(context, 'user'), 'example-user');
    writeFileSync(join(context, 'author_name'), 'Example Author');
    writeFileSync(join(context, 'author_email'), 'author@example.org');
    writeFileSync(join(context, 'envrc'), 'test');
    const hosts = join(root, 'hosts-template');
    const config = join(root, 'config-template');
    writeFileSync(hosts, 'initial hosts');
    writeFileSync(config, 'initial config');
    symlinkSync(hosts, join(context, 'gh', 'hosts.yml'));
    symlinkSync(join(root, 'old'), join(target, '.envrc'));
    const run = () => spawnSync('bash', ['scripts/link-git-identity.sh', context, base, hosts, config]);
    assert.equal(run().status, 0);
    const copiedHosts = join(context, 'gh', 'hosts.yml');
    const copiedConfig = join(context, 'gh', 'config.yml');
    assert.equal(readFileSync(copiedHosts, 'utf8'), 'initial hosts');
    assert.equal(statSync(copiedHosts).mode & 0o777, 0o600);
    assert.equal(readFileSync(copiedConfig, 'utf8'), 'initial config');
    assert.equal(readlinkSync(join(target, '.envrc')), join(context, 'envrc'));
    assert.equal(readlinkSync(join(target, '.gh')), join(context, 'gh'));
    writeFileSync(copiedHosts, 'updated by gh');
    writeFileSync(copiedConfig, 'updated config');
    assert.equal(run().status, 0);
    assert.equal(readFileSync(copiedHosts, 'utf8'), 'updated by gh');
    assert.equal(readFileSync(copiedConfig, 'utf8'), 'updated config');
    writeFileSync(join(context, 'author_name'), "O'Example");
    assert.notEqual(run().status, 0);
    writeFileSync(join(context, 'author_name'), 'Example Author');
    rmSync(join(target, '.envrc'));
    writeFileSync(join(target, '.envrc'), 'existing');
    assert.notEqual(run().status, 0);
    writeFileSync(join(context, 'org'), '../escape');
    assert.notEqual(run().status, 0);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
