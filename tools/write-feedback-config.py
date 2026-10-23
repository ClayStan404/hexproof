#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Validate optional official feedback build configuration without printing it."""

import argparse
import json
import os
from pathlib import Path
import re
import sys
from urllib.parse import urlsplit


FIELDS = {"schemaVersion", "enabled", "apiBase", "supportLabel", "privacyUrl", "receiptOnlyApiBases",
          "publicRepository", "noticeRevision", "noticeText", "providerPolicyRevision"}
DISABLED = {"schemaVersion": 2, "enabled": False, "apiBase": "", "supportLabel": "",
            "privacyUrl": "", "receiptOnlyApiBases": [], "publicRepository": "",
            "noticeRevision": "", "noticeText": "", "providerPolicyRevision": ""}


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
    if not isinstance(value, dict) or set(value) != FIELDS or type(value["schemaVersion"]) is not int or value["schemaVersion"] != 2 or type(value["enabled"]) is not bool:
        raise ValueError("Invalid feedback configuration schema")
    if not isinstance(value["supportLabel"], str) or len(value["supportLabel"]) > 120 or any(ord(c) < 32 for c in value["supportLabel"]):
        raise ValueError("Invalid feedback support label")
    for key in ("apiBase", "privacyUrl"):
        if not isinstance(value[key], str) or value[key] and not https(value[key]):
            raise ValueError("Feedback destinations must use trusted HTTPS URLs")
    if value["apiBase"] and urlsplit(value["apiBase"]).path.rstrip("/") != "/feedback/v2":
        raise ValueError("Public feedback apiBase must include /feedback/v2")
    old = value["receiptOnlyApiBases"]
    if not isinstance(old, list) or len(old) > 8 or any(not https(item) or urlsplit(item).path.rstrip("/") not in ("/feedback/v1", "/feedback/v2") for item in old) or len(set(old)) != len(old):
        raise ValueError("Invalid receipt-only feedback destinations")
    for key in ("noticeRevision", "providerPolicyRevision"):
        if not isinstance(value[key], str) or (value[key] and not re.fullmatch(r"[A-Za-z0-9_.-]{1,80}", value[key])):
            raise ValueError("Invalid public feedback notice revision")
    repository = value["publicRepository"]
    if not isinstance(repository, str) or (repository and not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]{1,100}", repository)):
        raise ValueError("Invalid public feedback repository")
    notice = value["noticeText"]
    if not isinstance(notice, str) or len(notice.encode("utf-8")) > 8192 or any(ord(c) < 32 and c not in "\n\t" for c in notice):
        raise ValueError("Invalid public feedback disclosure")
    if value["enabled"] and (not value["apiBase"] or not value["privacyUrl"] or not value["supportLabel"].strip()
                             or not repository or not value["noticeRevision"] or not notice.strip()
                             or not value["providerPolicyRevision"]):
        raise ValueError("Enabled public feedback requires destination, organization and a versioned disclosure")
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


def validate_receiver_match(value, raw):
    """Compare public settings only; receiver credential files are never opened."""
    if len(raw.encode("utf-8")) > 32768:
        raise ValueError("Receiver configuration exceeds its size bound")
    def pairs(items):
        result = {}
        for key, item in items:
            if key in result:
                raise ValueError("Duplicate receiver configuration key")
            result[key] = item
        return result
    receiver = json.loads(raw, object_pairs_hook=pairs)
    if (not isinstance(receiver, dict) or type(receiver.get("schemaVersion")) is not int
            or receiver["schemaVersion"] != 2 or not isinstance(receiver.get("public"), dict)):
        raise ValueError("Matching requires a public V2 receiver configuration")
    public = receiver["public"]
    fields = {"publicRepository": "repository", "noticeRevision": "noticeRevision",
              "noticeText": "noticeText", "providerPolicyRevision": "providerPolicyRevision"}
    if (not value["apiBase"] or value["apiBase"] != receiver.get("publicUrl")
            or any(not value[key] or value[key] != public.get(other) for key, other in fields.items())):
        raise ValueError("Client and receiver publication settings differ")
    native = receiver.get("multica")
    if native is not None and (not isinstance(native, dict)
                              or native.get("providerPolicyRevision") != value["providerPolicyRevision"]
                              or value["providerPolicyRevision"] == "none-v1"):
        raise ValueError("Multica processing policy differs from the public disclosure")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--defaults", type=Path, help="Reviewed public build defaults; environment input takes precedence")
    parser.add_argument("--receiver-config", type=Path,
                        help="Require matching V2 public settings before writing; does not validate credentials or activate services")
    args = parser.parse_args()
    raw = os.environ.get("HEXPROOF_FEEDBACK_CONFIG_JSON", "")
    if not raw.strip() and args.defaults is not None:
        raw = args.defaults.read_text(encoding="utf-8")
    value = parse(raw)
    if args.receiver_config is not None:
        validate_receiver_match(value, args.receiver_config.read_text(encoding="utf-8"))
    destination = args.output
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError):
        sys.exit("Feedback configuration preparation failed; no configuration was printed.")
