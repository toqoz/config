import { randomUUID } from 'node:crypto';

export type Run = (args: string[]) => Promise<{ code: number; active: boolean }>;

export class Lease {
  private current: { id: string; acquiredAt: number } | null = null;
  private disabled = false;

  async update(hold: boolean, now: number, run: Run): Promise<string> {
    if (this.disabled) return 'disabled-until-restart';
    if (!hold) {
      if (this.current) {
        const result = await run(['lease', 'release', '--id', this.current.id, '--json']);
        if (result.code !== 0) throw new Error('Keepresso release failed');
        this.current = null;
      }
      return 'released';
    }
    if (this.current) {
      const result = await run(['lease', 'heartbeat', '--id', this.current.id, '--json']);
      if (result.code === 3 || result.code === 4) {
        this.disabled = true;
        return 'revoked-or-expired';
      }
      if (result.code !== 0) throw new Error('Keepresso heartbeat failed');
      if (now - this.current.acquiredAt < 6 * 86_400_000) return result.active ? 'held' : 'safety-paused';
      // Check the old lease is live before rotating under its seven-day ceiling.
      const old = this.current;
      const status = await this.acquire(now, run);
      if (this.current?.id !== old.id) await run(['lease', 'release', '--id', old.id, '--json']);
      return status;
    }
    return this.acquire(now, run);
  }

  private async acquire(now: number, run: Run): Promise<string> {
    const id = randomUUID();
    const result = await run(['lease', 'acquire', '--id', id, '--tool', 't3-sleep-watcher', '--task', 'T3 Code agent work', '--ttl', '90', '--max-lifetime', '604800', '--json']);
    if (result.code === 4) { this.disabled = true; return 'automation-disabled'; }
    if (result.code !== 0) throw new Error('Keepresso acquire failed');
    this.current = { id, acquiredAt: now };
    return result.active ? 'held' : 'safety-paused';
  }
}
