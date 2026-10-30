#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("local_backup", ROOT / "tools/local-config-backup.py")
BACKUP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BACKUP)


class LocalConfigBackupTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.home = self.root / "original-home"
        self.repo = self.home / "hexproof"
        self.repo.mkdir(parents=True)
        self.archive = self.root / "private.tar.gz"
        self.target_home = self.root / "restored-home"
        self.target_repo = self.target_home / "new-clone"
        self.write(self.home / ".ssh/id_ed25519", b"private-key-fixture")
        self.write(self.home / ".ssh/known_hosts", b"trusted-host-fixture")
        self.write(self.home / ".ssh/config", f"IdentityFile {self.home}/.ssh/id_ed25519\n".encode())
        self.write(self.home / ".ssh/known_hosts.old", b"old history")
        self.write(self.home / ".ssh/agent/cache", b"runtime cache")
        self.write(self.home / BACKUP.OPERATOR / "multica-operations.json", json.dumps({
            "host": {"repositoryRoot": str(self.repo), "privateStateDirectory": str(self.home / "private")},
            "feedback": {"connectionFile": str(self.home / BACKUP.FEEDBACK / "connection.json")},
            "token": str(self.home / "opaque-secret-must-not-change"),
        }).encode())
        self.write(self.home / BACKUP.OPERATOR / "feedback-deployment.json", json.dumps({
            "inputsFile": str(self.home / BACKUP.FEEDBACK / "inputs.production.json")}).encode())
        self.write(self.home / BACKUP.FEEDBACK / "inputs.production.json", json.dumps({
            "githubTokenFile": str(self.home / BACKUP.FEEDBACK / "github-token")}).encode())
        self.write(self.home / BACKUP.FEEDBACK / "github-token", str(self.home / "opaque-token").encode())
        self.write(self.home / BACKUP.FEEDBACK / "connection.json", b'{"socket":"/run/user/1001/native.sock"}')
        self.write(self.repo / "apps/client-qt/config/servers.json", b'{"servers":[]}')
        for path in [self.repo / "build/large-output", self.repo / "data/decks.json",
                     self.home / BACKUP.OPERATOR / "audits/old-log.json",
                     self.home / ".config/gh/hosts.yml"]:
            self.write(path, b"not part of the minimal backup")

    @staticmethod
    def write(path, data):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def create(self):
        with patch.object(BACKUP.os, "getuid", return_value=1001):
            return BACKUP.create(self.archive, self.home, self.repo)

    def test_minimal_selection_private_archive_and_relocated_roundtrip(self):
        self.create()
        self.assertEqual(self.archive.stat().st_mode & 0o777, 0o600)
        with tarfile.open(self.archive) as stream:
            names = stream.getnames()
        self.assertIn("home/.ssh/id_ed25519", names)
        self.assertIn("home/" + BACKUP.FEEDBACK + "/github-token", names)
        self.assertFalse(any("build/" in name or "audits/" in name or "decks.json" in name
                             or "known_hosts.old" in name or "/agent/" in name or "hosts.yml" in name
                             for name in names))
        with patch.object(BACKUP.os, "getuid", return_value=2002):
            result = BACKUP.restore(self.archive, self.target_home, self.target_repo)
        self.assertGreater(result["restored"], 0)
        self.assertEqual((self.target_home / ".ssh").stat().st_mode & 0o777, 0o700)
        self.assertEqual((self.target_home / ".ssh/id_ed25519").stat().st_mode & 0o777, 0o600)
        self.assertEqual((self.target_home / ".ssh/id_ed25519").read_bytes(), b"private-key-fixture")
        self.assertIn(str(self.target_home), (self.target_home / ".ssh/config").read_text())
        config = json.loads((self.target_home / BACKUP.OPERATOR / "multica-operations.json").read_text())
        self.assertEqual(config["host"]["repositoryRoot"], str(self.target_repo))
        self.assertEqual(config["token"], str(self.home / "opaque-secret-must-not-change"))
        self.assertEqual((self.target_home / BACKUP.FEEDBACK / "github-token").read_bytes(),
                         (self.home / BACKUP.FEEDBACK / "github-token").read_bytes())
        socket = json.loads((self.target_home / BACKUP.FEEDBACK / "connection.json").read_text())["socket"]
        self.assertEqual(socket, "/run/user/2002/native.sock")
        self.assertTrue((self.target_repo / "apps/client-qt/config/servers.json").is_file())

    def test_dry_run_and_conflict_preflight_do_not_write_partial_configuration(self):
        self.create()
        BACKUP.restore(self.archive, self.target_home, self.target_repo, dry_run=True)
        self.assertFalse(self.target_home.exists())
        key = self.target_home / ".ssh/id_ed25519"
        self.write(key, b"new system private key")
        with self.assertRaisesRegex(ValueError, "differs"):
            BACKUP.restore(self.archive, self.target_home, self.target_repo)
        self.assertEqual(key.read_bytes(), b"new system private key")
        self.assertFalse((self.target_home / ".local").exists())

    def test_explicit_overwrite_retains_previous_file_and_rerun_is_idempotent(self):
        self.create()
        key = self.target_home / ".ssh/id_ed25519"
        self.write(key, b"previous-key")
        result = BACKUP.restore(self.archive, self.target_home, self.target_repo, overwrite=True)
        previous = Path(result["previousFiles"]) / "home/.ssh/id_ed25519"
        self.assertEqual(previous.read_bytes(), b"previous-key")
        self.assertEqual(previous.stat().st_mode & 0o777, 0o600)
        key.chmod(0o666)
        second = BACKUP.restore(self.archive, self.target_home, self.target_repo)
        self.assertIsNone(second["previousFiles"])
        self.assertEqual(key.stat().st_mode & 0o777, 0o600)

    def test_symlink_destination_and_non_regular_conflict_are_rejected_before_writes(self):
        self.create()
        outside = self.root / "outside"
        outside.mkdir()
        self.target_home.mkdir()
        (self.target_home / ".ssh").symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "Unsafe"):
            BACKUP.restore(self.archive, self.target_home, self.target_repo, overwrite=True)
        self.assertEqual(list(outside.iterdir()), [])
        (self.target_home / ".ssh").unlink()
        (self.target_home / ".ssh/id_ed25519").mkdir(parents=True)
        with self.assertRaisesRegex(ValueError, "regular file"):
            BACKUP.restore(self.archive, self.target_home, self.target_repo, overwrite=True)
        self.assertFalse((self.target_home / ".local").exists())

    def crafted(self, files, *, extra=None, bad_checksum=False, pax=None):
        entries = [{"path": name, "mode": 0o600,
                    "format": "opaque",
                    "sha256": "0" * 64 if bad_checksum else hashlib.sha256(data).hexdigest()}
                   for name, data in files.items()]
        manifest = {"version": 1, "home": str(self.home), "repository": str(self.repo),
                    "uid": 1001, "files": entries}
        with tarfile.open(self.archive, "w:gz") as stream:
            for name, data in {"manifest.json": json.dumps(manifest).encode(), **files}.items():
                member = tarfile.TarInfo(name)
                member.size = len(data)
                if pax:
                    member.pax_headers = pax
                stream.addfile(member, io.BytesIO(data))
            if extra:
                stream.addfile(extra, io.BytesIO(b""))

    def test_traversal_outside_allowlist_and_overlapping_members_are_rejected(self):
        for files in [{"home/.ssh/../../escape": b"x"}, {"home/.bashrc": b"x"},
                      {"repo/README.md": b"x"},
                      {"home/.ssh/conflict": b"x", "home/.ssh/conflict/child": b"y"}]:
            with self.subTest(files=list(files)):
                self.crafted(files)
                with self.assertRaises(ValueError):
                    BACKUP.restore(self.archive, self.target_home, self.target_repo)
                self.assertFalse(self.target_home.exists())

    def test_links_directories_duplicate_and_unlisted_members_are_rejected(self):
        for kind in [tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.DIRTYPE, tarfile.REGTYPE]:
            with self.subTest(kind=kind):
                extra = tarfile.TarInfo("home/.ssh/id_ed25519")
                extra.type, extra.linkname = kind, "/outside"
                self.crafted({"home/.ssh/id_ed25519": b"x"}, extra=extra)
                with self.assertRaises(ValueError):
                    BACKUP.restore(self.archive, self.target_home, self.target_repo)
                self.assertFalse(self.target_home.exists())
        self.crafted({"home/.ssh/id_ed25519": b"x"}, extra=tarfile.TarInfo("home/.ssh/unlisted"))
        with self.assertRaisesRegex(ValueError, "unlisted"):
            BACKUP.restore(self.archive, self.target_home, self.target_repo)

    def test_checksum_and_resource_limits_stop_before_restore(self):
        self.crafted({"home/.ssh/id_ed25519": b"x"}, bad_checksum=True)
        with self.assertRaisesRegex(ValueError, "checksum"):
            BACKUP.restore(self.archive, self.target_home, self.target_repo)
        self.crafted({"home/.ssh/id_ed25519": b"x", "home/.ssh/config": b"x"})
        for limit, value in [("MAX_FILES", 1), ("MAX_FILE_BYTES", 10), ("MAX_TOTAL_BYTES", 10)]:
            with self.subTest(limit=limit), patch.object(BACKUP, limit, value), self.assertRaises(ValueError):
                BACKUP.restore(self.archive, self.target_home, self.target_repo)
        self.assertFalse(self.target_home.exists())

    def test_create_failure_does_not_publish_archive_or_leave_private_temporaries(self):
        with patch.object(BACKUP.tarfile.TarFile, "addfile", side_effect=OSError("fixture failure")):
            with self.assertRaises(OSError):
                self.create()
        self.assertFalse(self.archive.exists())
        self.assertEqual(list(self.root.glob(".hexproof-private-backup-*")), [])
        self.archive.write_bytes(b"existing backup")
        with self.assertRaisesRegex(ValueError, "already exists"):
            self.create()
        self.assertEqual(self.archive.read_bytes(), b"existing backup")

    def test_missing_active_credential_dependency_stops_backup(self):
        (self.home / BACKUP.FEEDBACK / "github-token").unlink()
        with self.assertRaisesRegex(ValueError, "Referenced configuration is missing"):
            self.create()
        self.assertFalse(self.archive.exists())

    def test_path_relocation_is_single_pass_and_secret_env_values_are_opaque(self):
        manifest = {"home": str(self.home), "repository": str(self.repo), "uid": 1001}
        repo = self.home / "different-clone"
        text = f"IdentityFile {self.repo}/key\n".encode()
        result = BACKUP.relocate(text, "home/.ssh/config", manifest, self.target_home, repo, "text")
        self.assertEqual(result, f"IdentityFile {repo}/key\n".encode())
        secret = f"SECRET_TOKEN={self.home}/opaque\n".encode()
        self.assertEqual(BACKUP.relocate(secret, "home/" + BACKUP.OPERATOR + "/token.env",
                                         manifest, self.target_home, self.target_repo, "text"), secret)

    def test_opaque_json_credentials_and_smtp_dependencies_are_preserved(self):
        inputs = self.home / BACKUP.FEEDBACK / "inputs.production.json"
        opaque = self.home / BACKUP.FEEDBACK / "token.json"
        smtp = self.home / BACKUP.FEEDBACK / "smtp-password"
        self.write(opaque, b"credential that is not JSON")
        self.write(smtp, b"smtp password fixture")
        inputs.write_text(json.dumps({"githubTokenFile": str(opaque), "smtpPasswordFile": str(smtp)}))
        self.create()
        BACKUP.restore(self.archive, self.target_home, self.target_repo)
        self.assertEqual((self.target_home / BACKUP.FEEDBACK / "token.json").read_bytes(), opaque.read_bytes())
        self.assertEqual((self.target_home / BACKUP.FEEDBACK / "smtp-password").read_bytes(), smtp.read_bytes())
        manifest = {"home": str(self.home), "repository": str(self.repo), "uid": 1001}
        secret = json.dumps({"socket": str(self.home / "opaque-token")}).encode()
        self.assertEqual(BACKUP.relocate(secret, "home/" + BACKUP.FEEDBACK + "/token.json",
                                         manifest, self.target_home, self.target_repo, "opaque"), secret)

    def test_runtime_uid_relocation_in_ssh_environment_and_unit_configuration(self):
        manifest = {"home": str(self.home), "repository": str(self.repo), "uid": 1001}
        for name, text in [("home/.ssh/config", "ControlPath /run/user/1001/ssh.sock\n"),
                           ("home/" + BACKUP.OPERATOR + "/tunnel.env", "NATIVE_SOCKET=/run/user/1001/native.sock\n"),
                           ("home/" + BACKUP.TUNNEL, "ExecStart=/usr/bin/ssh -L /run/user/1001/native.sock node\n")]:
            with self.subTest(name=name), patch.object(BACKUP.os, "getuid", return_value=2002):
                result = BACKUP.relocate(text.encode(), name, manifest, self.target_home, self.target_repo, "text")
                self.assertEqual(result, text.replace("/run/user/1001/", "/run/user/2002/").encode())

    def test_repo_smtp_credential_is_selected_only_when_actively_referenced(self):
        gmail = self.repo / "gmail"
        self.write(gmail, b"smtp fixture")
        self.assertNotIn("repo/gmail", BACKUP.collect(self.home, self.repo))
        inputs = self.home / BACKUP.FEEDBACK / "inputs.production.json"
        inputs.write_text(json.dumps({"smtpPasswordFile": str(gmail)}))
        self.create()
        BACKUP.restore(self.archive, self.target_home, self.target_repo)
        self.assertEqual((self.target_repo / "gmail").read_bytes(), gmail.read_bytes())

    def test_unsupported_local_dependency_is_reported_instead_of_silently_omitted(self):
        unknown = self.home / "other-credentials/token"
        self.write(unknown, b"fixture")
        inputs = self.home / BACKUP.FEEDBACK / "inputs.production.json"
        inputs.write_text(json.dumps({"githubTokenFile": str(unknown)}))
        with self.assertRaisesRegex(ValueError, "outside the backup allowlist"):
            self.create()
        self.assertFalse(self.archive.exists())

    def test_unselected_private_directory_symlink_is_not_followed_or_modified(self):
        self.crafted({"home/.ssh/id_ed25519": b"x"})
        outside = self.root / "unrelated"
        outside.mkdir(mode=0o755)
        link = self.target_home / BACKUP.OPERATOR
        link.parent.mkdir(parents=True)
        link.symlink_to(outside, target_is_directory=True)
        BACKUP.restore(self.archive, self.target_home, self.target_repo)
        self.assertEqual(outside.stat().st_mode & 0o777, 0o755)
        self.assertEqual(list(outside.iterdir()), [])

    def test_tar_pax_metadata_is_included_in_expanded_size_limit(self):
        self.crafted({"home/.ssh/id_ed25519": b"x"})
        with patch.object(BACKUP, "MAX_TOTAL_BYTES", 12000):
            BACKUP.read_archive(self.archive, self.target_home, self.target_repo)
        self.crafted({"home/.ssh/id_ed25519": b"x"}, pax={"comment": "x" * 20000})
        self.assertLess(self.archive.stat().st_size, 12000)
        with patch.object(BACKUP, "MAX_TOTAL_BYTES", 12000), self.assertRaisesRegex(ValueError, "expanded size"):
            BACKUP.restore(self.archive, self.target_home, self.target_repo)
        self.assertFalse(self.target_home.exists())

    def test_default_invocation_restores_from_fresh_clone_root(self):
        self.target_repo.mkdir(parents=True)
        self.archive = self.target_repo / BACKUP.ARCHIVE_NAME
        self.create()
        tools = self.target_repo / "tools"
        tools.mkdir()
        script = tools / "local-config-backup.py"
        shutil.copy2(ROOT / "tools/local-config-backup.py", script)
        result = subprocess.run([sys.executable, str(script)], cwd=self.target_repo,
                                env={**os.environ, "HOME": str(self.target_home)},
                                capture_output=True, text=True, check=True)
        self.assertGreater(json.loads(result.stdout)["restored"], 0)
        self.assertEqual((self.target_home / ".ssh/id_ed25519").read_bytes(), b"private-key-fixture")


if __name__ == "__main__":
    unittest.main()
