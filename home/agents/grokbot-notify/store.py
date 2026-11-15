import json
import os
from pathlib import Path
import sqlite3
import time
import uuid

from sender import DeliveryError, post


def state_path():
    return Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'grokbot-notify/state.sqlite3'


class Store:
    def __init__(self, path=None):
        path = Path(path) if path else state_path()
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.db = sqlite3.connect(path, timeout=5)
        os.chmod(path, 0o600)
        self.db.row_factory = sqlite3.Row
        self.db.executescript('''
            PRAGMA foreign_keys=ON;
            CREATE TABLE IF NOT EXISTS routes (
                thread TEXT PRIMARY KEY, bot TEXT NOT NULL,
                epoch INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1
            );
            CREATE TABLE IF NOT EXISTS bindings (
                provider TEXT, session TEXT, thread TEXT REFERENCES routes(thread),
                PRIMARY KEY(provider, session)
            );
            CREATE TABLE IF NOT EXISTS runs (
                id INTEGER PRIMARY KEY, provider TEXT, session TEXT, native_id TEXT,
                thread TEXT REFERENCES routes(thread), bot TEXT, epoch INTEGER,
                UNIQUE(provider, session, native_id)
            );
            CREATE TABLE IF NOT EXISTS outbox (
                id INTEGER PRIMARY KEY, run INTEGER REFERENCES runs(id),
                kind TEXT, observation TEXT, payload TEXT,
                state TEXT NOT NULL DEFAULT 'pending', attempts INTEGER NOT NULL DEFAULT 0,
                next_at REAL NOT NULL DEFAULT 0, lease_until REAL, token TEXT,
                last_error TEXT, UNIQUE(run, kind, observation)
            );
        ''')

    def close(self):
        self.db.close()

    def _revoke(self, thread):
        self.db.execute('UPDATE routes SET active=0, epoch=epoch+1 WHERE thread=?', (thread,))
        self.db.execute('''UPDATE outbox SET state='cancelled', token=NULL
            WHERE state IN ('pending','inflight') AND run IN
            (SELECT id FROM runs WHERE thread=?)''', (thread,))

    def unregister(self, thread):
        with self.db:
            self.db.execute('BEGIN IMMEDIATE')
            self._revoke(thread)

    def begin(self, provider, session, native_id, directive=None, expected_thread=None, active_id=None):
        with self.db:
            self.db.execute('BEGIN IMMEDIATE')
            existing = self.run(provider, session, native_id)
            if existing:
                if expected_thread and existing['thread'] != expected_thread:
                    raise ValueError('thread_mismatch')
                return dict(existing)
            binding = self.db.execute('SELECT thread FROM bindings WHERE provider=? AND session=?',
                                      (provider, session)).fetchone()
            thread = directive.get('t3_code_thread_id') if directive else None
            thread = thread or (binding['thread'] if binding else None)
            if thread and expected_thread and thread != expected_thread:
                raise ValueError('thread_mismatch')
            if directive and directive.get('unregister'):
                if thread:
                    self._revoke(thread)
                return None
            if directive:
                self.db.execute('''INSERT INTO routes(thread,bot) VALUES (?,?)
                    ON CONFLICT(thread) DO UPDATE SET bot=excluded.bot, active=1''',
                                (thread, directive['grok_bot_id']))
                self.db.execute('''INSERT INTO bindings VALUES (?,?,?)
                    ON CONFLICT(provider,session) DO UPDATE SET thread=excluded.thread''',
                                (provider, session, thread))
            route = self.db.execute('SELECT * FROM routes WHERE thread=? AND active=1', (thread,)).fetchone()
            if not route:
                return None
            # Busy Pi input changes the next run's route, never this run's snapshot.
            if active_id:
                active = self.run(provider, session, active_id)
                return dict(active) if active else None
            self.db.execute('INSERT INTO runs(provider,session,native_id,thread,bot,epoch) VALUES (?,?,?,?,?,?)',
                            (provider, session, native_id, thread, route['bot'], route['epoch']))
            return dict(self.run(provider, session, native_id))

    def run(self, provider, session, native_id):
        return self.db.execute('SELECT * FROM runs WHERE provider=? AND session=? AND native_id=?',
                               (provider, session, native_id)).fetchone()

    def observe(self, provider, session, native_id, kind, reason, message, observation=''):
        with self.db:
            self.db.execute('BEGIN IMMEDIATE')
            run = self.run(provider, session, native_id)
            if not run:
                return False
            route = self.db.execute('SELECT * FROM routes WHERE thread=?', (run['thread'],)).fetchone()
            if not route['active'] or route['epoch'] != run['epoch']:
                return False
            payload = dict(grok_bot_id=run['bot'], t3_code_thread_id=run['thread'],
                           provider=provider, status=kind, reason=reason, message=message)
            self.db.execute('''INSERT OR IGNORE INTO outbox(run,kind,observation,payload)
                VALUES (?,?,?,?)''', (run['id'], kind, observation, json.dumps(payload, ensure_ascii=False)))
            return True

    def claim(self, now):
        with self.db:
            self.db.execute('BEGIN IMMEDIATE')
            self.db.execute('''UPDATE outbox SET state='dead', last_error='attempts_exhausted'
                WHERE attempts>=5 AND (state='pending' OR (state='inflight' AND lease_until<=?))''', (now,))
            row = self.db.execute('''SELECT o.* FROM outbox o JOIN runs r ON r.id=o.run
                JOIN routes t ON t.thread=r.thread AND t.active=1 AND t.epoch=r.epoch
                WHERE o.attempts<5 AND ((o.state='pending' AND o.next_at<=?)
                    OR (o.state='inflight' AND o.lease_until<=?)) ORDER BY o.id LIMIT 1''', (now, now)).fetchone()
            if not row:
                return None
            token = str(uuid.uuid4())
            self.db.execute("UPDATE outbox SET state='inflight', attempts=attempts+1, lease_until=?, token=? WHERE id=?",
                            (now + 120, token, row['id']))
            return dict(row) | {'token': token, 'attempts': row['attempts'] + 1}

    def settle(self, row, error, now):
        state = 'delivered' if error is None else 'pending' if error.retryable and row['attempts'] < 5 else 'dead'
        delay = (5, 30, 120, 600, 600)[row['attempts'] - 1]
        with self.db:
            self.db.execute('''UPDATE outbox SET state=?, next_at=?, last_error=?, token=NULL
                WHERE id=? AND token=? AND state='inflight' ''',
                            (state, now + delay, error.code if error else None, row['id'], row['token']))

    def status(self):
        return {
            'routes': [dict(r) for r in self.db.execute('SELECT * FROM routes')],
            'outbox': [dict(r) for r in self.db.execute('SELECT id,kind,state,attempts,last_error FROM outbox')],
        }


def drain(store, *, send=post, now=time.time, limit=20):
    delivered = 0
    for _ in range(limit):
        row = store.claim(now())
        if row is None:
            break
        error = None
        try:
            send(json.loads(row['payload']))
        except DeliveryError as failure:
            error = failure
        store.settle(row, error, now())
        delivered += error is None
    return delivered
