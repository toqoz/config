from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import tempfile
from threading import Thread
import unittest
from unittest.mock import patch

from sender import DeliveryError, post


@contextmanager
def receiver(status=204):
    requests = []

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            requests.append((self.path, dict(self.headers),
                             json.loads(self.rfile.read(int(self.headers['Content-Length'])))))
            self.send_response(status)
            if 300 <= status < 400:
                self.send_header('Location', '/redirected')
            self.end_headers()
            if status >= 400:
                self.wfile.write(b'private URL and secret-token')

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f'http://127.0.0.1:{server.server_port}/webhook', requests
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


class SenderTests(unittest.TestCase):
    def setUp(self):
        cache = Path(__file__).resolve().parents[3] / '.agents/cache/grokbot-notify-tests'
        cache.mkdir(parents=True, exist_ok=True)
        directory = tempfile.TemporaryDirectory(dir=cache)
        self.addCleanup(directory.cleanup)
        self.path = Path(directory.name) / '.config/grokbot-webhook/credentials.json'
        self.path.parent.mkdir(parents=True)
        env = patch.dict(os.environ, {'HOME': directory.name, 'NO_PROXY': '127.0.0.1'})
        env.start()
        self.addCleanup(env.stop)
        self.payload = {
            'grok_bot_id': 'bot "quoted" 日本語', 't3_code_thread_id': 't3-thread',
            'provider': 'codex', 'status': 'response_observed', 'reason': None,
            'message': 'Visible answer\nwith a second line',
        }

    def credentials(self, url):
        self.path.write_text(json.dumps({'url': url, 'key': 'secret-token'}))

    def test_json_and_auth_are_delivered_once(self):
        with receiver() as (url, requests):
            self.credentials(url)
            post(self.payload)
        self.assertEqual(len(requests), 1)
        path, headers, body = requests[0]
        self.assertEqual(path, '/webhook')
        self.assertEqual(headers['Authorization'], 'Bearer secret-token')
        self.assertEqual(headers['Content-Type'], 'application/json')
        self.assertEqual(body, self.payload)

    def test_http_errors_are_classified_without_retry_or_response_leak(self):
        for status, retryable in [(307, False), (401, False), (408, True), (429, True), (503, True)]:
            with self.subTest(status=status), receiver(status) as (url, requests):
                self.credentials(url)
                with self.assertRaises(DeliveryError) as caught:
                    post(self.payload)
                self.assertEqual(caught.exception.code, f'http_{status}')
                self.assertEqual(caught.exception.retryable, retryable)
                self.assertEqual(len(requests), 1)
                self.assertNotIn('secret-token', str(caught.exception))
                self.assertNotIn(url, str(caught.exception))

    def test_invalid_configuration_never_enters_transport(self):
        for credentials in [[], {}, {'url': 'file:///secret-token', 'key': 'secret-token'},
                            {'url': 'http://127.0.0.1:secret-token', 'key': 'secret-token'},
                            {'url': 'http://127.0.0.1', 'key': 'secret-token\nInjected: yes'}]:
            with self.subTest(credentials=credentials):
                self.path.write_text(json.dumps(credentials))
                with self.assertRaises(DeliveryError) as caught:
                    post(self.payload)
                self.assertFalse(caught.exception.retryable)
                self.assertNotIn('secret-token', str(caught.exception))

    def test_credentials_can_be_repaired_before_a_later_delivery_attempt(self):
        with self.assertRaises(DeliveryError) as caught:
            post(self.payload)
        self.assertEqual(caught.exception.code, 'credentials_missing')
        self.assertTrue(caught.exception.retryable)
        with receiver() as (url, requests):
            self.credentials(url)
            post(self.payload)
        self.assertEqual(len(requests), 1)


if __name__ == '__main__':
    unittest.main()
