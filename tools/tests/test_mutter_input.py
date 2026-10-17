# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import importlib.util
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
        for key, modifiers in [(65, 0x10000000), (65, 0x20000000), (0x01000030, 0)]:
            with self.subTest(key=key, modifiers=modifiers), self.assertRaises(ValueError):
                INPUT.qt_key(key, modifiers)

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


if __name__ == "__main__":
    unittest.main()
