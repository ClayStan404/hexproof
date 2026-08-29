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

    function test_handDropOntoBattlefieldDoesNotRecordALandPlay() {
        controller.moveCardToBattlefield("card-1", "hand", 0, 0.4, 0.6)
        compare(fakeWs.playLandCalls.length, 0)
        compare(fakeWs.moveCalls.length, 1)
        compare(fakeWs.moveCalls[0].fromZone, "hand")
        compare(fakeWs.moveCalls[0].toZone, "battlefield")
        compare(fakeWs.moveCalls[0].toSeat, 0)
    }
}
