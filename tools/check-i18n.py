#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Audit literal QML translation calls against every UI language's TS catalogs.

Coverage boundary (what this static audit can and cannot see):

- The main catalogs are produced by lupdate over the application sources, so
  they also contain messages that only C++ code emits; the "missing" check can
  only require the messages that a literal ``qsTr``/``qsTranslate`` call in a
  ``.qml`` file proves are used. Dynamically built source strings (the
  ``HexproofDynamic`` catalog) are instead compared against the Simplified
  Chinese dynamic catalog, which is the manually maintained template list.
- ``vanished``/``obsolete`` entries are historical: they never satisfy a
  coverage requirement and never mask a missing message.
- Runtime-only behavior (catalog loading, plural selection, fallback) is
  covered by the QML/C++ tests, not by this file audit.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

JSON_STRING = r'"(?:\\.|[^"\\])*"'
TRANSLATION_CALL = re.compile(rf"qsTr\(\s*(?P<literal>{JSON_STRING})", re.DOTALL)
EXPLICIT_TRANSLATION_CALL = re.compile(
    rf"qsTranslate\(\s*(?P<context>{JSON_STRING})\s*,\s*(?P<literal>{JSON_STRING})",
    re.DOTALL,
)
TRANSLATOR_PRAGMA = re.compile(rf"pragma\s+Translator:\s*(?P<literal>{JSON_STRING})")
PLACEHOLDER = re.compile(r"%(?:L(?:n|\d{1,2})|n|\d{1,2})")
VANISHED_TYPES = ("vanished", "obsolete")

MessageKey = tuple[str, str]


class LanguageSpec:
    def __init__(self, locale: str, ui_file: str, dynamic_file: str, plural_forms: int):
        self.locale = locale
        self.ui_file = ui_file
        self.dynamic_file = dynamic_file
        self.plural_forms = plural_forms


# Mirrors the UI language registry in apps/client-qt/src/UiLanguages.h and the
# CMake locale lists; all three must change together. English is the source
# language and has no catalogs.
LANGUAGES: dict[str, LanguageSpec] = {
    "zh_CN": LanguageSpec("zh_CN", "hexproof_zh_CN", "hexproof_dynamic_zh_CN", 1),
    "ja": LanguageSpec("ja", "hexproof_ja", "hexproof_dynamic_ja", 1),
    "fr": LanguageSpec("fr", "hexproof_fr", "hexproof_dynamic_fr", 2),
    "de": LanguageSpec("de", "hexproof_de", "hexproof_dynamic_de", 2),
    "es": LanguageSpec("es", "hexproof_es", "hexproof_dynamic_es", 2),
    "it": LanguageSpec("it", "hexproof_it", "hexproof_dynamic_it", 2),
    "pt_BR": LanguageSpec("pt_BR", "hexproof_pt_BR", "hexproof_dynamic_pt_BR", 2),
    "zh_TW": LanguageSpec("zh_TW", "hexproof_zh_TW", "hexproof_dynamic_zh_TW", 1),
}
# The Simplified Chinese dynamic catalog is the authoritative hand-maintained
# template list every other dynamic catalog must cover.
REFERENCE_LANGUAGE = "zh_CN"


class CatalogReport:
    def __init__(self) -> None:
        self.keys: list[MessageKey] = []
        self.valid_key_set: set[MessageKey] = set()
        self.duplicates: list[MessageKey] = []
        self.unfinished: list[MessageKey] = []
        self.placeholder_issues: list[tuple[MessageKey, str]] = []
        self.plural_issues: list[tuple[MessageKey, str]] = []
        self.translated: int = 0
        self.vanished: int = 0
        self.obsolete: int = 0


def decode_literal(literal: str) -> str:
    return json.loads(literal)


def translation_forms(translation: ET.Element | None) -> list[str]:
    if translation is None:
        return []
    numerus = translation.findall("numerusform")
    if numerus:
        return [form.text or "" for form in numerus]
    return [translation.text or ""]


