// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "TableGameLogRail"
    width: 640
    height: 520
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 640
        height: 520
        visible: true
    }

    QtObject {
        id: fakeActions
        property int submitCalls: 0
        function submitChatMessage() { ++submitCalls; return true }
    }

    Item {
        id: fakeTable
        property var cardActions: fakeActions
        property var tableGameLog: []
        property bool showGameLogRail: true
        property real gameLogRailWidth: 200
        property bool canChat: true
    }

    TableGameLogRail {
        id: rail
        parent: testWindow.contentItem
        width: 160
        height: 500
        tableController: fakeTable
    }

    function init() {
        testTranslations.setLanguage("en")
        fakeTable.showGameLogRail = true
        fakeTable.canChat = true
        fakeActions.submitCalls = 0
        rail.chatInput.clear()
        fakeTable.tableGameLog = [
            {"id": 1, "text": "Alice joined", "kind": "system"},
            {"id": 2, "text": "Hello", "kind": "chat"}
        ]
    }

    function cleanup() {
        wait(0)
        testTranslations.setLanguage("en")
    }

    function longEntries(count) {
        const entries = []
        for (let index = 0; index < count; ++index) {
            entries.push({
                "id": index + 1,
                "text": "Long game log entry " + index,
                "kind": "system",
                "seat": index % 2
            })
        }
        return entries
    }

    function test_exposesChatInputAndLog() {
        verify(rail.visible)
        compare(rail.chatInput.objectName, "gameChatInput")
        compare(findChild(rail, "gameLog").count, 2)
        compare(rail.width, 160)
    }

    function test_tracksDirectTableLogReplacement() {
        const log = findChild(rail, "gameLog")
        verify(log !== null)

        fakeTable.tableGameLog = [{
            "id": 3, "text": "Replacement", "kind": "system"
        }]

        tryCompare(log, "count", 1)
        tryVerify(() => log.itemAtIndex(0) !== null
                         && log.itemAtIndex(0).text === "Replacement")
        compare(log.itemAtIndex(0).text, "Replacement")
    }

    function test_appendsWithoutReplacingMatchingDelegates() {
        const log = findChild(rail, "gameLog")
        verify(log !== null)
        tryVerify(() => log.itemAtIndex(0) !== null)
        const firstDelegate = log.itemAtIndex(0)

        fakeTable.tableGameLog = fakeTable.tableGameLog.concat([{
            "id": 3, "text": "Appended", "kind": "system", "seat": 0
        }])

        tryCompare(log, "count", 3)
        compare(log.itemAtIndex(0), firstDelegate)
    }

    function test_translatesDirectTableLogEntries() {
        const log = findChild(rail, "gameLog")
        verify(log !== null)

        testTranslations.setLanguage("zh")
        fakeTable.tableGameLog = [{
            "id": 3,
            "text": "Alice advanced to the Attackers step.",
            "kind": "system"
        }]

        tryCompare(log, "count", 1)
        tryVerify(() => log.itemAtIndex(0) !== null
                         && log.itemAtIndex(0).text
                            === "Alice 推进到宣攻阶段。")
        compare(log.itemAtIndex(0).text, "Alice 推进到宣攻阶段。")
    }

    function test_forwardsChatActions() {
        rail.chatInput.text = "hello"
        rail.chatInput.accepted()
        compare(fakeActions.submitCalls, 1)
    }

    function test_translatesRulesButKeepsIdenticalChatLiteral() {
        testTranslations.setLanguage("zh")
        fakeTable.tableGameLog = [
            {id: 10, kind: "rules_life", text: "Alice: life 20 → 17."},
            {id: 11, kind: "chat", text: "Alice: life 20 → 17."}
        ]
        const log = findChild(rail, "gameLog")
        tryCompare(log, "count", 2)
        tryVerify(() => log.itemAtIndex(0) !== null && log.itemAtIndex(1) !== null)
        compare(log.itemAtIndex(0).text, "Alice：生命 20 → 17。")
        compare(log.itemAtIndex(1).text, "Alice: life 20 → 17.")
    }

    function test_showsInteractiveScrollBarForOverflowingLog() {
        const scrollBar = findChild(rail, "gameLogScrollBar")
        verify(scrollBar !== null)
        compare(scrollBar.policy, ScrollBar.AsNeeded)
        verify(scrollBar.interactive)

        const entries = fakeTable.tableGameLog.slice()
        for (let index = 0; index < 80; ++index) {
            entries.push({
                "id": index + 3,
                "text": "Long game log entry " + index,
                "kind": "system"
            })
        }
        fakeTable.tableGameLog = entries
        tryVerify(() => scrollBar.visible && scrollBar.size < 1)
    }

    function test_appendStaysPutWhenReadingOlderEntries() {
        const log = findChild(rail, "gameLog")
        fakeTable.tableGameLog = longEntries(80)
        tryVerify(() => log.contentHeight > log.height)
        wait(0)
        log.positionViewAtIndex(20, ListView.Beginning)
        wait(0)
        const previousContentY = log.contentY

        fakeTable.tableGameLog = fakeTable.tableGameLog.concat([{
            "id": 81, "text": "Newest entry", "kind": "system", "seat": 0
        }])
        wait(1)

        verify(Math.abs(log.contentY - previousContentY) < 2)
    }

    function test_appendFollowsWhenPinnedToEnd() {
        const log = findChild(rail, "gameLog")
        fakeTable.tableGameLog = longEntries(80)
        tryVerify(() => log.contentHeight > log.height)
        wait(0)
        log.positionViewAtEnd()
        wait(0)

        fakeTable.tableGameLog = fakeTable.tableGameLog.concat([{
            "id": 81, "text": "Newest entry", "kind": "system", "seat": 0
        }])

        tryVerify(() => log.contentY
                         >= log.originY + log.contentHeight - log.height - 2)
    }

    function test_prefixCorrectionPreservesUsefulVisibleIndex() {
        const log = findChild(rail, "gameLog")
        fakeTable.tableGameLog = longEntries(80)
        tryVerify(() => log.contentHeight > log.height)
        wait(0)
        log.positionViewAtIndex(25, ListView.Beginning)
        wait(0)
        const previousIndex = log.indexAt(1, log.contentY + 1)
        verify(previousIndex >= 24 && previousIndex <= 26)

        const corrected = longEntries(60)
        corrected[0].text = "Corrected first entry"
        fakeTable.tableGameLog = corrected
        wait(1)

        const visibleIndex = log.indexAt(1, log.contentY + 1)
        verify(Math.abs(visibleIndex - previousIndex) <= 1)
        verify(log.contentY
               < log.originY + log.contentHeight - log.height - 2)
    }

    function test_tracksVisibilityAndChatAvailability() {
        fakeTable.showGameLogRail = false
        verify(!rail.visible)
        fakeTable.showGameLogRail = true
        fakeTable.canChat = false
        verify(!rail.chatInput.enabled)
    }
}
