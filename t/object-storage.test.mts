// Behavior of the ras01 object storage scripts against real versitygw and awscli
// processes: reconcile convergence, credential lifecycle, authorization, IAM loss,
// backup/restore, and that no secret ever reaches command output.
import { strict as assert } from 'node:assert';
import { spawn, spawnSync, type ChildProcess } from 'node:child_process';
import {
  chmodSync, existsSync, linkSync, realpathSync, mkdirSync, mkdtempSync, openSync, readFileSync, readdirSync, rmSync, statSync,
  symlinkSync, writeFileSync,
} from 'node:fs';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { after, before, test } from 'node:test';

const repo = fileURLToPath(new URL('..', import.meta.url));
const scripts = join(repo, 'nixos/object-storage');
const linux = process.platform === 'linux';

function must(result: ReturnType<typeof spawnSync>, what: string): string {
  assert.equal(result.status, 0, `${what} failed: ${result.stderr}`);
  return String(result.stdout);
}

function toolPath(): string {
  const packages = ['bash', 'versitygw', 'awscli2', 'jq', 'curl', 'coreutils', 'gnused', 'gnugrep', 'gnutar', 'gzip'];
  const out = must(spawnSync('nix', ['build', '--inputs-from', repo, '--no-link', '--print-out-paths',
    ...packages.map((p) => `nixpkgs#${p}`)], { encoding: 'utf8' }), 'nix build tools');
  return [...out.trim().split('\n').map((p) => `${p}/bin`), process.env.PATH].join(':');
}

function freePort(): Promise<number> {
  return new Promise((resolve) => {
    const server = createServer().listen(0, '127.0.0.1', () => {
      const { port } = server.address() as { port: number };
      server.close(() => resolve(port));
    });
  });
}

type Ctx = {
  path: string; root: string; run: string; iamPort: number; s3Port: number; desired: string;
  iam?: ChildProcess; gateway?: ChildProcess; stub?: string; outputs: string[]; credentials: Record<string, string>;
};
let ctx: Ctx;

const stateDir = () => join(ctx.root, 'var/lib/versitygw');
const rootDir = () => join(ctx.root, 'var/lib/versitygw-root');
const rootCredentials = () => join(rootDir(), 'root-credentials');
const iamEndpoint = () => `http://127.0.0.1:${ctx.iamPort}`;
const s3Endpoint = () => `http://127.0.0.1:${ctx.s3Port}`;
const socket = () => join(ctx.run, 'iam.sock');

function env(extra: Record<string, string> = {}) {
  return {
    PATH: ctx.path, HOME: ctx.root, AWS_CONFIG_FILE: '/dev/null', AWS_SHARED_CREDENTIALS_FILE: '/dev/null',
    AWS_REGION: 'us-east-1', AWS_PAGER: '', AWS_EC2_METADATA_DISABLED: 'true',
    VGW_IAM_ENDPOINT: iamEndpoint(), VGW_S3_ENDPOINT: s3Endpoint(), VGW_ROOT_CREDENTIALS: rootCredentials(), ...extra,
  };
}

// Every script run goes through here so the final test can scan all output for secrets.
function script(name: string, args: string[], extra: Record<string, string> = {}) {
  const result = spawnSync('bash', [join(scripts, `${name}.sh`), ...args], { encoding: 'utf8', env: env(extra) });
  ctx.outputs.push(result.stdout, result.stderr);
  return result;
}

function rootAws(args: string[]) {
  const [access, secret] = readFileSync(rootCredentials(), 'utf8').split('\n');
  return spawnSync('aws', args, { encoding: 'utf8', env: env({ AWS_ACCESS_KEY_ID: access, AWS_SECRET_ACCESS_KEY: secret }) });
}
const iam = (args: string[]) => rootAws(['iam', '--endpoint-url', iamEndpoint(), '--output', 'json', ...args]);

function userS3(file: string, profile: string, args: string[], extra: Record<string, string> = {}) {
  return spawnSync('aws', ['s3api', '--endpoint-url', s3Endpoint(), '--output', 'json', ...args], {
    encoding: 'utf8', env: env({ AWS_SHARED_CREDENTIALS_FILE: file, AWS_PROFILE: profile, ...extra }),
  });
}

async function waitHealthy(url: string) {
  for (let i = 0; i < 100; i++) {
    try {
      if ((await fetch(`${url}/health`)).ok) return;
    } catch { /* not listening yet */ }
    await new Promise((r) => setTimeout(r, 200));
  }
  throw new Error(`${url} never became healthy`);
}

function launch(wrapperArgs: string[], args: string[], log: string): ChildProcess {
  const fd = openSync(join(ctx.run, log), 'a');
  return spawn('bash', [join(scripts, 'with-root-credentials.sh'), ...wrapperArgs, 'versitygw', ...args], {
    env: { ...env(), CREDENTIALS_DIRECTORY: rootDir() }, stdio: ['ignore', fd, fd],
  });
}

