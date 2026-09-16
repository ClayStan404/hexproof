#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Validate a GitHub secret and write a private client server directory."""

from __future__ import annotations

import json
import ipaddress
import os
from pathlib import Path
import re
import sys
import tempfile
from urllib.parse import urlsplit, urlunsplit


SECRET_NAME = "HEXPROOF_PUBLIC_SERVERS_JSON"
MAXIMUM_SERVERS = 32


def validate_server_url(value: object, label: str) -> None:
    if not isinstance(value, str) or len(value) > 2048:
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


def validate_directory_url(value: object) -> None:
    if not isinstance(value, str) or len(value) > 2048:
        raise ValueError("directory URL must be a bounded string")
    parsed = urlsplit(value)
    try:
        loopback = parsed.hostname == "localhost" or ipaddress.ip_address(parsed.hostname or "").is_loopback
    except ValueError:
        loopback = False
    if (not parsed.hostname or parsed.username or parsed.password or parsed.fragment
            or parsed.port == 0 or parsed.scheme not in ({"https", "http"} if loopback else {"https"})):
        raise ValueError("directory URLs require HTTPS (HTTP is allowed only on loopback)")
    validate_server_url(value.replace("https://", "wss://", 1).replace("http://", "ws://", 1), "directory URL")


def validate_directory(document: object) -> dict[str, object]:
    if not isinstance(document, dict) or type(document.get("schemaVersion")) is not int:
        raise ValueError("the directory requires schemaVersion and servers")
    if len(json.dumps(document, ensure_ascii=False).encode("utf-8")) > 64 * 1024:
        raise ValueError("the directory must not exceed 64 KiB")
    schema = document["schemaVersion"]
    if schema not in (1, 2):
        raise ValueError("schemaVersion must be 1 or 2")
    allowed = {"schemaVersion", "servers"} if schema == 1 else {"schemaVersion", "revision", "directoryUrls", "servers"}
    if not set(document).issubset(allowed) or "servers" not in document:
        raise ValueError("the directory contains unsupported fields")
    if schema == 2:
        revision = document.get("revision")
        if type(revision) is not int or not 1 <= revision <= 2**53 - 1:
            raise ValueError("revision must be a positive safe JSON integer")
        sources = document.get("directoryUrls", [])
        if not isinstance(sources, list) or len(sources) > 4:
            raise ValueError("directoryUrls must contain at most four sources")
        for source in sources:
            validate_directory_url(source)

    servers = document["servers"]
    if not isinstance(servers, list) or not (0 if schema == 2 else 1) <= len(servers) <= MAXIMUM_SERVERS:
        raise ValueError(f"servers must contain at most {MAXIMUM_SERVERS} entries")
    ids = set()
    urls = set()
    for index, server in enumerate(servers, start=1):
        fields = {"url", "legacyUrls"} if schema == 1 else {"id", "name", "sponsor", "url", "forge", "legacyUrls"}
        if not isinstance(server, dict) or not set(server).issubset(fields):
            raise ValueError(f"server {index} contains unsupported fields")
        if "url" not in server:
            raise ValueError(f"server {index} must contain url")
        validate_server_url(server["url"], f"server {index} url")
        endpoint = urlsplit(server["url"].strip())
        normalized = urlunsplit((endpoint.scheme, endpoint.netloc.lower(),
                                 "/ws" if endpoint.path in ("", "/") else endpoint.path,
                                 endpoint.query, ""))
        if normalized in urls:
            raise ValueError("server URLs must be unique")
        urls.add(normalized)
        if schema == 2:
            identifier = server.get("id")
            if (not isinstance(identifier, str) or not re.fullmatch(r"[a-z0-9_-]{1,64}", identifier)
                    or identifier == "custom" or identifier in ids):
                raise ValueError("server IDs must be unique, bounded identifiers")
            ids.add(identifier)
            name = server.get("name")
            if not isinstance(name, str) or not name.strip() or len(name) > 120:
                raise ValueError("server name must be a bounded, nonempty string")
            if type(server.get("forge")) is not bool:
                raise ValueError("forge must be a boolean")
            sponsor = server.get("sponsor", "")
            if not isinstance(sponsor, str) or len(sponsor) > 120:
                raise ValueError("sponsor must be a bounded string")
            validate_directory_url(server["url"].replace("wss://", "https://", 1).replace("ws://", "http://", 1))
            if urlsplit(server["url"]).query:
                raise ValueError("public server URLs must not contain a query")
        legacy_urls = server.get("legacyUrls", [])
        if not isinstance(legacy_urls, list) or len(legacy_urls) > 8:
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
