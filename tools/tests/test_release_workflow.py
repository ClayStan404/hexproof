#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Exercise the release workflow's metadata and draft-only mutation boundary."""

import fnmatch
import hashlib
import json
import os
import re
import shutil
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/release.yml"


def workflow_job(name):
    return re.search(rf"^  {name}:\n(.*?)(?=^  [a-z][a-z0-9-]*:|\Z)",
                     WORKFLOW.read_text(), re.MULTILINE | re.DOTALL)[1]


def workflow_step(name):
    return re.search(rf"^      - name: {re.escape(name)}\n(.*?)(?=^      - |^  [a-z]|\Z)",
                     WORKFLOW.read_text(), re.MULTILINE | re.DOTALL)[1]


def workflow_script(name):
    step = workflow_step(name)
    lines = step.split("        run: |\n", 1)[1].splitlines()
    script = []
    for line in lines:
        if line and not line.startswith("          "):
            break
        script.append(line[10:] if line else "")
    return "\n".join(script) + "\n"


class ReleaseWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        source = self.root / "apps/client-qt/CMakeLists.txt"
        source.parent.mkdir(parents=True)
        source.write_text('set(HEXPROOF_VERSION "3.1.0")\n')
        self.environment = dict(os.environ, GITHUB_REF_TYPE="tag", GITHUB_REF_NAME="v3.1.0",
                                GITHUB_SHA="a" * 40, REQUESTED_VERSION="",
                                GITHUB_REPOSITORY="ClayStan404/hexproof",
                                RELEASE_VERSION="3.1.0", APPLICATION_VERSION="3.1.0",
                                GITHUB_OUTPUT=str(self.root / "outputs"),
                                RUNNER_TEMP=str(self.root), RELEASE_TAG="v3.1.0",
                                MACOS_RELEASE_NOTARIZED="false")

    def run_step(self, name):
        return subprocess.run(["bash", "-c", workflow_script(name)], cwd=self.root,
                              env=self.environment, text=True, capture_output=True)

    def test_all_packages_require_local_gate_and_assembly_requires_every_input(self):
        def dependencies(job):
            block = workflow_job(job)
            needs = re.search(r"^    needs:\n((?:      - [a-z0-9-]+\n)+)", block,
                              re.MULTILINE)
            return set(re.findall(r"      - ([a-z0-9-]+)", needs[1])) if needs else set()

        packages = {"client-linux", "client-windows", "client-macos", "server", "forge-sources"}
        for job in packages:
            self.assertEqual(dependencies(job), {"prepare"}, job)
        self.assertEqual(dependencies("assemble"), packages | {"prepare"})
        self.assertEqual(dependencies("prepare"), set())
        for job in packages | {"prepare", "assemble"}:
            self.assertNotRegex(workflow_job(job), r"(?m)^    (?:if|continue-on-error):")

    def test_release_uses_read_only_local_status_gate_without_repeating_full_suites(self):
        workflow = WORKFLOW.read_text()
        self.assertNotRegex(workflow, r"(?m)^  quality-(?:gate|server):")
        self.assertNotRegex(workflow, r"\b(?:ctest|go (?:vet|test))\b")
        self.assertNotRegex(workflow, r"python3?\s+-m\s+(?:unittest|pytest)\b")
        self.assertNotIn("HEXPROOF_QML_TESTS_PER_FILE", workflow)
        self.assertNotIn("continue-on-error", workflow)
        prepare = workflow_job("prepare")
        self.assertIn("      contents: read\n      statuses: read\n", prepare)
        self.assertNotIn("statuses: write", workflow)
        step = workflow_step("Require matching local verification")
        self.assertIn("      - name: Require matching local verification\n" + step, prepare)
        self.assertNotRegex(step, r"(?m)^        if:")
        self.assertIn("GH_TOKEN: ${{ github.token }}", step)
        self.assertIn("RELEASE_VERSION: ${{ steps.metadata.outputs.version }}", step)
        self.assertNotIn("|| true", workflow_script("Require matching local verification"))
        self.assertIn("Verify stable card database compatibility", prepare)
        self.assertIn("exit 1", workflow_script("Verify stable card database compatibility"))
        assemble = workflow_job("assemble")
        self.assertIn("      statuses: read", assemble)
        recheck = "Recheck local verification before assembly"
        self.assertIn(recheck, assemble)
        self.assertNotRegex(workflow_step(recheck), r"(?m)^        if:")
        self.assertEqual(workflow_script(recheck), workflow_script("Require matching local verification"))
        self.assertLess(assemble.index(recheck), assemble.index("Download release artifacts"))

    def test_local_status_gate_passes_exact_identity_and_propagates_failure_for_all_builds(self):
        checker = self.root / "tools/release-verification.py"
        checker.parent.mkdir()
        checker.write_text("""import json
import os
from pathlib import Path
import sys
Path(os.environ["STATUS_TEST_LOG"]).write_text(json.dumps(sys.argv[1:]))
sys.exit(int(os.environ["STATUS_TEST_EXIT"]))
""")
        self.environment["STATUS_TEST_LOG"] = str(self.root / "status-log")
        for ref_type in ("tag", "branch"):
            for exit_code in (0, 17):
                with self.subTest(ref_type=ref_type, exit_code=exit_code):
                    self.environment.update(GITHUB_REF_TYPE=ref_type, STATUS_TEST_EXIT=str(exit_code))
                    result = self.run_step("Require matching local verification")
                    self.assertEqual(result.returncode, exit_code, result.stderr)
                    self.assertEqual(json.loads((self.root / "status-log").read_text()),
                                     ["check", "--repository", "ClayStan404/hexproof",
                                      "--commit", "a" * 40, "--version", "3.1.0"])

    def test_complete_source_and_platform_artifacts_are_selected_for_assembly(self):
        source = workflow_job("forge-sources")
        self.assertIn("python3 third_party/forge-runtime/build-overlay.py", source)
        self.assertIn("--source-output build/forge-source-release/hexproof-forge-overlay-source.tar.gz", source)
        self.assertIn("name: hexproof-forge-overlay-source", source)
        self.assertIn("if-no-files-found: error", source)
        pattern = re.search(r"^          pattern: (.+)$", workflow_job("assemble"),
                            re.MULTILINE)[1]
        self.assertFalse(fnmatch.fnmatchcase("release-quality-test-results", pattern))
        for package in ("hexproof-forge-overlay-source", "hexproof-client-linux-x86_64",
                        "hexproof-client-windows-x64", "hexproof-client-macos-arm64",
                        "hexproof-server-linux-amd64", "hexproof-server-linux-arm64"):
            self.assertTrue(fnmatch.fnmatchcase(package, pattern), package)

    def test_platform_smoke_signing_and_attestation_checks_remain(self):
        for job in ("client-linux", "client-windows", "client-macos"):
            self.assertIn("- name: Verify packaged client", workflow_job(job))
            self.assertIn("--version", workflow_job(job))
        self.assertIn("smoke_status -ne 124", workflow_job("client-linux"))
        self.assertIn("startup smoke test", workflow_job("client-windows"))
        macos = workflow_job("client-macos")
        self.assertIn("codesign --verify --deep --strict", macos)
        self.assertIn("startup smoke test", macos)
        self.assertIn("- name: Verify packaged server", workflow_job("server"))
        self.assertIn('"$connector" -version', workflow_job("server"))
        attest = workflow_step("Attest release assets")
        self.assertIn("if: needs.prepare.outputs.publish == 'true'", attest)
        self.assertIn("uses: actions/attest@", attest)
        self.assertIn("subject-path: release-assets/*", attest)

    def prepare_assembly_inputs(self):
        tools = self.root / "tools"
        tools.mkdir()
        shutil.copyfile(ROOT / "tools/write-release-compatibility.py", tools / "write-release-compatibility.py")
        schema = self.root / "protocol/v2/wire-schema.json"
        schema.parent.mkdir(parents=True)
        schema.write_text('{"protocol": "hexproof.v2"}\n')
        for directory, filename, payload in (("client", "client package.tar.gz", b"client fixture"),
                                             ("server", "server.tar.gz", b"server fixture")):
            path = self.root / "downloaded" / directory / filename
            path.parent.mkdir(parents=True)
            path.write_bytes(payload)

    def test_assembly_checksums_every_package_and_compatibility_manifest(self):
        self.prepare_assembly_inputs()
        result = self.run_step("Assemble assets and checksums")
        self.assertEqual(result.returncode, 0, result.stderr)
        assets = self.root / "release-assets"
        manifest = json.loads((assets / "compatibility.json").read_text())
        self.assertEqual(manifest, {"schemaVersion": 1, "applicationVersion": "3.1.0",
                                    "gameProtocol": "hexproof.v2"})
        checksums = {}
        for line in (assets / "SHA256SUMS").read_text().splitlines():
            digest, name = line.split("  ", 1)
            checksums[name] = digest
            self.assertEqual(digest, hashlib.sha256((assets / name).read_bytes()).hexdigest())
        self.assertEqual(set(checksums), {"client package.tar.gz", "server.tar.gz", "compatibility.json"})

    def test_duplicate_asset_names_cannot_silently_replace_a_package(self):
        self.prepare_assembly_inputs()
        duplicate = self.root / "downloaded/other/server.tar.gz"
        duplicate.parent.mkdir()
        duplicate.write_bytes(b"different package")
        result = self.run_step("Assemble assets and checksums")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Duplicate release filename", result.stderr)
        self.assertFalse((self.root / "release-assets/SHA256SUMS").exists())

    def test_exact_tag_uses_committed_source_version(self):
        result = self.run_step("Resolve and validate version")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "outputs").read_text(),
                         "publish=true\ntag=v3.1.0\nversion=3.1.0\n")

    def test_wrong_or_invalid_tag_cannot_override_source_version(self):
        for tag in ("v3.2.0", "v3.1.0-preview"):
            with self.subTest(tag=tag):
                self.environment["GITHUB_REF_NAME"] = tag
                result = self.run_step("Resolve and validate version")
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.root / "outputs").exists())

    def test_manual_branch_build_remains_artifact_only(self):
        self.environment.update(GITHUB_REF_TYPE="branch", GITHUB_REF_NAME="main",
                                REQUESTED_VERSION="3.1.0")
        result = self.run_step("Resolve and validate version")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "outputs").read_text(),
                         "publish=false\ntag=\nversion=3.1.0\n")

    def test_manual_build_cannot_override_locally_verified_source_version(self):
        self.environment.update(GITHUB_REF_TYPE="branch", GITHUB_REF_NAME="main",
                                REQUESTED_VERSION="3.2.0")
        result = self.run_step("Resolve and validate version")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("locally verified source version", result.stderr)
        self.assertFalse((self.root / "outputs").exists())

    def install_fake_gh(self, draft_state):
        binary = self.root / "bin/gh"
        binary.parent.mkdir()
        binary.write_text('''#!/usr/bin/env python3
import json
import os
import re
from pathlib import Path
import sys

args = sys.argv[1:]
with open(os.environ["GH_TEST_LOG"], "a") as log:
    log.write(json.dumps(args) + "\\n")
if args[:2] == ["release", "view"]:
    if "isDraft" in args:
        state = os.environ["GH_TEST_DRAFT_STATE"]
        if state == "missing":
            sys.exit(1)
        print(state)
    else:
        print("Existing generated notes.")
elif args[:2] == ["release", "edit"]:
    Path(os.environ["GH_TEST_NOTES"]).write_text(Path(args[args.index("-F") + 1]).read_text())
''')
        binary.chmod(0o755)
        assets = self.root / "release-assets"
        assets.mkdir()
        (assets / "compatibility.json").write_text("{}\n")
        self.environment.update(PATH=str(binary.parent) + os.pathsep + os.environ["PATH"],
                                GH_TEST_LOG=str(self.root / "gh-log"),
                                GH_TEST_NOTES=str(self.root / "final-notes"),
                                GH_TEST_DRAFT_STATE=draft_state)

    def calls(self):
        return [json.loads(line) for line in (self.root / "gh-log").read_text().splitlines()]

    def test_published_release_is_read_only(self):
        self.install_fake_gh("false")
        result = self.run_step("Create or update draft release")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Refusing", result.stderr)
        self.assertEqual(len(self.calls()), 1)
        self.assertFalse((self.root / "final-notes").exists())

    def test_unrecognized_draft_response_cannot_mutate_release(self):
        self.install_fake_gh("null")
        result = self.run_step("Create or update draft release")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.calls()), 1)

    def test_existing_draft_upload_preserves_install_notice(self):
        self.install_fake_gh("true")
        result = self.run_step("Create or update draft release")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[1] for call in self.calls()], ["view", "upload", "view", "edit"])
        notes = (self.root / "final-notes").read_text()
        self.assertIn("<!-- hexproof-macos-install-notes:start -->", notes)
        self.assertIn("Existing generated notes.", notes)

    def test_new_release_is_draft_with_verified_tag(self):
        self.install_fake_gh("missing")
        result = self.run_step("Create or update draft release")
        self.assertEqual(result.returncode, 0, result.stderr)
        create = next(call for call in self.calls() if call[1] == "create")
        self.assertIn("--draft", create)
        self.assertIn("--verify-tag", create)
        self.assertEqual(create[create.index("--target") + 1], "a" * 40)
        self.assertFalse(any(call[1] == "publish" for call in self.calls()))


if __name__ == "__main__":
    unittest.main()
