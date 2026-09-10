#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SETUP_ACTION = "./.github/actions/setup-qt"


class QtToolchainTests(unittest.TestCase):
    def test_shared_toolchain_uses_an_exact_version_and_required_modules(self):
        action = (ROOT / ".github/actions/setup-qt/action.yml").read_text()
        self.assertIn("using: composite", action)
        self.assertRegex(action, r"install-qt-action@[0-9a-f]{40}\b")
        version = re.search(r"version: '([0-9]+\.[0-9]+\.[0-9]+)'", action)
        self.assertIsNotNone(version, "Pin a validated release, not a moving latest version")
        self.assertIn("modules: qtwebsockets qtimageformats", action)
        self.assertIn("cache: true", action)
        packaging = (ROOT / "packaging/README.md").read_text()
        self.assertIn("pinned Qt " + version.group(1), packaging)

    def test_every_qt_job_uses_shared_setup_after_checkout(self):
        for name in ("ci", "release", "card-database"):
            with self.subTest(workflow=name):
                workflow = (ROOT / f".github/workflows/{name}.yml").read_text()
                self.assertNotIn("install-qt-action@", workflow)
                self.assertNotIn("QT_VERSION:", workflow)
                self.assertIn("uses: " + SETUP_ACTION, workflow)
                for job_steps in workflow.split("    steps:\n")[1:]:
                    if "uses: " + SETUP_ACTION in job_steps:
                        self.assertIn("uses: actions/checkout@", job_steps)
                        self.assertLess(job_steps.index("uses: actions/checkout@"),
                                        job_steps.index("uses: " + SETUP_ACTION))

    def test_macos_release_and_local_bundle_share_supported_baseline(self):
        release = (ROOT / ".github/workflows/release.yml").read_text()
        script = (ROOT / "packaging/macos/build-bundle.sh").read_text()
        packaging = (ROOT / "packaging/README.md").read_text()
        self.assertIn("HEXPROOF_MACOS_DEPLOYMENT_TARGET: '13.0'", release)
        self.assertIn("${HEXPROOF_MACOS_DEPLOYMENT_TARGET:-13.0}", script)
        self.assertIn("macOS 13+ Apple Silicon", packaging)


if __name__ == "__main__":
    unittest.main()
