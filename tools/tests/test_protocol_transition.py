#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("protocol_transition", ROOT / "deploy/deploy-home-release.py")
RELEASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RELEASE)


class ProtocolTransitionTests(unittest.TestCase):
    def test_legacy_binary_is_identified_by_cli_not_application_version(self):
        result = subprocess.CompletedProcess([], 0, "", "  -version\n    print version\n")
        with patch.object(RELEASE.INSTALL, "run", return_value=result) as run:
            self.assertEqual(RELEASE.INSTALL.binary_protocol(Path("/verified/hub")), "hexproof.v1")
        run.assert_called_once_with("/verified/hub", "-h", check=False)

    def test_explicit_protocol_is_required_when_new_cli_supports_it(self):
        help_result = subprocess.CompletedProcess([], 0, "", "  -protocol\n    print protocol\n")
        for output, accepted in [("hexproof.v2\n", True), ("hexproof.v02", False), ("", False)]:
            with self.subTest(output=output), patch.object(RELEASE.INSTALL, "run", side_effect=[
                    help_result, subprocess.CompletedProcess([], 0, output, "")]):
                if accepted:
                    self.assertEqual(RELEASE.INSTALL.binary_protocol(Path("/verified/hub")), "hexproof.v2")
                else:
                    with self.assertRaises(ValueError):
                        RELEASE.INSTALL.binary_protocol(Path("/verified/hub"))

    def test_old_node_room_preflight_uses_its_inspected_protocol(self):
        sent = []

        class Socket:
            def send(self, kind, request, payload):
                sent.append((kind, payload))

            def until(self, kind):
                return {"v": "hexproof.v1", "serverVersion": "3.0.0"} if kind == "session.welcome" else {"rooms": []}

            def close(self):
                pass

        with patch.object(RELEASE, "inspect", return_value={"protocol": "hexproof.v1"}), \
                patch.object(RELEASE.SMOKE, "WebSocket", return_value=Socket()), \
                patch.object(RELEASE, "ssh", return_value=""):
            RELEASE.assert_idle({"ssh": "fixture", "endpoint": "wss://fixture.invalid/ws"}, "3.0.0")
        self.assertEqual(sent[0][1]["protocol"], "hexproof.v1")
        self.assertEqual(sent[1][0], "room.list")


if __name__ == "__main__":
    unittest.main()
