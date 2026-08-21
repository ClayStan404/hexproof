// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "TableAttachmentController"
    when: windowShown

    QtObject {
        id: fakeTable

        property var tableAttachments: []
        property var selectedBattlefieldCard: ({})
        property string selectedBattlefieldCardId: ""
        property int selectedBattlefieldOwnerSeat: 0
        property bool canAct: true
        property var roomSession: ({
            "seatIndex": 0,
            "role": "player"
        })
        property var gameTableModel: fakeModel
        property var zoneState: fakeZones
        property var selection: fakeSelection
        property var wsModel: fakeWs
    }

    QtObject {
        id: fakeModel

        property var seats: [{ "seat": 0 }, { "seat": 1 }]
        property var attachments: fakeTable.tableAttachments

        function visibleZoneSeat(cardId, zone) {
            if (zone !== "battlefield")
                return -1
            if (cardId.indexOf("s0-") === 0)
                return 0
            if (cardId.indexOf("s1-") === 0)
                return 1
            return -1
        }

        function attachmentForSource(cardId) {
            for (let index = 0; index < fakeTable.tableAttachments.length;
                 ++index) {
                if (fakeTable.tableAttachments[index].sourceCardId === cardId)
                    return fakeTable.tableAttachments[index]
            }
            return ({})
        }
    }

    QtObject {
        id: fakeZones

        function cardDataForId(cardId) {
            return {
                "id": cardId,
                "name": cardId,
                "ownerSeat": cardId.indexOf("s0-") === 0 ? 0 : 1
            }
        }
    }

    QtObject {
        id: fakeSelection

        property int count: 1
        property string lastMode: ""

        function selectedCount() {
            return count
        }

        function beginRelationTarget(kind) {
            lastMode = kind
        }

        function clear() {
            lastMode = ""
        }
    }

    QtObject {
        id: fakeWs

        property var lastAttachment: ({})

        function setAttachment(sourceCardId, targetCardId) {
            lastAttachment = {
                "sourceCardId": sourceCardId,
                "targetCardId": targetCardId
            }
        }
    }

    TableAttachmentController {
        id: controller
        tableRoot: fakeTable
    }

    function init() {
        fakeTable.tableAttachments = []
        fakeTable.selectedBattlefieldCard = ({
            "id": "s0-aura",
            "ownerSeat": 0
        })
        fakeTable.selectedBattlefieldCardId = "s0-aura"
        fakeSelection.count = 1
        fakeSelection.lastMode = ""
        fakeWs.lastAttachment = ({})
    }

    function test_hidesHomeLaneCardOnlyWhenTargetIsOnAnotherSeat() {
        fakeTable.tableAttachments = [{
            "sourceCardId": "s0-aura",
            "targetCardId": "s1-bear"
        }]
        verify(controller.hidesHomeLaneCard("s0-aura", 0))
        verify(!controller.hidesHomeLaneCard("s0-aura", 1))
        verify(!controller.hidesHomeLaneCard("s1-bear", 1))
    }

    function test_crossLaneStacksSkipSameLaneAttachments() {
        fakeTable.tableAttachments = [{
            "sourceCardId": "s0-aura",
            "targetCardId": "s1-bear"
        }, {
            "sourceCardId": "s0-sword",
            "targetCardId": "s0-bear"
        }]
        compare(controller.crossLaneStacks.length, 1)
        compare(controller.crossLaneStacks[0].sourceCardId, "s0-aura")
        compare(controller.crossLaneStacks[0].targetCardId, "s1-bear")
        compare(controller.crossLaneStacks[0].stackIndex, 0)
    }

    function test_beginAttachAndDetachUseExistingCommands() {
        verify(controller.canAttachSelected())
        verify(!controller.canDetachSelected())
        controller.beginAttach()
        compare(fakeSelection.lastMode, "attach")

        fakeTable.tableAttachments = [{
            "sourceCardId": "s0-aura",
            "targetCardId": "s1-bear"
        }]
        verify(controller.canDetachSelected())
        controller.detachSelected()
        compare(fakeWs.lastAttachment.sourceCardId, "s0-aura")
        verify(!fakeWs.lastAttachment.targetCardId)
    }

    function test_attachmentStackPositionMatchesServerOffset() {
        const first = controller.attachmentStackPosition({"x": 0.50, "y": 0.60}, 0)
        compare(first.x, 0.54)
        compare(first.y, 0.65)
        const second = controller.attachmentStackPosition({"x": 0.50, "y": 0.60}, 1)
        compare(second.x, 0.58)
        compare(second.y, 0.70)
    }

    function test_ownerOnlyAttachAndAttachmentSourceLookup() {
        verify(controller.canAttachSelected())
        fakeTable.selectedBattlefieldCard = ({
            "id": "s0-stolen",
            "ownerSeat": 1
        })
        fakeTable.selectedBattlefieldCardId = "s0-stolen"
        verify(!controller.canAttachSelected())
        verify(!controller.canDetachSelected())

        fakeTable.selectedBattlefieldCard = ({
            "id": "s0-aura",
            "ownerSeat": 0
        })
        fakeTable.selectedBattlefieldCardId = "s0-aura"
        fakeTable.tableAttachments = [{
            "sourceCardId": "s0-aura",
            "targetCardId": "s0-bear"
        }]
        verify(controller.isAttachmentSource("s0-aura"))
        verify(!controller.isAttachmentSource("s0-bear"))
        verify(!controller.hidesHomeLaneCard("s0-aura", 0))
    }
}
