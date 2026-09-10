// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    name: "TableSelectionController"

    QtObject {
        id: fakeRoomSession
        property int seatIndex: 0
    }

    QtObject {
        id: fakePresentation
        function availableCardFaces(card) { return [] }
    }

    QtObject {
        id: fakeZoneState
        property var battlefields: ({})
        property var stackCards: ({})

        function visibleZoneSeatForCard(cardId, zone) {
            if (zone !== "battlefield")
                return -1
            const seats = Object.keys(battlefields)
            for (let seatIndex = 0; seatIndex < seats.length; ++seatIndex) {
                const seat = Number(seats[seatIndex])
                const cards = battlefields[seats[seatIndex]]
                for (let cardIndex = 0; cardIndex < cards.length; ++cardIndex) {
                    if (cards[cardIndex].id === cardId)
                        return seat
                }
            }
            return -1
        }

        function cardDataForId(cardId) {
            const seats = Object.keys(battlefields)
            for (let seatIndex = 0; seatIndex < seats.length; ++seatIndex) {
                const cards = battlefields[seats[seatIndex]]
                for (let cardIndex = 0; cardIndex < cards.length; ++cardIndex) {
                    if (cards[cardIndex].id === cardId)
                        return cards[cardIndex]
                }
            }
            return stackCards[cardId] ? stackCards[cardId] : ({"id": cardId})
        }

        function cardInZone(cardId, zone, seat) {
            return zone === "stack" && seat === -1
                    && stackCards[cardId] !== undefined
        }
    }

    QtObject {
        id: fakeTable
        property bool canAct: true
        property var roomSession: fakeRoomSession
        property var zoneState: fakeZoneState
        property var presentation: fakePresentation
        property var pendingCardMoves: ({})
    }

    TableSelectionController {
        id: controller
        tableRoot: fakeTable
    }

    function card(id, name, ownerSeat) {
        return {
            "id": id,
            "name": name,
            "ownerSeat": ownerSeat
        }
    }

    function setBattlefields(seatZero, seatOne) {
        fakeZoneState.battlefields = {
            "0": seatZero ? seatZero : [],
            "1": seatOne ? seatOne : []
        }
    }

    function startInteraction(mode) {
        controller.clear()
        fakeTable.pendingCardMoves = ({})
        fakeZoneState.stackCards = ({})
        setBattlefields([card("a", "Alpha", 0)], [])
        controller.beginRelationTargetForSources(mode, ["a"])
    }

    function startSelectedInteraction(mode) {
        controller.clear()
        fakeTable.pendingCardMoves = ({})
        fakeZoneState.stackCards = ({})
        setBattlefields([card("a", "Alpha", 0)], [])
        controller.selectCard(fakeZoneState.battlefields["0"][0], 0, false)
        controller.beginRelationTarget(mode)
    }

    function init() {
        fakeTable.pendingCardMoves = ({})
        fakeZoneState.stackCards = ({})
        setBattlefields([
            card("a", "Alpha", 0),
            card("b", "Beta", 0)
        ], [])
        controller.clear()
    }

    function test_clearsWhenEverySelectedCardLeavesBattlefield() {
        controller.selectCard(fakeZoneState.battlefields["0"][0], 0, false)
        compare(controller.selectedCount(), 1)

        setBattlefields([], [])
        controller.reconcileBattlefieldSelection()

        compare(controller.selectedCount(), 0)
        compare(controller.selectedCardId, "")
        compare(controller.selectedOwnerSeat, -1)
    }

    function test_prunesOneSelectionAndPreservesTheOther() {
        controller.selectCard(fakeZoneState.battlefields["0"][0], 0, false)
        controller.selectCard(fakeZoneState.battlefields["0"][1], 0, true)
        compare(controller.selectedCount(), 2)

        setBattlefields([card("b", "Beta refreshed", 0)], [])
        controller.reconcileBattlefieldSelection()

        compare(controller.selectedCount(), 1)
        verify(controller.cardSelected("b"))
        compare(controller.selectedCardId, "b")
        compare(controller.selectedCard.name, "Beta refreshed")
    }

    function test_refreshesRetainedCardMetadataAndControllerSeat() {
        controller.selectCard(fakeZoneState.battlefields["0"][0], 0, false)

        setBattlefields([], [card("a", "Alpha transformed", 0)])
        controller.reconcileBattlefieldSelection()

        compare(controller.selectedCount(), 1)
        compare(controller.selectedCardId, "a")
        compare(controller.selectedCard.name, "Alpha transformed")
        compare(controller.selectedOwnerSeat, 1)
    }

    function test_prunesInvalidInteractionSources() {
        controller.selectCard(fakeZoneState.battlefields["0"][0], 0, false)
        controller.selectCard(fakeZoneState.battlefields["0"][1], 0, true)
        controller.beginRelationTarget("arrow")

        setBattlefields([card("b", "Beta", 0)], [])
        controller.reconcileBattlefieldSelection()

        compare(controller.interactionMode, "arrow")
        compare(controller.interactionSourceIds.length, 1)
        compare(controller.interactionSourceIds[0], "b")

        setBattlefields([], [])
        controller.reconcileBattlefieldSelection()
        compare(controller.interactionMode, "")
        compare(controller.interactionSourceIds.length, 0)
    }

    function test_keepsValidSharedStackInteractionSource() {
        fakeZoneState.stackCards = {
            "stack-a": card("stack-a", "Stack spell", 0)
        }
        controller.beginRelationTargetForSources("arrow", ["stack-a"])

        controller.reconcileBattlefieldSelection()

        compare(controller.interactionMode, "arrow")
        compare(controller.interactionSourceIds.length, 1)
        compare(controller.interactionSourceIds[0], "stack-a")
    }

    function test_authoritativeBattlefieldToStackIsModeAware() {
        startInteraction("arrow")
        setBattlefields([], [])
        fakeZoneState.stackCards = {
            "a": card("a", "Alpha", 0)
        }
        controller.reconcileBattlefieldSelection()
        compare(controller.interactionMode, "arrow")
        compare(controller.interactionSourceIds, ["a"])

        const battlefieldOnlyModes = ["attack", "block", "attach"]
        for (let index = 0; index < battlefieldOnlyModes.length; ++index) {
            startInteraction(battlefieldOnlyModes[index])
            setBattlefields([], [])
            fakeZoneState.stackCards = {
                "a": card("a", "Alpha", 0)
            }
            controller.reconcileBattlefieldSelection()
            compare(controller.interactionMode, "")
            compare(controller.interactionSourceIds.length, 0)
        }
    }

    function test_pendingBattlefieldToStackIsModeAware() {
        startInteraction("arrow")
        fakeTable.pendingCardMoves = {
            "a": {
                "cardId": "a",
                "fromZone": "battlefield",
                "fromSeat": 0,
                "toZone": "stack",
                "toSeat": -1
            }
        }
        controller.reconcileBattlefieldSelection()
        compare(controller.interactionMode, "arrow")
        compare(controller.interactionSourceIds, ["a"])

        const battlefieldOnlyModes = ["attack", "block", "attach"]
        for (let index = 0; index < battlefieldOnlyModes.length; ++index) {
            startInteraction(battlefieldOnlyModes[index])
            fakeTable.pendingCardMoves = {
                "a": {
                    "cardId": "a",
                    "fromZone": "battlefield",
                    "fromSeat": 0,
                    "toZone": "stack",
                    "toSeat": -1
                }
            }
            controller.reconcileBattlefieldSelection()
            compare(controller.interactionMode, "")
            compare(controller.interactionSourceIds.length, 0)
        }
    }

    function test_selectedArrowSurvivesAuthoritativeMoveToStack() {
        startSelectedInteraction("arrow")
        setBattlefields([], [])
        fakeZoneState.stackCards = {
            "a": card("a", "Alpha", 0)
        }

        controller.reconcileBattlefieldSelection()

        compare(controller.selectedCount(), 0)
        compare(controller.selectedCardId, "")
        compare(controller.selectedOwnerSeat, -1)
        compare(controller.selectedCard, ({}))
        compare(controller.interactionMode, "arrow")
        compare(controller.interactionSourceIds, ["a"])
    }

    function test_selectedArrowSurvivesPendingMoveToStack() {
        startSelectedInteraction("arrow")
        fakeTable.pendingCardMoves = {
            "a": {
                "cardId": "a",
                "card": card("a", "Alpha", 0),
                "fromZone": "battlefield",
                "fromSeat": 0,
                "toZone": "stack",
                "toSeat": -1
            }
        }

        controller.reconcileBattlefieldSelection()

        compare(controller.selectedCount(), 0)
        compare(controller.selectedCardId, "")
        compare(controller.selectedOwnerSeat, -1)
        compare(controller.selectedCard, ({}))
        compare(controller.interactionMode, "arrow")
        compare(controller.interactionSourceIds, ["a"])
    }
}
