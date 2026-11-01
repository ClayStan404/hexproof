#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Validate the offline reference against its independently pinned CR heading index."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "apps/client-qt/resources/keyword-reference.json"
MANIFEST = ROOT / "testdata/keyword-reference/headings-20260925.json"


def extract_headings(rules: bytes) -> list[dict[str, str]]:
    """Keep Unicode headings, including infinity, and exclude the two introductions."""
    text = rules.decode("utf-8-sig")
    return [
        {"rule": rule, "english": name, "category": "action" if rule.startswith("701.") else "ability"}
        for rule, name in re.findall(r"(?m)^(70[12]\.\d+)\. ([^\r\n]+)\r?$", text)
        if rule not in {"701.1", "702.1"}
    ]


def require_text(value: object, label: str) -> None:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label}: nonempty text required")
    if any(ord(char) < 32 and char not in "\n\t" for char in value) or "<" in value or ">" in value:
        raise ValueError(f"{label}: plain text required")
    if "verification in progress" in value.casefold() or "正在核验" in value:
        raise ValueError(f"{label}: unfinished content")


def validate(catalog: dict, manifest: dict, rules: bytes | None = None) -> None:
    if catalog.get("schemaVersion") != 1:
        raise ValueError("unsupported schemaVersion")
    source = catalog.get("source", {})
    if source != manifest.get("source"):
        raise ValueError("catalog source differs from pinned manifest")
    if not re.fullmatch(r"[0-9a-f]{64}", source.get("sha256", "")):
        raise ValueError("source SHA-256 required")
    if not re.fullmatch(r"https://media\.wizards\.com/\d{4}/downloads/MagicCompRules%20\d{8}\.txt", source.get("url", "")):
        raise ValueError("source must be the pinned official rules text URL")
    headings = manifest.get("headings", [])
    if not headings or len({heading["rule"] for heading in headings}) != len(headings):
        raise ValueError("invalid pinned headings")
    if rules is not None:
        if hashlib.sha256(rules).hexdigest() != source["sha256"]:
            raise ValueError("rules file does not match pinned SHA-256")
        if extract_headings(rules) != headings:
            raise ValueError("manifest does not match the official rules headings")

    entries = catalog.get("entries", [])
    actual = [{key: entry.get(key) for key in ("rule", "english", "category")} for entry in entries]
    if actual != headings:
        raise ValueError("reference must cover every pinned action and ability heading exactly once and in source order")
    if len({entry.get("id") for entry in entries}) != len(entries):
        raise ValueError("duplicate entry id")
    for entry in entries:
        if not re.fullmatch(r"(?:action|ability)-[a-z0-9]+(?:-[a-z0-9]+)*", entry.get("id", "")):
            raise ValueError(f"{entry.get('rule')}: invalid id")
        for key in ("english", "chinese", "summaryEn", "summaryZh"):
            require_text(entry.get(key), f"{entry['rule']} {key}")
        aliases = entry.get("aliases")
        if not isinstance(aliases, list):
            raise ValueError(f"{entry['rule']}: aliases must be a list")
        for alias in aliases:
            require_text(alias, f"{entry['rule']} alias")
        if len(set(aliases)) != len(aliases):
            raise ValueError(f"{entry['rule']}: duplicate alias")
    coverage = catalog.get("coverage", {})
    for category, key in (("action", "actions"), ("ability", "abilities")):
        if coverage.get(key) != sum(entry["category"] == category for entry in entries):
            raise ValueError(f"incorrect {key} coverage count")
    for key in ("notesEn", "notesZh"):
        require_text(coverage.get(key), f"coverage {key}")
    for key in ("noticeEn", "noticeZh"):
        require_text(catalog.get(key), key)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=CATALOG)
    parser.add_argument("--manifest", type=Path, default=MANIFEST)
    parser.add_argument("--rules", type=Path, help="optional locally downloaded exact official TXT; never downloads")
    parser.add_argument("--print-headings", action="store_true", help="print the heading-only index from --rules for a reviewed update")
    args = parser.parse_args()
    try:
        rules = args.rules.read_bytes() if args.rules else None
        if args.print_headings:
            if rules is None:
                parser.error("--print-headings requires --rules")
            print(json.dumps(extract_headings(rules), ensure_ascii=False, indent=2))
            return 0
        catalog = json.loads(args.catalog.read_text(encoding="utf-8"))
        manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
        validate(catalog, manifest, rules)
        print(f"keyword reference: {catalog['coverage']['actions']} actions, {catalog['coverage']['abilities']} abilities; pinned index complete")
        return 0
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError, KeyError, TypeError) as error:
        print(f"keyword reference: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
