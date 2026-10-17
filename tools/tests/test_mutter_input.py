# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import importlib.util
import json
import os
from pathlib import Path
import sys
import unittest
from unittest import mock

PATH = Path(__file__).resolve().parents[1] / "ui-automation/mutter-input.py"
SPEC = importlib.util.spec_from_file_location("mutter_input", PATH)
INPUT = importlib.util.module_from_spec(SPEC)
# These contract tests never connect to a desktop and do not require GNOME.
with mock.patch.dict(sys.modules, {"dbus": mock.Mock()}):
    SPEC.loader.exec_module(INPUT)


class MutterInputTests(unittest.TestCase):
    def test_rejects_foreign_requester_before_focus_or_device_input(self):
        desktop = object.__new__(INPUT.Desktop)
        desktop.pid, desktop.group = 123, True
        desktop.activate = mock.Mock()
        desktop.session = mock.Mock()
        with self.assertRaisesRegex(ValueError, "parent"):
            desktop.dispatch({"action": "key", "pid": 456, "window": 10, "dpr": 2, "key": 65})
        desktop.activate.assert_not_called()
        self.assertEqual(desktop.session.mock_calls, [])

    def test_window_ownership_is_not_inferred_from_a_caller_supplied_title(self):
        desktop = object.__new__(INPUT.Desktop)
        desktop.pid, desktop.window = 123, 10
        desktop.property = mock.Mock(return_value=456)
        with self.assertRaisesRegex(RuntimeError, "not owned"):
            desktop.owned()
        desktop.property.assert_called_once_with(10, "_NET_WM_PID")

    def test_an_already_active_window_does_not_queue_a_late_activation(self):
        desktop = object.__new__(INPUT.Desktop)
        desktop.owned, desktop.focused, desktop.x = mock.Mock(), mock.Mock(), mock.Mock()
        desktop.activate()
        desktop.focused.assert_called_once()
        self.assertEqual(desktop.x.mock_calls, [])

    def test_transient_dialog_chain_requires_ownership_at_every_level(self):
        desktop = object.__new__(INPUT.Desktop)
        desktop.pid = 123
        properties = {(10, "_NET_WM_PID"): 123, (20, "_NET_WM_PID"): 123,
                      (20, "WM_TRANSIENT_FOR"): 10, (30, "_NET_WM_PID"): 456,
                      (30, "WM_TRANSIENT_FOR"): 10, (40, "_NET_WM_PID"): 123}
        desktop.property = lambda window, name: properties.get((window, name))
        self.assertTrue(desktop.belongs_to(20, 10))
        self.assertFalse(desktop.belongs_to(30, 10))
        self.assertFalse(desktop.belongs_to(40, 10))
        properties[20, "WM_TRANSIENT_FOR"] = 20
        self.assertFalse(desktop.belongs_to(20, 10))

    def test_shortcuts_are_bounded_and_text_key_mapping_is_explicit(self):
        self.assertEqual(INPUT.qt_key(65, 0x04000000), (97, [0xffe3]))
        self.assertEqual(INPUT.qt_key(71, 0x08000000), (103, [0xffe9]))
        self.assertEqual(INPUT.qt_key(68, 0x0c000000), (100, [0xffe3, 0xffe9]))
        self.assertEqual(INPUT.qt_key(0x01000004, 0), (0xff0d, []))
        self.assertEqual(INPUT.qt_key(0x01000055, 0), (0xff67, []))
        self.assertEqual(INPUT.qt_key(0x01000039, 0x02000000), (0xffc7, [0xffe1]))
        for key, modifiers in [(65, 0x10000000), (65, 0x20000000), (0x01000030, 0)]:
            with self.subTest(key=key, modifiers=modifiers), self.assertRaises(ValueError):
                INPUT.qt_key(key, modifiers)

    def test_pointer_motion_uses_the_emulated_input_device(self):
        desktop = object.__new__(INPUT.Desktop)
        desktop.focused = mock.Mock()
        desktop.destination = mock.Mock(return_value=(200, 100))
        desktop.pointer = mock.Mock(side_effect=[(100, 60), (200, 100)])
        desktop.pid, desktop.window = 123, 10
        desktop.session = mock.Mock()
        desktop.pointer_channel = mock.Mock()
        desktop.move([10, 10], 2)
        desktop.pointer_channel.nudge.assert_called_once_with(50, 20)
        desktop.pointer_channel.pump.assert_called_once_with(.012)
        desktop.session.NotifyPointerMotionRelative.assert_not_called()

    def test_motion_checks_the_position_after_the_last_bounded_nudge(self):
        desktop = object.__new__(INPUT.Desktop)
        desktop.focused = mock.Mock()
        desktop.destination = mock.Mock(return_value=(200, 100))
        desktop.pointer = mock.Mock(side_effect=[(100, 60)] * 12 + [(200, 100)])
        desktop.pointer_channel = mock.Mock()
        desktop.pid, desktop.window = 123, 10
        desktop.move([10, 10], 2)
        self.assertEqual(desktop.pointer_channel.nudge.call_count, 12)

    def test_failed_motion_keeps_bounded_position_delta_and_destination_evidence(self):
        desktop = object.__new__(INPUT.Desktop)
        desktop.focused = mock.Mock()
        desktop.destination = mock.Mock(return_value=(200, 100))
        desktop.pointer = mock.Mock(return_value=(100, 60))
        desktop.pointer_channel = mock.Mock()
        desktop.pid, desktop.window = 123, 10
        with self.assertRaises(INPUT.PointerMotionError) as raised:
            desktop.move([10, 10], 2)
        evidence = raised.exception.diagnostics
        self.assertEqual(evidence["destination"], [200, 100])
        self.assertEqual(evidence["samples"][0]["pointer"], [100, 60])
        self.assertEqual(evidence["samples"][0]["relativeMotion"], [50, 20])
        self.assertEqual(evidence["samples"][-1]["remaining"], [100, 40])
        self.assertEqual(len(evidence["samples"]), 13)
        self.assertEqual(desktop.pointer_channel.nudge.call_count, 12)

    def test_motion_rechecks_ownership_and_focus_before_each_nudge(self):
        desktop = object.__new__(INPUT.Desktop)
        desktop.focused = mock.Mock(side_effect=[None, None, RuntimeError("foreign focus")])
        desktop.destination = mock.Mock(return_value=(200, 100))
        desktop.pointer = mock.Mock(return_value=(100, 60))
        desktop.pointer_channel = mock.Mock()
        desktop.pid, desktop.window = 123, 10
        with self.assertRaisesRegex(INPUT.PointerMotionError, "foreign focus"):
            desktop.move([10, 10], 2)
        desktop.pointer_channel.nudge.assert_called_once_with(50, 20)

    def test_pointer_motion_failure_receipt_retains_diagnostics(self):
        desktop = mock.Mock()
        desktop.dispatch.side_effect = INPUT.PointerMotionError(
            "not reached", {"destination": [200, 100], "samples": [{"pointer": [100, 60]}]})
        with mock.patch("builtins.print") as output:
            INPUT.reply(desktop, b'{"action":"hover"}')
        receipt = json.loads(output.call_args.args[0])
        self.assertEqual(receipt["status"], "failed")
        self.assertEqual(receipt["pointerMotion"], desktop.dispatch.side_effect.diagnostics)

    def test_failed_key_request_releases_pressed_modifiers(self):
        desktop = object.__new__(INPUT.Desktop)
        desktop.focused = mock.Mock()
        for modifiers in ([0xffe3], [0xffe3, 0xffe9]):
            with self.subTest(modifiers=modifiers):
                desktop.session = mock.Mock()
                desktop.session.NotifyKeyboardKeysym.side_effect = (
                    [None] * len(modifiers) + [RuntimeError("device closed")] + [None] * len(modifiers))
                with mock.patch.object(INPUT.dbus, "UInt32", side_effect=lambda value: value):
                    with self.assertRaisesRegex(RuntimeError, "device closed"):
                        desktop.key(97, modifiers)
                self.assertEqual(desktop.session.NotifyKeyboardKeysym.call_args_list,
                                 [mock.call(key, True) for key in modifiers] + [mock.call(97, True)]
                                 + [mock.call(key, False) for key in reversed(modifiers)])

    def test_desktop_start_failure_closes_the_display_lock_and_session(self):
        x = mock.Mock()
        x.XOpenDisplay.return_value = 42
        session = mock.Mock()
        session.Start.side_effect = RuntimeError("start failed")
        lock = mock.Mock()
        with mock.patch.object(INPUT.C, "CDLL", return_value=x), \
                mock.patch.object(INPUT.dbus, "Interface", return_value=session), \
                mock.patch.dict(os.environ, {"HEXPROOF_AUDIT_SHARED": "/test-only"}), \
                mock.patch("builtins.open", return_value=lock):
            with self.assertRaisesRegex(RuntimeError, "start failed"):
                INPUT.Desktop()
        session.Stop.assert_called_once()
        lock.close.assert_called_once()
        x.XCloseDisplay.assert_called_once_with(42)

    def test_session_stop_failure_does_not_leave_display_or_lock_open(self):
        desktop = object.__new__(INPUT.Desktop)
        desktop.pointer_channel, desktop.session, desktop.lock, desktop.x = (
            mock.Mock(), mock.Mock(), mock.Mock(), mock.Mock())
        desktop.display = 42
        channel, session, lock, x = (
            desktop.pointer_channel, desktop.session, desktop.lock, desktop.x)
        session.Stop.side_effect = RuntimeError("session already closed")
        with self.assertRaisesRegex(RuntimeError, "already closed"):
            desktop.close()
        channel.close.assert_called_once()
        lock.close.assert_called_once()
        x.XCloseDisplay.assert_called_once_with(42)
        desktop.close()
        x.XCloseDisplay.assert_called_once()

    def test_request_stream_handles_split_utf8_eis_events_and_unterminated_eof(self):
        desktop = mock.Mock()
        desktop.dispatch.side_effect = lambda request: {"text": request["text"]}
        desktop.pointer_channel.fileno.return_value = 20
        request = json.dumps({"action": "type", "text": "牌"}, ensure_ascii=False).encode()
        split = request.index("牌".encode()) + 1
        chunks = [request[:split], request[split:] + b"\n\n", request, b""]
        with mock.patch.object(INPUT, "Desktop", return_value=desktop), \
                mock.patch.object(INPUT.sys, "stdin") as stdin, \
                mock.patch.object(INPUT.select, "select", side_effect=[
                    ([20], [], []), ([10], [], []), ([10], [], []),
                    ([10, 20], [], []), ([10], [], [])]), \
                mock.patch.object(INPUT.os, "read", side_effect=chunks), \
                mock.patch("builtins.print") as output:
            stdin.fileno.return_value = 10
            INPUT.main()
        self.assertEqual(desktop.dispatch.call_args_list, [
            mock.call({"action": "type", "text": "牌"})] * 2)
        self.assertEqual(desktop.pointer_channel.pump.call_args_list, [mock.call(0)] * 2)
        self.assertEqual([json.loads(call.args[0]) for call in output.call_args_list], [
            {"action": "type", "text": "牌", "status": "passed"}] * 2)
        desktop.close.assert_called_once()

    def test_bad_record_is_rejected_without_losing_the_following_request(self):
        desktop = mock.Mock()
        desktop.dispatch.return_value = {}
        with mock.patch("builtins.print") as output:
            INPUT.reply(desktop, b'{"action":')
            INPUT.reply(desktop, b'{"action":"activate"}')
        self.assertEqual(json.loads(output.call_args_list[0].args[0])["status"], "failed")
        self.assertEqual(json.loads(output.call_args_list[1].args[0])["status"], "passed")
        desktop.dispatch.assert_called_once_with({"action": "activate"})


