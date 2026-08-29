// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "TableSharedZoneController"

    QtObject {
        id: fakeWs
        property int seatIndex: 0
    }

    QtObject {
        id: fakeRoomSession
        property int seatIndex: fakeWs.seatIndex
    }

    QtObject {
        id: fakeTable
        property var zoneState: fakeTable
        property var seatState: fakeTable
        property var wsModel: fakeWs
        property var roomSession: fakeRoomSession
        property var stackCards: []
        property var revealedCards: []
        property var pendingCardMoves: ({})
        property var occupied: ({})
        property var seats: ({
            "0": {"seat": 0, "displayName": "Alice"},
            "1": {"seat": 1, "displayName": "Bob"}
        })

        function seatData(seat) {
            return seats[String(seat)] || ({})
        }

        function cardInZone(cardId, zone, seat) {
            return occupied[String(cardId) + ":" + zone + ":" + seat]
                    === true
        }
    }

    TableSharedZoneController {
        id: controller
        tableRoot: fakeTable
        playerLabel: "Player"
        revealedLabel: "Revealed"
    }

    function init() {
        fakeWs.seatIndex = 0
        fakeTable.stackCards = []
        fakeTable.revealedCards = []
        fakeTable.pendingCardMoves = ({})
        fakeTable.occupied = ({})
        controller.reset()
    }

    function test_combinesStackRevealsAndPendingMoves() {
        fakeTable.stackCards = [{
            "id": "stack-1", "name": "Spell", "ownerSeat": 0
        }]
        fakeTable.revealedCards = [
            {"id": "reveal-1", "name": "One", "ownerSeat": 0},
            {"id": "reveal-2", "name": "Two", "ownerSeat": 1}
        ]
        fakeTable.pendingCardMoves = ({
            "pending-1": {
                "toZone": "stack",
                "card": {
                    "id": "stack-2", "name": "Pending", "ownerSeat": 1
                }
            }
        })

        const cards = controller.combinedCards()
        compare(cards.length, 4)
        compare(cards[0].sharedZone, "stack")
        compare(cards[0].ownerDisplayName, "Alice")
        compare(cards[1].sharedZone, "stack")
        compare(cards[1].ownerDisplayName, "Bob")
        verify(cards[2].revealDivider)
        compare(cards[2].revealDividerLabel, "Alice · Revealed")
        verify(cards[3].revealDivider)
        compare(cards[3].revealDividerLabel, "Bob · Revealed")
    }

    function test_pendingMoveAlreadyAuthoritativeIsNotDuplicated() {
        fakeTable.pendingCardMoves = ({
            "pending-1": {
                "toZone": "stack",
                "card": {"id": "stack-1", "name": "Spell"}
            }
        })
        fakeTable.occupied = ({"stack-1:stack:-1": true})
        compare(controller.combinedCards().length, 0)
    }

    function test_selectionReconcilesOrClears() {
        fakeTable.stackCards = [{"id": "stack-1", "name": "Spell"}]
        controller.selectCard({"id": "stack-1", "name": "Old"}, "stack")
        controller.reconcileSelection()
        compare(controller.selectedCard.name, "Spell")

        fakeTable.stackCards = []
        controller.reconcileSelection()
        compare(controller.selectedCard.id, undefined)
        compare(controller.selectedZone, "")
    }

    function test_tracksOpponentZoneExpansionBySeat() {
        verify(!controller.opponentZoneExpanded(1))
        controller.setOpponentZoneExpanded(1, true)
        verify(controller.opponentZoneExpanded(1))
        controller.setOpponentZoneExpanded(1, false)
        verify(!controller.opponentZoneExpanded(1))
    }

    function test_tracksOpponentZonePanelPositionBySeat() {
        compare(controller.opponentZonePanelPosition(1).x, undefined)
        controller.setOpponentZonePanelPosition(1, 0.25, 0.75)
        compare(controller.opponentZonePanelPosition(1).x, 0.25)
        compare(controller.opponentZonePanelPosition(1).y, 0.75)
        controller.setOpponentZonePanelPosition(2, -1, 2)
        compare(controller.opponentZonePanelPosition(2).x, 0)
        compare(controller.opponentZonePanelPosition(2).y, 1)
        controller.resetOpponentZonePanelPosition(1)
        compare(controller.opponentZonePanelPosition(1).x, undefined)
        compare(controller.opponentZonePanelPosition(2).y, 1)
    }
}
