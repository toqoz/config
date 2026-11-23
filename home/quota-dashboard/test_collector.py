import json
import os
import tempfile
import unittest

import collector


class ToEpochTest(unittest.TestCase):
    def test_passthrough_seconds(self):
        self.assertEqual(collector.to_epoch(1795395299), 1795395299.0)

    def test_milliseconds(self):
        self.assertEqual(collector.to_epoch(1795395299000), 1795395299.0)

    def test_iso(self):
        self.assertEqual(collector.to_epoch("2026-11-20T22:59:59+00:00"), 1795215599.0)

    def test_missing(self):
        self.assertIsNone(collector.to_epoch(None))
        self.assertIsNone(collector.to_epoch("not a date"))


class CodexWindowTest(unittest.TestCase):
    def test_known_windows(self):
        self.assertEqual(collector.codex_window(300), "5h")
        self.assertEqual(collector.codex_window(10080), "weekly")
        self.assertEqual(collector.codex_window(44640), "monthly")

    def test_unknown_falls_back(self):
        self.assertEqual(collector.codex_window(None), "weekly")
        self.assertEqual(collector.codex_window("oops"), "weekly")


class CodexLogTest(unittest.TestCase):
    def write(self, lines):
        handle = tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False)
        for line in lines:
            handle.write(line + "\n")
        handle.close()
        self.addCleanup(os.unlink, handle.name)
        return handle.name

    def test_last_token_count_wins(self):
        path = self.write(
            [
                json.dumps({"type": "event_msg", "payload": {"type": "token_count", "rate_limits": {"primary": {"used_percent": 1}}}}),
                "not json",
                json.dumps({"type": "event_msg", "payload": {"type": "token_count", "rate_limits": {"primary": {"used_percent": 2}}}}),
            ]
        )
        found = collector.last_codex_rate_limits(path)
        self.assertEqual(found["rate_limits"]["primary"]["used_percent"], 2)

    def test_event_timestamp_is_observation_time(self):
        path = self.write([
            json.dumps({
                "timestamp": "2026-11-16T12:47:50.650Z",
                "type": "event_msg",
                "payload": {"type": "token_count", "rate_limits": {"primary": {"used_percent": 1}}},
            })
        ])
        found = collector.last_codex_rate_limits(path)
        self.assertAlmostEqual(found["observed_at"], 1794833270.65, places=2)

    def test_no_rate_limits(self):
        path = self.write([json.dumps({"type": "event_msg", "payload": {"type": "token_count"}})])
        self.assertIsNone(collector.last_codex_rate_limits(path))

    def test_tail_read_keeps_latest_lines(self):
        path = self.write([json.dumps({"i": i}) for i in range(50)])
        lines = collector.read_tail_lines(path, max_lines=5)
        self.assertEqual([json.loads(line)["i"] for line in lines], [45, 46, 47, 48, 49])

    def test_tail_read_keeps_a_complete_first_line(self):
        body = "".join(f"line{i}aaaa\n" for i in range(10))  # 10 bytes per line
        with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False) as handle:
            handle.write(body)
        self.addCleanup(os.unlink, handle.name)
        self.assertEqual(collector.read_tail_lines(handle.name, max_lines=10, max_bytes=20)[0], "line8aaaa")
        self.assertEqual(len(collector.read_tail_lines(handle.name, max_lines=10, max_bytes=20)), 2)

    def test_sessions_are_newest_first(self):
        with tempfile.TemporaryDirectory() as root:
            for index in range(3):
                path = os.path.join(root, f"{index}.jsonl")
                with open(path, "w") as handle:
                    handle.write("{}\n")
                os.utime(path, (1000 + index, 1000 + index))
            self.assertEqual(
                [os.path.basename(path) for path, _ in collector.codex_sessions(2, root)],
                ["2.jsonl", "1.jsonl"],
            )


class ClaudeIntervalTest(unittest.TestCase):
    def test_skips_until_the_next_window(self):
        instance = collector.Collector("remilis")
        instance.now = 1000.0
        self.assertTrue(instance.claude_due())
        instance.claude_next_at = 1000.0 + collector.CLAUDE_MIN_INTERVAL
        self.assertFalse(instance.claude_due())
        instance.now = instance.claude_next_at
        self.assertTrue(instance.claude_due())


