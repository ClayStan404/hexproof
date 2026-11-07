# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Own temporary Hyprland windows for the two-seat manual-match scenario."""

import json
from pathlib import Path
import re
import shutil
import subprocess
import time

PROC = Path("/proc")


def read_json(path):
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    if not isinstance(value, dict):
        raise ValueError(f"Expected an object in {path.name}")
    return value


def write_json(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def lua_string(value):
    """Quote UTF-8 without JSON's Lua-incompatible Unicode escapes."""
    return '"' + "".join(
        "\\\\" if char == "\\" else '\\"' if char == '"'
        else f"\\{ord(char):03d}" if ord(char) < 32 or ord(char) == 127 else char
        for char in value) + '"'


class HyprlandManualMatch:
    # Each handoff is after a completed input burst, at a scenario barrier.
    # Keep this contract beside manual-match.qml's display-state acknowledgments.
    PHASES = ((1, "seated1"), (2, "ready"), (1, "opened1"), (2, "opened2"),
              (1, "played1"), (2, "played2"), (1, "result1"), (2, "returned2"),
              (1, "passed"), (2, "passed"))

    def __init__(self, output, run_id, binary):
        if not re.fullmatch(r"[0-9a-f]{32}", run_id):
            raise ValueError("Hyprland control requires the native runner's unique run ID")
        self.output = Path(output).resolve()
        self.shared = self.output / "shared"
        self.run_id = run_id
        self.binary = Path(binary).resolve(strict=True)
        self.hyprctl = shutil.which("hyprctl")
        if not self.hyprctl:
            raise ValueError("Hyprland control requires the installed hyprctl command")
        self.seats = {}
        self.windows = {}
        self.ready = set()
        self.initial_focus = None
        self.phase = 0
        self.turn = 0
        self.token = 0
        self.workspaces = {seat: f"hexproof-native-{run_id}-{seat}" for seat in (1, 2)}
        self.original_workspace = self._json("activeworkspace")["name"]
        if not isinstance(self.original_workspace, str) or not self.original_workspace:
            raise ValueError("Hyprland did not report an active workspace")
        monitors = self._json("monitors")
        write_json(self.output / "hyprland-environment.json", {
            "runId": run_id, "version": self._json("version"),
            "originalWorkspace": self.original_workspace,
            "temporaryWorkspaces": self.workspaces,
            "monitors": [{key: monitor.get(key) for key in
                          ("name", "width", "height", "x", "y", "scale", "focused")}
                         for monitor in monitors],
        })

    def _call(self, *arguments):
        try:
            result = subprocess.run([self.hyprctl, *arguments], capture_output=True,
                                    text=True, timeout=3, check=False)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise RuntimeError(f"Hyprland command failed: {error}") from error
        if result.returncode:
            detail = (result.stderr or result.stdout).strip()
            raise RuntimeError(f"Hyprland {arguments[0]} failed: {detail}")
        return result.stdout.strip()

    def _json(self, command):
        return json.loads(self._call("-j", command))

    def _dispatch(self, expression, seat=None):
        event = {"monotonicMs": round(time.monotonic() * 1000), "expression": expression}
        if seat is not None:
            event.update(seat=seat, **self.windows[seat])
        try:
            result = self._call("dispatch", expression)
            if result != "ok":
                raise RuntimeError(f"Hyprland dispatcher rejected the operation: {result}")
            event["status"] = "passed"
        except RuntimeError as error:
            event.update(status="failed", reason=str(error))
            raise
        finally:
            with (self.output / "hyprland-actions.jsonl").open("a", encoding="utf-8") as log:
                log.write(json.dumps(event) + "\n")

    def start(self, stage_seats):
        if self.seats or len(stage_seats) != 2:
            raise ValueError("Hyprland control supports one two-seat manual-match stage")
        for seat, (process, artifacts, _) in enumerate(stage_seats, 1):
            artifacts = Path(artifacts).resolve()
            if artifacts != self.output / f"seat-{seat}" / "artifacts":
                raise ValueError("Hyprland seat artifacts must belong to this run")
            self.seats[seat] = (process, artifacts)
        write_json(self.shared / "display-turn.json", {"seat": 0, "token": 0})

    def _identity(self, seat):
        process, artifacts = self.seats[seat]
        if process.poll() is not None:
            raise RuntimeError(f"Seat {seat} exited before its window operation")
        directory = PROC / str(process.pid)
        try:
            executable = (directory / "exe").resolve(strict=True)
            environment = dict(entry.split(b"=", 1) for entry in
                               (directory / "environ").read_bytes().split(b"\0") if b"=" in entry)
        except OSError as error:
            raise RuntimeError(f"Cannot verify seat {seat} process ownership") from error
        expected = {b"HEXPROOF_TEST_PROFILE_ROOT": str(artifacts.parent).encode(),
                    b"HEXPROOF_AUDIT_RUN_ID": self.run_id.encode(),
                    b"HEXPROOF_AUDIT_SEAT": str(seat).encode()}
        if executable != self.binary or any(environment.get(key) != value for key, value in expected.items()):
            raise RuntimeError(f"Seat {seat} process identity does not match this native run")

    def _owned_window(self, seat, *, optional=False):
        self._identity(seat)
        process, _ = self.seats[seat]
        matches = [window for window in self._json("clients") if window.get("pid") == process.pid]
        if not matches and optional:
            return None
        if len(matches) != 1:
            raise RuntimeError(f"Seat {seat} requires exactly one owned native window")
        window = matches[0]
        address = window.get("address", "")
        if not re.fullmatch(r"0x[0-9a-f]+", address) or window.get("xwayland") is not False:
            raise RuntimeError(f"Seat {seat} does not have a valid native Wayland window")
        if seat in self.windows and self.windows[seat]["address"] != address:
            raise RuntimeError(f"Seat {seat} window identity changed during the run")
        return window

    def _window_dispatch(self, seat, operation):
        window = self._owned_window(seat)
        selector = lua_string("address:" + window["address"])
        self._dispatch(operation.replace("WINDOW", selector), seat)

    def _prepare(self, seat, window):
        process, _ = self.seats[seat]
        self.windows[seat] = {"pid": process.pid, "address": window["address"]}
        workspace = lua_string("name:" + self.workspaces[seat])
        self._window_dispatch(seat, "hl.dsp.window.move({workspace=" + workspace +
                              ",follow=false,window=WINDOW})")
        self._window_dispatch(seat, "hl.dsp.window.fullscreen_state({internal=1,client=1,"
                              "action='set',layout_aware=false,window=WINDOW})")

    def _startup_ready(self, seat):
        process, artifacts = self.seats[seat]
        startup = read_json(artifacts / "startup.json")
        if not startup:
            return False
        window = startup.get("window", {})
        if (startup.get("pid") != process.pid or startup.get("runId") != self.run_id
                or str(startup.get("seat")) != str(seat) or window.get("platform") != "wayland"
                or window.get("visibility") != 4 or window.get("windowMode") != "maximized"
                or window.get("requestedWindowMode") != "maximized"
                or window.get("exposed") is not True
                or window.get("width", 0) <= 0 or window.get("height", 0) <= 0):
            raise RuntimeError(f"Seat {seat} did not establish native maximized startup evidence")
        return True

    def _focus(self, seat):
        write_json(self.shared / "display-turn.json", {"seat": 0, "token": self.token})
        self._window_dispatch(seat, "hl.dsp.focus({window=WINDOW})")
        self.turn = seat

    def _grant(self):
        self._owned_window(self.turn)
        self.token += 1
        write_json(self.shared / "display-turn.json", {"seat": self.turn, "token": self.token})

    def _passed(self, seat):
        process, artifacts = self.seats[seat]
        return process.poll() == 0 and read_json(artifacts / "result.json").get("status") == "passed"

    def _phase_complete(self):
        seat, marker = self.PHASES[self.phase]
        if marker == "passed":
            return self._passed(seat)
        if marker == "ready":
            state = read_json(self.seats[seat][1] / "display-state.json")
            return state.get("step", -1) >= 8
        return read_json(self.shared / (marker + ".json")).get("ready") is True

    def poll(self):
        if not self.seats:
            raise RuntimeError("Hyprland control was not started")
        for seat in self.seats:
            if seat not in self.windows:
                window = self._owned_window(seat, optional=True)
                if window:
                    self._prepare(seat, window)
        if len(self.ready) < 2:
            for seat in self.windows:
                if self._startup_ready(seat):
                    self.ready.add(seat)
            pending = sorted(set(self.windows) - self.ready)
            if pending and self.initial_focus != pending[0]:
                self.initial_focus = pending[0]
                self._window_dispatch(pending[0], "hl.dsp.focus({window=WINDOW})")
            if len(self.ready) == 2:
                self._focus(self.PHASES[0][0])
                self._grant()
            return
        if self.phase >= len(self.PHASES):
            return
        acknowledgment = read_json(self.seats[self.turn][1] / "display-state.json")
        if not (acknowledgment.get("token") == self.token and acknowledgment.get("busy") is False
                or self._passed(self.turn)):
            return
        if self._phase_complete():
            self.phase += 1
            if self.phase == len(self.PHASES):
                return
            self._focus(self.PHASES[self.phase][0])
        # The final timer stops before the process has necessarily exited.
        # Wait for exit/readback instead of granting another unacknowledgeable tick.
        process, artifacts = self.seats[self.turn]
        if read_json(artifacts / "result.json").get("status") != "passed":
            self._grant()

    def finish(self):
        """Called after the runner has stopped/reaped its children; never kill here."""
        errors = []
        result = {"remainingProcesses": [], "remainingWindows": [],
                  "remainingTemporaryWorkspaces": [], "restoredWorkspace": False}
        try:
            write_json(self.shared / "display-turn.json", {"seat": 0, "token": self.token})
            active = self._json("activeworkspace").get("name")
            if active in self.workspaces.values():
                workspace = self.original_workspace
                selector = workspace if workspace.isdigit() else "name:" + workspace
                self._dispatch("hl.dsp.focus({workspace=" + lua_string(selector) + "})")
                if self._json("activeworkspace").get("name") != workspace:
                    raise RuntimeError("Hyprland did not restore the original workspace")
                result["restoredWorkspace"] = True
        except (OSError, RuntimeError, ValueError, KeyError) as error:
            errors.append(str(error))
        # Read each resource independently so restoration failure cannot hide
        # leaked windows/workspaces or skip the cleanup receipt.
        for process, _ in self.seats.values():
            if process.poll() is None:
                result["remainingProcesses"].append(process.pid)
        owned_pids = {process.pid for process, _ in self.seats.values()}
        try:
            result["remainingWindows"] = [
                {"pid": window.get("pid"), "address": window.get("address")}
                for window in self._json("clients") if window.get("pid") in owned_pids]
        except (RuntimeError, ValueError) as error:
            errors.append(str(error))
        try:
            result["remainingTemporaryWorkspaces"] = [
                workspace["name"] for workspace in self._json("workspaces")
                if workspace.get("name") in self.workspaces.values()]
        except (RuntimeError, ValueError) as error:
            errors.append(str(error))
        if any(result[key] for key in ("remainingProcesses", "remainingWindows", "remainingTemporaryWorkspaces")):
            errors.append("Owned Hyprland test resources remain after process cleanup")
        result.update(status="failed" if errors else "passed", reason="; ".join(errors) or None,
                      runId=self.run_id, phasesCompleted=self.phase)
        write_json(self.output / "hyprland-cleanup.json", result)
        return result
