# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Release feedback configuration stays separate, bounded and credential-free."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("feedback_config", ROOT / "tools/write-feedback-config.py")
CONFIG = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONFIG)


class FeedbackConfigTests(unittest.TestCase):
    def enabled(self):
        return {"schemaVersion": 2, "enabled": True,
                "apiBase": "https://support.example.invalid/feedback/v2",
                "supportLabel": "Hexproof test operator",
                "privacyUrl": "https://support.example.invalid/privacy",
                "publicRepository": "example/project", "noticeRevision": "public-v1",
                "noticeText": "This submission and all attachments will be public.",
                "providerPolicyRevision": "none-v1",
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

    def test_public_consent_configuration_is_required_and_private_intake_is_retired(self):
        for change in ({"apiBase": "https://support.example.invalid/feedback/v1"},
                       {"schemaVersion": 1}, {"noticeRevision": ""}, {"noticeText": "  "},
                       {"noticeText": "a" * 8193}, {"noticeText": "a\x00b"},
                       {"noticeRevision": "revision\n2"}, {"providerPolicyRevision": ""},
                       {"publicRepository": ""}, {"publicRepository": "owner/repo/issues/1"}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                CONFIG.validate(dict(self.enabled(), **change))
        self.assertEqual(CONFIG.validate(dict(self.enabled(), receiptOnlyApiBases=[
            "https://old.example.invalid/feedback/v1", "https://old.example.invalid/feedback/v2"
        ]))["schemaVersion"], 2)

    def test_official_defaults_use_the_qualified_public_destination(self):
        value = CONFIG.parse((ROOT / "apps/client-qt/config/feedback.official.json").read_text())
        self.assertTrue(value["enabled"])
        self.assertEqual(value["apiBase"], "https://47.97.30.103/feedback/v2")
        self.assertEqual(value["privacyUrl"], "https://47.97.30.103/feedback/privacy")
        self.assertEqual(value["publicRepository"], "ClayStan404/hexproof")
        self.assertEqual(value["noticeRevision"], "hexproof-public-20261024-v1")
        self.assertEqual(value["providerPolicyRevision"], "hexproof-test-openai-multica-20261023-v1")
        self.assertIn("https://47.122.120.151/feedback/v1", value["receiptOnlyApiBases"])

    def test_packaging_defaults_are_used_and_environment_can_disable_them(self):
        with tempfile.TemporaryDirectory() as directory:
            defaults = Path(directory) / "defaults.json"
            defaults.write_text(json.dumps(self.enabled()))
            output = Path(directory) / "packaged.json"
            command = [sys.executable, str(ROOT / "tools/write-feedback-config.py"), str(output),
                       "--defaults", str(defaults)]
            env = dict(os.environ, HEXPROOF_FEEDBACK_CONFIG_JSON="")
            subprocess.run(command, env=env, check=True, capture_output=True)
            self.assertEqual(json.loads(output.read_text()), self.enabled())
            env["HEXPROOF_FEEDBACK_CONFIG_JSON"] = json.dumps(CONFIG.DISABLED)
            subprocess.run(command, env=env, check=True, capture_output=True)
            self.assertEqual(json.loads(output.read_text()), CONFIG.DISABLED)

    def test_packaging_writes_utf8_under_a_legacy_system_encoding(self):
        value = dict(self.enabled(), supportLabel="Hexproof 官方支持",
                     noticeText="此反馈将公开。\nAI 会参与处理。")
        with tempfile.TemporaryDirectory() as directory:
            defaults = Path(directory) / "defaults.json"
            defaults.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
            output = Path(directory) / "packaged.json"
            # Disable Python's UTF-8 mode and POSIX locale coercion. On Windows
            # this keeps the native legacy code page; on POSIX it forces ASCII.
            env = dict(os.environ, HEXPROOF_FEEDBACK_CONFIG_JSON="",
                       LC_ALL="C", PYTHONCOERCECLOCALE="0")
            result = subprocess.run([sys.executable, "-X", "utf8=0",
                                     str(ROOT / "tools/write-feedback-config.py"),
                                     str(output), "--defaults", str(defaults)],
                                    env=env, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(output.read_text(encoding="utf-8")), value)
            self.assertEqual(result.stdout, b"")

    def test_invalid_defaults_leave_prior_output_intact_and_do_not_print_secrets(self):
        with tempfile.TemporaryDirectory() as directory:
            defaults = Path(directory) / "defaults.json"
            defaults.write_text(json.dumps(dict(self.enabled(), smtpPassword="private-test-secret")))
            output = Path(directory) / "packaged.json"
            output.write_text("previous configuration")
            result = subprocess.run([sys.executable, str(ROOT / "tools/write-feedback-config.py"), str(output),
                                     "--defaults", str(defaults)], capture_output=True,
                                    env=dict(os.environ, HEXPROOF_FEEDBACK_CONFIG_JSON=""))
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(output.read_text(), "previous configuration")
            self.assertNotIn(b"private-test-secret", result.stdout + result.stderr)

    def receiver(self):
        client = self.enabled()
        return {"schemaVersion": 2, "publicUrl": client["apiBase"], "public": {
            "repository": client["publicRepository"], "noticeRevision": client["noticeRevision"],
            "noticeText": client["noticeText"], "providerPolicyRevision": client["providerPolicyRevision"],
            "tokenFile": "/nonexistent/private-github-token"}}

    def test_receiver_matching_covers_frozen_disclosure_and_destination(self):
        client = self.enabled()
        CONFIG.validate_receiver_match(client, json.dumps(self.receiver()))
        CONFIG.validate_receiver_match(dict(client, enabled=False), json.dumps(self.receiver()))
        for field in ("apiBase", "publicRepository", "noticeRevision", "noticeText", "providerPolicyRevision"):
            with self.subTest(field=field), self.assertRaises(ValueError):
                CONFIG.validate_receiver_match(dict(client, **{field: client[field] + "changed"}),
                                               json.dumps(self.receiver()))

    def test_receiver_matching_rejects_ambiguous_or_incompatible_input(self):
        for receiver in (dict(self.receiver(), schemaVersion=1), dict(self.receiver(), schemaVersion=True),
                         dict(self.receiver(), public=None), dict(self.receiver(), multica={}),
                         dict(self.receiver(), multica={"providerPolicyRevision": "none-v1"})):
            with self.subTest(receiver=receiver), self.assertRaises(ValueError):
                CONFIG.validate_receiver_match(self.enabled(), json.dumps(receiver))
        for raw in ('{"schemaVersion":2,"schemaVersion":2}', " " * 32769):
            with self.assertRaises(ValueError):
                CONFIG.validate_receiver_match(self.enabled(), raw)
        client = dict(self.enabled(), providerPolicyRevision="approved-team-v1")
        receiver = self.receiver()
        receiver["public"]["providerPolicyRevision"] = client["providerPolicyRevision"]
        receiver["multica"] = {"providerPolicyRevision": client["providerPolicyRevision"],
                               "webhookFile": "/nonexistent/private-webhook"}
        CONFIG.validate_receiver_match(client, json.dumps(receiver))

    def test_receiver_matching_cli_preserves_previous_output_on_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            defaults, receiver, output = (directory / name for name in ("client.json", "receiver.json", "output.json"))
            defaults.write_text(json.dumps(self.enabled()))
            receiver.write_text(json.dumps(self.receiver()))
            command = [sys.executable, str(ROOT / "tools/write-feedback-config.py"), str(output),
                       "--defaults", str(defaults), "--receiver-config", str(receiver)]
            env = dict(os.environ, HEXPROOF_FEEDBACK_CONFIG_JSON="")
            subprocess.run(command, env=env, check=True, capture_output=True)
            self.assertEqual(json.loads(output.read_text()), self.enabled())
            changed = self.receiver()
            changed["public"]["noticeText"] = "sensitive-test-value"
            receiver.write_text(json.dumps(changed))
            before = output.read_bytes()
            result = subprocess.run(command, env=env, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(output.read_bytes(), before)
            self.assertNotIn(b"sensitive-test-value", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