class TokenParsingTest(unittest.TestCase):
    def test_claude_usage_is_split_into_kinds(self):
        record = {"message": {"usage": {
            "input_tokens": 2, "output_tokens": 227,
            "cache_read_input_tokens": 13765, "cache_creation_input_tokens": 17263}}}
        self.assertEqual(collector.claude_token_deltas(record),
                         {"input": 2, "output": 227, "cache_read": 13765, "cache_write": 17263})

    def test_codex_last_usage_excludes_cached_from_input(self):
        record = {"payload": {"type": "token_count", "info": {"last_token_usage": {
            "input_tokens": 240554, "cached_input_tokens": 239616, "output_tokens": 205}}}}
        self.assertEqual(collector.codex_token_deltas(record),
                         {"input": 938, "output": 205, "cache_read": 239616})

    def test_pi_usage_is_keyed_by_kind(self):
        record = {"type": "message", "message": {"role": "assistant", "usage": {
            "input": 25386, "output": 139, "cacheRead": 7, "cacheWrite": 0}}}
        self.assertEqual(collector.pi_token_deltas(record),
                         {"input": 25386, "output": 139, "cache_read": 7, "cache_write": 0})

    def test_unrelated_records_are_ignored(self):
        self.assertIsNone(collector.claude_token_deltas({"type": "user"}))
        self.assertIsNone(collector.codex_token_deltas({"payload": {"type": "turn"}}))
        self.assertIsNone(collector.pi_token_deltas({"type": "message", "message": {"role": "user"}}))

    def test_duplicate_claude_messages_count_once(self):
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "session.jsonl")
            line = json.dumps({"timestamp": "2026-11-19T00:00:00Z", "message": {
                "id": "msg_1", "model": "claude-x",
                "usage": {"input_tokens": 10, "output_tokens": 1}}})
            with open(path, "w") as handle:
                handle.write(line + "\n" + line + "\n")
            instance = collector.Collector("remilis")
            instance.now = collector.to_epoch("2026-11-19T01:00:00Z")
            instance._scan_first_time("claude_code", path, collector.claude_token_deltas, instance.now - 3600)
            self.assertEqual(instance.tokens["claude_code"]["anthropic"]["claude-x"]["input"], 10)

    def test_tail_read_starts_after_the_previous_offset(self):
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "session.jsonl")
            first = json.dumps({"timestamp": "2026-11-19T00:00:00Z", "message": {"id": "a", "model": "claude-x", "usage": {"input_tokens": 5}}})
            second = json.dumps({"timestamp": "2026-11-19T00:01:00Z", "message": {"id": "b", "model": "claude-x", "usage": {"input_tokens": 7}}})
            with open(path, "w") as handle:
                handle.write(first + "\n")
            instance = collector.Collector("remilis")
            instance.now = collector.to_epoch("2026-11-19T01:00:00Z")
            instance._scan_first_time("claude_code", path, collector.claude_token_deltas, instance.now - 7200)
            with open(path, "a") as handle:
                handle.write(second + "\n")
            instance._scan_tail("claude_code", path, collector.claude_token_deltas, instance.offsets[path])
            self.assertEqual(instance.tokens["claude_code"]["anthropic"]["claude-x"]["input"], 12)


class WindowSecondsTest(unittest.TestCase):
    def test_nominal_lengths_follow_the_window(self):
        instance = collector.Collector("remilis")
        instance.quota("claude_code", "5h", used_percent=10)
        instance.quota("claude_code", "weekly", used_percent=20)
        metrics = {m["name"]: m for m in instance.otlp_body()["resourceMetrics"][0]["scopeMetrics"][0]["metrics"]}
        values = [p["asDouble"] for p in metrics["quota_window_seconds"]["gauge"]["dataPoints"]]
        self.assertEqual(values, [18000.0, 604800.0])

    def test_explicit_length_wins(self):
        instance = collector.Collector("remilis")
        instance.quota("codex", "weekly", used_percent=20, window_seconds=3600)
        metrics = {m["name"]: m for m in instance.otlp_body()["resourceMetrics"][0]["scopeMetrics"][0]["metrics"]}
        self.assertEqual(metrics["quota_window_seconds"]["gauge"]["dataPoints"][0]["asDouble"], 3600.0)


