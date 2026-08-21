#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# SPDX-FileCopyrightText: 2026 Hexproof contributors

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class TableArchitectureTests(unittest.TestCase):
    @staticmethod
    def source(path: str) -> str:
        return (ROOT / path).read_text(encoding="utf-8")

    def test_table_is_an_assembly_shell(self) -> None:
        table = self.source("apps/client-qt/qml/screens/Table.qml")
        functions = re.findall(r"^\s*function\s+(\w+)\s*\(", table, re.MULTILINE)

        self.assertLess(len(table.splitlines()), 400)
        self.assertEqual(functions, [])
        self.assertIn("TableSceneShell", table)
        self.assertIn("TableRuntimeSyncController", table)
        self.assertIn("TableSeatStateController", table)
        self.assertIn("readonly property var cardMoveCommands", table)
        self.assertIn("readonly property var optimisticCommands", table)
        self.assertIn("readonly property var zoneState", table)
        self.assertIn("readonly property var seatState", table)

        for inline_view in (
            "BattlefieldView {",
            "TableHandArea {",
            "TableEditorPopups {",
            "TableDialogs {",
            "TableMenus {",
            "SideboardPanel {",
        ):
            self.assertNotIn(inline_view, table)

    def test_scene_shell_owns_views_and_modal_registry(self) -> None:
        shell = self.source("apps/client-qt/qml/components/TableSceneShell.qml")
        cmake = self.source("apps/client-qt/CMakeLists.txt")

        for component in (
            "TableGameLogRail",
            "SharedZonesView",
            "BattlefieldView",
            "TableHandArea",
            "TableOverlayLayer",
            "TableAttachmentStackLayer",
            "TableOpponentZonePanelLayer",
            "TableEditorPopups",
            "TableDialogs",
            "TableMenus",
            "TableSettingsPopup",
            "SideboardPanel",
            "TableShortcuts",
        ):
            self.assertIn(component, shell)

        self.assertIn("readonly property var modalPopups", shell)
        self.assertIn("readonly property bool modalOpen", shell)
        self.assertIn("qml/components/TableSceneShell.qml", cmake)
        self.assertIn("qml/components/TableSeatStateController.qml", cmake)

    def test_production_qml_does_not_call_removed_table_facades(self) -> None:
        removed = (
            "seatData",
            "zoneModelForSeat",
            "zoneCardsForSeat",
            "sharedZoneCards",
            "zoneCardCount",
            "zoneCardAt",
            "zoneDelegateModel",
            "modelCardCount",
            "finishHandDrag",
            "finishBattlefieldDrag",
            "syncDisplayedOwnHand",
            "visibleOwnHandCount",
            "displayedLife",
            "setLifeOptimistically",
            "displayedTapped",
            "hasTappedOwnPermanent",
            "untapOwnBattlefield",
            "displayedCounterValue",
            "setCounterOptimistically",
            "commanderCards",
            "displayedCommanderTax",
            "commanderTaxSummary",
            "commanderTaxDisplayName",
            "isCardPendingFrom",
            "beginPendingCardMove",
            "beginPendingCardMoves",
            "removePendingCardMove",
            "clearPendingCardMoves",
            "bindPendingCardMoveRequest",
            "rollbackPendingCardMove",
            "bindOptimisticValueRequest",
            "rollbackOptimisticValue",
            "clearOptimisticPhase",
            "trackQueuedCommand",
            "rollbackFailedCommand",
            "trackOptimisticValues",
            "cardInZone",
            "cardDataForId",
            "visibleZoneSeatForCard",
            "reconcilePendingCardMoves",
            "pendingBattlefieldMovesForSeat",
            "publicZoneCards",
            "displayedPublicZoneTopCard",
            "clearPendingLibraryApproval",
            "openSelectedCounterLabelEditor",
            "openSelectedCounterValueEditor",
            "counterShortcutBlocked",
            "showLibraryMoveCardsEditor",
            "toggleHandReveal",
            "handRevealTransitionPending",
            "openTableSettings",
            "setGameLogRailVisible",
            "applyTableSettings",
            "clearCounterSelection",
            "resetCounterCountRequest",
            "syncOwnCounterCount",
            "maybeShowGameResult",
            "syncBattlefieldSeats",
            "syncGameLog",
            "revealedCardsForSeat",
            "cardImageSource",
            "availableCardFaces",
            "tableCardImageSource",
            "prioritizeVisibleCards",
            "opponentZoneExpanded",
            "setOpponentZoneExpanded",
            "inspectCard",
            "hideCardPreview",
            "gameSummary",
            "matchScoreSummary",
            "moveSelectedBattlefieldToZone",
            "moveSelectedHandCard",
            "canMoveToHand",
            "moveDroppedCardToBattlefield",
            "clearPendingBattlefieldMove",
            "finishPublicZoneDrop",
            "moveCardToBattlefield",
        )
        qml_root = ROOT / "apps/client-qt/qml"
        problems: list[str] = []

        for path in qml_root.rglob("*.qml"):
            text = path.read_text(encoding="utf-8")
            for name in removed:
                pattern = rf"(?:tableRoot|tableController|\btable)\.{name}\s*\("
                if re.search(pattern, text):
                    problems.append(f"{path.relative_to(ROOT)} calls {name}")

        self.assertEqual(problems, [])

    def test_matchloading_exercises_controller_surface(self) -> None:
        test = self.source("apps/client-qt/tests/qml/tst_matchloading.qml")
        self.assertIn("table.cardMoveCommands.moveCardToBattlefield", test)
        self.assertIn("table.optimisticCommands.beginPendingCardMove", test)
        self.assertIn("table.gameValues.displayedTapped", test)
        self.assertIn("table.presentation.inspectCard", test)
        self.assertNotIn("table.moveCardToBattlefield(", test)
        self.assertNotIn("table.beginPendingCardMove(", test)

    def test_card_move_facade_delegates_battlefield_layout_policy(self) -> None:
        facade = self.source(
            "apps/client-qt/qml/components/TableCardMoveController.qml"
        )
        layout = self.source(
            "apps/client-qt/qml/components/TableBattlefieldLayoutController.qml"
        )
        cmake = self.source("apps/client-qt/CMakeLists.txt")

        self.assertLess(len(facade.splitlines()), 700)
        self.assertLess(len(layout.splitlines()), 700)
        self.assertIn("TableBattlefieldLayoutController", facade)
        self.assertIn("battlefieldLayout.smartBattlefieldPosition", facade)
        self.assertIn("function battlefieldCategory", layout)
        self.assertIn("function nonOverlappingBattlefieldPosition", layout)
        self.assertIn(
            "qml/components/TableBattlefieldLayoutController.qml", cmake
        )

    def test_battlefield_view_composes_bounded_region_components(self) -> None:
        view = self.source("apps/client-qt/qml/components/BattlefieldView.qml")
        shell = self.source("apps/client-qt/qml/components/TableSceneShell.qml")
        panel_layer = self.source(
            "apps/client-qt/qml/components/TableOpponentZonePanelLayer.qml"
        )
        card = self.source(
            "apps/client-qt/qml/components/BattlefieldCardDelegate.qml"
        )
        dock = self.source(
            "apps/client-qt/qml/components/BattlefieldOpponentZoneDock.qml"
        )

        self.assertLess(len(view.splitlines()), 700)
        self.assertLess(len(panel_layer.splitlines()), 700)
        self.assertLess(len(card.splitlines()), 700)
        self.assertLess(len(dock.splitlines()), 700)
        self.assertIn("BattlefieldCardDelegate", view)
        self.assertNotIn("BattlefieldOpponentZoneDock", view)
        self.assertIn("TableOpponentZonePanelLayer", shell)
        self.assertIn("BattlefieldOpponentZoneDock", panel_layer)
        self.assertIn("BattlefieldOpponentPublicZonePile", dock)
        self.assertNotIn("id: opponentGraveyardPile", view)

    def test_sideboard_panel_composes_zone_and_preview_components(self) -> None:
        panel = self.source("apps/client-qt/qml/components/SideboardPanel.qml")
        zone = self.source(
            "apps/client-qt/qml/components/SideboardZoneView.qml"
        )
        preview = self.source(
            "apps/client-qt/qml/components/SideboardPreviewLayer.qml"
        )

        self.assertLess(len(panel.splitlines()), 700)
        self.assertLess(len(zone.splitlines()), 700)
        self.assertLess(len(preview.splitlines()), 700)
        self.assertIn("SideboardZoneView", panel)
        self.assertIn("SideboardPreviewLayer", panel)
        self.assertIn("function syncCardModel", zone)
        self.assertIn("function finishDrag", preview)

    def test_library_search_composes_card_list_and_context_menu(self) -> None:
        popup = self.source(
            "apps/client-qt/qml/components/LibrarySearchPopup.qml"
        )
        card_list = self.source(
            "apps/client-qt/qml/components/LibrarySearchCardList.qml"
        )
        menu = self.source(
            "apps/client-qt/qml/components/LibrarySearchContextMenu.qml"
        )

        self.assertLess(len(popup.splitlines()), 700)
        self.assertLess(len(card_list.splitlines()), 700)
        self.assertLess(len(menu.splitlines()), 700)
        self.assertIn("LibrarySearchCardList", popup)
        self.assertIn("LibrarySearchContextMenu", popup)
        self.assertIn('objectName: "librarySearchCards"', card_list)
        self.assertIn('objectName: "libraryCardMenu"', menu)

    def test_tournament_lobby_composes_event_actions_and_score_editor(self) -> None:
        lobby = self.source("apps/client-qt/qml/screens/TournamentLobby.qml")
        event_desk = self.source(
            "apps/client-qt/qml/components/TournamentEventDesk.qml"
        )
        score_editor = self.source(
            "apps/client-qt/qml/components/TournamentScoreEditor.qml"
        )

        self.assertLess(len(lobby.splitlines()), 700)
        self.assertLess(len(event_desk.splitlines()), 700)
        self.assertLess(len(score_editor.splitlines()), 700)
        self.assertIn("TournamentEventDesk", lobby)
        self.assertIn("TournamentScoreEditor", lobby)
        self.assertIn("registerTournament", event_desk)
        self.assertIn("reportTournamentResult", score_editor)

    def test_public_zone_release_always_completes_qml_drop(self) -> None:
        pile = self.source(
            "apps/client-qt/qml/components/TableOwnPublicZonePile.qml"
        )
        release_handler = pile.split("onReleased: {", 1)[1].split(
            "Qt.callLater", 1
        )[0]

        self.assertIn("zoneDragCard.Drag.drop()", release_handler)
        self.assertNotIn("if (drag.active)", release_handler)

    def test_ci_runs_table_architecture_gate(self) -> None:
        for workflow in (".github/workflows/ci.yml", ".github/workflows/release.yml"):
            text = self.source(workflow)
            self.assertIn("tools.tests.test_table_architecture", text)

    def test_ci_races_tournament_package(self) -> None:
        text = self.source(".github/workflows/ci.yml")
        self.assertIn("go test -race ./internal/room ./internal/server ./internal/tournament", text)

    def test_settings_surfaces_preference_save_errors(self) -> None:
        settings = self.source("apps/client-qt/qml/screens/Settings.qml")
        self.assertIn("preferences.lastError", settings)


if __name__ == "__main__":
    unittest.main()
