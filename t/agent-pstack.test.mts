// Keep the DSH adapter for pstack consistent with the Pi install.
//
// The DSH side pins pstack for `programs.agent-skills` while the Pi side pins
// the same revision for `pi install`. Two pins, one upstream: the test fails
// when they drift, and when the curated skill list loses a skill the adapter
// depends on.
//
// Run from the repo root:
//   node --test t/*.test.mts

import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const dshText = readFileSync(new URL('../home/agents/pstack/default.nix', import.meta.url), 'utf8');
const piText = readFileSync(new URL('../home/pi/default.nix', import.meta.url), 'utf8');
const skillText = readFileSync(
  new URL('../home/agents/skills/pstack-dsh/SKILL.md', import.meta.url),
  'utf8',
);

function dshRevision(): string {
  const match = dshText.match(/rev = "([a-f0-9]{40})";/);
  assert.ok(match, 'home/agents/pstack/default.nix must pin a 40-character revision');
  return match[1]!;
}

function piRevision(): string {
  const match = piText.match(/pstackRevision = "([a-f0-9]{40})";/);
  assert.ok(match, 'home/pi/default.nix must pin pstackRevision');
  return match[1]!;
}

function enabledSkills(): string[] {
  const start = dshText.indexOf('enabled = [');
  const end = dshText.indexOf('];', start);
  assert.ok(start !== -1 && end !== -1, 'the module must declare an `enabled` list');
  return [...dshText.slice(start, end).matchAll(/"([a-z0-9-]+)"/g)].map((m) => m[1]!);
}

test('the DSH pin matches the Pi pin', () => {
  assert.equal(dshRevision(), piRevision());
});

test('the DSH source hash is an SRI sha256', () => {
  const match = dshText.match(/hash = "(sha256-[A-Za-z0-9+/=]+)";/);
  assert.ok(match, 'the fetchgit call must pin a sha256 hash');
});

test('the curated set is duplicate-free', () => {
  const skills = enabledSkills();
  assert.ok(skills.length > 0);
  assert.equal(new Set(skills).size, skills.length, 'duplicate skill id in `enabled`');
});

test('the adapter depends only on skills the module enables', () => {
  const skills = enabledSkills();
  for (const required of ['poteto-mode', 'unslop', 'deslop']) {
    assert.ok(skills.includes(required), `${required} must stay enabled`);
  }
});

test('every enabled principle has a matching pstack skill name', () => {
  for (const name of enabledSkills().filter((n) => n.startsWith('principle-'))) {
    assert.match(name, /^principle-[a-z0-9]+(-[a-z0-9]+)*$/);
  }
});

test('the pstack-dsh skill declares usable frontmatter', () => {
  assert.ok(skillText.startsWith('---\n'), 'SKILL.md must start with frontmatter');

  const frontmatter = skillText.slice(4, skillText.indexOf('\n---\n', 4));
  const name = frontmatter.match(/^name: (\S+)$/m);
  const description = frontmatter.match(/^description: (.+)$/m);

  assert.equal(name?.[1], 'pstack-dsh');
  assert.ok(description, 'the skill needs a description for catalogue matching');
  assert.ok(description![1]!.length > 0);
});
