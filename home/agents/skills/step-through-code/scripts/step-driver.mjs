#!/usr/bin/env node
// step-driver: event-driven Node.js step debugger over CDP (Node >= 24, no dependencies).
//
// A `serve` session owns one target Node process started with
// --inspect-brk=127.0.0.1:0 and accepts one command at a time over a Unix
// socket in the session directory. Every command returns when the matching
// protocol event (pause, exit) arrives or its bounded timeout elapses.
//
// See `node step-driver.mjs --help`.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import net from 'node:net';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const USAGE = `usage:
  step-driver.mjs serve <dir> [--startup-timeout-ms N] -- <node-args...>
      Start a session: spawn \`node --inspect-brk=127.0.0.1:0 <node-args...>\`,
      attach, run to the initial pause, then serve commands on <dir>/ctl.sock.
      <dir> must be new or empty. Runs until \`stop\` or SIGINT/SIGTERM/SIGHUP;
      the session stays alive after the target exits so \`report\` still works.
  step-driver.mjs <dir> <command> [args...]
      Send one command to the session in <dir> and print the JSON result.
      Waits (bounded) for the session socket if serve is still starting.

commands (one at a time; a concurrent command is rejected with "busy"):
  where                     current state: paused location/reason/hits, running, or exited
  stack                     paused call frames
  source [--context N]      executed script text around the paused line (default 5)
  bp <url|abs-path|suffix> <line>
                            breakpoint at 1-based <line>. A suffix must match one
                            loaded script; unmatched suffixes stay pending.
  bps                       breakpoints with accepted/resolved/hit state
  next|step|out|continue --expect <text> [--timeout-ms N]
                            log the prediction, advance, return the actual outcome:
                            paused | exited | timeout (target still running)
  wait [--timeout-ms N]     wait for the next pause or exit without advancing
  eval <expr>               side-effect-free evaluation in the top paused frame
                            (throwOnSideEffect; mutations are rejected)
  report                    state, breakpoints, step count, program stdout/stderr
  stop                      SIGKILL the target (no remaining code runs), wait for
                            its exit, then end the session

files in <dir>: transcript.jsonl, program.stdout, program.stderr, session.json (at end)
`;

const SOCKET = 'ctl.sock';
const ENDED = 'session.json';
const DEFAULT_TIMEOUT_MS = 5000;
const CDP_TIMEOUT_MS = 5000;
const OUTPUT_LIMIT = 16 * 1024;
const BANNER = [
  /^Debugger listening on ws:\/\//,
  /^For help, see: https:\/\/nodejs\.org\/en\/docs\/inspector/,
  /^Debugger attached\.$/,
  /^Debugger ending on ws:\/\//,
  /^Waiting for the debugger to disconnect\.\.\.$/,
];
const MOVES = { next: 'Debugger.stepOver', step: 'Debugger.stepInto', out: 'Debugger.stepOut', continue: 'Debugger.resume' };

const escapeRegex = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function parseFlags(args, names) {
  const flags = {};
  const positional = [];
  for (let i = 0; i < args.length; i++) {
    const name = args[i].startsWith('--') ? args[i].slice(2) : null;
    if (name && names.includes(name)) {
      if (i + 1 >= args.length) throw new Error(`--${name} needs a value`);
      flags[name] = args[++i];
    } else positional.push(args[i]);
  }
  return { flags, positional };
}

function positiveInt(value, label) {
  const n = Number(value);
  if (!Number.isInteger(n) || n < 1) throw new Error(`${label} must be a positive integer, got ${JSON.stringify(value)}`);
  return n;
}

function readTail(file) {
  let text = '';
  try { text = fs.readFileSync(file, 'utf8'); } catch {}
  return text.length > OUTPUT_LIMIT
    ? { path: file, truncated: true, text: text.slice(-OUTPUT_LIMIT) }
    : { path: file, text };
}

