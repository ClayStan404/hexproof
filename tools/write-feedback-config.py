#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Validate optional official feedback build configuration without printing it."""

import json
import os
from pathlib import Path
import sys
from urllib.parse import urlsplit


FIELDS = {"schemaVersion", "enabled", "apiBase", "supportLabel", "privacyUrl", "receiptOnlyApiBases"}
DISABLED = {"schemaVersion": 1, "enabled": False, "apiBase": "", "supportLabel": "",
            "privacyUrl": "", "receiptOnlyApiBases": []}


def https(value):
    if not isinstance(value, str) or len(value) > 2048 or any(ord(c) <= 32 for c in value) or "%" in value:
        return False
    try:
        url = urlsplit(value)
        return (url.scheme == "https" and bool(url.hostname) and url.username is None and
                url.password is None and not url.query and not url.fragment and
                ".." not in url.path and "//" not in url.path and
                (url.port is None or 1 <= url.port <= 65535))
    except ValueError:
        return False


def validate(value):
    if not isinstance(value, dict) or set(value) != FIELDS or type(value["schemaVersion"]) is not int or value["schemaVersion"] != 1 or type(value["enabled"]) is not bool:
        raise ValueError("Invalid feedback configuration schema")
    if not isinstance(value["supportLabel"], str) or len(value["supportLabel"]) > 120 or any(ord(c) < 32 for c in value["supportLabel"]):
        raise ValueError("Invalid feedback support label")
    for key in ("apiBase", "privacyUrl"):
        if not isinstance(value[key], str) or value[key] and not https(value[key]):
            raise ValueError("Feedback destinations must use trusted HTTPS URLs")
    if value["apiBase"] and urlsplit(value["apiBase"]).path.rstrip("/") != "/feedback/v1":
        raise ValueError("Feedback apiBase must include /feedback/v1")
    old = value["receiptOnlyApiBases"]
    if not isinstance(old, list) or len(old) > 8 or any(not https(item) or urlsplit(item).path.rstrip("/") != "/feedback/v1" for item in old) or len(set(old)) != len(old):
        raise ValueError("Invalid receipt-only feedback destinations")
    if value["enabled"] and (not value["apiBase"] or not value["privacyUrl"] or not value["supportLabel"].strip()):
        raise ValueError("Enabled feedback requires destination, organization and privacy notice")
    return value


def parse(raw):
    if len(raw.encode()) > 16384:
        raise ValueError("Feedback configuration exceeds its size bound")
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError("Duplicate feedback configuration key")
            result[key] = value
        return result
    return validate(json.loads(raw, object_pairs_hook=pairs)) if raw.strip() else dict(DISABLED)


def main():
    if len(sys.argv) != 2:
        raise ValueError("Supply the output configuration path")
    value = parse(os.environ.get("HEXPROOF_FEEDBACK_CONFIG_JSON", ""))
    destination = Path(sys.argv[1])
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError):
        sys.exit("Feedback configuration preparation failed; no configuration was printed.")
