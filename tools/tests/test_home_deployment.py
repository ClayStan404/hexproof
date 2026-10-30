#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

from __future__ import annotations

import argparse
from contextlib import ExitStack
import importlib.util
import io
import json
from pathlib import Path
import socket
import subprocess
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]


def load(name, path):
    specification = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


PACKAGE = load("package_home_node", "tools/package-home-node.py")
INSTALL = load("install_home_node", "deploy/install-home-node.py")
SMOKE = load("smoke_home_node", "tools/smoke-home-node.py")


class HomeDeploymentTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        binary = self.root / "connector"
        binary.write_text("reviewed connector fixture")
        self.bundle = self.root / "gateway.tar.gz"
        self.report = PACKAGE.build(argparse.Namespace(
            output=self.bundle, binary=binary, kind="gateway", source_commit="test-snapshot"))

    def test_bundle_round_trip_and_no_secrets(self):
        extracted = self.root / "extracted"
        extracted.mkdir()
        release, manifest = INSTALL.extract_checked(self.bundle, self.report["sha256"], extracted)
        self.assertEqual(manifest["releaseId"], self.report["releaseId"])
        self.assertEqual((release / "hexproof-home").read_text(), "reviewed connector fixture")
        self.assertEqual(list(release.rglob("gateway.json")), [])

    def test_archive_checksum_is_required_before_extraction(self):
        destination = self.root / "unchecked"
        destination.mkdir()
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            INSTALL.extract_checked(self.bundle, "0" * 64, destination)
        self.assertEqual(list(destination.iterdir()), [])

    def test_archive_cannot_escape_destination(self):
        archive = self.root / "unsafe.tar.gz"
        with tarfile.open(archive, "w:gz") as stream:
            item = tarfile.TarInfo("../escaped")
            item.size = 4
            stream.addfile(item, io.BytesIO(b"test"))
        with self.assertRaises(tarfile.FilterError):
            PACKAGE.checked_archive(archive, PACKAGE.digest(archive), self.root / "unpack")
        self.assertFalse((self.root / "escaped").exists())

    def test_node_references_verified_central_sources_without_copying_archive(self):
        release = self.root / "release"
        runtime = release / "forge-runtime"
        runtime.mkdir(parents=True)
        source = self.root / "hexproof-forge-source-fixture.tar.gz"
        source.write_bytes(b"verified corresponding source archive fixture")
        checksum = PACKAGE.digest(source)
        reference = {"schemaVersion": 2, "archive": source.name, "sha256": checksum}
        (runtime / "SOURCE.json").write_text(json.dumps(reference))
        with self.assertRaisesRegex(ValueError, "requires forge-source"):
            PACKAGE.reference_forge_source(release, None, None)
        with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
            PACKAGE.reference_forge_source(release, source, "0" * 64)
        reference["sha256"] = "f" * 64
        (runtime / "SOURCE.json").write_text(json.dumps(reference))
        with self.assertRaisesRegex(ValueError, "matching source archive"):
            PACKAGE.reference_forge_source(release, source, checksum)
        self.assertFalse((release / "sources").exists())
        reference["sha256"] = checksum
        (runtime / "SOURCE.json").write_text(json.dumps(reference))
        record = PACKAGE.reference_forge_source(release, source, checksum)
        self.assertEqual(record["forgeSourceArchiveSha256"], checksum)
        self.assertEqual(record["forgeSourceArchiveName"], source.name)
        self.assertNotIn("forgeSourceArchive", record)
        self.assertFalse((release / "sources").exists())
        self.assertEqual(source.read_bytes(), b"verified corresponding source archive fixture")

    def upgrade_fixture(self, connector=True):
        base = self.root / "base"
        for name, content in {
            "hexproof-home": "old connector", "server/bin/hexproof-server": "old hub",
            "server/obsolete": "old package file", "java/bin/java": "verified Java",
            "java/LICENSE": "vendor license", "forge-runtime/forge-harness.jar": "verified Forge",
            "sources/forge-source.tar.gz": "corresponding sources",
            "deploy/hexproof-home-hub.service": "existing unit",
            "deploy/hexproof-home-node.service": "existing connector unit",
        }.items():
            path = base / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        (base / "java/license-link").symlink_to("LICENSE")
        checksum = PACKAGE.digest(base / "sources/forge-source.tar.gz")
        (base / "forge-runtime/SOURCE.json").write_text(json.dumps(
            {"schemaVersion": 2, "archive": "forge-source.tar.gz", "sha256": checksum}))
        sources = {"sourceCommit": "old-snapshot", "forgeArchiveSha256": "f" * 64,
                   "javaArchiveSha256": "a" * 64, "forgeSourceArchiveSha256": checksum,
                   "forgeSourceArchive": "sources/forge-source.tar.gz"}
        PACKAGE.seal_tree(base, "node", sources)
        archive = self.root / "server.tar.gz"
        with tarfile.open(archive, "w:gz") as stream:
            for name in ("hexproof-server", "hexproof-home") if connector else ("hexproof-server",):
                data = ("released " + name).encode()
                item = tarfile.TarInfo("server/bin/" + name)
                item.mode, item.size = 0o755, len(data)
                stream.addfile(item, io.BytesIO(data))
        return argparse.Namespace(upgrade_from=base, output=self.root / "upgraded",
            base_manifest_sha256=PACKAGE.digest(base / "manifest.json"), hub_archive=archive,
            hub_sha256=PACKAGE.digest(archive), source_commit="release-commit")

    def test_release_upgrade_externalizes_sources_and_preserves_runtime_and_rollback(self):
        args = self.upgrade_fixture()
        before = {str(path.relative_to(args.upgrade_from)): path.read_bytes()
                  for path in args.upgrade_from.rglob("*") if path.is_file()}
        result = PACKAGE.upgrade_node(args)
        manifest = INSTALL.verify_tree(args.output, result["manifestSha256"])
        self.assertEqual((args.output / "hexproof-home").read_text(), "released hexproof-home")
        self.assertEqual((args.output / "server/bin/hexproof-server").read_text(), "released hexproof-server")
        self.assertFalse((args.output / "server/obsolete").exists())
        for name, content in before.items():
            self.assertEqual((args.upgrade_from / name).read_bytes(), content)
            if name.startswith(("java/", "forge-runtime/", "deploy/")):
                self.assertEqual((args.output / name).read_bytes(), content)
        self.assertFalse((args.output / "sources").exists())
        self.assertEqual(manifest["sources"]["forgeSourceArchiveName"], "forge-source.tar.gz")
        self.assertEqual(manifest["sources"]["forgeSourceArchiveSha256"],
                         PACKAGE.digest(args.upgrade_from / "sources/forge-source.tar.gz"))
        self.assertNotIn("forgeSourceArchive", manifest["sources"])
        self.assertTrue((args.output / "java/license-link").is_symlink())
        self.assertEqual(manifest["sources"]["sourceCommit"], "release-commit")
        self.assertEqual(manifest["sources"]["forgeArchiveSha256"], "f" * 64)
        self.assertEqual(manifest["sources"]["hubArchiveSha256"], args.hub_sha256)
        self.assertEqual(manifest["sources"]["connectorSha256"], PACKAGE.digest(args.output / "hexproof-home"))

        # The next ordinary upgrade needs no local archive or installation inputs.
        args.upgrade_from, args.output = args.output, self.root / "upgraded-again"
        args.base_manifest_sha256 = PACKAGE.digest(args.upgrade_from / "manifest.json")
        second = PACKAGE.upgrade_node(args)
        INSTALL.verify_tree(args.output, second["manifestSha256"])
        self.assertFalse((args.output / "sources").exists())
        self.assertEqual(PACKAGE.forge_source_identity(second["sources"]),
                         PACKAGE.forge_source_identity(manifest["sources"]))

    def test_source_migration_rejects_invalid_references_before_removing_any_archive(self):
        args = self.upgrade_fixture()
        sources = json.loads((args.upgrade_from / "manifest.json").read_text())["sources"]
        invalid = [None, {}, {**sources, "forgeSourceArchiveSha256": "not-a-checksum"},
                   {**sources, "forgeSourceArchive": None},
                   {**sources, "forgeSourceArchive": "/outside/source.tar.gz"},
                   {**sources, "forgeSourceArchive": "sources/../source.tar.gz"},
                   {**sources, "forgeSourceArchiveName": "other.tar.gz"},
                   {**sources, "forgeSourceArchiveName": None},
                   {**sources, "forgeSourceArchiveSha256": "a" * 64}]
        archive = args.upgrade_from / "sources/forge-source.tar.gz"
        original = archive.read_bytes()
        for record in invalid:
            with self.subTest(record=record), self.assertRaises(ValueError):
                PACKAGE.externalize_forge_source(args.upgrade_from, record)
            self.assertEqual(archive.read_bytes(), original)

    def test_source_migration_keeps_unrelated_source_entries(self):
        args = self.upgrade_fixture()
        other = args.upgrade_from / "sources/other.txt"
        other.write_text("unrelated preserved data")
        sources = json.loads((args.upgrade_from / "manifest.json").read_text())["sources"]
        PACKAGE.seal_tree(args.upgrade_from, "node", sources)
        args.base_manifest_sha256 = PACKAGE.digest(args.upgrade_from / "manifest.json")
        PACKAGE.upgrade_node(args)
        self.assertEqual((args.output / "sources/other.txt").read_text(), other.read_text())
        self.assertFalse((args.output / "sources/forge-source.tar.gz").exists())

    def test_release_upgrade_rejects_modified_base_and_wrong_archive(self):
        args = self.upgrade_fixture()
        args.hub_sha256 = "0" * 64
        with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
            PACKAGE.upgrade_node(args)
        self.assertFalse(args.output.exists())
        args.hub_sha256 = PACKAGE.digest(args.hub_archive)
        (args.upgrade_from / "java/bin/java").write_text("tampered")
        with self.assertRaisesRegex(ValueError, "verification failed"):
            PACKAGE.upgrade_node(args)
        self.assertFalse(args.output.exists())

    def test_release_upgrade_rejects_missing_connector_and_output_inside_base(self):
        args = self.upgrade_fixture(connector=False)
        with self.assertRaisesRegex(ValueError, "Missing regular executable"):
            PACKAGE.upgrade_node(args)
        self.assertFalse(args.output.exists())
        args.output = args.upgrade_from / "nested"
        with self.assertRaisesRegex(ValueError, "outside the base"):
            PACKAGE.upgrade_node(args)
        self.assertFalse(args.output.exists())

    def test_current_inventory_verifies_payload_units_and_versions_without_secrets(self):
        args = self.upgrade_fixture()
        opt, units, config = (self.root / name for name in ("opt", "units", "config"))
        release = opt / "releases" / "baseline"
        release.parent.mkdir(parents=True)
        args.upgrade_from.rename(release)
        (opt / "current").symlink_to(release)
        units.mkdir()
        config.mkdir()
        (config / "node.json").write_text('{"token":"do-not-report-this"}')
        for unit in ("hexproof-home-hub.service", "hexproof-home-node.service"):
            (units / unit).write_bytes((release / "deploy" / unit).read_bytes())

        def command(*argv, **kwargs):
            if argv[-1] == "-version":
                output = Path(argv[0]).name + " 2.0.6\n"
            else:
                output = "100\n"
            return subprocess.CompletedProcess(argv, 0, output, "")

        with patch.object(INSTALL, "OPT", opt), patch.object(INSTALL, "UNITS", units), \
                patch.object(INSTALL, "CONFIG", config), patch.object(INSTALL, "run", side_effect=command), \
                patch.object(INSTALL, "await_ready"):
            state = INSTALL.inspect_current()
            self.assertEqual(state["version"], "2.0.6")
            self.assertEqual(state["manifestSha256"], args.base_manifest_sha256)
            self.assertEqual(state["hubSha256"], PACKAGE.digest(release / "server/bin/hexproof-server"))
            self.assertNotIn("do-not-report-this", json.dumps(state))
            (units / "hexproof-home-node.service").write_text("unexpected live unit")
            with self.assertRaisesRegex(ValueError, "sealed template"):
                INSTALL.inspect_current()
            (release / "java/bin/java").write_text("modified runtime")
            with self.assertRaisesRegex(ValueError, "verification failed"):
                INSTALL.inspect_current()

    def test_nginx_keeps_existing_routes_and_is_idempotent(self):
        original = ("server {\n    location = /ws { proxy_pass http://127.0.0.1:57320; }\n"
                    "    include /etc/nginx/snippets/hexproof-server-directory.inc;\n}\n")
        changed = INSTALL.nginx_with_home(original)
        self.assertEqual(INSTALL.nginx_with_home(changed), changed)
        self.assertIn("location = /ws { proxy_pass http://127.0.0.1:57320; }", changed)
        self.assertEqual(changed.count(str(INSTALL.SNIPPET)), 1)
        with self.assertRaises(ValueError):
            INSTALL.nginx_with_home("server { location / { return 404; } }")

    def test_empty_host_inventory_rejects_partial_installations_and_occupied_ports(self):
        paths = {name: self.root / name.lower() for name in ("OPT", "CONFIG", "STATE", "UNITS")}
        with ExitStack() as stack:
            for name, value in paths.items():
                stack.enter_context(patch.object(INSTALL, name, value))
            command = stack.enter_context(patch.object(INSTALL, "run",
                return_value=subprocess.CompletedProcess([], 3, "", "")))
            probe = stack.enter_context(patch.object(INSTALL.socket, "socket"))
            probe.return_value.__enter__.return_value.connect_ex.return_value = 111
            self.assertIsNone(INSTALL.inspect_current()["current"])
            # Preparing a tree does not turn an empty host into an installation.
            (paths["OPT"] / "prepared").mkdir(parents=True)
            self.assertIsNone(INSTALL.inspect_current()["current"])
            paths["CONFIG"].mkdir()
            with self.assertRaisesRegex(ValueError, "Incomplete"):
                INSTALL.inspect_current()
            paths["CONFIG"].rmdir()
            probe.return_value.__enter__.return_value.connect_ex.return_value = 0
            with self.assertRaisesRegex(ValueError, "port 57323"):
                INSTALL.inspect_current()
            probe.return_value.__enter__.return_value.connect_ex.return_value = 111
            command.return_value = subprocess.CompletedProcess([], 0, "", "")
            with self.assertRaisesRegex(ValueError, "active without"):
                INSTALL.inspect_current()

    def test_first_node_install_and_rollback_need_no_previous_release(self):
        bundle = self.upgrade_fixture()
        paths = {name: self.root / name.lower() for name in ("OPT", "CONFIG", "STATE", "UNITS")}
        config = self.root / "private.json"
        config.write_text(json.dumps({"backendUrl": "ws://127.0.0.1:57323/ws",
            "healthUrl": "http://127.0.0.1:57323/healthz", "token": "private-node-token"}))

        def command(*argv, **kwargs):
            output = ('openjdk version "21.0.12"' if Path(argv[0]).name == "java" else
                      "hexproof-server 2.1.0" if argv[-1] == "-version" else "")
            return subprocess.CompletedProcess(argv, 3 if "--quiet" in argv else 0, output, "")

        with ExitStack() as stack:
            for name, value in paths.items():
                stack.enter_context(patch.object(INSTALL, name, value))
            stack.enter_context(patch.object(INSTALL.os, "geteuid", return_value=0))
            stack.enter_context(patch.object(INSTALL.os, "chown"))
            stack.enter_context(patch.object(INSTALL.pwd, "getpwnam", return_value=SimpleNamespace(pw_uid=0)))
            stack.enter_context(patch.object(INSTALL.grp, "getgrnam", return_value=SimpleNamespace(gr_gid=0)))
            stack.enter_context(patch.object(INSTALL, "run", side_effect=command))
            stack.enter_context(patch.object(INSTALL, "await_ready"))
            result = INSTALL.install(argparse.Namespace(directory=bundle.upgrade_from,
                manifest_sha256=bundle.base_manifest_sha256, config=config, hub_version="2.1.0",
                prepared=None, prepare=False, activate=True))
            self.assertIsNone(result["previousRelease"])
            self.assertEqual((paths["CONFIG"] / "node.json").read_bytes(), config.read_bytes())
            self.assertTrue((paths["OPT"] / "current").is_symlink())
            self.assertEqual(list((paths["STATE"] / "retained").iterdir()), [])
            self.assertNotIn("private-node-token", json.dumps(result))
            INSTALL.rollback(Path(result["rollbackRecord"]), True)
            self.assertFalse((paths["OPT"] / "current").exists())
            self.assertFalse((paths["CONFIG"] / "node.json").exists())
            self.assertFalse((paths["UNITS"] / "hexproof-home-node.service").exists())

    def test_failed_activation_restores_only_owned_services_and_files(self):
        paths = {name: self.root / name.lower() for name in ("OPT", "CONFIG", "STATE", "UNITS")}
        paths["NGINX"] = self.root / "nginx.conf"
        paths["SNIPPET"] = self.root / "home.inc"
        for name in ("OPT", "CONFIG", "STATE", "UNITS"):
            paths[name].mkdir()
        old_release = paths["OPT"] / "releases" / "old"
        old_release.mkdir(parents=True)
        (old_release / "manifest.json").write_text('{"kind":"gateway"}')
        (paths["OPT"] / "current").symlink_to(old_release)
        old_config = paths["CONFIG"] / "gateway.json"
        old_config.write_text('{"oldCredential":"private"}')
        old_unit = paths["UNITS"] / "hexproof-home-gateway.service"
        old_unit.write_text("previous unit")
        nginx_bytes = b"server {\n    include /etc/nginx/snippets/hexproof-server-directory.inc;\n}\n"
        paths["NGINX"].write_bytes(nginx_bytes)
        new_config = self.root / "new.json"
        new_config.write_text(json.dumps({"listen": "127.0.0.1:57322"}))
        commands = []

        def command(*argv, check=True):
            commands.append(argv)
            return subprocess.CompletedProcess(argv, 0, "", "")

        arguments = argparse.Namespace(archive=self.bundle, sha256=self.report["sha256"],
                                       config=new_config, hub_version="2.0.6", activate=True)
        with ExitStack() as stack:
            for name, path in paths.items():
                stack.enter_context(patch.object(INSTALL, name, path))
            stack.enter_context(patch.object(INSTALL.os, "geteuid", return_value=0))
            stack.enter_context(patch.object(INSTALL.os, "chown"))
            stack.enter_context(patch.object(INSTALL.pwd, "getpwnam", return_value=SimpleNamespace(pw_uid=1)))
            stack.enter_context(patch.object(INSTALL.grp, "getgrnam", return_value=SimpleNamespace(gr_gid=1)))
            stack.enter_context(patch.object(INSTALL, "run", side_effect=command))
            stack.enter_context(patch.object(INSTALL, "await_ready", side_effect=RuntimeError("injected failure")))
            with self.assertRaisesRegex(RuntimeError, "injected failure"):
                INSTALL.install(arguments)
        self.assertEqual((paths["OPT"] / "current").resolve(), old_release)
        self.assertEqual(old_config.read_text(), '{"oldCredential":"private"}')
        self.assertEqual(old_unit.read_text(), "previous unit")
        self.assertEqual(paths["NGINX"].read_bytes(), nginx_bytes)
        self.assertFalse(paths["SNIPPET"].exists())
        self.assertIn(("systemctl", "start", "hexproof-home-gateway.service"), commands)
        self.assertFalse(any("hexproof.service" in command or "hexproof-server.service" in command
                             for command in commands))

    def test_smoke_handles_fragmented_reply_and_ping(self):
        incoming, outgoing = socket.socketpair()
        self.addCleanup(incoming.close)
        self.addCleanup(outgoing.close)
        client = SMOKE.WebSocket.__new__(SMOKE.WebSocket)
        client.sock = incoming
        client.buffer = bytearray()
        outgoing.sendall(b'\x01\x08{"type":' + b'\x89\x01?' + b'\x80\x04"x"}')
        self.assertEqual(client.receive(), {"type": "x"})
        pong = outgoing.recv(64)
        self.assertEqual(pong[0], 0x8A)
        self.assertEqual(pong[1], 0x81)
        self.assertEqual(pong[-1] ^ pong[2], ord("?"))

    def test_smoke_rejects_hidden_cards_and_missing_own_hand(self):
        snapshot = {"gameId": "synthetic", "zones": [{"zone": "hand", "ownerSeat": 0,
                    "count": 1, "cards": [{"visible": True, "identity": {"name": "Mountain"}}]}]}
        SMOKE.verify_projection(snapshot, 0)
        for seat in (1, -1):
            with self.assertRaisesRegex(ValueError, "hidden card"):
                SMOKE.verify_projection(snapshot, seat)
        snapshot["zones"][0]["cards"] = []
        with self.assertRaisesRegex(ValueError, "omitted cards"):
            SMOKE.verify_projection(snapshot, 0)

    def test_ai_gate_uses_real_welcome_not_healthy_forge(self):
        welcome = {"v": "hexproof.v2", "serverVersion": "2.0.6", "forgeRulesAvailable": True}
        with patch.object(SMOKE, "HTTP") as http, patch.object(SMOKE, "WebSocket") as websocket:
            http.open.return_value.__enter__.return_value.status = 200
            http.open.return_value.__enter__.return_value.read.return_value = b"ok\n"
            client = websocket.return_value
            client.until.return_value = welcome
            with self.assertRaisesRegex(ValueError, "native Forge AI availability"):
                SMOKE.smoke("wss://gateway.example/home/node/ws", "2.0.6", True, False, True)
            client.close.assert_called_once()
            welcome["forgeAIAvailable"] = True
            report = SMOKE.smoke("wss://gateway.example/home/node/ws", "2.0.6", True, False, True)
            self.assertTrue(report["forgeAIAvailable"])
            self.assertEqual(client.close.call_count, 2)


if __name__ == "__main__":
    unittest.main()