class Session {
  constructor(dir) {
    this.dir = dir;
    this.child = null;
    this.ws = null;
    this.cdpSeq = 0;
    this.pending = new Map(); // CDP id -> { resolve, reject, timer }
    this.scripts = new Map(); // scriptId -> { url, sourceMapURL }
    this.sources = new Map(); // scriptId -> Promise<string[]>
    this.breakpoints = new Map(); // breakpointId -> record
    this.watchers = new Set();
    this.paused = null;
    this.pauseSeq = 0;
    this.exit = null; // { code, signal }
    this.finishing = false; // program done, inspector waiting for disconnect
    this.stopping = false;
    this.moves = 0;
    this.busy = null;
    this.server = null;
    this.socketIno = null;
  }

  file(name) { return path.join(this.dir, name); }

  log(kind, data = {}) {
    fs.appendFileSync(this.file('transcript.jsonl'), JSON.stringify({ t: new Date().toISOString(), kind, ...data }) + '\n');
  }

  notify() { for (const w of [...this.watchers]) w(); }

  // Resolve true as soon as pred() holds after any state change, false on timeout.
  waitUntil(pred, ms) {
    return new Promise((resolve) => {
      if (pred()) return resolve(true);
      const done = (v) => { clearTimeout(timer); this.watchers.delete(check); resolve(v); };
      const check = () => { if (pred()) done(true); };
      const timer = setTimeout(() => done(false), ms);
      this.watchers.add(check);
    });
  }