def parse_catalog(path: Path, plural_forms: int) -> CatalogReport:
    root = ET.parse(path).getroot()
    report = CatalogReport()
    for context in root.findall("context"):
        context_name = context.findtext("name") or ""
        for message in context.findall("message"):
            source = message.findtext("source") or ""
            key = (context_name, source)
            report.keys.append(key)
            translation = message.find("translation")
            status = translation.get("type") if translation is not None else None
            if status in VANISHED_TYPES:
                if status == "vanished":
                    report.vanished += 1
                else:
                    report.obsolete += 1
                continue
            report.valid_key_set.add(key)
            if status == "unfinished":
                report.unfinished.append(key)
                continue
            forms = translation_forms(translation)
            if message.get("numerus") == "yes":
                if len(forms) != plural_forms:
                    if all(not form.strip() for form in forms):
                        report.unfinished.append(key)
                    else:
                        report.plural_issues.append(
                            (key, f"expected {plural_forms} plural form(s), found {len(forms)}"))
                    continue
                if not all(form.strip() for form in forms):
                    report.unfinished.append(key)
                    continue
            else:
                if not forms or not forms[0].strip():
                    report.unfinished.append(key)
                    continue
                if translation is not None and translation.findall("numerusform"):
                    report.plural_issues.append(
                        (key, "plural forms on a non-plural message"))
                    continue
            source_tokens = sorted(PLACEHOLDER.findall(source))
            for form in forms:
                target_tokens = sorted(PLACEHOLDER.findall(form))
                if target_tokens != source_tokens:
                    missing = [token for token in source_tokens
                               if target_tokens.count(token) < source_tokens.count(token)]
                    extra = [token for token in target_tokens
                             if source_tokens.count(token) < target_tokens.count(token)]
                    detail = f"placeholder mismatch (missing {missing}, extra {extra})"
                    report.placeholder_issues.append((key, detail))
            report.translated += 1
    report.duplicates = sorted(key for key, count in Counter(report.keys).items()
                               if count > 1)
    report.unfinished = sorted(set(report.unfinished))
    return report


def used_literals(qml_root: Path) -> set[MessageKey]:
    used: set[MessageKey] = set()
    for path in sorted(qml_root.rglob("*.qml")):
        text = path.read_text(encoding="utf-8")
        pragma = TRANSLATOR_PRAGMA.search(text)
        context = decode_literal(pragma.group("literal")) if pragma else path.stem
        used.update(
            (context, decode_literal(match.group("literal")))
            for match in TRANSLATION_CALL.finditer(text)
        )
        used.update(
            (decode_literal(match.group("context")), decode_literal(match.group("literal")))
            for match in EXPLICIT_TRANSLATION_CALL.finditer(text)
        )
    return used


def format_key(key: MessageKey) -> str:
    return f"{key[0]}: {key[1]}"


def language_reports(root: Path) -> tuple[set[MessageKey],
                                          dict[str, tuple[CatalogReport, CatalogReport]]]:
    qml_root = root / "apps/client-qt/qml"
    i18n_root = root / "apps/client-qt/i18n"
    used = used_literals(qml_root)
    reports: dict[str, tuple[CatalogReport, CatalogReport]] = {}
    for locale, spec in LANGUAGES.items():
        ui = parse_catalog(i18n_root / f"{spec.ui_file}.ts", spec.plural_forms)
        dynamic = parse_catalog(i18n_root / f"{spec.dynamic_file}.ts", spec.plural_forms)
        reports[locale] = (ui, dynamic)
    return used, reports


