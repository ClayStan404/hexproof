#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Package pinned Forge and Java archives for offline import by Hexproof players."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile
from urllib.parse import unquote, urlparse
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "apps/server/internal/runtimepkg/manifest.json"


def archive_path(asset, explicit, directory):
    if explicit is not None:
        return explicit
    if directory is not None:
        for name in (f"{asset['sha256']}.{asset['format']}",
                     unquote(Path(urlparse(asset["url"]).path).name)):
            candidate = directory / name
            if candidate.is_file():
                return candidate
    raise ValueError(f"Provide the unchanged archive from {asset['url']}")


def zip_entry(name):
    entry = zipfile.ZipInfo(name)
    entry.create_system = 3
    entry.external_attr = 0o100644 << 16
    entry.compress_type = zipfile.ZIP_STORED
    return entry


def build_pack(manifest_bytes, platform, forge_archive, java_archive, output):
    manifest = json.loads(manifest_bytes)
    if platform not in manifest["java"]:
        raise ValueError(f"Unsupported platform: {platform}")
    package_id = hashlib.sha256(manifest_bytes).hexdigest()[:20]
    metadata = {"schemaVersion": 1, "packageId": package_id, "platform": platform}
    output.parent.mkdir(parents=True, exist_ok=True)
    # Publish only complete, verified packs; never overwrite an existing file.
    with tempfile.NamedTemporaryFile(dir=output.parent, prefix=".forge-pack-", delete=False) as temp:
        temporary = Path(temp.name)
    try:
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_STORED) as pack:
            pack.writestr(zip_entry("forge-pack.json"), json.dumps(metadata, sort_keys=True) + "\n")
            for name, source, asset in (("forge", forge_archive, manifest["forge"]),
                                        ("java", java_archive, manifest["java"][platform])):
                if not source.is_file() or source.stat().st_size != asset["size"]:
                    raise ValueError(f"{name} archive has the wrong size: {source}")
                digest = hashlib.sha256()
                copied = 0
                with source.open("rb") as incoming, pack.open(zip_entry(f"{name}.{asset['format']}"), "w") as outgoing:
                    while chunk := incoming.read(1024 * 1024):
                        copied += len(chunk)
                        if copied > asset["size"]:
                            raise ValueError(f"{name} archive changed while packaging")
                        digest.update(chunk)
                        outgoing.write(chunk)
                if copied != asset["size"] or digest.hexdigest() != asset["sha256"]:
                    raise ValueError(f"{name} archive checksum mismatch: {source}")
        os.link(temporary, output)
    finally:
        temporary.unlink()
    with output.open("rb") as stream:
        checksum = hashlib.file_digest(stream, "sha256").hexdigest()
    return {**metadata, "file": str(output), "size": output.stat().st_size, "sha256": checksum}


def main():
    manifest_bytes = MANIFEST.read_bytes()
    manifest = json.loads(manifest_bytes)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", required=True, choices=sorted(manifest["java"]))
    parser.add_argument("--archive-dir", type=Path,
                        help="directory containing archives with their original or SHA-256 filenames")
    parser.add_argument("--forge-archive", type=Path, help="override the local Forge archive path")
    parser.add_argument("--java-archive", type=Path, help="override the local platform-specific Java archive path")
    parser.add_argument("--output", type=Path, help="new output file; defaults to build/forge-offline/")
    args = parser.parse_args()
    package_id = hashlib.sha256(manifest_bytes).hexdigest()[:20]
    output = args.output or ROOT / "build/forge-offline" / f"hexproof-forge-{args.platform}-{package_id}.hexproof-forgepack"
    try:
        forge_archive = archive_path(manifest["forge"], args.forge_archive, args.archive_dir)
        java_archive = archive_path(manifest["java"][args.platform], args.java_archive, args.archive_dir)
        report = build_pack(manifest_bytes, args.platform, forge_archive, java_archive, output)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Offline pack failed: {error}\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
