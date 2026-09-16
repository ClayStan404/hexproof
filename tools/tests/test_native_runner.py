# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import base64
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

PATH = Path(__file__).resolve().parents[1] / "ui-automation/run-native.py"
SPEC = importlib.util.spec_from_file_location("native_runner", PATH)
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


@unittest.skipUnless(sys.platform.startswith("linux"), "The native runner supports Linux only")
class NativeRunnerTests(unittest.TestCase):
    def test_window_size_is_an_explicit_layout_variant(self):
        cases = [
            ([], False, None, None),
            (["--windowed"], True, 1440, 900),
            (["--width", "900", "--height", "620"], True, 900, 620),
            (["--width", "1000"], True, 1000, 900),
            (["--height", "700"], True, 1440, 700),
        ]
        for options, windowed, width, height in cases:
            with self.subTest(options=options), tempfile.TemporaryDirectory() as directory, \
                    mock.patch.object(RUNNER, "ROOT", Path(directory)), \
                    mock.patch.object(RUNNER, "run", return_value=0) as run, \
                    mock.patch.object(RUNNER.signal, "signal"), \
                    mock.patch.object(sys, "argv", [str(PATH), "--scenario", str(PATH), *options]):
                self.assertEqual(RUNNER.main(), 0)
                args = run.call_args.args[0]
                self.assertEqual((args.windowed, args.width, args.height), (windowed, width, height))

    def test_explicit_window_dimensions_retain_bounds(self):
        for options in (["--width", "0"], ["--height", "619"], ["--width", "7681"]):
            with self.subTest(options=options), \
                    mock.patch.object(RUNNER, "run") as run, \
                    mock.patch.object(RUNNER.signal, "signal"), \
                    mock.patch.object(sys, "stderr", io.StringIO()), \
                    mock.patch.object(sys, "argv", [str(PATH), "--scenario", str(PATH), *options]):
                with self.assertRaises(SystemExit) as stopped:
                    RUNNER.main()
                self.assertEqual(stopped.exception.code, 2)
                run.assert_not_called()

    def test_display_lock_rejects_concurrent_native_scenarios(self):
        import fcntl
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lock_path = root / "build/native-verification/.display.lock"
            lock_path.parent.mkdir(parents=True)
            with lock_path.open("w") as lock, \
                    mock.patch.object(RUNNER, "ROOT", root), \
                    mock.patch.object(RUNNER, "run", return_value=0) as run, \
                    mock.patch.object(RUNNER.signal, "signal"), \
                    mock.patch.object(sys, "argv", [str(PATH), "--scenario", str(PATH)]), \
                    mock.patch.object(sys, "stderr", io.StringIO()) as error:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                with self.assertRaises(SystemExit) as stopped:
                    RUNNER.main()
                self.assertEqual(stopped.exception.code, 2)
                self.assertIn("Another native scenario owns the display", error.getvalue())
                run.assert_not_called()
                fcntl.flock(lock, fcntl.LOCK_UN)
                self.assertEqual(RUNNER.main(), 0)
                run.assert_called_once()

    def write_passing_evidence(self, artifacts):
        RUNNER.write_json(artifacts / "result.json", {
            "status": "passed", "requiredScreenshots": ["opening.png"],
        })
        RUNNER.write_json(artifacts / "startup.json", {
            "evidence": "native-qt-input",
            "window": {"platform": "xcb", "visible": True, "exposed": True},
        })
        RUNNER.write_json(artifacts / "audit-summary.json", {
            "evidence": "native-qt-input", "inputs": 1, "exitCode": 0,
            "failedInputs": 0, "artifactFailures": 0, "qmlWarnings": [],
        })
        (artifacts / "actions.jsonl").write_text(json.dumps({
            "action": "click", "accepted": True, "evidence": "native-qt-input", "sequence": 1,
        }) + "\n")
        (artifacts / "opening.png").write_bytes(base64.b64decode(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a"
            "Y9sAAAAASUVORK5CYII="))

    def test_exit_zero_requires_explicit_scenario_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts = Path(directory)
            process = subprocess.Popen(["true"])
            process.wait()
            self.assertEqual(RUNNER.seat_result(process, artifacts)["status"], "failed")
            (artifacts / "result.json").write_text('{"status":"passed"}')
            self.assertEqual(RUNNER.seat_result(process, artifacts)["status"], "failed")
            self.write_passing_evidence(artifacts)
            self.assertEqual(RUNNER.seat_result(process, artifacts)["status"], "passed")
            self.assertEqual(RUNNER.seat_result(process, artifacts, "hung")["status"], "failed")

    def test_pass_artifact_cannot_mask_process_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts = Path(directory)
            self.write_passing_evidence(artifacts)
            process = subprocess.Popen(["false"])
            process.wait()
            self.assertEqual(RUNNER.seat_result(process, artifacts)["status"], "failed")

    def test_all_native_evidence_files_are_required(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts = Path(directory)
            process = subprocess.Popen(["true"])
            process.wait()
            for name in ("startup.json", "audit-summary.json", "actions.jsonl", "opening.png"):
                with self.subTest(name=name):
                    self.write_passing_evidence(artifacts)
                    (artifacts / name).unlink()
                    self.assertEqual(RUNNER.seat_result(process, artifacts)["status"], "failed")

    def test_summary_failures_and_incomplete_native_window_cannot_pass(self):
        cases = [
            ("startup.json", "window", {"platform": "offscreen", "visible": True, "exposed": True}),
            ("startup.json", "window", {"platform": "minimal:foo", "visible": True, "exposed": True}),
            ("startup.json", "window", {"platform": "xcb", "visible": True, "exposed": False}),
            ("startup.json", "window", {"visible": True, "exposed": True}),
            ("audit-summary.json", "inputs", 0),
            ("audit-summary.json", "inputs", 2),
            ("audit-summary.json", "inputs", True),
            ("audit-summary.json", "exitCode", 4),
            ("audit-summary.json", "failedInputs", 1),
            ("audit-summary.json", "artifactFailures", 1),
            ("audit-summary.json", "artifactFailures", None),
            ("audit-summary.json", "qmlWarnings", ["Invalid binding"]),
            ("audit-summary.json", "qmlWarnings", None),
            ("audit-summary.json", "evidence", "fixture-setup"),
        ]
        with tempfile.TemporaryDirectory() as directory:
            artifacts = Path(directory)
            process = subprocess.Popen(["true"])
            process.wait()
            for name, field, value in cases:
                with self.subTest(name=name, field=field, value=value):
                    self.write_passing_evidence(artifacts)
                    data = json.loads((artifacts / name).read_text())
                    data[field] = value
                    RUNNER.write_json(artifacts / name, data)
                    self.assertEqual(RUNNER.seat_result(process, artifacts)["status"], "failed")

    def test_failed_truncated_or_fixture_input_trace_cannot_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts = Path(directory)
            process = subprocess.Popen(["true"])
            process.wait()
            for change in ({"accepted": False}, {"evidence": "fixture-setup"},
                           {"sequence": 2}, {"action": ""}, {"sequence": True}):
                with self.subTest(change=change):
                    self.write_passing_evidence(artifacts)
                    action = json.loads((artifacts / "actions.jsonl").read_text())
                    action.update(change)
                    (artifacts / "actions.jsonl").write_text(json.dumps(action) + "\n")
                    self.assertEqual(RUNNER.seat_result(process, artifacts)["status"], "failed")
            for contents in ("", "{", "null\n", "[]\n"):
                with self.subTest(contents=contents):
                    self.write_passing_evidence(artifacts)
                    (artifacts / "actions.jsonl").write_text(contents)
                    self.assertEqual(RUNNER.seat_result(process, artifacts)["status"], "failed")

    def test_screenshots_require_explicit_names_and_png_files(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts = Path(directory)
            process = subprocess.Popen(["true"])
            process.wait()
            for names in (None, [], "opening.png", ["../opening.png"], ["opening"], ["missing.png"]):
                with self.subTest(names=names):
                    self.write_passing_evidence(artifacts)
                    RUNNER.write_json(artifacts / "result.json", {
                        "status": "passed", "requiredScreenshots": names,
                    })
                    self.assertEqual(RUNNER.seat_result(process, artifacts)["status"], "failed")
            for contents in (b"", b"not a PNG", b"\x89PNG\r\n\x1a\n"):
                with self.subTest(contents=contents):
                    self.write_passing_evidence(artifacts)
                    (artifacts / "opening.png").write_bytes(contents)
                    self.assertEqual(RUNNER.seat_result(process, artifacts)["status"], "failed")
            self.write_passing_evidence(artifacts)
            screenshot = artifacts / "opening.png"
            screenshot.write_bytes(screenshot.read_bytes()[:24])
            self.assertEqual(RUNNER.seat_result(process, artifacts)["status"], "failed")

    def test_native_file_input_requires_owned_window_and_truthful_backend(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts = Path(directory)
            process = subprocess.Popen(["true"])
            process.wait()
            for backend in ("native-x11-input", "native-gtk-input"):
                dialog = {"pid": 123, "status": "passed", "matches": 1, "keys": 2,
                          "path": "/isolated/deck.txt",
                          "window": "0x123", "transientOwner": "0x100", "evidence": backend,
                          "events": [{"keyval": 1}, {"keyval": 2}],
                          "pointerEvents": [{"type": event, "target": "Open", "window": "0x124",
                                             "x": 50, "y": 10}
                                            for event in ("button-press", "button-release")],
                          "osInputRoutingVerified": False}
                changes = [{}, {"pid": 456}, {"matches": 0}, {"keys": 0}, {"status": "failed"},
                           {"window": ""}, {"transientOwner": ""}]
                if backend == "native-gtk-input":
                    changes.extend([{"osInputRoutingVerified": True}, {"events": []},
                                    {"evidence": "native-x11-input"}, {"pointerEvents": []},
                                    {"pointerEvents": [None, None]}, {"path": "/wrong/deck.txt"}])
                for change in changes:
                    with self.subTest(backend=backend, change=change):
                        self.write_passing_evidence(artifacts)
                        startup = json.loads((artifacts / "startup.json").read_text())
                        startup["pid"] = 123
                        RUNNER.write_json(artifacts / "startup.json", startup)
                        action = {"action": "chooseFile", "accepted": True,
                                  "dialogAccepted": True, "dialogClosed": True,
                                  "evidence": backend, "sequence": 1,
                                  "path": "/isolated/deck.txt",
                                  "selectedFile": "file:///isolated/deck.txt",
                                  "nativeDialog": {**dialog, **change}}
                        (artifacts / "actions.jsonl").write_text(json.dumps(action) + "\n")
                        self.assertEqual(RUNNER.seat_result(process, artifacts)["status"],
                                         "failed" if change else "passed")
                        if backend == "native-gtk-input" and not change:
                            for selected in ("file:///different.txt", "file://remote/isolated/deck.txt",
                                             "/isolated/deck.txt", 17):
                                action["selectedFile"] = selected
                                (artifacts / "actions.jsonl").write_text(json.dumps(action) + "\n")
                                self.assertEqual(RUNNER.seat_result(process, artifacts)["status"], "failed")

    def test_quick_file_input_requires_actual_acceptance_closure_and_exact_url(self):
        with tempfile.TemporaryDirectory() as directory:
            artifacts = Path(directory)
            process = subprocess.Popen(["true"])
            process.wait()
            base = {"action": "chooseFile", "accepted": True, "sequence": 1,
                    "evidence": "native-qt-input", "path": "/isolated/deck file.txt",
                    "selectedFile": "file:///isolated/deck%20file.txt",
                    "dialogAccepted": True, "dialogClosed": True}
            cases = [(None, None)] + [(field, value) for field in ("dialogAccepted", "dialogClosed")
                                      for value in (None, False, 1)]
            cases += [("selectedFile", value) for value in (None, "file:///wrong.txt",
                      "file://remote/isolated/deck%20file.txt", "/isolated/deck file.txt")]
            for field, value in cases:
                with self.subTest(field=field, value=value):
                    self.write_passing_evidence(artifacts)
                    action = dict(base)
                    if field:
                        if value is None: action.pop(field)
                        else: action[field] = value
                    (artifacts / "actions.jsonl").write_text(json.dumps(action) + "\n")
                    self.assertEqual(RUNNER.seat_result(process, artifacts)["status"],
                                     "failed" if field else "passed")

    def test_native_runtime_critical_cannot_be_hidden_by_pass_result(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            process = subprocess.Popen(["true"])
            process.wait()
            for stage in ("artifacts", "stage-2-artifacts"):
                artifacts = root / stage
                artifacts.mkdir()
                self.write_passing_evidence(artifacts)
                name = "client.log" if stage == "artifacts" else "stage-2-client.log"
                log = root / name
                log.write_text("Ordinary startup message\n")
                self.assertEqual(RUNNER.seat_result(process, artifacts)["status"], "passed")
                log.write_text("(test:123): Gtk-CRITICAL **: widget event failed\n")
                self.assertEqual(RUNNER.seat_result(process, artifacts)["status"], "failed")

    def test_fixture_copies_images_and_excludes_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source"
            source.mkdir()
            (source / "images").mkdir()
            image = source / "images/card.png"
            image.write_bytes(b"test-image")
            (source / "decks.json").write_text('{"imagePath":"@PROFILE@/images/card.png"}')
            (source / "resume.json").write_text('{"secret":"do not copy"}')
            (source / "settings.json").write_text('{"uiLanguage":"zh"}')
            profile = Path(directory) / "seat"
            destination = RUNNER.prepare_profile(profile, fixture=source)
            self.assertFalse((destination / "resume.json").exists())
            self.assertEqual(json.loads((destination / "settings.json").read_text())["uiLanguage"], "en")
            self.assertEqual(json.loads((destination / "decks.json").read_text())["imagePath"],
                             str(destination / "images/card.png"))
            (destination / "images/card.png").write_bytes(b"fault injection")
            self.assertEqual(image.read_bytes(), b"test-image")

    def test_fixture_rejects_links_to_live_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source"
            source.mkdir()
            (source / "images").symlink_to(Path(directory), target_is_directory=True)
            with self.assertRaises(ValueError):
                RUNNER.prepare_profile(Path(directory) / "seat", fixture=source)

    def test_downloads_and_restart_checkpoints_stay_in_the_test_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            profile = Path(directory) / "seat with spaces"
            destination = RUNNER.prepare_profile(profile)
            self.assertEqual((profile / "config/user-dirs.dirs").read_text(),
                             f'XDG_DOWNLOAD_DIR="{profile / "downloads"}"\n')
            initial = RUNNER.profile_checkpoint(profile)
            self.assertNotIn("cards.sqlite", initial["files"])
            self.assertEqual(initial["imageFiles"], 0)
            (destination / "decks.json").write_text('{"decks": []}')
            updated = RUNNER.profile_checkpoint(profile)
            self.assertIn("decks.json", updated["files"])
            self.assertEqual(initial["files"]["settings.json"], updated["files"]["settings.json"])

    def test_download_sealing_rejects_links_special_files_and_oversized_data(self):
        for kind in ("link", "fifo", "oversized", "empty"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                profile = root / "seat-1"
                RUNNER.prepare_profile(profile)
                artifacts = profile / "artifacts"
                artifacts.mkdir()
                archive = profile / "downloads/package.tar.gz"
                if kind == "link":
                    other = root / "other"
                    other.write_bytes(b"test")
                    archive.symlink_to(other)
                elif kind == "fifo":
                    import os
                    os.mkfifo(archive)
                else:
                    with archive.open("wb") as stream:
                        stream.truncate(1024 * 1024 * 1024 + 1 if kind == "oversized" else 0)
                result = {"scenario": "application-update", "status": "passed",
                          "downloadReady": True, "sawDownload": True, "downloadPath": str(archive)}
                RUNNER.write_json(artifacts / "result.json", result)
                with self.assertRaises(ValueError):
                    RUNNER.record_verified_download(artifacts, result, "run", 1, 1)
                self.assertFalse((artifacts / "download-evidence.json").exists())

    def test_cleanup_signals_only_owned_child(self):
        process = subprocess.Popen(["sleep", "60"], start_new_session=True)
        try:
            RUNNER.stop_owned(process)
            self.assertIsNotNone(process.poll())
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()


if __name__ == "__main__":
    unittest.main()
