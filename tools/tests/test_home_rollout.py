#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import argparse
import copy
from contextlib import ExitStack
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("home_release", ROOT / "deploy/deploy-home-release.py")
RELEASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RELEASE)
INSTALL, PACKAGE = RELEASE.INSTALL, RELEASE.PACKAGE


class HomeRolloutTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.protocol_probe = patch.object(RELEASE, "running_protocol", return_value="hexproof.v2")
        self.protocol_probe.start()
        self.addCleanup(self.protocol_probe.stop)
        self.root = Path(temporary.name)
        self.binary = self.root / "binary"
        self.binary.write_text("reviewed executable")
        self.tree = self.root / "tree"
        self.record = PACKAGE.build(argparse.Namespace(output=self.tree, directory=True,
            binary=self.binary, kind="gateway", source_commit="reviewed"))

    def test_directory_is_sealed_and_rejects_modified_or_unlisted_content(self):
        self.assertEqual(INSTALL.verify_tree(self.tree, self.record["manifestSha256"])["releaseId"],
                         self.record["releaseId"])
        with self.assertRaisesRegex(ValueError, "manifest SHA-256"):
            INSTALL.verify_tree(self.tree, "0" * 64)
        extra = self.tree / "unexpected"
        extra.write_text("unlisted")
        with self.assertRaisesRegex(ValueError, "unlisted"):
            INSTALL.verify_tree(self.tree)
        extra.unlink()
        (self.tree / "hexproof-home").write_text("modified")
        with self.assertRaisesRegex(ValueError, "verification failed"):
            INSTALL.verify_tree(self.tree)

    def test_prepare_then_activate_uses_protected_tree_and_same_version_does_not_restart(self):
        paths = {name: self.root / name.lower() for name in ("OPT", "CONFIG", "STATE", "UNITS")}
        paths.update(NGINX=self.root / "nginx", SNIPPET=self.root / "include")
        for name in ("OPT", "CONFIG", "STATE", "UNITS"):
            paths[name].mkdir()
        paths["NGINX"].write_text("server {\n    include /etc/nginx/snippets/hexproof-server-directory.inc;\n}\n")
        config = self.root / "config.json"
        config.write_text('{"listen":"127.0.0.1:57322"}')
        args = argparse.Namespace(directory=self.tree, manifest_sha256=self.record["manifestSha256"],
            config=config, hub_version="2.0.6", activate=False, prepare=True, prepared=None)
        commands = []

        def command(*argv, **kwargs):
            commands.append(argv)
            return subprocess.CompletedProcess(argv, 0, "", "")

        with ExitStack() as stack:
            for name, value in paths.items():
                stack.enter_context(patch.object(INSTALL, name, value))
            stack.enter_context(patch.object(INSTALL.os, "geteuid", return_value=0))
            stack.enter_context(patch.object(INSTALL.os, "chown"))
            stack.enter_context(patch.object(INSTALL.pwd, "getpwnam", return_value=SimpleNamespace(pw_uid=0)))
            stack.enter_context(patch.object(INSTALL.grp, "getgrnam", return_value=SimpleNamespace(gr_gid=0)))
            stack.enter_context(patch.object(INSTALL, "run", side_effect=command))
            stack.enter_context(patch.object(INSTALL, "await_ready"))
            INSTALL.install(args)
            prepared = paths["OPT"] / "prepared" / self.record["releaseId"]
            self.assertTrue(prepared.is_dir())
            self.assertFalse(any("restart" in call for call in commands))
            # Changes to the upload after prepare must not enter the running release.
            (self.tree / "hexproof-home").write_text("modified upload")
            args.directory = None
            args.prepared = self.record["releaseId"]
            args.activate = True
            # Simulate root ownership without changing filesystem ownership in tests.
            original_stat = Path.stat
            def root_owned(path, *positional, **keywords):
                result = original_stat(path, *positional, **keywords)
                if path == prepared:
                    values = list(result)
                    values[4] = 0
                    return os.stat_result(values)
                return result
            with patch.object(Path, "stat", root_owned):
                INSTALL.install(args)
            self.assertEqual((paths["OPT"] / "current/hexproof-home").read_text(), "reviewed executable")
            commands.clear()
            args.prepared = None
            args.directory = paths["OPT"] / "current"
            result = INSTALL.install(args)
            self.assertTrue(result["unchanged"])
            self.assertFalse(any("restart" in call for call in commands))

    def test_native_smoke_failure_rolls_back_before_next_target(self):
        target = {"ssh": "fixture", "endpoint": "wss://fixture.example/ws"}
        record = {"releaseId": "a" * 24, "manifestSha256": "b" * 64}
        activation = {"rollbackRecord": "/var/lib/hexproof-home/deployments/fixture/rollback.json"}
        with patch.object(RELEASE, "assert_idle"), patch.object(RELEASE, "ssh", side_effect=[
                'hexproof-server 2.0.6\n', json.dumps(activation), '{"restoredRelease":"previous"}']) as ssh, \
                patch.object(RELEASE.SMOKE, "smoke", return_value={}), \
                patch.object(RELEASE.SMOKE, "forge_smoke", side_effect=ValueError("failed game")):
            with self.assertRaisesRegex(ValueError, "failed game"):
                RELEASE.activate(target, record, ("/stage", {}), "2.0.6", self.root)
        self.assertIn("--rollback", ssh.call_args.args)
        self.assertTrue((self.root / "fixture-rollback.json").exists())

    def test_version_upgrade_checks_old_version_before_restart_and_new_version_after(self):
        target = {"ssh": "fixture", "endpoint": "wss://fixture.example/ws"}
        record = {"releaseId": "a" * 24, "manifestSha256": "b" * 64}
        with patch.object(RELEASE, "assert_idle") as idle, \
                patch.object(RELEASE, "ssh", side_effect=['hexproof-server 2.0.6\n', '{}']) as ssh, \
                patch.object(RELEASE.SMOKE, "smoke", return_value={}) as welcome, \
                patch.object(RELEASE.SMOKE, "forge_smoke", return_value={}):
            RELEASE.activate(target, record, ("/stage", {}), "2.1.0", self.root)
        self.assertEqual([call.args[1] for call in idle.call_args_list], ["2.0.6", "2.1.0"])
        self.assertEqual(welcome.call_args.args[1], "2.1.0")
        self.assertIn("2.1.0", ssh.call_args.args)

    def test_unknown_current_version_stops_before_activation(self):
        with patch.object(RELEASE, "ssh", return_value="unexpected version") as ssh, \
                patch.object(RELEASE, "assert_idle") as idle:
            with self.assertRaisesRegex(ValueError, "current server version"):
                RELEASE.activate({"ssh": "fixture"}, {}, ("/stage", {}), "2.1.0", self.root)
        self.assertEqual(ssh.call_count, 1)
        idle.assert_not_called()

    def test_authorized_interruption_retains_post_activation_checks_and_rollback(self):
        target = {"ssh": "fixture", "endpoint": "wss://fixture.example/ws"}
        record = {"releaseId": "a" * 24, "manifestSha256": "b" * 64}
        activation = {"rollbackRecord": "/var/lib/hexproof-home/deployments/fixture/rollback.json"}
        with patch.object(RELEASE, "assert_idle", side_effect=ValueError("cleanup failed")) as idle, \
                patch.object(RELEASE, "ssh", side_effect=['hexproof-server 2.0.6\n',
                    json.dumps(activation), '{"restoredRelease":"previous"}']) as ssh, \
                patch.object(RELEASE.SMOKE, "smoke", return_value={}), \
                patch.object(RELEASE.SMOKE, "forge_smoke", return_value={}):
            with self.assertRaisesRegex(ValueError, "cleanup failed"):
                RELEASE.activate(target, record, ("/stage", {}), "2.1.0", self.root, allow_active_rooms=True)
        idle.assert_called_once_with(target, "2.1.0")
        self.assertIn("--rollback", ssh.call_args.args)

    def test_identical_running_release_has_no_mutation_or_test_room(self):
        with patch.object(RELEASE, "ssh") as ssh, patch.object(RELEASE.SMOKE, "forge_smoke") as smoke:
            RELEASE.activate({"ssh": "fixture"}, {}, ("/stage", {"unchanged": True}), "2.0.6", self.root)
        ssh.assert_not_called()
        smoke.assert_not_called()

    def test_first_install_uses_supplied_config_without_querying_an_old_service(self):
        target = {"ssh": "fixture", "endpoint": "wss://fixture/ws"}
        with patch.object(RELEASE, "running_version") as version, patch.object(RELEASE, "assert_idle") as idle, \
                patch.object(RELEASE, "ssh", return_value='{}') as ssh, \
                patch.object(RELEASE.SMOKE, "smoke", return_value={}), \
                patch.object(RELEASE.SMOKE, "forge_smoke", return_value={}):
            RELEASE.activate(target, {"releaseId": "a" * 24, "manifestSha256": "b" * 64},
                ("/stage", {"initial": True, "config": "/stage/node.json"}), "2.1.0", self.root)
        version.assert_not_called()
        idle.assert_called_once_with(target, "2.1.0")
        self.assertIn("/stage/node.json", ssh.call_args.args)

    def test_initial_stage_uploads_prepared_payload_and_private_config(self):
        config = self.root / "private.json"
        config.write_text('{"token":"keep-private"}')
        response = {"checked": True, "activated": False, "releaseId": self.record["releaseId"]}
        with patch.object(RELEASE, "run") as command, \
                patch.object(RELEASE, "ssh", side_effect=["", json.dumps(response)]) as ssh:
            _, staged = RELEASE.stage({"ssh": "fixture"}, {"current": None}, {}, {"version": "2.1.0"},
                "/stage", self.root, payload=self.record, config=config)
        self.assertTrue(staged[1]["initial"])
        self.assertEqual(staged[1]["configSha256"], PACKAGE.digest(config))
        self.assertFalse(any("--upgrade-from" in call.args for call in ssh.call_args_list))
        self.assertTrue(any(call.args[0][0] == "rsync" for call in command.call_args_list))
        self.assertNotIn("keep-private", (self.root / "fixture-staged.json").read_text())

    def test_cached_artifact_hash_is_rechecked(self):
        record = {"path": str(self.binary), "sha256": PACKAGE.digest(self.binary)}
        self.assertEqual(RELEASE.verified_artifact(record), self.binary)
        self.binary.write_text("stale cache")
        with self.assertRaisesRegex(ValueError, "checksum mismatch"):
            RELEASE.verified_artifact(record)


class GitHubHomeReleaseTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        nodes = json.loads((ROOT / "deploy/home/nodes.example.json").read_text())
        nodes.pop("_example")
        nodes["home-a"]["ssh"] = "home-a"
        inventory = self.root / "nodes.json"
        inventory.write_text(json.dumps(nodes))
        environment = patch.dict(os.environ, {"HEXPROOF_NODES_FILE": str(inventory)})
        environment.start()
        self.addCleanup(environment.stop)
        self.payloads = {}
        for arch in ("amd64", "arm64"):
            name = f"hexproof-server-2.1.0-linux-{arch}"
            archive = self.root / (name + ".tar.gz")
            with tarfile.open(archive, "w:gz") as stream:
                for binary in ("hexproof-server", "hexproof-home"):
                    data = (arch + " released " + binary).encode()
                    item = tarfile.TarInfo(name + "/bin/" + binary)
                    item.mode, item.size = 0o755, len(data)
                    stream.addfile(item, io.BytesIO(data))
            self.payloads[archive.name] = archive.read_bytes()
        import hashlib
        self.hash = lambda data: hashlib.sha256(data).hexdigest()
        self.payloads["SHA256SUMS"] = "".join(
            self.hash(data) + "  " + name + "\n" for name, data in self.payloads.items()).encode()
        self.metadata = {"databaseId": 123, "tagName": "v2.1.0", "targetCommitish": "master", "isDraft": False,
            "assets": [{"name": name, "digest": "sha256:" + self.hash(data)} for name, data in self.payloads.items()]}
        self.commands = []
        self.provenance_fails = False
        self.release_changes = False
        self.views = 0
        self.report = self.root / "report"
        self.report.mkdir()

    def github(self, *args):
        self.commands.append(args)
        if args[:2] == ("release", "view"):
            self.views += 1
            metadata = copy.deepcopy(self.metadata)
            if self.release_changes and self.views > 1:
                metadata["databaseId"] += 1
            return json.dumps(metadata)
        if args[0] == "api":
            return "f" * 40
        if args[:2] == ("release", "download"):
            directory = Path(args[args.index("--dir") + 1])
            for index, arg in enumerate(args):
                if arg == "--pattern":
                    name = args[index + 1]
                    (directory / name).write_bytes(self.payloads[name])
            return ""
        if args[:2] == ("attestation", "verify"):
            if self.provenance_fails:
                raise subprocess.CalledProcessError(1, ["gh", *args])
            return "[]\n"
        raise AssertionError(args)

    def fetch(self, version="2.1.0", allow_draft=False):
        with patch.object(RELEASE, "github", side_effect=self.github):
            return RELEASE.fetch_release("ClayStan404/hexproof", version, allow_draft,
                                         {"amd64", "arm64"}, self.report)

    def test_published_release_resolves_latest_and_pins_tag_commit_provenance(self):
        release = self.fetch(version=None)
        self.assertEqual(release["version"], "2.1.0")
        self.assertEqual(release["sourceCommit"], "f" * 40)
        self.assertEqual(set(release["artifacts"]), {"amd64", "arm64"})
        proof, = [args for args in self.commands if args[:2] == ("attestation", "verify")]
        for flag, value in (("--source-digest", "f" * 40), ("--source-ref", "refs/tags/v2.1.0"),
                ("--signer-workflow", "ClayStan404/hexproof/.github/workflows/release.yml")):
            self.assertEqual(proof[proof.index(flag) + 1], value)
        download, = [args for args in self.commands if args[:2] == ("release", "download")]
        self.assertEqual(download.count("--pattern"), 3)

    def test_initial_payload_uses_github_binaries_and_pinned_runtime_archives(self):
        release = self.fetch()

        def archive(name, files):
            path = self.root / (name + ".tar.gz")
            with tarfile.open(path, "w:gz") as stream:
                for relative, data in files.items():
                    item = tarfile.TarInfo(name + "/" + relative)
                    item.size, item.mode = len(data), 0o755
                    stream.addfile(item, io.BytesIO(data))
            return {"path": str(path), "sha256": PACKAGE.digest(path)}

        source = archive("forge-source", {"LICENSE": b"corresponding sources"})
        runtime = archive("forge-runtime", {"forge-harness.jar": b"verified runtime",
            "SOURCE.json": json.dumps({"schemaVersion": 2, "archive": Path(source["path"]).name,
                                        "sha256": source["sha256"]}).encode()})
        java = archive("java", {"bin/java": b"verified Java 21"})
        inputs = {"forge": {"runtime": runtime, "source": source}, "java": {"amd64": java}}
        with patch.object(RELEASE, "run") as validation:
            records = RELEASE.build_payloads(inputs, release, [{"arch": "amd64"}], self.report)
        self.assertIn("verify-release", validation.call_args.args[0])
        tree = Path(records["amd64"]["directory"])
        INSTALL.verify_tree(tree, records["amd64"]["manifestSha256"])
        self.assertEqual((tree / "hexproof-home").read_bytes(), b"amd64 released hexproof-home")
        self.assertEqual((tree / "server/bin/hexproof-server").read_bytes(), b"amd64 released hexproof-server")
        self.assertEqual((tree / "forge-runtime/forge-harness.jar").read_bytes(), b"verified runtime")
        self.assertEqual((tree / "sources/forge-source.tar.gz").read_bytes(), Path(source["path"]).read_bytes())
        Path(runtime["path"]).write_bytes(b"corrupted")
        with patch.object(RELEASE, "run") as validation:
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                RELEASE.build_payloads(inputs, release, [{"arch": "amd64"}], self.report)
        validation.assert_not_called()

    def test_draft_requires_explicit_version_and_opt_in(self):
        self.metadata["isDraft"] = True
        for version, allowed in (("2.1.0", False), (None, True)):
            with self.subTest(version=version, allowed=allowed), self.assertRaisesRegex(ValueError, "Draft deployment"):
                self.fetch(version, allowed)
        self.assertFalse(any(args[:2] == ("release", "download") for args in self.commands))
        self.assertTrue(self.fetch("2.1.0", True)["github"]["isDraft"])

    def test_corrupt_download_stops_before_provenance_or_remote_access(self):
        self.payloads["hexproof-server-2.1.0-linux-amd64.tar.gz"] = b"modified asset"
        with self.assertRaisesRegex(ValueError, "asset digest mismatch"):
            self.fetch()
        self.assertFalse(any(args[0] == "attestation" for args in self.commands))

    def test_bad_checksums_cannot_be_bypassed_by_matching_github_upload_digest(self):
        self.payloads["SHA256SUMS"] = self.payloads["SHA256SUMS"].replace(
            self.hash(self.payloads["hexproof-server-2.1.0-linux-amd64.tar.gz"]).encode(), b"0" * 64)
        self.metadata["assets"][-1]["digest"] = "sha256:" + self.hash(self.payloads["SHA256SUMS"])
        with self.assertRaisesRegex(ValueError, "Release checksum mismatch"):
            self.fetch()

    def test_unverified_provenance_stops_before_rollout(self):
        self.provenance_fails = True
        with patch.object(RELEASE, "github", side_effect=self.github), \
                patch.object(RELEASE, "rollout") as rollout, \
                patch.object(sys, "argv", ["deploy-home-release.py", "--targets", "home-a", "--version", "2.1.0",
                                           "--cache", str(self.root / "cache")]):
            with self.assertRaises(subprocess.CalledProcessError):
                RELEASE.main()
            rollout.assert_not_called()

    def test_backend_accepts_dotted_ssh_alias_by_name_or_alias(self):
        inventory = self.root / "nodes.json"
        nodes = json.loads(inventory.read_text())
        nodes["home-a"]["ssh"] = "home.a.example"
        nodes["home-a"]["endpoint"] = "wss://hub.example.com:8443/home/home-a/ws"
        inventory.write_text(json.dumps(nodes))
        for selected in ("home-a", "home.a.example"):
            with self.subTest(target=selected), patch.object(RELEASE, "github", side_effect=self.github), \
                    patch.object(RELEASE, "rollout") as rollout, \
                    patch.object(sys, "argv", ["deploy-home-release.py", "--targets", selected,
                                               "--version", "2.1.0", "--verify-only",
                                               "--cache", str(self.root / "cache")]):
                RELEASE.main()
                rollout.assert_called_once()
                self.assertEqual(rollout.call_args.args[0], [nodes["home-a"]])
                self.assertEqual(rollout.call_args.args[1]["version"], "2.1.0")
                self.assertTrue(rollout.call_args.args[3])

    def test_invalid_endpoint_ports_stop_at_inventory_before_network(self):
        inventory = self.root / "nodes.json"
        nodes = json.loads(inventory.read_text())
        for port in ("not-a-port", "99999", "0", ""):
            nodes["home-a"]["endpoint"] = "wss://hub.example.com:" + port + "/ws"
            inventory.write_text(json.dumps(nodes))
            with self.subTest(port=port):
                with self.assertRaisesRegex(ValueError, "Invalid deployment endpoint"):
                    RELEASE.operator_config.load_nodes()
                with patch.object(RELEASE, "github") as github, patch.object(RELEASE, "rollout") as rollout, \
                        patch.object(sys, "stderr", io.StringIO()), \
                        patch.object(sys, "argv", ["deploy-home-release.py", "--targets", "home-a",
                                                   "--version", "2.1.0"]), self.assertRaises(SystemExit):
                    RELEASE.main()
                github.assert_not_called()
                rollout.assert_not_called()

    def test_release_changed_during_download_is_rejected(self):
        self.release_changes = True
        with self.assertRaisesRegex(ValueError, "Release changed"):
            self.fetch()

    def test_alias_duplicates_and_implicit_draft_are_rejected_before_github(self):
        for arguments in (["--targets", "home-b", "home-b-ssh"], ["--targets", "home-a", "--allow-draft"],
                          ["--targets", "home-b", "--allow-active-rooms"],
                          ["--targets", "home-b", "--version", "2.1.0", "--allow-active-rooms", "--verify-only"],
                          ["--targets", "home-a", "--reinstall"],
                          ["--targets", "home-a", "--inputs", "private.json"],
                          ["--targets", "home-a", "--version", "2.1.0", "--inputs", "private.json", "--verify-only"]):
            with self.subTest(arguments=arguments), patch.object(sys, "argv", ["deploy-home-release.py", *arguments]), \
                    patch.object(sys, "stderr", io.StringIO()), \
                    patch.object(RELEASE, "github") as github, self.assertRaises(SystemExit):
                RELEASE.main()
            github.assert_not_called()


class HomeReleaseTransactionTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.report = Path(directory.name)
        self.targets = [{"ssh": "home-a", "arch": "amd64", "endpoint": "wss://fixture/home-a/ws"},
                        {"ssh": "home-b-ssh", "arch": "arm64", "endpoint": "wss://fixture/home-b/ws"}]
        self.release = {"version": "2.1.0", "sourceCommit": "f" * 40, "artifacts": {}}
        self.states, self.records = {}, {}
        for index, target in enumerate(self.targets):
            key = str(index + 1)
            self.release["artifacts"][target["arch"]] = {
                "sha256": key * 64, "binaries": {"hexproof-server": "b" * 64, "hexproof-home": "c" * 64}}
            self.records[target["ssh"]] = {"releaseId": key * 24, "manifestSha256": "d" * 64}
            self.states[target["ssh"]] = {"current": "/opt/hexproof-home/releases/previous", "manifestSha256": "a" * 64,
                "version": "2.0.6", "system": "Linux", "machine": "x86_64" if index == 0 else "aarch64",
                "hubSha256": "old hub", "connectorSha256": "old connector", "configSha256": "private config digest",
                "unitHashes": {"hub": "unit digest"}, "pids": {"hub": "100"},
                "manifest": {"treeSha256": "a" * 64, "sources": {"hubArchiveSha256": "old archive",
                    "forgeArchiveSha256": "forge", "forgeSourceArchiveSha256": "source", "javaArchiveSha256": "java"}}}
        self.originals = copy.deepcopy(self.states)
        self.events = []
        self.fail_stage = self.fail_activation = self.fail_public = self.change_baseline = None
        stack = self.enterContext(ExitStack())
        stack.enter_context(patch.object(RELEASE, "inspect", side_effect=lambda target: copy.deepcopy(self.states[target["ssh"]])))
        stack.enter_context(patch.object(RELEASE, "stage", side_effect=self.stage))
        stack.enter_context(patch.object(RELEASE, "restore", side_effect=self.restore))
        self.cleanup = stack.enter_context(patch.object(RELEASE, "cleanup"))
        self.idle = stack.enter_context(patch.object(RELEASE, "assert_idle"))
        stack.enter_context(patch.object(RELEASE, "activate", side_effect=self.activate))
        stack.enter_context(patch.object(RELEASE.SMOKE, "smoke", side_effect=self.smoke))

    def install(self, target):
        state = self.states[target["ssh"]]
        artifact = self.release["artifacts"][target["arch"]]
        state.update(version="2.1.0", hubSha256=artifact["binaries"]["hexproof-server"],
                     connectorSha256=artifact["binaries"]["hexproof-home"], pids={"hub": "200"})
        state["manifest"]["sources"]["hubArchiveSha256"] = artifact["sha256"]
        state["current"] = "/opt/hexproof-home/releases/" + self.records[target["ssh"]]["releaseId"]

    def stage(self, target, before, artifact, release, upload, report, **kwargs):
        name = target["ssh"]
        self.events.append(("stage", name))
        if name == self.fail_stage:
            raise ValueError("stage failed")
        if name == self.change_baseline:
            self.states[name]["configSha256"] = "concurrently changed"
        return self.records[name], (upload, {"checked": True, "activated": False,
                                           "configSha256": "private config digest"})

    def activate(self, target, record, staged, version, report, allow_active_rooms=False):
        name = target["ssh"]
        self.events.append(("activate", name))
        self.install(target)
        if name == self.fail_activation:
            raise OSError("activation reply lost")

    def restore(self, target, before, record, upload, report):
        self.events.append(("restore", target["ssh"]))
        self.states[target["ssh"]] = copy.deepcopy(before)

    def smoke(self, endpoint, version, *args):
        if endpoint == self.fail_public and version == "2.1.0":
            raise ValueError("public smoke failed")
        return {"serverVersion": version}

    def run_rollout(self, verify_only=False):
        return RELEASE.rollout(self.targets, self.release, self.report, verify_only)

    def test_stages_all_nodes_before_activation_and_preserves_runtime(self):
        result = self.run_rollout()
        self.assertEqual(self.events, [("stage", "home-a"), ("stage", "home-b-ssh"),
                                      ("activate", "home-a"), ("activate", "home-b-ssh")])
        self.assertEqual(result["activated"], ["home-a", "home-b-ssh"])
        self.assertEqual(self.cleanup.call_count, 2)
        for target in self.targets:
            self.assertTrue(RELEASE.matches(self.states[target["ssh"]], self.release["artifacts"][target["arch"]], "2.1.0"))

    def test_already_installed_is_read_only_even_without_verify_only(self):
        for target in self.targets:
            self.install(target)
        result = self.run_rollout()
        self.assertEqual(result["activated"], [])
        self.assertEqual(result["unchanged"], ["home-a", "home-b-ssh"])
        self.assertEqual(self.events, [])
        self.idle.assert_not_called()
        self.cleanup.assert_not_called()

    def test_active_rooms_block_staging_without_explicit_opt_in(self):
        self.idle.side_effect = ValueError("Active rooms")
        with self.assertRaisesRegex(ValueError, "Active rooms"):
            self.run_rollout()
        self.assertEqual(self.events, [])

    def test_explicit_interruption_stages_all_targets_and_retains_rollback(self):
        self.idle.side_effect = ValueError("Active rooms")
        self.fail_activation = "home-b-ssh"
        with self.assertRaisesRegex(OSError, "reply lost"):
            RELEASE.rollout(self.targets, self.release, self.report, allow_active_rooms=True)
        self.idle.assert_not_called()
        self.assertEqual(self.events[:2], [("stage", "home-a"), ("stage", "home-b-ssh")])
        self.assertEqual(self.events[-2:], [("restore", "home-b-ssh"), ("restore", "home-a")])
        self.assertEqual(self.states, self.originals)
        policy = json.loads((self.report / "interruption-policy.json").read_text())
        self.assertEqual(policy, {"allowActiveRooms": True, "targets": ["home-a", "home-b-ssh"]})

    def test_verify_only_mismatch_never_uploads_or_activates(self):
        with self.assertRaisesRegex(ValueError, "Release not installed"):
            self.run_rollout(verify_only=True)
        self.assertEqual(self.events, [])
        self.idle.assert_not_called()
        self.cleanup.assert_not_called()

    def test_older_published_latest_cannot_downgrade_a_newer_installed_draft(self):
        self.states["home-a"]["version"] = "2.2.0"
        with self.assertRaisesRegex(ValueError, "version downgrade"):
            self.run_rollout()
        self.assertEqual(self.events, [])
        self.idle.assert_not_called()

    def test_same_version_with_different_connector_requires_upgrade(self):
        for target in self.targets:
            self.install(target)
        self.states["home-b-ssh"]["connectorSha256"] = "different binary"
        result = self.run_rollout()
        self.assertEqual(result["activated"], ["home-b-ssh"])
        self.assertEqual(self.events, [("stage", "home-b-ssh"), ("activate", "home-b-ssh")])

    def test_second_stage_failure_never_restarts_a_service(self):
        self.fail_stage = "home-b-ssh"
        with self.assertRaisesRegex(ValueError, "stage failed"):
            self.run_rollout()
        self.assertEqual(self.events, [("stage", "home-a"), ("stage", "home-b-ssh")])
        self.assertEqual(self.states, self.originals)
        self.assertTrue((self.report / "uploads.json").exists())

    def test_lost_second_activation_reply_rolls_back_both_in_reverse_order(self):
        self.fail_activation = "home-b-ssh"
        with self.assertRaisesRegex(OSError, "reply lost"):
            self.run_rollout()
        self.assertEqual(self.events[-2:], [("restore", "home-b-ssh"), ("restore", "home-a")])
        self.assertEqual(self.states, self.originals)
        self.cleanup.assert_not_called()

    def test_public_failure_rolls_back_the_whole_changed_group(self):
        self.fail_public = self.targets[1]["endpoint"]
        with self.assertRaisesRegex(ValueError, "public smoke failed"):
            self.run_rollout()
        self.assertEqual(self.events[-2:], [("restore", "home-b-ssh"), ("restore", "home-a")])
        self.assertEqual(self.states, self.originals)

    def test_configuration_drift_stops_before_restart(self):
        self.change_baseline = "home-a"
        with self.assertRaisesRegex(ValueError, "baseline changed"):
            self.run_rollout()
        self.assertFalse(any(event[0] == "activate" for event in self.events))

    def test_missing_initial_inputs_never_uploads_or_restarts(self):
        self.states["home-a"]["current"] = None
        with self.assertRaisesRegex(ValueError, "First installation requires"):
            self.run_rollout()
        self.assertEqual(self.events, [])
        self.idle.assert_not_called()

    def test_initial_install_and_upgrade_share_the_same_transaction(self):
        self.states["home-a"]["current"] = None
        payloads = {node["arch"]: {"treeSha256": "a" * 64} for node in self.targets}
        with patch.object(RELEASE, "initial_config", return_value=self.report / "config.json"), \
                patch.object(RELEASE, "build_payloads", return_value=payloads):
            result = RELEASE.rollout(self.targets, self.release, self.report, inputs={})
        self.assertEqual(result["activated"], ["home-a", "home-b-ssh"])
        self.assertEqual(self.events[:2], [("stage", "home-a"), ("stage", "home-b-ssh")])
        self.idle.assert_called_once_with(self.targets[1], "2.0.6")

    def test_runtime_input_failure_does_not_touch_hosts(self):
        with patch.object(RELEASE, "build_payloads", side_effect=ValueError("invalid runtime")):
            with self.assertRaisesRegex(ValueError, "invalid runtime"):
                RELEASE.rollout(self.targets, self.release, self.report, inputs={})
        self.assertEqual(self.events, [])
        self.idle.assert_not_called()

    def test_verify_only_cannot_accept_installation_inputs(self):
        with self.assertRaisesRegex(ValueError, "Read-only"):
            RELEASE.rollout(self.targets, self.release, self.report, verify_only=True, inputs={})
        self.assertEqual(self.events, [])

    def test_verify_only_cannot_authorize_room_interruption(self):
        with self.assertRaisesRegex(ValueError, "Read-only"):
            RELEASE.rollout(self.targets, self.release, self.report, verify_only=True, allow_active_rooms=True)
        self.assertEqual(self.events, [])

    def test_runtime_no_op_is_not_rolled_back_when_another_node_fails(self):
        self.install(self.targets[0])
        baseline = copy.deepcopy(self.states["home-a"])
        payloads = {node["arch"]: {"treeSha256": "a" * 64} for node in self.targets}
        self.fail_activation = "home-b-ssh"

        def stage(*args, **kwargs):
            record, (upload, response) = self.stage(*args, **kwargs)
            response["unchanged"] = args[0]["ssh"] == "home-a"
            return record, (upload, response)

        def activate(target, record, staged, version, report, **kwargs):
            if not staged[1].get("unchanged"):
                self.activate(target, record, staged, version, report)

        with patch.object(RELEASE, "build_payloads", return_value=payloads), \
                patch.object(RELEASE, "stage", side_effect=stage), \
                patch.object(RELEASE, "activate", side_effect=activate):
            with self.assertRaisesRegex(OSError, "reply lost"):
                RELEASE.rollout(self.targets, self.release, self.report, inputs={})
        self.assertEqual(self.states["home-a"], baseline)
        self.assertEqual([event for event in self.events if event[0] == "restore"], [("restore", "home-b-ssh")])


