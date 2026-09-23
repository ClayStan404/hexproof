#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Owned-window GNOME system input for hexproof_native_audit (JSON lines).

Mutter injects virtual device events through the compositor. Xlib only resolves
and activates the requesting audit process's XWayland window; it never sends
application keyboard or mouse events. The client separately verifies receipt.
"""

import ctypes as C
import fcntl
import json
import math
import os
from pathlib import Path
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
        self.lock = open(Path(os.environ["HEXPROOF_AUDIT_SHARED"]) / "system-input.lock", "a")
        self.group = False
        self.session = None
        self.bus = dbus.SessionBus()
        destination = "org.gnome.Mutter.RemoteDesktop"
        path = self.bus.get_object(destination, "/org/gnome/Mutter/RemoteDesktop").CreateSession(
            dbus_interface=destination)
        self.session = dbus.Interface(self.bus.get_object(destination, path), destination + ".Session")
        self.session.Start()

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
        # Mutter coordinates are logical; XWayland geometry uses physical pixels.
        # Recheck actual pointer position after each compositor motion.
        for _ in range(12):
            px, py = self.pointer()
            if abs(x - px) <= 2 and abs(y - py) <= 2:
                return
            self.session.NotifyPointerMotionRelative((x - px) / scale, (y - py) / scale)
            time.sleep(.012)
        raise RuntimeError("System pointer did not reach the owned window target")

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
        if self.session:
            self.session.Stop()
        self.lock.close()
        self.x.XCloseDisplay(self.display)


def qt_key(key, modifiers):
    symbols = {0x01000000: 0xff1b, 0x01000001: 0xff09, 0x01000003: 0xff08,
               0x01000004: 0xff0d, 0x01000005: 0xff0d, 0x01000007: 0xffff,
               0x01000010: 0xff50, 0x01000011: 0xff57, 0x01000012: 0xff51,
               0x01000013: 0xff52, 0x01000014: 0xff53, 0x01000015: 0xff54,
               0x01000016: 0xff55, 0x01000017: 0xff56}
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


def main():
    desktop = Desktop()
    try:
        for line in sys.stdin:
            try:
                request = json.loads(line)
                result = desktop.dispatch(request)
                result.update(status="passed", action=request["action"])
            except Exception as error:
                result = {"status": "failed", "error": str(error)}
            print(json.dumps(result), flush=True)
    finally:
        desktop.close()


if __name__ == "__main__":
    main()
