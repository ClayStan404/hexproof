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

    ApplicationWindow { id: testWindow; width: 1000; height: 900; visible: true }
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
    Component { id: blockers; RulesCombatAssignmentPrompt {
        wsModel: null; cardCatalogModel: catalog; sourceModel: testRulesPrompt.session.promptCombat
        promptId: testRulesPrompt.session.promptId; assignmentKind: "blockers"
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

    Component { id: reveal; RulesRevealPrompt {
        wsModel: null; cardCatalogModel: catalog; cardModel: cards; promptId: 1
    } }
    Component { id: scalar; RulesScalarChoicePrompt {
        wsModel: null; choiceModel: cards; promptId: 1; minimumTotal: 2; maximumTotal: 3
    } }
    Component { id: number; RulesNumberPrompt {
        wsModel: null; promptId: 1; minimum: 0; maximum: 999
    } }
    Component { id: scry; RulesScryPrompt {
        wsModel: null; cardCatalogModel: catalog; cardModel: cards; promptId: 1
        destinations: ["libraryTop", "libraryBottom"]
    } }
    Component { id: context; RulesPromptContext {
        cardCatalogModel: catalog; sourceCardModel: cards; targetModel: cards
        contextText: "Choose a target for this spell, then confirm your selection."
    } }

    function init() {
        testWindow.requestActivate()
        tryVerify(() => testWindow.active)
        cards.clear()
        for (let i = 0; i < 8; ++i) {
            cards.append({responseId: "target:" + i, cardId: "card:" + i,
                kind: "card", label: "Raging Goblin " + i, objectId: "object:" + i,
                name: "Raging Goblin", setCode: "M10", collectorNumber: "154",
                token: false, oracle: "Haste", lethalDamage: 1, weight: 1, canRepeat: true})
        }
    }
    function cleanup() {
        testRulesPrompt.clear()
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

    function test_narrowCandidatesAndActionsRemainReachable_data() {
        let result = []
        for (const kind of ["targets", "combat", "selection", "order", "damage", "reveal", "scalar"])
            for (const language of ["en", "zh"])
                for (const scale of [1, 1.35])
                    result.push({tag: kind + "-" + language + "-" + scale,
                                 kind: kind, language: language, scale: scale})
        return result
    }
    function test_narrowCandidatesAndActionsRemainReachable(data) {
        Theme.uiScale = data.scale
        testTranslations.setLanguage(data.language)
        const components = {targets: targets, combat: combat, selection: selection,
                            order: order, damage: damage, reveal: reveal, scalar: scalar}
        const prompt = createTemporaryObject(components[data.kind], testWindow.contentItem,
                                             {width: 380})
        verify(prompt !== null)
        prompt.height = Qt.binding(() => prompt.implicitHeight)
        const list = candidateList(prompt)
        tryCompare(list, "count", 8)
        waitForRendering(prompt)
        verify(list.width >= prompt.width - 1,
               data.kind + " candidates should use the full decision dock width")
        verify(list.itemHeight >= Theme.size(data.kind === "scalar" ? 38 : 120),
               data.kind + " candidates lost their usable height")
        const confirmNames = {targets: "rulesConfirmTargets", combat: "rulesConfirmCombat-attackers",
                              selection: "rulesConfirmCards", order: "rulesConfirmOrder",
                              damage: "rulesConfirmDamage", reveal: "acknowledgeRevealButton",
                              scalar: "rulesConfirmChoices"}
        const confirm = findChild(prompt, confirmNames[data.kind])
        verify(confirm !== null)
        verify(confirm.mapToItem(prompt, 0, 0).y >= list.mapToItem(prompt, 0, list.height).y,
               "Confirmation must sit below the candidates")
        verify(confirm.width >= confirm.implicitWidth - 1,
               confirm.text + " must fit the translated label")
        verify(confirm.mapToItem(prompt, confirm.width, confirm.height).x <= prompt.width + 1)
        verify(confirm.mapToItem(prompt, confirm.width, confirm.height).y <= prompt.height + 1)
        if (data.kind === "combat") {
            for (let step = 0; step < 20 && !list.atXEnd; ++step)
                mouseWheel(list, list.width / 2, 20, 0, -240)
        } else {
            list.forceActiveFocus()
            keyClick(Qt.Key_End)
        }
        waitForRendering(prompt)
        verify(data.kind === "scalar" ? list.contentY > 0 : list.contentX > 0)
        verify(list.itemAtIndex(7) !== null, "Navigation must reach the last candidate")
        if (data.kind === "combat") {
            list.positionViewAtBeginning()
        } else {
            keyClick(Qt.Key_Home)
        }
        waitForRendering(prompt)
        verify(data.kind === "scalar" ? Math.abs(list.contentY - list.originY) < 1
                                     : Math.abs(list.contentX - list.originX) < 1)
        if (data.kind === "targets" || data.kind === "selection") {
            const tile = list.itemAtIndex(0)
            mouseClick(tile)
            compare(prompt.selectedCount, 1)
            verify(confirm.enabled, "A valid candidate must enable confirmation")
        }
    }

    function test_nativeAbilityTextFitsAndKeepsChoiceIdentity_data() {
        return [{tag: "normal", scale: 1}, {tag: "scaled", scale: 1.35}]
    }
    function test_nativeAbilityTextFitsAndKeepsChoiceIdentity(data) {
        Theme.uiScale = data.scale
        cards.clear()
        cards.append({responseId: "choice:0", label: "Ragavan, Nimble Pilferer - Creature 2 / 1",
                      weight: 1, canRepeat: false})
        cards.append({responseId: "choice:1", label: "Dash {1}{R} (You may cast this spell for its dash cost. If you do, it gains haste, and it's returned from the battlefield to its owner's hand at the beginning of the next end step.)",
                      weight: 1, canRepeat: false})
        const submissions = []
        const prompt = createTemporaryObject(scalar, testWindow.contentItem,
            {width: 330, minimumTotal: 0, maximumTotal: 1,
             wsModel: {respondRulesPromptWithChoices: (id, choices) => submissions.push({id: id, choices: choices})}})
        verify(prompt !== null)
        prompt.height = Qt.binding(() => prompt.implicitHeight)
        const list = findChild(prompt, "rulesScalarCandidates")
        tryCompare(list, "count", 2)
        waitForRendering(prompt)
        for (let index = 0; index < 2; ++index) {
            list.positionViewAtIndex(index, ListView.Contain)
            waitForRendering(list)
            const button = findChild(list.itemAtIndex(index), "rulesScalarChoice-choice:" + index)
            verify(button !== null)
            const origin = button.mapToItem(list, 0, 0)
            verify(origin.x >= 0 && origin.x + button.width <= list.width,
                   "A whole ability choice must fit without horizontal scrolling")
            verify(button.contentItem.width <= button.width)
            verify(button.contentItem.implicitHeight <= button.availableHeight + 1,
                   "The full Dash explanation must remain readable")
            verify(!button.contentItem.truncated)
        }
        const dash = findChild(list.itemAtIndex(1), "rulesScalarChoice-choice:1")
        mouseClick(dash)
        compare(prompt.selectedTotal, 0)
        compare(prompt.selectedIds.length, 0)
        verify(!findChild(prompt, "rulesScalarQuantity-choice:1").visible)
        verify(!findChild(prompt, "rulesConfirmChoices").visible)
        compare(submissions.length, 1)
        compare(submissions[0].choices[0], "choice:1")
        prompt.promptId = 2
        compare(prompt.selectedTotal, 0)
        compare(prompt.selectedIds.length, 0)
        const skip = findChild(prompt, "rulesSkipChoice")
        verify(skip.visible)
        compare(skip.text, "Choose none")
        mouseClick(skip)
        compare(submissions[1].id, 2)
        compare(submissions[1].choices, [])
    }

    function test_weightedAndRepeatedChoicesRetainConfirmation_data() {
        return [{tag:"weighted", weighted:true}, {tag:"repeat", weighted:false}]
    }
    function test_weightedAndRepeatedChoicesRetainConfirmation(data) {
        cards.clear()
        cards.append({responseId:"choice:0", label:"Weighted mode", weight:2, canRepeat:false})
        cards.append({responseId:"choice:1", label:"Repeatable mode", weight:1, canRepeat:true})
        const submissions = []
        const prompt = createTemporaryObject(scalar, testWindow.contentItem,
            {width:380, minimumTotal:3, maximumTotal:3,
             wsModel:{respondRulesPromptWithChoices:(id, choices) => submissions.push(choices)}})
        prompt.height = Qt.binding(() => prompt.implicitHeight)
        const list = findChild(prompt, "rulesScalarCandidates")
        tryCompare(list, "count", 2)
        waitForRendering(prompt)
        const repeat = findChild(list.itemAtIndex(1), "rulesScalarChoice-choice:1")
        if (data.weighted) mouseClick(findChild(list.itemAtIndex(0), "rulesScalarChoice-choice:0"))
        for (let count = 0; count < (data.weighted ? 1 : 3); ++count) mouseClick(repeat)
        compare(prompt.selectedTotal, 3)
        compare(submissions.length, 0)
        verify(findChild(prompt, "rulesScalarQuantity-choice:1").visible)
        verify(!findChild(prompt, "rulesSkipChoice").visible)
        const confirm = findChild(prompt, "rulesConfirmChoices")
        verify(confirm.visible && confirm.enabled)
        mouseClick(confirm)
        compare(submissions[0], data.weighted ? ["choice:0", "choice:1"] : ["choice:1", "choice:1", "choice:1"])
    }

    function test_narrowContextNumberAndScry_data() {
        return [{tag: "en", language: "en"}, {tag: "zh", language: "zh"}]
    }
    function test_narrowContextNumberAndScry(data) {
        Theme.uiScale = 1.35
        testTranslations.setLanguage(data.language)
        for (const component of [context, number, scry]) {
            const prompt = createTemporaryObject(component, testWindow.contentItem, {width: 380})
            verify(prompt !== null)
            prompt.height = Qt.binding(() => prompt.implicitHeight)
            waitForRendering(prompt)
            const targets = findChild(prompt, "rulesPromptContextTargets")
            if (targets) {
                const contextText = findChild(prompt, "rulesPromptContextText")
                verify(contextText.width > Theme.size(160))
                verify(targets.width >= prompt.width - 1)
                targets.forceActiveFocus()
                keyClick(Qt.Key_End)
                verify(targets.contentX > 0)
            }
            const confirm = findChild(prompt, "rulesConfirmNumber")
                            || findChild(prompt, "confirmScryButton")
            if (confirm) {
                verify(confirm.width >= confirm.implicitWidth - 1, confirm.text + ": " + confirm.width + " < " + confirm.implicitWidth)
                verify(confirm.mapToItem(prompt, confirm.width, 0).x <= prompt.width + 1)
                verify(confirm.mapToItem(prompt, 0, confirm.height).y <= prompt.height + 1)
            }
            prompt.destroy()
        }
    }

    function test_narrowMultiBlockPopupStaysWithinDecisionWidth_data() {
        return [{tag: "en", language: "en"}, {tag: "zh", language: "zh"}]
    }
    function test_narrowMultiBlockPopupStaysWithinDecisionWidth(data) {
        Theme.uiScale = 1.35
        testTranslations.setLanguage(data.language)
        const value = {roomId: "BLOCK1", gameId: "narrow-blocks", pending: true,
            supported: true, promptId: 44, kind: "chooseBlockers", options: [], choices: [],
            cards: [], targets: [], contextCards: [], contextTargets: [], damageTargets: [],
            scryDestinations: [], totalDamage: 0,
            combatSources: [{responseId: "guard", objectId: "guard", label: "Palace Guard",
                name: "Palace Guard", validTargetIds: [], mustAssignIfAble: false,
                maxAssignments: 12}], combatTargets: []}
        for (let index = 0; index < 12; ++index) {
            value.combatSources[0].validTargetIds.push("attacker-" + index)
            value.combatTargets.push({responseId: "attacker-" + index, kind: "attacker",
                objectId: "attacker-" + index, label: "Attacker " + index,
                minAssignments: 0, maxAssignments: 1, mustReceiveIfAble: false})
        }
        verify(testRulesPrompt.applyPrompt(value))
        const prompt = createTemporaryObject(blockers, testWindow.contentItem, {x: 600, width: 380})
        verify(prompt !== null)
        prompt.height = Qt.binding(() => prompt.implicitHeight)
        waitForRendering(prompt)
        const button = findChild(prompt, "rulesCombatMultiAssignment-guard")
        verify(button !== null)
        mouseClick(button)
        const popup = button.targetPopup
        tryCompare(popup, "opened", true)
        const list = popup.contentItem
        const start = list.mapToItem(prompt, 0, 0)
        verify(start.x >= 0)
        verify(start.x + list.width <= prompt.width)
        verify(list.height > Theme.size(200))
        list.positionViewAtIndex(11, ListView.End)
        waitForRendering(list)
        const lastTarget = list.itemAtIndex(11)
        verify(lastTarget !== null)
        mouseClick(lastTarget)
        compare(prompt.selectedTargets("guard")[0], "attacker-11")
        keyClick(Qt.Key_Escape)
        tryCompare(popup, "opened", false)
    }
}
