#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Independently verify a natively exported card-art pack and optional cold import.

Reads the documented HXPART01 container, checks every declared blob's SHA-256,
compares exact printing/face coverage with the real-card fixture, and optionally
checks the recipient's persisted index, image files and duplicate-import evidence.
No application methods, services, or existing profile files are modified.
--make-invalid explicitly creates a separate damaged copy for a negative UI test.
"""

import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re
import shutil
import sqlite3
import struct
import sys
from types import SimpleNamespace
from urllib.parse import unquote, urlsplit


# Reuse the runner's native window, complete input trace and screenshot checks.
# Importing it does not launch a client; process exits come from its persisted report.
RUNNER_SPEC = importlib.util.spec_from_file_location("art_transfer_native_runner",
                                                   Path(__file__).with_name("run-native.py"))
RUNNER = importlib.util.module_from_spec(RUNNER_SPEC)
RUNNER_SPEC.loader.exec_module(RUNNER)
FIXTURES_SPEC = importlib.util.spec_from_file_location("art_transfer_card_fixtures",
                                                     Path(__file__).with_name("make-card-fixtures.py"))
FIXTURES = importlib.util.module_from_spec(FIXTURES_SPEC)
FIXTURES_SPEC.loader.exec_module(FIXTURES)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def regular(path):
    require(path.is_file() and not path.is_symlink(), f"Expected an ordinary file: {path}")
    return path


def digest(path):
    with regular(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read_json(path):
    return json.loads(regular(path).read_text())


def normalized(value):
    return " ".join(str(value).split()).casefold()


def entry_key(entry):
    return "|".join((entry["requestLanguage"], normalized(entry["requestedName"]),
                     entry["setCode"].upper(), entry["collectorNumber"]))


def read_pack(path):
    regular(path)
    require(path.stat().st_size <= 64 * 1024 * 1024 * 1024, "Pack exceeds the documented payload bound")
    with path.open("rb") as stream:
        require(stream.read(8) == b"HXPART01", "Invalid pack magic")
        length = stream.read(4)
        require(len(length) == 4, "Truncated manifest length")
        length = struct.unpack(">I", length)[0]
        require(0 < length <= 64 * 1024 * 1024, "Manifest exceeds the documented bound")
        data = stream.read(length)
        require(len(data) == length, "Truncated manifest")
        manifest = json.loads(data)
        require(isinstance(manifest, dict) and manifest.get("format") == "hexproof.card-art-pack"
                and manifest.get("formatVersion") == 1, "Unsupported pack format")
        entries, images = manifest.get("entries"), manifest.get("images")
        require(isinstance(entries, list) and 0 < len(entries) <= 500_000
                and isinstance(images, list) and 0 < len(images) <= 100_000,
                "Pack must contain bounded nonempty entry and image lists")
        blobs = {}
        for image in images:
            require(isinstance(image, dict), "Invalid image declaration")
            sha = image.get("sha256", "")
            size = image.get("bytes", 0)
            require(isinstance(sha, str) and re.fullmatch(r"[a-f0-9]{64}", sha)
                    and sha not in blobs, "Invalid or duplicate image hash")
            require(type(size) in (int, float) and math.isfinite(size)
                    and int(size) == size and 0 < size <= 32 * 1024 * 1024,
                    "Invalid image byte count")
            suffix = image.get("format")
            require(suffix in ("jpg", "png", "webp"), "Unsupported image format")
            payload = stream.read(int(size))
            require(len(payload) == size and hashlib.sha256(payload).hexdigest() == sha,
                    f"Image size or SHA-256 mismatch: {sha}")
            signature = (payload.startswith(b"\xff\xd8\xff") if suffix == "jpg" else
                         payload.startswith(b"\x89PNG\r\n\x1a\n") if suffix == "png" else
                         payload.startswith(b"RIFF") and payload[8:12] == b"WEBP")
            require(signature, f"Image signature does not match its declared format: {sha}")
            blobs[sha] = {"bytes": int(size), "format": suffix}
        require(stream.read(1) == b"", "Trailing bytes after the declared image payload")
    keys, referenced = set(), set()
    for entry in entries:
        require(isinstance(entry, dict) and "imagePath" not in entry,
                "Pack entries must not retain device-local image paths")
        require(all(isinstance(entry.get(name), str) and entry[name].strip()
                    and "|" not in entry[name] and "\0" not in entry[name]
                    for name in ("requestLanguage", "requestedName", "name", "setCode", "collectorNumber")),
                "Entry lacks a complete printing identity")
        require(entry["requestLanguage"] in ("en", "zh") and entry.get("imageLanguage") in ("en", "zh"),
                "Unsupported entry language")
        key = entry_key(entry)
        require(key not in keys, f"Duplicate lookup identity: {key}")
        keys.add(key)
        sha = entry.get("blobSha256")
        require(sha in blobs, "Entry refers to an undeclared image")
        referenced.add(sha)
    require(referenced == set(blobs), "Pack contains unused image blobs")
    return manifest, blobs


def verify_faces(deck, manifest):
    coverage = []
    for card in deck["mainboard"] + deck["sideboard"]:
        candidates = [entry for entry in manifest["entries"]
                      if entry["setCode"].upper() == card["setCode"].upper()
                      and entry["collectorNumber"] == card["collectorNumber"]
                      and normalized(entry["name"]) == normalized(card["name"])]
        hashes = []
        require(len(card["faces"]) == card["imageFaceCount"], "Fixture has inconsistent face expectations")
        for index, face in enumerate(card["faces"]):
            matching = [entry for entry in candidates
                        if normalized(face) in {normalized(entry.get(field, ""))
                                                for field in ("requestedName", "faceName", "name")}
                        and (card["imageFaceCount"] == 1
                             or normalized(entry.get("faceName", "")) == normalized(face)
                             or index == 0 and not entry.get("faceName"))]
            require(matching, f"Missing exact printing face: {card['name']} {card['setCode']}/{card['collectorNumber']} {face}")
            face_hashes = {entry["blobSha256"] for entry in matching}
            hashes.append(face_hashes)
            coverage.append({"name": card["name"], "setCode": card["setCode"],
                             "collectorNumber": card["collectorNumber"], "faceName": face,
                             "sha256": sorted(face_hashes)})
        if len(hashes) == 2:
            require(hashes[0].isdisjoint(hashes[1]), f"Front and back share image bytes: {card['name']}")
    return coverage


def resolve_related_results(deck, source, catalog):
    cards = deck["mainboard"] + deck["sideboard"]
    has_meld = any(card.get("layout") == "meld" or any(
        part.get("component") == "meld_result" for part in card.get("relatedCards", [])) for card in cards)
    require(catalog is not None or not has_meld,
            "Meld coverage requires --catalog with the fixture's original catalog snapshot")
    if catalog is None:
        return [], None
    require(isinstance(source, dict) and source.get("hashKind") == "logical-selection-v1",
            "The fixture does not identify a supported pinned catalog hash")
    catalog_cards, provenance = FIXTURES.load_catalog(regular(catalog))
    require(provenance["sha256"] == source.get("sha256"),
            "Catalog logical SHA-256 does not match the fixture's original snapshot")
    by_id = {card["id"]: card for card in catalog_cards}
    results = {}
    for card in cards:
        pinned = by_id.get(card.get("id"))
        require(pinned is not None and pinned["name"] == card["name"]
                and pinned["set_code"].upper() == card["setCode"].upper()
                and pinned["collector_number"] == card["collectorNumber"]
                and pinned["layout"] == card.get("layout"),
                "Fixture printing or layout differs from its pinned catalog identity")
        if pinned["layout"] != "meld":
            continue
        relations = json.loads(pinned["related_cards"] or "[]")
        require(card.get("relatedCards") == relations, "Fixture meld relations differ from the pinned catalog")
        meld_results = [part for part in relations if part.get("component") == "meld_result"]
        require(meld_results, f"Pinned meld part has no result: {card['name']}")
        for part in meld_results:
            related = by_id.get(part.get("id"))
            require(related is not None and related["layout"] == "meld"
                    and related["name"] == part.get("name")
                    and related["set_code"] and related["collector_number"],
                    f"Pinned catalog lacks an exact meld result: {part.get('id')}")
            result = results.setdefault(related["id"], {
                "id": related["id"], "name": related["name"], "setCode": related["set_code"].upper(),
                "collectorNumber": related["collector_number"], "faceName": related["name"],
                "component": "meld_result", "sourceCards": [],
            })
            parent = {field: card[field] for field in ("id", "name", "setCode", "collectorNumber")}
            if parent not in result["sourceCards"]:
                result["sourceCards"].append(parent)
    return sorted(results.values(), key=lambda row: (row["name"], row["setCode"], row["collectorNumber"])), provenance


def verify_related_results(artifacts, required_results, manifest):
    if not required_results:
        return []
    base = artifacts.parent / "data/Hexproof/Hexproof"
    cache = read_json(base / "card-cache.json")
    positive = cache.get("positive") if isinstance(cache, dict) else None
    require(isinstance(positive, dict), "Sender lacks persisted cache mappings for related results")
    images = (base / "images").resolve(strict=True)
    coverage = []
    for expected in required_results:
        matching = [entry for entry in manifest["entries"]
                    if entry["setCode"].upper() == expected["setCode"]
                    and entry["collectorNumber"] == expected["collectorNumber"]
                    and normalized(entry["name"]) == normalized(expected["name"])
                    and normalized(entry["requestedName"]) == normalized(expected["name"])
                    and normalized(entry.get("faceName", "")) in ("", normalized(expected["name"]))]
        require(matching, f"Missing exact meld result: {expected['name']} "
                f"{expected['setCode']}/{expected['collectorNumber']}")
        hashes = set()
        for entry in matching:
            record = positive.get(entry_key(entry))
            require(isinstance(record, dict) and all(record.get(field, "") == entry.get(field, "")
                    for field in ("name", "requestedName", "faceName", "setCode", "collectorNumber", "imageLanguage")),
                    "Related result differs from the sender's exact persisted cache mapping")
            path = Path(record["imagePath"])
            regular(path)
            require(path.is_absolute() and path.resolve().is_relative_to(images),
                    "Sender's related image is outside its isolated cache")
            sha = digest(path)
            require(sha == entry["blobSha256"],
                    f"Related result bytes differ from the sender's cached face: {expected['name']} "
                    f"{expected['setCode']}/{expected['collectorNumber']}")
            hashes.add(sha)
        # Different exact printings may legitimately reuse one image blob.
        coverage.append(dict(expected, sha256=sorted(hashes)))
    return coverage


def native_evidence(artifacts, mode):
    result = read_json(artifacts / "result.json")
    summary = read_json(artifacts / "audit-summary.json")
    require(isinstance(result, dict) and result.get("status") == "passed"
            and result.get("scenario") == "art-transfer-lifecycle"
            and result.get("mode") == mode and result.get("networkIsolated") is True
            and type(result.get("sawCacheActivity")) is bool,
            f"The native {mode} scenario did not pass a local-only transfer")
    require(isinstance(summary, dict) and type(summary.get("fixtures")) is int and summary["fixtures"] == 0,
            f"The native {mode} evidence has missing or injected business fixtures")
    metadata = read_json(artifacts.parent.parent / "environment.json")
    report = read_json(artifacts.parent.parent / "report.json")
    require(isinstance(metadata, dict) and metadata.get("evidence") == "native-qt-input"
            and isinstance(metadata.get("runId"), str) and metadata["runId"]
            and type(metadata.get("players")) is int and 1 <= metadata["players"] <= 8
            and isinstance(metadata.get("stages"), list) and metadata["stages"],
            "Missing native run provenance")
    launcher = metadata.get("clientLauncher")
    require(metadata.get("networkIsolated") is True and metadata["players"] == 1
            and not metadata.get("serverUrl") and isinstance(launcher, list) and len(launcher) == 4
            and isinstance(launcher[0], str) and Path(launcher[0]).is_absolute()
            and Path(launcher[0]).name == "unshare" and launcher[1:] == ["--user", "--map-root-user", "--net"],
            "Native transfer lacks the runner's offline network-namespace launcher")
    require(isinstance(report, dict) and report.get("status") == "passed" and report.get("reason") is None
            and report.get("runId") == metadata["runId"] and isinstance(report.get("seats"), list)
            and len(report["seats"]) == metadata["players"] * len(metadata["stages"]),
            "Native run failed or did not complete every requested stage and seat")
    matched = []
    for index, seat in enumerate(report["seats"]):
        require(isinstance(seat, dict) and seat.get("status") == "passed"
                and type(seat.get("exitCode")) is int and seat["exitCode"] == 0
                and type(seat.get("stage")) is int and seat["stage"] == index // metadata["players"] + 1
                and type(seat.get("seat")) is int and seat["seat"] == index % metadata["players"] + 1
                and isinstance(seat.get("artifacts"), str),
                "Native run contains a failed or incomplete seat")
        if Path(seat["artifacts"]).resolve() == artifacts.resolve():
            matched.append(seat)
    require(len(matched) == 1 and matched[0].get("scenarioResult") == result,
            "Native artifacts do not match exactly one completed runner seat")
    process = SimpleNamespace(poll=lambda: matched[0]["exitCode"])
    verified = RUNNER.seat_result(process, artifacts)
    require(verified["status"] == "passed", f"Native {mode} evidence failed: {verified.get('reason')}")
    require(isinstance(result.get("packFile"), str) and Path(result["packFile"]).is_absolute()
            and type(result.get("damagedPackExercised")) is bool,
            "Native transfer result lacks an explicit pack and negative-test boundary")
    actions = [json.loads(line) for line in (artifacts / "actions.jsonl").read_text().splitlines() if line.strip()]
    dialog = "currentDeckArtExportFileDialog" if mode == "export" else "cardArtImportFileDialog"
    selections = [action["path"] for action in actions
                  if action.get("action") == "chooseFile" and action.get("dialog") == dialog
                  and isinstance(action.get("path"), str)]
    require(selections.count(result["packFile"]) >= (1 if mode == "export" else 3),
            "Native file selection does not establish export or cancellation, import and duplicate import")
    if mode == "import" and result["damagedPackExercised"]:
        transfer = read_json(artifacts / "transfer-input.json")
        invalid = transfer.get("invalidFile") if isinstance(transfer, dict) else None
        require(isinstance(invalid, str) and Path(invalid).is_absolute()
                and invalid != result["packFile"] and invalid in selections,
                "Native file selection does not establish the claimed damaged-pack import")
    return result


def verify_sender_faces(artifacts, coverage, observed):
    def identity(row):
        return (row.get("name", row.get("cardName")), row["setCode"].upper(),
                row["collectorNumber"], row["faceName"])
    indexed = {identity(row): row for row in observed}
    require(len(indexed) == len(observed) and set(indexed) == {identity(row) for row in coverage},
            "Sender's native face observations do not cover the independent fixture")
    source_images = (artifacts.parent / "data/Hexproof/Hexproof/images").resolve(strict=True)
    for expected in coverage:
        source = urlsplit(indexed[identity(expected)]["imageSource"])
        require(source.scheme == "file" and source.netloc in ("", "localhost"),
                "Sender face observation is not a local image")
        path = Path(unquote(source.path))
        regular(path)
        require(path.resolve().is_relative_to(source_images), "Sender image is outside its isolated cache")
        require(digest(path) in expected["sha256"],
                f"Exported face bytes differ from the sender's displayed face: {expected['faceName']}")
    return len(indexed)


def canonical_front_aliases(deck, manifest):
    aliases = {}
    for card in deck["mainboard"] + deck["sideboard"]:
        faces = card.get("faces", [])
        if (card.get("layout") not in ("transform", "modal_dfc", "double_faced_token", "reversible_card")
                or card.get("imageFaceCount") != 2 or len(faces) != 2 or card["name"] != " // ".join(faces)):
            continue
        for entry in manifest["entries"]:
            if (entry["name"] != card["name"] or entry["setCode"].upper() != card["setCode"].upper()
                    or entry["collectorNumber"] != card["collectorNumber"]
                    or entry["requestedName"] != faces[0] or entry.get("faceName") != faces[0]):
                continue
            alias = dict(entry, requestedName=card["name"])
            aliases[entry_key(alias)] = {"sourceKey": entry_key(entry), "requestedName": card["name"]}
    return aliases


def verify_cache_evolution(first, settled, duplicate, deck, manifest):
    for snapshot in (first, settled, duplicate):
        require(isinstance(snapshot, dict) and isinstance(snapshot.get("positive"), dict)
                and snapshot.get("negative") == {}, "Import snapshots lack complete successful cache mappings")
    packaged_keys = {entry_key(entry) for entry in manifest["entries"]}
    require(packaged_keys <= set(first["positive"]), "First import lost packaged lookup identities")
    original = {key: first["positive"][key] for key in packaged_keys}
    for entry in manifest["entries"]:
        # These three fields describe the container mapping, not the saved record.
        expected = {key: value for key, value in entry.items()
                    if key not in ("requestLanguage", "blobSha256", "source")}
        record = original[entry_key(entry)]
        require(isinstance(record, dict) and {key: value for key, value in record.items()
                if key != "imagePath"} == expected, "First import changed packaged card metadata")
    positive = settled["positive"]
    require(all(positive.get(key) == record for key, record in first["positive"].items()),
            "Background hydration changed an original imported cache mapping")
    allowed = canonical_front_aliases(deck, manifest)
    extra = set(positive) - set(original)
    for snapshot in (first["positive"], positive):
        additions = set(snapshot) - set(original)
        require(additions <= set(allowed), "Recipient gained an unrelated lookup identity")
        for key in additions:
            alias = allowed[key]
            expected = dict(original[alias["sourceKey"]], requestedName=alias["requestedName"])
            require(snapshot[key] == expected,
                    "Canonical front alias changed the original face's image or metadata")
    require(settled["positive"] == duplicate["positive"] and settled["negative"] == duplicate["negative"],
            "Duplicate import changed persisted cache entries after hydration settled")
    return sorted(extra)


def verify_recipient(profile, artifacts, manifest, blobs, pack, deck):
    require(profile.resolve() == artifacts.parent.resolve(), "Recipient profile does not own the native artifacts")
    result = native_evidence(artifacts, "import")
    require(Path(result["packFile"]).resolve() == pack.resolve(), "Recipient imported a different pack")
    metadata = read_json(artifacts.parent.parent / "environment.json")
    checkpoint = read_json(artifacts / "profile-before.json")
    require(metadata.get("fixture") is None and isinstance(checkpoint, dict)
            and type(checkpoint.get("imageFiles")) is int and checkpoint["imageFiles"] == 0
            and isinstance(checkpoint.get("files"), dict)
            and not {"card-cache.json", "decks.json"}.intersection(checkpoint["files"]),
            "Cold import requires an unseeded profile before the native process starts")
    for name in ("cold-inventory", "cancelled-inventory"):
        snapshot = read_json(artifacts / f"{name}.json")
        require(all(snapshot.get(key) == 0 for key in
                    ("imageCount", "indexedEntryCount", "missingEntryCount", "orphanCount")),
                f"Recipient was not cold at {name}")
    first = read_json(artifacts / "cache-after-import.json")
    settled = read_json(artifacts / "cache-before-duplicate.json")
    duplicate = read_json(artifacts / "cache-after-duplicate.json")
    aliases = verify_cache_evolution(first, settled, duplicate, deck, manifest)
    base = profile / "data/Hexproof/Hexproof"
    cache = read_json(base / "card-cache.json")
    positive = cache.get("positive")
    require(isinstance(positive, dict) and positive == duplicate.get("positive") and not cache.get("negative"),
            "Final recipient cache differs from the successful import or contains failed mappings")
    image_root = (base / "images").resolve(strict=True)
    paths = set()
    for entry in manifest["entries"]:
        record = positive[entry_key(entry)]
        for field in ("name", "requestedName", "faceName", "setCode", "collectorNumber", "imageLanguage"):
            require(record.get(field, "") == entry.get(field, ""), f"Imported identity changed: {field}")
        path = Path(record["imagePath"])
        regular(path)
        require(path.is_absolute() and path.resolve().is_relative_to(image_root),
                "Imported image points outside the recipient's managed images")
        sha = entry["blobSha256"]
        require(path.name == sha + "." + blobs[sha]["format"] and digest(path) == sha
                and path.stat().st_size == blobs[sha]["bytes"], "Imported bytes differ from the exported blob")
        paths.add(path.resolve())
    files = set()
    for path in image_root.rglob("*"):
        require(not path.is_symlink(), "Recipient images contain a symlink")
        if path.is_file():
            files.add(path.resolve())
        else:
            require(path.is_dir(), "Recipient images contain a special file")
    require(files == paths and len(files) == len(blobs), "Recipient contains missing, duplicate or orphan image files")
    initial_inventory = read_json(artifacts / "inventory-after-import.json")
    before = read_json(artifacts / "inventory-before-duplicate.json")
    after = read_json(artifacts / "inventory-after-duplicate.json")
    for name, snapshot, entry_count in (("first import", initial_inventory, len(manifest["entries"])),
                                        ("settled import", before, len(settled["positive"]))):
        require(snapshot.get("imageCount") == len(blobs) and snapshot.get("indexedEntryCount") == entry_count
                and snapshot.get("missingEntryCount") == 0 and snapshot.get("orphanCount") == 0
                and snapshot.get("totalBytes") == sum(blob["bytes"] for blob in blobs.values()),
                f"Displayed {name} inventory disagrees with verified cache mappings and bytes")
    for key in ("imageCount", "indexedEntryCount", "missingEntryCount", "orphanCount", "totalBytes"):
        require(before.get(key) == after.get(key), f"Duplicate import changed inventory {key}")
    require(after.get("imageCount") == len(blobs) and after.get("indexedEntryCount") == len(positive)
            and after.get("totalBytes") == sum(blob["bytes"] for blob in blobs.values()),
            "Displayed inventory disagrees with verified disk contents")
    if result.get("damagedPackExercised"):
        rejected = read_json(artifacts / "damaged-pack-rejected.json")
        require(bool(rejected.get("error")) and all(rejected["inventory"].get(key) == 0
                    for key in ("imageCount", "indexedEntryCount", "missingEntryCount", "orphanCount")),
                "Damaged pack did not fail without leaving partial files")
    return {"entries": len(positive), "importedEntries": len(manifest["entries"]),
            "canonicalFrontAliases": aliases, "images": len(files), "duplicatePreserved": True,
            "coldImport": True, "cancellationPreserved": True,
            "damagedPackRejected": result.get("damagedPackExercised", False)}


def damaged_copy(source, destination):
    require(not destination.exists() and not destination.is_symlink(), "Damaged-copy destination must be new")
    with regular(source).open("rb") as incoming, destination.open("xb") as output:
        shutil.copyfileobj(incoming, output)
    with destination.open("r+b") as output:
        output.seek(-1, 2)
        byte = output.read(1)
        output.seek(-1, 2)
        output.write(bytes([byte[0] ^ 1]))
    return {"path": str(destination.resolve()), "sha256": digest(destination),
            "mutation": "Final image payload byte toggled; original manifest and pack retained"}


def run(args):
    require(not args.output.exists() and not args.output.is_symlink(), "The verification report must be new")
    report = {"status": "failed", "evidence": "independent-container-and-persisted-file-hashes"}
    try:
        exported = native_evidence(args.export_artifacts, "export")
        require(Path(exported["packFile"]).resolve() == args.pack.resolve(), "Exporter wrote a different pack")
        fixture = read_json(args.manifest)
        require(fixture.get("schema") == "hexproof.card-shape-fixtures.v1" and args.variant in fixture.get("decks", {}),
                "Unsupported independent card fixture")
        manifest, blobs = read_pack(args.pack)
        deck = fixture["decks"][args.variant]
        coverage = verify_faces(deck, manifest)
        required_results, catalog_source = resolve_related_results(deck, fixture.get("source"), args.catalog)
        related_coverage = verify_related_results(args.export_artifacts, required_results, manifest)
        completed = read_json(args.export_artifacts / "export-completed.json")
        result = completed["result"]
        require(result.get("ok") is True and result.get("entryCount") == len(manifest["entries"])
                and result.get("imageCount") == len(blobs)
                and result.get("bytes") == sum(blob["bytes"] for blob in blobs.values()),
                "Export summary disagrees with the actual container")
        sender_faces = verify_sender_faces(args.export_artifacts, coverage, completed["expectedFaces"])
        report.update(pack=str(args.pack.resolve()), packSha256=digest(args.pack), entries=len(manifest["entries"]),
                      images=len(blobs), bytes=sum(blob["bytes"] for blob in blobs.values()),
                      fixtureSha256=digest(args.manifest), faceCoverage=coverage,
                      relatedResultCoverage=related_coverage, relatedCatalog=catalog_source,
                      senderRelatedResultHashesVerified=len(related_coverage),
                      senderFaceHashesVerified=sender_faces,
                      independentImageDecode=False)
        if args.profile:
            report["recipient"] = verify_recipient(args.profile, args.import_artifacts or args.profile / "artifacts",
                                                   manifest, blobs, args.pack, deck)
        if args.make_invalid:
            report["negativeFixture"] = damaged_copy(args.pack, args.make_invalid)
        report["status"] = "passed"
    except (OSError, ValueError, KeyError, TypeError, struct.error, sqlite3.Error) as error:
        report["error"] = str(error)
    with args.output.open("x") as output:
        json.dump(report, output, ensure_ascii=False, indent=2)
        output.write("\n")
    print(f"Art transfer verification: {args.output}")
    return 0 if report["status"] == "passed" else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--catalog", type=Path,
                        help="Read-only original fixture catalog; required for exact related meld results")
    parser.add_argument("--variant", default="modern")
    parser.add_argument("--export-artifacts", type=Path, required=True)
    parser.add_argument("--profile", type=Path, help="Optional cold recipient seat root")
    parser.add_argument("--import-artifacts", type=Path, help="Recipient artifacts, if not profile/artifacts")
    parser.add_argument("--make-invalid", type=Path, help="Create a separate new damaged pack for a negative UI import")
    parser.add_argument("--output", type=Path, required=True, help="New verification report; never overwritten")
    args = parser.parse_args()
    if args.import_artifacts and not args.profile:
        parser.error("--import-artifacts requires --profile")
    try:
        return run(args)
    except (OSError, ValueError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    sys.exit(main())