def audit(root: Path) -> dict[str, object]:
    """Return the full multi-language report used by both main() and tests."""
    used, reports = language_reports(root)
    reference_dynamic_keys = reports[REFERENCE_LANGUAGE][1].valid_key_set
    per_language: dict[str, dict[str, object]] = {}
    for locale, (ui, dynamic) in reports.items():
        per_language[locale] = {
            "ui_messages": len(ui.valid_key_set),
            "ui_translated": ui.translated,
            "ui_unfinished": ui.unfinished,
            "ui_missing": sorted(used - ui.valid_key_set),
            "ui_duplicates": ui.duplicates + dynamic.duplicates,
            "ui_vanished": ui.vanished,
            "ui_obsolete": ui.obsolete,
            "dynamic_messages": len(dynamic.valid_key_set),
            "dynamic_translated": dynamic.translated,
            "dynamic_unfinished": dynamic.unfinished,
            "dynamic_missing": sorted(reference_dynamic_keys - dynamic.valid_key_set),
            "dynamic_extra": sorted(dynamic.valid_key_set - reference_dynamic_keys),
            "placeholder_issues": ui.placeholder_issues + dynamic.placeholder_issues,
            "plural_issues": ui.plural_issues + dynamic.plural_issues,
        }
    return {"used": len(used), "languages": per_language}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument(
        "--strict",
        action="store_true",
        help="return failure for missing or unfinished translations",
    )
    parser.add_argument(
        "--unused",
        action="store_true",
        help="also print catalog entries not referenced by a literal qsTr() call",
    )
    args = parser.parse_args()

    root = args.root.resolve()
    try:
        result = audit(root)
    except (OSError, ET.ParseError, json.JSONDecodeError, ValueError) as error:
        print(f"i18n audit failed: {error}", file=sys.stderr)
        return 2

    used = int(result["used"])
    failed = False
    for locale, language in result["languages"].items():
        duplicates = language["ui_duplicates"]
        unfinished = language["ui_unfinished"] + language["dynamic_unfinished"]
        missing = language["ui_missing"]
        missing_dynamic = language["dynamic_missing"]
        issues = language["placeholder_issues"] + language["plural_issues"]
        print(
            f"{locale}: {language['ui_translated']}/{language['ui_messages']} UI messages "
            f"({len(missing)} missing, {len(language['ui_unfinished'])} unfinished, "
            f"{language['ui_vanished']} vanished, {language['ui_obsolete']} obsolete), "
            f"{language['dynamic_translated']}/{language['dynamic_messages']} dynamic "
            f"({len(missing_dynamic)} missing, {len(language['dynamic_extra'])} extra), "
            f"{len(issues)} placeholder/plural issue(s)"
        )
        detail_stream = sys.stderr if args.strict else sys.stdout
        if duplicates:
            failed = True
            print(f"{locale}: duplicate translation messages:", file=sys.stderr)
            for key in duplicates:
                print(f"  - {format_key(key)}", file=sys.stderr)
        if unfinished or missing or missing_dynamic or issues:
            if args.strict:
                failed = True
            print(f"{locale}: incomplete translations:", file=detail_stream)
            for key in missing:
                print(f"  - missing from UI catalog: {format_key(key)}", file=detail_stream)
            for key in missing_dynamic:
                print(f"  - missing from dynamic catalog: {format_key(key)}",
                      file=detail_stream)
            for key in unfinished:
                print(f"  - unfinished: {format_key(key)}", file=detail_stream)
            for key, detail in language["placeholder_issues"]:
                print(f"  - placeholder: {format_key(key)}: {detail}", file=detail_stream)
            for key, detail in language["plural_issues"]:
                print(f"  - plural: {format_key(key)}: {detail}", file=detail_stream)
        if args.unused and locale == REFERENCE_LANGUAGE:
            unused = sorted(
                reports_unused_keys(root))
            print(f"{locale}: {len(unused)} unused main-catalog entries")
            for key in unused:
                print(f"  - unused: {format_key(key)}")

    print(
        f"i18n audit: {used} literal calls, "
        f"{len(result['languages'])} language catalogs checked"
    )
    return 1 if failed else 0


def reports_unused_keys(root: Path) -> set[MessageKey]:
    """Main-catalog entries of the reference language without a literal caller."""
    used, reports = language_reports(root)
    return reports[REFERENCE_LANGUAGE][0].valid_key_set - used


if __name__ == "__main__":
    raise SystemExit(main())
