# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Test WAN orchestration bounds and marker isolation without opening a GUI."""

import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

PATH = Path(__file__).resolve().parents[1] / "ui-automation/run-wan-native.py"
SPEC = importlib.util.spec_from_file_location("wan_native_runner", PATH)
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


@unittest.skipUnless(sys.platform in ("linux", "win32"), "Linux/Windows native orchestration")
class WANRunnerTests(unittest.TestCase):
    def config(self, root, seats=None):
        return dict(url="https://test.invalid", token="a" * 64, case="fixture-1",
                    seats=seats or [1, 3], variant="eldrazi",
                    **{name: str(root / name) for name in
                       ("output", "binary", "runtime", "catalog", "manifest")})

    def test_configuration_rejects_ambiguous_or_unbounded_runs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "config.json"
            valid = self.config(root)
            path.write_text(json.dumps(valid))
            self.assertEqual(RUNNER.load_config(path), valid)
            for key, value in [("url", "http://test.invalid"), ("url", "https://@test.invalid"),
                               ("url", "https://test.invalid/path"), ("token", "short"),
                               ("case", "../private"), ("seats", [1, 2]), ("seats", [3]),
                               ("runtime", "relative"), ("timeout", 99999),
                               ("migration", "unsupported"), ("peer", "false"),
                               ("peerExpected", "anything"), ("peerExpected", "relay")]:
                with self.subTest(key=key, value=value):
                    path.write_text(json.dumps(dict(valid, **{key: value})))
                    with self.assertRaises(ValueError):
                        RUNNER.load_config(path)

    def test_blocked_candidate_scenario_requires_explicit_peer_consent(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "config.json"
            valid = dict(self.config(root), peer=True, peerExpected="relay")
            path.write_text(json.dumps(valid))
            self.assertEqual(RUNNER.load_config(path), valid)

    def test_owner_uploads_only_named_markers_and_changed_values(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "forge-room.json").write_text('{"roomId":"test-room"}')
            (root / "settings.json").write_text('{"credential":"must-stay-local"}')
            coordination = RUNNER.Coordination(self.config(root), root)
            with mock.patch.object(coordination, "request", return_value=None) as request:
                coordination.update()
                coordination.update()
                writes = [call for call in request.call_args_list if len(call.args) == 2]
                self.assertEqual(writes, [mock.call("forge-room", {"roomId": "test-room"})])
                (root / "forge-room.json").write_text('{"roomId":"next-room"}')
                coordination.update()
                self.assertEqual(request.call_args_list[-1],
                                 mock.call("forge-room", {"roomId": "next-room"}))

    def test_guest_receives_markers_without_uploading_profiles(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            coordination = RUNNER.Coordination(self.config(root, [2]), root)
            with mock.patch.object(coordination, "request", side_effect=lambda key:
                                   {"started": True} if key == "forge-migration" else None) as request:
                coordination.update()
                self.assertEqual(json.loads((root / "forge-migration.json").read_text()),
                                 {"started": True})
                self.assertTrue(all(len(call.args) == 1 for call in request.call_args_list))
                self.assertEqual([p.name for p in root.iterdir()], ["forge-migration.json"])

    def test_remote_failure_stops_instead_of_waiting_out_the_game(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            coordination = RUNNER.Coordination(self.config(root), root)
            with mock.patch.object(coordination, "request", return_value={"status": "failed"}):
                with self.assertRaisesRegex(RuntimeError, "Remote native participant failed"):
                    coordination.update()

    def test_record_bounds_apply_before_upload_and_after_download(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            coordination = RUNNER.Coordination(self.config(root), root)
            with mock.patch.object(coordination.opener, "open") as opened:
                with self.assertRaises(ValueError):
                    coordination.request("forge-room", {"oversized": "x" * 65536})
                opened.assert_not_called()
                response = opened.return_value.__enter__.return_value
                response.status = 200
                response.read.return_value = b"x" * 65537
                with self.assertRaises(ValueError):
                    coordination.request("forge-room")

    def test_display_lock_is_released_after_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "display.lock"
            with self.assertRaisesRegex(RuntimeError, "fixture"):
                with RUNNER.display_lock(path):
                    raise RuntimeError("fixture")
            with RUNNER.display_lock(path):
                self.assertTrue(path.is_file())

    def test_packaged_identity_requires_the_recorded_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with mock.patch.object(RUNNER.NATIVE, "ROOT", root):
                (root / "source-commit.txt").write_text("a" * 40 + "\n", encoding="ascii")
                self.assertEqual(RUNNER.source_identity()["commit"], "a" * 40)
                (root / "source-commit.txt").write_text("unknown", encoding="ascii")
                with self.assertRaises(ValueError):
                    RUNNER.source_identity()


if __name__ == "__main__":
    unittest.main()