  cdp(method, params = {}, ms = CDP_TIMEOUT_MS) {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return Promise.reject(new Error(`inspector not connected (${method})`));
    const id = ++this.cdpSeq;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.pending.delete(id); reject(new Error(`${method} timed out after ${ms}ms`)); }, ms);
      this.pending.set(id, { resolve, reject, timer });
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }

  async start(nodeArgs, startupMs) {
    const stdoutFd = fs.openSync(this.file('program.stdout'), 'wx');
    fs.writeFileSync(this.file('program.stderr'), '', { flag: 'wx' });
    const argv = ['--inspect-brk=127.0.0.1:0', ...nodeArgs];
    this.child = spawn(process.execPath, argv, { stdio: ['ignore', stdoutFd, 'pipe'] });
    fs.closeSync(stdoutFd);
    this.log('spawn', { pid: this.child.pid, argv: [process.execPath, ...argv], cwd: process.cwd() });

    let wsUrl = null;
    let partial = '';
    const onLine = (line) => {
      if (!BANNER.some((re) => re.test(line))) return fs.appendFileSync(this.file('program.stderr'), line + '\n');
      wsUrl ??= /ws:\/\/\S+/.exec(line)?.[0] ?? null;
      if (/^Waiting for the debugger to disconnect/.test(line)) this.onProgramFinished();
      this.notify();
    };
    this.child.stderr.setEncoding('utf8');
    this.child.stderr.on('data', (d) => {
      const lines = (partial + d).split('\n');
      partial = lines.pop();
      lines.forEach(onLine);
    });
    this.child.stderr.on('end', () => { if (partial) onLine(partial); partial = ''; });
    this.child.on('error', (err) => this.log('spawn-error', { message: err.message }));
    // Preserve the exit code after draining stderr, but descendants may keep
    // that pipe open after the direct target has exited. Bound only the drain.
    let drainTimer;
    this.child.on('exit', () => {
      drainTimer = setTimeout(() => {
        this.log('stderr-held-open', { note: 'target exited; descendant stderr capture ends here' });
        this.child.stderr.destroy();
      }, 500);
      drainTimer.unref();
    });
    this.child.on('close', (code, signal) => {
      clearTimeout(drainTimer);
      this.exit = { code, signal };
      this.paused = null;
      this.log('exit', this.exit);
      this.ws?.close();
      this.notify();
    });

    if (!(await this.waitUntil(() => wsUrl || this.exit, startupMs)) || !wsUrl) {
      throw new Error(this.exit ? `target exited before the inspector started (code ${this.exit.code}, signal ${this.exit.signal})` : `no inspector URL within ${startupMs}ms`);
    }
    await this.connect(wsUrl, startupMs);
    await this.cdp('Runtime.enable');
    await this.cdp('Debugger.enable');
    const seq = this.pauseSeq;
    await this.cdp('Runtime.runIfWaitingForDebugger');
    if (!(await this.waitUntil(() => this.pauseSeq > seq || this.exit, startupMs))) throw new Error(`no initial pause within ${startupMs}ms`);
  }

  connect(url, ms) {
    const ws = new WebSocket(url);
    this.ws = ws;
    ws.addEventListener('message', ({ data }) => this.onMessage(JSON.parse(data)));
    ws.addEventListener('close', () => this.onInspectorClosed(ws));
    return new Promise((resolve, reject) => {
      const done = (err) => { clearTimeout(timer); ws.removeEventListener('open', onOpen); ws.removeEventListener('error', onError); err ? reject(err) : resolve(); };
      const onOpen = () => done();
      const onError = () => done(new Error(`inspector connection failed: ${url}`));
      const timer = setTimeout(() => done(new Error(`inspector connection timed out after ${ms}ms`)), ms);
      ws.addEventListener('open', onOpen);
      ws.addEventListener('error', onError);
    });
  }

  onMessage(m) {
    if (m.id) {
      const p = this.pending.get(m.id);
      if (!p) return;
      clearTimeout(p.timer);
      this.pending.delete(m.id);
      return m.error ? p.reject(new Error(m.error.message)) : p.resolve(m.result);
    }
    const params = m.params;
    switch (m.method) {
      case 'Debugger.scriptParsed':
        this.scripts.set(params.scriptId, { url: params.url, sourceMapURL: params.sourceMapURL || undefined });
        break;
      case 'Debugger.paused':
        this.paused = params;
        this.pauseSeq++;
        for (const id of params.hitBreakpoints ?? []) { const bp = this.breakpoints.get(id); if (bp) bp.hits++; }
        this.notify();
        break;
      case 'Debugger.resumed':
        this.paused = null;
        this.notify();
        break;
      case 'Debugger.breakpointResolved': {
        const bp = this.breakpoints.get(params.breakpointId);
        const location = this.location(params.location);
        if (bp) bp.locations.push(location);
        this.log('breakpoint-resolved', { id: params.breakpointId, location });
        break;
      }
    }
  }

  onInspectorClosed(ws) {
    if (this.ws !== ws) return;
    this.ws = null;
    this.paused = null;
    for (const [id, p] of this.pending) { clearTimeout(p.timer); p.reject(new Error('inspector disconnected')); this.pending.delete(id); }
    if (!this.exit && !this.finishing && !this.stopping) {
      // Losing the inspector resumes the target; kill it so it does not keep running unobserved.
      this.log('inspector-lost', { note: 'target resumed without a debugger until killed; side effects may have run' });
      this.child?.kill('SIGKILL');
    }
    this.notify();
  }

  // Under --inspect-brk Node keeps the process alive after the program finishes
  // until the debugger disconnects; disconnect so it exits with its real code.
  onProgramFinished() {
    if (this.finishing) return;
    this.finishing = true;
    this.paused = null;
    this.log('program-finished');
    this.ws?.close();
  }

  location(loc) {
    return { url: this.scripts.get(loc.scriptId)?.url ?? '', line: loc.lineNumber + 1, column: loc.columnNumber + 1 };
  }

  sourceLines(scriptId) {
    if (!this.sources.has(scriptId)) {
      const p = this.cdp('Debugger.getScriptSource', { scriptId }).then((r) => r.scriptSource.split('\n'));
      p.catch(() => this.sources.delete(scriptId));
      this.sources.set(scriptId, p);
    }
    return this.sources.get(scriptId);
  }

  async state() {
    if (this.exit) return { state: 'exited', code: this.exit.code, signal: this.exit.signal };
    if (this.finishing) return { state: 'finishing' };
    if (!this.paused) return { state: 'running' };
    const frame = this.paused.callFrames[0];
    const lines = await this.sourceLines(frame.location.scriptId);
    return {
      state: 'paused',
      reason: this.paused.reason,
      hitBreakpoints: this.paused.hitBreakpoints ?? [],
      ...this.location(frame.location),
      function: frame.functionName || '(anonymous)',
      code: lines[frame.location.lineNumber]?.trimEnd() ?? null,
    };
  }

  describeBreakpoint(bp) {
    const resolved = bp.locations.length > 0;
    return {
      id: bp.id,
      requested: bp.requested,
      accepted: true,
      status: !resolved ? 'pending' : bp.locations.some((l) => l.line !== bp.requested.line) ? 'moved' : 'resolved',
      locations: bp.locations,
      hits: bp.hits,
    };
  }

  async setBreakpoint(target, line) {
    let params;
    if (/^[a-z][a-z0-9+.-]*:/i.test(target)) params = { url: target };
    // Node reports realpath-based file URLs (e.g. /tmp -> /private/tmp on macOS).
    else if (path.isAbsolute(target)) params = { url: pathToFileURL(fs.existsSync(target) ? fs.realpathSync(target) : target).href };
    else {
      const suffix = target.replace(/^\.\//, '');
      const urls = [...new Set([...this.scripts.values()].map((s) => s.url))].filter((u) => u === suffix || u.endsWith('/' + suffix));
      if (urls.length > 1) throw new Error(`suffix ${JSON.stringify(target)} is ambiguous: ${urls.join(', ')}`);
      params = urls.length === 1 ? { url: urls[0] } : { urlRegex: `(^|/)${escapeRegex(suffix)}$` };
    }
    const r = await this.cdp('Debugger.setBreakpointByUrl', { ...params, lineNumber: line - 1 });
    const bp = { id: r.breakpointId, requested: { target, ...params, line }, locations: r.locations.map((l) => this.location(l)), hits: 0 };
    this.breakpoints.set(bp.id, bp);
    return { breakpoint: this.describeBreakpoint(bp) };
  }

  async move(cmd, flags) {
    const expect = flags.expect?.trim();
    if (!expect) throw new Error(`${cmd} requires --expect <text>: state the predicted next pause or result before advancing`);
    const timeoutMs = flags['timeout-ms'] ? positiveInt(flags['timeout-ms'], '--timeout-ms') : DEFAULT_TIMEOUT_MS;
    if (!this.paused) throw new Error(`${cmd} needs a paused target; state is ${(await this.state()).state}`);
    const before = await this.state();
    const seq = this.pauseSeq;
    const n = ++this.moves;
    // Durable before the target moves: the prediction cannot be written after the fact.
    this.log('predict', { move: n, cmd, expect, before });
    await this.cdp(MOVES[cmd]);
    const arrived = await this.waitUntil(() => this.pauseSeq > seq || this.exit, timeoutMs);
    const outcome = !arrived ? 'timeout' : this.exit ? 'exited' : 'paused';
    const after = await this.state();
    this.log('actual', { move: n, cmd, outcome, after });
    return { move: n, expect, outcome, ...(outcome === 'timeout' ? { timeoutMs } : {}), after };
  }

  async evaluate(expression) {
    if (!expression) throw new Error('eval needs an expression');
    if (!this.paused) throw new Error(`eval needs a paused target; state is ${(await this.state()).state}`);
    const r = await this.cdp('Debugger.evaluateOnCallFrame', {
      callFrameId: this.paused.callFrames[0].callFrameId,
      expression,
      throwOnSideEffect: true,
      returnByValue: true,
      silent: true,
      timeout: 1000,
    });
    if (r.exceptionDetails) {
      const description = (r.result?.description ?? r.exceptionDetails.text ?? '').split('\n')[0];
      return { exception: description, sideEffectBlocked: /possible side-effect/i.test(description) };
    }
    const { type, subtype, value, description } = r.result;
    return { type, ...(subtype ? { subtype } : {}), value, ...(description !== undefined ? { description } : {}) };
  }

  async report() {
    return {
      ...(await this.state()),
      moves: this.moves,
      breakpoints: [...this.breakpoints.values()].map((bp) => this.describeBreakpoint(bp)),
      stdout: readTail(this.file('program.stdout')),
      stderr: readTail(this.file('program.stderr')),
      transcript: this.file('transcript.jsonl'),
    };
  }

  async handle(argv) {
    const [cmd, ...rest] = argv;
    switch (cmd) {
      case 'where': return this.state();
      case 'stack': {
        if (!this.paused) return this.state();
        return { frames: this.paused.callFrames.map((f) => ({ function: f.functionName || '(anonymous)', ...this.location(f.location) })) };
      }
      case 'source': {
        const { flags } = parseFlags(rest, ['context']);
        const context = flags.context ? positiveInt(flags.context, '--context') : 5;
        if (!this.paused) return this.state();
        const loc = this.paused.callFrames[0].location;
        const lines = await this.sourceLines(loc.scriptId);
        const from = Math.max(0, loc.lineNumber - context);
        const script = this.scripts.get(loc.scriptId);
        return {
          url: script?.url ?? '',
          ...(script?.sourceMapURL ? { sourceMapURL: script.sourceMapURL } : {}),
          note: 'script text as executed by V8; source maps are not applied',
          lines: lines.slice(from, loc.lineNumber + context + 1).map((text, i) => ({ line: from + i + 1, text, ...(from + i === loc.lineNumber ? { current: true } : {}) })),
        };
      }
      case 'bp': {
        if (rest.length !== 2) throw new Error('usage: bp <url|abs-path|suffix> <line>');
        return this.setBreakpoint(rest[0], positiveInt(rest[1], 'line'));
      }
      case 'bps': return { breakpoints: [...this.breakpoints.values()].map((bp) => this.describeBreakpoint(bp)) };
      case 'next': case 'step': case 'out': case 'continue':
        return this.move(cmd, parseFlags(rest, ['expect', 'timeout-ms']).flags);
      case 'wait': {
        const { flags } = parseFlags(rest, ['timeout-ms']);
        const timeoutMs = flags['timeout-ms'] ? positiveInt(flags['timeout-ms'], '--timeout-ms') : DEFAULT_TIMEOUT_MS;
        const arrived = await this.waitUntil(() => this.paused || this.exit, timeoutMs);
        return { outcome: arrived ? (this.exit ? 'exited' : 'paused') : 'timeout', ...(await this.state()) };
      }
      case 'eval': return this.evaluate(rest.join(' '));
      case 'report': return this.report();
      default: throw new Error(`unknown command ${JSON.stringify(cmd)}; see --help`);
    }
  }

  // Kill before disconnecting: a detached debugger would resume the target and run its remaining code.
  async terminateTarget() {
    this.stopping = true;
    if (this.child && !this.exit) {
      this.child.kill('SIGKILL');
      if (!(await this.waitUntil(() => this.exit, 5000))) this.log('kill-timeout', { pid: this.child.pid });
    }
    this.ws?.close();
  }

  listen() {
    const tmp = this.file(`${SOCKET}.${process.pid}.tmp`);
    this.server = net.createServer((conn) => this.onConnection(conn));
    return new Promise((resolve, reject) => {
      this.server.once('error', reject);
      this.server.listen(tmp, () => {
        // Publish atomically: clients never see a socket that is not yet accepting.
        fs.renameSync(tmp, this.file(SOCKET));
        this.socketIno = fs.statSync(this.file(SOCKET)).ino;
        resolve();
      });
    });
  }

  onConnection(conn) {
    let buf = '';
    conn.setEncoding('utf8');
    conn.on('error', () => {});
    conn.on('data', async (d) => {
      buf += d;
      if (buf.length > 1 << 20) return conn.destroy();
      const nl = buf.indexOf('\n');
      if (nl < 0) return;
      conn.removeAllListeners('data');
      const reply = (res) => new Promise((r) => conn.end(JSON.stringify(res) + '\n', r));
      let argv;
      try { argv = JSON.parse(buf.slice(0, nl)); } catch { return reply({ ok: false, error: 'malformed request' }); }
      if (!Array.isArray(argv) || !argv.every((a) => typeof a === 'string')) return reply({ ok: false, error: 'request must be a JSON string array' });
      if (this.busy || this.stopping) return reply({ ok: false, error: 'busy', busyWith: this.busy ?? 'stop' });
      this.busy = argv[0] ?? '';
      if (argv[0] === 'stop') return this.stop(argv, reply);
      let res;
      try { res = { ok: true, ...(await this.handle(argv)) }; } catch (err) { res = { ok: false, error: err.message }; }
      this.log('command', { argv, res });
      this.busy = null;
      reply(res);
    });
  }

  async stop(argv, reply) {
    const wasRunning = !this.exit;
    await this.terminateTarget();
    const confirmed = Boolean(this.exit);
    const res = {
      ok: confirmed,
      stopped: confirmed,
      killed: wasRunning && confirmed,
      ...(confirmed ? {} : { error: 'target exit not confirmed', pid: this.child?.pid }),
      ...(await this.report()),
    };
    this.log('command', { argv, res });
    await reply(res);
    await this.close('stop');
    process.exit(confirmed ? 0 : 1);
  }

  async close(reason, error) {
    if (this.server) await new Promise((r) => this.server.close(r));
    try { if (this.socketIno !== null && fs.statSync(this.file(SOCKET)).ino === this.socketIno) fs.rmSync(this.file(SOCKET)); } catch {}
    for (const w of [...this.watchers]) w();
    const end = { reason, ...(error ? { error } : {}), pid: this.child?.pid, exit: this.exit };
    this.log('end', end);
    fs.writeFileSync(this.file(ENDED), JSON.stringify(end, null, 2) + '\n');
  }
}

