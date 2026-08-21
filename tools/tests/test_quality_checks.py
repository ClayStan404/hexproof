#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# SPDX-FileCopyrightText: 2026 Hexproof contributors

from __future__ import annotations

import importlib
import importlib.util
import tempfile
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parents[1]


def load_tool(filename: str, module_name: str):
    spec = importlib.util.spec_from_file_location(module_name, TOOLS_DIR / filename)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {filename}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


protocol = load_tool("check-protocol-parity.py", "check_protocol_parity")
protocol_codegen = load_tool("protocol_codegen.py", "protocol_codegen")
payload_schema = importlib.import_module("payload_schema")
payload_go_structs = importlib.import_module("payload_go_structs")
i18n = load_tool("check-i18n.py", "check_i18n")


class ProtocolParityTests(unittest.TestCase):
    def test_generated_go_and_cpp_constants_match(self) -> None:
        constants = [
            protocol_codegen.WireConstant("ProtocolVersion", "hexproof.v1"),
            protocol_codegen.WireConstant("TypePing", "session.ping"),
        ]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            go = root / "wire_constants_generated.go"
            cpp = root / "WireConstantsGenerated.h"
            go.write_text(protocol_codegen.render_go(constants), encoding="utf-8")
            cpp.write_text(protocol_codegen.render_cpp(constants), encoding="utf-8")
            expected = {item.name: item.value for item in constants}
            self.assertEqual(protocol.parse_constants(go, protocol.GO_CONSTANT), expected)
            self.assertEqual(protocol.parse_constants(cpp, protocol.CPP_CONSTANT), expected)

    def test_manual_generated_constant_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            go = root / "apps/server/internal/protocol/protocol.go"
            cpp = root / "apps/client-qt/src/protocol/Message.h"
            go.parent.mkdir(parents=True)
            cpp.parent.mkdir(parents=True)
            go.write_text('const TypePing = "session.ping"\n', encoding="utf-8")
            cpp.write_text(
                'inline const QString kTypePing = QStringLiteral("session.ping");\n',
                encoding="utf-8",
            )
            self.assertEqual(
                protocol.manual_declarations(root, {"TypePing"}),
                [
                    "apps/server/internal/protocol/protocol.go manually redeclares generated "
                    "constant TypePing",
                    "apps/client-qt/src/protocol/Message.h manually redeclares generated "
                    "constant TypePing",
                ],
            )

    def test_core_payload_schema_matches_go_and_fixtures(self) -> None:
        root = TOOLS_DIR.parent
        constants = protocol_codegen.load_schema(root)
        message_types = {
            item.value for item in constants if item.name.startswith("Type")
        }
        schema = payload_schema.load_payload_schema(root, message_types)
        self.assertEqual(schema.protocol, "hexproof.v1")
        self.assertEqual(set(schema.messages), message_types - {"room.event"})
        self.assertIn("game.snapshot", schema.messages)
        self.assertIn("room.snapshot", schema.messages)
        self.assertIn("sideboard.completed", schema.messages)
        self.assertIn("replay.loaded", schema.messages)
        self.assertIn("game.attachment_set", schema.messages)
        self.assertIn("game.library_view_resolved", schema.messages)
        self.assertIn("game.said", schema.messages)
        self.assertIn("error", schema.messages)
        self.assertNotIn("room.event", schema.messages)
        self.assertEqual(payload_schema.verify_payload_fixtures(root, schema), [])
        self.assertEqual(payload_go_structs.verify_go_payload_structs(root, schema), [])
        self.assertEqual(payload_schema.verify_qt_payload_builders(root, schema), [])

    def test_go_struct_parser_keeps_inline_empty_structs_separate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "protocol.go"
            path.write_text(
                'package protocol\n\n'
                'type Empty struct{}\n\n'
                'type Reply struct {\n'
                '\tRoomID string `json:"roomId"`\n'
                '}\n',
                encoding="utf-8",
            )
            structs = payload_schema.parse_go_structs(path)
            self.assertEqual(structs["Empty"], {})
            self.assertEqual(structs["Reply"], {"roomId": ("string", False)})

    def test_go_package_struct_parser_reads_non_test_files(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "first.go").write_text(
                "package protocol\n\ntype First struct{}\n", encoding="utf-8"
            )
            (root / "second.go").write_text(
                'package protocol\n\ntype Second struct {\n'
                '\tRoomID string `json:"roomId"`\n'
                '}\n',
                encoding="utf-8",
            )
            (root / "ignored_test.go").write_text(
                "package protocol\n\ntype TestOnly struct{}\n", encoding="utf-8"
            )
            structs = payload_go_structs.parse_go_package_structs(root)
            self.assertEqual(structs["First"], {})
            self.assertEqual(structs["Second"], {"roomId": ("string", False)})
            self.assertNotIn("TestOnly", structs)

    def test_payload_number_accepts_coordinates_but_not_boolean(self) -> None:
        self.assertTrue(payload_schema._json_matches_type(0.25, "number"))
        self.assertTrue(payload_schema._json_matches_type(1, "number"))
        self.assertFalse(payload_schema._json_matches_type(True, "number"))

    def test_payload_validation_rejects_missing_and_unknown_fields(self) -> None:
        spec = payload_schema.ObjectSpec(
            name="Ready",
            go_type="PlayerReady",
            fields=(
                payload_schema.FieldSpec("ready", "boolean", True),
            ),
        )
        schema = payload_schema.PayloadSchema("hexproof.v1", {}, {})
        problems = payload_schema._validate_object(
            {"extra": True}, spec, schema, "player.ready.payload"
        )
        self.assertEqual(
            problems,
            [
                "player.ready.payload: unknown fields extra",
                "player.ready.payload.ready: required field is missing",
            ],
        )


