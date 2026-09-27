# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Regression coverage for the multi-language i18n audit."""

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("check_i18n", Path(__file__).parents[1] / "check-i18n.py")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


def ts_file(language: str, context: str, messages: list[str]) -> str:
    body = "".join(f"    {message}\n" for message in messages)
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        f'<TS version="2.1" language="{language}">\n'
        f"<context>\n    <name>{context}</name>\n{body}</context>\n</TS>\n"
    )


def plain(source: str, translation: str) -> str:
    return f"<message>\n        <source>{source}</source>\n" \
           f"        <translation>{translation}</translation>\n    </message>"


def vanished(source: str, translation: str = "old") -> str:
    return f"<message>\n        <source>{source}</source>\n" \
           f'        <translation type="vanished">{translation}</translation>\n    </message>'


def obsolete(source: str, translation: str = "old") -> str:
    return f"<message>\n        <source>{source}</source>\n" \
           f'        <translation type="obsolete">{translation}</translation>\n    </message>'


def unfinished(source: str, translation: str = "") -> str:
    return f"<message>\n        <source>{source}</source>\n" \
           f'        <translation type="unfinished">{translation}</translation>\n    </message>'


def plural(source: str, forms: list[str]) -> str:
    numerus = "".join(
        f"<numerusform>{form}</numerusform>" for form in forms
    ) or "<numerusform />"
    return f'<message numerus="yes">\n        <source>{source}</source>\n' \
           f"        <translation>\n            {numerus}\n        </translation>\n    </message>"


