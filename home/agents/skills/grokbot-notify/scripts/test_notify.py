import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread
import unittest


SCRIPT = Path(__file__).with_name("notify.py")


class NotifyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.requests = []

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                body = self.rfile.read(int(self.headers["Content-Length"]))
                cls.requests.append((self.path, dict(self.headers), json.loads(body)))
                status = {"/fail": 401, "/redirect": 307}.get(self.path, 204)
                self.send_response(status)
                if status == 307:
                    self.send_header("Location", "/destination")
                self.end_headers()
                if status == 401:
                    self.wfile.write(b"private response: test-secret")

            def log_message(self, *args):
                pass

        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.thread = Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.url = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / ".config/grokbot-webhook/credentials.json"
        self.path.parent.mkdir(parents=True)
        self.write_credentials({"url": self.url, "key": "test-secret"})
        self.requests.clear()

    def write_credentials(self, value):
        self.path.write_text(json.dumps(value))

    def run_notify(self, *args, thread_id="t3-thread-123"):
        env = {**os.environ, "HOME": self.directory.name, "T3CODE_THREAD_ID": thread_id,
               "CODEX_SESSION_ID": "wrong-session", "CODEX_THREAD_ID": "wrong-thread",
               "GROKBOT_WEBHOOK_URL": "http://127.0.0.1:1/ignored",
               "GROKBOT_WEBHOOK_KEY": "ignored", "NO_PROXY": "127.0.0.1"}
        result = subprocess.run([sys.executable, str(SCRIPT), *args], env=env,
                                capture_output=True, text=True, timeout=5)
        self.assertNotIn("test-secret", result.stdout + result.stderr)
        self.assertNotIn(self.url, result.stdout + result.stderr)
        return result

    def test_posts_bot_and_t3_thread_with_bearer_auth(self):
        grok_bot_id = 'bot "quoted" \\ value 日本語'
        result = self.run_notify(grok_bot_id)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "Grokbot notification sent.\n")
        self.assertEqual(len(self.requests), 1)
        path, headers, body = self.requests[0]
        self.assertEqual(path, "/")
        self.assertEqual(headers["Authorization"], "Bearer test-secret")
        self.assertEqual(headers["Content-Type"], "application/json")
        self.assertEqual(body, {"grok_bot_id": grok_bot_id, "t3_code_thread_id": "t3-thread-123"})

    def test_missing_or_extra_arguments_do_not_send(self):
        for args in ((), ("bot", "extra"), ("  ",)):
            with self.subTest(args=args):
                self.assertNotEqual(self.run_notify(*args).returncode, 0)
        self.assertEqual(self.requests, [])

    def test_missing_t3_thread_does_not_fall_back_to_codex(self):
        result = self.run_notify("bot", thread_id="")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("T3CODE_THREAD_ID is missing", result.stderr)
        self.assertEqual(self.requests, [])

    def test_missing_credentials_does_not_send(self):
        self.path.unlink()
        result = self.run_notify("bot")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Credentials not found", result.stderr)
        self.assertEqual(self.requests, [])

    def test_invalid_credentials_do_not_send_or_leak(self):
        values = [[], {}, {"url": self.url}, {"url": self.url, "key": 123},
                  {"url": "file:///private/test-secret", "key": "test-secret"},
                  {"url": self.url, "key": "test-secret\nInjected: value"}]
        for value in values:
            with self.subTest(value=value):
                self.write_credentials(value)
                result = self.run_notify("bot")
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("Traceback", result.stderr)
        self.path.write_text('{"key": "test-secret", broken')
        result = self.run_notify("bot")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Cannot read credentials JSON", result.stderr)
        self.assertEqual(self.requests, [])

    def test_http_failure_is_reported_without_retry_or_response_body(self):
        self.write_credentials({"url": self.url + "/fail", "key": "test-secret"})
        result = self.run_notify("bot")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("HTTP 401", result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(len(self.requests), 1)

    def test_redirect_is_not_followed(self):
        self.write_credentials({"url": self.url + "/redirect", "key": "test-secret"})
        result = self.run_notify("bot")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("HTTP 307", result.stderr)
        self.assertEqual(len(self.requests), 1)

    def test_connection_failure_is_reported_without_secrets(self):
        self.write_credentials({"url": "http://127.0.0.1:0", "key": "test-secret"})
        result = self.run_notify("bot")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Webhook request failed", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_malformed_http_url_does_not_leak(self):
        for url in ("http://127.0.0.1:test-secret", "http://127.0.0.1/\ntest-secret"):
            with self.subTest(url=url):
                self.write_credentials({"url": url, "key": "test-secret"})
                result = self.run_notify("bot")
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("Traceback", result.stderr)


if __name__ == "__main__":
    unittest.main()