async function startIam() {
  mkdirSync(join(stateDir(), 'iam'), { recursive: true, mode: 0o700 });
  ctx.iam = launch([], ['--port', `127.0.0.1:${ctx.iamPort}`, '--health', '/health', 'iam', '--dir', join(stateDir(), 'iam'),
    '--private-ports', socket(), '--private-socket-perm', '0660'], 'iam.log');
  await waitHealthy(iamEndpoint());
}

async function startGateway() {
  mkdirSync(join(stateDir(), 'data'), { recursive: true, mode: 0o700 });
  ctx.gateway = launch(['--gateway'], ['--port', `127.0.0.1:${ctx.s3Port}`, '--health', '/health', '--iam-standalone-endpoint', socket(),
    '--iam-cache-disable', 'posix', join(stateDir(), 'data')], 'gateway.log');
  await waitHealthy(s3Endpoint());
}

async function stop(child?: ChildProcess) {
  if (!child || child.exitCode !== null || child.signalCode !== null) return;
  const exited = new Promise((r) => child.once('exit', r));
  child.kill('SIGTERM');
  await exited;
}

async function stopAll() {
  await stop(ctx.gateway);
  await stop(ctx.iam);
}

async function startAll() {
  await startIam();
  await startGateway();
}

function provision(args: string[]) {
  return script('provision-s3-credential', args);
}

// Issue a key into a fresh 0600 file and remember its secret for the leak scan.
function issue(command: 'create' | 'rotate', user: string): { file: string; id: string } {
  const file = join(ctx.root, `${user}-${Object.keys(ctx.credentials).length}.ini`);
  const out = must(provision([command, user, '--out', file]), `${command} ${user}`);
  const text = readFileSync(file, 'utf8');
  const id = /aws_access_key_id = (\S+)/.exec(text)![1];
  ctx.credentials[id] = /aws_secret_access_key = (\S+)/.exec(text)![1];
  assert.match(out, new RegExp(`created access key ${id} for ${user}`));
  return { file, id };
}

const keyIds = (user: string) =>
  JSON.parse(must(iam(['list-access-keys', '--user-name', user]), 'list keys')).AccessKeyMetadata
    .map((k: { AccessKeyId: string; Status: string }) => `${k.AccessKeyId}:${k.Status}`).sort();

before(async () => {
  const root = mkdtempSync(join(tmpdir(), 'object-storage-'));
  // Unix socket paths are limited to ~104 bytes, so the socket gets a short directory.
  const run = mkdtempSync('/tmp/vgw-');
  ctx = {
    path: toolPath(), root, run, iamPort: await freePort(), s3Port: await freePort(),
    desired: join(root, 'desired.json'), outputs: [], credentials: {},
  };
  const desired = must(spawnSync('nix', ['eval', '--json',
    `${repo}#nixosConfigurations.ras01.config.services.objectStorage.desiredState`], { encoding: 'utf8' }), 'nix eval desired');
  writeFileSync(ctx.desired, desired);
  must(script('root-credentials', [rootDir()]), 'root-credentials');
  await startAll();
});

after(async () => {
  if (ctx.stub) spawnSync(ctx.stub, ['stop'], { env: env() });
  await stopAll();
  rmSync(ctx.root, { recursive: true, force: true });
  rmSync(ctx.run, { recursive: true, force: true });
});

test('root credentials are created once with root-only modes and never replaced', () => {
  const before = readFileSync(rootCredentials(), 'utf8');
  assert.match(before, /^VGWROOT[0-9A-F]{20}\n[0-9a-f]{60}\n$/);
  assert.equal(statSync(rootDir()).mode & 0o777, 0o700);
  assert.equal(statSync(rootCredentials()).mode & 0o777, 0o400);
  const again = script('root-credentials', [rootDir()]);
  assert.equal(again.status, 0, again.stderr);
  assert.match(again.stdout, /root credentials present/);
  assert.equal(readFileSync(rootCredentials(), 'utf8'), before);
  const interrupted = join(ctx.root, 'interrupted');
  mkdirSync(interrupted);
  writeFileSync(join(interrupted, '.root-credentials.AbC123'), 'partial');
  must(script('root-credentials', [interrupted]), 'after interruption');
  assert.deepEqual(readdirSync(interrupted), ['root-credentials']);
});

test('reconcile creates the declared users, policies, and buckets, and a second run changes nothing', () => {
  const first = script('reconcile', [ctx.desired]);
  assert.equal(first.status, 0, first.stderr);
  for (const line of ['create user agent', 'create user publisher', 'create user versitygw-reconcile',
    'add user agent policy handoff-rw', 'add user publisher policy published-rw', 'add user versitygw-reconcile policy buckets',
    'create bucket handoff', 'create bucket published']) {
    assert.match(first.stdout, new RegExp(`applied: ${line}\\n`));
  }
  const users = JSON.parse(must(iam(['list-users']), 'list-users')).Users;
  assert.deepEqual(users.map((u: { UserName: string; Path: string }) => `${u.UserName}${u.Path}`).sort(),
    ['agent/nix-managed/', 'publisher/nix-managed/', 'versitygw-reconcile/nix-managed/']);
  const second = script('reconcile', [ctx.desired]);
  assert.equal(second.status, 0, second.stderr);
  assert.equal(second.stdout, 'reconcile: 0 change(s) applied, 0 conflict(s)\n');
});

