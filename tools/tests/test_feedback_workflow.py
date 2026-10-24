#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Exercise the feedback-only workflow's source gate and real package construction."""

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/feedback.yml"


def step(name):
    return re.search(rf"^      - name: {re.escape(name)}\n(.*?)(?=^      - |\Z)",
                     WORKFLOW.read_text(), re.MULTILINE | re.DOTALL)[1]


def script(name):
    lines = step(name).split("        run: |\n", 1)[1].splitlines()
    return "\n".join(line[10:] if line else "" for line in lines) + "\n"


class FeedbackWorkflowTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        (self.root / "apps/server").mkdir(parents=True)
        (self.root / "apps/client-qt").mkdir()
        (self.root / "apps/client-qt/CMakeLists.txt").write_text('set(HEXPROOF_VERSION "3.1.0")\n')
        (self.root / "packaging/server").mkdir(parents=True)
        self.unit = b"[Service]\nExecStart=/usr/local/bin/hexproof-feedback\n"
        (self.root / "packaging/server/hexproof-feedback.service.in").write_bytes(self.unit)
        self.bin = self.root / "test-bin"
        self.bin.mkdir()
        self.environment = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                                GITHUB_EVENT_NAME="workflow_dispatch", GITHUB_REPOSITORY="ClayStan404/hexproof",
                                GITHUB_REF="refs/heads/master", GITHUB_SHA="a" * 40, REQUESTED_HEAD_SHA="a" * 40,
                                REPOSITORY_PRIVATE="false", TARGET_ARCH="amd64", GITHUB_WORKSPACE=str(self.root),
                                GITHUB_OUTPUT=str(self.root / "outputs"), COMMAND_LOG=str(self.root / "commands.jsonl"))
        self.fake("git", 'import os, sys\nif sys.argv[1:]==["rev-parse", "HEAD"]: print(os.environ.get("CHECKOUT_SHA", os.environ["GITHUB_SHA"]))\nelif sys.argv[1:]==["status", "--porcelain", "--untracked-files=all"]: print(os.environ.get("DIRTY_SOURCE", ""))\nelse: sys.exit(1)\n')
        self.fake("go", '''import json, os, pathlib, sys
args = sys.argv[1:]
with open(os.environ["COMMAND_LOG"], "a") as log:
    log.write(json.dumps({"args": args, "cwd": os.getcwd(), "cgo": os.environ.get("CGO_ENABLED"),
                          "os": os.environ.get("GOOS"), "arch": os.environ.get("GOARCH")}) + "\\n")
if args[0] == "build":
    output = pathlib.Path(args[args.index("-o") + 1])
    output.write_bytes(b"fixture receiver " + os.environ["GOARCH"].encode())
    output.chmod(0o755)
elif args[0] not in ("vet", "test"):
    sys.exit(1)
''')

    def fake(self, name, source):
        path = self.bin / name
        path.write_text("#!" + sys.executable + "\n" + source)
        path.chmod(0o755)

    def run_step(self, name, **overrides):
        working = re.search(r"^        working-directory: (.+)$", step(name), re.MULTILINE)
        cwd = self.root / working[1] if working else self.root
        return subprocess.run(["bash", "-e", "-o", "pipefail", "-c", script(name)], cwd=cwd,
                              env=dict(self.environment, **overrides), capture_output=True, text=True, timeout=10)

    def test_only_exact_public_master_source_and_supported_architectures_are_admitted(self):
        self.assertEqual(self.run_step("Validate source identity").returncode, 0)
        self.assertEqual(self.run_step("Validate source identity", TARGET_ARCH="arm64").returncode, 0)
        for change in ({"GITHUB_EVENT_NAME": "push"}, {"GITHUB_REPOSITORY": "contributor/fork"},
                       {"GITHUB_REF": "refs/heads/topic"}, {"GITHUB_REF": "refs/tags/master"},
                       {"REPOSITORY_PRIVATE": "true"}, {"GITHUB_SHA": "b" * 40},
                       {"REQUESTED_HEAD_SHA": "a" * 39}, {"REQUESTED_HEAD_SHA": "A" * 40},
                       {"TARGET_ARCH": "386"}):
            with self.subTest(change=change):
                self.assertNotEqual(self.run_step("Validate source identity", **change).returncode, 0)
        self.assertFalse((self.root / "commands.jsonl").exists())

    def test_verification_is_limited_to_feedback_and_includes_race_checks(self):
        result = self.run_step("Verify feedback service")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [json.loads(line) for line in (self.root / "commands.jsonl").read_text().splitlines()]
        self.assertEqual([call["args"] for call in calls],
                         [["vet", "./internal/feedback", "./cmd/hexproof-feedback"],
                          ["test", "-race", "./internal/feedback", "./cmd/hexproof-feedback"]])
        self.assertTrue(all(call["cwd"] == str(self.root / "apps/server") for call in calls))

    def test_actual_package_has_exact_component_contents_and_matching_provenance(self):
        for arch in ("amd64", "arm64"):
            with self.subTest(arch=arch):
                result = self.run_step("Build feedback package", TARGET_ARCH=arch)
                self.assertEqual(result.returncode, 0, result.stderr)
                name = "hexproof-feedback-3.1.0-linux-" + arch
                archive = self.root / "build/feedback-package" / (name + ".tar.gz")
                with tarfile.open(archive) as bundle:
                    files = {item.name.removeprefix(name + "/"): item for item in bundle if not item.isdir()}
                    self.assertEqual(set(files), {"bin/hexproof-feedback", "deploy/hexproof-feedback.service.in", "build.json"})
                    self.assertTrue(all(item.isfile() for item in files.values()))
                    binary = bundle.extractfile(files["bin/hexproof-feedback"]).read()
                    self.assertEqual(binary, b"fixture receiver " + arch.encode())
                    self.assertTrue(files["bin/hexproof-feedback"].mode & 0o111)
                    self.assertEqual(bundle.extractfile(files["deploy/hexproof-feedback.service.in"]).read(), self.unit)
                    self.assertEqual(json.load(bundle.extractfile(files["build.json"])),
                                     {"schemaVersion": 1, "version": "3.1.0", "sourceCommit": "a" * 40,
                                      "architecture": arch, "receiverSha256": hashlib.sha256(binary).hexdigest()})
                call = json.loads((self.root / "commands.jsonl").read_text().splitlines()[-1])
                self.assertEqual(call["cwd"], str(self.root / "apps/server"))
                self.assertEqual((call["cgo"], call["os"], call["arch"]), ("0", "linux", arch))
                self.assertEqual(call["args"][:4], ["build", "-trimpath", "-ldflags", "-X hexproof/server/internal/buildinfo.Version=3.1.0"])
                self.assertEqual(call["args"][-1], "./cmd/hexproof-feedback")
                self.assertIn("archive=" + str(archive), (self.root / "outputs").read_text())

    def test_checkout_changes_or_invalid_version_prevent_build(self):
        for change in ({"CHECKOUT_SHA": "b" * 40}, {"DIRTY_SOURCE": " M apps/server/go.mod"}):
            with self.subTest(change=change):
                self.assertNotEqual(self.run_step("Build feedback package", **change).returncode, 0)
        (self.root / "apps/client-qt/CMakeLists.txt").write_text('set(HEXPROOF_VERSION "invalid")\n')
        self.assertNotEqual(self.run_step("Build feedback package").returncode, 0)
        self.assertFalse((self.root / "commands.jsonl").exists())

    def test_signed_package_upload_is_after_verification_with_no_release_or_deployment(self):
        workflow = WORKFLOW.read_text()
        triggers = workflow.split("on:\n", 1)[1].split("\npermissions:\n", 1)[0]
        self.assertEqual(re.findall(r"^  ([a-z_]+):$", triggers, re.MULTILINE), ["workflow_dispatch"])
        permissions = workflow.split("permissions:\n", 1)[1].split("\njobs:\n", 1)[0]
        self.assertEqual(dict(re.findall(r"^  ([a-z-]+): ([a-z]+)$", permissions, re.MULTILINE)),
                         {"contents": "read", "id-token": "write", "attestations": "write"})
        names = re.findall(r"^      - name: (.+)$", workflow, re.MULTILINE)
        self.assertEqual(names, ["Validate source identity", "Verify feedback service", "Build feedback package",
                                 "Attest feedback package", "Upload feedback package"])
        self.assertEqual(re.findall(r"^  ([a-z][a-z0-9-]*):$", workflow.split("jobs:\n", 1)[1], re.MULTILINE), ["package"])
        self.assertIn("    name: Build feedback service\n", workflow)
        self.assertIn("          ref: ${{ github.sha }}\n", workflow)
        self.assertIn("          go-version-file: apps/server/go.mod\n", workflow)
        self.assertIn("subject-path: ${{ steps.package.outputs.archive }}", step("Attest feedback package"))
        self.assertIn("path: ${{ steps.package.outputs.archive }}", step("Upload feedback package"))
        self.assertIn("name: hexproof-feedback-${{ github.sha }}-linux-${{ inputs.arch }}", step("Upload feedback package"))
        self.assertNotRegex(workflow, r"(?m)^\s+(?:continue-on-error|if):")
        actions = re.findall(r"uses: ([^\s]+)", workflow)
        release = (ROOT / ".github/workflows/release.yml").read_text()
        self.assertEqual(len(actions), 4)
        for action in actions:
            self.assertRegex(action, r"@[0-9a-f]{40}$")
            self.assertIn("uses: " + action, release)
        self.assertNotRegex(workflow, r"\b(?:ssh|scp|gh release|git push|ctest|cmake)\b|secrets\.")


if __name__ == "__main__":
    unittest.main()