class HomeReleaseRecoveryTests(unittest.TestCase):
    def test_failed_initial_install_rolls_back_without_an_old_public_server(self):
        with tempfile.TemporaryDirectory() as directory:
            current = "/opt/hexproof-home/releases/" + "a" * 24
            with patch.object(RELEASE, "ssh", side_effect=[current, '{"activated":true}', ""]) as ssh, \
                    patch.object(RELEASE.SMOKE, "smoke") as smoke:
                RELEASE.restore({"ssh": "fixture"}, {"current": None}, {"releaseId": "a" * 24},
                                "/stage", Path(directory))
            self.assertIn("--rollback", ssh.call_args_list[1].args)
            smoke.assert_not_called()

    def test_lost_ssh_reply_recovers_using_deterministic_rollback_record(self):
        with tempfile.TemporaryDirectory() as directory:
            before = {"current": "/opt/hexproof-home/releases/previous", "manifestSha256": "old",
                      "configSha256": "config", "unitHashes": {}, "version": "2.0.6"}
            record = {"releaseId": "a" * 24}
            with patch.object(RELEASE, "ssh", side_effect=[
                    "/opt/hexproof-home/releases/" + "a" * 24, '{"activated":true}']) as ssh, \
                    patch.object(RELEASE, "inspect", return_value=before), patch.object(RELEASE.SMOKE, "smoke"):
                RELEASE.restore({"ssh": "fixture", "endpoint": "wss://fixture/ws"}, before, record,
                                "/var/tmp/fixture", Path(directory))
            self.assertIn("--rollback", ssh.call_args.args)
            self.assertIn("/var/lib/hexproof-home/deployments/" + "a" * 24 + ".before/rollback.json", ssh.call_args.args)

    def test_recovery_refuses_an_unrelated_new_deployment(self):
        with patch.object(RELEASE, "ssh", return_value="/opt/hexproof-home/releases/unrelated") as ssh:
            with self.assertRaisesRegex(ValueError, "unrelated current tree"):
                RELEASE.restore({"ssh": "fixture"}, {"current": "/opt/hexproof-home/releases/previous"},
                                {"releaseId": "a" * 24}, "/var/tmp/fixture", Path("unused"))
            self.assertEqual(ssh.call_count, 1)


if __name__ == "__main__":
    unittest.main()
