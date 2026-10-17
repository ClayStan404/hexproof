# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Release feedback configuration stays separate, bounded and credential-free."""

import importlib.util
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("feedback_config", ROOT / "tools/write-feedback-config.py")
CONFIG = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONFIG)


class FeedbackConfigTests(unittest.TestCase):
    def enabled(self):
        return {"schemaVersion": 1, "enabled": True,
                "apiBase": "https://support.example.invalid/feedback/v1",
                "supportLabel": "Hexproof test operator",
                "privacyUrl": "https://support.example.invalid/privacy",
                "receiptOnlyApiBases": ["https://old.example.invalid/feedback/v1"]}

    def test_unconfigured_build_is_disabled(self):
        self.assertEqual(CONFIG.parse(""), CONFIG.DISABLED)
        self.assertEqual(CONFIG.parse(json.dumps(self.enabled())), self.enabled())

    def test_destinations_reject_credentials_redirect_shapes_and_invalid_ports(self):
        for endpoint in ("http://localhost/feedback/v1", "https://user:secret@example.invalid/feedback/v1",
                         "https://example.invalid/feedback/v1?secret=x", "https://example.invalid/feedback/v1#x",
                         "https://example.invalid/%2e%2e/feedback/v1", "https://example.invalid/../feedback/v1",
                         "https://example.invalid:65536/feedback/v1", "https://example.invalid/ws"):
            with self.subTest(endpoint=endpoint), self.assertRaises(ValueError):
                CONFIG.validate(dict(self.enabled(), apiBase=endpoint))
        with self.assertRaises(ValueError):
            CONFIG.validate(dict(self.enabled(), receiptOnlyApiBases=["http://custom-hub/feedback/v1"]))

    def test_unknown_fields_duplicates_and_size_fail_closed(self):
        for change in ({"smtpPassword": "must-never-be-embedded"}, {"schemaVersion": True},
                       {"supportLabel": ""}, {"receiptOnlyApiBases": ["https://old.example.invalid/feedback/v1"] * 2}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                CONFIG.validate(dict(self.enabled(), **change))
        with self.assertRaises(ValueError):
            CONFIG.parse('{"enabled":false,"enabled":true}')
        with self.assertRaises(ValueError):
            CONFIG.parse(" " * 16385)


if __name__ == "__main__":
    unittest.main()
