#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Validate and package public sponsors, avatars and announcement history."""

from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
MAX_DOCUMENT = 2 * 1024 * 1024
MAX_AVATAR = 1024 * 1024
MAX_REVISION = 9007199254740991


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def revision(value: object) -> bool:
    return type(value) is int and 1 <= value <= MAX_REVISION


def identifier(value: object) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,63}", value) is not None


def safe_path(value: object) -> bool:
    return (isinstance(value, str) and re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_./-]{0,511}", value) is not None
            and all(part not in ("", ".", "..") for part in value.split("/")))


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def valid_hash(value: object) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[a-f0-9]{64}", value) is not None


def text(value: object, maximum: int, empty: bool = False) -> bool:
    return (isinstance(value, str) and (empty or bool(value.strip()))
            and len(value.encode("utf-16-le")) // 2 <= maximum and "\0" not in value)


def translated(value: object, maximum: int) -> bool:
    return (isinstance(value, dict) and "en" in value and set(value) <= {"en", "zh"}
            and all(text(item, maximum) for item in value.values()))


def timestamp(value: object) -> datetime:
    require(isinstance(value, str) and len(value) <= 32 and value.endswith("Z"), "Use UTC ISO timestamps ending in Z")
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def validate_document(kind: str, document: dict) -> dict:
    require(isinstance(document, dict) and document.get("schemaVersion") == 1
            and type(document.get("schemaVersion")) is int, "Unsupported content schema")
    require(revision(document.get("revision")), "Content revision must be a positive integer")
    entries = document.get(kind)
    require(isinstance(entries, list) and len(entries) <= (512 if kind == "sponsors" else 2000), "Invalid content entries")
    seen = set()
    for entry in entries:
        require(isinstance(entry, dict) and identifier(entry.get("id")) and entry["id"] not in seen, "Entry IDs must be stable and unique")
        seen.add(entry["id"])
        if kind == "sponsors":
            require(text(entry.get("name"), 120), "Sponsor name is required")
            require(entry.get("tier") in {"omniscience", "dockside", "ragavan"}, "Unknown sponsor tier")
            require("featured" not in entry or type(entry["featured"]) is bool, "Invalid featured flag")
            require("description" not in entry or translated(entry["description"], 2000), "Invalid sponsor description")
            profile = entry.get("profileUrl")
            require(text(profile, 2048, True), "Invalid sponsor profile URL")
            if profile:
                url = urlsplit(profile)
                require(url.scheme == "https" and bool(url.hostname) and not url.username
                        and not url.password and url.port != 0 and not any(c.isspace() for c in profile), "Profile URLs must use HTTPS without credentials")
            if "avatar" in entry:
                avatar = entry["avatar"]
                require(isinstance(avatar, dict) and safe_path(avatar.get("path"))
                        and avatar["path"].startswith("avatars/") and valid_hash(avatar.get("sha256")), "Invalid avatar path/hash")
        else:
            require(revision(entry.get("notificationRevision")), "Invalid announcement notification revision")
            require(translated(entry.get("title"), 200) and translated(entry.get("body"), 32768), "Announcement needs localized title/body")
            published = timestamp(entry.get("publishedAt"))
            start = timestamp(entry["startsAt"]) if "startsAt" in entry else published
            if "expiresAt" in entry:
                require(timestamp(entry["expiresAt"]) > start, "Announcement expiry must follow its start")
            for flag in ("pinned", "withdrawn"):
                require(flag not in entry or type(entry[flag]) is bool, f"Invalid {flag} flag")
    if kind == "announcements":
        policy = document.get("display")
        require(isinstance(policy, dict) and policy.get("mode") in {"all", "recent", "selected"}, "Invalid announcement display mode")
        require(type(policy.get("recentDays")) is int and 1 <= policy["recentDays"] <= 36500, "Invalid announcement display window")
        selected = policy.get("selectedIds")
        require(isinstance(selected, list) and all(identifier(value) for value in selected)
                and len(set(selected)) == len(selected) and set(selected) <= seen, "Selected announcements must exist and be unique")
    return document


def validate_index(index: dict) -> dict:
    require(isinstance(index, dict) and type(index.get("schemaVersion")) is int
            and index["schemaVersion"] == 1 and revision(index.get("revision")), "Invalid content index")
    for kind in ("sponsors", "announcements"):
        item = index.get(kind)
        require(isinstance(item, dict) and revision(item.get("revision"))
                and safe_path(item.get("path")) and valid_hash(item.get("sha256")), "Invalid content descriptor")
    return index


def validate_update(previous: dict, following: dict, kind: str) -> None:
    require(following["revision"] >= previous["revision"], f"{kind}: revision must not decrease")
    if following["revision"] == previous["revision"]:
        require(following == previous, f"{kind}: increment revision before editing")
    if kind == "announcements":
        entries = {item["id"]: item for item in following[kind]}
        for old in previous[kind]:
            require(old["id"] in entries, "Keep complete announcement history; use withdrawn to hide an entry")
            require(entries[old["id"]]["notificationRevision"] >= old["notificationRevision"], "Notification revision must not decrease")


def package(sponsors: Path, announcements: Path, avatars: Path, output: Path, index_revision: int) -> dict:
    require(revision(index_revision), "Invalid index revision")
    require(not output.exists(), "Output must be a new directory")
    files = {}
    index = {"schemaVersion": 1, "revision": index_revision}
    for kind, source in (("sponsors", sponsors), ("announcements", announcements)):
        payload = source.read_bytes()
        require(len(payload) <= MAX_DOCUMENT, "Content document exceeds 2 MiB")
        document = validate_document(kind, json.loads(payload))
        digest = sha256(payload)
        folder = f"releases/{kind}-{document['revision']}-{digest}"
        path = folder + "/data.json"
        files[path] = payload
        index[kind] = {"revision": document["revision"], "path": path, "sha256": digest}
        if kind == "sponsors":
            for entry in document[kind]:
                if "avatar" not in entry:
                    continue
                avatar = entry["avatar"]
                source_avatar = (avatars / avatar["path"].removeprefix("avatars/")).resolve()
                require(source_avatar.is_relative_to(avatars.resolve()) and source_avatar.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"}, "Invalid avatar source")
                data = source_avatar.read_bytes()
                require(len(data) <= MAX_AVATAR and sha256(data) == avatar["sha256"], f"Avatar hash/size mismatch: {entry['id']}")
                files[folder + "/" + avatar["path"]] = data
    files["index.json"] = (json.dumps(index, indent=2) + "\n").encode()
    output.mkdir(parents=True)
    try:
        for path, data in files.items():
            destination = output / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
    except BaseException:
        shutil.rmtree(output)
        raise
    return index


def read_package(root: Path) -> tuple[dict, dict[str, bytes], dict[str, dict]]:
    payload = (root / "index.json").read_bytes()
    require(len(payload) <= 32768, "Content index is too large")
    index = validate_index(json.loads(payload))
    files = {"index.json": payload}
    documents = {}
    for kind in ("sponsors", "announcements"):
        descriptor = index[kind]
        path = descriptor["path"]
        require(path.startswith("releases/"), "Content must use immutable release paths")
        payload = (root / path).read_bytes()
        require(len(payload) <= MAX_DOCUMENT and sha256(payload) == descriptor["sha256"], "Content digest mismatch")
        document = validate_document(kind, json.loads(payload))
        require(document["revision"] == descriptor["revision"], "Content revision mismatch")
        documents[kind] = document
        files[path] = payload
        if kind == "sponsors":
            for entry in document[kind]:
                if "avatar" not in entry:
                    continue
                avatar = entry["avatar"]
                asset_path = str(Path(path).parent / avatar["path"])
                data = (root / asset_path).read_bytes()
                require(len(data) <= MAX_AVATAR and sha256(data) == avatar["sha256"], "Avatar digest mismatch")
                files[asset_path] = data
    return index, files, documents


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sponsors", type=Path, default=ROOT / "apps/client-qt/config/content/sponsors.json")
    parser.add_argument("--announcements", type=Path, default=ROOT / "apps/client-qt/config/content/announcements.json")
    parser.add_argument("--avatars", type=Path, default=ROOT / "apps/client-qt/assets/sponsors")
    parser.add_argument("--revision", required=True, type=int)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        index = package(args.sponsors, args.announcements, args.avatars, args.output, args.revision)
        print(f"Packaged content revision {index['revision']} in {args.output}")
        return 0
    except (OSError, ValueError, TypeError, KeyError) as error:
        print(f"Content packaging failed: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
