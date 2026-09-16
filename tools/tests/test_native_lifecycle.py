# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Exercise runner subprocess/restart logic with an explicitly fake client.

These tests do not open a window, connect to a display or establish product
GUI coverage. The child fabricates audit artifacts only to test the runner's
artifact validation and lifecycle decisions.
"""

import argparse
import contextlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


PATH = Path(__file__).resolve().parents[1] / "ui-automation/run-native.py"
SPEC = importlib.util.spec_from_file_location("native_lifecycle_runner", PATH)
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)

FAKE_CLIENT = r'''
import base64
import json
import os
from pathlib import Path
import sys
import time

output = Path(os.environ["HEXPROOF_AUDIT_OUTPUT"])
profile = Path(os.environ["HEXPROOF_TEST_PROFILE_ROOT"])
app_data = Path(os.environ["XDG_DATA_HOME"]) / "Hexproof/Hexproof"
shared = Path(os.environ["HEXPROOF_AUDIT_SHARED"])
stage = int(os.environ["HEXPROOF_AUDIT_STAGE"])
mode = Path(os.environ["HEXPROOF_AUDIT_DRIVER"]).read_text().strip()
state_path = profile / "tool-only-restart-state.json"

def write(name, value):
    (output / name).write_text(json.dumps(value))

if stage == 1:
    assert not (app_data / "settings.json").exists(), "Fresh settings were preseeded"
    (app_data / "settings.json").write_text('{"toolOnlyLanguage":"preserved"}')
    (app_data / "decks.json").write_text('{"toolOnlyDeck":"preserved"}')
    (app_data / "images").mkdir()
    (app_data / "images/tool-only-image").write_bytes(b"fake image, not product evidence")
    (profile / "downloads/tool-only-download").write_text("preserved")
    (shared / "tool-only-stage-marker").write_text("must not enter next stage")
    state_path.write_text(json.dumps({"pid": os.getpid(), "profile": str(profile)}))
else:
    prior = json.loads(state_path.read_text())
    assert prior["profile"] == str(profile), "Restart changed the profile"
    assert prior["pid"] != os.getpid(), "Restart reused the process"
    try:
        os.kill(prior["pid"], 0)
    except ProcessLookupError:
        pass
    else:
        raise AssertionError("Next stage started before the old client exited")
    assert json.loads((app_data / "settings.json").read_text())["toolOnlyLanguage"] == "preserved"
    assert json.loads((app_data / "decks.json").read_text())["toolOnlyDeck"] == "preserved"
    assert (app_data / "images/tool-only-image").is_file()
    assert (profile / "downloads/tool-only-download").read_text() == "preserved"
    assert not (shared / "tool-only-stage-marker").exists(), "Stage coordination leaked"

write("tool-only-child.json", {
    "pid": os.getpid(), "stage": stage, "profile": str(profile),
    "shared": str(shared), "startupServices": os.environ["HEXPROOF_AUDIT_STARTUP_SERVICES"],
    "catalogImport": os.environ["HEXPROOF_AUDIT_CATALOG_IMPORT"],
    "deckManifest": os.environ["HEXPROOF_AUDIT_DECK_MANIFEST"],
    "downloadConfiguration": (profile / "config/user-dirs.dirs").read_text(),
    "toolOnly": True,
    "networkNamespace": os.readlink("/proc/self/ns/net"),
    "networkIsolated": os.environ["HEXPROOF_AUDIT_NETWORK_ISOLATED"],
    "gioUseVfs": os.environ.get("GIO_USE_VFS"),
    "arguments": sys.argv[1:],
    "windowWidth": os.environ["HEXPROOF_AUDIT_WIDTH"],
    "windowHeight": os.environ["HEXPROOF_AUDIT_HEIGHT"],
    "legacyWidth": os.environ.get("AUDIT_WIDTH"),
    "legacyHeight": os.environ.get("AUDIT_HEIGHT"),
})
if mode == "missing-evidence":
    raise SystemExit(0)
if mode == "hang":
    time.sleep(60)

result = {"status": "failed" if mode == "fail" else "passed",
          "requiredScreenshots": ["tool-only.png"], "toolOnly": True}
if mode.startswith("download"):
    download = profile / ("outside-download" if mode == "download-outside" else "downloads/tool-only-package")
    download.write_bytes(b"tool-only download bytes")
    result.update(scenario="application-update", downloadReady=True, sawDownload=True,
                  updaterError="", sourceVersion="1.1.0", targetVersion="1.2.0", downloadPath=str(download))
write("result.json", result)
if mode == "download-missing-native":
    raise SystemExit(0)
write("startup.json", {"evidence": "native-qt-input", "pid": os.getpid(), "toolOnly": True,
                       "window": {"platform": "xcb", "visible": True, "exposed": True}})
write("audit-summary.json", {"evidence": "native-qt-input", "inputs": 1, "exitCode": 0,
                             "failedInputs": 0, "artifactFailures": 0,
                             "qmlWarnings": [], "toolOnly": True})
(output / "actions.jsonl").write_text(json.dumps({
    "action": "click", "accepted": True, "evidence": "native-qt-input",
    "sequence": 1, "toolOnly": True}) + "\n")
(output / "tool-only.png").write_bytes(base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a"
    "Y9sAAAAASUVORK5CYII="))
'''


@unittest.skipUnless(sys.platform.startswith("linux"), "The lifecycle runner is Linux only")
class NativeLifecycleTests(unittest.TestCase):
    def exercise(self, root, first="pass", second="pass", timeout=5, network_isolated=False,
                 windowed=False):
        binary = root / "tool-only-fake-client.py"
        binary.write_text(f"#!{sys.executable}\n" + FAKE_CLIENT)
        binary.chmod(0o700)
        first_scenario, next_scenario = root / "First.qml", root / "Restart.qml"
        first_scenario.write_text(first)
        next_scenario.write_text(second)
        catalog_import = root / "catalog-to-import.sqlite"
        catalog_import.write_bytes(b"Tool fixture path only; the fake client never imports it")
        manifest = root / "manifest.json"
        manifest.write_text('{"toolOnly": true}')
        args = argparse.Namespace(
            scenario=first_scenario, next_scenario=[next_scenario], binary=binary,
            server_binary=None, output=root / "run", catalog=None, fixture_dir=None,
            catalog_import=catalog_import, deck_manifest=manifest, startup_services=True,
            network_isolated=network_isolated,
            fresh_settings=True, file_dialog_helper=None, card_language="en", variant="modern",
            players=1, timeout=timeout, hang_timeout=2, windowed=windowed,
            width=1440 if windowed else None, height=900 if windowed else None, scale=1,
        )
        # run() bypasses the desktop lock only for this headless fake process.
        # No Qt client or X11 helper is launched and no display input is sent.
        with mock.patch.dict(os.environ, {"DISPLAY": ":tool-only-no-display",
                                          "QT_QPA_PLATFORM": "xcb"}), \
                contextlib.redirect_stdout(io.StringIO()):
            code = RUNNER.run(args)
        report = json.loads((args.output / "report.json").read_text())
        return code, report, args.output

    def test_window_mode_reaches_every_child_and_restart(self):
        for windowed in (False, True):
            with self.subTest(windowed=windowed), tempfile.TemporaryDirectory() as directory, \
                    mock.patch.dict(os.environ, {"AUDIT_WIDTH": "910", "AUDIT_HEIGHT": "630"}):
                code, report, output = self.exercise(Path(directory), windowed=windowed)
                self.assertEqual(code, 0, report)
                environment = json.loads((output / "environment.json").read_text())
                self.assertEqual(environment["requestedWindowMode"], "windowed" if windowed else "maximized")
                self.assertEqual(environment["requestedWindowSize"], [1440, 900] if windowed else None)
                for stage in ("artifacts", "stage-2-artifacts"):
                    child = json.loads((output / "seat-1" / stage / "tool-only-child.json").read_text())
                    self.assertEqual("--windowed" in child["arguments"], windowed)
                    self.assertEqual(child["windowWidth"], "1440" if windowed else "")
                    self.assertEqual(child["windowHeight"], "900" if windowed else "")
                    self.assertIsNone(child["legacyWidth"])
                    self.assertIsNone(child["legacyHeight"])

    def test_finished_updater_stage_seals_download_and_rejects_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            code, report, output = self.exercise(Path(directory), first="download")
            self.assertEqual(code, 0, report)
            seat = report["seats"][0]
            artifacts = output / "seat-1/artifacts"
            evidence_path = artifacts / "download-evidence.json"
            evidence = json.loads(evidence_path.read_text())
            archive = output / "seat-1/downloads/tool-only-package"
            self.assertEqual(evidence["sha256"], RUNNER.digest(archive))
            self.assertEqual(evidence["bytes"], len(b"tool-only download bytes"))
            self.assertEqual(evidence["resultSha256"], RUNNER.digest(artifacts / "result.json"))
            self.assertEqual(evidence["runId"], report["runId"])
            self.assertEqual(seat["verifiedDownload"]["sha256"], RUNNER.digest(evidence_path))
            self.assertNotIn("verifiedDownload", report["seats"][1])
            before = evidence_path.read_bytes()
            with self.assertRaises(FileExistsError):
                RUNNER.record_verified_download(artifacts, seat["scenarioResult"], report["runId"], 1, 1)
            self.assertEqual(evidence_path.read_bytes(), before)

    def test_download_outside_profile_or_without_native_evidence_cannot_seal_or_restart(self):
        for mode in ("download-outside", "download-missing-native"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                code, report, output = self.exercise(Path(directory), first=mode)
                self.assertEqual(code, 1, report)
                self.assertEqual(report["seats"][0]["status"], "failed")
                self.assertNotIn("verifiedDownload", report["seats"][0])
                self.assertFalse((output / "seat-1/artifacts/download-evidence.json").exists())
                self.assertFalse((output / "seat-1/stage-2-artifacts").exists())

    def test_offline_children_use_actual_separate_network_namespaces(self):
        launcher = shutil.which("unshare")
        if not launcher or subprocess.run(
                [launcher, "--user", "--map-root-user", "--net", "true"],
                capture_output=True).returncode:
            self.skipTest("This environment does not permit unprivileged network namespaces")
        with tempfile.TemporaryDirectory() as directory, \
                mock.patch.dict(os.environ, {"GIO_USE_VFS": "gvfs"}):
            code, report, output = self.exercise(Path(directory), network_isolated=True)
            self.assertEqual(code, 0, report)
            self.assertEqual(os.environ["GIO_USE_VFS"], "gvfs")
            parent_namespace = os.readlink("/proc/self/ns/net")
            for name in ("artifacts", "stage-2-artifacts"):
                child = json.loads((output / "seat-1" / name / "tool-only-child.json").read_text())
                self.assertEqual(child["networkIsolated"], "1")
                self.assertNotEqual(child["networkNamespace"], parent_namespace)
                self.assertEqual(child["gioUseVfs"], "local")
            environment = json.loads((output / "environment.json").read_text())
            self.assertIs(environment["networkIsolated"], True)
            self.assertEqual(environment["clientLauncher"],
                             [launcher, "--user", "--map-root-user", "--net"])
            self.assertEqual(environment["clientEnvironmentOverrides"], {"GIO_USE_VFS": "local"})
            self.assertEqual(environment["fileSystemScope"], "local-files-only")

    def test_networked_children_keep_the_inherited_vfs(self):
        with tempfile.TemporaryDirectory() as directory, \
                mock.patch.dict(os.environ, {"GIO_USE_VFS": "gvfs"}):
            code, report, output = self.exercise(Path(directory))
            self.assertEqual(code, 0, report)
            for name in ("artifacts", "stage-2-artifacts"):
                child = json.loads((output / "seat-1" / name / "tool-only-child.json").read_text())
                self.assertEqual(child["gioUseVfs"], "gvfs")
            environment = json.loads((output / "environment.json").read_text())
            self.assertEqual(environment["clientEnvironmentOverrides"], {})
            self.assertEqual(environment["fileSystemScope"], "not-restricted-by-runner")
            self.assertEqual(os.environ["GIO_USE_VFS"], "gvfs")

    def test_restart_uses_new_process_and_preserves_same_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            code, report, output = self.exercise(Path(directory))
            self.assertEqual(code, 0, report)
            self.assertEqual(report["status"], "passed")
            self.assertEqual([seat["stage"] for seat in report["seats"]], [1, 2])
            artifacts = [output / "seat-1" / name
                         for name in ("artifacts", "stage-2-artifacts")]
            observations = [json.loads((path / "tool-only-child.json").read_text())
                            for path in artifacts]
            self.assertNotEqual(observations[0]["pid"], observations[1]["pid"])
            self.assertEqual(observations[0]["profile"], observations[1]["profile"])
            self.assertNotEqual(observations[0]["shared"], observations[1]["shared"])
            for observation in observations:
                self.assertEqual(observation["startupServices"], "1")
                self.assertEqual(observation["catalogImport"], str(Path(directory) / "catalog-to-import.sqlite"))
                self.assertEqual(observation["deckManifest"], str(Path(directory) / "manifest.json"))
                self.assertEqual(observation["downloadConfiguration"],
                                 f'XDG_DOWNLOAD_DIR="{output / "seat-1/downloads"}"\n')
            first_before = json.loads((artifacts[0] / "profile-before.json").read_text())
            first_after = json.loads((artifacts[0] / "profile-after.json").read_text())
            next_before = json.loads((artifacts[1] / "profile-before.json").read_text())
            self.assertNotIn("settings.json", first_before["files"])
            self.assertEqual(first_before["imageFiles"], 0)
            self.assertEqual(first_after["imageFiles"], 1)
            self.assertEqual(first_after, next_before)

    def test_failed_first_stage_stops_restart_despite_zero_exit(self):
        with tempfile.TemporaryDirectory() as directory:
            code, report, output = self.exercise(Path(directory), first="fail")
            self.assertEqual(code, 1)
            self.assertEqual(report["status"], "failed")
            self.assertEqual(len(report["seats"]), 1)
            self.assertEqual(report["seats"][0]["exitCode"], 0)
            self.assertEqual(report["seats"][0]["status"], "failed")
            self.assertFalse((output / "seat-1/stage-2-artifacts").exists())

    def test_restart_must_produce_its_own_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            code, report, output = self.exercise(Path(directory), second="missing-evidence")
            self.assertEqual(code, 1)
            self.assertEqual(report["status"], "failed")
            self.assertEqual([seat["status"] for seat in report["seats"]], ["passed", "failed"])
            self.assertEqual(report["seats"][1]["exitCode"], 0)
            self.assertTrue((output / "seat-1/artifacts/result.json").is_file())
            self.assertFalse((output / "seat-1/stage-2-artifacts/result.json").exists())

    def test_watchdog_terminates_only_the_hung_restart_child(self):
        with tempfile.TemporaryDirectory() as directory:
            code, report, output = self.exercise(Path(directory), second="hang", timeout=1)
            self.assertEqual(code, 1)
            self.assertIn("watchdog", report["reason"])
            self.assertEqual([seat["status"] for seat in report["seats"]], ["passed", "failed"])
            observation = json.loads((output / "seat-1/stage-2-artifacts/tool-only-child.json").read_text())
            with self.assertRaises(ProcessLookupError):
                os.kill(observation["pid"], 0)


if __name__ == "__main__":
    unittest.main()