class I18nAuditTests(unittest.TestCase):
    def test_catalog_messages_include_completed_translations(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "hexproof_zh_CN.ts"
            path.write_text(
                '<?xml version="1.0"?><TS><context><name>Main</name>'
                '<message><source>Hello</source><translation>你好</translation></message>'
                '</context></TS>',
                encoding="utf-8",
            )
            keys, duplicates, unfinished = i18n.catalog_messages(path)
            self.assertEqual(keys, {("Main", "Hello")})
            self.assertEqual(duplicates, [])
            self.assertEqual(unfinished, [])

    def test_unfinished_and_duplicate_messages_are_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "hexproof_zh_CN.ts"
            path.write_text(
                '<?xml version="1.0"?><TS><context><name>Main</name>'
                '<message><source>Hello</source>'
                '<translation type="unfinished"></translation></message>'
                '<message><source>Hello</source><translation>您好</translation></message>'
                '</context></TS>',
                encoding="utf-8",
            )
            _, duplicates, unfinished = i18n.catalog_messages(path)
            self.assertEqual(duplicates, [("Main", "Hello")])
            self.assertEqual(unfinished, [("Main", "Hello")])


class VerificationScriptTests(unittest.TestCase):
    def test_clang_format_is_limited_to_cpp_sources(self) -> None:
        script = (TOOLS_DIR / "verify.sh").read_text(encoding="utf-8")
        self.assertIn(
            "git clang-format --diff --extensions cpp,h",
            script,
        )

    def test_default_server_output_matches_local_run_command(self) -> None:
        script = (TOOLS_DIR / "verify.sh").read_text(encoding="utf-8")
        readme = (TOOLS_DIR.parent / "README.md").read_text(encoding="utf-8")
        self.assertIn(
            'server_binary="${HEXPROOF_SERVER_BINARY_PATH:-$repo_root/build/server/hexproof-server}"',
            script,
        )
        self.assertIn("./build/server/hexproof-server -bind", readme)

    def test_qml_text_safety_is_shared_by_local_and_ci_gates(self) -> None:
        paths = (
            TOOLS_DIR / "verify.sh",
            TOOLS_DIR.parent / ".github/workflows/ci.yml",
            TOOLS_DIR.parent / ".github/workflows/release.yml",
        )
        for path in paths:
            with self.subTest(path=path):
                self.assertIn(
                    "./tools/check-qml-text-safety.sh",
                    path.read_text(encoding="utf-8"),
                )

    def test_macos_signing_secrets_are_scoped_to_required_steps(self) -> None:
        workflow = (TOOLS_DIR.parent / ".github/workflows/release.yml").read_text(
            encoding="utf-8"
        )
        macos_job = workflow.split("  client-macos:\n", 1)[1].split(
            "\n  server:\n", 1
        )[0]
        job_configuration = macos_job.split("    steps:\n", 1)[0]
        self.assertNotIn("secrets.MACOS_", job_configuration)
        self.assertIn("      - name: Import signing certificate", macos_job)
        self.assertIn("      - name: Build package", macos_job)
        self.assertIn("MACOS_RELEASE_NOTARIZED:", workflow)


class CardServiceBoundaryTests(unittest.TestCase):
    @staticmethod
    def source(path: str) -> str:
        return (TOOLS_DIR.parent / path).read_text(encoding="utf-8")

    def test_catalog_disconnects_direct_replies_before_resolver_shutdown(self) -> None:
        text = self.source("apps/client-qt/src/services/CardCatalog.cpp")
        destructor = text.split("CardCatalog::~CardCatalog()", 1)[1].split(
            "bool CardCatalog::installed()", 1
        )[0]
        disconnect = destructor.index("disconnect(reply, nullptr, this, nullptr)")
        clear_jobs = destructor.index("m_directImageJobs.clear()")
        reset_resolver = destructor.index("m_cardResolver.reset()")
        self.assertLess(disconnect, reset_resolver)
        self.assertLess(clear_jobs, reset_resolver)
        self.assertNotIn("m_directImageJobs.contains(reply)", destructor)

    def test_mtgch_recovery_clears_confirmed_missing(self) -> None:
        policy = self.source("apps/client-qt/src/services/CardResolverPolicy.cpp")
        replies = self.source("apps/client-qt/src/services/CardResolverReplies.cpp")
        self.assertGreaterEqual(policy.count("m_currentConfirmedMissing = false;"), 2)
        self.assertGreaterEqual(replies.count("m_currentConfirmedMissing = false;"), 2)

    def test_table_uses_model_revisions_instead_of_json_serialization(self) -> None:
        table = self.source("apps/client-qt/qml/screens/Table.qml")
        seat_state = self.source(
            "apps/client-qt/qml/components/BattlefieldSeatState.qml"
        )
        self.assertNotIn("JSON.stringify", table)
        self.assertNotIn("JSON.stringify", seat_state)
        self.assertIn("source.modelRevision", seat_state)
        model = self.source("apps/client-qt/src/models/GameTableModel.cpp")
        self.assertIn("m_cardsByZone", model)
        self.assertIn("modelRevision", model)

    def test_table_coordination_boundaries_are_extracted(self) -> None:
        table = self.source("apps/client-qt/qml/screens/Table.qml")
        self.assertIn("TableSelectionController", table)
        self.assertIn("TableBattlefieldGeometry", table)
        self.assertIn("TableOptimisticCommandController", table)
        self.assertIn("TableCardMoveController", table)
        self.assertIn("TableGameValueController", table)
        self.assertIn("TableZoneStateController", table)
        self.assertIn("BattlefieldSeatState", table)
        self.assertNotIn("const immutableOwner =", table)
        self.assertIn(
            "const immutableOwner =",
            self.source("apps/client-qt/qml/components/TableSelectionController.qml"),
        )
        optimistic = self.source(
            "apps/client-qt/qml/components/TableOptimisticCommandController.qml"
        )
        self.assertNotIn('commandType === "game.move_card"', table)
        self.assertIn('commandType === "game.move_card"', optimistic)
        self.assertIn("resetCounterCountRequest", optimistic)
        card_moves = self.source(
            "apps/client-qt/qml/components/TableCardMoveController.qml"
        )
        self.assertNotIn("const adjustedPosition =", table)
        self.assertIn("const adjustedPosition =", card_moves)
        self.assertIn("finishPublicZoneDrop", card_moves)
        self.assertIn("commitCardToBattlefield", card_moves)
        zone_state = self.source(
            "apps/client-qt/qml/components/TableZoneStateController.qml"
        )
        self.assertIn("function cardDataForId(cardId)", zone_state)
        self.assertIn("function reconcilePendingCardMoves()", zone_state)
        self.assertIn("function zoneDelegateModel(", zone_state)
        self.assertNotIn("gameTableModel.cardData(cardId)", table)
        self.assertIn("readonly property var zoneState: zoneStateController", table)
        self.assertLess(len(table.splitlines()), 3300)

    def test_core_qt_commands_match_payload_schema(self) -> None:
        root = TOOLS_DIR.parent
        constants = protocol_codegen.load_schema(root)
        message_types = {
            item.value for item in constants if item.name.startswith("Type")
        }
        schema = payload_schema.load_payload_schema(root, message_types)
        self.assertEqual(payload_schema.verify_qt_payload_builders(root, schema), [])

    def test_dynamic_quality_gates_cover_client_and_server_boundaries(self) -> None:
        cmake = self.source("apps/client-qt/CMakeLists.txt")
        ci = self.source(".github/workflows/ci.yml")
        self.assertIn("HEXPROOF_ENABLE_SANITIZERS", cmake)
        self.assertIn("-fsanitize=address,undefined", cmake)
        self.assertIn("Qt client (ASan and UBSan)", ci)
        self.assertIn("FuzzParseEnvelope", ci)
        self.assertIn("FuzzGameMoveSequencePreservesCards", ci)
        self.assertIn("FuzzDecodeRetainedRoom", ci)

    def test_ci_format_check_tolerates_rewritten_push_bases(self) -> None:
        ci = self.source(".github/workflows/ci.yml")
        self.assertIn("PUSH_BASE_SHA: ${{ github.event.before }}", ci)
        self.assertIn('git cat-file -e "$base^{commit}"', ci)
        self.assertIn("git rev-parse --verify --quiet HEAD^", ci)

    def test_retention_rejects_and_removes_invalid_archives(self) -> None:
        retention = self.source("apps/server/internal/server/retention.go")
        self.assertIn("decoder.Decode(&struct{}{})", retention)
        self.assertIn("validateRetainedRoom", retention)
        self.assertIn("remove invalid retained match", retention)


if __name__ == "__main__":
    unittest.main()
