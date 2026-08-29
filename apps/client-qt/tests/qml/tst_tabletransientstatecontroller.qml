// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "TableTransientStateController"

    QtObject {
        id: fakeWs
        property bool inRoom: true
        property string roomPhase: "started"
    }

    QtObject {
        id: fakeRoomSession
        property string phase: fakeWs.roomPhase
    }

    QtObject {
        id: fakeTable
        property var seatState: fakeTable
        property var wsModel: fakeWs
        property var roomSession: fakeRoomSession
        property var ownHand: []
        property var seats: ({})

        function seatData(seat) {
            return seats[String(seat)] || ({})
        }
    }

    TableTransientStateController {
        id: controller
        tableRoot: fakeTable
    }

    function init() {
        fakeWs.inRoom = true
        fakeWs.roomPhase = "started"
        fakeTable.ownHand = []
        fakeTable.seats = ({})
        controller.reset()
    }

    function test_reconcilesSelectedHandCard() {
        fakeTable.ownHand = [{"id": "card-1", "name": "Current"}]
        controller.selectedHandCard = {"id": "card-1", "name": "Old"}
        controller.reconcile()
        compare(controller.selectedHandCard.name, "Current")

        fakeTable.ownHand = []
        controller.reconcile()
        compare(controller.selectedHandCard.id, undefined)
    }

    function test_clearsRemovedCounterSelection() {
        fakeTable.seats = ({
            "0": {"counters": [{"key": "energy", "value": 2}]}
        })
        controller.selectedCounterSeat = 0
        controller.selectedCounterKey = "energy"
        controller.reconcile()
        compare(controller.selectedCounterKey, "energy")

        fakeTable.seats = ({"0": {"counters": []}})
        controller.reconcile()
        compare(controller.selectedCounterSeat, -1)
        compare(controller.selectedCounterKey, "")
    }

    function test_roomExitClearsLibraryTransientState() {
        controller.setLibraryApproval("approval-1", "Bob", 3)
        compare(controller.pendingLibraryTopCount, 3)
        controller.libraryMoveDestination = "exile"
        fakeWs.inRoom = false
        controller.reconcile()
        compare(controller.pendingLibraryApprovalId, "")
        compare(controller.pendingLibraryRequesterName, "")
        compare(controller.pendingLibraryTopCount, 0)
        compare(controller.libraryMoveDestination, "")
    }
}