class MultiLanguageAuditTest(unittest.TestCase):
    def build_root(self, qml: str, ui: dict = None, dynamic: dict = None) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        qml_dir = root / "apps/client-qt/qml"
        qml_dir.mkdir(parents=True)
        (qml_dir / "Screen.qml").write_text(qml, encoding="utf-8")
        i18n_dir = root / "apps/client-qt/i18n"
        i18n_dir.mkdir(parents=True)
        for locale, language_spec in checker.LANGUAGES.items():
            ui_messages = (ui or {}).get(locale, ["<message id='none' />"])
            dynamic_messages = (dynamic or {}).get(locale, ["<message id='none' />"])
            (i18n_dir / f"{language_spec.ui_file}.ts").write_text(
                ts_file(locale, "Screen", ui_messages), encoding="utf-8")
            (i18n_dir / f"{language_spec.dynamic_file}.ts").write_text(
                ts_file(locale, "HexproofDynamic", dynamic_messages), encoding="utf-8")
        return root

    def audit_language(self, root: Path, locale: str = "zh_CN") -> dict:
        return checker.audit(root)["languages"][locale]

    def test_vanished_entries_never_satisfy_literal_coverage(self):
        qml = 'Item { property string label: qsTr("Gone") }'
        root = self.build_root(qml, ui={"zh_CN": [vanished("Gone")]})
        language = self.audit_language(root)
        self.assertIn(("Screen", "Gone"), [tuple(k) for k in language["ui_missing"]])
        self.assertEqual(language["ui_vanished"], 1)
        self.assertEqual(language["ui_messages"], 0)

    def test_translated_entries_cover_literals(self):
        qml = 'Item { property string label: qsTr("Here") }'
        root = self.build_root(qml, ui={"zh_CN": [plain("Here", "这里")]})
        language = self.audit_language(root)
        self.assertEqual(language["ui_missing"], [])
        self.assertEqual(language["ui_translated"], 1)

    def test_unfinished_and_empty_translations_are_flagged(self):
        qml = 'Item { property string a: qsTr("A") }'
        root = self.build_root(qml, ui={"zh_CN": [
            unfinished("A"), plain("B", ""), plain("C", "好的")]})
        language = self.audit_language(root)
        self.assertIn(("Screen", "A"), [tuple(k) for k in language["ui_unfinished"]])
        self.assertIn(("Screen", "B"), [tuple(k) for k in language["ui_unfinished"]])
        self.assertNotIn(("Screen", "C"), [tuple(k) for k in language["ui_unfinished"]])
        self.assertEqual(language["ui_translated"], 1)

    def test_populated_unfinished_messages_fail_strict_audit(self):
        for domain in ("ui", "dynamic"):
            for numerus in (False, True):
                with self.subTest(domain=domain, numerus=numerus):
                    catalogs = {
                        locale: [plain("Hello", "Bonjour"),
                                 plural("%n card(s)", ["%n carte"] * spec.plural_forms)]
                        for locale, spec in checker.LANGUAGES.items()
                    }
                    root = self.build_root(
                        'Item { property string label: qsTr("Hello") }',
                        ui=catalogs, dynamic=catalogs)
                    context = "Screen" if domain == "ui" else "HexproofDynamic"
                    messages = list(catalogs["fr"])
                    index = 1 if numerus else 0
                    source = "%n card(s)" if numerus else "Hello"
                    messages[index] = messages[index].replace(
                        "<translation>", '<translation type="unfinished">')
                    filename = getattr(checker.LANGUAGES["fr"], f"{domain}_file")
                    (root / "apps/client-qt/i18n" / f"{filename}.ts").write_text(
                        ts_file("fr", context, messages), encoding="utf-8")

                    report = self.audit_language(root, "fr")
                    self.assertEqual(report[f"{domain}_unfinished"], [(context, source)])
                    self.assertEqual(report[f"{domain}_translated"], 1)
                    self.assertEqual(report["ui_missing"], [])
                    self.assertEqual(report["dynamic_missing"], [])
                    self.assertEqual(report["plural_issues"], [])
                    command = [sys.executable, str(Path(checker.__file__)),
                               "--root", str(root)]
                    strict = subprocess.run(command + ["--strict"],
                                            capture_output=True, text=True)
                    self.assertEqual(strict.returncode, 1, strict.stdout + strict.stderr)
                    self.assertIn(f"unfinished: {context}: {source}", strict.stderr)
                    advisory = subprocess.run(command, capture_output=True, text=True)
                    self.assertEqual(advisory.returncode, 0, advisory.stderr)
                    self.assertIn(f"unfinished: {context}: {source}", advisory.stdout)

    def test_placeholder_mismatch_is_flagged(self):
        qml = 'Item { property string a: qsTr("Moved %1") }'
        root = self.build_root(qml, ui={"zh_CN": [
            plain("Moved %1", "移走了"),          # dropped %1
            plain("Took %2", "拿了 %1"),          # wrong index
            plain("Score %1–%2", "%2：%1"),       # reordering is fine
        ]})
        language = self.audit_language(root)
        flagged = [tuple(key) for key, _ in language["placeholder_issues"]]
        self.assertIn(("Screen", "Moved %1"), flagged)
        self.assertIn(("Screen", "Took %2"), flagged)
        self.assertNotIn(("Screen", "Score %1–%2"), flagged)

    def test_percent_without_placeholder_is_not_corrupted(self):
        qml = 'Item { property string a: qsTr("50% sold") }'
        root = self.build_root(qml, ui={"zh_CN": [plain("50% sold", "已售出 50%")]})
        language = self.audit_language(root)
        self.assertEqual(language["placeholder_issues"], [])

    def test_plural_form_counts_follow_language_rules(self):
        qml = 'Item { property string a: qsTr("%n deck(s)") }'
        root = self.build_root(qml, ui={
            "zh_CN": [plural("%n deck(s)", ["%n 副套牌"])],
            "ja": [plural("%n deck(s)", ["%n デッキ"])],
            "de": [plural("%n deck(s)", ["%n Deck", "%n Decks"])],
            "fr": [plural("%n deck(s)", ["%n deck", "%n decks"])],
        })
        for locale in ("zh_CN", "ja", "de", "fr"):
            language = self.audit_language(root, locale)
            self.assertEqual(language["plural_issues"], [], locale)
            self.assertEqual(language["ui_translated"], 1, locale)

    def test_wrong_plural_form_count_is_flagged(self):
        qml = 'Item { property string a: qsTr("%n deck(s)") }'
        root = self.build_root(qml, ui={
            "de": [plural("%n deck(s)", ["%n Deck"])],         # needs two forms
            "fr": [plural("%n deck(s)", ["%n deck", "", ])],   # empty second form
        })
        german = self.audit_language(root, "de")
        self.assertIn(("Screen", "%n deck(s)"),
                      [tuple(key) for key, _ in german["plural_issues"]])
        french = self.audit_language(root, "fr")
        self.assertIn(("Screen", "%n deck(s)"),
                      [tuple(k) for k in french["ui_unfinished"]])

    def test_unfinished_plural_skeleton_is_unfinished_not_malformed(self):
        qml = 'Item { property string a: qsTr("%n deck(s)") }'
        root = self.build_root(qml, ui={"de": [plural("%n deck(s)", [""])]})
        language = self.audit_language(root, "de")
        self.assertIn(("Screen", "%n deck(s)"),
                      [tuple(k) for k in language["ui_unfinished"]])
        self.assertEqual(language["plural_issues"], [])

    def test_dynamic_coverage_uses_simplified_chinese_template(self):
        qml = 'Item { property string a: qsTr("x") }'
        root = self.build_root(qml, ui={
            "zh_CN": [plain("x", "x")], "fr": [plain("x", "x")]},
            dynamic={
                "zh_CN": [plain("Runtime alpha", "甲"), plain("Runtime beta", "乙")],
                "fr": [plain("Runtime alpha", "alpha")],
                "de": [plain("Runtime alpha", "alpha"),
                       plain("Runtime beta", "beta"),
                       plain("Runtime gamma", "gamma")],
            })
        french = self.audit_language(root, "fr")
        self.assertEqual(french["dynamic_missing"], [("HexproofDynamic", "Runtime beta")])
        german = self.audit_language(root, "de")
        self.assertEqual(german["dynamic_missing"], [])
        self.assertEqual(german["dynamic_extra"], [("HexproofDynamic", "Runtime gamma")])

    def test_obsolete_entries_are_counted_not_required(self):
        qml = 'Item { property string a: qsTr("Fresh") }'
        root = self.build_root(qml, ui={"zh_CN": [
            plain("Fresh", "新鲜"), obsolete("Stale", "陈旧")]})
        language = self.audit_language(root)
        self.assertEqual(language["ui_missing"], [])
        self.assertEqual(language["ui_obsolete"], 1)

    def test_duplicate_messages_are_detected(self):
        qml = 'Item { property string a: qsTr("Dup") }'
        root = self.build_root(qml, ui={"zh_CN": [
            plain("Dup", "重一"), plain("Dup", "重二")]})
        language = self.audit_language(root)
        self.assertIn(("Screen", "Dup"), [tuple(k) for k in language["ui_duplicates"]])

    def test_literal_percent_n_in_user_text_survives(self):
        qml = 'Item { property string a: qsTr("Alice %2 drew") }'
        root = self.build_root(qml, ui={"fr": [plain("Alice %2 drew", "Alice %2 a pioché")]})
        language = self.audit_language(root, "fr")
        self.assertEqual(language["placeholder_issues"], [])


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
