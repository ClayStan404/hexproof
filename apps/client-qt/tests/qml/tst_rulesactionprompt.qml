// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    property int sidebarWidth: 0
    property var panel: null
    readonly property string longAbilityLabel:
        "Walking Ballista: Remove a +1/+1 counter from Walking Ballista: It deals 1 damage to any target. Additional ability description "

    name: "RulesActionPrompt"
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 800; height: 420; visible: true
        QtObject {
            id: controller
            property var rulesSession: testRulesPrompt.session
            property bool rulesResponsePending: false
            property var cardCatalogModel: null
            property var wsModel: responder
            function stepLabel(step) { return "Waiting" }
            function promptTitle(kind, title) { return title }
            function promptDetail(kind, detail) { return detail }
            function promptOptionLabel(kind, responseId, label) { return label }
        }
        QtObject {
            id: responder
            property string lastResponseId: ""
            property int responseCount: 0
            function respondRulesPrompt(promptId, responseId) {
                lastResponseId = responseId
                responseCount++
                controller.rulesResponsePending = true
            }
        }
        Component {
            id: panelComponent
            RulesPromptPanel {
                anchors.left: testCase.sidebarWidth > 0 ? undefined : parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 10
                width: testCase.sidebarWidth
                tableController: controller
                Component.onDestruction: testCase.panel = null
            }
        }
    }

    function init() {
        sidebarWidth = 0
        testWindow.requestActivate()
        tryVerify(() => testWindow.active)
        mouseMove(testWindow.contentItem, 1, 1)
        testRulesPrompt.clear()
        controller.rulesResponsePending = false
        responder.lastResponseId = ""
        responder.responseCount = 0
        panel = panelComponent.createObject(testWindow.contentItem)
        verify(panel !== null)
    }
    function cleanup() {
        mouseMove(testWindow.contentItem, 1, 1)
        // Cancel the view's pending delegates while their model rows still
        // exist. Clearing a shared model before destroying a scrolled view
        // can make its queued incubation cancel an index from the old model.
        if (panel)
            panel.destroy()
        tryCompare(testCase, "panel", null)
        testRulesPrompt.clear()
        Theme.uiScale = 1.0
        waitForRendering(testWindow.contentItem)
    }

    function applyActionPrompt(options) {
        verify(testRulesPrompt.applyPrompt({
            roomId: "ACT001", gameId: "action-fixture", pending: true,
            promptId: 9, kind: "chooseAction", supported: true,
            title: "Choose an action", detail: "Choose a spell or activated ability, or pass priority.",
            options: options, choices: [], cards: [], targets: [], contextCards: [],
            contextTargets: [], combatSources: [], combatTargets: [], damageTargets: [],
            scryDestinations: [], totalDamage: 0
        }))
    }

    function relativeLuminance(color) {
        function linear(value) {
            return value <= 0.04045 ? value / 12.92
                                   : Math.pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.r) + 0.7152 * linear(color.g)
               + 0.0722 * linear(color.b)
    }

    function test_basicActionsStayVisibleBeyondLongAbilityList_data() {
        return [
            {tag: "pass", action: "$pass", label: "Pass priority", width: 800, scale: 1.0},
            {tag: "resolve", action: "$pass-stack", label: "Resolve current stack", width: 620, scale: 1.25},
            {tag: "payment", action: "$pay", label: "Confirm payment", width: 620, scale: 1.0},
            {tag: "cancel", action: "$cancel", label: "Cancel", width: 620, scale: 1.0}
        ]
    }
    function test_basicActionsStayVisibleBeyondLongAbilityList(data) {
        testWindow.width = data.width
        Theme.uiScale = data.scale
        const options = []
        for (let index = 0; index < 12; index++) {
            options.push({responseId: "action:" + index, kind: "activate",
                          label: longAbilityLabel + index})
        }
        options.push({responseId: data.action, kind: "special", label: data.label})
        for (const entry of [{id: "$pass", label: "Pass priority"},
                             {id: "$pass-stack", label: "Resolve current stack"},
                             {id: "$pay", label: "Confirm payment"},
                             {id: "$cancel", label: "Cancel"}]) {
            if (entry.id !== data.action)
                options.push({responseId: entry.id, kind: "special", label: entry.label})
        }
        applyActionPrompt(options)
        const fixed = findChild(panel, "rulesFixedPromptActions")
        const list = findChild(panel, "rulesPromptOptions")
        const button = findChild(fixed, "rulesPromptOption-" + data.action)
        verify(button !== null)
        waitForRendering(panel)
        tryVerify(() => list.contentWidth > list.width)
        verify(button.visible && button.enabled)
        const position = button.mapToItem(panel, 0, 0)
        verify(position.x >= 0 && position.x + button.width <= panel.width)
        verify(position.y >= 0 && position.y + button.height <= panel.height)
        const first = findChild(list, "rulesPromptOption-action:0")
        verify(first.width <= Theme.size(260))
        compare(first.contentItem.wrapMode, Text.Wrap)
        list.contentX = list.contentWidth - list.width
        const scroll = findChild(panel, "rulesPromptScroll")
        scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height)
        mouseClick(button)
        compare(responder.lastResponseId, data.action)
        compare(responder.responseCount, 1)
        verify(!button.enabled)
    }

    function test_actionTooltipStaysInsideSidebarAndOnlyExplainsTruncatedLabels_data() {
        return [{tag: "normal", scale: 1.0}, {tag: "scaled", scale: 1.35}]
    }
    function test_actionTooltipStaysInsideSidebarAndOnlyExplainsTruncatedLabels(data) {
        testWindow.width = 800
        sidebarWidth = 380
        Theme.uiScale = data.scale
        applyActionPrompt([
            {responseId: "action:0", kind: "activate", label: longAbilityLabel.repeat(2) + "0"},
            {responseId: "action:1", kind: "activate", label: longAbilityLabel.repeat(2) + "1"},
            {responseId: "action:2", kind: "activate", label: "Tap for mana"},
            {responseId: "$pass", kind: "special", label: "Pass priority"}
        ])
        waitForRendering(panel)
        const list = findChild(panel, "rulesPromptOptions")
        list.positionViewAtIndex(1, ListView.Contain)
        waitForRendering(panel)
        const longAction = findChild(list, "rulesPromptOption-action:1")
        verify(longAction !== null, "The scrolled action must exist")
        verify(longAction.contentItem.truncated,
               "The long action must be visibly truncated before hovering")
        const longTooltip = findChild(longAction, "rulesPromptActionTooltip-action:1")
        verify(longTooltip !== null)
        mouseMove(longAction, longAction.width / 2, longAction.height / 2)
        tryCompare(longAction, "hovered", true)
        tryCompare(longTooltip, "opened", true)
        waitForRendering(longTooltip.background)
        const position = longTooltip.background.mapToItem(panel, 0, 0)
        verify(position.x >= -1, "The action explanation must stay out of the battlefield")
        verify(position.x + longTooltip.background.width <= panel.width + 1,
               "The action explanation must fit the reserved sidebar")
        compare(longTooltip.contentItem.text, longAction.text)
        compare(longTooltip.background.color.a, 1)
        const foreground = relativeLuminance(longTooltip.contentItem.color)
        const background = relativeLuminance(longTooltip.background.color)
        const contrast = (Math.max(foreground, background) + 0.05)
                         / (Math.min(foreground, background) + 0.05)
        verify(contrast >= 4.5, "Action explanation text needs readable contrast: " + contrast)

        mouseMove(testWindow.contentItem, 1, 1)
        tryCompare(longTooltip, "opened", false)
        list.positionViewAtIndex(2, ListView.Contain)
        waitForRendering(panel)
        const shortAction = findChild(list, "rulesPromptOption-action:2")
        verify(shortAction !== null && !shortAction.contentItem.truncated)
        const shortTooltip = findChild(shortAction, "rulesPromptActionTooltip-action:2")
        verify(shortTooltip !== null)
        mouseMove(shortAction, shortAction.width / 2, shortAction.height / 2)
        tryCompare(shortAction, "hovered", true)
        wait(shortTooltip.delay + 100)
        verify(!shortTooltip.opened && !shortTooltip.visible,
               "Fully visible action labels should not open an extra explanation")
    }
}
