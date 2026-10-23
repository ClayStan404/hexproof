# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Project-only AO setup recovery and real shell dispatch, without providers."""

import copy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("ao_reporting_setup", ROOT / "tools/configure-ao-reporting.py")
SETUP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SETUP)


class FakeAPI:
    def __init__(self, config):
        self.config = copy.deepcopy(config)
        self.host = "host-test"
        self.writes = []
        self.fail_write = False
        self.fail_readback = False
        self.change_on_recheck = False
        self.project_reads = 0

    def call(self, method, path, payload=None):
        if (method, path) == ("GET", "identity"):
            return {"apiVersion": 1, "hostId": self.host}
        if (method, path) == ("GET", "projects/example"):
            self.project_reads += 1
            if self.change_on_recheck and self.project_reads == 2:
                self.config["agentRules"] = "new owner rules"
            if self.fail_readback and self.writes:
                self.fail_readback = False
                raise SETUP.SetupError("Readback unavailable")
            return {"project": {"id": "example", "config": copy.deepcopy(self.config)}}
        if (method, path) == ("PUT", "projects/example/config"):
            if set(payload) != {"config"}:
                raise AssertionError("AO setConfig requires a config envelope")
            if self.fail_write:
                raise SETUP.SetupError("Write unavailable")
            self.config = copy.deepcopy(payload["config"])
            self.writes.append(copy.deepcopy(payload))
            return {"project": {"id": "example", "config": copy.deepcopy(self.config)}}
        raise AssertionError((method, path))


class ReportingSetupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.state = self.root / "state"
        self.state.mkdir()
        self.source = self.root / "tools"
        (self.source / "ao-reporting").mkdir(parents=True)
        for name in ("bash-env.sh", "zshenv"):
            shutil.copyfile(ROOT / "tools/ao-reporting" / name, self.source / "ao-reporting" / name)
        (self.source / "ao_review_report.py").write_text("# fixture helper v1\n")
        self.addCleanup(patch.stopall)
        patch.object(SETUP, "__file__", str(self.source / "configure-ao-reporting.py")).start()
        patch.object(SETUP, "executable", side_effect=lambda name: "/fixture/bin/" + name).start()
        patch.dict(os.environ, {}, clear=True).start()
        self.original = {"defaultBranch": "master", "autoReview": False,
                         "agentRules": "keep owner rules", "env": {"KEEP": "private-value"}}
        self.api = FakeAPI(self.original)

    def apply(self, operation="install"):
        return SETUP.apply(self.api, "example", self.state, operation)

    def record(self):
        return json.loads((self.state / "example.json").read_text())

    def test_install_is_scoped_and_record_omits_unrelated_environment(self):
        result = self.apply()
        self.assertTrue(result["newSessionsOnly"])
        self.assertTrue(self.apply("status")["installed"])
        self.assertEqual(self.api.config["agentRules"], self.original["agentRules"])
        self.assertFalse(self.api.config["autoReview"])
        self.assertEqual(self.api.config["env"]["KEEP"], "private-value")
        record = self.record()
        self.assertEqual(record["phase"], "installed")
        self.assertNotIn("private-value", json.dumps(record))
        self.assertTrue(all(value is None for value in record["previous"].values()))
        target = Path(record["bundle"])
        self.assertEqual(target.stat().st_mode & 0o777, 0o500)
        self.assertEqual((target / "ao_review_report.py").stat().st_mode & 0o777, 0o400)
        for name in (".zprofile", ".zshrc", ".zlogin", ".zlogout"):
            self.assertEqual((target / name).read_bytes(), (target / ".zshenv").read_bytes())

    def test_idempotent_reinstall_preserves_original_hooks_and_remove_restores_them(self):
        self.api.config["env"].update(BASH_ENV="/original/bash", ZDOTDIR="/original/zsh")
        original = copy.deepcopy(self.api.config)
        self.apply()
        first = self.record()
        self.apply()
        self.assertEqual(self.record()["bundle"], first["bundle"])
        self.assertEqual(self.record()["previous"], first["previous"])
        self.assertEqual(self.api.config["env"]["HEXPROOF_AO_PREVIOUS_BASH_ENV"], "/original/bash")
        self.assertEqual(self.api.config["env"]["HEXPROOF_AO_PREVIOUS_ZDOTDIR"], "/original/zsh")
        self.apply("remove")
        self.assertEqual(self.api.config, original)
        self.assertFalse((self.state / "example.json").exists())
        self.assertFalse(self.apply("remove")["installed"])

    def test_remove_drops_absent_keys_and_keeps_later_unrelated_edits(self):
        self.apply()
        self.api.config["env"]["LATER"] = "new value"
        self.api.config["defaultBranch"] = "develop"
        self.apply("remove")
        self.assertEqual(self.api.config["env"], {"KEEP": "private-value", "LATER": "new value"})
        self.assertEqual(self.api.config["defaultBranch"], "develop")
        self.assertNotIn(None, self.api.config["env"].values())

    def test_explicit_empty_hooks_do_not_inherit_installer_environment(self):
        self.api.config["env"].update(BASH_ENV="", ZDOTDIR="")
        with patch.dict(os.environ, {"BASH_ENV": "/ambient/bash", "ZDOTDIR": "/ambient/zsh"}):
            self.apply()
        self.assertEqual(self.api.config["env"]["HEXPROOF_AO_PREVIOUS_BASH_ENV"], "")
        self.assertEqual(self.api.config["env"]["HEXPROOF_AO_PREVIOUS_ZDOTDIR"], "")
        self.apply("remove")
        self.assertEqual(self.api.config["env"]["BASH_ENV"], "")
        self.assertEqual(self.api.config["env"]["ZDOTDIR"], "")

    def test_reinstall_preserves_original_ambient_hooks(self):
        with patch.dict(os.environ, {"BASH_ENV": "/first/bash", "ZDOTDIR": "/first/zsh"}):
            self.apply()
        with patch.dict(os.environ, {"BASH_ENV": "/later/bash", "ZDOTDIR": "/later/zsh"}):
            self.apply()
        self.assertEqual(self.api.config["env"]["HEXPROOF_AO_PREVIOUS_BASH_ENV"], "/first/bash")
        self.assertEqual(self.api.config["env"]["HEXPROOF_AO_PREVIOUS_ZDOTDIR"], "/first/zsh")

    def test_project_home_is_used_when_zdotdir_is_unset(self):
        self.api.config["env"]["HOME"] = "/isolated/profile"
        with patch.dict(os.environ, {"HOME": "/supervisor/profile"}):
            self.apply()
        self.assertEqual(self.api.config["env"]["HEXPROOF_AO_PREVIOUS_ZDOTDIR"], "/isolated/profile")
        self.assertEqual(self.api.config["env"]["HOME"], "/isolated/profile")
        self.apply("remove")
        self.assertEqual(self.api.config["env"]["HOME"], "/isolated/profile")
        self.assertNotIn("ZDOTDIR", self.api.config["env"])

    def test_nonliteral_bash_initialization_is_rejected_before_config_write(self):
        for value in ("$HOME/init", "${HOME}/init", "$(echo /tmp/init)", "`echo /tmp/init`",
                      "$((1+1))/init", "~/init", "~owner/init"):
            for source in ("project", "ambient"):
                with self.subTest(value=value, source=source):
                    self.api = FakeAPI(self.original)
                    environment = {}
                    if source == "project":
                        self.api.config["env"]["BASH_ENV"] = value
                    else:
                        environment["BASH_ENV"] = value
                    before = copy.deepcopy(self.api.config)
                    with patch.dict(os.environ, environment), self.assertRaisesRegex(SETUP.SetupError, "literal path"):
                        self.apply()
                    self.assertEqual(self.api.writes, [])
                    self.assertEqual(self.api.config, before)
                    self.assertFalse((self.state / "example.json").exists())

    def test_failed_first_write_keeps_recoverable_prepared_record(self):
        self.api.fail_write = True
        with self.assertRaises(SETUP.SetupError):
            self.apply()
        self.assertEqual(self.record()["phase"], "prepared")
        self.assertEqual(self.api.config, self.original)
        self.assertFalse(self.apply("status")["installed"])
        self.api.fail_write = False
        self.apply()
        self.assertTrue(self.apply("status")["installed"])

    def test_failed_bundle_upgrade_can_be_removed_using_original_values(self):
        self.apply()
        old = copy.deepcopy(self.api.config)
        (self.source / "ao_review_report.py").write_text("# fixture helper v2\n")
        self.api.fail_write = True
        with self.assertRaises(SETUP.SetupError):
            self.apply()
        self.assertEqual(self.api.config, old)
        self.assertEqual(self.record()["phase"], "prepared")
        self.apply("status")
        self.api.fail_write = False
        self.apply("remove")
        self.assertEqual(self.api.config, self.original)

    def test_ambiguous_successful_write_is_recovered_by_readback(self):
        self.api.fail_readback = True
        with self.assertRaises(SETUP.SetupError):
            self.apply()
        self.assertEqual(self.record()["phase"], "prepared")
        self.assertTrue(self.apply("status")["installed"])
        self.apply()
        self.assertEqual(self.record()["phase"], "installed")

    def test_changed_configuration_is_not_overwritten_and_record_allows_retry(self):
        self.api.change_on_recheck = True
        with self.assertRaisesRegex(SETUP.SetupError, "changed during setup"):
            self.apply()
        self.assertEqual(self.api.writes, [])
        self.api.change_on_recheck = False
        self.apply()
        self.assertEqual(self.api.config["agentRules"], "new owner rules")

    def test_owned_environment_conflict_and_wrong_host_fail_without_writes(self):
        self.apply()
        before = len(self.api.writes)
        original_hook = self.api.config["env"]["BASH_ENV"]
        self.api.config["env"]["BASH_ENV"] = "/owner/new-hook"
        with self.assertRaisesRegex(SETUP.SetupError, "environment changed"):
            self.apply("remove")
        self.api.config["env"]["BASH_ENV"] = original_hook
        self.api.host = "another-host"
        with self.assertRaisesRegex(SETUP.SetupError, "host changed"):
            self.apply()
        self.assertEqual(len(self.api.writes), before)

    def test_tampered_bundle_is_rejected_before_config_write(self):
        self.apply()
        helper = Path(self.record()["bundle"]) / "ao_review_report.py"
        helper.chmod(0o600)
        helper.write_text("# changed after installation\n")
        before = len(self.api.writes)
        with self.assertRaisesRegex(SETUP.SetupError, "content hash"):
            self.apply()
        self.assertEqual(len(self.api.writes), before)


class ReportingShellTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.owner = self.root / "owner"
        self.owner.mkdir()
        self.hooks = self.root / "hooks"
        self.hooks.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        shutil.copyfile(ROOT / "tools/ao-reporting/bash-env.sh", self.hooks / "bash-env.sh")
        for name in (".zshenv", ".zprofile", ".zshrc", ".zlogin", ".zlogout"):
            shutil.copyfile(ROOT / "tools/ao-reporting/zshenv", self.hooks / name)
        script = ("import json, os, sys\n"
                  "print(json.dumps({'kind': KIND, 'args':sys.argv[1:], 'stdin':sys.stdin.read(), "
                  "'owner':os.getenv('OWNER_INIT'), 'login':os.getenv('OWNER_LOGIN'), "
                  "'zdotdir':os.getenv('ZDOTDIR'), 'previous_zdotdir':os.getenv('HEXPROOF_AO_PREVIOUS_ZDOTDIR'), "
                  "'phases':os.getenv('OWNER_PHASES'), 'scoped':os.getenv('OWNER_SCOPED')}))\n"
                  "sys.exit(int(os.getenv('FIXTURE_EXIT', '0')))\n")
        self.helper = self.root / "helper.py"
        self.helper.write_text("KIND='adapter'\n" + script)
        delegate = self.bin / "ao"
        delegate.write_text("#!" + sys.executable + "\nKIND='delegate'\n" + script)
        delegate.chmod(0o700)
        self.payload = '{"body":"literal $() `quotes` 中文", "reviews": []}\n'
        self.env = {"HOME": str(self.owner), "PATH": str(self.bin) + ":/usr/bin:/bin",
                    "BASH_ENV": str(self.hooks / "bash-env.sh"), "ZDOTDIR": str(self.hooks),
                    "HEXPROOF_AO_PREVIOUS_BASH_ENV": str(self.owner / "bash-init"),
                    "HEXPROOF_AO_PREVIOUS_ZDOTDIR": str(self.owner),
                    "HEXPROOF_AO_PYTHON": sys.executable,
                    "HEXPROOF_AO_REPORT_ADAPTER": str(self.helper),
                    "AO_REVIEW_WORKER_SESSION_ID": "worker-1", "AO_REVIEW_SESSION_ID": "review-1"}
        (self.owner / "bash-init").write_text("export OWNER_INIT=preserved\n")
        (self.owner / ".zshenv").write_text("export OWNER_INIT=preserved\n")
        # Login system profiles may reset PATH; the owner's login files restore it.
        login = "export OWNER_LOGIN=preserved\nexport PATH=" + str(self.bin) + ":/usr/bin:/bin\n"
        (self.owner / ".bash_profile").write_text(login)
        (self.owner / ".zprofile").write_text(login)

    def run_shell(self, shell, flag, command, **changes):
        path = shutil.which(shell)
        if not path:
            self.skipTest(shell + " is unavailable")
        env = dict(self.env, **changes)
        result = subprocess.run([path, flag, command], input=self.payload, env=env,
                                cwd=self.root, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.stderr, "", result.stderr)
        return result, json.loads(result.stdout)

    def test_native_submission_preserves_owner_startup_args_stdin_and_exit_status(self):
        for shell in ("bash", "zsh"):
            for flag in ("-c", "-lc"):
                with self.subTest(shell=shell, flag=flag):
                    result, value = self.run_shell(shell, flag, "ao review submit --session worker-1 --reviews -",
                                                   FIXTURE_EXIT="7")
                    self.assertEqual(result.returncode, 7)
                    self.assertEqual(value["kind"], "adapter")
                    self.assertEqual(value["args"], ["review", "submit", "--session", "worker-1", "--reviews", "-"])
                    self.assertEqual(value["stdin"], self.payload)
                    self.assertEqual(value["owner"], "preserved")
                    self.assertEqual(value["login"], "preserved" if flag == "-lc" else None)
                    if shell == "zsh":
                        self.assertEqual(value["zdotdir"], str(self.hooks))
                        self.assertEqual(value["previous_zdotdir"], str(self.owner))

    def test_other_ao_commands_and_nonreviewer_submissions_delegate(self):
        for shell in ("bash", "zsh"):
            for flag in ("-c", "-lc"):
                for command, changes in (("ao report --session worker-1", {}),
                                         ("ao review trigger --session worker-1", {}),
                                         ("ao review submit --reviews -", {"AO_REVIEW_WORKER_SESSION_ID": ""})):
                    with self.subTest(shell=shell, flag=flag, command=command):
                        result, value = self.run_shell(shell, flag, command, **changes)
                        self.assertEqual(result.returncode, 0)
                        self.assertEqual(value["kind"], "delegate")
                        self.assertEqual(value["stdin"], self.payload)
                        self.assertEqual(value["owner"], "preserved")

    def test_absent_previous_initialization_file_is_silent(self):
        (self.owner / "bash-init").unlink()
        (self.owner / ".zshenv").unlink()
        for shell in ("bash", "zsh"):
            with self.subTest(shell=shell):
                result, value = self.run_shell(shell, "-c", "ao review submit --reviews -")
                self.assertEqual(result.returncode, 0)
                self.assertEqual(value["kind"], "adapter")
                self.assertIsNone(value["owner"])

    def test_nested_zsh_login_shell_keeps_reporting_adapter(self):
        zsh = shutil.which("zsh")
        if not zsh:
            self.skipTest("zsh is unavailable")
        command = shlex.join([zsh, "-lc", "ao review submit --session worker-1 --reviews -"])
        result, value = self.run_shell("zsh", "-lc", command)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(value["kind"], "adapter")
        self.assertEqual(value["stdin"], self.payload)
        self.assertEqual(value["owner"], "preserved")
        self.assertEqual(value["login"], "preserved")
        self.assertEqual(value["zdotdir"], str(self.hooks))

    def test_zsh_proxies_all_owner_startup_phases_at_top_level(self):
        logout = self.root / "logout-marker"
        for phase in (".zshenv", ".zprofile", ".zshrc", ".zlogin"):
            text = ('[ "$ZDOTDIR" = ' + shlex.quote(str(self.owner)) + ' ] || exit 61\n'
                    'export OWNER_PHASES="${OWNER_PHASES-}' + phase + ' "\n'
                    "alias ao='false'\nfunction ao { return 62; }\n")
            if phase == ".zshrc":
                text += "typeset -x OWNER_SCOPED=preserved\n"
            if phase == ".zprofile":
                text += "export PATH=" + shlex.quote(str(self.bin) + ":/usr/bin:/bin") + "\n"
            (self.owner / phase).write_text(text)
        (self.owner / ".zlogout").write_text(
            'printf "%s" "$ZDOTDIR" > ' + shlex.quote(str(logout)) + "\n")
        result, value = self.run_shell("zsh", "-lic", "ao review submit --reviews -")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(value["kind"], "adapter")
        self.assertEqual(value["phases"], ".zshenv .zprofile .zshrc .zlogin ")
        self.assertEqual(value["scoped"], "preserved")
        self.assertEqual(logout.read_text(), str(self.owner))

    def test_zsh_tracks_owner_startup_directory_changes_in_later_phases(self):
        alternate = self.root / "alternate"
        alternate.mkdir()
        (self.owner / ".zshenv").write_text("export ZDOTDIR=" + shlex.quote(str(alternate)) + "\n")
        (alternate / ".zprofile").write_text(
            '[ "$ZDOTDIR" = ' + shlex.quote(str(alternate)) + ' ] || exit 63\n'
            "export OWNER_LOGIN=alternate\nexport PATH=" + shlex.quote(str(self.bin) + ":/usr/bin:/bin") + "\n")
        result, value = self.run_shell("zsh", "-lc", "ao review submit --reviews -")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(value["kind"], "adapter")
        self.assertEqual(value["login"], "alternate")
        self.assertEqual(value["previous_zdotdir"], str(alternate))
        self.assertEqual(value["zdotdir"], str(self.hooks))


if __name__ == "__main__":
    unittest.main()
