// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "RulesMultipleBlocks"
    when: windowShown
    property int serial: 400
    property bool bottomAligned: false

    ApplicationWindow {
        id: testWindow
        width: 900
        height: 540
        visible: true
        QtObject {
            id: transport
            property int responses: 0
            property var assignments: []
            function respondRulesPromptWithAssignments(id, values) {
                assignments = values
                responses++
            }
        }
        RulesCombatAssignmentPrompt {
            id: prompt
            anchors.top: bottomAligned ? undefined : parent.top
            anchors.bottom: bottomAligned ? parent.bottom : undefined
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 20
            height: 160
            wsModel: transport
            cardCatalogModel: null
            sourceModel: testRulesPrompt.session.promptCombat
            promptId: testRulesPrompt.session.promptId
            assignmentKind: "blockers"
        }
    }

    function prepare(maximum, count) {
        const value = {
            roomId: "BLOCK1", gameId: "multiple-blocks", pending: true, supported: true,
            promptId: ++serial, kind: "chooseBlockers", options: [], choices: [], cards: [],
            targets: [], contextCards: [], contextTargets: [], damageTargets: [], scryDestinations: [], totalDamage: 0,
            combatSources: [{responseId: "combat-source:0", objectId: "card-guard",
                label: "Palace Guard", name: "Palace Guard", validTargetIds: [],
                mustAssignIfAble: false, maxAssignments: maximum}], combatTargets: []
        }
        for (let index = 0; index < count; ++index) {
            value.combatSources[0].validTargetIds.push("combat-target:" + index)
            value.combatTargets.push({responseId: "combat-target:" + index, kind: "attacker",
                label: "Attacker " + index, objectId: "attacker-" + index,
                minAssignments: 1, maxAssignments: 1, mustReceiveIfAble: false})
        }
        verify(testRulesPrompt.applyPrompt(value))
        waitForRendering(prompt)
    }

    function init() {
        transport.responses = 0
        transport.assignments = []
        Theme.uiScale = 1
        bottomAligned = false
        testWindow.requestActivate()
        tryVerify(() => testWindow.active)
    }

    function cleanup() {
        const popup = findChild(prompt, "rulesCombatMultiAssignment-combat-source:0").targetPopup
        if (popup)
            popup.close()
        testRulesPrompt.clear()
    }

    function target(index) {
        return findChild(prompt, "rulesCombatMultiAssignment-combat-source:0").targetPopup.contentItem.itemAtIndex(index)
    }

    function test_selectMultipleAttackersAndReleaseCapacity() {
        prepare(2, 3)
        const button = findChild(prompt, "rulesCombatMultiAssignment-combat-source:0")
        verify(button && button.visible)
        mouseClick(button)
        const popup = findChild(prompt, "rulesCombatMultiAssignment-combat-source:0").targetPopup
        tryCompare(popup, "opened", true)
        tryVerify(() => target(2) !== null)
        mouseClick(target(0))
        mouseClick(target(1))
        compare(prompt.selectedTargets("combat-source:0").length, 2)
        verify(!target(2).enabled)
        verify(target(0).enabled && target(1).enabled)
        mouseClick(target(0))
        verify(target(2).enabled)
        mouseClick(target(2))
        compare(prompt.assignedCount, 1)
        keyClick(Qt.Key_Escape)
        tryCompare(popup, "opened", false)
        const confirm = findChild(prompt, "rulesConfirmCombat-blockers")
        verify(confirm.enabled)
        mouseClick(confirm)
        compare(transport.responses, 1)
        compare(transport.assignments.length, 2)
        compare(transport.assignments[0].sourceId, "combat-source:0")
        compare(transport.assignments[1].sourceId, "combat-source:0")
        compare(transport.assignments[0].targetId, "combat-target:1")
        compare(transport.assignments[1].targetId, "combat-target:2")
        prepare(2, 3)
        compare(prompt.assignedCount, 0)
    }

    function test_allAttackersRemainReachableWithUnlimitedNativeCapacity() {
        prepare(12, 12)
        mouseClick(findChild(prompt, "rulesCombatMultiAssignment-combat-source:0"))
        const popup = findChild(prompt, "rulesCombatMultiAssignment-combat-source:0").targetPopup
        tryCompare(popup, "opened", true)
        const list = popup.contentItem
        verify(list.contentHeight > list.height)
        for (let index = 0; index < 12; ++index) {
            list.positionViewAtIndex(index, ListView.Contain)
            list.forceLayout()
            tryVerify(() => target(index) !== null)
            mouseClick(target(index))
        }
        compare(prompt.selectedTargets("combat-source:0").length, 12)
        verify(target(11).activeFocus)
        keyClick(Qt.Key_Escape)
        tryCompare(popup, "opened", false)
        mouseClick(findChild(prompt, "rulesConfirmCombat-blockers"))
        compare(transport.assignments.length, 12)
    }

    function test_ordinaryBlockerUsesSingleTargetControl() {
        prepare(1, 3)
        const combo = findChild(prompt, "rulesCombatAssignment-combat-source:0")
        verify(combo.visible && combo.enabled)
        verify(!findChild(prompt, "rulesCombatMultiAssignment-combat-source:0").visible)
        combo.forceActiveFocus()
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Down)
        mouseClick(findChild(prompt, "rulesConfirmCombat-blockers"))
        compare(transport.assignments.length, 1)
        compare(transport.assignments[0].targetId, "combat-target:1")
    }

    function test_popupStaysInsideWindowAtBottom() {
        bottomAligned = true
        prepare(12, 12)
        const button = findChild(prompt, "rulesCombatMultiAssignment-combat-source:0")
        mouseClick(button)
        const popup = button.targetPopup
        tryCompare(popup, "opened", true)
        const list = popup.contentItem
        const point = list.mapToItem(testWindow.contentItem, 0, 0)
        verify(point.y >= 0)
        verify(point.y + list.height <= testWindow.height)
        verify(list.height >= 280, "Bottom placement must retain the full target viewport")
        verify(point.y < button.mapToItem(testWindow.contentItem, 0, 0).y)
    }
}
