#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# SPDX-FileCopyrightText: 2026 Hexproof contributors

from __future__ import annotations

import importlib
import importlib.util
import json
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
module_size = load_tool("check-module-size.py", "check_module_size")


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
    def test_module_size_distinguishes_qml_controllers_from_views(self) -> None:
        policy = {
            "defaults": {".qml": 1000},
            "pathRules": [
                {"glob": "apps/client-qt/qml/**/*Controller.qml", "limit": 700},
                {"glob": "apps/client-qt/qml/**/*Shortcuts.qml", "limit": 700},
            ],
            "overrides": {},
        }
        self.assertEqual(
            module_size.limit_for(
                "apps/client-qt/qml/components/TableCardMoveController.qml",
                ".qml",
                policy,
            ),
            700,
        )
        self.assertEqual(
            module_size.limit_for(
                "apps/client-qt/qml/components/TableGameShortcuts.qml",
                ".qml",
                policy,
            ),
            700,
        )
        self.assertEqual(
            module_size.limit_for(
                "apps/client-qt/qml/components/BattlefieldView.qml", ".qml", policy
            ),
            1000,
        )

    def test_module_size_policy_includes_test_sources(self) -> None:
        policy = json.loads(module_size.POLICY_PATH.read_text(encoding="utf-8"))
        excluded = policy.get("excludePrefixes", [])
        self.assertNotIn("apps/client-qt/tests/", excluded)
        self.assertNotIn("apps/server/", excluded)
        sources = {
            module_size.relative(path) for path in module_size.source_files(policy)
        }
        self.assertIn("apps/client-qt/tests/qml/tst_matchloading.qml", sources)
        self.assertIn("apps/server/internal/room/room_test.go", sources)

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

    def test_background_jobs_do_not_use_the_global_qt_thread_pool(self) -> None:
        source_root = TOOLS_DIR.parent / "apps/client-qt/src"
        offenders = []
        for path in source_root.rglob("*.cpp"):
            text = path.read_text(encoding="utf-8")
            if "QtConcurrent::run([" in text or "QtConcurrent::run(\n        [" in text:
                offenders.append(str(path.relative_to(TOOLS_DIR.parent)))
        self.assertEqual(offenders, [])

    def test_synchronous_deck_import_is_not_exposed_to_qml(self) -> None:
        header = (
            TOOLS_DIR.parent / "apps/client-qt/src/models/DeckLibraryModel.h"
        ).read_text(encoding="utf-8")
        self.assertIn(
            "bool importDeck(const QString &name, const QString &format, const QString &text);",
            header,
        )
        self.assertNotIn("Q_INVOKABLE bool importDeck(", header)

    def test_client_and_tests_share_domain_libraries(self) -> None:
        cmake = (TOOLS_DIR.parent / "apps/client-qt/CMakeLists.txt").read_text(
            encoding="utf-8"
        )
        for target in (
            "hexproof_deck_core",
            "hexproof_deck_library",
            "hexproof_session",
            "hexproof_table_models",
        ):
            self.assertIn(f"qt_add_library({target} STATIC", cmake)
        wsclient_test = cmake.split("qt_add_executable(hexproof_wsclient_test", 1)[
            1
        ].split("add_test(NAME wsclient", 1)[0]
        self.assertIn("hexproof_session", wsclient_test)
        self.assertNotIn("src/services/WsClient.cpp", wsclient_test)
        deck_test = cmake.split("qt_add_executable(hexproof_deck_test", 1)[1].split(
            "add_test(NAME deck", 1
        )[0]
        self.assertIn("hexproof_deck_library", deck_test)
        self.assertNotIn("src/models/DeckLibraryModel.cpp", deck_test)

    def test_macos_signing_secrets_are_scoped_to_required_steps(self) -> None:
        workflow = (TOOLS_DIR.parent / ".github/workflows/release.yml").read_text(
            encoding="utf-8"
        )
        macos_job = workflow.split("  client-macos:\n", 1)[1].split(
            "\n  server:\n", 1
        )[0]
        job_configuration = macos_job.split("    steps:\n", 1)[0]
        self.assertNotIn("secrets.MACOS_", job_configuration)
        self.assertIn(
            "          - arch: arm64\n            runner: macos-15",
            macos_job,
        )
        self.assertIn(
            "          - arch: x86_64\n            runner: macos-15-intel",
            macos_job,
        )
        self.assertIn("      - name: Import signing certificate", macos_job)
        self.assertIn("      - name: Build package", macos_job)
        self.assertIn("MACOS_RELEASE_NOTARIZED:", workflow)

    def test_release_includes_current_card_database(self) -> None:
        workflow = (TOOLS_DIR.parent / ".github/workflows/release.yml").read_text(
            encoding="utf-8"
        )
        database_job = workflow.split("  card-database:\n", 1)[1].split(
            "\n  assemble:\n", 1
        )[0]
        assemble_job = workflow.split("  assemble:\n", 1)[1]
        self.assertIn(
            "./tools/card-database-builder/build-latest.sh build/card-database",
            database_job,
        )
        self.assertIn(".schemaVersion == 10", database_job)
        self.assertIn(
            "build/card-database/release/hexproof-default-cards.sqlite.gz",
            database_job,
        )
        self.assertIn(
            "build/card-database/release/card-database-manifest.json",
            database_job,
        )
        self.assertIn("      - card-database", assemble_job)
        self.assertIn('! -name SHA256SUMS', assemble_job)
        self.assertIn('sha256sum "${assets[@]}" > SHA256SUMS', assemble_job)


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
        requests = self.source("apps/client-qt/src/services/CardResolverRequests.cpp")
        replies = self.source("apps/client-qt/src/services/CardResolverReplies.cpp")
        mtgch_english = requests.split("const auto beginMtgchEnglish", 1)[1].split(
            "if (m_currentProvider", 1
        )[0]
        mtgch_reply = replies.split("void CardResolver::applyMtgchJson", 1)[1].split(
            "void CardResolver::handleImageReply", 1
        )[0]
        self.assertIn("m_currentConfirmedMissing = false;", mtgch_english)
        self.assertGreaterEqual(
            mtgch_reply.count("m_currentConfirmedMissing = false;"), 2
        )

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
        self.assertIn(
            "client-sanitizers:\n"
            "    name: Qt client (ASan and UBSan)\n"
            "    if: github.event_name == 'workflow_dispatch'",
            ci,
        )
        self.assertIn(
            "client-platforms:\n"
            "    name: Qt client (${{ matrix.name }})\n"
            "    if: github.event_name == 'workflow_dispatch'",
            ci,
        )
        self.assertGreaterEqual(
            ci.count("if: github.event_name == 'workflow_dispatch'"), 4
        )
        self.assertIn("FuzzParseEnvelope", ci)
        self.assertIn("FuzzGameMoveSequencePreservesCards", ci)
        self.assertIn("FuzzDecodeRetainedRoom", ci)

    def test_ci_format_check_tolerates_rewritten_push_bases(self) -> None:
        ci = self.source(".github/workflows/ci.yml")
        self.assertIn("PUSH_BASE_SHA: ${{ github.event.before }}", ci)
        self.assertIn('git cat-file -e "$base^{commit}"', ci)
        self.assertIn("git rev-parse --verify --quiet HEAD^", ci)

    def test_ci_selects_build_scope_and_keeps_one_required_gate(self) -> None:
        ci = self.source(".github/workflows/ci.yml")
        changes = ci.split("  changes:\n", 1)[1].split("\n  quality:\n", 1)[0]
        server = ci.split("  server:\n", 1)[1].split("\n  client:\n", 1)[0]
        client = ci.split("  client:\n", 1)[1].split(
            "\n  client-sanitizers:\n", 1
        )[0]
        required = ci.split("  ci-required:\n", 1)[1]

        self.assertIn("apps/server/*|protocol/*|testdata/protocol/*", changes)
        self.assertIn(
            "apps/client-qt/*|apps/server/*|packaging/linux/*|protocol/*",
            changes,
        )
        self.assertIn("    needs: changes", server)
        self.assertIn("if: needs.changes.outputs.server == 'true'", server)
        self.assertIn("    needs: changes", client)
        self.assertIn("if: needs.changes.outputs.client == 'true'", client)
        self.assertIn("    name: CI required", required)
        self.assertIn("    if: always()", required)
        self.assertIn(
            'require_result "Quality" "$QUALITY_RESULT" "success"',
            required,
        )

    def test_tag_release_reuses_ci_for_the_exact_commit(self) -> None:
        release = self.source(".github/workflows/release.yml")
        gate = release.split("  quality-gate:\n", 1)[1].split(
            "\n  client-linux:\n", 1
        )[0]

        self.assertIn("      - name: Verify CI for tagged commit", gate)
        self.assertIn(
            "actions/workflows/ci.yml/runs?head_sha=${GITHUB_SHA}",
            gate,
        )
        self.assertIn(
            'select(.head_sha == $sha and .conclusion == "success")',
            gate,
        )
        self.assertIn('gh run watch "$run_id"', gate)
        self.assertIn(
            "      - name: Test server\n"
            "        if: github.event_name == 'workflow_dispatch'",
            gate,
        )
        self.assertIn(
            "      - name: Build and test client\n"
            "        if: github.event_name == 'workflow_dispatch'",
            gate,
        )

    def test_retention_rejects_and_removes_invalid_archives(self) -> None:
        retention = self.source("apps/server/internal/server/retention.go")
        self.assertIn("decoder.Decode(&struct{}{})", retention)
        self.assertIn("validateRetainedRoom", retention)
        self.assertIn("remove invalid retained match", retention)


if __name__ == "__main__":
    unittest.main()
