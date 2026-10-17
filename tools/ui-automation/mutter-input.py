#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Owned-window GNOME system input for hexproof_native_audit (JSON lines).

Mutter injects virtual device events through the compositor. Xlib only resolves
and activates the requesting audit process's XWayland window; it never sends
application keyboard or mouse events. The client separately verifies receipt.
"""

import ctypes as C
from contextlib import suppress
import fcntl
import json
import math
import os
from pathlib import Path
import select
import sys
import time

import dbus


class ClientData(C.Union):
    _fields_ = [("b", C.c_char * 20), ("s", C.c_short * 10), ("l", C.c_long * 5)]


class ClientMessage(C.Structure):
    _fields_ = [("type", C.c_int), ("serial", C.c_ulong), ("send_event", C.c_int),
                ("display", C.c_void_p), ("window", C.c_ulong), ("message_type", C.c_ulong),
                ("format", C.c_int), ("data", ClientData)]


class XEvent(C.Union):
    _fields_ = [("client", ClientMessage), ("pad", C.c_long * 24)]


class PointerMotionError(RuntimeError):
    def __init__(self, message, diagnostics):
        super().__init__(message)
        self.diagnostics = diagnostics


class EisPointer:
    """Relative pointer on the Mutter remote-desktop session's EIS socket.

    NotifyPointerMotionRelative can return success without moving the X
    pointer. The same session's emulated-input device does move it.
    """

    POINTER = 1
    SEAT_ADDED = 3
    DEVICE_ADDED = 5
    DEVICE_REMOVED = 6
    DISCONNECT = 2
    PAUSED = 7
    RESUMED = 8

    def __init__(self, fd):
        # The dbus UnixFd is taken by the caller. Until setup_backend_fd takes
        # ownership, this constructor must close it on every failure path.
        self.ei = None
        self.devices = {}
        self.device = None
        self.emulating = False
        self.sequence = 1
        self.disconnected = False
        self.frames_sent = 0
        self.last_frame_time = None
        try:
            self.lib = C.CDLL("libei.so.1")
            self.configure(fd)
            fd = None
            self.wait_until_ready(2)
        except Exception:
            self.close()
            raise
        finally:
            if fd is not None:
                os.close(fd)

    def configure(self, fd):

        def bind(name, result, *arguments):
            function = getattr(self.lib, name)
            function.restype, function.argtypes = result, list(arguments)
            return function

        self.new_sender = bind("ei_new_sender", C.c_void_p, C.c_void_p)
        self.configure_name = bind("ei_configure_name", None, C.c_void_p, C.c_char_p)
        self.setup_fd = bind("ei_setup_backend_fd", C.c_int, C.c_void_p, C.c_int)
        self.get_fd = bind("ei_get_fd", C.c_int, C.c_void_p)
        self.dispatch_events = bind("ei_dispatch", None, C.c_void_p)
        self.get_event = bind("ei_get_event", C.c_void_p, C.c_void_p)
        self.unref_event = bind("ei_event_unref", C.c_void_p, C.c_void_p)
        self.event_type = bind("ei_event_get_type", C.c_int, C.c_void_p)
        self.event_seat = bind("ei_event_get_seat", C.c_void_p, C.c_void_p)
        self.event_device = bind("ei_event_get_device", C.c_void_p, C.c_void_p)
        self.seat_has = bind("ei_seat_has_capability", C.c_bool, C.c_void_p, C.c_int)
        self.device_has = bind("ei_device_has_capability", C.c_bool, C.c_void_p, C.c_int)
        self.device_type = bind("ei_device_get_type", C.c_int, C.c_void_p)
        self.ref_device = bind("ei_device_ref", C.c_void_p, C.c_void_p)
        self.unref_device = bind("ei_device_unref", C.c_void_p, C.c_void_p)
        self.start_emulating = bind("ei_device_start_emulating", None, C.c_void_p, C.c_uint32)
        self.stop_emulating = bind("ei_device_stop_emulating", None, C.c_void_p)
        self.motion = bind("ei_device_pointer_motion", None, C.c_void_p, C.c_double, C.c_double)
        self.frame = bind("ei_device_frame", None, C.c_void_p, C.c_uint64)
        self.now = bind("ei_now", C.c_uint64, C.c_void_p)
        self.unref = bind("ei_unref", C.c_void_p, C.c_void_p)
        self.log_priority = bind("ei_log_set_priority", None, C.c_void_p, C.c_int)
        # Declare only the fixed argument of this variadic API. The enum and
        # NULL sentinel are passed explicitly as C types at the call site.
        self.bind_pointer = bind("ei_seat_bind_capabilities", None, C.c_void_p)
        self.ei = self.new_sender(None)
        if not self.ei:
            raise RuntimeError("Cannot create an emulated input client")
        if os.environ.get("HEXPROOF_AUDIT_EI_DEBUG") == "1":
            self.log_priority(self.ei, 10)
        self.configure_name(self.ei, b"hexproof-system-input")
        # libei owns its duplicate once setup_backend_fd is called, including
        # when setup returns a negative errno. Keep the original owned here.
        if self.setup_fd(self.ei, os.dup(fd)) < 0:
            raise RuntimeError("Cannot connect the emulated input client")
        os.close(fd)

    def fileno(self):
        if not self.ei:
            return -1
        return self.get_fd(self.ei)

    def pump(self, timeout):
        if not self.ei:
            return
        fd = self.fileno()
        if fd >= 0 and timeout:
            select.select([fd], [], [], timeout)
        if fd >= 0:
            self.dispatch_events(self.ei)
        while True:
            event = self.get_event(self.ei)
            if not event:
                break
            try:
                self.handle(event)
            finally:
                self.unref_event(event)
            if self.disconnected:
                self.close()
                break

    def handle(self, event):
        kind = self.event_type(event)
        if kind == self.SEAT_ADDED:
            seat = self.event_seat(event)
            if seat and self.seat_has(seat, self.POINTER):
                self.bind_pointer(seat, C.c_int(self.POINTER), C.c_void_p())
        elif kind == self.DEVICE_ADDED:
            device = self.event_device(event)
            if device and device not in self.devices and self.device_has(device, self.POINTER):
                self.devices[self.ref_device(device)] = False
        elif kind in (self.RESUMED, self.PAUSED, self.DEVICE_REMOVED):
            device = self.event_device(event)
            if device not in self.devices:
                return
            if kind == self.RESUMED:
                self.devices[device] = True
            else:
                self.devices[device] = False
                if device == self.device:
                    # Pausing resets device state; removed-device events must
                    # never be sent. Neither case needs a stop request.
                    self.device, self.emulating = None, False
                if kind == self.DEVICE_REMOVED:
                    del self.devices[device]
                    self.unref_device(device)
            self.use_ready_device()
        elif kind == self.DISCONNECT:
            self.emulating = False
            self.disconnected = True

    def use_ready_device(self):
        if self.emulating or self.disconnected:
            return
        self.device = next((device for device, resumed in self.devices.items() if resumed), None)
        if self.device:
            self.start_emulating(self.device, self.sequence)
            self.sequence = (self.sequence + 1) & 0xffffffff
            self.emulating = True

    def wait_until_ready(self, seconds):
        deadline = time.monotonic() + seconds
        while self.ei and not self.emulating and not self.disconnected and time.monotonic() < deadline:
            self.pump(.05)
        if self.disconnected:
            raise RuntimeError("Emulated input disconnected before the pointer resumed")
        if not self.ei:
            raise RuntimeError("Emulated input channel is closed")
        if not self.emulating:
            raise RuntimeError("Emulated pointer did not resume")

    def nudge(self, dx, dy):
        # A pause/removal may already be queued while stdin became readable.
        self.pump(0)
        if not self.emulating:
            self.wait_until_ready(.5)
        self.motion(self.device, float(dx), float(dy))
        self.last_frame_time = self.now(self.ei)
        self.frame(self.device, self.last_frame_time)
        self.frames_sent += 1
        self.pump(0)

    def diagnostics(self):
        return {"connected": bool(self.ei), "disconnected": self.disconnected,
                "emulating": self.emulating, "pointerDevices": len(self.devices),
                "deviceType": self.device_type(self.device) if self.device else None,
                "framesSent": self.frames_sent, "lastFrameTime": self.last_frame_time}

    def close(self):
        if self.device and self.emulating and not self.disconnected:
            self.stop_emulating(self.device)
        self.emulating = False
        self.device = None
        for device in self.devices:
            self.unref_device(device)
        self.devices.clear()
        if self.ei:
            self.unref(self.ei)
            self.ei = None


class Desktop:
    def __init__(self):
        self.x = C.CDLL("libX11.so.6")
        signatures = {
            "XOpenDisplay": (C.c_void_p, [C.c_char_p]),
            "XDefaultRootWindow": (C.c_ulong, [C.c_void_p]),
            "XInternAtom": (C.c_ulong, [C.c_void_p, C.c_char_p, C.c_int]),
            "XGetWindowProperty": (C.c_int, [C.c_void_p, C.c_ulong, C.c_ulong, C.c_long,
                C.c_long, C.c_int, C.c_ulong, C.POINTER(C.c_ulong), C.POINTER(C.c_int),
                C.POINTER(C.c_ulong), C.POINTER(C.c_ulong), C.POINTER(C.c_void_p)]),
            "XGetGeometry": (C.c_int, [C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong),
                C.POINTER(C.c_int), C.POINTER(C.c_int), *[C.POINTER(C.c_uint)] * 4]),
            "XTranslateCoordinates": (C.c_int, [C.c_void_p, C.c_ulong, C.c_ulong,
                C.c_int, C.c_int, C.POINTER(C.c_int), C.POINTER(C.c_int), C.POINTER(C.c_ulong)]),
            "XQueryPointer": (C.c_int, [C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong),
                C.POINTER(C.c_ulong), *[C.POINTER(C.c_int)] * 4, C.POINTER(C.c_uint)]),
            "XGetInputFocus": (C.c_int, [C.c_void_p, C.POINTER(C.c_ulong), C.POINTER(C.c_int)]),
            "XSendEvent": (C.c_int, [C.c_void_p, C.c_ulong, C.c_int, C.c_long, C.POINTER(XEvent)]),
            "XRaiseWindow": (C.c_int, [C.c_void_p, C.c_ulong]),
            "XFlush": (C.c_int, [C.c_void_p]),
            "XFree": (C.c_int, [C.c_void_p]),
            "XCloseDisplay": (C.c_int, [C.c_void_p]),
        }
        for name, (result, arguments) in signatures.items():
            function = getattr(self.x, name)
            function.restype, function.argtypes = result, arguments
        self.display = self.x.XOpenDisplay(None)
        if not self.display:
            raise RuntimeError("An authenticated XWayland display is required")
        self.root = self.x.XDefaultRootWindow(self.display)
        self.pid = os.getppid()
        self.window = 0
        self.lock = None
        self.group = False
        self.session = None
        self.pointer_channel = None
        try:
            self.lock = open(Path(os.environ["HEXPROOF_AUDIT_SHARED"]) / "system-input.lock", "a")
            self.bus = dbus.SessionBus()
            destination = "org.gnome.Mutter.RemoteDesktop"
            path = self.bus.get_object(destination, "/org/gnome/Mutter/RemoteDesktop").CreateSession(
                dbus_interface=destination)
            self.session = dbus.Interface(self.bus.get_object(destination, path), destination + ".Session")
            self.session.Start()
            socket = self.session.ConnectToEIS(dbus.Dictionary({}, signature="sv"))
            self.pointer_channel = EisPointer(int(socket.take()))
        except Exception:
            with suppress(Exception):
                self.close()
            raise

    def atom(self, name):
        return self.x.XInternAtom(self.display, name.encode(), False)

    def property(self, window, name):
        kind, count, remaining, value = C.c_ulong(), C.c_ulong(), C.c_ulong(), C.c_void_p()
        bits = C.c_int()
        status = self.x.XGetWindowProperty(self.display, window, self.atom(name), 0, 1,
            False, 0, C.byref(kind), C.byref(bits), C.byref(count), C.byref(remaining), C.byref(value))
        try:
            if status != 0 or bits.value != 32 or count.value != 1 or remaining.value:
                return None
            return C.cast(value, C.POINTER(C.c_ulong))[0]
        finally:
            if value:
                self.x.XFree(value)

    def owned(self):
        if not self.window or self.property(self.window, "_NET_WM_PID") != self.pid:
            raise RuntimeError("Target window is not owned by the audit parent process")

    def focused(self):
        self.owned()
        focus, revert = C.c_ulong(), C.c_int()
        self.x.XGetInputFocus(self.display, C.byref(focus), C.byref(revert))
        active = self.property(self.root, "_NET_ACTIVE_WINDOW")
        if focus.value != self.window or active != self.window:
            raise RuntimeError(f"The compositor did not focus the owned audit window: expected={self.window}, focus={focus.value}, active={active}")

    def belongs_to(self, window, owner):
        seen = set()
        while window and window not in seen and len(seen) < 8:
            if self.property(window, "_NET_WM_PID") != self.pid:
                return False
            if window == owner:
                return True
            seen.add(window)
            window = self.property(window, "WM_TRANSIENT_FOR")
        return False

    def completed_focus(self, owner):
        # Opening or accepting a modal chooser changes focus during a valid
        # click. Input still starts on the exact requested window; only its
        # owned transient family is allowed as the resulting focus.
        focus, revert = C.c_ulong(), C.c_int()
        self.x.XGetInputFocus(self.display, C.byref(focus), C.byref(revert))
        active = self.property(self.root, "_NET_ACTIVE_WINDOW")
        if focus.value != active or not self.belongs_to(active, owner):
            raise RuntimeError("System input moved focus outside the owned window family")
        return active

    def activate(self):
        self.owned()
        try:
            self.focused()
            return
        except RuntimeError:
            pass
        event = XEvent()
        event.client.type, event.client.window = 33, self.window
        event.client.message_type, event.client.format = self.atom("_NET_ACTIVE_WINDOW"), 32
        event.client.data.l[0] = 2
        self.x.XSendEvent(self.display, self.root, False, (1 << 20) | (1 << 19), C.byref(event))
        self.x.XRaiseWindow(self.display, self.window)
        self.x.XFlush(self.display)
        stable = 0
        for _ in range(150):
            try:
                self.focused()
                stable += 1
                if stable >= 8:
                    return
            except RuntimeError:
                stable = 0
            time.sleep(.01)
        self.focused()
        raise RuntimeError("The owned window focus did not settle")

    def pointer(self):
        root, child, rx, ry, wx, wy, mask = C.c_ulong(), C.c_ulong(), C.c_int(), C.c_int(), C.c_int(), C.c_int(), C.c_uint()
        if not self.x.XQueryPointer(self.display, self.root, C.byref(root), C.byref(child),
                C.byref(rx), C.byref(ry), C.byref(wx), C.byref(wy), C.byref(mask)):
            raise RuntimeError("Cannot locate the system pointer")
        return rx.value, ry.value

    def destination(self, point, scale):
        if len(point) != 2 or not all(isinstance(n, (int, float)) and math.isfinite(n) for n in point):
            raise ValueError("Invalid pointer coordinates")
        root, x, y, width, height, border, depth = C.c_ulong(), C.c_int(), C.c_int(), C.c_uint(), C.c_uint(), C.c_uint(), C.c_uint()
        if not self.x.XGetGeometry(self.display, self.window, C.byref(root), C.byref(x), C.byref(y),
                C.byref(width), C.byref(height), C.byref(border), C.byref(depth)):
            raise RuntimeError("Cannot inspect the owned window geometry")
        px, py = [round(n * scale) for n in point]
        if not (0 <= px < width.value and 0 <= py < height.value):
            raise ValueError("Pointer destination is outside the owned window")
        child = C.c_ulong()
        self.x.XTranslateCoordinates(self.display, self.window, self.root, px, py,
            C.byref(x), C.byref(y), C.byref(child))
        return x.value, y.value

    def move(self, point, scale):
        self.focused()
        x, y = self.destination(point, scale)
        started = time.monotonic()
        samples = []
        diagnostics = {"destination": [x, y], "point": point, "dpr": scale,
                       "pid": self.pid, "window": self.window, "samples": samples}
        # Mutter coordinates are logical; XWayland geometry uses physical pixels.
        # Recheck actual pointer position after each compositor motion.
        try:
            for attempt in range(13):
                self.focused()
                px, py = self.pointer()
                sample = {"attempt": attempt, "pointer": [px, py],
                          "remaining": [x - px, y - py],
                          "elapsedMs": round((time.monotonic() - started) * 1000)}
                if isinstance(self.pointer_channel, EisPointer):
                    sample["channel"] = self.pointer_channel.diagnostics()
                samples.append(sample)
                if abs(x - px) <= 2 and abs(y - py) <= 2:
                    return
                if attempt == 12:
                    break
                dx, dy = (x - px) / scale, (y - py) / scale
                sample["relativeMotion"] = [dx, dy]
                self.pointer_channel.nudge(dx, dy)
                self.pointer_channel.pump(.012)
        except Exception as error:
            raise PointerMotionError(str(error), diagnostics) from error
        raise PointerMotionError("System pointer did not reach the owned window target", diagnostics)

    def key(self, symbol, modifiers=()):
        self.focused()
        held = []
        try:
            for modifier in modifiers:
                self.session.NotifyKeyboardKeysym(dbus.UInt32(modifier), True)
                held.append(modifier)
            self.session.NotifyKeyboardKeysym(dbus.UInt32(symbol), True)
            self.session.NotifyKeyboardKeysym(dbus.UInt32(symbol), False)
        finally:
            for modifier in reversed(held):
                self.session.NotifyKeyboardKeysym(dbus.UInt32(modifier), False)

    def dispatch(self, request):
        action = request["action"]
        if action == "begin":
            if self.group:
                raise RuntimeError("Nested system input group")
            fcntl.flock(self.lock, fcntl.LOCK_EX)
            self.group = True
            return {}
        if action == "end":
            self.group = False
            fcntl.flock(self.lock, fcntl.LOCK_UN)
            return {}
        if not self.group:
            fcntl.flock(self.lock, fcntl.LOCK_EX)
        try:
            if request["pid"] != self.pid:
                raise ValueError("The input requester must be the helper's parent")
            self.window = int(request["window"])
            owner = int(request.get("ownerWindow", self.window))
            if not self.belongs_to(self.window, owner):
                raise ValueError("Input window is not in the owned transient family")
            scale = request["dpr"]
            if not isinstance(scale, (int, float)) or not .5 <= scale <= 4:
                raise ValueError("Invalid display scale")
            self.activate()
            if action in ("click", "doubleClick", "rightClick", "hover", "wheel", "drag"):
                self.move(request["point"], scale)
            if action in ("click", "doubleClick", "rightClick"):
                for _ in range(2 if action == "doubleClick" else 1):
                    self.focused()
                    button = 273 if action == "rightClick" else 272
                    self.session.NotifyPointerButton(button, True)
                    try:
                        time.sleep(.03)
                    finally:
                        self.session.NotifyPointerButton(button, False)
                    time.sleep(.035)
            elif action == "key":
                symbol, modifiers = qt_key(request["key"], request.get("modifiers", 0))
                self.key(symbol, modifiers)
            elif action == "type":
                for character in request["text"]:
                    code = ord(character)
                    symbol = 0xff0d if character == "\n" else code if code < 256 else 0x01000000 | code
                    self.key(symbol)
            elif action == "wheel":
                delta = request["delta"]
                if not isinstance(delta, int) or not 0 < abs(delta) <= 2000:
                    raise ValueError("Invalid wheel delta")
                self.session.NotifyPointerAxisDiscrete(dbus.UInt32(0), -round(delta / 120))
            elif action == "drag":
                self.destination(request["end"], scale)
                self.session.NotifyPointerButton(272, True)
                try:
                    for step in range(1, 17):
                        self.move([a + (b - a) * step / 16 for a, b in zip(request["point"], request["end"])], scale)
                        time.sleep(.015)
                finally:
                    self.session.NotifyPointerButton(272, False)
            elif action not in ("activate", "hover"):
                raise ValueError("Unsupported system input action")
            focus_after = self.completed_focus(owner)
            return {"pid": self.pid, "window": self.window, "focusVerified": True,
                    "ownerWindow": owner, "focusAfter": focus_after,
                    "pointer": self.pointer(), "backend": "mutter-virtual-device"}
        finally:
            if not self.group:
                fcntl.flock(self.lock, fcntl.LOCK_UN)

    def close(self):
        try:
            if self.pointer_channel:
                channel, self.pointer_channel = self.pointer_channel, None
                channel.close()
        finally:
            try:
                if self.session:
                    session, self.session = self.session, None
                    session.Stop()
            finally:
                try:
                    if self.lock:
                        lock, self.lock = self.lock, None
                        lock.close()
                finally:
                    if self.display:
                        display, self.display = self.display, None
                        self.x.XCloseDisplay(display)


def qt_key(key, modifiers):
    symbols = {0x01000000: 0xff1b, 0x01000001: 0xff09, 0x01000003: 0xff08,
               0x01000004: 0xff0d, 0x01000005: 0xff0d, 0x01000007: 0xffff,
               0x01000010: 0xff50, 0x01000011: 0xff57, 0x01000012: 0xff51,
               0x01000013: 0xff52, 0x01000014: 0xff53, 0x01000015: 0xff54,
               0x01000016: 0xff55, 0x01000017: 0xff56,
               0x01000039: 0xffc7, 0x01000055: 0xff67}
    if 0x41 <= key <= 0x5a:
        symbol = key + 32
    elif 0x20 <= key <= 0x7e:
        symbol = key
    elif key in symbols:
        symbol = symbols[key]
    else:
        raise ValueError("Unsupported test key")
    if modifiers & ~0x0e000000:
        raise ValueError("Only Shift, Control and Alt modifiers are supported")
    return symbol, [symbol for mask, symbol in [(0x02000000, 0xffe1), (0x04000000, 0xffe3),
                                                (0x08000000, 0xffe9)] if modifiers & mask]


def reply(desktop, line):
    if not line.strip():
        return
    try:
        request = json.loads(line)
        result = desktop.dispatch(request)
        result.update(status="passed", action=request["action"])
    except Exception as error:
        result = {"status": "failed", "error": str(error)}
        if isinstance(error, PointerMotionError):
            result["pointerMotion"] = error.diagnostics
    print(json.dumps(result), flush=True)


def main():
    desktop = Desktop()
    pending = b""
    try:
        stdin = sys.stdin.fileno()
        while True:
            channel = desktop.pointer_channel.fileno()
            watch = [stdin] if channel < 0 else [stdin, channel]
            readable, _, _ = select.select(watch, [], [], 15)
            if channel in readable:
                desktop.pointer_channel.pump(0)
            if stdin not in readable:
                continue
            chunk = os.read(stdin, 65536)
            if not chunk:
                reply(desktop, pending)
                break
            # Decode complete records, since a read can split a UTF-8 character.
            pending += chunk
            while b"\n" in pending:
                line, pending = pending.split(b"\n", 1)
                reply(desktop, line)
    finally:
        desktop.close()


if __name__ == "__main__":
    main()
