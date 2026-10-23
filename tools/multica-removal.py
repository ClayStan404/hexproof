#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Quarantine or explicitly purge stopped, inventoried local copies without a receiver ACK."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys
import tempfile
import uuid

MAX_MANIFEST = 1024 * 1024
LABEL = re.compile(r"[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,127}\Z")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def unique_object(pairs: list[tuple]) -> dict:
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate manifest field")
        result[key] = value
    return result


def labels(values: object, name: str, nonempty: bool = False) -> None:
    require(isinstance(values, list) and len(values) <= 10000
            and (not nonempty or bool(values))
            and all(isinstance(value, str) and LABEL.fullmatch(value) for value in values)
            and len(set(values)) == len(values), f"Invalid {name}")


def read_manifest(path: Path) -> dict:
    require(path.stat().st_size <= MAX_MANIFEST, "Manifest exceeds 1 MiB")
    document = json.loads(path.read_text(), object_pairs_hook=unique_object)
    require(isinstance(document, dict) and set(document) == {
        "schemaVersion", "caseId", "binding", "revocationRevision", "family",
        "containmentEvidence", "localCopies", "nativeResiduals", "inventoryGaps"
    }, "Unexpected manifest fields")
    require(type(document["schemaVersion"]) is int and document["schemaVersion"] == 1,
            "Unsupported manifest schema")
    try:
        require(str(uuid.UUID(document["caseId"])) == document["caseId"], "Invalid case ID")
    except (TypeError, AttributeError, ValueError):
        raise ValueError("Invalid case ID") from None
    require(isinstance(document["binding"], str) and LABEL.fullmatch(document["binding"]),
            "Invalid processor binding")
    require(type(document["revocationRevision"]) is int
            and 0 < document["revocationRevision"] <= 9007199254740991, "Invalid revocation revision")
    family = document["family"]
    require(isinstance(family, dict) and set(family) == {"issues", "tasks", "inventoryEvidence"},
            "Invalid family inventory")
    for field in family:
        labels(family[field], "family " + field, field != "tasks")
    labels(document["containmentEvidence"], "containment evidence", True)
    labels(document["inventoryGaps"], "inventory gaps")
    copies = document["localCopies"]
    require(isinstance(copies, list) and len(copies) <= 10000, "Invalid local copies")
    seen = set()
    for entry in copies:
        require(isinstance(entry, dict) and set(entry) == {"id", "path"}, "Invalid local copy")
        require(isinstance(entry["id"], str) and LABEL.fullmatch(entry["id"])
                and entry["id"] not in seen, "Local copy IDs must be unique opaque labels")
        seen.add(entry["id"])
        relative = entry["path"]
        require(isinstance(relative, str) and 0 < len(relative) <= 4096
                and not Path(relative).is_absolute()
                and all(part not in {"", ".", ".."} for part in relative.split("/"))
                and "\\" not in relative and not any(ord(c) < 32 for c in relative), "Invalid copy path")
    residuals = document["nativeResiduals"]
    require(isinstance(residuals, list) and len(residuals) <= 10000, "Invalid native residuals")
    seen = set()
    for entry in residuals:
        require(isinstance(entry, dict) and set(entry) == {"id", "surface", "evidence"},
                "Invalid native residual")
        require(all(isinstance(entry[field], str) and LABEL.fullmatch(entry[field])
                    for field in ("id", "surface")) and entry["id"] not in seen,
                "Invalid native residual identity")
        seen.add(entry["id"])
        labels(entry["evidence"], "residual evidence", True)
    return document


def no_symlink_ancestors(path: Path) -> None:
    require(path.is_absolute(), "Use absolute root paths")
    for ancestor in (*reversed(path.parents), path):
        require(not ancestor.is_symlink(), "Symlink roots or ancestors are not allowed")


def inspect_tree(path: Path, device: int) -> tuple[int, int]:
    """Inspect metadata only; never follow links or load removed content."""
    info = path.lstat()
    require(info.st_dev == device, "Selected copy crosses a filesystem boundary")
    require(not stat.S_ISLNK(info.st_mode), "Symlinks are not allowed in a selected copy")
    if stat.S_ISREG(info.st_mode):
        require(info.st_nlink == 1, "Hard-linked copies need separate inventory")
        return 1, info.st_size
    require(stat.S_ISDIR(info.st_mode), "Only ordinary files and directories are supported")
    count, size = 0, 0
    for entry in path.iterdir():
        child_count, child_size = inspect_tree(entry, device)
        count += child_count
        size += child_size
    return count, size


def prepare(document: dict, source: Path, quarantine: Path) -> list[dict]:
    no_symlink_ancestors(source)
    no_symlink_ancestors(quarantine)
    require(source.is_dir() and source.resolve() == source, "Source root must be an existing canonical directory")
    require(source not in (Path("/"), Path.home()) and not Path.home().is_relative_to(source),
            "Select a dedicated task-artifact root")
    require(not quarantine.exists(), "Quarantine destination must not already exist")
    require(quarantine.parent.is_dir(), "Create the private quarantine parent first")
    require(quarantine.parent.resolve() == quarantine.parent, "Use a canonical quarantine parent")
    require(not source.is_relative_to(quarantine) and not quarantine.is_relative_to(source),
            "Source and quarantine roots must be separate")
    require(source.stat().st_dev == quarantine.parent.stat().st_dev,
            "Quarantine must be on the same filesystem for atomic moves")
    paths = []
    prepared = []
    for index, entry in enumerate(document["localCopies"]):
        path = source / entry["path"]
        no_symlink_ancestors(path)
        require(path.is_relative_to(source) and path != source, "Copy escapes source root")
        require(not any(path.is_relative_to(other) or other.is_relative_to(path) for other in paths),
                "Selected copies overlap")
        files, size = inspect_tree(path, quarantine.parent.stat().st_dev)
        paths.append(path)
        info = path.lstat()
        prepared.append({"id": entry["id"], "source": path, "destination": f"copy-{index:04d}",
                         "files": files, "bytes": size, "device": info.st_dev, "inode": info.st_ino})
    return prepared


