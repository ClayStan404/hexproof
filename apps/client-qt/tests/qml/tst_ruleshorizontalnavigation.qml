// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "RulesHorizontalNavigation"
    when: windowShown
    property string mode: "combat"
    property int serial: 120

    ApplicationWindow {
        id: testWindow
        width: 900; height: 340; visible: true
        QtObject {
            id: transport
            property var assignments: []
            property var selected: []
            property int responses: 0
            function respondRulesPromptWithAssignments(id, values) { assignments = values; responses++ }
            function respondRulesPromptWithCards(id, response, values) { selected = values; responses++ }
            function respondRulesPromptWithTargets(id, response, values) { selected = values; responses++ }
        }
        Loader {
            id: promptLoader
            anchors.fill: parent
            anchors.margins: 20
            sourceComponent: mode === "combat" ? combatComponent
                             : mode === "cards" ? cardsComponent
                             : mode === "targets" ? targetsComponent : scryComponent
        }
        Component {
            id: combatComponent
            RulesCombatAssignmentPrompt {
                wsModel: transport
                cardCatalogModel: null
                sourceModel: testRulesPrompt.session.promptCombat
                promptId: testRulesPrompt.session.promptId
                assignmentKind: "attackers"
            }
        }
        Component {
            id: cardsComponent
            RulesCardSelectionPrompt {
                wsModel: transport
                cardCatalogModel: null
                cardModel: testRulesPrompt.session.promptCards
                promptId: testRulesPrompt.session.promptId
                minimumSelections: 1; maximumSelections: 1
                confirmationText: "Confirm cards"
            }
        }
        Component {
            id: targetsComponent
            RulesTargetSelectionPrompt {
                wsModel: transport
                cardCatalogModel: null
                targetModel: testRulesPrompt.session.promptTargets
                promptId: testRulesPrompt.session.promptId
                minimumSelections: 1; maximumSelections: 1; cancellable: false
            }
        }
        Component {
            id: scryComponent
            RulesScryPrompt {
                wsModel: transport
                cardCatalogModel: null
                cardModel: testRulesPrompt.session.promptCards
                destinations: testRulesPrompt.session.promptScryDestinations
                promptId: testRulesPrompt.session.promptId
            }
        }
    }

    function init() {
        transport.responses = 0
        transport.assignments = []
        transport.selected = []
        Theme.uiScale = 1.0
        testWindow.requestActivate()
        tryVerify(() => testWindow.active)
    }
    function cleanup() { testRulesPrompt.clear() }

    function prepare(kind) {
        mode = kind
        const value = {
            roomId: "NAV001", gameId: "navigation", pending: true, supported: true,
            promptId: ++serial, kind: kind === "combat" ? "chooseAttackers"
                    : kind === "cards" ? "chooseCards"
                    : kind === "targets" ? "chooseBoardTargets" : "scry",
            options: [], choices: [], cards: [], targets: [], contextCards: [], contextTargets: [],
            combatSources: [], combatTargets: [], damageTargets: [], totalDamage: 0,
            scryDestinations: kind === "scry" ? ["libraryTop", "libraryBottom", "graveyard"] : [],
            minCardSelections: kind === "cards" ? 1 : 0, maxCardSelections: kind === "cards" ? 1 : 0,
            minSelections: kind === "targets" ? 1 : 0, maxSelections: kind === "targets" ? 1 : 0
        }
        if (kind === "combat") {
            value.combatTargets = [{responseId: "defender", objectId: "player-1",
                                    kind: "player", label: "Other player",
                                    minAssignments: 0, maxAssignments: 10}]
            for (let index = 0; index < 10; ++index)
                value.combatSources.push({responseId: "source-" + index, objectId: "card-" + index,
                    label: "Creature " + index, name: "Creature " + index,
                    validTargetIds: ["defender"], mustAssignIfAble: false})
        } else {
            for (let index = 0; index < 16; ++index) {
                value.cards.push({id: (kind === "scry" ? "scry:" : "card-") + index, name: "Card " + index})
                value.targets.push({responseId: "target-" + index, objectId: "card-" + index,
                                    kind: "permanent", label: "Target " + index, name: "Target " + index})
            }
        }
        verify(testRulesPrompt.applyPrompt(value))
        tryCompare(promptLoader, "status", Loader.Ready)
        waitForRendering(promptLoader.item)
    }

    function contained(item, viewport) {
        if (!item)
            return false
        const position = item.mapToItem(viewport, 0, 0)
        return position.x >= -1 && position.x + item.width <= viewport.width + 1
               && position.y >= 0 && position.y + item.height <= viewport.height + 1
    }

    function wheelToEnd(list) {
        const start = list.contentX
        for (let count = 0; count < 30 && list.contentX < list.originX + list.contentWidth - list.width - 1; ++count)
            mouseWheel(list, list.width / 2, 20, 0, -240)
        verify(list.contentX > start, "A normal vertical mouse wheel must move the horizontal list")
        tryVerify(() => list.atXEnd)
        const bar = findChild(list, list.objectName + "ScrollBar")
        verify(bar && bar.visible && bar.size < 1)
    }

    function test_combatWheelReachesAllCandidatesAndKeepsDeclareUsable() {
        prepare("combat")
        const list = findChild(promptLoader.item, "rulesCombatCandidates-attackers")
        const confirm = findChild(promptLoader.item, "rulesConfirmCombat-attackers")
        compare(list.count, 10)
        wheelToEnd(list)
        const last = findChild(list, "rulesCombatAssignment-source-9")
        verify(contained(last, list))
        last.forceActiveFocus()
        tryVerify(() => last.activeFocus)
        keyClick(Qt.Key_Down)
        compare(promptLoader.item.assignments["source-9"], "defender")
        verify(confirm.enabled, "Confirm disabled: " + JSON.stringify(promptLoader.item.selectedIds || promptLoader.item.assignments))
        verify(contained(confirm, promptLoader.item), "Confirm geometry: " + JSON.stringify(confirm.mapToItem(promptLoader.item, 0, 0)) + " " + confirm.width + "x" + confirm.height + " in " + promptLoader.item.width + "x" + promptLoader.item.height)
        mouseClick(confirm)
        compare(transport.responses, 1)
        compare(transport.assignments.length, 1)
        compare(transport.assignments[0].sourceId, "source-9")
    }

    function test_combatTabFocusRevealsOffscreenAssignments() {
        prepare("combat")
        const list = findChild(promptLoader.item, "rulesCombatCandidates-attackers")
        const first = findChild(list, "rulesCombatAssignment-source-0")
        first.forceActiveFocus()
        for (let index = 0; index < 10; ++index) {
            const box = findChild(list, "rulesCombatAssignment-source-" + index)
            tryVerify(() => box && box.activeFocus, 5000, "Tab should reach source-" + index + "; focused " + testWindow.activeFocusItem)
            tryVerify(() => contained(box, list))
            keyClick(Qt.Key_Down)
            compare(promptLoader.item.assignments["source-" + index], "defender")
            if (index < 9)
                keyClick(Qt.Key_Tab)
        }
        verify(list.contentX > 0)
        const confirm = findChild(promptLoader.item, "rulesConfirmCombat-attackers")
        verify(confirm.enabled, "Confirm disabled: " + JSON.stringify(promptLoader.item.selectedIds || promptLoader.item.assignments))
        verify(contained(confirm, promptLoader.item), "Confirm geometry: " + JSON.stringify(confirm.mapToItem(promptLoader.item, 0, 0)) + " " + confirm.width + "x" + confirm.height + " in " + promptLoader.item.width + "x" + promptLoader.item.height)
        mouseClick(confirm)
        compare(transport.assignments.length, 10)
    }

    function test_selectionWheelAndKeyboard_data() {
        return [{tag: "cards", kind: "cards", list: "rulesCardCandidates", prefix: "rulesCardCandidate-card-", confirm: "rulesConfirmCards", chosen: "card-15"},
                {tag: "targets", kind: "targets", list: "rulesTargetCandidates", prefix: "rulesTarget-target-", confirm: "rulesConfirmTargets", chosen: "target-15"}]
    }
    function test_selectionWheelAndKeyboard(data) {
        prepare(data.kind)
        const list = findChild(promptLoader.item, data.list)
        wheelToEnd(list)
        const last = findChild(list, data.prefix + "15")
        verify(contained(last, list))
        last.forceActiveFocus()
        tryVerify(() => last.activeFocus)
        keyClick(Qt.Key_Space)
        const confirm = findChild(promptLoader.item, data.confirm)
        verify(confirm.enabled, "Confirm disabled: " + JSON.stringify(promptLoader.item.selectedIds || promptLoader.item.assignments))
        verify(contained(confirm, promptLoader.item), "Confirm geometry: " + JSON.stringify(confirm.mapToItem(promptLoader.item, 0, 0)) + " " + confirm.width + "x" + confirm.height + " in " + promptLoader.item.width + "x" + promptLoader.item.height)
        mouseClick(confirm)
        compare(transport.selected[0], data.chosen)
    }

    function test_nestedScryWheelMovesOneLevelAtATime() {
        prepare("scry")
        const outer = findChild(promptLoader.item, "rulesScryPileList")
        const inner = findChild(promptLoader.item, "rulesScryCards-libraryTop")
        verify(inner.contentWidth > inner.width && outer.contentWidth > outer.width)
        const outside = outer.contentX
        mouseWheel(inner, inner.width / 2, 20, 0, -120)
        tryVerify(() => inner.contentX > 0)
        compare(outer.contentX, outside)
        inner.positionViewAtEnd()
        waitForRendering(inner)
        mouseWheel(inner, inner.width / 2, 20, 0, -120)
        tryVerify(() => outer.contentX > outside)
    }
}
