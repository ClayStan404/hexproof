// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    name: "TableZoneStateController"

    QtObject {
        id: optimisticModel

        property var removed: []

        function removeValue(kind, key) {
            removed = removed.concat([kind + ":" + key])
        }
    }

    QtObject {
        id: mockWs

        property int seatIndex: 0
    }

    QtObject {
        id: fakeRoomSession
        property int seatIndex: mockWs.seatIndex
    }

    QtObject {
        id: fakeTable
        property var optimisticCommands: fakeTable
        property var wsModel: mockWs
        property var roomSession: fakeRoomSession
        property var optimisticCommandModel: optimisticModel
        property var gameTableModel: testGameTable
        property var authoritativeSeats: testGameTable.seats
        property var pendingCardMoves: ({})

        function isCardPendingFrom(cardId, zone, seat) {
            if (!Object.prototype.hasOwnProperty.call(
                        pendingCardMoves, cardId)) {
                return false
            }
            const move = pendingCardMoves[cardId]
            return move.fromZone === zone
                    && (move.fromSeat === seat || move.fromSeat < 0)
        }
    }

    TableZoneStateController {
        id: controller
        tableRoot: fakeTable
    }

    function init() {
        optimisticModel.removed = []
        fakeTable.pendingCardMoves = ({})
        testGameTable.applySnapshot({
            "seats": [{
            "seat": 0,
            "hand": [{"id": "hand-1", "ownerSeat": 0}],
            "battlefield": [{"id": "battlefield-1", "ownerSeat": 0}],
            "graveyard": [],
            "exile": [],
            "commandZone": []
        }, {
            "seat": 1,
            "hand": [],
            "battlefield": [],
            "graveyard": [{"id": "graveyard-1", "ownerSeat": 1}],
            "exile": [],
            "commandZone": []
            }],
            "stack": [{"id": "stack-1", "ownerSeat": 1}],
            "revealed": [{"id": "reveal-1", "ownerSeat": 0}]
        })
    }

    function cleanup() {
        testGameTable.clear()
    }

    function test_readsTypedZonesAndLocatesCards() {
        compare(controller.zoneCardCount(0, "hand"), 1)
        compare(controller.zoneCardAt(0, "hand", 0).id, "hand-1")
        verify(controller.cardInZone("graveyard-1", "graveyard", 1))
        compare(controller.cardDataForId("stack-1").ownerSeat, 1)
        compare(controller.visibleZoneSeatForCard(
                    "graveyard-1", "graveyard"), 1)
        compare(controller.revealedCardsForSeat(0).length, 1)
    }

    function test_pendingMovesOverlayAndReconcile() {
        fakeTable.pendingCardMoves = ({
            "battlefield-2": {
                "cardId": "battlefield-2",
                "card": {"id": "battlefield-2", "name": "Pending"},
                "fromZone": "hand",
                "fromSeat": 0,
                "toZone": "battlefield",
                "toSeat": 0,
                "x": 0.4,
                "y": 0.5,
                "tapped": true
            },
            "graveyard-1": {
                "cardId": "graveyard-1",
                "card": {"id": "graveyard-1", "name": "Moved"},
                "fromZone": "graveyard",
                "fromSeat": 1,
                "toZone": "exile",
                "toSeat": 1
            }
        })

        const pending = controller.pendingBattlefieldMovesForSeat(0)
        compare(pending.length, 1)
        compare(pending[0].x, 0.4)
        compare(pending[0].tapped, true)
        compare(controller.displayedPublicZoneTopCard(1, "exile").id,
                "graveyard-1")

        testGameTable.applySnapshot({"seats": [{
            "seat": 0,
            "hand": [{"id": "hand-1", "ownerSeat": 0}],
            "battlefield": [{"id": "battlefield-1", "ownerSeat": 0}],
            "graveyard": [],
            "exile": [],
            "commandZone": []
        }, {
            "seat": 1,
            "hand": [],
            "battlefield": [],
            "graveyard": [],
            "exile": [{"id": "graveyard-1", "ownerSeat": 1}],
            "commandZone": []
        }]})
        controller.reconcilePendingCardMoves()
        verify(optimisticModel.removed.indexOf(
                   "move:graveyard-1") >= 0)
    }

    function test_handRevealTransitionDetection() {
        fakeTable.pendingCardMoves = ({
            "hand-1": {
                "cardId": "hand-1",
                "fromZone": "hand",
                "fromSeat": 0,
                "toZone": "reveal",
                "toSeat": -1
            }
        })
        verify(controller.handRevealTransitionPending())
        fakeTable.pendingCardMoves = ({})
        verify(!controller.handRevealTransitionPending())
    }
}
