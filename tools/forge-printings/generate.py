#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Generate a reproducible, offline printing alias index using a catalog and pinned native runtime."""

import argparse
from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / "third_party/forge-runtime/native-host"


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def export_catalog(catalog, destination, anchors_destination=None):
    with closing(sqlite3.connect(catalog.resolve().as_uri() + "?mode=ro", uri=True)) as connection:
        rows = connection.execute("""SELECT oracle_id, name, upper(set_code), collector_number, layout,
                max(CASE WHEN lang = 'en' THEN 1 ELSE 0 END)
            FROM cards WHERE digital = 0 AND oracle_id != ''
            AND set_code != '' AND collector_number != ''
            AND layout NOT IN ('token', 'double_faced_token', 'emblem', 'art_series')
            GROUP BY oracle_id, name, upper(set_code), collector_number, layout
            ORDER BY oracle_id, name, upper(set_code), collector_number""").fetchall()
        metadata = dict(connection.execute("SELECT key, value FROM metadata"))
        anchors = connection.execute("""SELECT oracle_id, name, upper(set_code), collector_number, layout,
                max(CASE WHEN lang = 'en' THEN 1 ELSE 0 END)
            FROM cards WHERE digital = 1 AND oracle_id != ''
            AND set_code != '' AND collector_number != ''
            AND layout NOT IN ('token', 'double_faced_token', 'emblem', 'art_series')
            GROUP BY oracle_id, name, upper(set_code), collector_number, layout
            ORDER BY oracle_id, name, upper(set_code), collector_number""").fetchall() if anchors_destination else []
    if not rows or any(any(not value or '\t' in value or '\n' in value for value in row[:5]) for row in rows):
        raise ValueError("Invalid or empty printing catalog")
    identities = {}
    for oracle, name, set_code, number, layout, english in rows + anchors:
        if any(not value or '\t' in value or '\n' in value for value in (oracle, name, set_code, number, layout)):
            raise ValueError("Invalid printing catalog anchor")
        key = (name.casefold(), set_code, number)
        if key in identities and identities[key] != oracle:
            raise ValueError("Conflicting Oracle identities for one printing")
        identities[key] = oracle
    destination.write_text(json.dumps(rows, ensure_ascii=False) + "\n", encoding="utf-8")
    if anchors_destination:
        anchors_destination.write_text(json.dumps(anchors, ensure_ascii=False) + "\n", encoding="utf-8")
    return metadata


def write_provenance(catalog, metadata, index, report, destination):
    summary = json.loads(report.read_text(encoding="utf-8"))
    summary.pop("unresolved")
    generator_sources = [Path(__file__), Path(__file__).with_name("NativePrintingIndex.java")]
    resolver_sources = [HOST / "src/main/java/org/hexproof/forge" / name for name in
                        ("NativeSession.java", "NativeCardNames.java", "NativePrintingAliases.java")]
    destination.write_text(json.dumps({"schema": 2, "catalogSha256": digest(catalog),
        "catalogGeneratedAt": metadata.get("generated_at", ""),
        "forgeRevision": json.loads((HOST / "upstream.json").read_text(encoding="utf-8"))["revision"],
        "indexSha256": digest(index), "unavailableSha256": digest(index.with_name("printing-unavailable.tsv")),
        "generatorSources": {path.relative_to(ROOT).as_posix(): digest(path) for path in generator_sources},
        "resolverSources": {path.relative_to(ROOT).as_posix(): digest(path) for path in resolver_sources},
        **summary}, indent=2) + "\n", encoding="utf-8")


def check_coverage(output, baseline):
    report = json.loads((output / "report.json").read_text(encoding="utf-8"))
    if report["actionableUnresolvedPrintings"]:
        raise ValueError("Supported native cards still have unmatched catalog printings; inspect report.json")
    for name in ("printing-aliases.tsv", "printing-unavailable.tsv", "printing-aliases.json"):
        if (output / name).read_bytes() != (baseline / name).read_bytes():
            raise ValueError(f"Catalog compatibility changed: review {name} before updating the shipped baseline")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", required=True, type=Path)
    parser.add_argument("--runtime", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--check", action="store_true", help="Fail on an unexplained gap or any changed compatibility baseline")
    args = parser.parse_args()
    subprocess.run([sys.executable, str(ROOT / "tools/local-forge-runtime.py"),
                    "--root", str(args.runtime.resolve())], check=True, stdout=subprocess.DEVNULL)
    args.output.mkdir(parents=True, exist_ok=False)
    candidates = args.output / "catalog.json"
    anchors = args.output / "anchors.json"
    metadata = export_catalog(args.catalog, candidates, anchors)
    classes = args.output / "classes"
    classes.mkdir()
    classpath = os.pathsep.join([str(args.runtime.resolve() / "forge-harness.jar"),
                                str(args.runtime.resolve() / "lib/*")])
    subprocess.run(["javac", "--release", "21", "-encoding", "UTF-8", "-cp", classpath,
                    "-d", str(classes), str(Path(__file__).with_name("NativePrintingIndex.java"))], check=True)
    index, report = args.output / "printing-aliases.tsv", args.output / "report.json"
    unavailable = args.output / "printing-unavailable.tsv"
    with (args.output / "native.log").open("w") as log:
        subprocess.run(["java", "-Xmx2g", "-Djava.awt.headless=true", "-cp", str(classes) + os.pathsep + classpath,
                        "org.hexproof.forge.NativePrintingIndex", str(args.runtime.resolve() / "forge-gui"),
                        str(candidates), str(index), str(report), str(unavailable), str(anchors)], stdout=log, stderr=subprocess.STDOUT, check=True)
    write_provenance(args.catalog, metadata, index, report, args.output / "printing-aliases.json")
    if args.check:
        check_coverage(args.output, HOST / "src/main/resources/org/hexproof/forge")


if __name__ == "__main__":
    main()
