#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

from __future__ import annotations

import base64
import hashlib
import importlib.util
import json
import os
import re
import shutil
import stat
import sys
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEPLOY_DIR = REPO_ROOT / "deploy"


def operator_fixture(root):
    targets = json.loads((DEPLOY_DIR / "deployment-targets.example.json").read_text())
    targets.pop("_example")
    nodes = json.loads((DEPLOY_DIR / "home/nodes.example.json").read_text())
    nodes.pop("_example")
    nodes["home-a"]["ssh"] = "home-a"
    for name, data in (("deployment-targets", targets), ("nodes", nodes)):
        (root / (name + ".json")).write_text(json.dumps(data))
    return {"HEXPROOF_DEPLOYMENT_TARGETS_FILE": str(root / "deployment-targets.json"),
            "HEXPROOF_NODES_FILE": str(root / "nodes.json")}


class ReleaseReadinessTests(unittest.TestCase):
    def readiness_functions(self) -> list[str]:
        source = (DEPLOY_DIR / "deploy-release-server.sh").read_text()
        functions = re.findall(r"^wait_for_local_health\(\) \{\n.*?^\}", source,
                               flags=re.MULTILINE | re.DOTALL)
        self.assertEqual(len(functions), 2, "Exercise activation and rollback readiness")
        return functions

    def run_readiness(self, function: str, curl_body: str,
                      owns_binary: bool = True) -> tuple[int, int, int]:
        # Advance Bash's clock in-process so delayed and stalled startup paths
        # exercise the real polling functions without real network or sleep.
        script = "set -euo pipefail\n" + function + "\nchecks=0\n"
        script += "run_systemctl() { return 0; }\n"
        script += f"verify_active_service_binary() {{ return {0 if owns_binary else 1}; }}\n"
        script += "sleep() { SECONDS=$((SECONDS + 1)); }\n"
        script += "curl() { checks=$((checks + 1)); " + curl_body + "; }\n"
        script += 'service=hexproof.service\n'
        script += 'if wait_for_local_health; then outcome=0; else outcome=$?; fi\n'
        script += 'printf "%s %s %s\\n" "$outcome" "$SECONDS" "$checks"\n'
        result = subprocess.run(["bash", "-c", script], capture_output=True, text=True,
                                timeout=5, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        outcome, elapsed, checks = map(int, result.stdout.split())
        return outcome, elapsed, checks

    def test_accepts_delayed_forge_startup_in_activation_and_rollback(self) -> None:
        for index, function in enumerate(self.readiness_functions()):
            with self.subTest(helper=index):
                outcome, _, checks = self.run_readiness(function, '[[ "$checks" -ge 45 ]]')
                self.assertEqual(outcome, 0)
                self.assertEqual(checks, 45)

    def test_stalled_health_requests_remain_time_bounded(self) -> None:
        for index, function in enumerate(self.readiness_functions()):
            with self.subTest(helper=index):
                outcome, elapsed, checks = self.run_readiness(
                    function, 'SECONDS=$((SECONDS + 2)); return 1')
                self.assertEqual(outcome, 1)
                self.assertLessEqual(elapsed, 123)
                self.assertGreater(checks, 0)

    def test_a_different_process_cannot_satisfy_readiness(self) -> None:
        for index, function in enumerate(self.readiness_functions()):
            with self.subTest(helper=index):
                outcome, elapsed, checks = self.run_readiness(function, 'return 0', False)
                self.assertEqual(outcome, 1)
                self.assertEqual(checks, 0)
                self.assertLessEqual(elapsed, 121)


class DeploymentScriptHarness(unittest.TestCase):
    """Sandboxed release deployment plus fake network commands."""

    script_name = "deploy-release-server.sh"
    default_env = {
        "HEXPROOF_TARGETS": "cloud-b",
        "HEXPROOF_VERSION": "1.0.1",
    }

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        (self.root / "deploy").mkdir()
        shutil.copy2(DEPLOY_DIR / self.script_name,
                     self.root / "deploy" / self.script_name)
        shutil.copy2(DEPLOY_DIR / "operator_config.py", self.root / "deploy/operator_config.py")
        self.operator_env = operator_fixture(self.root)
        self.bin_dir = self.root / "test-bin"
        self.bin_dir.mkdir()
        self.log = self.root / "commands.log"
        self.ssh_count = self.root / "ssh-count"
        self.release_dir = self.root / "release-assets"
        self.release_dir.mkdir()
        self._create_release_fixture("1.0.1", "amd64")
        self._create_release_fixture("1.0.1", "arm64")
        self._write_fake(
            "ssh",
            'printf "ssh %s\\n" "$*" >> "$HEXPROOF_TEST_COMMAND_LOG"\n'
            'count=0\n'
            'if [[ -f "$HEXPROOF_TEST_SSH_COUNT" ]]; then '
            'count="$(<"$HEXPROOF_TEST_SSH_COUNT")"; fi\n'
            'count=$((count + 1))\n'
            'printf "%s\\n" "$count" > "$HEXPROOF_TEST_SSH_COUNT"\n'
            'if [[ "$*" == *"uname -m"* ]]; then\n'
            '  if [[ "$*" == *"${HEXPROOF_TEST_ARM_TARGET:-no-arm-host}"* ]]; then machine="aarch64"; '
            '  else machine="${HEXPROOF_TEST_SSH_MACHINE:-x86_64}"; fi\n'
            '  printf "%s\\n" "$machine"\n'
            'fi\n'
            'if [[ "${HEXPROOF_TEST_SSH_FAIL_AT:-}" == "$count" ]]; then '
            'exit "${HEXPROOF_TEST_SSH_FAIL_EXIT:-42}"; fi\n'
            'if [[ -n "${HEXPROOF_TEST_SSH_FAIL_MATCH:-}" && '
            '"$*" == *"$HEXPROOF_TEST_SSH_FAIL_MATCH"* ]]; then '
            'exit "${HEXPROOF_TEST_SSH_FAIL_EXIT:-42}"; fi\n'
            'if [[ "$*" == *" check-current "* ]]; then '
            'exit "${HEXPROOF_TEST_CURRENT_EXIT:-10}"; fi\n'
            'exit "${HEXPROOF_TEST_SSH_EXIT:-0}"\n',
        )
        self._write_fake(
            "curl",
            'printf "curl %s\\n" "$*" >> "$HEXPROOF_TEST_COMMAND_LOG"\n'
            'if [[ -n "${HEXPROOF_TEST_CURL_FAIL_MATCH:-}" && '
            '"$*" == *"$HEXPROOF_TEST_CURL_FAIL_MATCH"* ]]; then '
            'exit "${HEXPROOF_TEST_CURL_FAIL_EXIT:-22}"; fi\n'
            'if [[ "${HEXPROOF_TEST_CURL_EXIT:-0}" != "0" ]]; then '
            'exit "$HEXPROOF_TEST_CURL_EXIT"; fi\n'
            'output=""\nheaders=""\nurl=""\n'
            'while (($# > 0)); do\n'
            '  case "$1" in\n'
            '    -o) shift; output="$1" ;;\n'
            '    -D) shift; headers="$1" ;;\n'
            '    http://*|https://*) url="$1" ;;\n'
            '  esac\n'
            '  shift\n'
            'done\n'
            'if [[ -n "$headers" ]]; then '
            'printf "HTTP/1.1 101 Switching Protocols\\r\\n\\r\\n" > "$headers"; fi\n'
            'if [[ -n "$output" && "$output" != "/dev/null" ]]; then\n'
            '  cp "$HEXPROOF_TEST_RELEASE_DIR/${url##*/}" "$output"\n'
            'fi\n',
        )
        self._write_fake(
            "scp",
            'printf "scp %s\\n" "$*" >> "$HEXPROOF_TEST_COMMAND_LOG"\n'
            'exit "${HEXPROOF_TEST_SCP_EXIT:-0}"\n',
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _write_fake(self, name: str, body: str) -> None:
        path = self.bin_dir / name
        if name == "python3":
            body = 'if [[ "$1" == */operator_config.py ]]; then exec ' + sys.executable + ' "$@"; fi\n' + body
        path.write_text("#!/usr/bin/env bash\nset -euo pipefail\n" + body, encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def _create_release_fixture(self, version: str, architecture: str) -> None:
        package_name = f"hexproof-server-{version}-linux-{architecture}"
        package_root = self.root / "release-stage" / package_name
        binary = package_root / "bin" / "hexproof-server"
        binary.parent.mkdir(parents=True)
        binary.write_text(
            f"#!/usr/bin/env bash\nprintf '%s\\n' 'hexproof-server {version}'\n",
            encoding="utf-8",
        )
        binary.chmod(binary.stat().st_mode | stat.S_IXUSR)
        connector = binary.with_name("hexproof-home")
        connector.write_text(f"#!/usr/bin/env bash\nprintf '%s\\n' 'hexproof-home {version}'\n")
        connector.chmod(connector.stat().st_mode | stat.S_IXUSR)
        archive = self.release_dir / f"{package_name}.tar.gz"
        with tarfile.open(archive, "w:gz") as output:
            output.add(package_root, arcname=package_name)
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        with (self.release_dir / "SHA256SUMS").open("a", encoding="utf-8") as sums:
            sums.write(f"{digest}  {archive.name}\n")

    def run_script(self, **overrides: str) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment.update(
            {
                "PATH": f"{self.bin_dir}{os.pathsep}{environment['PATH']}",
                "HEXPROOF_TEST_COMMAND_LOG": str(self.log),
                "HEXPROOF_TEST_SSH_EXIT": "0",
                "HEXPROOF_TEST_CURL_EXIT": "0",
                "HEXPROOF_TEST_SSH_COUNT": str(self.ssh_count),
                "HEXPROOF_TEST_RELEASE_DIR": str(self.release_dir),
                "HEXPROOF_TEST_CURRENT_EXIT": "10",
                "HEXPROOF_TEST_SCP_EXIT": "0",
            }
        )
        environment.update(self.operator_env)
        environment.update(self.default_env)
        environment.update(overrides)
        return subprocess.run(
            [str(self.root / "deploy" / self.script_name)],
            cwd=self.root,
            env=environment,
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )

    def commands(self) -> list[str]:
        if not self.log.exists():
            return []
        return self.log.read_text(encoding="utf-8").splitlines()


class ReleaseDeploymentScriptFailureTests(DeploymentScriptHarness):
    def test_missing_or_example_inventory_stops_before_network(self) -> None:
        for filename in (self.root / "missing.json", DEPLOY_DIR / "deployment-targets.example.json"):
            with self.subTest(inventory=filename.name):
                result = self.run_script(HEXPROOF_DEPLOYMENT_TARGETS_FILE=str(filename))
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertEqual(self.commands(), [])

    def prepare_draft_github(self) -> None:
        # Exercise the real shared verifier; only GitHub/network transport is fake.
        for relative in ("deploy/deploy-home-release.py", "deploy/install-home-node.py",
                         "tools/package-home-node.py", "tools/smoke-home-node.py"):
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(REPO_ROOT / relative, destination)
        command = self.bin_dir / "gh"
        command.write_text("#!" + sys.executable + "\n" + '''import hashlib, json, os, pathlib, shutil, sys
args = sys.argv[1:]
with open(os.environ["HEXPROOF_TEST_COMMAND_LOG"], "a") as log:
    log.write("gh " + " ".join(args) + "\\n")
assets = pathlib.Path(os.environ["HEXPROOF_TEST_RELEASE_DIR"])
if args[:2] == ["release", "view"]:
    print(json.dumps({"databaseId": 12, "tagName": "v1.0.1", "isDraft": True,
        "assets": [{"name": p.name, "digest": "sha256:" + hashlib.sha256(p.read_bytes()).hexdigest()}
                   for p in assets.iterdir() if p.is_file()]}))
elif args[0] == "api":
    print("f" * 40)
elif args[:2] == ["release", "download"]:
    destination = pathlib.Path(args[args.index("--dir") + 1])
    for index, arg in enumerate(args):
        if arg == "--pattern": shutil.copy2(assets / args[index + 1], destination)
elif args[:2] == ["attestation", "verify"]:
    if os.environ.get("HEXPROOF_TEST_ATTESTATION_FAIL") == "1": sys.exit(7)
    print("[]")
else:
    sys.exit("Unexpected GitHub operation")
''')
        command.chmod(0o755)

    def test_cloud_draft_uses_authenticated_assets_and_pinned_attestation(self) -> None:
        self.prepare_draft_github()
        result = self.run_script(HEXPROOF_ALLOW_DRAFT="1", HEXPROOF_TARGETS="cloud-a cloud-b")
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.commands()
        proof = next(line for line in commands if line.startswith("gh attestation verify "))
        self.assertIn("--source-digest " + "f" * 40, proof)
        self.assertIn("--source-ref refs/tags/v1.0.1", proof)
        self.assertEqual(sum(" activate " in line for line in commands), 2)
        self.assertEqual(sum(line.startswith("gh release download ") for line in commands), 1)
        self.assertFalse(any(line.startswith("curl ") and "releases/download" in line for line in commands))
        first_write = next(index for index, line in enumerate(commands) if " prepare-stage " in line)
        self.assertLess(commands.index(proof), first_write)

    def test_cloud_draft_failed_attestation_prevents_remote_writes(self) -> None:
        self.prepare_draft_github()
        result = self.run_script(HEXPROOF_ALLOW_DRAFT="1", HEXPROOF_TEST_ATTESTATION_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(" prepare-stage " in line or " activate " in line or line.startswith("scp ")
                             for line in self.commands()))

    def test_cloud_draft_requires_explicit_version_and_boolean_opt_in(self) -> None:
        for values in ({"HEXPROOF_ALLOW_DRAFT": "1", "HEXPROOF_VERSION": ""},
                       {"HEXPROOF_ALLOW_DRAFT": "yes"}):
            result = self.run_script(**values)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertEqual(self.commands(), [])

    def test_routes_home_targets_to_the_release_backend(self) -> None:
        self._write_fake("python3", 'printf "python3 %s\\n" "$*" >> "$HEXPROOF_TEST_COMMAND_LOG"\n')
        result = self.run_script(HEXPROOF_TARGETS="home-a home-b", HEXPROOF_VERSION="2.1.0",
                                 HEXPROOF_ALLOW_DRAFT="1", HEXPROOF_VERIFY_ONLY="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.commands()
        self.assertEqual(len(commands), 1)
        self.assertIn("deploy-home-release.py --repo ClayStan404/hexproof --targets home-a home-b", commands[0])
        for argument in ("--version 2.1.0", "--allow-draft", "--verify-only"):
            self.assertIn(argument, commands[0])

    def test_rejects_mixed_groups_and_unsupported_modes_before_network(self) -> None:
        result = self.run_script(HEXPROOF_TARGETS="cloud-b home-a")
        self.assertEqual(result.returncode, 2)
        self.assertIn("separate invocations", result.stderr)
        self.assertEqual(self.commands(), [])
        result = self.run_script(HEXPROOF_TARGETS="cloud-b", HEXPROOF_VERIFY_ONLY="1")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.commands(), [])

    def test_home_room_interruption_requires_boolean_opt_in(self) -> None:
        self._write_fake("python3", 'printf "python3 %s\\n" "$*" >> "$HEXPROOF_TEST_COMMAND_LOG"\n')
        result = self.run_script(HEXPROOF_TARGETS="home-b", HEXPROOF_ALLOW_ACTIVE_ROOMS="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--allow-active-rooms", self.commands()[0])
        self.log.write_text("")
        for targets, value in (("home-b", "yes"), ("cloud-b", "1")):
            result = self.run_script(HEXPROOF_TARGETS=targets, HEXPROOF_ALLOW_ACTIVE_ROOMS=value)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertEqual(self.commands(), [])

    def test_runtime_inputs_are_forwarded_only_for_home_targets(self) -> None:
        self._write_fake("python3", 'printf "python3 %s\\n" "$*" >> "$HEXPROOF_TEST_COMMAND_LOG"\n')
        rejected = self.run_script(HEXPROOF_TARGETS="cloud-b", HEXPROOF_HOME_INPUTS="/private/inputs.json")
        self.assertEqual(rejected.returncode, 2)
        self.assertEqual(self.commands(), [])
        result = self.run_script(HEXPROOF_TARGETS="home-a", HEXPROOF_HOME_INPUTS="/private/inputs.json")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--inputs /private/inputs.json", self.commands()[0])

    def test_defaults_to_the_maintained_production_hubs(self) -> None:
        result = self.run_script(HEXPROOF_TARGETS="")
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.commands()
        activations = [line for line in commands if " activate " in line]
        self.assertEqual(len(activations), 2)
        for target, command in zip(("cloud-a", "cloud-b"), activations):
            self.assertIn(f"{target} bash -s -- activate hexproof.service", command)
        self.assertFalse(any(
            target in line for line in commands for target in ("home-b-ssh", "home-a")
        ))

    def test_rejects_unknown_duplicate_and_retired_targets(self) -> None:
        unknown = self.run_script(HEXPROOF_TARGETS="moon")
        self.assertEqual(unknown.returncode, 2)
        self.assertIn("Unknown deployment target: moon", unknown.stderr)
        self.assertEqual(self.commands(), [])

        duplicate = self.run_script(HEXPROOF_TARGETS="cloud-b cloud-b")
        self.assertEqual(duplicate.returncode, 2)
        self.assertIn("Duplicate deployment target: cloud-b", duplicate.stderr)
        self.assertEqual(self.commands(), [])

        retired = self.run_script(HEXPROOF_TARGETS="retired-cloud")
        self.assertEqual(retired.returncode, 2)
        self.assertIn("Unknown deployment target: retired-cloud", retired.stderr)
        self.assertEqual(self.commands(), [])

    def test_rejects_invalid_version_before_remote_access(self) -> None:
        result = self.run_script(HEXPROOF_VERSION="1.0")
        self.assertEqual(result.returncode, 2)
        self.assertIn("Release version must use MAJOR.MINOR.PATCH", result.stderr)
        self.assertEqual(self.commands(), [])

    def test_rejects_invalid_backup_retention_before_remote_access(self) -> None:
        result = self.run_script(HEXPROOF_BACKUP_KEEP="five")
        self.assertEqual(result.returncode, 2)
        self.assertIn("HEXPROOF_BACKUP_KEEP must be", result.stderr)
        self.assertEqual(self.commands(), [])

    def test_rejects_incomplete_version_with_leading_v(self) -> None:
        result = self.run_script(HEXPROOF_VERSION="v1.0")
        self.assertEqual(result.returncode, 2)
        self.assertIn("Release version must use MAJOR.MINOR.PATCH", result.stderr)
        self.assertEqual(self.commands(), [])

    def test_accepts_complete_version_with_leading_v(self) -> None:
        result = self.run_script(
            HEXPROOF_VERSION="v1.0.1",
            HEXPROOF_TEST_SSH_MACHINE="x86_64",
            HEXPROOF_TEST_SSH_FAIL_AT="2",
        )
        self.assertEqual(result.returncode, 42)
        self.assertNotIn("Release version must use", result.stderr)
        self.assertEqual(
            len([line for line in self.commands() if line.startswith("ssh ")]), 2
        )

    def test_unsupported_remote_architecture_stops_before_download(self) -> None:
        result = self.run_script(HEXPROOF_TEST_SSH_MACHINE="riscv64")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Unsupported architecture", result.stderr)
        commands = self.commands()
        self.assertEqual(len([line for line in commands if line.startswith("ssh ")]), 1)
        self.assertFalse(any(line.startswith("curl ") for line in commands))
        self.assertNotIn("Downloading and verifying", result.stdout)

    def test_preflight_failure_stops_before_download_and_public_checks(self) -> None:
        result = self.run_script(
            HEXPROOF_TEST_SSH_MACHINE="x86_64",
            HEXPROOF_TEST_SSH_FAIL_AT="2",
        )
        self.assertEqual(result.returncode, 42)
        commands = self.commands()
        self.assertEqual(len([line for line in commands if line.startswith("ssh ")]), 2)
        self.assertFalse(any(line.startswith("curl ") for line in commands))
        self.assertNotIn("Downloading and verifying", result.stdout)
        self.assertNotIn("public health endpoint", result.stdout)

    def test_downloads_verifies_and_deploys_release(self) -> None:
        result = self.run_script(HEXPROOF_TEST_SSH_MACHINE="x86_64")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Deployment complete: release v1.0.1 is current", result.stdout)
        commands = self.commands()
        self.assertEqual(len([line for line in commands if line.startswith("ssh ")]), 7)
        self.assertEqual(len([line for line in commands if line.startswith("scp ")]), 1)
        self.assertEqual(len([line for line in commands if line.startswith("curl ")]), 4)

    def test_skips_upload_and_restart_when_release_is_already_installed(self) -> None:
        result = self.run_script(
            HEXPROOF_TEST_SSH_MACHINE="x86_64",
            HEXPROOF_TEST_CURRENT_EXIT="0",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Already current on cloud-b", result.stdout)
        self.assertIn("0 activated, 1 unchanged", result.stdout)
        commands = self.commands()
        self.assertFalse(any(line.startswith("scp ") for line in commands))
        self.assertFalse(any(" activate " in line for line in commands))

    def test_two_targets_download_two_architectures_once(self) -> None:
        result = self.run_script(HEXPROOF_TARGETS="cloud-a cloud-b",
                                 HEXPROOF_TEST_ARM_TARGET=" cloud-b uname -m")
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.commands()
        scp_commands = [line for line in commands if line.startswith("scp ")]
        self.assertEqual(len(scp_commands), 2)
        amd64_downloads = [
            line
            for line in commands
            if "hexproof-server-1.0.1-linux-amd64.tar.gz" in line
            and line.startswith("curl ")
        ]
        arm64_downloads = [
            line
            for line in commands
            if "hexproof-server-1.0.1-linux-arm64.tar.gz" in line
            and line.startswith("curl ")
        ]
        self.assertEqual(len(amd64_downloads), 1)
        self.assertEqual(len(arm64_downloads), 1)
        last_stage = max(
            index for index, line in enumerate(commands) if " verify-stage " in line
        )
        first_activation = min(
            index for index, line in enumerate(commands) if " activate " in line
        )
        self.assertLess(last_stage, first_activation)

    def test_renewed_hub_target_deploys_like_the_other_hubs(self) -> None:
        result = self.run_script(HEXPROOF_TARGETS="cloud-a")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("1 activated, 0 unchanged", result.stdout)
        commands = self.commands()
        self.assertTrue(
            any(" cloud-a bash -s -- " in line for line in commands),
            "the cloud-a target must use its own SSH alias",
        )
        self.assertTrue(any("cloud-a bash -s -- verify-stage" in line for line in commands))
        self.assertTrue(any("cloud-a bash -s -- activate" in line for line in commands))
        self.assertFalse(any("cloud-a bash -s -- rollback" in line for line in commands))

    def test_later_activation_failure_rolls_back_earlier_target(self) -> None:
        result = self.run_script(
            HEXPROOF_TARGETS="cloud-a cloud-b",
            HEXPROOF_TEST_SSH_FAIL_MATCH="cloud-b bash -s -- activate",
        )
        self.assertNotEqual(result.returncode, 0)
        commands = self.commands()
        self.assertTrue(any("cloud-a bash -s -- rollback" in line for line in commands))
        self.assertTrue(
            any("cleanup-staging" in line for line in commands),
            "failed deployment should clean remote staging directories",
        )

    def test_scp_failure_cleans_remote_staging(self) -> None:
        result = self.run_script(HEXPROOF_TEST_SCP_EXIT="44")
        self.assertEqual(result.returncode, 44)
        self.assertTrue(
            any("cleanup-staging" in line for line in self.commands())
        )

    def test_interrupted_stage_creation_attempts_remote_cleanup(self) -> None:
        result = self.run_script(
            HEXPROOF_TEST_SSH_FAIL_MATCH="prepare-stage",
            HEXPROOF_TEST_SSH_FAIL_EXIT="45",
        )
        self.assertEqual(result.returncode, 45)
        self.assertTrue(
            any("cleanup-staging" in line for line in self.commands())
        )

    def test_public_failure_rolls_back_activated_target(self) -> None:
        result = self.run_script(
            HEXPROOF_TEST_CURL_FAIL_MATCH="https://hub-b.example.com/healthz"
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(
            any("cloud-b bash -s -- rollback" in line for line in self.commands())
        )

    def test_zero_backup_retention_disables_pruning(self) -> None:
        result = self.run_script(HEXPROOF_BACKUP_KEEP="0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any("prune-backups" in line for line in self.commands()))

    def test_checksum_mismatch_stops_before_copy(self) -> None:
        (self.release_dir / "SHA256SUMS").write_text(
            f"{'0' * 64}  hexproof-server-1.0.1-linux-amd64.tar.gz\n",
            encoding="utf-8",
        )
        result = self.run_script(HEXPROOF_TEST_SSH_MACHINE="x86_64")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(
            any(line.startswith("scp ") for line in self.commands())
        )


class TestServerDeploymentScriptTests(DeploymentScriptHarness):
    script_name = "deploy-test-server.sh"
    default_env = {
        "HEXPROOF_TEST_TARGET": "cloud-b",
        "HEXPROOF_TEST_VERSION": "1.0.1",
    }

    def setUp(self) -> None:
        super().setUp()
        shutil.copy2(
            DEPLOY_DIR / "hexproof-test.service",
            self.root / "deploy" / "hexproof-test.service",
        )
        shutil.copy2(
            DEPLOY_DIR / "hexproof-test-nginx.inc",
            self.root / "deploy" / "hexproof-test-nginx.inc",
        )
        self.test_binary = self.root / "hexproof-server-test"
        self.test_binary.write_text(
            "#!/usr/bin/env bash\n"
            "if [[ \"${1:-}\" == \"-version\" ]]; then\n"
            "  printf '%s\\n' \"hexproof-server "
            "${HEXPROOF_TEST_FAKE_BINARY_VERSION:-1.0.1}\"\n"
            "fi\n",
            encoding="utf-8",
        )
        self.test_binary.chmod(self.test_binary.stat().st_mode | stat.S_IXUSR)
        self.default_env["HEXPROOF_TEST_BINARY"] = str(self.test_binary)
        self._write_fake(
            "ssh",
            'printf "ssh %s\\n" "$*" >> "$HEXPROOF_TEST_COMMAND_LOG"\n'
            'count=0\n'
            'if [[ -f "$HEXPROOF_TEST_SSH_COUNT" ]]; then '
            'count="$(<"$HEXPROOF_TEST_SSH_COUNT")"; fi\n'
            'count=$((count + 1))\n'
            'printf "%s\\n" "$count" > "$HEXPROOF_TEST_SSH_COUNT"\n'
            'if [[ "${HEXPROOF_TEST_SSH_FAIL_AT:-}" == "$count" ]]; then '
            'exit "${HEXPROOF_TEST_SSH_FAIL_EXIT:-42}"; fi\n'
            'if [[ -n "${HEXPROOF_TEST_SSH_FAIL_MATCH:-}" && '
            '"$*" == *"$HEXPROOF_TEST_SSH_FAIL_MATCH"* ]]; then '
            'exit "${HEXPROOF_TEST_SSH_FAIL_EXIT:-42}"; fi\n'
            'if [[ "$*" == *" inspect-host"* ]]; then\n'
            '  printf "%s %s %s\\n" '
            '"${HEXPROOF_TEST_REMOTE_SYSTEM:-Linux}" '
            '"${HEXPROOF_TEST_REMOTE_OS:-home-a}" '
            '"${HEXPROOF_TEST_SSH_MACHINE:-x86_64}"\n'
            'fi\n'
            'if [[ "$*" == *" check-current "* ]]; then '
            'exit "${HEXPROOF_TEST_CURRENT_EXIT:-10}"; fi\n'
            'exit "${HEXPROOF_TEST_SSH_EXIT:-0}"\n',
        )

    def test_deploys_to_isolated_test_service(self) -> None:
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Isolated test deployment complete", result.stdout)
        self.assertIn("127.0.0.1:57321", result.stdout)
        self.assertIn("wss://hub-b.example.com/test/ws", result.stdout)
        commands = self.commands()
        self.assertEqual(len([line for line in commands if line.startswith("ssh ")]), 7)
        self.assertEqual(len([line for line in commands if line.startswith("scp ")]), 1)
        self.assertTrue(any(" prepare-stage " in line for line in commands))
        self.assertTrue(any(" verify-stage " in line for line in commands))
        self.assertTrue(any(" activate " in line for line in commands))
        self.assertTrue(any(" configure-proxy " in line for line in commands))
        self.assertFalse(
            any(
                "hexproof.service" in line
                for line in commands
                if " activate " in line
            )
        )

    def test_skips_binary_and_restart_when_test_service_is_current(self) -> None:
        result = self.run_script(HEXPROOF_TEST_CURRENT_EXIT="0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("already current", result.stdout)
        commands = self.commands()
        self.assertEqual(len([line for line in commands if line.startswith("ssh ")]), 2)
        self.assertFalse(any(line.startswith("scp ") for line in commands))
        self.assertFalse(any(" activate " in line for line in commands))

    def test_defaults_to_server_two_and_its_public_route(self) -> None:
        result = self.run_script(HEXPROOF_TEST_TARGET="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("wss://hub-b.example.com/test/ws", result.stdout)
        commands = self.commands()
        for operation in ("inspect-host", "check-current", "prepare-stage",
                          "verify-stage", "activate", "configure-proxy"):
            self.assertTrue(any(f"cloud-b bash -s -- {operation}" in line
                                for line in commands), operation)
        self.assertTrue(any("https://hub-b.example.com/test/healthz" in line
                            for line in commands))
        self.assertFalse(any("43.137.36.143" in line for line in commands))

    def test_rejects_unknown_test_host_before_remote_access(self) -> None:
        result = self.run_script(HEXPROOF_TEST_TARGET="retired-cloud")
        self.assertEqual(result.returncode, 2)
        self.assertIn("Unknown deployment target", result.stderr)
        self.assertEqual(self.commands(), [])

    def test_rejects_unconfigured_hosts_before_remote_access(self) -> None:
        result = self.run_script(HEXPROOF_TEST_TARGET="cloud-a")
        self.assertEqual(result.returncode, 2)
        self.assertIn("not enabled for test deployment", result.stderr)
        self.assertEqual(self.commands(), [])

    def test_rejects_unsafe_target_before_remote_access(self) -> None:
        result = self.run_script(HEXPROOF_TEST_TARGET="-oProxyCommand=bad")
        self.assertEqual(result.returncode, 2)
        self.assertIn("plain existing SSH aliases", result.stderr)
        self.assertEqual(self.commands(), [])

    def test_rejects_unsupported_remote_host_before_upload(self) -> None:
        result = self.run_script(HEXPROOF_TEST_REMOTE_SYSTEM="Darwin")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Unsupported remote operating system", result.stderr)
        commands = self.commands()
        self.assertEqual(len([line for line in commands if line.startswith("ssh ")]), 1)
        self.assertFalse(any(line.startswith("scp ") for line in commands))

    def test_rejects_mismatched_binary_before_remote_mutation(self) -> None:
        result = self.run_script(HEXPROOF_TEST_FAKE_BINARY_VERSION="9.9.9")
        self.assertEqual(result.returncode, 1)
        self.assertIn("expected hexproof-server 1.0.1", result.stderr)
        commands = self.commands()
        self.assertEqual(len([line for line in commands if line.startswith("ssh ")]), 1)
        self.assertFalse(any(" prepare-stage " in line for line in commands))
        self.assertFalse(any(line.startswith("scp ") for line in commands))

    def test_activation_failure_cleans_staging(self) -> None:
        result = self.run_script(HEXPROOF_TEST_SSH_FAIL_MATCH=" activate ")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Production service was not modified", result.stderr)
        self.assertTrue(any("cleanup-staging" in line for line in self.commands()))

    def test_proxy_failure_rolls_back_activated_test_service(self) -> None:
        result = self.run_script(HEXPROOF_TEST_SSH_FAIL_MATCH=" configure-proxy ")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(
            any(" rollback-deployment " in line for line in self.commands())
        )

    def test_public_failure_rolls_back_service_and_proxy(self) -> None:
        result = self.run_script(
            HEXPROOF_TEST_CURL_FAIL_MATCH="https://hub-b.example.com/test/healthz"
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("restoring the previous deployment", result.stderr)
        self.assertTrue(
            any(" rollback-deployment " in line for line in self.commands())
        )

    def test_service_is_private_resource_limited_and_forge_disabled(self) -> None:
        unit = (DEPLOY_DIR / "hexproof-test.service").read_text(encoding="utf-8")
        self.assertIn("-bind 127.0.0.1", unit)
        self.assertIn("-port 57321", unit)
        self.assertIn("/var/lib/hexproof-test/retained", unit)
        self.assertIn('Environment="HEXPROOF_FORGE_HARNESS="', unit)
        self.assertIn('Environment="HEXPROOF_FORGE_HOME="', unit)
        self.assertNotIn("-forge-harness", unit)
        self.assertNotIn("-forge-home", unit)
        self.assertIn("MemoryMax=384M", unit)
        self.assertIn("CPUQuota=100%", unit)
        self.assertIn("Nice=5", unit)
        self.assertNotIn("/var/lib/hexproof/retained", unit)
        nginx = (DEPLOY_DIR / "hexproof-test-nginx.inc").read_text(encoding="utf-8")
        self.assertIn("location = /test/healthz", nginx)
        self.assertIn("location = /test/ws", nginx)
        self.assertIn("127.0.0.1:57321/healthz", nginx)
        self.assertIn("127.0.0.1:57321/ws", nginx)

    def test_test_proxy_does_not_publish_source_downloads(self) -> None:
        nginx = (DEPLOY_DIR / "hexproof-test-nginx.inc").read_text(encoding="utf-8")
        self.assertNotIn("/test/forge-source/", nginx)
        self.assertNotIn("/var/www/hexproof-test-forge-sources", nginx)
        self.assertNotIn("alias ", nginx)


class ForgeDeploymentScriptTests(DeploymentScriptHarness):
    script_name = "deploy-forge-runtime.sh"
    default_env = {
        "HEXPROOF_TARGETS": "cloud-b",
        "HEXPROOF_FORGE_SCOPE": "production",
        "HEXPROOF_FORGE_BUILD_IF_MISSING": "0",
    }

    def setUp(self) -> None:
        super().setUp()
        fixture_spec = importlib.util.spec_from_file_location(
            "forge_deploy_fixtures", REPO_ROOT / "tools/tests/test_forge_source_package.py"
        )
        fixtures = importlib.util.module_from_spec(fixture_spec)
        fixture_spec.loader.exec_module(fixtures)
        fixture_dir = self.root / "forge-stage"
        self.forge_archive, self.source_archive = fixtures.create_release_fixture(fixture_dir)
        self.package_root = fixture_dir / "hexproof-forge-runtime"
        shutil.copytree(
            fixture_dir / "hexproof-forge-source" / "hexproof-build",
            self.root / "third_party" / "forge-runtime",
        )

    def run_script(self, **overrides: str) -> subprocess.CompletedProcess[str]:
        options = {"HEXPROOF_FORGE_ARCHIVE": str(self.forge_archive)}
        options.update(overrides)
        return super().run_script(**options)

    def test_stages_and_activates_pinned_runtime(self) -> None:
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Forge runtime deployment complete", result.stdout)
        commands = self.commands()
        self.assertEqual(len([line for line in commands if line.startswith("ssh ")]), 6)
        self.assertEqual(len([line for line in commands if line.startswith("scp ")]), 1)
        self.assertTrue(any(" preflight " in line for line in commands))
        self.assertTrue(any(" verify-stage " in line for line in commands))
        self.assertTrue(any(" activate " in line for line in commands))

    def test_defaults_to_the_maintained_forge_hub(self) -> None:
        result = self.run_script(HEXPROOF_TARGETS="")
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.commands()
        activations = [line for line in commands if " activate " in line]
        self.assertEqual(len(activations), 1)
        for target, command in zip(("cloud-b",), activations):
            self.assertIn(f"{target} bash -s -- activate hexproof.service", command)
            self.assertIn("/var/lib/hexproof/forge-runtime", command)
            self.assertIn("57320 production", command)
        self.assertFalse(any(
            target in line for line in commands for target in ("home-b-ssh", "home-a")
        ))
        for host in ("hub-b.example.com",):
            self.assertTrue(any(
                "curl " in line and f"https://{host}/healthz" in line
                for line in commands
            ))
        for target, java in (
            ("cloud-b", "/usr/lib/jvm/java-21-openjdk-amd64/bin/java"),
        ):
            for operation in ("preflight", "check-current", "activate"):
                command = next(
                    line for line in commands
                    if f"{target} bash -s -- {operation} " in line
                )
                self.assertIn(f" {java} ", command)

    def test_rejects_manual_only_and_retired_nodes_before_remote_access(self) -> None:
        for target in ("cloud-a", "retired-cloud", "home-b-ssh", "home-a"):
            with self.subTest(target=target):
                result = self.run_script(HEXPROOF_TARGETS=target)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(self.commands(), [])

    def test_explicit_java_override_applies_to_the_production_hub(self) -> None:
        result = self.run_script(
            HEXPROOF_TARGETS="", HEXPROOF_FORGE_JAVA="/opt/custom-jre/bin/java"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.commands()
        for target in ("cloud-b",):
            for operation in ("preflight", "check-current", "activate"):
                command = next(
                    line for line in commands
                    if f"{target} bash -s -- {operation} " in line
                )
                self.assertIn(" /opt/custom-jre/bin/java ", command)

    def test_test_scope_defaults_to_only_the_cloud_b_test_service(self) -> None:
        result = self.run_script(
            HEXPROOF_FORGE_SCOPE="test", HEXPROOF_TARGETS=""
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.commands()
        for operation in ("preflight", "check-current", "activate"):
            command = next(line for line in commands if f" {operation} " in line)
            self.assertIn(f"cloud-b bash -s -- {operation} hexproof-test.service", command)
            self.assertIn("/var/lib/hexproof-test/forge-runtime", command)
            self.assertNotIn("hexproof.service", command)
            if operation != "preflight":
                self.assertIn("57321 test", command)
        self.assertTrue(any(
            "curl " in line and "https://hub-b.example.com/test/healthz" in line
            for line in commands
        ))
        self.assertFalse(any("57320" in line for line in commands))

    def test_rejects_invalid_scope_and_test_targets_before_remote_access(self) -> None:
        for scope, targets in (
            ("staging", "cloud-b"),
            ("test", "home-a"),
            ("test", "cloud-b home-a"),
            ("test", "cloud-b cloud-b"),
            ("test", "cloud-b retired-cloud"),
            ("test", "retired-cloud"),
        ):
            with self.subTest(scope=scope, targets=targets):
                result = self.run_script(
                    HEXPROOF_FORGE_SCOPE=scope, HEXPROOF_TARGETS=targets
                )
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertEqual(self.commands(), [])

    def test_default_production_scope_keeps_cloud_b_production_paths(self) -> None:
        result = self.run_script(HEXPROOF_TARGETS="cloud-b", HEXPROOF_FORGE_SCOPE="")
        self.assertEqual(result.returncode, 0, result.stderr)
        activation = next(line for line in self.commands() if " activate " in line)
        self.assertIn("activate hexproof.service", activation)
        self.assertIn("/var/lib/hexproof/forge-runtime", activation)
        self.assertIn("57320 production", activation)
        self.assertNotIn("hexproof-test", activation)

    def test_test_public_failure_rolls_back_only_test_service_and_port(self) -> None:
        result = self.run_script(
            HEXPROOF_FORGE_SCOPE="test",
            HEXPROOF_TARGETS="cloud-b",
            HEXPROOF_TEST_CURL_FAIL_MATCH="https://hub-b.example.com/test/healthz",
        )
        self.assertNotEqual(result.returncode, 0)
        rollback = next(line for line in self.commands() if " rollback " in line)
        self.assertIn("cloud-b bash -s -- rollback hexproof-test.service", rollback)
        self.assertIn("/var/lib/hexproof-test/forge-runtime", rollback)
        self.assertTrue(rollback.endswith(" 57321"))
        self.assertNotIn("hexproof.service", rollback)

    def _prepare_remote_runtime(self) -> None:
        self.remote_root = self.root / "remote-test"
        self.remote_root.mkdir()
        self.remote_runtime = self.remote_root / "forge-runtime"
        self.remote_release = self.remote_runtime / "releases" / "new-runtime"
        self.remote_dropin = self.remote_root / "service.d" / "forge-runtime.conf"
        self.remote_stage = self.remote_root / "staging"
        self.remote_stage.mkdir()
        self.remote_archive = self.remote_stage / "runtime.tar.gz"
        shutil.copy2(self.forge_archive, self.remote_archive)
        self.remote_backup = self.remote_root / "backup"
        self._write_fake(
            "systemctl",
            'printf "systemctl %s\\n" "$*" >> "$HEXPROOF_TEST_COMMAND_LOG"\n'
            'case "$*" in\n'
            '  *"-p Environment "*)\n'
            '    if [[ -n "${HEXPROOF_TEST_ENVIRONMENT:-}" ]]; then\n'
            '      printf "%s\\n" "$HEXPROOF_TEST_ENVIRONMENT"\n'
            '    else\n'
            '      sed -n \'s/^Environment=//p\' '
            '"$HEXPROOF_TEST_SYSTEMD_DROPIN" | tr "\\n" " "\n'
            '    fi ;;\n'
            '  *"-p MemoryMax "*) '
            'printf "%s\\n" "${HEXPROOF_TEST_MEMORY_MAX:-1073741824}" ;;\n'
            '  *"-p TasksMax "*) '
            'printf "%s\\n" "${HEXPROOF_TEST_TASKS_MAX:-192}" ;;\n'
            '  "restart "*)\n'
            '    if [[ -n "${HEXPROOF_TEST_RESTART_FAILURE:-}" && '
            '! -e "$HEXPROOF_TEST_RESTART_FAILURE" ]]; then\n'
            '      touch "$HEXPROOF_TEST_RESTART_FAILURE"; exit 43\n'
            '    fi ;;\n'
            'esac\n',
        )

    def _run_remote_runtime(
        self, block: str, *, scope: str = "test", archive_sha256: str | None = None,
        **overrides: str,
    ) -> subprocess.CompletedProcess[str]:
        source = (self.root / "deploy" / self.script_name).read_text(encoding="utf-8")
        script = source.split(f"<<'{block}'\n", 1)[1].split(f"\n{block}\n", 1)[0]
        if block == "REMOTE_ACTIVATE":
            arguments = [
                "activate", "hexproof-test.service", "0", str(self.remote_runtime),
                str(self.remote_release), str(self.remote_dropin), "java",
                str(self.remote_stage), str(self.remote_archive), str(self.remote_backup),
                archive_sha256 or hashlib.sha256(self.remote_archive.read_bytes()).hexdigest(),
                "57321", scope,
            ]
        else:
            self.assertEqual(block, "REMOTE_CURRENT")
            arguments = [
                "check-current", "hexproof-test.service", str(self.remote_runtime),
                str(self.remote_release), str(self.remote_dropin), "java", "57321", scope,
            ]
        environment = os.environ.copy()
        environment.update({
            "PATH": f"{self.bin_dir}{os.pathsep}{environment['PATH']}",
            "HEXPROOF_TEST_COMMAND_LOG": str(self.log),
            "HEXPROOF_TEST_SYSTEMD_DROPIN": str(self.remote_dropin),
        })
        environment.update(overrides)
        return subprocess.run(
            ["bash", "-s", "--", *arguments], input=script, env=environment,
            capture_output=True, text=True, check=False, timeout=10,
        )

    def test_remote_preflight_requires_java_21_before_staging(self) -> None:
        self._prepare_remote_runtime()
        (self.remote_root / "backups").mkdir()
        binary = self.remote_root / "hexproof-server"
        binary.write_text(
            "#!/usr/bin/env bash\nprintf '%s\\n' HEXPROOF_FORGE_HARNESS\n",
            encoding="utf-8",
        )
        binary.chmod(binary.stat().st_mode | stat.S_IXUSR)
        source = (self.root / "deploy" / self.script_name).read_text(encoding="utf-8")
        script = source.split("<<'REMOTE_PREFLIGHT'\n", 1)[1].split("\nREMOTE_PREFLIGHT\n", 1)[0]
        arguments = [
            "preflight", "hexproof-test.service", str(binary), str(self.remote_root),
            "0", "java", str(self.remote_stage / "new-stage"),
            str(self.remote_root / "backups" / "new-backup"),
            str(self.remote_runtime), str(self.remote_dropin),
        ]
        for version in ("17", "18", "20", "21", "22", "unknown"):
            with self.subTest(version=version):
                self._write_fake("java", f"printf '%s\\n' 'openjdk version \"{version}.0.1\"' >&2\n")
                environment = os.environ.copy()
                environment.update({
                    "PATH": f"{self.bin_dir}{os.pathsep}{environment['PATH']}",
                    "HEXPROOF_TEST_COMMAND_LOG": str(self.log),
                })
                result = subprocess.run(
                    ["bash", "-s", "--", *arguments], input=script, env=environment,
                    capture_output=True, text=True, check=False, timeout=10,
                )
                if version == "21":
                    self.assertEqual(result.returncode, 0, result.stderr)
                else:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("Forge requires Java 21", result.stderr)
                self.assertFalse((self.remote_stage / "new-stage").exists())
                self.assertFalse(self.remote_dropin.exists())

    def test_remote_activation_rechecks_uploaded_archive_before_mutation(self) -> None:
        self._prepare_remote_runtime()
        original_hash = hashlib.sha256(self.remote_archive.read_bytes()).hexdigest()
        with self.remote_archive.open("ab") as archive:
            archive.write(b"changed after staging")
        result = self._run_remote_runtime("REMOTE_ACTIVATE", archive_sha256=original_hash)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.remote_release.exists())
        self.assertFalse(self.remote_backup.exists())
        self.assertFalse(self.remote_dropin.exists())
        self.assertFalse(any("systemctl restart " in line for line in self.commands()))

    def test_remote_test_activation_sets_and_checks_bounded_resources(self) -> None:
        self._prepare_remote_runtime()
        result = self._run_remote_runtime("REMOTE_ACTIVATE")
        self.assertEqual(result.returncode, 0, result.stderr)
        dropin = self.remote_dropin.read_text(encoding="utf-8")
        self.assertIn('Environment="GOMAXPROCS=1"', dropin)
        self.assertIn("-Xms64m -Xmx512m -XX:ActiveProcessorCount=1", dropin)
        self.assertIn("-XX:+ExitOnOutOfMemoryError", dropin)
        self.assertIn("-Djava.awt.headless=true -Duser.home=/var/lib/hexproof-test", dropin)
        self.assertIn("MemoryMax=1G", dropin)
        self.assertIn("TasksMax=192", dropin)
        self.assertNotIn("CPUQuota=", dropin)
        self.assertNotIn("Nice=", dropin)
        result = self._run_remote_runtime("REMOTE_CURRENT")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any("http://127.0.0.1:57321/healthz" in line for line in self.commands()))
        for override in (
            {"HEXPROOF_TEST_MEMORY_MAX": "536870912"},
            {"HEXPROOF_TEST_TASKS_MAX": "128"},
        ):
            with self.subTest(override=override):
                result = self._run_remote_runtime("REMOTE_CURRENT", **override)
                self.assertEqual(result.returncode, 10, result.stderr)
        for old, new in (("-Xmx512m", "-Xmx1g"), ("GOMAXPROCS=1", "GOMAXPROCS=2")):
            with self.subTest(setting=old):
                self.remote_dropin.write_text(dropin.replace(old, new), encoding="utf-8")
                result = self._run_remote_runtime("REMOTE_CURRENT")
                self.assertEqual(result.returncode, 10, result.stderr)
        self.remote_dropin.write_text(dropin, encoding="utf-8")
        environment = " ".join(
            line.removeprefix("Environment=") for line in dropin.splitlines()
            if line.startswith("Environment=")
        )
        result = self._run_remote_runtime(
            "REMOTE_CURRENT", HEXPROOF_TEST_ENVIRONMENT=environment.replace(
                '-Duser.home=/var/lib/hexproof-test"',
                '-Duser.home=/var/lib/hexproof-test -Xmx2g"',
            ),
        )
        self.assertEqual(result.returncode, 10, result.stderr)

    def test_remote_activation_restores_previous_runtime_and_complete_dropin(self) -> None:
        self._prepare_remote_runtime()
        previous = self.remote_runtime / "releases" / "previous-runtime"
        previous.mkdir(parents=True)
        (self.remote_runtime / "current").symlink_to("releases/previous-runtime")
        self.remote_dropin.parent.mkdir()
        old_dropin = '[Service]\nEnvironment="JAVA_TOOL_OPTIONS=-Xmx256m"\nMemoryMax=768M\n'
        self.remote_dropin.write_text(old_dropin, encoding="utf-8")
        result = self._run_remote_runtime(
            "REMOTE_ACTIVATE",
            HEXPROOF_TEST_RESTART_FAILURE=str(self.remote_root / "failed-once"),
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.remote_runtime / "current").resolve(), previous)
        self.assertEqual(self.remote_dropin.read_text(encoding="utf-8"), old_dropin)
        restarts = [line for line in self.commands() if line.startswith("systemctl restart ")]
        self.assertEqual(restarts, ["systemctl restart hexproof-test.service"] * 2)

    def test_remote_first_activation_failure_restores_forge_disabled_state(self) -> None:
        self._prepare_remote_runtime()
        result = self._run_remote_runtime(
            "REMOTE_ACTIVATE",
            HEXPROOF_TEST_RESTART_FAILURE=str(self.remote_root / "failed-once"),
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.remote_runtime / "current").is_symlink())
        self.assertFalse(self.remote_dropin.exists())
        self.assertTrue(self.remote_release.is_dir())

    def test_remote_production_activation_has_no_test_resource_overrides(self) -> None:
        self._prepare_remote_runtime()
        result = self._run_remote_runtime("REMOTE_ACTIVATE", scope="production")
        self.assertEqual(result.returncode, 0, result.stderr)
        dropin = self.remote_dropin.read_text(encoding="utf-8")
        for setting in ("JAVA_TOOL_OPTIONS", "GOMAXPROCS", "MemoryMax", "TasksMax"):
            self.assertNotIn(setting, dropin)

    def test_stages_every_target_before_activation(self) -> None:
        result = self.run_script(HEXPROOF_TARGETS="cloud-b")
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.commands()
        last_stage = max(
            index for index, line in enumerate(commands) if " verify-stage " in line
        )
        first_activation = min(
            index for index, line in enumerate(commands) if " activate " in line
        )
        self.assertLess(last_stage, first_activation)
        self.assertEqual(
            len([line for line in commands if line.startswith("scp ")]), 1
        )

    def test_skips_runtime_that_is_already_active(self) -> None:
        result = self.run_script(HEXPROOF_TEST_CURRENT_EXIT="0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("already current on cloud-b", result.stdout)
        self.assertIn("0 activated, 1 unchanged", result.stdout)
        self.assertFalse(
            any(line.startswith("scp ") for line in self.commands())
        )

    def test_activation_failure_cleans_staged_runtime(self) -> None:
        result = self.run_script(
            HEXPROOF_TARGETS="cloud-b",
            HEXPROOF_TEST_SSH_FAIL_MATCH="cloud-b bash -s -- activate",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(any("cleanup-staging" in line for line in self.commands()))

    def test_rejects_unpinned_or_incomplete_archive_before_remote_access(self) -> None:
        incomplete = self.root / "incomplete" / self.forge_archive.name
        incomplete_root = self.root / "incomplete" / "hexproof-forge-runtime"
        incomplete_root.mkdir(parents=True)
        (incomplete_root / "forge-harness.jar").write_bytes(b"incomplete")
        with tarfile.open(incomplete, "w:gz") as output:
            output.add(incomplete_root, arcname="hexproof-forge-runtime")

        result = self.run_script(
            HEXPROOF_FORGE_ARCHIVE=str(incomplete),
            HEXPROOF_FORGE_SOURCE_ARCHIVE=str(self.source_archive),
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.commands(), [])

    def test_rejects_unsafe_java_command_before_remote_access(self) -> None:
        result = self.run_script(HEXPROOF_FORGE_JAVA="java --show-version")
        self.assertEqual(result.returncode, 2)
        self.assertIn("must be one command name", result.stderr)
        self.assertEqual(self.commands(), [])

    def test_rejects_modified_runtime_before_remote_access(self) -> None:
        (self.package_root / "forge-harness.jar").write_bytes(b"changed adapter")
        with tarfile.open(self.forge_archive, "w:gz") as output:
            output.add(self.package_root, arcname="hexproof-forge-runtime")
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.commands(), [])

    def test_rejects_missing_matching_source_before_remote_access(self) -> None:
        result = self.run_script(
            HEXPROOF_FORGE_SOURCE_ARCHIVE=str(self.root / "missing-source.tar.gz")
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("matching source archives are required", result.stderr)
        self.assertEqual(self.commands(), [])

    def test_rejects_modified_matching_source_before_remote_access(self) -> None:
        with self.source_archive.open("ab") as source:
            source.write(b"source archive changed after packaging")
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.commands(), [])

    def test_rejects_stale_adapter_revision_before_remote_access(self) -> None:
        pin = self.root / "third_party" / "forge-runtime" / "native-host" / "upstream.json"
        upstream = json.loads(pin.read_text(encoding="utf-8"))
        upstream["adapterRevision"] += 1
        pin.write_text(json.dumps(upstream), encoding="utf-8")
        result = self.run_script(HEXPROOF_FORGE_SOURCE_ARCHIVE=str(self.source_archive))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.commands(), [])

    def test_accepts_explicit_matching_source_location(self) -> None:
        custom_source = self.root / "external-sources" / self.source_archive.name
        custom_source.parent.mkdir()
        shutil.copy2(self.source_archive, custom_source)
        result = self.run_script(HEXPROOF_FORGE_SOURCE_ARCHIVE=str(custom_source))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any(" activate " in line for line in self.commands()))




class DirectoryPublicationTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        environment = patch.dict(os.environ, operator_fixture(Path(directory.name)))
        environment.start()
        self.addCleanup(environment.stop)

    @classmethod
    def setUpClass(cls) -> None:
        spec = importlib.util.spec_from_file_location(
            "publish_server_directory", DEPLOY_DIR / "publish-server-directory.py")
        cls.publisher = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.publisher)

    def test_revision_rejects_rollback_and_same_revision_mutation(self) -> None:
        old = {"schemaVersion": 2, "revision": 5, "servers": []}
        self.publisher.validate_update(json.dumps(old).encode(), old)
        for changed in (dict(old, revision=4), dict(old, directoryUrls=[])):
            with self.assertRaises(ValueError):
                self.publisher.validate_update(json.dumps(old).encode(), changed)
        self.publisher.validate_update(json.dumps(old).encode(), dict(old, revision=6))

    def test_all_preflights_finish_before_any_write(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "servers.json"
            source.write_text('{"schemaVersion":2,"revision":2,"servers":[]}')
            old = b'{"schemaVersion":2,"revision":1,"servers":[]}'
            newer = b'{"schemaVersion":2,"revision":3,"servers":[]}'
            with patch.object(self.publisher, "remote", side_effect=[old, newer]) as remote:
                with self.assertRaises(ValueError):
                    # Two entries simulate a multi-host deployment where a later
                    # preflight failure must prevent every earlier write.
                    self.publisher.publish(source, ["cloud-b", "cloud-b"])
                self.assertEqual([call.kwargs["mode"] for call in remote.call_args_list],
                                 ["read", "read"])

    def test_remote_publish_is_atomic_and_rejects_concurrent_update(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            live = root / "servers.json"
            live.write_bytes(b"previous")
            program = self.publisher.REMOTE.replace('"/var/www/hexproof"', repr(folder))
            token = "test-publication"
            expected = self.publisher.digest(b"previous")
            def run(mode: str, **fields: object):
                return subprocess.run(
                    [sys.executable, "-c", program],
                    input=json.dumps(dict(mode=mode, token=token, expected=expected, **fields)),
                    text=True, capture_output=True, check=False,
                )
            staged = run("stage", payload="new catalog")
            self.assertEqual(staged.returncode, 0, staged.stderr)
            self.assertEqual(live.read_bytes(), b"previous")
            # An operator changed the file between staging and activation.
            live.write_bytes(b"concurrent update")
            raced = run("publish", digest=self.publisher.digest(b"new catalog"))
            self.assertNotEqual(raced.returncode, 0)
            self.assertEqual(live.read_bytes(), b"concurrent update")
            live.write_bytes(b"previous")
            published = run("publish", digest=self.publisher.digest(b"new catalog"))
            self.assertEqual(published.returncode, 0, published.stderr)
            self.assertEqual(live.read_bytes(), b"new catalog")
            self.assertEqual((root / "servers.json.previous").read_bytes(), b"previous")
            self.assertEqual(run("cleanup").returncode, 0)


class PublicContentPublicationTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        environment = patch.dict(os.environ, operator_fixture(Path(directory.name)))
        environment.start()
        self.addCleanup(environment.stop)
        spec = importlib.util.spec_from_file_location("publish_public_content", DEPLOY_DIR / "publish-public-content.py")
        self.publisher = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.publisher)

    def test_remote_assets_are_immutable_and_index_rejects_concurrent_updates(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            program = self.publisher.REMOTE.replace('"/var/www/hexproof/content"', repr(folder))
            def run(mode, payload, **fields):
                request = dict(mode=mode, payload=base64.b64encode(payload).decode(), token="test", **fields)
                return subprocess.run([sys.executable, "-c", program], input=json.dumps(request),
                                      text=True, capture_output=True, check=False, timeout=5)
            asset = dict(path="releases/test/data.json", sha256=hashlib.sha256(b"asset").hexdigest())
            first = run("asset", b"asset", **asset)
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertEqual(run("asset", b"asset", **asset).returncode, 0)
            asset["sha256"] = hashlib.sha256(b"changed").hexdigest()
            self.assertNotEqual(run("asset", b"changed", **asset).returncode, 0)
            self.assertEqual((root / asset["path"]).read_bytes(), b"asset")
            live = root / "index.json"
            live.write_bytes(b"concurrent")
            expected = hashlib.sha256(b"previous").hexdigest()
            self.assertNotEqual(run("index", b"next", expected=expected).returncode, 0)
            self.assertEqual(live.read_bytes(), b"concurrent")
            live.write_bytes(b"previous")
            published = run("index", b"next", expected=expected)
            self.assertEqual(published.returncode, 0, published.stderr)
            self.assertEqual(live.read_bytes(), b"next")
            self.assertEqual((root / "index.json.previous").read_bytes(), b"previous")

    def test_public_asset_verification_failure_does_not_activate_index(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / "package"
            content = self.publisher.CONTENT
            content.package(REPO_ROOT / "apps/client-qt/config/content/sponsors.json",
                            REPO_ROOT / "apps/client-qt/config/content/announcements.json",
                            REPO_ROOT / "apps/client-qt/assets/sponsors", root, 1)
            with patch.object(self.publisher, "remote", return_value=b"") as remote, \
                 patch.object(self.publisher.urllib.request, "urlopen", side_effect=OSError("not served")):
                with self.assertRaises(OSError):
                    self.publisher.publish(root, "cloud-b")
                modes = [call.kwargs["mode"] for call in remote.call_args_list]
                self.assertIn("asset", modes)
                self.assertNotIn("index", modes)

    def test_dropping_announcement_history_fails_before_any_write(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "announcements.json"
            content = self.publisher.CONTENT
            sponsors = REPO_ROOT / "apps/client-qt/config/content/sponsors.json"
            news = json.loads((REPO_ROOT / "apps/client-qt/config/content/announcements.json").read_bytes())
            news["revision"] = 3
            source.write_text(json.dumps(news))
            index = content.package(sponsors, source, REPO_ROOT / "apps/client-qt/assets/sponsors", root / "package", 2)
            old_news = dict(news, revision=2, announcements=[{
                "id": "history", "notificationRevision": 1, "publishedAt": "2026-09-23T00:00:00Z",
                "title": {"en": "History"}, "body": {"en": "Retained body"}}])
            old_payload = json.dumps(old_news).encode()
            old_index = dict(index, revision=1)
            old_index["announcements"] = dict(index["announcements"], revision=2, sha256=content.sha256(old_payload))
            def read(_target, **request):
                self.assertEqual(request["mode"], "read")
                if "path" not in request:
                    return json.dumps(old_index).encode()
                return sponsors.read_bytes() if request["path"] == index["sponsors"]["path"] else old_payload
            with patch.object(self.publisher, "remote", side_effect=read) as remote:
                with self.assertRaisesRegex(ValueError, "complete announcement history"):
                    self.publisher.publish(root / "package", "cloud-b")
                self.assertEqual(remote.call_count, 3)


class OperatorInventoryTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.environment = operator_fixture(self.root)
        environment = patch.dict(os.environ, self.environment)
        environment.start()
        self.addCleanup(environment.stop)
        spec = importlib.util.spec_from_file_location("operator_inventory_tests", DEPLOY_DIR / "operator_config.py")
        self.config = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.config)

    def test_operator_defaults_capabilities_and_home_aliases(self):
        self.assertEqual(self.config.defaults("releaseTargets"), ["cloud-a", "cloud-b"])
        self.assertEqual(self.config.cloud_target("cloud-b", "forge")["origin"], "https://hub-b.example.com")
        with self.assertRaisesRegex(ValueError, "not enabled"):
            self.config.cloud_target("cloud-a", "forge")
        nodes = self.config.load_nodes()
        self.assertEqual(self.config.home_name("home-b-ssh", nodes), "home-b")
        self.assertEqual(self.config.classify("home-b-ssh"), "home")
        self.assertEqual(self.config.classify("cloud-a"), "cloud")

    def test_default_path_is_operator_owned_and_never_the_repo_example(self):
        with patch.dict(os.environ, {"HOME": str(self.root), "XDG_STATE_HOME": "", "HEXPROOF_NODES_FILE": "",
                                    "HEXPROOF_DEPLOYMENT_TARGETS_FILE": ""}):
            self.assertEqual(self.config.inventory_path("nodes"),
                             self.root / ".local/state/hexproof-operator/nodes.json")
            with self.assertRaisesRegex(ValueError, "Missing operator inventory"):
                self.config.load_nodes()
            with self.assertRaisesRegex(ValueError, "Missing operator inventory"):
                self.config.defaults("releaseTargets")
            with patch.dict(os.environ, {"XDG_STATE_HOME": str(self.root / "state")}):
                self.assertEqual(self.config.inventory_path("nodes"), self.root / "state/hexproof-operator/nodes.json")

    def test_missing_explicit_file_and_examples_are_rejected(self):
        for variable, loader, example in (
                ("HEXPROOF_NODES_FILE", self.config.load_nodes, "home/nodes.example.json"),
                ("HEXPROOF_DEPLOYMENT_TARGETS_FILE", self.config.load_targets, "deployment-targets.example.json")):
            for path in (self.root / "missing.json", DEPLOY_DIR / example):
                with self.subTest(variable=variable, path=path.name), patch.dict(os.environ, {variable: str(path)}):
                    with self.assertRaises(ValueError):
                        loader(required=False)

    def test_invalid_target_and_endpoint_values_are_rejected(self):
        for value in ("-oProxyCommand=bad", "host;command", "host\nother"):
            with self.subTest(alias=value), self.assertRaises(ValueError):
                self.config.alias(value)
        for value in ("http://hub.example.com", "https://user:secret@hub.example.com",
                      "https://hub.example.com?token=secret", "https://hub.example.com/path",
                      "https://hub.example.com;command", "https://hub.example.com:8443"):
            with self.subTest(endpoint=value), self.assertRaises(ValueError):
                self.config.origin(value)

    def test_monitoring_uses_configured_home_alias_and_cloud_binary(self):
        spec = importlib.util.spec_from_file_location("monitoring_inventory_tests", DEPLOY_DIR / "monitoring/install.py")
        monitor = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(monitor)
        for target, host, binary in (
                ("cloud-b", "cloud-b", "/usr/local/bin/hexproof-server"),
                ("home-b", "home-b-ssh", "/opt/hexproof-home/current/server/bin/hexproof-server")):
            with self.subTest(target=target), patch.object(monitor, "ssh", return_value="old version") as remote:
                with self.assertRaisesRegex(ValueError, "application version does not match"):
                    monitor.deploy([target], "3.1.0")
                remote.assert_called_once_with(host, binary, "-version")
        with patch.object(monitor, "ssh") as remote:
            with self.assertRaisesRegex(ValueError, "distinct"):
                monitor.deploy(["home-b", "home-b-ssh"], "3.1.0")
            remote.assert_not_called()

    def test_remote_monitor_installer_rejects_unknown_layout_without_operator_files(self):
        environment = dict(os.environ, HEXPROOF_DEPLOYMENT_TARGETS_FILE=str(self.root / "absent.json"),
                           HEXPROOF_NODES_FILE=str(self.root / "absent.json"))
        result = subprocess.run([sys.executable, str(DEPLOY_DIR / "monitoring/install.py"),
                                 "--local", "--port", "57320", "--binary", "/fixture/not-a-service",
                                 "--version", "3.1.0"], env=environment, capture_output=True, text=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("Traceback", result.stderr)
        self.assertNotIn("operator inventory", result.stderr)


if __name__ == "__main__":
    unittest.main()
