// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "RulesDamagePrompt"
    when: windowShown

    ApplicationWindow {
        width: 920
        height: 460
        visible: true

        QtObject {
            id: fakeWs
            property int orderResponseCount: 0
            property int damageResponseCount: 0
            property var lastOrder: []
            property var lastAssignments: []

            function respondRulesPromptWithDamageOrder(promptId, orderedIds) {
                orderResponseCount++
                lastOrder = orderedIds
            }

            function respondRulesPromptWithDamage(promptId, assignments) {
                damageResponseCount++
                lastAssignments = assignments
            }
        }

        QtObject {
            id: fakeCatalog
            property int imageRevision: 0

            function tableImageSource(name, setCode, collectorNumber) {
                return ""
            }
        }

        QtObject {
            id: damageTargets

            function items() {
                return [
                    {"responseId": "damage-target:0", "kind": "card",
                     "label": "Bear Cub", "name": "Bear Cub", "setCode": "P02",
                     "collectorNumber": "120", "token": false, "oracle": "",
                     "lethalDamage": 2},
                    {"responseId": "damage-target:1", "kind": "card",
                     "label": "Hill Giant", "name": "Hill Giant", "setCode": "M10",
                     "collectorNumber": "143", "token": false, "oracle": "",
                     "lethalDamage": 3},
                    {"responseId": "damage-target:2", "kind": "player",
                     "label": "Bob · Seat 2", "name": "", "setCode": "",
                     "collectorNumber": "", "token": false, "oracle": "",
                     "lethalDamage": -1}
                ]
            }
        }

        ListModel {
            id: visualTargets

            function items() {
                return damageTargets.items()
            }

            ListElement {
                responseId: "damage-target:0"
                kind: "card"
                label: "Bear Cub"
                name: "Bear Cub"
                setCode: "P02"
                collectorNumber: "120"
                token: false
                lethalDamage: 2
            }
            ListElement {
                responseId: "damage-target:1"
                kind: "card"
                label: "Hill Giant"
                name: "Hill Giant"
                setCode: "M10"
                collectorNumber: "143"
                token: false
                lethalDamage: 3
            }
            ListElement {
                responseId: "damage-target:2"
                kind: "player"
                label: "Bob · Seat 2"
                name: ""
                setCode: ""
                collectorNumber: ""
                token: false
                lethalDamage: -1
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RulesOrderPrompt {
                id: orderPrompt
                width: parent.width
                height: 210
                wsModel: fakeWs
                cardCatalogModel: fakeCatalog
                orderModel: damageTargets
                promptId: 81
                damageOrder: true
            }

            RulesDamageAssignmentPrompt {
                id: damagePrompt
                width: parent.width
                height: 210
                wsModel: fakeWs
                cardCatalogModel: fakeCatalog
                targetModel: visualTargets
                damageSource: ({"name": "Colossal Dreadmaw"})
                promptId: 82
                totalDamage: 7
                deathtouch: false
            }
        }
    }

    function init() {
        fakeWs.orderResponseCount = 0
        fakeWs.damageResponseCount = 0
        fakeWs.lastOrder = []
        fakeWs.lastAssignments = []
        orderPrompt.resetOrder()
        damagePrompt.resetAssignments()
    }

    function test_reordersOpaqueDamageTargets() {
        orderPrompt.moveItem(1, 0)
        orderPrompt.submitOrder()
        compare(fakeWs.orderResponseCount, 1)
        compare(fakeWs.lastOrder[0], "damage-target:1")
        compare(fakeWs.lastOrder[1], "damage-target:0")
    }

    function test_assignsLethalDamageBeforeLaterTargets() {
        verify(!damagePrompt.setDamage("damage-target:1", 1))
        damagePrompt.autoAssign()
        compare(damagePrompt.assignedTo("damage-target:0"), 2)
        compare(damagePrompt.assignedTo("damage-target:1"), 3)
        compare(damagePrompt.assignedTo("damage-target:2"), 2)
        verify(damagePrompt.validAssignment)

        damagePrompt.submitDamage()
        compare(fakeWs.damageResponseCount, 1)
        compare(fakeWs.lastAssignments.length, 3)
        compare(fakeWs.lastAssignments[2].damage, 2)

        verify(damagePrompt.setDamage("damage-target:0", 1))
        compare(damagePrompt.assignedTo("damage-target:1"), 0)
        compare(damagePrompt.assignedTo("damage-target:2"), 0)
        verify(!damagePrompt.validAssignment)
    }
}
