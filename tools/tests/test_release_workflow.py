#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Exercise the release workflow's metadata and draft-only mutation boundary."""

import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/release.yml"


def workflow_script(name):
    step = WORKFLOW.read_text().split(f"      - name: {name}\n", 1)[1]
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
                                GITHUB_OUTPUT=str(self.root / "outputs"),
                                RUNNER_TEMP=str(self.root), RELEASE_TAG="v3.1.0",
                                MACOS_RELEASE_NOTARIZED="false")

    def run_step(self, name):
        return subprocess.run(["bash", "-c", workflow_script(name)], cwd=self.root,
                              env=self.environment, text=True, capture_output=True)

    def test_packaging_runs_in_parallel_but_assembly_requires_full_quality(self):
        text = WORKFLOW.read_text()
        def dependencies(job):
            block = re.search(rf"^  {job}:\n(.*?)(?=^  [a-z][a-z0-9-]*:|\Z)",
                              text, re.MULTILINE | re.DOTALL)[1]
            needs = re.search(r"^    needs:\n((?:      - [a-z0-9-]+\n)+)", block,
                              re.MULTILINE)
            return set(re.findall(r"      - ([a-z0-9-]+)", needs[1])) if needs else set()
        platforms = {"client-linux", "client-windows", "client-macos", "server"}
        for job in platforms:
            self.assertTrue(dependencies(job) <= {"prepare"}, job)
        required = dependencies("assemble")
        self.assertTrue(platforms | {"prepare", "quality-gate"} <= required)
        # Successful packages alone cannot create a combined/publishable bundle.
        successful = platforms | {"prepare"}
        self.assertFalse(required <= successful)
        self.assertTrue(required <= successful | {"quality-gate"})

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
                                REQUESTED_VERSION="3.2.0")
        result = self.run_step("Resolve and validate version")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "outputs").read_text(),
                         "publish=false\ntag=\nversion=3.2.0\n")

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