export async function serve(dir, nodeArgs, { startupTimeoutMs = 10000 } = {}) {
  dir = path.resolve(dir);
  if (!nodeArgs.length) throw new Error('serve needs node arguments after --');
  if (Buffer.byteLength(path.join(dir, `${SOCKET}.${process.pid}.tmp`)) > 103) throw new Error(`session dir path too long for a Unix socket: ${dir}`);
  fs.mkdirSync(dir, { recursive: true });
  if (fs.readdirSync(dir).length) throw new Error(`session dir is not empty (another or previous session?): ${dir}`);
  // Exclusive create claims the directory against a concurrent serve.
  fs.writeFileSync(path.join(dir, 'transcript.jsonl'), '', { flag: 'wx' });

  const session = new Session(dir);
  let ending = false;
  const abort = async (reason, error, code) => {
    if (ending) return;
    ending = true;
    await session.terminateTarget();
    await session.close(reason, error);
    process.exit(code);
  };
  for (const sig of ['SIGINT', 'SIGTERM', 'SIGHUP']) process.on(sig, () => abort(`signal:${sig}`, undefined, 128 + ({ SIGHUP: 1, SIGINT: 2, SIGTERM: 15 })[sig]));
  process.on('uncaughtException', (err) => abort('driver-error', err.stack, 70));
  process.on('unhandledRejection', (err) => abort('driver-error', String(err?.stack ?? err), 70));

  try {
    await session.start(nodeArgs, startupTimeoutMs);
    await session.listen();
  } catch (err) {
    console.error(`step-driver: startup failed: ${err.message}`);
    return abort('startup-failed', err.message, 1);
  }
  const ready = { ready: true, dir, pid: session.child.pid, ...(await session.state()) };
  session.log('ready', ready);
  console.log(JSON.stringify(ready));
}

