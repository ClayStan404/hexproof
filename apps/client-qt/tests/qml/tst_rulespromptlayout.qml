// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "RulesPromptLayout"
    when: windowShown

    ApplicationWindow { id: testWindow; width: 1000; height: 500; visible: true }
    QtObject {
        id: catalog
        property int imageRevision: 0
        function tableImageSource() { return "" }
    }
    ListModel {
        id: cards
        function validAssignments() { return true }
        function items() {
            let result = []
            for (let i = 0; i < count; ++i) result.push(get(i))
            return result
        }
    }
    Component { id: targets; RulesTargetSelectionPrompt {
        wsModel: null; cardCatalogModel: catalog; targetModel: cards
        promptId: 1; minimumSelections: 1; maximumSelections: 1; cancellable: true
    } }
    Component { id: combat; RulesCombatAssignmentPrompt {
        wsModel: null; cardCatalogModel: catalog; sourceModel: testRulesCombatSources
        promptId: 1; assignmentKind: "attackers"
    } }
    Component { id: selection; RulesCardSelectionPrompt {
        wsModel: null; cardCatalogModel: catalog; cardModel: cards
        promptId: 1; minimumSelections: 1; maximumSelections: 1; confirmationText: "Confirm cards"
    } }
    Component { id: order; RulesOrderPrompt {
        wsModel: null; cardCatalogModel: catalog; orderModel: cards; promptId: 1
    } }
    Component { id: damage; RulesDamageAssignmentPrompt {
        wsModel: null; cardCatalogModel: catalog; targetModel: cards
        promptId: 1; totalDamage: 3; deathtouch: false; damageSource: ({})
    } }

    function init() {
        cards.clear()
        for (let i = 0; i < 8; ++i) {
            cards.append({responseId: "target:" + i, cardId: "card:" + i,
                kind: "card", label: "Raging Goblin " + i, objectId: "object:" + i,
                name: "Raging Goblin", setCode: "M10", collectorNumber: "154",
                token: false, oracle: "Haste", lethalDamage: 1})
        }
    }
    function cleanup() {
        Theme.uiScale = 1
        testTranslations.setLanguage("en")
    }
    function test_targetActionsFitTranslatedLabels_data() {
        return [{tag: "en", language: "en"}, {tag: "zh", language: "zh"}]
    }
    function test_targetActionsFitTranslatedLabels(data) {
        Theme.uiScale = 1.35
        testTranslations.setLanguage(data.language)
        const prompt = createTemporaryObject(targets, testWindow.contentItem,
                                            {width: 680, height: Theme.size(142)})
        verify(prompt !== null)
        waitForRendering(prompt)
        const confirm = findChild(prompt, "rulesConfirmTargets")
        verify(confirm !== null)
        const row = confirm.parent
        for (const button of row.children) {
            if (button.text === undefined || !button.visible) continue
            verify(button.width >= button.implicitWidth - 1,
                   button.text + " needs " + button.implicitWidth + "px, has " + button.width)
            verify(button.mapToItem(prompt, button.width, 0).x <= prompt.width + 1,
                   button.text + " must stay within the prompt viewport")
        }
        verify(candidateList(prompt).width >= Theme.size(228))
    }
    function candidateList(item) {
        if (item.orientation !== undefined && item.positionViewAtIndex !== undefined)
            return item
        for (const child of item.children || []) {
            const found = candidateList(child)
            if (found) return found
        }
        return null
    }
    function test_candidatesRemainUsable_data() {
        let result = []
        for (const kind of ["targets", "combat", "selection", "order", "damage"])
            for (const scale of [1, 1.35])
                result.push({tag: kind + "-" + scale, kind: kind, scale: scale})
        return result
    }
    function test_candidatesRemainUsable(data) {
        Theme.uiScale = data.scale
        const components = {targets: targets, combat: combat, selection: selection,
                            order: order, damage: damage}
        const prompt = createTemporaryObject(components[data.kind], testWindow.contentItem,
                                            {width: 700, height: Theme.size(218)})
        verify(prompt !== null)
        const list = candidateList(prompt)
        verify(list !== null)
        tryCompare(list, "count", 8)
        waitForRendering(prompt)
        verify(list.width >= Theme.size(228),
               data.kind + " candidate viewport collapsed to " + list.width)
        if (data.kind === "damage") {
            const tile = list.itemAtIndex(0)
            const increment = findChild(tile, "rulesDamageIncrement-" + tile.responseId)
            const decrement = findChild(tile, "rulesDamageDecrement-" + tile.responseId)
            verify(increment !== null && decrement !== null)
            const rightEdge = increment.mapToItem(tile, increment.width, 0).x
            verify(rightEdge <= tile.width, "Damage controls must not cover the next candidate")
            mouseClick(increment)
            compare(prompt.assignedTo(tile.responseId), 1)
            mouseClick(decrement)
            compare(prompt.assignedTo(tile.responseId), 0)
        }
        list.positionViewAtIndex(7, ListView.End)
        waitForRendering(prompt)
        verify(list.itemAtIndex(7) !== null)
        verify(list.contentX > 0, "All later candidates remain reachable")
    }
}
