// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "TableCardMoveController"

    QtObject {
        id: fakeWs
        property var moveCalls: []
        property var playLandCalls: []

        function moveCard(cardId, fromZone, toZone, position, toSeat, placement,
                          index, publicFromSeat, faceName, faceDown) {
            moveCalls = moveCalls.concat([{
                "cardId": cardId,
                "fromZone": fromZone,
                "toZone": toZone,
                "position": position,
                "toSeat": toSeat
            }])
        }

        function moveCards(cardIds, fromZone, toZone, placement, randomize) {
            moveCalls = moveCalls.concat([{
                "cardIds": cardIds,
                "fromZone": fromZone,
                "toZone": toZone
            }])
        }

        function playLand(cardId, position, faceName) {
            playLandCalls = playLandCalls.concat([{
                "cardId": cardId,
                "position": position,
                "faceName": faceName
            }])
        }
    }

    QtObject {
        id: fakeRoomSession
        property int seatIndex: 0
    }

    QtObject {
        id: fakeSelection
        property int count: 1
        property int clearCalls: 0

        function selectedCount() {
            return count
        }

        function clear() {
            ++clearCalls
        }
    }

    QtObject {
        id: fakeOptimistic
        property var pendingMoves: []
        property var battlefieldMoves: []

        function beginPendingCardMove(cardId, card, fromZone, fromSeat, toZone, toSeat) {
            pendingMoves = pendingMoves.concat([{
                "cardId": cardId,
                "fromZone": fromZone,
                "toZone": toZone
            }])
        }

        function beginPendingCardMoves(moves) {
            pendingMoves = pendingMoves.concat(moves)
        }

        function setBattlefieldMove(move) {
            battlefieldMoves = battlefieldMoves.concat([move])
        }
    }

    QtObject {
        id: fakeZones
        property var battlefieldCards: []

        function visibleZoneSeatForCard(cardId, zone) {
            return 0
        }

        function cardDataForId(cardId) {
            return {
                "id": cardId,
                "name": "Lightning Bolt",
                "ownerSeat": 0,
                "typeLine": "Instant"
            }
        }

        function zoneCardsForSeat(seatIndex, zone) {
            if (seatIndex === 0 && zone === "battlefield")
                return battlefieldCards
            return []
        }
    }

    QtObject {
        id: fakePresentation
        function availableCardFaces(card) {
            return []
        }
    }

    QtObject {
        id: fakeTable
        property var wsModel: fakeWs
        property var roomSession: fakeRoomSession
        property var selection: fakeSelection
        property var optimisticCommands: fakeOptimistic
        property var optimisticCommandModel: fakeOptimistic
        property var zoneState: fakeZones
        property var presentation: fakePresentation
        property var cardCatalogModel: null
        property bool canAct: true
        property string selectedBattlefieldCardId: "card-1"
        property int selectedBattlefieldOwnerSeat: 0
        property var selectedBattlefieldCard: ({
            "id": "card-1",
            "ownerSeat": 0,
            "name": "Lightning Bolt"
        })
        property var selectedBattlefieldCardIds: ({ "card-1": true, "card-2": true })
        property var selectedSharedCard: ({})
        property string selectedSharedZone: ""
        property var pendingBattlefieldMove: ({})
    }

    TableCardMoveController {
        id: controller
        tableRoot: fakeTable
    }

    function init() {
        fakeWs.moveCalls = []
        fakeWs.playLandCalls = []
        fakeOptimistic.pendingMoves = []
        fakeOptimistic.battlefieldMoves = []
        fakeSelection.clearCalls = 0
        fakeSelection.count = 1
        fakeTable.canAct = true
        fakeTable.selectedBattlefieldCardId = "card-1"
        fakeTable.selectedBattlefieldOwnerSeat = 0
        fakeTable.pendingBattlefieldMove = ({})
        fakeZones.battlefieldCards = []
    }

    function test_canManageSelectedBattlefieldRequiresLocalControl() {
        compare(controller.canManageSelectedBattlefield(), true)
        fakeTable.canAct = false
        compare(controller.canManageSelectedBattlefield(), false)
        fakeTable.canAct = true
        fakeTable.selectedBattlefieldOwnerSeat = 1
        fakeTable.selectedBattlefieldCard = {
            "id": "card-1",
            "ownerSeat": 1
        }
        compare(controller.canManageSelectedBattlefield(), false)
    }

    function test_moveSelectedBattlefieldToZoneUsesMoveCardNotPlayLand() {
        controller.moveSelectedBattlefieldToZone("graveyard")
        compare(fakeWs.playLandCalls.length, 0)
        compare(fakeWs.moveCalls.length, 1)
        compare(fakeWs.moveCalls[0].cardId, "card-1")
        compare(fakeWs.moveCalls[0].fromZone, "battlefield")
        compare(fakeWs.moveCalls[0].toZone, "graveyard")
        compare(fakeOptimistic.pendingMoves.length, 1)
        compare(fakeSelection.clearCalls, 1)
    }

    function test_moveSelectedBattlefieldCardsBeginsPendingMoves() {
        controller.moveSelectedBattlefieldCards("graveyard")
        compare(fakeWs.moveCalls.length, 1)
        compare(fakeWs.moveCalls[0].cardIds, ["card-1", "card-2"])
        compare(fakeWs.moveCalls[0].fromZone, "battlefield")
        compare(fakeWs.moveCalls[0].toZone, "graveyard")
        compare(fakeOptimistic.pendingMoves.length, 2)
        compare(fakeOptimistic.pendingMoves[0].cardId, "card-1")
        compare(fakeOptimistic.pendingMoves[0].card.id, "card-1")
        compare(fakeOptimistic.pendingMoves[0].fromZone, "battlefield")
        compare(fakeOptimistic.pendingMoves[0].fromSeat, 0)
        compare(fakeOptimistic.pendingMoves[0].toZone, "graveyard")
        compare(fakeOptimistic.pendingMoves[0].toSeat, 0)
        compare(fakeOptimistic.pendingMoves[1].cardId, "card-2")
        compare(fakeOptimistic.pendingMoves[1].toZone, "graveyard")
        compare(fakeSelection.clearCalls, 1)
    }

    function test_moveSelectedBattlefieldCardsToLibraryBeginsPendingMoves() {
        controller.moveSelectedBattlefieldCards("library", "top", true)
        compare(fakeWs.moveCalls.length, 1)
        compare(fakeWs.moveCalls[0].cardIds, ["card-1", "card-2"])
        compare(fakeWs.moveCalls[0].toZone, "library")
        compare(fakeOptimistic.pendingMoves.length, 2)
        compare(fakeOptimistic.pendingMoves[0].toZone, "library")
        compare(fakeOptimistic.pendingMoves[1].toZone, "library")
        compare(fakeSelection.clearCalls, 1)
    }

    function test_handDropOntoBattlefieldDoesNotRecordALandPlay() {
        controller.moveCardToBattlefield("card-1", "hand", 0, 0.4, 0.6)
        compare(fakeWs.playLandCalls.length, 0)
        compare(fakeWs.moveCalls.length, 1)
        compare(fakeWs.moveCalls[0].fromZone, "hand")
        compare(fakeWs.moveCalls[0].toZone, "battlefield")
        compare(fakeWs.moveCalls[0].toSeat, 0)
    }

    function test_beginLibraryBattlefieldPreviewCapturesKnownCards() {
        fakeZones.battlefieldCards = [
            {"id": "battlefield-1", "ownerSeat": 0},
            {"id": "battlefield-2", "ownerSeat": 0}
        ]

        controller.beginBattlefieldPreviewForCard(
                    "library-top", "library", 0, ({}), 0, 0.4, 0.5)

        compare(fakeOptimistic.pendingMoves.length, 1)
        compare(fakeOptimistic.pendingMoves[0].fromZone, "library")
        compare(fakeOptimistic.pendingMoves[0].knownCardIds,
                ["battlefield-1", "battlefield-2"])
        compare(fakeOptimistic.battlefieldMoves.length, 1)
        compare(fakeOptimistic.battlefieldMoves[0].knownCardIds,
                ["battlefield-1", "battlefield-2"])
    }

    function test_libraryBattlefieldPreviewCommitsOnlyOnNewCard() {
        fakeZones.battlefieldCards = [
            {"id": "battlefield-1", "ownerSeat": 0,
             "position": {"x": 0.4, "y": 0.5}}
        ]
        fakeTable.pendingBattlefieldMove = ({
            "cardId": "library-top",
            "fromZone": "library",
            "toSeat": 0,
            "x": 0.4,
            "y": 0.5,
            "knownCardIds": ["battlefield-1"]
        })

        // A permanent already sitting at the exact drop coordinates must not
        // steal the commit.
        verify(!controller.pendingBattlefieldMoveCommitted())

        // The server instance arrives with a new id and an auto-adjusted
        // position; that commits the preview.
        fakeZones.battlefieldCards = fakeZones.battlefieldCards.concat([
            {"id": "instance-9", "ownerSeat": 0,
             "position": {"x": 0.72, "y": 0.81}}
        ])
        verify(controller.pendingBattlefieldMoveCommitted())
    }
}
