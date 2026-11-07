# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import ast
import importlib.util
import json
from pathlib import Path
import re
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock


PATH = Path(__file__).resolve().parents[1] / "ui-automation/hyprland.py"
SPEC = importlib.util.spec_from_file_location("hyprland_controller", PATH)
HYPRLAND = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HYPRLAND)


class FakeProcess:
    def __init__(self, pid):
        self.pid = pid
        self.returncode = None

    def poll(self):
        return self.returncode


class FakeHyprland:
    def __init__(self):
        self.original = "1"
        self.active = self.original
        self.windows = []
        self.dispatches = []
        self.fail_dispatch = None
        self.fail_read = None

    @staticmethod
    def field(expression, name):
        match = re.search(name + r'''\s*=\s*("(?:\\.|[^"])*"|'(?:\\.|[^'])*')''', expression)
        return ast.literal_eval(match.group(1)) if match else None

    def run(self, command, **_kwargs):
        args = command[1:]
        if args[0] == "dispatch":
            expression = args[1]
            self.dispatches.append(expression)
            if self.fail_dispatch and self.fail_dispatch in expression:
                return SimpleNamespace(returncode=7, stdout="dispatch rejected", stderr="")
            address = self.field(expression, "window")
            window = next((w for w in self.windows if "address:" + w["address"] == address), None)
            workspace = self.field(expression, "workspace")
            if "window.move(" in expression and window:
                window["workspace"] = {"name": workspace.removeprefix("name:")}
            elif "fullscreen_state(" in expression and window:
                window.update(fullscreen=1, fullscreenClient=1)
            elif "hl.dsp.focus(" in expression:
                if window:
                    self.active = window["workspace"]["name"]
                elif workspace is not None:
                    self.active = workspace.removeprefix("name:")
            return SimpleNamespace(returncode=0, stdout="ok\n", stderr="")
        operation = args[-1]
        if operation == self.fail_read:
            return SimpleNamespace(returncode=1, stdout="", stderr="compositor unavailable")
        values = {
            "version": {"version": "0.56.2", "tag": "v0.56.2"},
            "activeworkspace": {"name": self.active, "id": 1},
            "monitors": [{"name": "DP-test", "width": 3840, "height": 2160,
                          "x": 0, "y": 0, "scale": 2}],
            "clients": self.windows,
            "workspaces": [{"name": name} for name in sorted(
                {self.active, self.original, *(w["workspace"]["name"] for w in self.windows)})],
        }
        if operation not in values:
            raise AssertionError(f"Unexpected read-only command: {command}")
        return SimpleNamespace(returncode=0, stdout=json.dumps(values[operation]), stderr="")


class HyprlandControllerTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.output = self.root / "run"
        (self.output / "shared").mkdir(parents=True)
        self.binary = self.root / "native-client"
        self.binary.write_bytes(b"fixture binary")
        self.proc = self.root / "proc"
        self.proc.mkdir()
        self.run_id = "0123456789abcdef0123456789abcdef"
        self.hypr = FakeHyprland()
        self.processes = [FakeProcess(1001), FakeProcess(1002)]
        self.seats = []
        for seat, process in enumerate(self.processes, 1):
            artifacts = self.output / f"seat-{seat}/artifacts"
            artifacts.mkdir(parents=True)
            self.seats.append((process, artifacts, 0.0))
            process_dir = self.proc / str(process.pid)
            process_dir.mkdir()
            (process_dir / "exe").symlink_to(self.binary)
            self.environment(seat)
            self.hypr.windows.append({"pid": process.pid, "address": f"0x{seat}00",
                                      "workspace": {"name": self.hypr.original},
                                      "xwayland": False, "mapped": True,
                                      "hidden": False, "fullscreen": 0, "fullscreenClient": 0})
        for patcher in (mock.patch.object(HYPRLAND, "PROC", self.proc),
                        mock.patch.object(HYPRLAND.shutil, "which", return_value="/test/hyprctl"),
                        mock.patch.object(HYPRLAND.subprocess, "run", side_effect=self.hypr.run)):
            patcher.start()
            self.addCleanup(patcher.stop)

    def environment(self, seat, **overrides):
        values = {"HEXPROOF_TEST_PROFILE_ROOT": str(self.output / f"seat-{seat}"),
                  "HEXPROOF_AUDIT_RUN_ID": self.run_id,
                  "HEXPROOF_AUDIT_SEAT": str(seat), "QT_QPA_PLATFORM": "wayland"}
        values.update(overrides)
        (self.proc / str(self.processes[seat - 1].pid) / "environ").write_bytes(
            b"\0".join(f"{key}={value}".encode() for key, value in values.items()) + b"\0")

    @staticmethod
    def write(path, value):
        path.write_text(json.dumps(value))

    def artifact(self, seat, name):
        return self.seats[seat - 1][1] / (name + ".json")

    def controller(self):
        controller = HYPRLAND.HyprlandManualMatch(self.output, self.run_id, self.binary)
        controller.start(self.seats)
        return controller

    def startup(self, seat, **changes):
        window = {"platform": "wayland", "windowMode": "maximized", "visibility": 4,
                  "requestedWindowMode": "maximized", "exposed": True, "visible": True,
                  "active": True, "width": 1896, "height": 1030, "dpr": 2}
        window.update(changes)
        self.write(self.artifact(seat, "startup"), {
            "pid": self.processes[seat - 1].pid, "runId": self.run_id,
            "seat": str(seat), "window": window,
        })

    def turn(self):
        path = self.output / "shared/display-turn.json"
        return json.loads(path.read_text()) if path.exists() else {"seat": 0, "token": 0}

    def acknowledge(self, step=0, **changes):
        turn = self.turn()
        state = {"step": step, "busy": False, "token": turn["token"]}
        state.update(changes)
        self.write(self.artifact(turn["seat"], "display-state"), state)

    def ready(self):
        controller = self.controller()
        controller.poll()
        self.startup(1)
        controller.poll()
        self.startup(2)
        controller.poll()
        self.assertEqual(self.turn()["seat"], 1)
        self.assertGreater(self.turn()["token"], 0)
        return controller

    def stop_clients(self):
        for process in self.processes:
            process.returncode = 0
            directory = self.proc / str(process.pid)
            for path in directory.iterdir():
                path.unlink()
            directory.rmdir()
        self.hypr.windows = []

    def test_foreign_profile_and_duplicate_windows_are_not_controlled(self):
        self.environment(1, HEXPROOF_TEST_PROFILE_ROOT=str(self.root / "owner-profile"))
        with self.assertRaises((RuntimeError, ValueError)):
            controller = self.controller()
            controller.poll()
        self.assertEqual(self.hypr.dispatches, [])
        self.environment(1)
        duplicate = dict(self.hypr.windows[0], address="0x999")
        self.hypr.windows.append(duplicate)
        with self.assertRaises((RuntimeError, ValueError)):
            controller = self.controller()
            controller.poll()
        self.assertEqual(self.hypr.dispatches, [])

    def test_no_input_grants_before_both_geometry_proofs(self):
        controller = self.controller()
        controller.poll()
        self.assertEqual(self.turn()["seat"], 0)
        self.startup(1)
        controller.poll()
        self.assertEqual(self.turn()["seat"], 0)
        self.startup(2, windowMode="windowed", visibility=2)
        with self.assertRaises((RuntimeError, ValueError)):
            controller.poll()
        self.assertEqual(self.turn()["seat"], 0)

    def test_acknowledgement_prevents_focus_switch_during_input(self):
        controller = self.ready()
        first = self.turn()
        self.write(self.output / "shared/seated1.json", {"ready": True})
        actions = list(self.hypr.dispatches)
        controller.poll()
        self.assertEqual(self.turn(), first)
        self.assertEqual(self.hypr.dispatches, actions)
        self.acknowledge(token=first["token"] - 1)
        controller.poll()
        self.assertEqual(self.turn(), first)
        self.acknowledge(busy=True)
        controller.poll()
        self.assertEqual(self.turn(), first)
        self.acknowledge()
        controller.poll()
        self.assertEqual(self.turn()["seat"], 2)
        self.assertGreater(self.turn()["token"], first["token"])

    def test_stale_window_address_cannot_receive_focus(self):
        controller = self.ready()
        actions = list(self.hypr.dispatches)
        self.hypr.windows[1]["address"] = "0xbeef"
        self.write(self.output / "shared/seated1.json", {"ready": True})
        self.acknowledge()
        with self.assertRaises((RuntimeError, ValueError)):
            controller.poll()
        self.assertEqual(self.hypr.dispatches, actions)

    def test_identity_is_rechecked_before_focus(self):
        controller = self.ready()
        actions = list(self.hypr.dispatches)
        self.environment(2, HEXPROOF_AUDIT_RUN_ID="another-run")
        self.write(self.output / "shared/seated1.json", {"ready": True})
        self.acknowledge()
        with self.assertRaises((RuntimeError, ValueError)):
            controller.poll()
        self.assertEqual(self.hypr.dispatches, actions)

    def test_complete_barrier_schedule_and_acknowledged_exit(self):
        controller = self.ready()
        transitions = [(1, "seated1", 7), (2, None, 8), (1, "opened1", 9),
                       (2, "opened2", 9), (1, "played1", 12), (2, "played2", 12),
                       (1, "result1", 15), (2, "returned2", 17)]
        for seat, shared, step in transitions:
            with self.subTest(seat=seat, shared=shared):
                self.assertEqual(self.turn()["seat"], seat)
                if shared:
                    self.write(self.output / f"shared/{shared}.json", {"ready": True})
                self.acknowledge(step=step)
                controller.poll()
        self.assertEqual(self.turn()["seat"], 1)
        self.write(self.artifact(1, "result"), {"status": "passed"})
        self.processes[0].returncode = 0
        controller.poll()
        self.assertEqual(self.turn()["seat"], 2)
        self.write(self.artifact(2, "result"), {"status": "passed"})
        self.processes[1].returncode = 0
        controller.poll()
        actions = list(self.hypr.dispatches)
        controller.poll()
        self.assertEqual(self.hypr.dispatches, actions)

    def test_cleanup_restores_only_its_temporary_workspace(self):
        controller = self.ready()
        self.stop_clients()
        result = controller.finish()
        self.assertEqual(result["status"], "passed", result)
        self.assertEqual(self.hypr.active, self.hypr.original)
        self.assertIn("hl.dsp.focus(", self.hypr.dispatches[-1])
        self.assertEqual(json.loads((self.output / "hyprland-cleanup.json").read_text())["status"], "passed")

    def test_cleanup_preserves_user_selected_workspace(self):
        controller = self.ready()
        self.stop_clients()
        self.hypr.active = "owner-workspace"
        before = list(self.hypr.dispatches)
        result = controller.finish()
        self.assertEqual(result["status"], "passed", result)
        self.assertEqual(self.hypr.dispatches, before)
        self.assertEqual(self.hypr.active, "owner-workspace")

    def test_named_workspace_restoration_is_quoted_as_data(self):
        self.hypr.original = self.hypr.active = 'notes "quoted" \\ workspace'
        for window in self.hypr.windows:
            window["workspace"]["name"] = self.hypr.original
        controller = self.ready()
        self.stop_clients()
        result = controller.finish()
        self.assertEqual(result["status"], "passed", result)
        self.assertEqual(self.hypr.active, self.hypr.original)

    def test_cleanup_records_restoration_failure_and_remaining_resources(self):
        controller = self.ready()
        self.stop_clients()
        self.hypr.fail_dispatch = "hl.dsp.focus("
        result = controller.finish()
        self.assertEqual(result["status"], "failed")
        self.assertTrue(result["reason"])
        evidence = json.loads((self.output / "hyprland-cleanup.json").read_text())
        self.assertEqual(evidence["status"], "failed")
        self.assertTrue(evidence["reason"])

    def test_cleanup_cannot_pass_with_owned_processes_alive(self):
        controller = self.ready()
        result = controller.finish()
        self.assertEqual(result["status"], "failed")
        self.assertTrue(result["reason"])


if __name__ == "__main__":
    unittest.main()
