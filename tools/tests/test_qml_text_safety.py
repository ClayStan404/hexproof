#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import importlib.util
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "qml_text_safety", Path(__file__).resolve().parents[1] / "check-qml-text-safety.py"
)
safety = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(safety)


class QmlTextSafetyTests(unittest.TestCase):
    def test_plain_text_need_not_be_first(self):
        self.assertEqual(safety.check_source('''
            Text {
                id: label
                // A nested object and comment precede the format.
                font { pixelSize: 18 }
                text: "Text { textFormat: Text.RichText }"
                textFormat: /* explicit safe format */ Text.PlainText
                color: "white"
            }
        '''), [])

    def test_missing_or_dynamic_format_is_rejected(self):
        for binding in ("", "Text.AutoText", "Text.RichText", '"Text.PlainText"',
                        "condition ? Text.PlainText : Text.RichText",
                        "Text.PlainText + 1", "Text.PlainText\n + 1",
                        "Text.PlainText\n in object", "Text.PlainText\n instanceof Object",
                        "Text.PlainText\n ? Text.PlainText : Text.RichText"):
            with self.subTest(binding=binding):
                self.assertTrue(safety.check_source(f"Text {{ textFormat: {binding} }}"))

    def test_parent_cannot_borrow_child_format(self):
        errors = safety.check_source("Text { Text { textFormat: Text.PlainText } }")
        self.assertEqual(len(errors), 1)

    def test_parent_and_child_can_each_declare_safe_format(self):
        self.assertEqual(safety.check_source('''Text {
            Text { textFormat: Text.PlainText }
            textFormat: Text.PlainText;
        }'''), [])

    def test_comments_strings_and_regex_are_not_qml_nodes(self):
        self.assertEqual(safety.check_source('''Item {
            // Text { }
            /* MenuItem { visible: false } */
            property string example: "Text { }"
            property var pattern: /[{}]Text\\{/g
        }'''), [])

    def test_duplicate_format_is_rejected(self):
        self.assertTrue(safety.check_source('''Text {
            textFormat: Text.PlainText;
            textFormat: Text.RichText;
        }'''))

    def test_only_direct_menu_visibility_needs_wrapper(self):
        self.assertEqual(safety.check_source('''MenuItem {
            contentItem: Text { textFormat: Text.PlainText; visible: false }
        }'''), [])
        for kind in ("MenuItem", "MenuSeparator"):
            self.assertTrue(safety.check_source(f"{kind} {{ visible: false }}"))
            self.assertEqual(safety.check_source(f"Conditional{kind} {{ visible: false }}"), [])

    def test_malformed_input_fails_closed(self):
        for source in ('Text {', '}', 'Text { text: "broken }', '/* never closed'):
            with self.subTest(source=source), self.assertRaises(ValueError):
                safety.check_source(source)


if __name__ == "__main__":
    unittest.main()
