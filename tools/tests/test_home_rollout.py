#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import argparse
from contextlib import ExitStack
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("home_rollout", ROOT / "tools/deploy-home-nodes.py")
DEPLOY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DEPLOY)
INSTALL, PACKAGE = DEPLOY.INSTALL, DEPLOY.PACKAGE


class HomeRolloutTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
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
        with patch.object(DEPLOY, "assert_idle"), patch.object(DEPLOY, "ssh", side_effect=[
                json.dumps(activation), '{"restoredRelease":"previous"}']) as ssh, \
                patch.object(DEPLOY.SMOKE, "smoke", return_value={}), \
                patch.object(DEPLOY.SMOKE, "forge_smoke", side_effect=ValueError("failed game")):
            with self.assertRaisesRegex(ValueError, "failed game"):
                DEPLOY.activate(target, record, ("/stage", {}), "2.0.6", self.root)
        self.assertIn("--rollback", ssh.call_args.args)
        self.assertTrue((self.root / "fixture-rollback.json").exists())

    def test_identical_running_release_has_no_mutation_or_test_room(self):
        with patch.object(DEPLOY, "ssh") as ssh, patch.object(DEPLOY.SMOKE, "forge_smoke") as smoke:
            DEPLOY.activate({"ssh": "fixture"}, {}, ("/stage", {"unchanged": True}), "2.0.6", self.root)
        ssh.assert_not_called()
        smoke.assert_not_called()

    def test_cached_artifact_hash_is_rechecked(self):
        record = {"path": str(self.binary), "sha256": PACKAGE.digest(self.binary)}
        self.assertEqual(DEPLOY.verified_artifact(record), self.binary)
        self.binary.write_text("stale cache")
        with self.assertRaisesRegex(ValueError, "checksum mismatch"):
            DEPLOY.verified_artifact(record)


if __name__ == "__main__":
    unittest.main()
