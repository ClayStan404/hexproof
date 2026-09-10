#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Validate a GitHub secret and write a private client server directory."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import sys
import tempfile
from urllib.parse import urlsplit


SECRET_NAME = "HEXPROOF_PUBLIC_SERVERS_JSON"
SERVER_COUNT = 5


def validate_server_url(value: object, label: str) -> None:
    if not isinstance(value, str):
        raise ValueError(f"{label} must be a string")
    normalized = value.strip()
    if (any(character.isspace() or ord(character) < 32 or ord(character) == 127
            for character in normalized)
            or re.search(r"%(?![0-9a-fA-F]{2})", normalized)):
        raise ValueError(f"{label} contains invalid whitespace or URL escaping")
    try:
        parsed = urlsplit(normalized)
        # urlsplit accepts an invalid port until this property is accessed.
        port = parsed.port
        valid = (parsed.scheme in {"ws", "wss"} and bool(parsed.hostname)
                 and (port is None or 1 <= port <= 65535))
    except ValueError:
        valid = False
    if not valid:
        # Do not echo endpoint values from the private release secret.
        raise ValueError(f"{label} must use ws:// or wss:// with a valid host and port")


def validate_directory(document: object) -> dict[str, object]:
    if not isinstance(document, dict) or set(document) != {"schemaVersion", "servers"}:
        raise ValueError("the directory must contain only schemaVersion and servers")
    if type(document["schemaVersion"]) is not int or document["schemaVersion"] != 1:
        raise ValueError("schemaVersion must be 1")

    servers = document["servers"]
    if not isinstance(servers, list) or len(servers) != SERVER_COUNT:
        raise ValueError(f"servers must contain exactly {SERVER_COUNT} entries")
    for index, server in enumerate(servers, start=1):
        if not isinstance(server, dict) or not set(server).issubset({"url", "legacyUrls"}):
            raise ValueError(f"server {index} contains unsupported fields")
        if "url" not in server:
            raise ValueError(f"server {index} must contain url")
        validate_server_url(server["url"], f"server {index} url")
        legacy_urls = server.get("legacyUrls", [])
        if not isinstance(legacy_urls, list):
            raise ValueError(f"server {index} legacyUrls must be an array")
        for legacy_index, legacy_url in enumerate(legacy_urls, start=1):
            validate_server_url(legacy_url, f"server {index} legacy URL {legacy_index}")
    return document


def write_private_directory(output_path: Path, secret: str) -> None:
    try:
        document = validate_directory(json.loads(secret))
    except (json.JSONDecodeError, ValueError) as error:
        raise ValueError(f"{SECRET_NAME} is invalid: {error}") from error

    output_path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{output_path.name}.", dir=output_path.parent
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as output:
            json.dump(document, output, ensure_ascii=True, indent=2)
            output.write("\n")
        os.chmod(temporary_path, 0o600)
        temporary_path.replace(output_path)
    except BaseException:
        temporary_path.unlink(missing_ok=True)
        raise


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} OUTPUT", file=sys.stderr)
        return 2
    secret = os.environ.get(SECRET_NAME, "")
    if not secret.strip():
        print(f"{SECRET_NAME} is not configured", file=sys.stderr)
        return 1
    try:
        write_private_directory(Path(sys.argv[1]), secret)
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
