# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Regression coverage for default, pragma, and explicit QML translation contexts."""

import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("check_i18n", Path(__file__).parents[1] / "check-i18n.py")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class TranslationContextTest(unittest.TestCase):
    def test_explicit_context_overrides_file_and_pragma(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "Sidebar.qml").write_text(
                'pragma Translator: "Lobby"\n'
                'Item { property var options: [qsTr("Chat"), qsTranslate("Event", "Desk")] }',
                encoding="utf-8",
            )
            self.assertEqual(checker.used_literals(path), {("Lobby", "Chat"), ("Event", "Desk")})

    def test_explicit_call_does_not_mask_missing_default_context(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "Panel.qml").write_text(
                'Item { property var options: [qsTr("Missing"), qsTranslate(\n"Table", "Exile")] }',
                encoding="utf-8",
            )
            self.assertEqual(checker.used_literals(path), {("Panel", "Missing"), ("Table", "Exile")})


if __name__ == "__main__":
    unittest.main()