class ErrorStateTest(unittest.TestCase):
    def test_counters_survive_a_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            state = os.path.join(directory, "state.json")
            first = collector.Collector("remilis", state)
            first.fail("codex", RuntimeError("boom"))
            first._save_state()
            second = collector.Collector("remilis", state)
            second.fail("codex", RuntimeError("boom"))
            body = second.otlp_body()
            metrics = {m["name"]: m for m in body["resourceMetrics"][0]["scopeMetrics"][0]["metrics"]}
            counts = {
                p["attributes"][0]["value"]["stringValue"]: p["asInt"]
                for p in metrics["collector_errors_total"]["sum"]["dataPoints"]
            }
            self.assertEqual(counts["codex"], "2")

    def test_broken_state_is_ignored(self):
        with tempfile.TemporaryDirectory() as directory:
            state = os.path.join(directory, "state.json")
            with open(state, "w") as handle:
                handle.write("{not json")
            instance = collector.Collector("remilis", state)
            self.assertEqual(instance.errors, {})


class OtlpBodyTest(unittest.TestCase):
    def test_gauge_datapoints_and_host(self):
        instance = collector.Collector("remilis")
        instance.quota("claude_code", "weekly", used_percent=58, resets_at=1795397999, observed_at=1795390000)
        body = instance.otlp_body()
        resource = body["resourceMetrics"][0]["resource"]["attributes"]
        self.assertEqual(
            resource,
            [
                {"key": "host.name", "value": {"stringValue": "remilis"}},
                {"key": "service.name", "value": {"stringValue": "quota-collector"}},
            ],
        )
        metrics = {m["name"]: m for m in body["resourceMetrics"][0]["scopeMetrics"][0]["metrics"]}
        self.assertEqual(
            set(metrics),
            {"quota_used_percent", "quota_resets_at_seconds", "quota_observed_at_seconds",
             "quota_window_seconds", "collector_errors_total"},
        )
        point = metrics["quota_used_percent"]["gauge"]["dataPoints"][0]
        self.assertEqual(point["asDouble"], 58.0)
        self.assertEqual(
            point["attributes"],
            [
                {"key": "service", "value": {"stringValue": "claude_code"}},
                {"key": "window", "value": {"stringValue": "weekly"}},
            ],
        )
        self.assertEqual(metrics["quota_resets_at_seconds"]["gauge"]["dataPoints"][0]["asInt"], "1795397999")

    def test_errors_become_monotonic_sum(self):
        instance = collector.Collector("forge01")
        instance.fail("codex", RuntimeError("boom"))
        instance.fail("codex", RuntimeError("boom"))
        instance.fail("ollama_cloud", RuntimeError("down"))
        body = instance.otlp_body()
        metrics = {m["name"]: m for m in body["resourceMetrics"][0]["scopeMetrics"][0]["metrics"]}
        errors = metrics["collector_errors_total"]["sum"]
        self.assertTrue(errors["isMonotonic"])
        self.assertEqual(errors["aggregationTemporality"], 2)
        counts = {p["attributes"][0]["value"]["stringValue"]: p["asInt"] for p in errors["dataPoints"]}
        self.assertEqual(counts, {"codex": "2", "ollama_cloud": "1", "claude_code": "0", "opencode_go": "0"})

    def test_scope_attribute_is_optional(self):
        instance = collector.Collector("remilis")
        instance.quota("claude_code", "weekly", used_percent=0, scope="Fable")
        instance.quota("claude_code", "5h", used_percent=1)
        metrics = {m["name"]: m for m in instance.otlp_body()["resourceMetrics"][0]["scopeMetrics"][0]["metrics"]}
        points = metrics["quota_used_percent"]["gauge"]["dataPoints"]
        keys = [tuple(attr["key"] for attr in point["attributes"]) for point in points]
        self.assertIn(("scope", "service", "window"), keys)
        self.assertIn(("service", "window"), keys)


if __name__ == "__main__":
    unittest.main()
