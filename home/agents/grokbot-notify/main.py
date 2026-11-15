import argparse
import json
import os
import sqlite3
import sys

from adapters import handle_hook
from store import Store, drain, state_path


def diagnostic(code):
    print(f'grokbot-notify: {code}', file=sys.stderr)
    try:
        path = state_path().parent / 'diagnostics.log'
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        with path.open('a') as log:
            log.write(code + '\n')
    except OSError:
        pass


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description='Persist harness notifications and deliver the outbox.')
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('hook').add_argument('provider', choices=['codex', 'claude', 'pi'])
    commands.add_parser('drain')
    commands.add_parser('status')
    commands.add_parser('unregister').add_argument('--t3-thread', required=True)
    args = parser.parse_args()
    event = None
    try:
        if args.command == 'hook':
            event = json.load(sys.stdin)
            if not isinstance(event, dict):
                raise ValueError('event_invalid')
            run = handle_hook(args.provider, event)
            if args.provider == 'pi':
                print(json.dumps({'run_id': run['native_id'] if run else None}))
            return 0
        if not state_path().exists():
            if args.command == 'status':
                print(json.dumps({'routes': [], 'outbox': []}))
            return 0
        store = Store()
        try:
            if args.command == 'drain':
                drain(store)
            elif args.command == 'status':
                print(json.dumps(store.status()))
            else:
                store.unregister(args.t3_thread)
        finally:
            store.close()
        return 0
    except (OSError, sqlite3.Error):
        diagnostic('state_unavailable')
    except (ValueError, TypeError, KeyError, AttributeError) as error:
        codes = {'registration_invalid', 'thread_mismatch', 'session_id_missing',
                 'run_id_missing', 'run_not_registered', 'tool_id_missing', 'settled_result_unavailable'}
        diagnostic(str(error) if str(error) in codes else 'invalid_event_or_registration')
    # Notification failures must not make Stop hooks continue the agent.
    if args.command == 'hook' and args.provider != 'pi' and isinstance(event, dict) and event.get(
            'hook_event_name') != 'UserPromptSubmit':
        return 0
    return 2


if __name__ == '__main__':
    sys.exit(main())
