from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from adapters import directive, handle_hook
from sender import DeliveryError
from store import Store, drain
from test_sender import receiver


def block(bot='bot', thread='t3-thread'):
    return '<grokbot-notify>' + json.dumps({'grok_bot_id': bot, 't3_code_thread_id': thread}) + '</grokbot-notify>\nWork'


class NotificationTests(unittest.TestCase):
    def setUp(self):
        cache = Path(__file__).resolve().parents[3] / '.agents/cache/grokbot-notify-tests'
        cache.mkdir(parents=True, exist_ok=True)
        directory = tempfile.TemporaryDirectory(dir=cache)
        self.addCleanup(directory.cleanup)
        self.home = Path(directory.name)
        self.path = self.home / 'state/grokbot-notify/state.sqlite3'
        env = patch.dict(os.environ, {'HOME': str(self.home), 'XDG_STATE_HOME': str(self.home / 'state')})
        env.start()
        self.addCleanup(env.stop)
        env = patch.dict(os.environ)
        env.start()
        os.environ.pop('T3CODE_THREAD_ID', None)
        self.addCleanup(env.stop)

    def hook(self, name, provider='codex', session='native-session', run='run-1', **fields):
        return handle_hook(provider, dict(hook_event_name=name, session_id=session,
            **{{'codex': 'turn_id', 'claude': 'prompt_id', 'pi': 'run_id'}[provider]: run}, **fields), path=self.path)

    def begin(self, **kwargs):
        return self.hook('UserPromptSubmit', prompt=block(), **kwargs)

    def read(self):
        store = Store(self.path)
        self.addCleanup(store.close)
        return store

    def payloads(self):
        return [json.loads(row[0]) for row in self.read().db.execute('SELECT payload FROM outbox ORDER BY id')]

    def test_opt_in_is_leading_and_strict(self):
        self.assertIsNone(directive('Quoted example: ' + block()))
        self.assertIsNone(self.hook('UserPromptSubmit', prompt='Work'))
        self.assertFalse(self.path.exists())
        for text in ['<grokbot-notify>{', '<grokbot-notify>[]</grokbot-notify>',
                     '<grokbot-notify>{"unregister":1}</grokbot-notify>',
                     '<grokbot-notify>{"grok_bot_id":"x"}</grokbot-notify>']:
            with self.assertRaises(ValueError):
                directive(text)
        self.assertEqual(directive(' \n' + block())['grok_bot_id'], 'bot')

    def test_routes_survive_reopen_and_blockless_followup_but_not_new_sessions(self):
        self.begin()
        self.hook('Stop', last_assistant_message='First')
        self.hook('UserPromptSubmit', run='run-2', prompt='Continue')
        self.hook('Stop', run='run-2', last_assistant_message='Second')
        os.environ['T3CODE_THREAD_ID'] = 't3-thread'
        self.hook('UserPromptSubmit', session='other-native', prompt='Unregistered')
        self.hook('Stop', session='other-native', last_assistant_message='Ignored')
        self.assertEqual([p['message'] for p in self.payloads()], ['First', 'Second'])

    def test_route_update_keeps_old_run_snapshot_and_other_thread_separate(self):
        self.begin()
        self.hook('UserPromptSubmit', run='run-2', prompt=block('new-bot'))
        self.hook('UserPromptSubmit', session='other', prompt=block('other-bot', 'other-thread'))
        self.hook('Stop', last_assistant_message='Old')
        self.hook('Stop', run='run-2', last_assistant_message='New')
        self.hook('Stop', session='other', last_assistant_message='Other')
        self.assertEqual([p['grok_bot_id'] for p in self.payloads()], ['bot', 'new-bot', 'other-bot'])
        # Replaying an old admission must not roll the route back.
        self.begin()
        self.hook('UserPromptSubmit', run='run-3', prompt='Continue')
        self.hook('Stop', run='run-3', last_assistant_message='Still new')
        self.assertEqual(self.payloads()[-1]['grok_bot_id'], 'new-bot')

    def test_unregistration_cancels_pending_and_re_registration_never_revives_old_runs(self):
        self.begin()
        self.hook('Stop', last_assistant_message='Old')
        self.hook('UserPromptSubmit', run='unregister', prompt='<grokbot-notify>{"unregister":true}</grokbot-notify>')
        self.hook('UserPromptSubmit', run='new', prompt=block())
        self.hook('Stop', last_assistant_message='Old later observation')
        self.hook('Stop', run='new', last_assistant_message='New')
        sent = []
        drain(self.read(), send=sent.append)
        self.assertEqual([p['message'] for p in sent], ['New'])
        self.assertEqual(self.read().status()['outbox'][0]['state'], 'cancelled')

    def test_environment_thread_mismatch_fails_closed(self):
        os.environ['T3CODE_THREAD_ID'] = 'wrong-thread'
        with self.assertRaisesRegex(ValueError, 'thread_mismatch'):
            self.begin()
        self.assertEqual(self.read().status()['routes'], [])

    def test_retry_failure_and_observed_responses_are_not_terminal(self):
        self.begin()
        for _ in range(2):
            self.hook('PostModelRequest', status='failed', error='secret usage_limit_reached')
        self.hook('PostModelRequest', status='completed')
        self.hook('Stop', last_assistant_message='Interim')
        self.hook('Stop', last_assistant_message='Interim')
        self.hook('Stop', last_assistant_message='Final')
        payloads = self.payloads()
        self.assertEqual([p['status'] for p in payloads], ['attempt_failed', 'response_observed', 'response_observed'])
        self.assertEqual(payloads[0]['reason'], 'model_request_failed')
        self.assertNotIn('secret', json.dumps(payloads))

    def test_claude_preserves_typed_failure_and_resumption_is_new_event(self):
        self.begin(provider='claude')
        self.hook('StopFailure', provider='claude', error='rate_limit', error_details='secret')
        self.hook('UserPromptSubmit', provider='claude', run='resumed', prompt='Continue')
        self.hook('Stop', provider='claude', run='resumed', last_assistant_message='Resumed')
        self.assertEqual([(p['status'], p['reason']) for p in self.payloads()],
                         [('stopped', 'rate_limit'), ('response_observed', None)])

    def test_subagents_and_missing_turn_ids_cannot_reuse_parent_identity(self):
        self.begin(provider='claude')
        self.hook('StopFailure', provider='claude', agent_id='child', error='rate_limit')
        with self.assertRaisesRegex(ValueError, 'run_id_missing'):
            self.hook('Stop', provider='claude', run=None, last_assistant_message='Unknown turn')
        self.assertEqual(self.payloads(), [])

    def test_distinct_questions_in_same_run_and_duplicate_tool_callback(self):
        self.begin()
        for tool, call in [('request_user_input', 'call-1'), ('request_user_input', 'call-1'),
                           ('request_user_input_async', 'call-2')]:
            self.hook('PreToolUse', tool_name=tool, tool_use_id=call,
                      tool_input={'questions': [{'question': 'Pick?', 'options': [{'label': 'A'}]}]})
        self.assertEqual([p['reason'] for p in self.payloads()], ['question_invoked', 'async_question'])
        self.assertEqual(self.payloads()[0]['message'], 'Pick?\n- A')

    def test_pi_only_settlement_emits_final_status_and_never_classifies_error_prose(self):
        for stop, expected in [('stop', ('response_finished', None)), ('error', ('stopped', 'provider_error')),
                               ('length', ('stopped', 'max_output_tokens')), ('aborted', ('stopped', 'aborted'))]:
            self.hook('input', provider='pi', run=stop, text=block())
            self.hook('agent_end', provider='pi', run=stop)
            self.hook('agent_settled', provider='pi', run=stop, aborted=False,
                      message={'stopReason': stop, 'content': [{'type': 'thinking', 'thinking': 'secret'},
                               {'type': 'text', 'text': 'Answer'}], 'errorMessage': 'secret usage limit'})
            last = self.payloads()[-1]
            self.assertEqual((last['status'], last['reason']), expected)
            self.assertNotIn('secret', json.dumps(last))
        self.assertEqual(self.payloads()[0]['message'], 'Answer')

    def test_pi_busy_registration_only_applies_to_next_run(self):
        self.hook('input', provider='pi', text=block())
        run = self.hook('input', provider='pi', run='steer', active_run_id='run-1', text=block('next-bot'))
        self.assertEqual(run['native_id'], 'run-1')
        self.hook('agent_settled', provider='pi', message={'stopReason': 'stop'})
        self.hook('input', provider='pi', run='next', text='Continue')
        self.hook('agent_settled', provider='pi', run='next', message={'stopReason': 'stop'})
        self.assertEqual([p['grok_bot_id'] for p in self.payloads()], ['bot', 'next-bot'])

    def test_unsettled_or_missing_pi_result_never_claims_success(self):
        self.hook('input', provider='pi', text=block())
        for message in [None, {'stopReason': 'deferred'}, {'stopReason': 'toolUse'}]:
            with self.assertRaisesRegex(ValueError, 'settled_result_unavailable'):
                self.hook('agent_settled', provider='pi', message=message)
        self.assertEqual(self.payloads(), [])

    def test_outbox_retries_after_restart_and_acknowledges_only_success(self):
        self.begin()
        self.hook('Stop', last_assistant_message='Answer')
        def fail(_):
            raise DeliveryError('connection_failure', True)
        drain(self.read(), send=fail, now=lambda: 0)
        self.assertEqual(self.read().status()['outbox'][0]['state'], 'pending')
        sent = []
        self.assertEqual(drain(self.read(), send=sent.append, now=lambda: 4), 0)
        self.assertEqual(drain(self.read(), send=sent.append, now=lambda: 5), 1)
        self.assertEqual(drain(self.read(), send=sent.append, now=lambda: 500), 0)
        self.assertEqual(len(sent), 1)

    def test_permanent_failure_and_bounded_retry(self):
        self.begin()
        self.hook('Stop', last_assistant_message='Answer')
        calls = []
        def fail(payload):
            calls.append(payload)
            raise DeliveryError('timeout', True)
        for now in range(0, 10000, 1000):
            drain(self.read(), send=fail, now=lambda: now)
        self.assertEqual(len(calls), 5)
        self.assertEqual(self.read().status()['outbox'][0]['state'], 'dead')

    def test_lease_recovery_and_stale_ack_cannot_acknowledge_new_attempt(self):
        self.begin()
        self.hook('Stop', last_assistant_message='Answer')
        store = self.read()
        old = store.claim(0)
        self.assertIsNone(store.claim(119))
        new = store.claim(120)
        store.settle(old, None, 121)
        self.assertEqual(store.status()['outbox'][0]['state'], 'inflight')
        store.settle(new, None, 122)
        self.assertEqual(store.status()['outbox'][0]['state'], 'delivered')

    def test_revoke_inflight_and_ignore_late_ack(self):
        self.begin()
        self.hook('Stop', last_assistant_message='Answer')
        store = self.read()
        row = store.claim(0)
        store.unregister('t3-thread')
        store.settle(row, None, 1)
        self.assertEqual(store.status()['outbox'][0]['state'], 'cancelled')

    def test_concurrent_callbacks_enqueue_and_workers_claim_once(self):
        self.begin()
        with ThreadPoolExecutor(max_workers=6) as pool:
            list(pool.map(lambda _: self.hook('Stop', last_assistant_message='Answer'), range(12)))
        self.assertEqual(len(self.payloads()), 1)
        def claim(_):
            store = Store(self.path)
            try:
                return store.claim(0)
            finally:
                store.close()
        with ThreadPoolExecutor(max_workers=6) as pool:
            claims = list(pool.map(claim, range(12)))
        self.assertEqual(sum(row is not None for row in claims), 1)

    def test_cli_invalid_registration_is_safe_and_unregister_works(self):
        script = Path(__file__).with_name('main.py')
        result = subprocess.run([sys.executable, '-B', script, 'hook', 'codex'], text=True,
            input=json.dumps({'hook_event_name': 'UserPromptSubmit', 'prompt': '<grokbot-notify>secret'}),
            capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertNotIn('secret', result.stderr)
        self.begin()
        result = subprocess.run([sys.executable, '-B', script, 'unregister', '--t3-thread', 't3-thread'],
                                capture_output=True)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.read().status()['routes'][0]['active'], 0)

    def test_cli_delivery_sends_the_persisted_payload_with_real_http(self):
        self.begin()
        self.hook('Stop', last_assistant_message='Queued response')
        with receiver() as (url, requests):
            credentials = self.home / '.config/grokbot-webhook/credentials.json'
            credentials.parent.mkdir(parents=True)
            credentials.write_text(json.dumps({'url': url, 'key': 'local-test-token'}))
            env = dict(os.environ, NO_PROXY='127.0.0.1')
            result = subprocess.run([sys.executable, '-B', Path(__file__).with_name('main.py'), 'drain'],
                                    env=env, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(requests), 1)
        self.assertEqual(requests[0][2], self.payloads()[0])
        self.assertEqual(self.read().status()['outbox'][0]['state'], 'delivered')

    def test_failed_stop_notification_logs_without_continuing_the_agent(self):
        self.begin(provider='claude')
        event = dict(hook_event_name='Stop', session_id='native-session', last_assistant_message='Unknown turn')
        result = subprocess.run([sys.executable, '-B', Path(__file__).with_name('main.py'), 'hook', 'claude'],
                                input=json.dumps(event), text=True, capture_output=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn('run_id_missing', result.stderr)
        self.assertEqual((self.path.parent / 'diagnostics.log').read_text(), 'run_id_missing\n')


if __name__ == '__main__':
    unittest.main()
