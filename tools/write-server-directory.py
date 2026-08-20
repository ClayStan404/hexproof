#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Validate a GitHub secret and write a private client server directory."""

from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import tempfile
from urllib.parse import urlsplit


SECRET_NAME = "HEXPROOF_PUBLIC_SERVERS_JSON"
SERVER_COUNT = 3


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
        url = server["url"]
        if not isinstance(url, str):
            raise ValueError(f"server {index} url must be a string")
        parsed = urlsplit(url.strip())
        if parsed.scheme not in {"ws", "wss"} or not parsed.hostname:
            raise ValueError(f"server {index} url must use ws:// or wss:// with a host")
        legacy_urls = server.get("legacyUrls", [])
        if not isinstance(legacy_urls, list):
            raise ValueError(f"server {index} legacyUrls must be an array")
        for legacy_index, legacy_url in enumerate(legacy_urls, start=1):
            if not isinstance(legacy_url, str):
                raise ValueError(
                    f"server {index} legacy URL {legacy_index} must be a string"
                )
            parsed_legacy = urlsplit(legacy_url.strip())
            if parsed_legacy.scheme not in {"ws", "wss"} or not parsed_legacy.hostname:
                raise ValueError(
                    f"server {index} legacy URL {legacy_index} must use ws:// or wss:// with a host"
                )
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
