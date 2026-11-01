#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Build an immutable, checksum-pinned home infrastructure deployment bundle.

The operator supplies a reviewed connector binary and externally verified
release/archive hashes. No game server is built, downloaded or published here.
Secrets are deployed separately and never enter the bundle.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import tarfile
import tempfile


ROOT = Path(__file__).resolve().parents[1]
MAX_EXPANDED = 4 * 1024**3


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def checked_archive(path: Path, expected: str, destination: Path) -> Path:
    if not re.fullmatch(r"[a-f0-9]{64}", expected) or digest(path) != expected:
        raise ValueError(f"Archive SHA-256 mismatch: {path.name}")
    destination.mkdir()
    with tarfile.open(path) as archive:
        members = archive.getmembers()
        if len(members) > 200_000 or sum(item.size for item in members) > MAX_EXPANDED:
            raise ValueError("Archive exceeds extraction limits")
        for item in members:
            # data_filter also validates resolved links before extraction.
            if "\n" in item.name or "\r" in item.name or item.name.startswith("/"):
                raise ValueError("Invalid archive path")
            tarfile.data_filter(item, destination)
        archive.extractall(destination, filter="data")
    roots = list(destination.iterdir())
    if len(roots) != 1 or not roots[0].is_dir() or roots[0].is_symlink():
        raise ValueError("Expected one archive root directory")
    return roots[0]


def forge_source_identity(sources: dict) -> dict:
    """Normalize source references from both legacy and archive-free bundles."""
    if not isinstance(sources, dict):
        raise ValueError("Invalid Forge source reference")
    name = sources.get("forgeSourceArchiveName")
    legacy = sources.get("forgeSourceArchive")
    if "forgeSourceArchive" in sources:
        if not isinstance(legacy, str) or not legacy.startswith("sources/"):
            raise ValueError("Invalid legacy Forge source path")
        legacy_name = legacy.removeprefix("sources/")
        if "forgeSourceArchiveName" in sources and name != legacy_name:
            raise ValueError("Conflicting Forge source references")
        name = legacy_name
    checksum = sources.get("forgeSourceArchiveSha256")
    if (not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]{0,254}", name)
            or not isinstance(checksum, str) or not re.fullmatch(r"[a-f0-9]{64}", checksum)):
        raise ValueError("Invalid Forge source reference")
    return {"forgeSourceArchiveName": name, "forgeSourceArchiveSha256": checksum}


def runtime_source_identity(release: Path) -> dict:
    reference = json.loads((release / "forge-runtime" / "SOURCE.json").read_text())
    if not isinstance(reference, dict) or reference.get("schemaVersion") != 2:
        raise ValueError("Invalid runtime Forge source reference")
    return forge_source_identity({"forgeSourceArchiveName": reference.get("archive"),
                                  "forgeSourceArchiveSha256": reference.get("sha256")})


def reference_forge_source(release: Path, archive: Path | None, expected: str | None) -> dict:
    """Verify centrally retained sources without copying them into a node."""
    if archive is None or expected is None:
        raise ValueError("Node bundle requires forge-source archive and SHA-256")
    if not re.fullmatch(r"[a-f0-9]{64}", expected) or digest(archive) != expected:
        raise ValueError("Forge source archive SHA-256 mismatch")
    reference = runtime_source_identity(release)
    if reference != {"forgeSourceArchiveName": archive.name, "forgeSourceArchiveSha256": expected}:
        raise ValueError("Forge runtime does not reference this matching source archive")
    return reference


def externalize_forge_source(release: Path, sources: dict) -> dict:
    """Migrate only the candidate copy; retain the original tree for rollback."""
    reference = forge_source_identity(sources)
    if reference != runtime_source_identity(release):
        raise ValueError("Manifest and runtime Forge source references differ")
    if "forgeSourceArchive" in sources:
        archive = release / sources["forgeSourceArchive"]
        if (archive.parent.is_symlink() or archive.is_symlink() or not archive.is_file()
                or digest(archive) != reference["forgeSourceArchiveSha256"]):
            raise ValueError("Legacy Forge source archive verification failed")
        archive.unlink()
        if not any(archive.parent.iterdir()):
            archive.parent.rmdir()
    result = dict(sources, **reference)
    result.pop("forgeSourceArchive", None)
    return result


