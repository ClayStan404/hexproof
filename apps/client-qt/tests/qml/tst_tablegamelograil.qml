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
        property bool showGameLogRail: true
        property real gameLogRailWidth: 200
        property bool canChat: true
    }

    ListModel {
        id: gameLogModel
        ListElement { entryText: "Alice joined"; entryKind: "system" }
        ListElement { entryText: "Hello"; entryKind: "chat" }
    }

    TableGameLogRail {
        id: rail
        parent: testWindow.contentItem
        width: 160
        height: 500
        tableController: fakeTable
        gameLogModel: gameLogModel
    }

    function init() {
        fakeTable.showGameLogRail = true
        fakeTable.canChat = true
        fakeActions.submitCalls = 0
        rail.chatInput.clear()
        gameLogModel.clear()
        gameLogModel.append({"entryText": "Alice joined",
                             "entryKind": "system"})
        gameLogModel.append({"entryText": "Hello",
                             "entryKind": "chat"})
    }

    function test_exposesChatInputAndLog() {
        verify(rail.visible)
        compare(rail.chatInput.objectName, "gameChatInput")
        compare(findChild(rail, "gameLog").count, 2)
        compare(rail.width, 160)
    }

    function test_forwardsChatActions() {
        rail.chatInput.text = "hello"
        rail.chatInput.accepted()
        compare(fakeActions.submitCalls, 1)
    }

    function test_showsInteractiveScrollBarForOverflowingLog() {
        const scrollBar = findChild(rail, "gameLogScrollBar")
        verify(scrollBar !== null)
        compare(scrollBar.policy, ScrollBar.AsNeeded)
        verify(scrollBar.interactive)

        for (let index = 0; index < 80; ++index) {
            gameLogModel.append({"entryText": "Long game log entry " + index,
                                 "entryKind": "system"})
        }
        tryVerify(() => scrollBar.visible && scrollBar.size < 1)
    }

    function test_tracksVisibilityAndChatAvailability() {
        fakeTable.showGameLogRail = false
        verify(!rail.visible)
        fakeTable.showGameLogRail = true
        fakeTable.canChat = false
        verify(!rail.chatInput.enabled)
    }
}
