import hashlib
import json
import os
import re

from store import Store, state_path


BLOCK = re.compile(r'^\s*<grokbot-notify>\s*(.*?)\s*</grokbot-notify>', re.S)


def directive(prompt):
    match = BLOCK.match(prompt)
    if not match:
        if prompt.lstrip().startswith('<grokbot-notify>'):
            raise ValueError('registration_invalid')
        return None
    try:
        value = json.loads(match[1])
    except ValueError:
        raise ValueError('registration_invalid') from None
    if isinstance(value, dict) and set(value) == {'unregister'} and value['unregister'] is True:
        return value
    keys = {'grok_bot_id', 't3_code_thread_id'}
    if not isinstance(value, dict) or set(value) != keys or any(
            not isinstance(v, str) or not v.strip() or len(v) > 1024 for v in value.values()):
        raise ValueError('registration_invalid')
    return value


def visible(message):
    if not isinstance(message, dict):
        return ''
    return '\n'.join(part['text'] for part in message.get('content', [])
                     if isinstance(part, dict) and part.get('type') == 'text' and isinstance(part.get('text'), str))


def handle_hook(provider, event, *, path=None):
    if event.get('agent_id'):
        return None
    name = event.get('hook_event_name')
    if name not in ('UserPromptSubmit', 'input', 'Stop', 'PostModelRequest', 'StopFailure',
                    'PreToolUse', 'agent_settled'):
        return None
    if name == 'PreToolUse' and event.get('tool_name') not in (
            'AskUserQuestion', 'request_user_input', 'request_user_input_async'):
        return None
    admission = name in ('UserPromptSubmit', 'input')
    registration = directive(event.get('prompt', event.get('text', ''))) if admission else None
    path = path or state_path()
    if registration is None and not path.exists():
        return None
    session = event.get('session_id')
    native_id = event.get({'codex': 'turn_id', 'claude': 'prompt_id', 'pi': 'run_id'}[provider])
    if not isinstance(session, str) or not session:
        raise ValueError('session_id_missing')
    store = Store(path)
    try:
        if registration is None and not store.db.execute(
                'SELECT 1 FROM bindings WHERE provider=? AND session=?', (provider, session)).fetchone():
            return None
        if not isinstance(native_id, str) or not native_id:
            raise ValueError('run_id_missing')
        if admission:
            return store.begin(provider, session, native_id, registration,
                               os.environ.get('T3CODE_THREAD_ID'), event.get('active_run_id'))
        run = store.run(provider, session, native_id)
        if not run:
            raise ValueError('run_not_registered')
        expected = os.environ.get('T3CODE_THREAD_ID')
        if expected and expected != run['thread']:
            raise ValueError('thread_mismatch')
        kind, reason, observation = None, None, ''
        if name == 'Stop':
            kind = 'response_observed'
            message = event.get('last_assistant_message') or 'The response text was unavailable.'
            observation = hashlib.sha256(message.encode()).hexdigest()
        elif provider == 'codex' and name == 'PostModelRequest' and event.get('status') == 'failed':
            kind, reason = 'attempt_failed', 'model_request_failed'
            message = 'A Codex model request failed. The run may continue.'
        elif provider == 'claude' and name == 'StopFailure':
            kind = 'stopped'
            reasons = {'authentication_failed', 'oauth_org_not_allowed', 'account_on_hold',
                       'verification_required', 'billing_error', 'rate_limit', 'overloaded',
                       'invalid_request', 'model_not_found', 'server_error', 'unknown',
                       'max_output_tokens', 'cloud_credential_error'}
            reason = event.get('error')
            reason = reason if reason in reasons else 'unknown'
            message = f'Claude stopped: {reason}.'
        elif name == 'PreToolUse':
            tool = event.get('tool_name', '')
            if tool not in ('AskUserQuestion', 'request_user_input', 'request_user_input_async'):
                return None
            observation = event.get('tool_use_id')
            if not isinstance(observation, str) or not observation:
                raise ValueError('tool_id_missing')
            kind = 'input_requested'
            reason = 'async_question' if tool.endswith('_async') else 'question_invoked'
            questions = event.get('tool_input', {}).get('questions', [])
            lines = []
            for question in questions:
                if not isinstance(question, dict):
                    continue
                text = question.get('question', question.get('title', ''))
                if isinstance(text, str):
                    lines.append(text)
                for option in question.get('options', []):
                    label = option.get('label') if isinstance(option, dict) else option
                    if isinstance(label, str):
                        lines.append(f'- {label}')
            message = '\n'.join(lines) or 'A question tool was invoked; check T3 pending requests.'
        elif provider == 'pi' and name == 'agent_settled':
            message = visible(event.get('message'))
            stop = (event.get('message') or {}).get('stopReason')
            if event.get('aborted') or stop == 'aborted':
                kind, reason = 'stopped', 'aborted'
            elif stop == 'stop':
                kind = 'response_finished'
            elif stop in ('error', 'length'):
                kind, reason = 'stopped', 'provider_error' if stop == 'error' else 'max_output_tokens'
            else:
                raise ValueError('settled_result_unavailable')
            if kind == 'stopped':
                message = f'Pi stopped: {reason}.'
            message = message or 'The response text was unavailable.'
        if kind:
            store.observe(provider, session, native_id, kind, reason, message, observation)
        return None
    finally:
        store.close()
