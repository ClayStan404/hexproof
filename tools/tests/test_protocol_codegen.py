#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1]


class ProtocolCodegenTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.write_json("protocol/v1/wire-schema.json", {
            "schemaVersion": 1, "protocol": "hexproof.v1", "constants": [
                {"name": "ProtocolVersion", "value": "hexproof.v1"},
                {"name": "TypePing", "value": "session.ping"},
            ],
        })
        self.write_json("protocol/v1/payload-schema.json", {
            "schemaVersion": 1, "protocol": "hexproof.v1", "definitions": [],
            "messages": [{"type": "session.ping", "goType": "Ping",
                          "direction": "clientToServer",
                          "fields": [{"name": "nonce", "type": "string", "required": True}]}],
        })
        self.write_json("testdata/protocol/v1/ping.json", {
            "type": "session.ping", "payload": {"nonce": "test"},
        })
        self.write("testdata/protocol/v1/README.md", "`ping.json`\n")
        self.write("apps/server/internal/protocol/protocol.go", "package protocol\n")
        # Exercise a payload declared outside protocol.go, independent of imports.
        self.payload = self.write("apps/server/internal/protocol/ping.go", """package protocol
type Ping struct {
    Nonce string `json:"nonce"`
}
""")
        self.write("apps/client-qt/src/protocol/Message.h", '#include "WireConstantsGenerated.h"\n')

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return path

    def write_json(self, name, content):
        return self.write(name, json.dumps(content))

    def run_tool(self, name, *args):
        return subprocess.run([sys.executable, str(TOOLS / name), "--root", str(self.root), *args],
                              capture_output=True, text=True, timeout=10)

    def test_generation_and_parity_validate_contract_without_inspecting_import_spelling(self):
        generated = self.run_tool("protocol_codegen.py")
        self.assertEqual(generated.returncode, 0, generated.stderr)
        # The checked source tree need not even contain the generator's source.
        checked = self.run_tool("check-protocol-parity.py")
        self.assertEqual(checked.returncode, 0, checked.stderr)
        self.assertEqual(self.run_tool("protocol_codegen.py", "--check").returncode, 0)

    def test_invalid_payload_anywhere_in_go_package_is_rejected_before_writing(self):
        self.assertEqual(self.run_tool("protocol_codegen.py").returncode, 0)
        outputs = [self.root / "apps/server/internal/protocol/wire_constants_generated.go",
                   self.root / "apps/client-qt/src/protocol/WireConstantsGenerated.h"]
        for output in outputs:
            output.write_text("preserve previous output\n")
        self.payload.write_text(self.payload.read_text().replace('json:"nonce"', 'json:"wrong"'))
        result = self.run_tool("protocol_codegen.py")
        self.assertEqual(result.returncode, 1)
        self.assertIn("missing JSON fields nonce", result.stderr)
        self.assertTrue(all(output.read_text() == "preserve previous output\n" for output in outputs))

    def test_invalid_fixture_does_not_create_outputs(self):
        self.write_json("testdata/protocol/v1/ping.json", {"type": "session.ping", "payload": {}})
        result = self.run_tool("protocol_codegen.py")
        self.assertEqual(result.returncode, 1)
        self.assertIn("required field is missing", result.stderr)
        self.assertFalse((self.root / "apps/client-qt/src/protocol/WireConstantsGenerated.h").exists())


if __name__ == "__main__":
    unittest.main()
