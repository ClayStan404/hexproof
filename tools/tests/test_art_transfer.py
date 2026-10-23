# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import copy
from contextlib import closing
import hashlib
import importlib.util
import json
from pathlib import Path
import sqlite3
import struct
import tempfile
import unittest
import zlib

PATH = Path(__file__).resolve().parents[1] / "ui-automation/verify-art-transfer.py"
SPEC = importlib.util.spec_from_file_location("art_transfer", PATH)
TRANSFER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TRANSFER)


def write_json(path, value):
    path.write_text(json.dumps(value))


def png(red):
    def chunk(name, data):
        return struct.pack(">I", len(data)) + name + data + struct.pack(">I", zlib.crc32(name + data))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 2, 2, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress((b"\0" + bytes([red, 40, 60]) * 2) * 2)) + chunk(b"IEND", b""))


class ArtTransferTests(unittest.TestCase):
    def meld_fixture(self, root):
        catalog = root / "cards.sqlite"
        fields = TRANSFER.FIXTURES.FIELDS
        rows = []

        def add(card_id, name, set_code, number, relations):
            card = dict.fromkeys(fields, "")
            card.update(id=card_id, name=name, set_code=set_code, collector_number=number,
                        layout="meld", related_cards=json.dumps(relations))
            rows.append(card)
            return card

        parts = []
        for index, (front, back, code, number, back_number) in enumerate((
                ("Bruna, the Fading Light", "Brisela, Voice of Nightmares", "V17", "5", "5b"),
                ("Gisela, the Broken Blade", "Brisela, Voice of Nightmares", "EMN", "28", "15b"),
                ("Argoth, Sanctum of Nature", "Titania, Gaea Incarnate", "BRO", "256", "256b"))):
            result_id = f"test-result-{index}"
            relation = {"component": "meld_result", "id": result_id, "name": back}
            part = add(f"test-part-{index}", front, code, number, [relation])
            add(result_id, back, code, back_number, [relation])
            parts.append(part)
        # Two registered parts of the same printing require one related result.
        parts.append(add("test-part-shared", "Gisela, the Broken Blade", "V17", "10",
                         json.loads(parts[0]["related_cards"])))
        with closing(sqlite3.connect(catalog)) as database, database:
            database.execute("CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT)")
            database.executemany("INSERT INTO metadata VALUES (?, ?)",
                                 [("schema_version", "10"), ("generated_at", "unit-test-only")])
            database.execute("CREATE TABLE cards (" + ",".join(name + " TEXT" for name in fields)
                             + ", digital INTEGER, lang TEXT)")
            database.executemany("INSERT INTO cards VALUES (" + ",".join("?" for _ in range(len(fields) + 2)) + ")",
                                 [[*(card[field] for field in fields), 0, "en"] for card in rows])
        _, source = TRANSFER.FIXTURES.load_catalog(catalog)
        deck = {"mainboard": [TRANSFER.FIXTURES.row(card, "modern") for card in parts], "sideboard": []}
        images = root / "sender/data/Hexproof/Hexproof/images"
        images.mkdir(parents=True)
        artifacts = root / "sender/artifacts"
        artifacts.mkdir()
        cache, entries, blobs = {}, [], {}
        for index, card in enumerate(row for row in rows if row["id"].startswith("test-result-")):
            payload = png(10 if index < 2 else 20)
            sha = hashlib.sha256(payload).hexdigest()
            path = images / (sha + ".png")
            path.write_bytes(payload)
            entry = {"name": card["name"], "requestedName": card["name"], "faceName": "",
                     "setCode": card["set_code"], "collectorNumber": card["collector_number"],
                     "requestLanguage": "en", "imageLanguage": "en", "blobSha256": sha}
            entries.append(entry)
            blobs[sha] = {"sha256": sha, "format": "png", "bytes": len(payload)}
            cache[TRANSFER.entry_key(entry)] = {**entry, "imagePath": str(path)}
        write_json(images.parent / "card-cache.json", {"positive": cache, "negative": {}})
        manifest = {"format": "hexproof.card-art-pack", "formatVersion": 1,
                    "entries": entries, "images": list(blobs.values())}
        return catalog, source, deck, artifacts, manifest

    def fixture(self, root):
        card = {"name": "Delver of Secrets // Insectile Aberration", "setCode": "V17",
                "collectorNumber": "7", "faces": ["Delver of Secrets", "Insectile Aberration"],
                "imageFaceCount": 2, "layout": "transform"}
        payloads = [png(10), png(20)]
        entries, images = [], []
        for face, payload in zip(card["faces"], payloads):
            sha = hashlib.sha256(payload).hexdigest()
            images.append({"sha256": sha, "bytes": len(payload), "format": "png"})
            entries.append({"name": card["name"], "requestedName": face, "faceName": face,
                            "setCode": "V17", "collectorNumber": "7", "requestLanguage": "en",
                            "imageLanguage": "en", "blobSha256": sha})
        manifest = {"format": "hexproof.card-art-pack", "formatVersion": 1,
                    "entries": entries, "images": images}
        path = root / "deck.hexproof-artpack"
        self.write_pack(path, manifest, payloads)
        return path, manifest, payloads, {"mainboard": [card], "sideboard": []}

    def write_pack(self, path, manifest, payloads):
        data = json.dumps(manifest).encode()
        path.write_bytes(b"HXPART01" + struct.pack(">I", len(data)) + data + b"".join(payloads))

    def native(self, artifacts, mode, pack):
        # Synthetic evidence exercises acceptance rules; these tests do not run a GUI.
        artifacts.mkdir(parents=True, exist_ok=True)
        result = {"status": "passed", "scenario": "art-transfer-lifecycle", "mode": mode,
                  "networkIsolated": True, "sawCacheActivity": False,
                  "packFile": str(pack), "damagedPackExercised": False,
                  "requiredScreenshots": ["transfer.png"]}
        write_json(artifacts / "result.json", result)
        inputs = 1 if mode == "export" else 3
        write_json(artifacts / "audit-summary.json", {"exitCode": 0, "inputs": inputs, "failedInputs": 0,
                   "artifactFailures": 0, "qmlWarnings": [], "fixtures": 0, "evidence": "native-qt-input"})
        write_json(artifacts / "startup.json", {"evidence": "native-qt-input", "pid": 123,
                   "window": {"visible": True, "exposed": True, "platform": "xcb"}})
        (artifacts / "actions.jsonl").write_text("".join(json.dumps({
                   "action": "chooseFile", "accepted": True, "evidence": "native-qt-input", "sequence": i + 1,
                   "dialogAccepted": True, "dialogClosed": True, "selectedFile": pack.as_uri(),
                   "path": str(pack), "dialog": "currentDeckArtExportFileDialog" if mode == "export"
                   else "cardArtImportFileDialog"}) + "\n" for i in range(inputs)))
        (artifacts / "transfer.png").write_bytes(png(10))
        write_json(artifacts / "profile-before.json", {"imageFiles": 0, "files": {}})
        write_json(artifacts.parent.parent / "environment.json", {
                   "runId": "unit-test-only", "stages": [{"scenario": "ArtTransferLifecycle.qml"}],
                   "players": 1, "fixture": None, "evidence": "native-qt-input", "networkIsolated": True,
                   "clientLauncher": ["/usr/bin/unshare", "--user", "--map-root-user", "--net"]})
        write_json(artifacts.parent.parent / "report.json", {"status": "passed", "reason": None,
                   "runId": "unit-test-only", "seats": [{"status": "passed", "exitCode": 0,
                   "stage": 1, "seat": 1, "scenarioResult": result, "artifacts": str(artifacts)}]})

    def recipient(self, root, pack, manifest, payloads):
        profile = root / "recipient"
        images = profile / "data/Hexproof/Hexproof/images"
        images.mkdir(parents=True)
        entries = {}
        for entry, blob, payload in zip(manifest["entries"], manifest["images"], payloads):
            image = images / (blob["sha256"] + ".png")
            image.write_bytes(payload)
            record = dict(entry, imagePath=str(image))
            record.pop("requestLanguage")
            record.pop("blobSha256")
            entries[TRANSFER.entry_key(entry)] = record
        cache = {"positive": entries, "negative": {}}
        write_json(images.parent / "card-cache.json", cache)
        artifacts = profile / "artifacts"
        self.native(artifacts, "import", pack)
        empty = {"imageCount": 0, "indexedEntryCount": 0, "missingEntryCount": 0, "orphanCount": 0, "totalBytes": 0}
        inventory = dict(empty, imageCount=2, indexedEntryCount=2, totalBytes=sum(map(len, payloads)))
        for name in ("cold-inventory", "cancelled-inventory"):
            write_json(artifacts / f"{name}.json", empty)
        for name in ("cache-after-import", "cache-before-duplicate", "cache-after-duplicate"):
            write_json(artifacts / f"{name}.json", cache)
        for name in ("inventory-after-import", "inventory-before-duplicate", "inventory-after-duplicate"):
            write_json(artifacts / f"{name}.json", inventory)
        return profile, artifacts, cache

    def test_every_image_is_hashed_and_independent_faces_keep_exact_printings(self):
        with tempfile.TemporaryDirectory() as directory:
            path, expected, _, deck = self.fixture(Path(directory))
            manifest, blobs = TRANSFER.read_pack(path)
            self.assertEqual(manifest, expected)
            self.assertEqual(len(blobs), 2)
            coverage = TRANSFER.verify_faces(deck, manifest)
            self.assertEqual([row["faceName"] for row in coverage], deck["mainboard"][0]["faces"])
            self.assertNotEqual(coverage[0]["sha256"], coverage[1]["sha256"])
            wrong = copy.deepcopy(manifest)
            wrong["entries"][1]["collectorNumber"] = "8"
            with self.assertRaisesRegex(ValueError, "Missing exact printing face"):
                TRANSFER.verify_faces(deck, wrong)
            wrong = copy.deepcopy(manifest)
            wrong["entries"][1]["blobSha256"] = wrong["entries"][0]["blobSha256"]
            with self.assertRaisesRegex(ValueError, "Front and back"):
                TRANSFER.verify_faces(deck, wrong)

    def test_meld_results_use_pinned_exact_ids_and_allow_deduplicated_images(self):
        with tempfile.TemporaryDirectory() as directory:
            catalog, source, deck, artifacts, manifest = self.meld_fixture(Path(directory))
            before = catalog.read_bytes()
            required, provenance = TRANSFER.resolve_related_results(deck, source, catalog)
            self.assertEqual(provenance["sha256"], source["sha256"])
            self.assertEqual(catalog.read_bytes(), before)
            self.assertEqual({(row["setCode"], row["collectorNumber"]) for row in required},
                             {("V17", "5b"), ("EMN", "15b"), ("BRO", "256b")})
            self.assertEqual(len(next(row for row in required if row["setCode"] == "V17")["sourceCards"]), 2)
            coverage = TRANSFER.verify_related_results(artifacts, required, manifest)
            self.assertEqual(len(coverage), 3)
            self.assertEqual(len({sha for row in coverage for sha in row["sha256"]}), 2)

    def test_meld_coverage_rejects_missing_or_changed_catalog_and_changed_relations(self):
        with tempfile.TemporaryDirectory() as directory:
            catalog, source, deck, _, _ = self.meld_fixture(Path(directory))
            with self.assertRaisesRegex(ValueError, "requires --catalog"):
                TRANSFER.resolve_related_results(deck, source, None)
            altered = copy.deepcopy(deck)
            altered["mainboard"][0]["relatedCards"][0]["id"] = "test-result-1"
            with self.assertRaisesRegex(ValueError, "relations differ"):
                TRANSFER.resolve_related_results(altered, source, catalog)
            with closing(sqlite3.connect(catalog)) as database, database:
                database.execute("UPDATE cards SET collector_number='wrong' WHERE id='test-result-0'")
            with self.assertRaisesRegex(ValueError, "logical SHA-256"):
                TRANSFER.resolve_related_results(deck, source, catalog)

    def test_missing_meld_wrong_same_name_printing_and_swapped_blob_cannot_pass(self):
        for mutation in ("missing", "same-name-wrong-printing", "swapped-blob"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                catalog, source, deck, artifacts, manifest = self.meld_fixture(Path(directory))
                required, _ = TRANSFER.resolve_related_results(deck, source, catalog)
                if mutation == "missing":
                    manifest["entries"].pop(0)
                elif mutation == "same-name-wrong-printing":
                    manifest["entries"][0]["collectorNumber"] = "wrong-same-name"
                else:
                    first, last = manifest["entries"][0], manifest["entries"][-1]
                    first["blobSha256"], last["blobSha256"] = last["blobSha256"], first["blobSha256"]
                with self.assertRaisesRegex(ValueError, "Missing exact meld result|bytes differ from the sender"):
                    TRANSFER.verify_related_results(artifacts, required, manifest)

    def test_corrupted_duplicate_trailing_or_device_path_pack_cannot_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path, manifest, payloads, deck = self.fixture(root)
            data = path.read_bytes()
            for bad in (data[:-1], data + b"extra", data[:-1] + bytes([data[-1] ^ 1])):
                path.write_bytes(bad)
                with self.assertRaises(ValueError):
                    TRANSFER.read_pack(path)
            for mutation in ("duplicate-key", "duplicate-hash", "local-path", "nonfinite-size"):
                with self.subTest(mutation=mutation):
                    altered = copy.deepcopy(manifest)
                    if mutation == "duplicate-key":
                        altered["entries"].append(altered["entries"][0])
                    elif mutation == "duplicate-hash":
                        altered["images"][1]["sha256"] = altered["images"][0]["sha256"]
                    elif mutation == "local-path":
                        altered["entries"][0]["imagePath"] = "/old/profile/art.png"
                    else:
                        altered["images"][0]["bytes"] = float("inf")
                    self.write_pack(path, altered, payloads)
                    with self.assertRaises(ValueError):
                        TRANSFER.read_pack(path)

    def test_sender_face_hashes_catch_swapped_front_and_back_payloads(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _, manifest, payloads, deck = self.fixture(root)
            artifacts = root / "sender/artifacts"
            artifacts.mkdir(parents=True)
            images = artifacts.parent / "data/Hexproof/Hexproof/images"
            images.mkdir(parents=True)
            observed = []
            for entry, payload in zip(manifest["entries"], payloads):
                path = images / (entry["blobSha256"] + ".png")
                path.write_bytes(payload)
                observed.append({"cardName": entry["name"], "setCode": entry["setCode"],
                                 "collectorNumber": entry["collectorNumber"], "faceName": entry["faceName"],
                                 "imageSource": path.as_uri()})
            coverage = TRANSFER.verify_faces(deck, manifest)
            self.assertEqual(TRANSFER.verify_sender_faces(artifacts, coverage, observed), 2)
            observed[0]["imageSource"], observed[1]["imageSource"] = observed[1]["imageSource"], observed[0]["imageSource"]
            with self.assertRaisesRegex(ValueError, "differ from the sender"):
                TRANSFER.verify_sender_faces(artifacts, coverage, observed)

    def test_cold_recipient_checks_real_bytes_and_duplicate_snapshots(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path, manifest, payloads, deck = self.fixture(root)
            _, blobs = TRANSFER.read_pack(path)
            profile, artifacts, cache = self.recipient(root, path, manifest, payloads)
            result = TRANSFER.verify_recipient(profile, artifacts, manifest, blobs, path, deck)
            self.assertTrue(result["coldImport"] and result["duplicatePreserved"])
            self.assertEqual(result["images"], 2)
            image = Path(next(iter(cache["positive"].values()))["imagePath"])
            image.write_bytes(b"corrupt despite success messages")
            with self.assertRaisesRegex(ValueError, "Imported bytes"):
                TRANSFER.verify_recipient(profile, artifacts, manifest, blobs, path, deck)

    def test_hydrated_full_name_aliases_preserve_exact_front_bytes_and_settled_duplicate_baseline(self):
        for already_hydrated in (False, True):
            with self.subTest(already_hydrated=already_hydrated), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                pack, manifest, payloads, deck = self.fixture(root)
                _, blobs = TRANSFER.read_pack(pack)
                profile, artifacts, first = self.recipient(root, pack, manifest, payloads)
                allowed = TRANSFER.canonical_front_aliases(deck, manifest)
                self.assertEqual(len(allowed), 1)
                key, definition = next(iter(allowed.items()))
                settled = copy.deepcopy(first)
                settled["positive"][key] = dict(first["positive"][definition["sourceKey"]],
                                                requestedName=definition["requestedName"])
                for name in ("cache-before-duplicate", "cache-after-duplicate"):
                    write_json(artifacts / f"{name}.json", settled)
                if already_hydrated:
                    write_json(artifacts / "cache-after-import.json", settled)
                write_json(profile / "data/Hexproof/Hexproof/card-cache.json", settled)
                inventory = json.loads((artifacts / "inventory-after-import.json").read_text())
                inventory["indexedEntryCount"] = 3
                for name in ("inventory-before-duplicate", "inventory-after-duplicate"):
                    write_json(artifacts / f"{name}.json", inventory)
                result = TRANSFER.verify_recipient(profile, artifacts, manifest, blobs, pack, deck)
                self.assertEqual(result["canonicalFrontAliases"], [key])
                self.assertEqual((result["importedEntries"], result["entries"], result["images"]), (2, 3, 2))
                self.assertTrue(result["duplicatePreserved"])

    def test_alias_allowance_rejects_other_keys_back_faces_metadata_and_duplicate_changes(self):
        for mutation in ("unrelated", "wrong-language", "wrong-printing", "back-image", "back-face",
                         "metadata", "original-change", "original-missing", "duplicate-change",
                         "not-double-faced", "first-extra", "first-missing", "first-metadata"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                pack, manifest, payloads, deck = self.fixture(root)
                _, _, first = self.recipient(root, pack, manifest, payloads)
                allowed = TRANSFER.canonical_front_aliases(deck, manifest)
                key, definition = next(iter(allowed.items()))
                settled = copy.deepcopy(first)
                original_key = definition["sourceKey"]
                alias = dict(first["positive"][original_key], requestedName=definition["requestedName"])
                if mutation == "unrelated":
                    key += "-unrelated"
                elif mutation == "wrong-language":
                    key = "zh|" + key.split("|", 1)[1]
                elif mutation == "wrong-printing":
                    key = key.rsplit("|", 1)[0] + "|999"
                elif mutation == "back-image":
                    other = next(value for name, value in first["positive"].items() if name != original_key)
                    alias["imagePath"] = other["imagePath"]
                elif mutation == "back-face":
                    alias["faceName"] = deck["mainboard"][0]["faces"][1]
                elif mutation == "metadata":
                    alias["oracleText"] = "Unexpected metadata change"
                elif mutation == "original-change":
                    settled["positive"][original_key]["faceName"] = "Changed source"
                elif mutation == "original-missing":
                    settled["positive"].pop(original_key)
                elif mutation == "not-double-faced":
                    deck["mainboard"][0]["layout"] = "prepare"
                elif mutation == "first-extra":
                    first["positive"]["unrelated"] = copy.deepcopy(alias)
                    settled["positive"]["unrelated"] = copy.deepcopy(alias)
                elif mutation == "first-missing":
                    first["positive"].pop(original_key)
                elif mutation == "first-metadata":
                    for snapshot in (first, settled):
                        snapshot["positive"][original_key]["oracleText"] = "Incorrect on initial import"
                    alias["oracleText"] = "Incorrect on initial import"
                settled["positive"][key] = alias
                duplicate = copy.deepcopy(settled)
                if mutation == "duplicate-change":
                    duplicate["positive"][key]["oracleText"] = "Changed during duplicate import"
                with self.assertRaises(ValueError):
                    TRANSFER.verify_cache_evolution(first, settled, duplicate, deck, manifest)

    def test_duplicate_import_requires_a_recorded_settled_baseline(self):
        for name in ("cache-before-duplicate", "inventory-before-duplicate"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                pack, manifest, payloads, deck = self.fixture(root)
                _, blobs = TRANSFER.read_pack(pack)
                profile, artifacts, _ = self.recipient(root, pack, manifest, payloads)
                (artifacts / f"{name}.json").unlink()
                with self.assertRaises((OSError, ValueError)):
                    TRANSFER.verify_recipient(profile, artifacts, manifest, blobs, pack, deck)

    def test_orphans_and_changed_duplicate_index_are_not_hidden_by_inventory(self):
        for mutation in ("orphan", "index-change"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                path, manifest, payloads, deck = self.fixture(root)
                _, blobs = TRANSFER.read_pack(path)
                profile, artifacts, cache = self.recipient(root, path, manifest, payloads)
                if mutation == "orphan":
                    (profile / "data/Hexproof/Hexproof/images/orphan.png").write_bytes(png(80))
                else:
                    cache["positive"].pop(next(iter(cache["positive"])))
                    write_json(artifacts / "cache-after-duplicate.json", cache)
                with self.assertRaises(ValueError):
                    TRANSFER.verify_recipient(profile, artifacts, manifest, blobs, path, deck)

    def test_native_failure_or_business_fixture_is_not_a_transfer_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts = Path(directory) / "seat-1/artifacts"
            self.native(artifacts, "export", Path(directory) / "pack")
            TRANSFER.native_evidence(artifacts, "export")
            summary = json.loads((artifacts / "audit-summary.json").read_text())
            for key, value in (("failedInputs", 1), ("artifactFailures", 1), ("qmlWarnings", ["warning"]),
                               ("fixtures", 1), ("fixtures", False), ("inputs", 0)):
                with self.subTest(key=key):
                    write_json(artifacts / "audit-summary.json", dict(summary, **{key: value}))
                    with self.assertRaises(ValueError):
                        TRANSFER.native_evidence(artifacts, "export")

    def test_offline_launcher_is_required_and_local_cache_activity_is_allowed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifacts = root / "seat-1/artifacts"
            self.native(artifacts, "export", root / "pack")
            result = json.loads((artifacts / "result.json").read_text())
            result["sawCacheActivity"] = True
            write_json(artifacts / "result.json", result)
            report = json.loads((root / "report.json").read_text())
            report["seats"][0]["scenarioResult"] = result
            write_json(root / "report.json", report)
            self.assertTrue(TRANSFER.native_evidence(artifacts, "export")["sawCacheActivity"])
            metadata = json.loads((root / "environment.json").read_text())
            for mutation in ({"networkIsolated": False}, {"clientLauncher": []},
                             {"clientLauncher": ["/usr/bin/unshare", "--user", "--map-root-user"]},
                             {"clientLauncher": ["/usr/bin/other", "--user", "--map-root-user", "--net"]},
                             {"clientLauncher": ["unshare", "--user", "--map-root-user", "--net"]},
                             {"serverUrl": "ws://127.0.0.1:12345/ws"}):
                with self.subTest(mutation=mutation):
                    write_json(root / "environment.json", {**metadata, **mutation})
                    with self.assertRaisesRegex(ValueError, "network-namespace"):
                        TRANSFER.native_evidence(artifacts, "export")
            write_json(root / "environment.json", metadata)
            result["networkIsolated"] = False
            write_json(artifacts / "result.json", result)
            with self.assertRaisesRegex(ValueError, "local-only transfer"):
                TRANSFER.native_evidence(artifacts, "export")

    def test_native_summary_cannot_replace_missing_or_failed_input_evidence(self):
        for mutation in ("startup-missing", "actions-missing", "actions-empty", "action-failed",
                         "offscreen", "screenshot-missing", "report-missing"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                artifacts = Path(directory) / "seat-1/artifacts"
                self.native(artifacts, "export", Path(directory) / "pack")
                if mutation.endswith("-missing"):
                    path = {"startup-missing": artifacts / "startup.json",
                            "actions-missing": artifacts / "actions.jsonl",
                            "screenshot-missing": artifacts / "transfer.png",
                            "report-missing": artifacts.parent.parent / "report.json"}[mutation]
                    path.unlink()
                elif mutation == "actions-empty":
                    (artifacts / "actions.jsonl").write_text("")
                elif mutation == "action-failed":
                    action = json.loads((artifacts / "actions.jsonl").read_text())
                    action["accepted"] = False
                    (artifacts / "actions.jsonl").write_text(json.dumps(action) + "\n")
                else:
                    startup = json.loads((artifacts / "startup.json").read_text())
                    startup["window"]["platform"] = "offscreen"
                    write_json(artifacts / "startup.json", startup)
                with self.assertRaises((OSError, ValueError)):
                    TRANSFER.native_evidence(artifacts, "export")

    def test_run_exit_or_incomplete_stages_cannot_be_hidden_by_scenario_pass(self):
        for mutation in ("run-failed", "exit-nonzero", "seat-missing", "different-artifacts",
                         "unfinished-stage", "different-run"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                artifacts = Path(directory) / "seat-1/artifacts"
                self.native(artifacts, "export", Path(directory) / "pack")
                report_path = artifacts.parent.parent / "report.json"
                report = json.loads(report_path.read_text())
                if mutation == "run-failed":
                    report.update(status="failed", reason="Watchdog stopped a later stage")
                elif mutation == "exit-nonzero":
                    report["seats"][0]["exitCode"] = 4
                elif mutation == "seat-missing":
                    report["seats"] = []
                elif mutation == "different-artifacts":
                    report["seats"][0]["artifacts"] = str(artifacts.parent / "other-artifacts")
                elif mutation == "different-run":
                    report["runId"] = "another-run"
                else:
                    metadata_path = artifacts.parent.parent / "environment.json"
                    metadata = json.loads(metadata_path.read_text())
                    metadata["stages"].append({"scenario": "NotExecuted.qml"})
                    write_json(metadata_path, metadata)
                write_json(report_path, report)
                with self.assertRaises(ValueError):
                    TRANSFER.native_evidence(artifacts, "export")

    def test_complete_multistage_report_binds_the_requested_export_stage(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first = root / "seat-1/artifacts"
            second = root / "seat-1/stage-2-artifacts"
            self.native(first, "export", root / "pack-one")
            report = json.loads((root / "report.json").read_text())
            self.native(second, "export", root / "pack-two")
            second_report = json.loads((root / "report.json").read_text())
            second_report["seats"][0]["stage"] = 2
            report["seats"].extend(second_report["seats"])
            write_json(root / "report.json", report)
            metadata = json.loads((root / "environment.json").read_text())
            metadata["stages"] *= 2
            write_json(root / "environment.json", metadata)
            self.assertEqual(TRANSFER.native_evidence(second, "export")["packFile"], str(root / "pack-two"))

    def test_unexecuted_transfer_or_duplicate_is_not_replaced_by_other_input(self):
        for mode in ("export", "import"):
            for mutation in ("only-clicks", "wrong-dialog", "wrong-file", "missing-duplicate"):
                if mode == "export" and mutation == "missing-duplicate":
                    continue
                with self.subTest(mode=mode, mutation=mutation), tempfile.TemporaryDirectory() as directory:
                    artifacts = Path(directory) / "seat-1/artifacts"
                    self.native(artifacts, mode, Path(directory) / "pack")
                    actions = [json.loads(line) for line in (artifacts / "actions.jsonl").read_text().splitlines()]
                    for action in actions:
                        if mutation == "only-clicks":
                            action["action"] = "click"
                        elif mutation == "wrong-dialog":
                            action["dialog"] = "unrelatedFileDialog"
                        elif mutation == "wrong-file":
                            action["path"] += "-other"
                    if mutation == "missing-duplicate":
                        actions.pop()
                        summary = json.loads((artifacts / "audit-summary.json").read_text())
                        summary["inputs"] = len(actions)
                        write_json(artifacts / "audit-summary.json", summary)
                    (artifacts / "actions.jsonl").write_text("".join(json.dumps(action) + "\n" for action in actions))
                    with self.assertRaises(ValueError):
                        TRANSFER.native_evidence(artifacts, mode)

    def test_file_input_requires_current_acceptance_closure_and_matching_selection(self):
        for mode in ("export", "import"):
            for field in ("dialogAccepted", "dialogClosed", "selectedFile"):
                for value in (None, False, "file:///different-file" if field == "selectedFile" else 1):
                    with self.subTest(mode=mode, field=field, value=value), tempfile.TemporaryDirectory() as directory:
                        root = Path(directory)
                        artifacts = root / "seat-1/artifacts"
                        self.native(artifacts, mode, root / "pack")
                        actions = [json.loads(line) for line in (artifacts / "actions.jsonl").read_text().splitlines()]
                        if value is None:
                            actions[0].pop(field)
                        else:
                            actions[0][field] = value
                        (artifacts / "actions.jsonl").write_text("".join(json.dumps(action) + "\n" for action in actions))
                        with self.assertRaises(ValueError):
                            TRANSFER.native_evidence(artifacts, mode)

    def test_damaged_pack_claim_requires_its_own_file_selection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifacts = root / "seat-1/artifacts"
            self.native(artifacts, "import", root / "pack")
            result = json.loads((artifacts / "result.json").read_text())
            result["damagedPackExercised"] = True
            write_json(artifacts / "result.json", result)
            report = json.loads((root / "report.json").read_text())
            report["seats"][0]["scenarioResult"] = result
            write_json(root / "report.json", report)
            write_json(artifacts / "transfer-input.json", {"invalidFile": str(root / "damaged-pack")})
            with self.assertRaisesRegex(ValueError, "claimed damaged-pack"):
                TRANSFER.native_evidence(artifacts, "import")
            with (artifacts / "actions.jsonl").open("a") as stream:
                stream.write(json.dumps({"action": "chooseFile", "accepted": True,
                             "evidence": "native-qt-input", "sequence": 4,
                             "dialogAccepted": True, "dialogClosed": True,
                             "selectedFile": (root / "damaged-pack").as_uri(),
                             "dialog": "cardArtImportFileDialog", "path": str(root / "damaged-pack")}) + "\n")
            summary = json.loads((artifacts / "audit-summary.json").read_text())
            summary["inputs"] = 4
            write_json(artifacts / "audit-summary.json", summary)
            self.assertTrue(TRANSFER.native_evidence(artifacts, "import")["damagedPackExercised"])

    def test_cold_claim_requires_runner_checkpoint_without_preseeded_art(self):
        for mutation in ("images", "cache", "decks", "missing", "fixture", "other-profile"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                path, manifest, payloads, deck = self.fixture(root)
                _, blobs = TRANSFER.read_pack(path)
                profile, artifacts, _ = self.recipient(root, path, manifest, payloads)
                checkpoint = {"imageFiles": 0, "files": {}}
                if mutation == "images":
                    checkpoint["imageFiles"] = 2
                elif mutation in ("cache", "decks"):
                    filename = "card-cache.json" if mutation == "cache" else "decks.json"
                    checkpoint["files"][filename] = {"bytes": 100, "sha256": "already-present"}
                elif mutation == "fixture":
                    metadata_path = artifacts.parent.parent / "environment.json"
                    metadata = json.loads(metadata_path.read_text())
                    metadata["fixture"] = "/prepared/art"
                    write_json(metadata_path, metadata)
                elif mutation == "other-profile":
                    # The imported bytes still validate if provenance is not bound to this profile.
                    profile = root / "different-profile"
                    profile.symlink_to(artifacts.parent, target_is_directory=True)
                    artifacts = root / "unrelated/seat-1/artifacts"
                    self.native(artifacts, "import", path)
                    for name in ("cold-inventory", "cancelled-inventory", "cache-after-import",
                                 "cache-before-duplicate", "cache-after-duplicate", "inventory-after-import",
                                 "inventory-before-duplicate", "inventory-after-duplicate"):
                        (artifacts / f"{name}.json").write_bytes(
                            (root / "recipient/artifacts" / f"{name}.json").read_bytes())
                write_json(artifacts / "profile-before.json", checkpoint)
                if mutation == "missing":
                    (artifacts / "profile-before.json").unlink()
                with self.assertRaises((OSError, ValueError)):
                    TRANSFER.verify_recipient(profile, artifacts, manifest, blobs, path, deck)

    def test_damaged_copy_retains_original_and_refuses_existing_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path, _, _, _ = self.fixture(root)
            original = path.read_bytes()
            destination = root / "bad.hexproof-artpack"
            TRANSFER.damaged_copy(path, destination)
            self.assertEqual(path.read_bytes(), original)
            self.assertEqual(destination.read_bytes()[:-1], original[:-1])
            with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                TRANSFER.read_pack(destination)
            with self.assertRaises(ValueError):
                TRANSFER.damaged_copy(path, destination)


if __name__ == "__main__":
    unittest.main()