class EisPointerTests(unittest.TestCase):
    def channel(self):
        channel = object.__new__(INPUT.EisPointer)
        channel.ei, channel.devices, channel.device = 1, {}, None
        channel.emulating, channel.disconnected, channel.sequence = False, False, 1
        channel.frames_sent, channel.last_frame_time = 0, None
        channel.event_type = lambda event: event["kind"]
        channel.event_device = lambda event: event.get("device")
        channel.event_seat = lambda event: event.get("seat")
        channel.ref_device = mock.Mock(side_effect=lambda device: device)
        for name in ("seat_has", "device_has"):
            setattr(channel, name, mock.Mock(return_value=True))
        for name in ("bind_pointer", "unref_device", "start_emulating", "stop_emulating",
                     "motion", "frame", "now", "unref", "dispatch_events", "unref_event"):
            setattr(channel, name, mock.Mock())
        channel.get_fd = mock.Mock(return_value=20)
        channel.now.return_value = 123456
        channel.device_type = mock.Mock(return_value=1)
        channel.get_event = mock.Mock(return_value=None)
        return channel

    def event(self, channel, kind, device=11):
        channel.handle({"kind": kind, "device": device})

    def test_only_pointer_capability_is_bound_with_a_typed_null_sentinel(self):
        channel = self.channel()
        channel.handle({"kind": channel.SEAT_ADDED, "seat": 30})
        seat, capability, sentinel = channel.bind_pointer.call_args.args
        self.assertEqual(seat, 30)
        self.assertIsInstance(capability, INPUT.C.c_int)
        self.assertEqual(capability.value, channel.POINTER)
        self.assertIsInstance(sentinel, INPUT.C.c_void_p)
        self.assertIsNone(sentinel.value)
        channel.seat_has.return_value = False
        channel.handle({"kind": channel.SEAT_ADDED, "seat": 31})
        channel.bind_pointer.assert_called_once()

    def test_device_requires_resume_before_framed_motion(self):
        channel = self.channel()
        self.event(channel, channel.DEVICE_ADDED)
        self.assertFalse(channel.emulating)
        with mock.patch.object(channel, "wait_until_ready", side_effect=RuntimeError("paused")):
            with self.assertRaisesRegex(RuntimeError, "paused"):
                channel.nudge(5, 10)
        channel.motion.assert_not_called()
        self.event(channel, channel.RESUMED)
        channel.nudge(5, 10)
        channel.start_emulating.assert_called_once_with(11, 1)
        channel.motion.assert_called_once_with(11, 5.0, 10.0)
        channel.frame.assert_called_once_with(11, 123456)
        self.event(channel, channel.RESUMED)
        channel.start_emulating.assert_called_once()
        self.assertEqual(channel.diagnostics(), {
            "connected": True, "disconnected": False, "emulating": True,
            "pointerDevices": 1, "deviceType": 1,
            "framesSent": 1, "lastFrameTime": 123456})

    def test_removed_device_is_released_and_already_resumed_replacement_used(self):
        channel = self.channel()
        for device in (11, 22):
            self.event(channel, channel.DEVICE_ADDED, device)
            self.event(channel, channel.RESUMED, device)
        self.assertEqual(channel.device, 11)
        self.event(channel, channel.DEVICE_REMOVED)
        self.assertEqual(channel.device, 22)
        self.assertEqual(channel.start_emulating.call_args_list, [mock.call(11, 1), mock.call(22, 2)])
        channel.unref_device.assert_called_once_with(11)
        self.assertNotIn(11, channel.devices)
        channel.stop_emulating.assert_not_called()
        self.event(channel, channel.RESUMED, 11)
        self.assertEqual(channel.device, 22)

    def test_queued_pause_prevents_motion_until_a_new_resume(self):
        channel = self.channel()
        self.event(channel, channel.DEVICE_ADDED)
        self.event(channel, channel.RESUMED)
        channel.get_event.side_effect = [{"kind": channel.PAUSED, "device": 11}, None]
        with mock.patch.object(channel, "wait_until_ready", side_effect=RuntimeError("paused")):
            with self.assertRaisesRegex(RuntimeError, "paused"):
                channel.nudge(10, 20)
        channel.motion.assert_not_called()
        self.assertFalse(channel.emulating)
        self.event(channel, channel.RESUMED)
        self.assertEqual(channel.start_emulating.call_args_list, [mock.call(11, 1), mock.call(11, 2)])

    def test_disconnect_releases_event_before_context_and_does_not_emulate_stop(self):
        channel = self.channel()
        self.event(channel, channel.DEVICE_ADDED)
        self.event(channel, channel.RESUMED)
        disconnected = {"kind": channel.DISCONNECT}
        channel.get_event.side_effect = [disconnected]
        calls = mock.Mock()
        calls.attach_mock(channel.unref_event, "event")
        calls.attach_mock(channel.unref_device, "device")
        calls.attach_mock(channel.unref, "context")
        channel.pump(0)
        self.assertEqual(calls.mock_calls, [
            mock.call.event(disconnected), mock.call.device(11), mock.call.context(1)])
        self.assertEqual(channel.fileno(), -1)
        channel.stop_emulating.assert_not_called()
        with self.assertRaisesRegex(RuntimeError, "disconnected"):
            channel.nudge(10, 20)
        channel.motion.assert_not_called()
        channel.close()
        channel.unref.assert_called_once()

    def test_channel_close_releases_each_reference_once(self):
        channel = self.channel()
        for device in (11, 22):
            self.event(channel, channel.DEVICE_ADDED, device)
            self.event(channel, channel.RESUMED, device)
        channel.close()
        channel.close()
        channel.stop_emulating.assert_called_once_with(11)
        self.assertEqual(channel.unref_device.call_args_list, [mock.call(11), mock.call(22)])
        channel.unref.assert_called_once_with(1)
        self.assertFalse(channel.devices)

    def test_missing_library_closes_the_taken_socket(self):
        taken, other = os.pipe()
        try:
            with mock.patch.object(INPUT.C, "CDLL", side_effect=OSError("missing libei")):
                with self.assertRaisesRegex(OSError, "missing libei"):
                    INPUT.EisPointer(taken)
            with self.assertRaises(OSError):
                os.fstat(taken)
        finally:
            os.close(other)

    def test_failed_startup_closes_both_owned_socket_references(self):
        for failure in ("new_sender", "setup_fd", "resume"):
            with self.subTest(failure=failure):
                taken, other = os.pipe()
                lib, transferred = mock.Mock(), []
                lib.ei_new_sender.return_value = 0 if failure == "new_sender" else 42

                def setup(context, fd):
                    transferred.append(fd)
                    return -1 if failure == "setup_fd" else 0

                lib.ei_setup_backend_fd.side_effect = setup
                lib.ei_unref.side_effect = lambda context: [os.close(fd) for fd in transferred]
                try:
                    with mock.patch.object(INPUT.C, "CDLL", return_value=lib), \
                            mock.patch.object(INPUT.EisPointer, "wait_until_ready",
                                              side_effect=RuntimeError("resume failed")):
                        with self.assertRaises(RuntimeError):
                            INPUT.EisPointer(taken)
                    for fd in [taken, *transferred]:
                        with self.assertRaises(OSError):
                            os.fstat(fd)
                    if failure == "new_sender":
                        lib.ei_unref.assert_not_called()
                    else:
                        lib.ei_unref.assert_called_once_with(42)
                finally:
                    os.close(other)

    def test_lib_bindings_match_pointer_returns_and_variadic_fixed_argument(self):
        taken, other = os.pipe()
        lib, transferred = mock.Mock(), []
        lib.ei_new_sender.return_value = 42
        lib.ei_setup_backend_fd.side_effect = lambda context, fd: transferred.append(fd) or 0
        lib.ei_unref.side_effect = lambda context: [os.close(fd) for fd in transferred]
        try:
            with mock.patch.object(INPUT.C, "CDLL", return_value=lib), \
                    mock.patch.object(INPUT.EisPointer, "wait_until_ready"):
                channel = INPUT.EisPointer(taken)
            self.assertIs(lib.ei_unref.restype, INPUT.C.c_void_p)
            self.assertIs(lib.ei_event_unref.restype, INPUT.C.c_void_p)
            self.assertEqual(lib.ei_seat_bind_capabilities.argtypes, [INPUT.C.c_void_p])
            self.assertEqual(lib.ei_device_pointer_motion.argtypes,
                             [INPUT.C.c_void_p, INPUT.C.c_double, INPUT.C.c_double])
            self.assertEqual(lib.ei_device_frame.argtypes, [INPUT.C.c_void_p, INPUT.C.c_uint64])
            with self.assertRaises(OSError):
                os.fstat(taken)
            self.assertIsNotNone(os.fstat(transferred[0]))
            channel.close()
        finally:
            os.close(other)


if __name__ == "__main__":
    unittest.main()