test('the bucket creator holds an access key only while reconcile runs', () => {
  assert.deepEqual(keyIds('versitygw-reconcile'), []);
  // A key left behind by an interrupted run is removed by the next one.
  must(iam(['create-access-key', '--user-name', 'versitygw-reconcile']), 'leftover key');
  const run = script('reconcile', [ctx.desired]);
  assert.equal(run.status, 0, run.stderr);
  assert.doesNotMatch(run.stdout + run.stderr, /SecretAccessKey/);
  assert.deepEqual(keyIds('versitygw-reconcile'), []);
});

let agent: { file: string; id: string };
let publisher: { file: string; id: string };

test('create writes a 0600 credentials file, prints only the key id, and refuses a second key', () => {
  agent = issue('create', 'agent');
  publisher = issue('create', 'publisher');
  assert.equal(statSync(agent.file).mode & 0o777, 0o600);
  const again = provision(['create', 'agent', '--out', join(ctx.root, 'unused.ini')]);
  assert.equal(again.status, 1);
  assert.match(again.stderr, /already has 1 access key\(s\); use rotate/);
  assert.equal(existsSync(join(ctx.root, 'unused.ini')), false);
  const clobber = provision(['rotate', 'agent', '--out', agent.file]);
  assert.equal(clobber.status, 1);
  assert.match(clobber.stderr, /refusing to overwrite/);
  assert.deepEqual(keyIds('agent'), [`${agent.id}:Active`]);
});

test('each user reaches only its own bucket', () => {
  writeFileSync(join(ctx.root, 'obj.txt'), 'hello');
  must(userS3(agent.file, 'agent', ['put-object', '--bucket', 'handoff', '--key', 'a.txt', '--body', join(ctx.root, 'obj.txt')]), 'agent put');
  must(userS3(agent.file, 'agent', ['get-object', '--bucket', 'handoff', '--key', 'a.txt', join(ctx.root, 'got.txt')]), 'agent get');
  assert.equal(readFileSync(join(ctx.root, 'got.txt'), 'utf8'), 'hello');
  must(userS3(publisher.file, 'publisher', ['put-object', '--bucket', 'published', '--key', 'r.html', '--body', join(ctx.root, 'obj.txt')]), 'publisher put');
  for (const [file, profile, args] of [
    [agent.file, 'agent', ['list-objects-v2', '--bucket', 'published']],
    [agent.file, 'agent', ['put-object', '--bucket', 'published', '--key', 'x', '--body', join(ctx.root, 'obj.txt')]],
    [publisher.file, 'publisher', ['get-object', '--bucket', 'handoff', '--key', 'a.txt', join(ctx.root, 'x')]],
    [agent.file, 'agent', ['create-bucket', '--bucket', 'sneaky']],
    [agent.file, 'agent', ['list-buckets']],
  ] as const) {
    const denied = userS3(file, profile, [...args]);
    assert.notEqual(denied.status, 0, `${profile} ${args[0]} should be denied`);
    assert.match(denied.stderr, /AccessDenied/);
  }
});

