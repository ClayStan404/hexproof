// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "TableProjectionSyncController"

    QtObject {
        id: fakeWs
        property int seatIndex: 0
        property string roomRole: "player"
    }

    QtObject {
        id: fakeRoomSession
        property int seatIndex: fakeWs.seatIndex
        property string role: fakeWs.roomRole
    }

    QtObject {
        id: fakeTable
        property var optimisticCommands: fakeTable
        property var wsModel: fakeWs
        property var roomSession: fakeRoomSession
        property bool isEDH: false
        property var authoritativeOwnHand: []
        property var pendingCardMoves: ({})
        property var authoritativeSeats: []
        property var tableGameLog: []
        property var pendingFromKeys: ({})

        function isCardPendingFrom(cardId, zone, seat) {
            return pendingFromKeys[
                        String(cardId) + ":" + zone + ":" + String(seat)]
                    === true
        }
    }

    Component {
        id: seatStateComponent

        QtObject {
            property int seat: -1
            property int updateCount: 0
            property var snapshot: ({})

            function updateFrom(value) {
                snapshot = value
                seat = value.seat
                ++updateCount
            }
        }
    }

    ListModel { id: fakeGameLogModel }

    TableProjectionSyncController {
        id: controller
        tableRoot: fakeTable
        seatStateComponent: seatStateComponent
        gameLogModel: fakeGameLogModel
    }

    function init() {
        controller.reset()
        fakeWs.seatIndex = 0
        fakeWs.roomRole = "player"
        fakeTable.isEDH = false
        fakeTable.authoritativeOwnHand = []
        fakeTable.pendingCardMoves = ({})
        fakeTable.authoritativeSeats = []
        fakeTable.tableGameLog = []
        fakeTable.pendingFromKeys = ({})
        fakeGameLogModel.clear()
    }

    function test_projectsPendingCardsIntoOwnHandWithoutDuplicates() {
        fakeTable.authoritativeOwnHand = [
            {"id": "card-1", "name": "One"}
        ]
        fakeTable.pendingCardMoves = ({
            "card-1": {
                "toZone": "hand",
                "toSeat": 0,
                "card": {"id": "card-1", "name": "Duplicate"}
            },
            "card-2": {
                "toZone": "hand",
                "toSeat": 0,
                "card": {"id": "card-2", "name": "Two"}
            }
        })

        controller.syncDisplayedOwnHand()

        compare(controller.ownHand.length, 2)
        compare(controller.ownHand[0].name, "One")
        compare(controller.ownHand[1].id, "card-2")
    }

    function test_handSyncWaitsUntilDragFinishes() {
        fakeTable.authoritativeOwnHand = [{"id": "card-1"}]
        controller.syncDisplayedOwnHand()
        compare(controller.ownHand.length, 1)

        controller.activeHandDragCardId = "card-1"
        fakeTable.authoritativeOwnHand = [
            {"id": "card-1"}, {"id": "card-2"}
        ]
        controller.syncDisplayedOwnHand()
        verify(controller.handModelSyncDeferred)
        compare(controller.ownHand.length, 1)

        controller.finishHandDrag()
        compare(controller.activeHandDragCardId, "")
        verify(!controller.handModelSyncDeferred)
        compare(controller.ownHand.length, 2)
    }

    function test_visibleHandCountExcludesPendingDepartures() {
        fakeTable.authoritativeOwnHand = [
            {"id": "card-1"}, {"id": "card-2"}
        ]
        fakeTable.pendingFromKeys = ({"card-2:hand:0": true})
        controller.syncDisplayedOwnHand()
        compare(controller.visibleOwnHandCount(), 1)
    }

    function test_ordersSeatsAndReusesSeatStateObjects() {
        fakeTable.authoritativeSeats = [
            {"seat": 0, "life": 20},
            {"seat": 1, "life": 20},
            {"seat": 2, "life": 20}
        ]
        controller.syncBattlefieldSeats()

        compare(controller.battlefieldSeats.length, 3)
        compare(controller.battlefieldSeats[0].seat, 1)
        compare(controller.battlefieldSeats[1].seat, 2)
        compare(controller.battlefieldSeats[2].seat, 0)
        const firstState = controller.battlefieldSeats[0]

        fakeTable.authoritativeSeats = [
            {"seat": 0, "life": 19},
            {"seat": 1, "life": 18},
            {"seat": 2, "life": 17}
        ]
        controller.syncBattlefieldSeats()
        compare(controller.battlefieldSeats[0], firstState)
        compare(firstState.updateCount, 2)
        compare(firstState.snapshot.life, 18)
    }

    function test_battlefieldSyncWaitsUntilDragFinishes() {
        fakeTable.authoritativeSeats = [
            {"seat": 0, "life": 20}, {"seat": 1, "life": 20}
        ]
        controller.syncBattlefieldSeats()
        const opponentState = controller.battlefieldSeats[0]

        controller.activeBattlefieldDragCardId = "card-1"
        fakeTable.authoritativeSeats = [
            {"seat": 0, "life": 19}, {"seat": 1, "life": 18}
        ]
        controller.syncBattlefieldSeats()
        verify(controller.battlefieldSeatSyncDeferred)
        compare(opponentState.updateCount, 1)

        controller.finishBattlefieldDrag()
        verify(!controller.battlefieldSeatSyncDeferred)
        compare(opponentState.updateCount, 2)
        compare(opponentState.snapshot.life, 18)
    }

    function test_edhSeatOrderKeepsOpponentsAroundLocalSeat() {
        fakeTable.isEDH = true
        fakeWs.seatIndex = 2
        fakeTable.authoritativeSeats = [
            {"seat": 0}, {"seat": 1}, {"seat": 2}, {"seat": 3}
        ]

        const snapshots = controller.orderedBattlefieldSeatSnapshots()
        compare(snapshots.length, 4)
        compare(snapshots[0].seat, 3)
        compare(snapshots[1].seat, 0)
        compare(snapshots[2].seat, 2)
        compare(snapshots[3].seat, 1)
    }

    function test_threePlayerEdhSeatOrderKeepsLocalSeatLast() {
        fakeTable.isEDH = true
        fakeWs.seatIndex = 1
        fakeTable.authoritativeSeats = [
            {"seat": 0}, {"seat": 1}, {"seat": 2}
        ]

        const snapshots = controller.orderedBattlefieldSeatSnapshots()
        compare(snapshots.length, 3)
        compare(snapshots[0].seat, 2)
        compare(snapshots[1].seat, 0)
        compare(snapshots[2].seat, 1)
    }

    function test_gameLogProjectionAppendsAndRebuildsChangedPrefix() {
        fakeTable.tableGameLog = [
            {"id": 1, "kind": "move", "seat": 0, "text": "A"},
            {"id": 2, "kind": "draw", "seat": 1, "text": "B"}
        ]
        controller.syncGameLog()
        compare(fakeGameLogModel.count, 2)
        compare(fakeGameLogModel.get(1).entryText, "B")

        fakeTable.tableGameLog = [
            {"id": 1, "kind": "move", "seat": 0, "text": "Changed"}
        ]
        controller.syncGameLog()
        compare(fakeGameLogModel.count, 1)
        compare(fakeGameLogModel.get(0).entryText, "Changed")
    }

}
