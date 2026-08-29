#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Audit literal QML qsTr() calls against the Simplified Chinese TS catalogs."""

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
TRANSLATOR_PRAGMA = re.compile(rf"pragma\s+Translator:\s*(?P<literal>{JSON_STRING})")

MessageKey = tuple[str, str]


def decode_literal(literal: str) -> str:
    return json.loads(literal)


def translated(translation: ET.Element | None) -> bool:
    if translation is None or translation.get("type") == "unfinished":
        return False
    forms = translation.findall("numerusform")
    if forms:
        return all((form.text or "").strip() for form in forms)
    return bool((translation.text or "").strip())


def catalog_messages(path: Path) -> tuple[set[MessageKey], list[MessageKey], list[MessageKey]]:
    root = ET.parse(path).getroot()
    keys: list[MessageKey] = []
    unfinished: list[MessageKey] = []
    for context in root.findall("context"):
        context_name = context.findtext("name") or ""
        for message in context.findall("message"):
            source = message.findtext("source") or ""
            key = (context_name, source)
            keys.append(key)
            if not translated(message.find("translation")):
                unfinished.append(key)
    duplicates = sorted(key for key, count in Counter(keys).items() if count > 1)
    return set(keys), duplicates, sorted(unfinished)


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
    return used


def format_key(key: MessageKey) -> str:
    return f"{key[0]}: {key[1]}"


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
    qml_root = root / "apps/client-qt/qml"
    catalogs = [
        root / "apps/client-qt/i18n/hexproof_zh_CN.ts",
        root / "apps/client-qt/i18n/hexproof_dynamic_zh_CN.ts",
    ]
    try:
        main_keys, main_duplicates, main_unfinished = catalog_messages(catalogs[0])
        dynamic_keys, dynamic_duplicates, dynamic_unfinished = catalog_messages(catalogs[1])
        used = used_literals(qml_root)
    except (OSError, ET.ParseError, json.JSONDecodeError, ValueError) as error:
        print(f"i18n audit failed: {error}", file=sys.stderr)
        return 2

    duplicates = main_duplicates + dynamic_duplicates
    unfinished = main_unfinished + dynamic_unfinished
    missing = sorted(used - main_keys)

    if duplicates:
        print("duplicate translation messages:", file=sys.stderr)
        for key in duplicates:
            print(f"  - {format_key(key)}", file=sys.stderr)
    if unfinished:
        stream = sys.stderr if args.strict else sys.stdout
        print("unfinished Simplified Chinese translations:", file=stream)
        for key in unfinished:
            print(f"  - {format_key(key)}", file=stream)
    if missing:
        stream = sys.stderr if args.strict else sys.stdout
        print("literal qsTr() strings missing from the main catalog:", file=stream)
        for key in missing:
            print(f"  - {format_key(key)}", file=stream)

    if args.unused:
        unused = sorted(main_keys - used)
        print(f"unused main-catalog entries: {len(unused)}")
        for key in unused:
            print(f"  - {format_key(key)}")

    print(
        f"i18n audit: {len(used)} literal calls, {len(main_keys)} UI messages, "
        f"{len(dynamic_keys)} dynamic messages, {len(missing)} missing, "
        f"{len(unfinished)} unfinished, {len(duplicates)} duplicate"
    )
    if duplicates or (args.strict and (missing or unfinished)):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
