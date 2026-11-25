import unittest

import api


class VectorTest(unittest.TestCase):
    def test_series_key_defaults(self):
        self.assertEqual(api.series_key({"service": "codex"}), ("codex", "", ""))

    def test_as_vectors_skips_broken_entries(self):
        result = [
            {"metric": {"service": "pi", "window": "5h"}, "value": [1, "42"]},
            {"metric": {"service": "pi"}, "value": []},
            {"metric": {}, "value": [1, "not a number"]},
        ]
        self.assertEqual(api.as_vectors(result), {("pi", "5h", ""): 42.0})


class QuotaTest(unittest.TestCase):
    def test_elapsed_and_overage(self):
        key = ("claude_code", "5h", "")
        now = 1_000_000
        quotas = api.build_quotas(
            used={key: 90.0},
            resets={key: now + 3600},
            observed={key: 30.0},
            windows={key: 18000},
            now=now,
        )
        self.assertEqual(
            quotas,
            [
                {
                    "service": "claude_code",
                    "window": "5h",
                    "scope": None,
                    "used_percent": 90.0,
                    "resets_at": now + 3600,
                    "elapsed_percent": 80.0,
                    "overage_points": 10.0,
                    "age_seconds": 30,
                }
            ],
        )

    def test_reset_in_the_past_counts_as_fully_elapsed(self):
        key = ("codex", "weekly", "")
        quotas = api.build_quotas({key: 10.0}, {key: 0}, {key: 5.0}, {key: 604800}, 1_000_000)
        self.assertEqual(quotas[0]["elapsed_percent"], 100.0)
        self.assertEqual(quotas[0]["overage_points"], -90.0)

    def test_missing_window_leaves_pace_empty(self):
        key = ("pi", "weekly", "")
        quotas = api.build_quotas({key: 10.0}, {key: 1_000_500}, {}, {}, 1_000_000)
        self.assertIsNone(quotas[0]["elapsed_percent"])
        self.assertIsNone(quotas[0]["overage_points"])

    def test_scope_is_preserved_and_rows_are_sorted(self):
        quotas = api.build_quotas(
            used={("claude_code", "weekly", "Fable"): 1.0, ("claude_code", "weekly", ""): 2.0},
            resets={},
            observed={},
            windows={},
            now=1_000_000,
        )
        self.assertEqual([row["scope"] for row in quotas], [None, "Fable"])


class TokenTest(unittest.TestCase):
    def test_rows_join_windows_and_sort_by_week(self):
        day = [
            {"metric": {"service": "pi", "provider": "ollama", "model": "a"}, "value": [1, "10"]},
            {"metric": {"service": "codex", "provider": "openai", "model": "b"}, "value": [1, "5"]},
        ]
        week = [
            {"metric": {"service": "pi", "provider": "ollama", "model": "a"}, "value": [1, "100"]},
            {"metric": {"service": "codex", "provider": "openai", "model": "b"}, "value": [1, "200"]},
        ]
        rows = api.build_tokens(day, week)
        self.assertEqual([row["model"] for row in rows], ["b", "a"])
        self.assertEqual(rows[0]["tokens_1d"], 5)
        self.assertEqual(rows[0]["tokens_7d"], 200)


if __name__ == "__main__":
    unittest.main()