// Wait until one of `names` exists in dir, watching the nearest existing ancestor.
function waitForEntry(dir, names, ms) {
  return new Promise((resolve, reject) => {
    let watcher = null;
    const finish = (err, value) => { clearTimeout(timer); watcher?.close(); err ? reject(err) : resolve(value); };
    const timer = setTimeout(() => finish(new Error(`no session in ${dir} within ${ms}ms (is serve running?)`)), ms);
    const arm = () => {
      watcher?.close();
      watcher = null;
      let watched = dir;
      while (!fs.existsSync(watched)) {
        const parent = path.dirname(watched);
        if (parent === watched) return finish(new Error(`no existing ancestor for ${dir}`));
        watched = parent;
      }
      try { watcher = fs.watch(watched, () => arm()); } catch (err) { return finish(err); }
      // Check after arming so an entry created in between is not missed.
      const found = watched === dir && names.find((n) => fs.existsSync(path.join(dir, n)));
      if (found) finish(null, found);
    };
    arm();
  });
}

function movementTimeout(argv) {
  const i = argv.indexOf('--timeout-ms');
  const n = i >= 0 ? Number(argv[i + 1]) : DEFAULT_TIMEOUT_MS;
  return (Number.isFinite(n) ? n : DEFAULT_TIMEOUT_MS) + CDP_TIMEOUT_MS * 2;
}