def seal_tree(release: Path, kind: str, sources: dict) -> dict:
    records = []
    links = {}
    for path in sorted(release.rglob("*")):
        relative = path.relative_to(release).as_posix()
        if relative in ("manifest.json", "SHA256SUMS"):
            continue
        if path.is_symlink():
            if not path.resolve().is_relative_to(release):
                raise ValueError(f"Link escapes deployment: {relative}")
            links[relative] = os.readlink(path)
        elif path.is_file():
            records.append(f"{digest(path)}  {relative}\n")
    tree_digest = hashlib.sha256(("".join(records) + json.dumps(links, sort_keys=True)).encode()).hexdigest()
    manifest = {"schemaVersion": 1, "kind": kind, "releaseId": tree_digest[:24],
                "treeSha256": tree_digest, "sources": sources, "links": links}
    (release / "SHA256SUMS").write_text("".join(records))
    (release / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def upgrade_node(args: argparse.Namespace) -> dict:
    """Replace hub/connector from a verified release, retaining a sealed runtime."""
    base = args.upgrade_from.resolve(strict=True)
    output = args.output.resolve()
    if output.exists() or output.is_relative_to(base):
        raise ValueError("Choose a fresh output outside the base release")
    if not re.fullmatch(r"[a-f0-9]{64}", args.base_manifest_sha256 or ""):
        raise ValueError("Base manifest SHA-256 is required")
    spec = importlib.util.spec_from_file_location("home_installer", ROOT / "deploy/install-home-node.py")
    installer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(installer)
    previous = installer.verify_tree(base, args.base_manifest_sha256)
    if previous["kind"] != "node":
        raise ValueError("Upgrade requires a verified node release")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="home-upgrade-", dir=output.parent) as temporary:
        temporary = Path(temporary)
        server = checked_archive(args.hub_archive, args.hub_sha256, temporary / "hub")
        for name in ("hexproof-server", "hexproof-home"):
            binary = server / "bin" / name
            if binary.is_symlink() or not binary.is_file() or not binary.stat().st_mode & 0o111:
                raise ValueError(f"Missing regular executable in server archive: {name}")
        release = temporary / "release"
        shutil.copytree(base, release, symlinks=True)
        # Recheck the copy so a changed base cannot silently become a new baseline.
        installer.verify_tree(release, args.base_manifest_sha256)
        sources = externalize_forge_source(release, previous["sources"])
        shutil.rmtree(release / "server")
        shutil.move(server, release / "server")
        (release / "hexproof-home").unlink()
        shutil.copy2(release / "server/bin/hexproof-home", release / "hexproof-home")
        sources = dict(sources, sourceCommit=args.source_commit,
                       hubArchiveSha256=args.hub_sha256,
                       connectorSha256=digest(release / "hexproof-home"),
                       baseTreeSha256=previous["treeSha256"])
        manifest = seal_tree(release, "node", sources)
        installer.verify_tree(release)
        shutil.move(release, output)
    return {"directory": str(output), "manifestSha256": digest(output / "manifest.json"), **manifest}


def build(args: argparse.Namespace) -> dict:
    output = args.output.resolve()
    if output.exists():
        raise ValueError("Output already exists; choose a fresh bundle path")
    output.parent.mkdir(parents=True, exist_ok=True)
    source_binary = args.binary.resolve(strict=True)
    if not source_binary.is_file() or source_binary.is_symlink():
        raise ValueError("Connector must be a regular executable file")
    sources = {"connectorSha256": digest(source_binary), "sourceCommit": args.source_commit}
    with tempfile.TemporaryDirectory(prefix="home-bundle-", dir=output.parent) as temporary:
        temporary = Path(temporary)
        release = temporary / "release"
        release.mkdir()
        shutil.copy2(source_binary, release / "hexproof-home")
        (release / "hexproof-home").chmod(0o755)
        if args.kind == "node":
            expected_files = {"server": "bin/hexproof-server", "forge-runtime": "forge-harness.jar",
                              "java": "bin/java"}
            for kind, required in expected_files.items():
                prefix = {"server": "hub", "forge-runtime": "forge", "java": "java"}[kind]
                path, checksum = getattr(args, prefix + "_archive"), getattr(args, prefix + "_sha256")
                if path is None or checksum is None:
                    raise ValueError(f"Node bundle requires {prefix} archive and SHA-256")
                root = checked_archive(path, checksum, temporary / prefix)
                if not (root / required).is_file():
                    raise ValueError(f"Missing {kind} entry point: {required}")
                shutil.move(root, release / kind)
                sources[prefix + "ArchiveSha256"] = checksum
            sources.update(reference_forge_source(release, args.forge_source_archive,
                                                  args.forge_source_sha256))
        templates = release / "deploy"
        templates.mkdir()
        names = [f"hexproof-home-{args.kind}.service"]
        names += (["hexproof-home-hub.service"] if args.kind == "node" else
                  ["hexproof-home-nginx.inc"])
        for name in names:
            shutil.copy2(ROOT / "deploy" / "home" / name, templates / name)
        manifest = seal_tree(release, args.kind, sources)
        if getattr(args, "directory", False):
            shutil.move(release, output)
            return {"directory": str(output), "manifestSha256": digest(output / "manifest.json"), **manifest}
        with tarfile.open(output, "w:gz") as archive:
            archive.add(release, arcname="release")
    return {"archive": str(output), "sha256": digest(output), **manifest}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kind", choices=("gateway", "node"), required=True)
    parser.add_argument("--binary", type=Path)
    parser.add_argument("--source-commit", required=True,
                        help="Reviewed infrastructure source revision or snapshot ID")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--directory", action="store_true", help="Emit a sealed tree for incremental rsync transfer")
    parser.add_argument("--upgrade-from", type=Path, help="Preserve a verified node tree's Forge, Java and service files")
    parser.add_argument("--base-manifest-sha256", help="Required pinned manifest for --upgrade-from")
    for prefix in ("hub", "forge", "forge-source", "java"):
        parser.add_argument(f"--{prefix}-archive", type=Path)
        parser.add_argument(f"--{prefix}-sha256")
    args = parser.parse_args()
    if args.upgrade_from:
        if (args.kind != "node" or not args.directory or not args.base_manifest_sha256
                or not args.hub_archive or not args.hub_sha256 or args.binary
                or any(getattr(args, prefix + suffix) for prefix in ("forge", "forge_source", "java")
                       for suffix in ("_archive", "_sha256"))):
            parser.error("--upgrade-from requires node/directory, base manifest and hub archive; no other payload inputs")
    elif not args.binary or args.base_manifest_sha256:
        parser.error("A new bundle requires --binary; --base-manifest-sha256 requires --upgrade-from")
    try:
        print(json.dumps(upgrade_node(args) if args.upgrade_from else build(args), indent=2))
    except (ValueError, OSError, tarfile.TarError) as error:
        parser.exit(1, f"Home bundle failed: {error}\n")


if __name__ == "__main__":
    main()
