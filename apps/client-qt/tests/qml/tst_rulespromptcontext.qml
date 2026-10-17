// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "RulesPromptContext"
    when: windowShown
    property int serial: 500
    property var panel: null

    QtObject {
        id: responder
        property var responses: []
        function respondRulesPromptWithTargets(id, responseId, targets) {
            responses = responses.concat([{id: id, responseId: responseId, targets: targets}])
        }
        function respondRulesPromptWithAssignments(id, assignments) {
            responses = responses.concat([{id: id, assignments: assignments}])
        }
    }
    QtObject {
        id: controller
        property var rulesSession: testRulesPrompt.session
        property var interaction: null
        property var combatInteraction: combatSelection
        property var roomSession: ({maxSeats: 2})
        property bool rulesResponsePending: false
        property var cardCatalogModel: fakeCatalog
        property var wsModel: responder
        function stepLabel(step) { return "Waiting" }
        function promptTitle(kind, title) { return title }
        function promptRulesText(language) { return "" }
        function promptDetail(kind, detail) { return detail }
        function promptOptionLabel(kind, responseId, label) { return label }
    }
    QtObject {
        id: combatContext
        property bool contextActive: controller.interaction === combatContext
        property bool canRespond: !controller.rulesResponsePending
        property int promptRevision: 0
    }
    QtObject {
        id: combatController
        property var rulesSession: testRulesPrompt.session
        property var interaction: combatContext
        property int localSeat: 0
    }
    ForgeCombatInteraction { id: combatSelection; tableController: combatController }
    Connections {
        target: testRulesPrompt.session
        function onPromptChanged() { combatContext.promptRevision++ }
    }
    Component {
        id: panelComponent
        RulesPromptPanel {
            tableController: controller
            Component.onDestruction: testCase.panel = null
        }
    }

    ApplicationWindow {
        id: testWindow
        width: 720
        height: 180
        visible: true

        QtObject {
            id: fakeCatalog
            property int imageRevision: 0

            function tableImageSource(name, setCode, collectorNumber) {
                return ""
            }
        }

        ListModel {
            id: sourceCards
            ListElement {
                cardId: "context-card:0"
                name: "Circle of Protection: Red"
                setCode: "4ED"
                collectorNumber: "17"
                token: false
            }
        }

        ListModel {
            id: affectedTargets
            ListElement {
                responseId: "context-target:0"
                kind: "card"
                label: "Ball Lightning"
                objectId: "target-card-1"
                name: "Ball Lightning"
                setCode: "4ED"
                collectorNumber: "174"
                token: false
            }
            ListElement {
                responseId: "context-target:1"
                kind: "player"
                label: "Alice · Seat 1"
                objectId: ""
                name: ""
                setCode: ""
                collectorNumber: ""
                token: false
            }
        }

        RulesPromptContext {
            id: prompt
            anchors.fill: parent
            anchors.margins: 20
            cardCatalogModel: fakeCatalog
            sourceCardModel: sourceCards
            targetModel: affectedTargets
            contextText: "otherwise: \"3 damage is dealt.\""
        }
    }

    function init() {
        failOnWarning(/.*/)
        testWindow.requestActivate()
        tryVerify(() => testWindow.active)
        responder.responses = []
        controller.rulesResponsePending = false
        controller.interaction = null
        controller.roomSession = ({maxSeats: 2})
    }

    function cleanup() {
        if (panel) {
            panel.destroy()
            tryCompare(testCase, "panel", null)
        }
        controller.interaction = null
        testRulesPrompt.clear()
        Theme.uiScale = 1
        testTranslations.setLanguage("en")
        prompt.visible = true
        testWindow.height = 180
    }

    function targetPrompt(minimum) {
        return {roomId: "CONTEXT", gameId: "target-context", pending: true,
            promptId: ++serial, kind: "chooseBoardTargets", supported: true,
            title: "Choose targets", detail: "Long source rules text. ".repeat(24)
                + "\nChoose target instant card in a graveyard",
            contextText: "Long source rules text. ".repeat(24),
            options: [], choices: [], cards: [], targets: [
                {responseId: "target:0", kind: "card", objectId: "visible-graveyard-card",
                 label: "Brave the Elements", name: "Brave the Elements", setCode: "M14", collectorNumber: "10"},
                {responseId: "target:1", kind: "card", objectId: "visible-graveyard-card-2",
                 label: "Opt", name: "Opt", setCode: "XLN", collectorNumber: "65"}],
            minSelections: minimum, maxSelections: 2, cancellable: true,
            contextCards: [{id: "context-card:0", name: "Snapcaster Mage", setCode: "ISD", collectorNumber: "78"}],
            contextTargets: [], combatSources: [], combatTargets: [], damageTargets: [],
            scryDestinations: [], totalDamage: 0}
    }

    function test_targetFooterStaysVisibleThroughLongContext_data() {
        return [{tag: "normal", scale: 1}, {tag: "scaled", scale: 1.35}]
    }

    function test_targetFooterStaysVisibleThroughLongContext(data) {
        Theme.uiScale = data.scale
        prompt.visible = false
        testWindow.height = 500
        const value = targetPrompt(1)
        verify(testRulesPrompt.applyPrompt(value))
        panel = panelComponent.createObject(testWindow.contentItem, {width: 390, height: 245})
        verify(panel !== null)
        verify(waitForPolish(testWindow))
        const confirm = findChild(panel, "rulesConfirmTargets")
        verify(confirm !== null)
        const initial = confirm.mapToItem(panel, 0, 0)
        verify(initial.y >= 0 && initial.y + confirm.height <= panel.height,
               "Target confirmation must be visible without first scrolling the long context")
        const count = findChild(panel, "rulesTargetSelectionCount")
        verify(count !== null && count.visible)
        const countPoint = count.mapToItem(panel, 0, 0)
        verify(countPoint.y >= 0 && countPoint.y + count.height <= initial.y)
        const scroll = findChild(panel, "rulesPromptScroll")
        verify(scroll.height > 0)
        verify(scroll.contentHeight > scroll.height)
        const detail = findChild(panel, "rulesPromptDetail")
        compare(detail.text, "Choose target instant card in a graveyard")
        const context = findChild(panel, "rulesPromptContext")
        compare(context.contextText, value.contextText)
        verify(!findChild(context, "rulesPromptContextText").visible,
               "Repeated rules text must not consume the target-selection body")
        const source = findChild(context, "rulesPromptSourceCard")
        verify(source !== null, "Source inspection remains available")
        verify(context.hasContext)
        source.inspect()
        const preview = findChild(context, "rulesPromptCardPreview")
        verify(preview !== null && preview.visible)
        compare(preview.card.typeLine, value.contextText)
        const footer = findChild(panel, "rulesTargetSelectionFooter")
        compare(preview.avoidItems, [footer])
        preview.hide()
        for (let index = 0; index < 12 && !scroll.atYEnd; ++index) {
            mouseWheel(scroll, 2, 2, 0, -120)
            tryCompare(scroll, "moving", false)
        }
        tryVerify(() => scroll.contentY > 0)
        tryCompare(scroll, "moving", false)
        verify(waitForPolish(testWindow))
        compare(confirm.mapToItem(panel, 0, 0), initial)
        const target = findChild(panel, "rulesTarget-target:0")
        verify(target !== null)
        const targetPoint = target.mapToItem(scroll, target.width / 2, target.height / 2)
        verify(targetPoint.y >= 0 && targetPoint.y <= scroll.height,
               "Target center " + targetPoint.y + " must fit the scrolled body height " + scroll.height)
        mouseClick(target)
        verify(confirm.enabled)
        verify(count.text.includes("1"))
        controller.rulesResponsePending = true
        verify(!confirm.enabled, "The detached footer retains the pending-response guard")
        controller.rulesResponsePending = false
        mouseClick(confirm)
        compare(responder.responses.length, 1)
        compare(responder.responses[0], {id:value.promptId, responseId:"$submit", targets:["target:0"]})
        const replacement = targetPrompt(1)
        verify(testRulesPrompt.applyPrompt(replacement))
        verify(!confirm.enabled)
        verify(count.text.includes("0"), "A replacement decision clears the previous selection")
        replacement.kind = "chooseAction"
        replacement.promptId = ++serial
        verify(testRulesPrompt.applyPrompt(replacement))
        tryCompare(footer, "visible", false)
    }

    function test_optionalTargetCanConfirmNoneBeforeScrolling() {
        prompt.visible = false
        testWindow.height = 500
        verify(testRulesPrompt.applyPrompt(targetPrompt(0)))
        panel = panelComponent.createObject(testWindow.contentItem, {width: 390, height: 200})
        verify(waitForPolish(testWindow))
        const confirm = findChild(panel, "rulesConfirmTargets")
        const point = confirm.mapToItem(panel, 0, 0)
        verify(point.y >= 0 && point.y + confirm.height <= panel.height)
        verify(confirm.enabled)
        mouseClick(confirm)
        compare(responder.responses.length, 1)
        compare(responder.responses[0].targets, [])
    }

    function combatPrompt(kind, multiplePlayers) {
        const value = targetPrompt(0)
        value.gameId = "fixed-combat-footer"
        value.kind = kind
        value.title = "Combat declaration"
        value.detail = ""
        value.targets = []
        value.maxSelections = 0
        value.contextCards = []
        value.contextText = "Long combat context that must scroll above the declaration. ".repeat(20)
        value.combatTargets = multiplePlayers ? [
            {responseId: "combat-target:0", kind: "player", label: "First defender", seat: 1,
             minAssignments: 0, maxAssignments: 2, mustReceiveIfAble: false},
            {responseId: "combat-target:1", kind: "player", label: "Second defender", seat: 2,
             minAssignments: 0, maxAssignments: 2, mustReceiveIfAble: false}
        ] : [{responseId: "combat-target:0", kind: "attacker", objectId: "attacker-0",
              label: "Rust Harvester with a long public label that wraps onto several lines",
              minAssignments: 2, maxAssignments: 2, mustReceiveIfAble: false}]
        value.combatSources = []
        for (let index = 0; index < 2; ++index)
            value.combatSources.push({responseId: "combat-source:" + index, objectId: "blocker-" + index,
                label: "Creature with a long public label to keep pending instructions readable " + index,
                name: "Grizzly Bears", validTargetIds: value.combatTargets.map(target => target.responseId),
                mustAssignIfAble: false, maxAssignments: 1})
        return value
    }

    function fullyInside(item, container) {
        const point = item.mapToItem(container, 0, 0)
        verify(point.x >= -1 && point.y >= -1
               && point.x + item.width <= container.width + 1
               && point.y + item.height <= container.height + 1,
               item.objectName + " must fit completely: " + JSON.stringify(point)
               + " size " + item.width + "x" + item.height
               + " inside " + container.width + "x" + container.height)
    }

    function revealBodyItem(item) {
        const scroll = findChild(panel, "rulesPromptScroll")
        for (let step = 0; step < 50; ++step) {
            const point = item.mapToItem(scroll, item.width / 2, item.height / 2)
            if (point.y >= 1 && point.y < scroll.height - 1) return
            mouseWheel(scroll, 2, 2, 0, point.y < 0 ? 120 : -120)
            tryCompare(scroll, "moving", false)
        }
        fail("Cannot reach body control " + item.objectName)
    }

    function test_combatFooterRemainsFixedThroughMinimumRecovery_data() {
        const rows = []
        for (const language of ["en", "zh", "zh_TW", "ja", "fr", "de", "es", "it", "pt_BR"])
            for (const scale of [1, 1.35])
                rows.push({tag: language + "-" + scale, language: language, scale: scale})
        return rows
    }

    function test_combatFooterRemainsFixedThroughMinimumRecovery(data) {
        Theme.uiScale = data.scale
        testTranslations.setLanguage(data.language)
        prompt.visible = false
        testWindow.height = 600
        controller.interaction = combatContext
        const value = combatPrompt("chooseBlockers", false)
        verify(testRulesPrompt.applyPrompt(value))
        panel = panelComponent.createObject(testWindow.contentItem, {width: 390, height: 245})
        verify(waitForPolish(testWindow))
        const footer = findChild(panel, "rulesCombatSelectionFooter")
        const confirm = findChild(panel, "rulesConfirmCombat-blockers")
        const all = findChild(panel, "rulesBlockWithAll")
        const count = findChild(panel, "rulesCombatSelectionCount")
        const scroll = findChild(panel, "rulesPromptScroll")
        verify(footer.visible && !findChild(panel, "rulesTargetSelectionFooter").visible)
        fullyInside(footer, panel)
        fullyInside(confirm, footer)
        fullyInside(all, footer)
        fullyInside(count, footer)
        verify(confirm.contentItem.implicitHeight <= confirm.availableHeight + 1
               && all.contentItem.implicitHeight <= all.availableHeight + 1,
               "Both translated primary action labels must fit, wrapping when needed")
        panel.height = panel.minimumHeight
        verify(waitForPolish(testWindow))
        verify(scroll.height >= Theme.size(48) - 1, "The minimum panel budget retains a usable scroll region")
        fullyInside(footer, panel)
        fullyInside(confirm, footer)
        fullyInside(all, footer)
        panel.height = 245
        verify(waitForPolish(testWindow))
        const initial = confirm.mapToItem(panel, 0, 0)
        verify(scroll.height > 0)
        verify(scroll.mapToItem(panel, 0, scroll.height).y <= footer.y,
               "Scrolling content cannot overlap the fixed combat actions")
        verify(combatSelection.activate("blocker-0"))
        verify(waitForPolish(testWindow))
        verify(!confirm.enabled)
        verify(count.text.includes("1"))
        const reason = findChild(panel, "rulesCombatMinimumReason")
        verify(reason.visible && reason.text.includes(value.combatTargets[0].label))
        verify(scroll.contentHeight > scroll.height, "Long partial-minimum instructions scroll above the footer")
        mouseClick(confirm)
        compare(responder.responses.length, 0)
        const clear = findChild(panel, "rulesCombatClear-blockers")
        revealBodyItem(clear)
        compare(confirm.mapToItem(panel, 0, 0), initial)
        mouseClick(clear)
        verify(confirm.enabled && !reason.visible)
        verify(count.text.includes("0"))
        controller.rulesResponsePending = true
        verify(!confirm.enabled && !all.enabled)
        mouseClick(all)
        mouseClick(confirm)
        compare(Object.keys(combatSelection.assignments).length, 0)
        compare(responder.responses.length, 0)
        controller.rulesResponsePending = false
        mouseClick(all)
        verify(waitForPolish(testWindow))
        compare(Object.keys(combatSelection.assignments).length, 2)
        verify(confirm.enabled && !reason.visible && count.text.includes("2"))
        compare(confirm.mapToItem(panel, 0, 0), initial)
        fullyInside(confirm, footer)
        mouseClick(confirm)
        compare(responder.responses.length, 1)
        compare(responder.responses[0], {id: value.promptId, assignments: [
            {sourceId: "combat-source:0", targetId: "combat-target:0"},
            {sourceId: "combat-source:1", targetId: "combat-target:0"}]})
        verify(testRulesPrompt.applyPrompt(combatPrompt("chooseBlockers", false)))
        verify(count.text.includes("0"))
        controller.interaction = null
        verify(testRulesPrompt.applyPrompt(targetPrompt(0)))
        tryCompare(footer, "visible", false)
        verify(findChild(panel, "rulesTargetSelectionFooter").visible)
    }

    function test_combatBodyKeepsSpecificEngineError() {
        prompt.visible = false
        testWindow.height = 600
        controller.interaction = combatContext
        const value = combatPrompt("chooseBlockers", false)
        value.detail = "Assign each blocker to the attackers it can legally block."
        verify(testRulesPrompt.applyPrompt(value))
        panel = panelComponent.createObject(testWindow.contentItem, {width:390, height:245})
        verify(waitForPolish(testWindow))
        const detail = findChild(panel, "rulesPromptDetail")
        verify(!detail.visible, "The board's instructions replace only the exact generic declaration hint")
        value.promptId = ++serial
        value.detail = "Rust Harvester must be blocked by two or more creatures."
        verify(testRulesPrompt.applyPrompt(value))
        verify(waitForPolish(testWindow))
        verify(detail.visible)
        compare(detail.text, value.detail, "Specific engine rejection detail remains available in the scroll body")
    }

    function test_attackFooterFitsEveryTranslation_data() {
        return ["en", "zh", "zh_TW", "ja", "fr", "de", "es", "it", "pt_BR"]
            .map(language => ({tag: language, language: language}))
    }

    function test_attackFooterFitsEveryTranslation(data) {
        Theme.uiScale = 1.35
        testTranslations.setLanguage(data.language)
        prompt.visible = false
        testWindow.height = 600
        controller.interaction = combatContext
        controller.roomSession = ({maxSeats: 4})
        verify(testRulesPrompt.applyPrompt(combatPrompt("chooseAttackers", true)))
        panel = panelComponent.createObject(testWindow.contentItem, {width: 390})
        const createdPanel = panel
        panel.height = Qt.binding(() => createdPanel.minimumHeight)
        verify(waitForPolish(testWindow))
        const footer = findChild(panel, "rulesCombatSelectionFooter")
        const all = findChild(panel, "rulesAttackWithAll")
        const confirm = findChild(panel, "rulesConfirmCombat-attackers")
        fullyInside(footer, panel)
        fullyInside(all, footer)
        fullyInside(confirm, footer)
        fullyInside(findChild(panel, "rulesCombatSelectionCount"), footer)
        verify(all.contentItem.implicitHeight <= all.availableHeight + 1
               && confirm.contentItem.implicitHeight <= confirm.availableHeight + 1)
        verify(findChild(panel, "rulesPromptScroll").height >= Theme.size(48) - 1)
    }

    function test_combatFooterKeepsPendingSourceCancelListAndAttackAllMenu() {
        prompt.visible = false
        testWindow.height = 600
        controller.interaction = combatContext
        const value = combatPrompt("chooseAttackers", true)
        value.combatTargets[1].kind = "planeswalker"
        value.combatTargets[1].objectId = "planeswalker-1"
        delete value.combatTargets[1].seat
        verify(testRulesPrompt.applyPrompt(value))
        panel = panelComponent.createObject(testWindow.contentItem, {width: 390, height: 300})
        verify(waitForPolish(testWindow))
        const confirm = findChild(panel, "rulesConfirmCombat-attackers")
        const initial = confirm.mapToItem(panel, 0, 0)
        verify(combatSelection.activate("blocker-0"))
        verify(combatSelection.chosenSource !== null)
        verify(waitForPolish(testWindow))
        verify(!confirm.enabled, "Selecting a source still requires a destination")
        const cancel = findChild(panel, "rulesCombatCancelSelection-attackers")
        revealBodyItem(cancel)
        compare(confirm.mapToItem(panel, 0, 0), initial)
        mouseClick(cancel)
        compare(combatSelection.chosenSource, null)
        verify(confirm.enabled)
        const details = findChild(panel, "rulesCombatDetails-attackers")
        revealBodyItem(details)
        mouseClick(details)
        verify(panel.combatListShown)
        verify(waitForPolish(testWindow))
        compare(confirm.mapToItem(panel, 0, 0), initial)
        controller.roomSession = ({maxSeats: 4})
        verify(testRulesPrompt.applyPrompt(combatPrompt("chooseAttackers", true)))
        verify(waitForPolish(testWindow))
        verify(panel.combatListShown, "Multiplayer retains its inline assignment list")
        mouseClick(findChild(panel, "rulesAttackWithAll"))
        const menu = findChild(panel, "rulesAttackAllMenu")
        tryCompare(menu, "opened", true)
        compare(menu.count, 2)
        verify(waitForPolish(testWindow))
        waitForRendering(menu.itemAt(1))
        const second = menu.itemAt(1)
        mouseClick(second)
        compare(combatSelection.assignments, {"combat-source:0":"combat-target:1", "combat-source:1":"combat-target:1"})
        compare(menu.count, 0)
        tryCompare(menu, "opened", false)
        compare(combatSelection.assignments, {"combat-source:0":"combat-target:1", "combat-source:1":"combat-target:1"})
        mouseClick(confirm)
        compare(responder.responses.length, 1)
        compare(responder.responses[0].assignments.length, 2)
        verify(testRulesPrompt.applyPrompt(combatPrompt("chooseAttackers", true)))
        verify(waitForPolish(testWindow))
        verify(!panel.combatPrompt.showDetails, "Replacement prompt clears the optional-list toggle")
        compare(Object.keys(combatSelection.assignments).length, 0)
        const ended = combatPrompt("chooseAttackers", true)
        ended.pending = false
        verify(testRulesPrompt.applyPrompt(ended))
        tryVerify(() => !findChild(panel, "rulesCombatSelectionFooter").visible)
    }

    function test_presentsSourceEffectAndAffectedObjects() {
        verify(prompt.visible)
        verify(prompt.hasContext)
        compare(prompt.sourceCount, 1)
        compare(prompt.targetCount, 2)
        const textItem = findChild(prompt, "rulesPromptContextText")
        verify(textItem !== null)
        compare(textItem.text, "otherwise: \"3 damage is dealt.\"")
    }
}