def write_report(path: Path, report: dict) -> None:
    payload = (json.dumps(report, indent=2) + "\n").encode()
    descriptor, name = tempfile.mkstemp(prefix=".report-", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def present(path: Path) -> bool:
    try:
        path.lstat()
        return True
    except FileNotFoundError:
        return False


def record_presence(result: dict, source: Path, destination: Path) -> None:
    for key, path in (("sourcePresent", source), ("destinationPresent", destination)):
        try:
            result[key] = present(path)
        except OSError:
            result[key] = None


def local_residuals(report: dict) -> None:
    report["localResiduals"] = [
        {"id": entry["id"], "state": "retained-in-quarantine" if entry["state"] == "quarantined"
         else "retained-at-source" if entry["state"] in {"pending", "planned"} else "unverified"}
        for entry in report["localCopies"] if entry["state"] != "purged"
    ]


def purge_copy(target: Path, entry: dict) -> None:
    info = target.lstat()
    require((info.st_dev, info.st_ino) == (entry["device"], entry["inode"]),
            "Quarantined copy changed before purge")
    if stat.S_ISDIR(info.st_mode):
        os.chmod(target, 0o700)
        shutil.rmtree(target)
    else:
        require(stat.S_ISREG(info.st_mode), "Quarantined copy is not an ordinary file")
        target.unlink()


def quarantine_copies(document: dict, source: Path, destination: Path, apply: bool, purge: bool = False) -> dict:
    require(not purge or apply, "Local purge requires --apply")
    require(not purge or shutil.rmtree.avoids_symlink_attacks,
            "This platform lacks safe directory purge support")
    prepared = prepare(document, source, destination)
    report = {"schemaVersion": 1, "caseId": document["caseId"], "binding": document["binding"],
              "revocationRevision": document["revocationRevision"], "mode": "apply" if apply else "plan",
              "operation": "purge" if purge else "quarantine",
              "receiverAcknowledgementSupported": False, "removed": False,
              "nativeVerification": "not-performed", "family": document["family"],
              "localRoots": {"source": str(source), "quarantine": str(destination)},
              "containmentEvidence": document["containmentEvidence"],
              "inventoryGaps": document["inventoryGaps"], "declaredNativeResiduals": document["nativeResiduals"],
              "localCopies": [], "localResiduals": []}
    for entry in prepared:
        report["localCopies"].append({key: entry[key] for key in ("id", "destination", "files", "bytes")}
                                    | {"state": "pending" if apply else "planned",
                                       "path": str(entry["source"].relative_to(source)),
                                       "sourcePresent": True, "destinationPresent": False})
    local_residuals(report)
    if apply:
        destination.mkdir(mode=0o700)
        write_report(destination / "report.json", report)
    for entry, result in zip(prepared, report["localCopies"]):
        if apply:
            target = destination / entry["destination"]
            try:
                info = entry["source"].lstat()
                require((info.st_dev, info.st_ino) == (entry["device"], entry["inode"]),
                        "Selected copy changed after preflight")
                entry["source"].rename(target)
                moved = target.lstat()
                require((moved.st_dev, moved.st_ino) == (entry["device"], entry["inode"])
                        and not present(entry["source"]), "Move readback failed")
                os.chmod(target, 0)
                require(stat.S_IMODE(target.lstat().st_mode) == 0, "Quarantine mode readback failed")
                result["state"] = "quarantined"
                record_presence(result, entry["source"], target)
                local_residuals(report)
                write_report(destination / "report.json", report)
                if purge:
                    result["state"] = "purging"
                    local_residuals(report)
                    write_report(destination / "report.json", report)
                    purge_copy(target, entry)
                    require(not present(target) and not present(entry["source"]), "Purge readback failed")
                    result["state"] = "purged"
                    record_presence(result, entry["source"], target)
            except (OSError, ValueError):
                result["state"] = "unverified"
                try:
                    remaining = target.lstat()
                    if (remaining.st_dev, remaining.st_ino) == (entry["device"], entry["inode"]):
                        os.chmod(target, 0)
                except OSError:
                    pass
                record_presence(result, entry["source"], target)
                local_residuals(report)
                write_report(destination / "report.json", report)
                raise ValueError("Local cleanup interrupted; inspect the private partial report") from None
        local_residuals(report)
        if apply:
            write_report(destination / "report.json", report)
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--quarantine-root", type=Path, required=True)
    parser.add_argument("--apply", action="store_true", help="Move explicit stopped copies; default only inspects metadata")
    parser.add_argument("--purge", action="store_true", help="Delete exact stopped case-owned copies after relocation; requires --apply")
    args = parser.parse_args()
    if args.purge and not args.apply:
        parser.error("--purge requires --apply")
    try:
        report = quarantine_copies(read_manifest(args.manifest), args.source_root, args.quarantine_root, args.apply, args.purge)
    except (OSError, ValueError, RecursionError):
        print("Removal containment failed; inspect inputs and any private partial report. No purge was acknowledged.", file=sys.stderr)
        return 1
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
