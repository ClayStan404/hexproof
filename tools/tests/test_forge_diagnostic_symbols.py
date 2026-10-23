# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Check bounded-code symbol extraction and pinned public-name generation."""

import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("forge_diagnostic_symbols", ROOT / "third_party/forge-runtime/diagnostic-symbols.py")
SYMBOLS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SYMBOLS)


def class_file(name, methods, enums=()):
    """Minimal structural class fixture; no Java compiler is required for tool tests."""
    entries = []
    def utf(text):
        encoded = text.encode()
        entries.append(b"\x01" + len(encoded).to_bytes(2, "big") + encoded)
        return len(entries)
    name_id = utf(name)
    entries.append(b"\x07" + name_id.to_bytes(2, "big"))
    class_id = len(entries)
    descriptor = utf("()V")
    method_ids = [utf(method) for method in methods]
    enum_ids = [utf(value) for value in enums]
    num = lambda value: value.to_bytes(2, "big")
    result = b"\xca\xfe\xba\xbe\x00\x00\x00\x41" + num(len(entries) + 1) + b"".join(entries)
    result += num(0x21) + num(class_id) + num(0) + num(0) + num(len(enum_ids))
    for index in enum_ids:
        result += num(0x4019) + num(index) + num(descriptor) + num(0)
    result += num(len(method_ids))
    for index in method_ids:
        result += num(1) + num(index) + num(descriptor) + num(0)
    return result + num(0)


class DiagnosticSymbolTests(unittest.TestCase):
    def test_code_methods_enum_names_and_source_faces_are_deterministic(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            classes, cards = root / "classes", root / "cards"
            classes.mkdir(); cards.mkdir()
            (classes / "Adapter.class").write_bytes(class_file("org/hexproof/forge/Adapter", ["capture", "<init>"]))
            (cards / "double.txt").write_text("Name:Public Front\nALTERNATE\nName:Public Back\nSVar:PrivateScript\n")
            aliases = root / "aliases.tsv"
            aliases.write_text("# reviewed aliases\nCatalog Front // Catalog Back\tSET\t1\tSET\t2\n")
            jar = root / "forge.jar"
            with zipfile.ZipFile(jar, "w") as archive:
                archive.writestr("forge/game/ability/ApiType.class", class_file("forge/game/ability/ApiType", ["values"], ["Draw", "Damage"]))
                archive.writestr("dependency/Secret.class", class_file("dependency/Secret", ["private"]));
            data = SYMBOLS.generate(classes, [jar], cards, aliases, "fixture-adapter31")
            value = json.loads(data)
            self.assertEqual(value["classes"]["org.hexproof.forge.Adapter"], ["<init>", "capture"])
            self.assertEqual(value["apis"], ["Damage", "Draw"])
            self.assertEqual(value["cardNames"], ["Catalog Back", "Catalog Front", "Public Back", "Public Front"])
            self.assertNotIn(b"PrivateScript", data)
            self.assertNotIn("dependency.Secret", value["classes"])
            self.assertEqual(data, SYMBOLS.generate(classes, [jar], cards, aliases, "fixture-adapter31"))

    def test_embedded_hub_index_matches_pinned_runtime_identity_and_digest(self):
        pin = json.loads((ROOT / "third_party/forge-runtime/native-host/upstream.json").read_text())
        data = (ROOT / "apps/server/internal/forgediag/diagnostic-symbols.json").read_bytes()
        self.assertEqual(hashlib.sha256(data).hexdigest(), pin["diagnosticSymbolsSha256"])
        index = json.loads(data)
        self.assertEqual(index["runtimeId"], f"{pin['revision']}-adapter{pin['adapterRevision']}")
        self.assertIn("resolveApiAbilityObserved", index["classes"]["forge.game.ability.AbilityUtils"])
        self.assertIn("Lightning Bolt", index["cardNames"])

    def test_malformed_class_fails_generation_instead_of_trusting_text(self):
        with self.assertRaises(ValueError):
            SYMBOLS.ClassReader(b"forge.game.Card\nprivate").read()
        with self.assertRaises(ValueError):
            SYMBOLS.ClassReader(class_file("forge/Test", ["run"])[:-8]).read()


if __name__ == "__main__":
    unittest.main()