export async function request(dir, argv, { connectTimeoutMs = 10000 } = {}) {
  dir = path.resolve(dir);
  const found = await waitForEntry(dir, [SOCKET, ENDED], connectTimeoutMs);
  const ended = () => ({ ok: false, error: 'session ended', session: JSON.parse(fs.readFileSync(path.join(dir, ENDED), 'utf8')) });
  if (found === ENDED && !fs.existsSync(path.join(dir, SOCKET))) return ended();
  const ms = movementTimeout(argv);
  return new Promise((resolve) => {
    let out = '';
    const conn = net.connect(path.join(dir, SOCKET));
    const timer = setTimeout(() => { conn.destroy(); resolve({ ok: false, error: `no reply within ${ms}ms` }); }, ms);
    conn.setEncoding('utf8');
    conn.on('connect', () => conn.write(JSON.stringify(argv) + '\n'));
    conn.on('data', (d) => { out += d; });
    conn.on('error', (err) => {
      clearTimeout(timer);
      if (fs.existsSync(path.join(dir, ENDED))) return resolve(ended());
      resolve({ ok: false, error: err.code === 'ECONNREFUSED' ? `stale socket, serve is not running: ${path.join(dir, SOCKET)}` : err.message });
    });
    conn.on('end', () => {
      clearTimeout(timer);
      try { resolve(JSON.parse(out)); } catch { resolve({ ok: false, error: 'malformed reply', raw: out }); }
    });
  });
}

async function main(args) {
  if (!args.length || args[0] === '-h' || args[0] === '--help') return process.stdout.write(USAGE);
  if (args[0] === 'serve') {
    const sep = args.indexOf('--');
    if (sep < 0) throw new Error('serve needs `-- <node-args...>`');
    const { flags, positional } = parseFlags(args.slice(1, sep), ['startup-timeout-ms']);
    if (positional.length !== 1) throw new Error('usage: serve <dir> [--startup-timeout-ms N] -- <node-args...>');
    const startupTimeoutMs = flags['startup-timeout-ms'] ? positiveInt(flags['startup-timeout-ms'], '--startup-timeout-ms') : undefined;
    return serve(positional[0], args.slice(sep + 1), { startupTimeoutMs });
  }
  if (args.length < 2) throw new Error('usage: <dir> <command> [args...]; see --help');
  const res = await request(args[0], args.slice(1));
  console.log(JSON.stringify(res, null, 2));
  process.exitCode = res.ok ? 0 : 1;
}

if (import.meta.main) {
  main(process.argv.slice(2)).catch((err) => { console.error(`step-driver: ${err.message}`); process.exitCode = 2; });
}
