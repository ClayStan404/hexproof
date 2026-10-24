#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class TableArchitectureTests(unittest.TestCase):
    # Guard invalid APIs, transport ownership, and required resource/workflow wiring.
    @staticmethod
    def source(path: str) -> str:
        return (ROOT / path).read_text(encoding="utf-8")

    def test_scene_modal_registry_and_controller_resources_are_wired(self) -> None:
        shell = self.source("apps/client-qt/qml/components/TableSceneShell.qml")
        cmake = self.source("apps/client-qt/CMakeLists.txt")
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

    def test_deep_zone_views_do_not_send_transport_commands(self) -> None:
        shared = self.source("apps/client-qt/qml/components/SharedZonesView.qml")
        sideboard = self.source("apps/client-qt/qml/components/SideboardZoneView.qml")
        self.assertNotIn("tableController.wsModel.", shared)
        self.assertNotIn("wsModel.", sideboard)

    def test_public_zone_release_always_completes_qml_drop(self) -> None:
        pile = self.source(
            "apps/client-qt/qml/components/TableOwnPublicZonePile.qml"
        )
        release_handler = pile.split("onReleased: {", 1)[1].split(
            "Qt.callLater", 1
        )[0]

        self.assertIn("zoneDragCard.Drag.drop()", release_handler)
        self.assertNotIn("if (drag.active)", release_handler)

    def test_development_ci_and_local_verification_run_table_architecture_gate(self) -> None:
        for entry_point in (".github/workflows/ci.yml", "tools/verify.sh"):
            text = self.source(entry_point)
            self.assertIn("python3 -m unittest discover -s tools/tests", text)

    def test_ci_automatically_races_gameplay_and_control_plane(self) -> None:
        text = self.source(".github/workflows/ci.yml")
        self.assertIn("go test -race ./internal/room ./internal/server ./internal/tournament", text)
        race_step = next(step for step in text.split("      - name:")
                         if "run: go test -race" in step)
        self.assertNotIn("if:", race_step)
        for package in ("accounts", "cluster", "syncutil"):
            self.assertIn(f"./internal/{package}", race_step)

    def test_ci_jobs_without_server_exclude_the_integration_label(self) -> None:
        text = self.source(".github/workflows/ci.yml")
        self.assertNotIn("-E '^server-integration$'", text)
        self.assertEqual(text.count("--output-on-failure -LE integration"), 2)

    def test_settings_surfaces_preference_save_errors(self) -> None:
        language = self.source("apps/client-qt/qml/screens/LanguageSettings.qml")
        self.assertIn("preferences.lastError", language)


if __name__ == "__main__":
    unittest.main()