test('a multipart upload of large handoff data works under the declared policy', () => {
  const big = join(ctx.root, 'big.bin');
  writeFileSync(big, Buffer.alloc(12 * 1024 * 1024, 7));
  const up = spawnSync('aws', ['s3', 'cp', '--endpoint-url', s3Endpoint(), big, 's3://handoff/big.bin'], {
    encoding: 'utf8', env: env({ AWS_SHARED_CREDENTIALS_FILE: agent.file, AWS_PROFILE: 'agent' }),
  });
  assert.equal(up.status, 0, up.stderr);
  const head = JSON.parse(must(userS3(agent.file, 'agent', ['head-object', '--bucket', 'handoff', '--key', 'big.bin']), 'head'));
  assert.equal(head.ContentLength, 12 * 1024 * 1024);
  assert.match(head.ETag, /-2"$/);
});

test('reconcile repairs a drifted policy, keeps manual identities, and leaves access keys alone', () => {
  const keysBefore = [keyIds('agent'), keyIds('publisher')];
  must(iam(['put-user-policy', '--user-name', 'agent', '--policy-name', 'handoff-rw', '--policy-document',
    '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:*"],"Resource":["*"]}]}']), 'drift policy');
  must(iam(['put-user-policy', '--user-name', 'agent', '--policy-name', 'manual-extra', '--policy-document',
    '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:GetObject"],"Resource":["arn:aws:s3:::published/*"]}]}']), 'extra policy');
  must(iam(['create-user', '--user-name', 'manual']), 'manual user');
  const fix = script('reconcile', [ctx.desired]);
  assert.equal(fix.status, 0, fix.stderr);
  assert.match(fix.stdout, /applied: update user agent policy handoff-rw\n/);
  assert.match(fix.stdout, /drift: user agent has undeclared inline policy manual-extra \(kept\)\n/);
  assert.match(fix.stdout, /reconcile: 1 change\(s\) applied/);
  assert.equal(script('reconcile', [ctx.desired]).stdout.split('\n').filter((l) => l.startsWith('applied')).length, 0);
  const doc = JSON.parse(must(iam(['get-user-policy', '--user-name', 'agent', '--policy-name', 'handoff-rw']), 'get policy')).PolicyDocument;
  assert.deepEqual(doc.Statement[0].Resource, ['arn:aws:s3:::handoff', 'arn:aws:s3:::handoff/*']);
  assert.equal(must(iam(['get-user', '--user-name', 'manual']), 'manual kept').includes('"Path": "/"'), true);
  assert.deepEqual([keyIds('agent'), keyIds('publisher')], keysBefore);
  must(iam(['delete-user-policy', '--user-name', 'agent', '--policy-name', 'manual-extra']), 'cleanup extra policy');
});

test('a same-named identity outside the managed path is a conflict and stays untouched', () => {
  const desired = JSON.parse(readFileSync(ctx.desired, 'utf8'));
  desired.users.manual = { policies: desired.users.agent.policies };
  // Also as the bucket creator: no key may be minted for an unmanaged user.
  desired.bucketCreator = 'manual';
  const file = join(ctx.root, 'conflict.json');
  writeFileSync(file, JSON.stringify(desired));
  const run = script('reconcile', [file]);
  assert.equal(run.status, 1);
  assert.match(run.stderr, /conflict: user manual exists outside \/nix-managed\/ \(path \/\); left untouched/);
  assert.match(run.stderr, /buckets not checked, manual is not managed/);
  assert.equal(JSON.parse(must(iam(['list-user-policies', '--user-name', 'manual']), 'policies')).PolicyNames.length, 0);
  assert.deepEqual(keyIds('manual'), []);
});

test('dry-run reports planned changes without applying them', () => {
  const desired = JSON.parse(readFileSync(ctx.desired, 'utf8'));
  desired.buckets.push('later');
  desired.users.reader = { policies: { 'read-only': { Version: '2012-10-17', Statement: [] } } };
  const file = join(ctx.root, 'dry.json');
  writeFileSync(file, JSON.stringify(desired));
  const run = script('reconcile', ['--dry-run', file]);
  assert.equal(run.status, 0, run.stderr);
  assert.match(run.stdout, /plan: create user reader\nplan: add user reader policy read-only\n/);
  assert.match(run.stdout, /plan: create bucket later\n/);
  assert.match(run.stdout, /reconcile: 3 change\(s\) planned/);
  assert.equal(iam(['get-user', '--user-name', 'reader']).status, 254);
});

test('rotate overlaps keys, and revoke waits until the new key has been used', () => {
  const rotated = issue('rotate', 'agent');
  assert.deepEqual(keyIds('agent'), [`${agent.id}:Active`, `${rotated.id}:Active`].sort());
  must(userS3(agent.file, 'agent', ['head-object', '--bucket', 'handoff', '--key', 'a.txt']), 'old key still works');
  const third = provision(['rotate', 'agent', '--out', join(ctx.root, 'third.ini')]);
  assert.equal(third.status, 1);
  assert.match(third.stderr, /rotate needs exactly one existing key, agent has 2/);
  const early = provision(['revoke', 'agent', agent.id]);
  assert.equal(early.status, 1);
  assert.match(early.stderr, new RegExp(`replacement key ${rotated.id} has never been used`));
  must(userS3(rotated.file, 'agent', ['head-object', '--bucket', 'handoff', '--key', 'a.txt']), 'new key works');
  const listed = must(provision(['list', 'agent']), 'list');
  assert.match(listed, new RegExp(`${rotated.id}\\tActive\\t\\S+\\t\\d{4}-`));
  assert.match(must(provision(['revoke', 'agent', agent.id]), 'revoke'), new RegExp(`revoked access key ${agent.id} of agent`));
  const old = userS3(agent.file, 'agent', ['head-object', '--bucket', 'handoff', '--key', 'a.txt']);
  assert.notEqual(old.status, 0);
  assert.deepEqual(keyIds('agent'), [`${rotated.id}:Active`]);
  const last = provision(['revoke', 'agent', rotated.id]);
  assert.equal(last.status, 1);
  assert.match(last.stderr, /last active key of agent; pass --force/);
  agent = rotated;
});

test('the stored root cannot sign S3 requests, so authenticated S3 requests depend on IAM', () => {
  for (const args of [['list-buckets'], ['head-object', '--bucket', 'handoff', '--key', 'a.txt'], ['create-bucket', '--bucket', 'by-root']]) {
    const denied = rootAws(['s3api', '--endpoint-url', s3Endpoint(), ...args]);
    assert.notEqual(denied.status, 0, `root ${args[0]} must be refused`);
    // HEAD responses carry no error body, only the status.
    assert.match(denied.stderr, args[0] === 'head-object' ? /\(403\)/ : /signature we calculated does not match/);
  }
});

test('new authenticated S3 requests are denied while IAM is stopped or hung, and resume with IAM', async () => {
  const once = { AWS_MAX_ATTEMPTS: '1' };
  const head = ['head-object', '--bucket', 'handoff', '--key', 'a.txt'];
  const rootHead = () => rootAws(['s3api', '--endpoint-url', s3Endpoint(), ...head]);
  await stop(ctx.iam);
  const down = userS3(agent.file, 'agent', head, once);
  assert.notEqual(down.status, 0, 'user request must fail while IAM is down');
  assert.match(down.stderr, /500|InternalError|Internal Server Error/);
  assert.notEqual(rootHead().status, 0, 'root request must fail while IAM is down');
  await startIam();
  must(userS3(agent.file, 'agent', head), 'works after IAM returns');

  ctx.iam!.kill('SIGSTOP');
  try {
    const started = Date.now();
    const hung = userS3(agent.file, 'agent', head, once);
    assert.notEqual(hung.status, 0, 'user request must fail while IAM is hung');
    assert.match(hung.stderr, /500|InternalError|Internal Server Error/);
    assert.ok(Date.now() - started < 30_000, 'the gateway gives up on a hung IAM');
    assert.notEqual(rootHead().status, 0, 'root request must fail while IAM is hung');
  } finally {
    ctx.iam!.kill('SIGCONT');
  }
  must(userS3(agent.file, 'agent', head), 'works after IAM resumes');
});

// Stands in for systemctl the way the units behave: stop ends the daemons and waits
// until they stop answering, start launches them from whatever state is in place.
function serviceStub(): { path: string; calls: string } {
  const path = join(ctx.root, 'systemctl');
  const calls = join(ctx.root, 'systemctl.log');
  const wrapper = join(scripts, 'with-root-credentials.sh');
  const launch = (args: string, log: string, pid: string) =>
    `CREDENTIALS_DIRECTORY=${rootDir()} nohup bash ${wrapper} ${args} >> ${join(ctx.run, log)} 2>&1 < /dev/null &\n` +
    `echo $! > ${join(ctx.run, pid)}\n`;
  writeFileSync(path, `#!/usr/bin/env bash
echo "$*" >> ${calls}
case $1 in
  stop)
    for f in ${ctx.run}/*.pid; do
      [[ -e $f ]] || continue
      kill "$(cat "$f")" 2>/dev/null || true
      rm -f "$f"
    done
    while curl -fsS -o /dev/null ${iamEndpoint()}/health 2>/dev/null || curl -fsS -o /dev/null ${s3Endpoint()}/health 2>/dev/null; do
      sleep 0.1
    done
    ;;
  start)
    ${launch(`versitygw --port 127.0.0.1:${ctx.iamPort} --health /health iam --dir ${join(stateDir(), 'iam')} --private-ports ${socket()} --private-socket-perm 0660`, 'iam.log', 'iam.pid')}
    ${launch(`--gateway versitygw --port 127.0.0.1:${ctx.s3Port} --health /health --iam-standalone-endpoint ${socket()} --iam-cache-disable posix ${join(stateDir(), 'data')}`, 'gateway.log', 'gateway.pid')}
    ;;
esac
`);
  chmodSync(path, 0o755);
  ctx.stub = path;
  return { path, calls };
}

test('backup and restore bring back IAM state, keys, policies, and objects on a fresh install', { skip: !linux && 'GNU tar has no xattr support on darwin; runs on Linux' }, async () => {
  const { path: systemctl, calls } = serviceStub();
  const pids = () => { writeFileSync(join(ctx.run, 'iam.pid'), String(ctx.iam!.pid)); writeFileSync(join(ctx.run, 'gateway.pid'), String(ctx.gateway!.pid)); };
  // Adjacent dots are an ordinary object name, not a path component.
  must(userS3(agent.file, 'agent', ['put-object', '--bucket', 'handoff', '--key', 'release..json', '--body', join(ctx.root, 'obj.txt')]), 'dotted put');
  const etag = JSON.parse(must(userS3(agent.file, 'agent', ['head-object', '--bucket', 'handoff', '--key', 'a.txt']), 'head')).ETag;
  const policy = must(iam(['get-user-policy', '--user-name', 'agent', '--policy-name', 'handoff-rw']), 'policy');
  const oldRoot = readFileSync(rootCredentials(), 'utf8');
  const dest = join(ctx.root, 'backups');
  mkdirSync(dest);
  // Archived setuid/setgid bits on the state parent must not survive a restore.
  chmodSync(stateDir(), 0o6755);
  pids();
  const backupEnv = { VGW_BACKUP_ROOT: ctx.root, VGW_SYSTEMCTL: systemctl };
  const made = script('versitygw-backup', ['create', dest], backupEnv);
  assert.equal(made.status, 0, made.stderr);
  const [archive] = readdirSync(dest);
  assert.match(archive, /^versitygw-\d{8}T\d{6}Z\.tar\.gz$/);
  assert.equal(statSync(join(dest, archive)).mode & 0o777, 0o600);
  assert.deepEqual(readFileSync(calls, 'utf8').split('\n').filter(Boolean),
    ['stop versitygw-reconcile.service versitygw.service versitygw-iam.service', 'start versitygw-reconcile.service']);

  // A fresh machine: new root account, empty IAM, declarations re-applied.
  must(spawnSync(systemctl, ['stop'], { encoding: 'utf8', env: env() }), 'stop restarted daemons');
  await stopAll();
  rmSync(stateDir(), { recursive: true });
  rmSync(rootDir(), { recursive: true });
  must(script('root-credentials', [rootDir()]), 'fresh root');
  ctx.credentials['fresh-root'] = readFileSync(rootCredentials(), 'utf8').split('\n')[1];
  assert.notEqual(readFileSync(rootCredentials(), 'utf8'), oldRoot);
  await startAll();
  must(script('reconcile', [ctx.desired]), 'fresh reconcile');
  assert.notEqual(userS3(agent.file, 'agent', ['head-object', '--bucket', 'handoff', '--key', 'a.txt']).status, 0);

  pids();
  // Restore only reports success once the restarted services answer with the restored root.
  const restored = script('versitygw-backup', ['restore', join(dest, archive)], backupEnv);
  assert.equal(restored.status, 0, restored.stderr);
  assert.ok(readdirSync(join(ctx.root, 'var/lib')).some((n) => n.startsWith('versitygw.pre-restore-')));
  assert.equal(readFileSync(rootCredentials(), 'utf8'), oldRoot);
  assert.equal(statSync(stateDir()).mode & 0o7777, 0o755);
  assert.equal(JSON.parse(must(userS3(agent.file, 'agent', ['head-object', '--bucket', 'handoff', '--key', 'a.txt']), 'restored head')).ETag, etag);
  assert.equal(must(iam(['get-user-policy', '--user-name', 'agent', '--policy-name', 'handoff-rw']), 'restored policy'), policy);
  must(userS3(agent.file, 'agent', ['head-object', '--bucket', 'handoff', '--key', 'release..json']), 'dotted object restored');
  assert.match(userS3(agent.file, 'agent', ['list-objects-v2', '--bucket', 'published']).stderr, /AccessDenied/);
  assert.match(script('reconcile', [ctx.desired]).stdout, /reconcile: 0 change\(s\) applied/);
});

// A restore target with sentinel state, plus archives built from a tree of required files.
function restoreFixture(name: string, startExit = 0) {
  const target = join(ctx.root, `${name}-target`);
  for (const dir of ['var/lib/versitygw/iam', 'var/lib/versitygw/data', 'var/lib/versitygw-root']) {
    mkdirSync(join(target, dir), { recursive: true });
  }
  writeFileSync(join(target, 'var/lib/versitygw/iam/iam.json'), 'current');
  writeFileSync(join(target, 'var/lib/versitygw-root/root-credentials'), 'current\n');
  writeFileSync(join(target, 'outside'), 'outside');
  const tree = join(ctx.root, `${name}-tree`);
  for (const dir of ['var/lib/versitygw/iam', 'var/lib/versitygw/data', 'var/lib/versitygw-root']) {
    mkdirSync(join(tree, dir), { recursive: true });
  }
  writeFileSync(join(tree, 'var/lib/versitygw/iam/iam.json'), '{"users":{}}');
  writeFileSync(join(tree, 'var/lib/versitygw-root/root-credentials'), 'VGWROOTARCHIVED\narchived\n');
  const calls = join(ctx.root, `${name}-systemctl.log`);
  const systemctl = join(ctx.root, `${name}-systemctl`);
  writeFileSync(systemctl, `#!/usr/bin/env bash\necho "$*" >> ${calls}\n[[ $1 == start ]] && exit ${startExit}\nexit 0\n`);
  chmodSync(systemctl, 0o755);
  const tar = (args: string[]) => must(spawnSync('tar', args, { encoding: 'utf8', env: env() }), `tar ${args[0]}`);
  const restore = (archive: string, extra: Record<string, string> = {}) =>
    script('versitygw-backup', ['restore', archive], { VGW_BACKUP_ROOT: target, VGW_SYSTEMCTL: systemctl, ...extra });
  const calledSystemctl = () => existsSync(calls);
  const untouched = () => {
    assert.equal(readFileSync(join(target, 'var/lib/versitygw/iam/iam.json'), 'utf8'), 'current');
    assert.equal(readFileSync(join(target, 'outside'), 'utf8'), 'outside');
    assert.deepEqual(readdirSync(join(target, 'var/lib')).sort(), ['versitygw', 'versitygw-root']);
  };
  return { target, tree, tar, restore, calledSystemctl, untouched, archive: join(ctx.root, `${name}.tar.gz`) };
}

test('restore refuses unusable or hostile archives before stopping anything', () => {
  const cases: [string, (f: ReturnType<typeof restoreFixture>) => void, RegExp][] = [
    ['corrupt', (f) => writeFileSync(f.archive, 'not a gzip stream'), /cannot read/],
    ['foreign', (f) => {
      mkdirSync(join(f.tree, 'etc'));
      writeFileSync(join(f.tree, 'etc/passwd'), 'x');
      f.tar(['--create', '--gzip', '-C', f.tree, '-f', f.archive, 'etc', 'var']);
    }, /unexpected archive member etc/],
    ['incomplete', (f) => {
      rmSync(join(f.tree, 'var/lib/versitygw-root'), { recursive: true });
      f.tar(['--create', '--gzip', '-C', f.tree, '-f', f.archive, 'var']);
    }, /lacks the root credentials/],
    ['malformed-root', (f) => {
      writeFileSync(join(f.tree, 'var/lib/versitygw-root/root-credentials'), 'only-one-line\n');
      f.tar(['--create', '--gzip', '-C', f.tree, '-f', f.archive, 'var']);
    }, /root-credentials is not an access key id and a secret/],
    ['malformed-iam', (f) => {
      writeFileSync(join(f.tree, 'var/lib/versitygw/iam/iam.json'), '{truncated');
      f.tar(['--create', '--gzip', '-C', f.tree, '-f', f.archive, 'var']);
    }, /iam.json is not VersityGW IAM state/],
    ['bad-schema', (f) => {
      writeFileSync(join(f.tree, 'var/lib/versitygw/iam/iam.json'), '{"users":"invalid"}');
      f.tar(['--create', '--gzip', '-C', f.tree, '-f', f.archive, 'var']);
    }, /iam.json is not VersityGW IAM state/],
    ['extra', (f) => {
      writeFileSync(join(f.tree, 'var/lib/versitygw/extra'), 'x');
      f.tar(['--create', '--gzip', '-C', f.tree, '-f', f.archive, 'var']);
    }, /unexpected archive member var\/lib\/versitygw\/extra/],
    ['symlink', (f) => {
      symlinkSync(join(f.target, 'outside'), join(f.tree, 'var/lib/versitygw/data/link'));
      f.tar(['--create', '--gzip', '-C', f.tree, '-f', f.archive, 'var']);
    }, /entries other than regular files and directories/],
    ['hardlink', (f) => {
      // A hard link member whose target is not in the archive, pointing at a file
      // that exists next to the real state.
      writeFileSync(join(f.tree, 'outside'), 'outside');
      linkSync(join(f.tree, 'outside'), join(f.tree, 'var/lib/versitygw/data/escape'));
      const plain = f.archive.replace(/\.gz$/, '');
      f.tar(['--create', '-C', f.tree, '-f', plain, 'outside', 'var']);
      f.tar(['--delete', '-f', plain, 'outside']);
      must(spawnSync('gzip', [plain], { env: env() }), 'gzip');
    }, /entries other than regular files and directories/],
  ];
  for (const [name, build, message] of cases) {
    const f = restoreFixture(name);
    build(f);
    const run = f.restore(f.archive);
    assert.equal(run.status, 1, `${name}: ${run.stderr}`);
    assert.match(run.stderr, message, name);
    assert.equal(f.calledSystemctl(), false, `${name} must not stop services`);
    f.untouched();
  }
});

test('a restore that fails after stopping the services puts the previous state back', () => {
  const f = restoreFixture('rollback');
  f.tar(['--create', '--gzip', '-C', f.tree, '-f', f.archive, 'var']);
  const run = f.restore(f.archive, { VGW_GATEWAY_OWNER: 'no-such-user-vgw:no-such-group-vgw' });
  assert.equal(run.status, 1);
  assert.match(run.stderr, /restore failed; the previous state is back in place/);
  f.untouched();
  assert.deepEqual(readFileSync(join(ctx.root, 'rollback-systemctl.log'), 'utf8').split('\n').filter(Boolean),
    ['stop versitygw-reconcile.service versitygw.service versitygw-iam.service', 'start versitygw-reconcile.service']);
});

test('a restore whose services do not come up puts the previous state back', async () => {
  const stopStart = ['stop versitygw-reconcile.service versitygw.service versitygw-iam.service', 'start versitygw-reconcile.service'];
  // Services fail to start.
  const failing = restoreFixture('start-fails', 1);
  failing.tar(['--create', '--gzip', '-C', failing.tree, '-f', failing.archive, 'var']);
  const run = failing.restore(failing.archive);
  assert.equal(run.status, 1);
  assert.match(run.stderr, /did not come up; rolling back/);
  failing.untouched();
  assert.deepEqual(readFileSync(join(ctx.root, 'start-fails-systemctl.log'), 'utf8').split('\n').filter(Boolean), [...stopStart, ...stopStart]);
  // Services start but IAM rejects the restored root account.
  const silent = restoreFixture('no-answer');
  silent.tar(['--create', '--gzip', '-C', silent.tree, '-f', silent.archive, 'var']);
  const quiet = silent.restore(silent.archive, { VGW_RESTORE_TIMEOUT: '2' });
  assert.equal(quiet.status, 1);
  assert.match(quiet.stderr, /did not come up; rolling back/);
  silent.untouched();
  // The gateway accepts connections but never answers: the deadline still holds.
  // The kernel accepts on the listen backlog even while spawnSync blocks this process.
  const mute = createServer(() => {}).listen(0, '127.0.0.1');
  await new Promise((r) => mute.once('listening', r));
  const hung = restoreFixture('hung');
  hung.tar(['--create', '--gzip', '-C', hung.tree, '-f', hung.archive, 'var']);
  const started = Date.now();
  const stuck = hung.restore(hung.archive, {
    VGW_RESTORE_TIMEOUT: '3', VGW_S3_ENDPOINT: `http://127.0.0.1:${(mute.address() as { port: number }).port}`,
  });
  mute.close();
  assert.equal(stuck.status, 1);
  assert.match(stuck.stderr, /did not come up; rolling back/);
  assert.ok(Date.now() - started < 15000, `restore took ${Date.now() - started} ms`);
  hung.untouched();
});

test('credentials are only delivered into directories other users cannot rearrange', () => {
  const before = keyIds('publisher');
  // Sticky does not help in the destination itself: the recipient could swap a file it owns there.
  for (const [name, mode] of [['shared-dir', 0o777], ['sticky-dir', 0o1777]] as const) {
    const dir = join(ctx.root, name);
    mkdirSync(dir);
    chmodSync(dir, mode);
    const run = provision(['rotate', 'publisher', '--out', join(dir, 'p.ini')]);
    assert.equal(run.status, 1, name);
    assert.match(run.stderr, new RegExp(`${name} is writable by other users`));
    assert.deepEqual(readdirSync(dir), [], name);
  }
  // A path through a symlink is used only in its checked, physical form, so a writable
  // directory holding the symlink cannot redirect the later steps.
  const open = join(ctx.root, 'open-dir');
  const real = join(ctx.root, 'real-private');
  mkdirSync(open);
  mkdirSync(real, { mode: 0o700 });
  chmodSync(open, 0o777);
  symlinkSync(real, join(open, 'route'));
  const routed = provision(['rotate', 'publisher', '--out', join(open, 'route', 'p.ini')]);
  assert.equal(routed.status, 0, routed.stderr);
  assert.ok(routed.stdout.includes(`in ${realpathSync(real)}/p.ini`), routed.stdout);
  const routedId = /created access key (\S+)/.exec(routed.stdout)![1];
  ctx.credentials[routedId] = /aws_secret_access_key = (\S+)/.exec(readFileSync(join(real, 'p.ini'), 'utf8'))![1];
  must(provision(['revoke', 'publisher', routedId, '--force']), 'revoke routed key');
  // A sticky ancestor is fine when the destination itself is private.
  const sticky = join(ctx.root, 'sticky-parent');
  mkdirSync(join(sticky, 'private'), { recursive: true });
  chmodSync(sticky, 0o1777);
  chmodSync(join(sticky, 'private'), 0o700);
  const ok = issue('rotate', 'publisher');
  assert.equal(statSync(ok.file).mode & 0o777, 0o600);
  must(provision(['revoke', 'publisher', ok.id, '--force']), 'revoke trial key');
  const inSticky = provision(['rotate', 'publisher', '--out', join(sticky, 'private', 'p.ini')]);
  assert.equal(inSticky.status, 0, inSticky.stderr);
  const id = /created access key (\S+)/.exec(inSticky.stdout)![1];
  ctx.credentials[id] = /aws_secret_access_key = (\S+)/.exec(readFileSync(join(sticky, 'private', 'p.ini'), 'utf8'))![1];
  must(provision(['revoke', 'publisher', id, '--force']), 'revoke sticky key');
  assert.deepEqual(keyIds('publisher'), before);
});

test('no command output contains the root secret or any issued secret', () => {
  const secrets = [readFileSync(rootCredentials(), 'utf8').split('\n')[1], ...Object.values(ctx.credentials)];
  assert.ok(secrets.length >= 4);
  const logs = ['iam.log', 'gateway.log'].map((f) => readFileSync(join(ctx.run, f), 'utf8'));
  for (const text of [...ctx.outputs, ...logs]) {
    for (const secret of secrets) assert.equal(text.includes(secret), false, 'a secret leaked into output');
  }
});
