// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "TournamentChat"
    when: windowShown
    property real previousScale: 1

    ApplicationWindow {
        id: testWindow
        width: 600
        height: 720
        visible: true
        TournamentChat {
            id: chat
            anchors.fill: parent
            tournamentModel: tournament
            wsModel: commands
        }
    }
    QtObject {
        id: tournament
        property string tournamentId: "review-event"
        property var chatMessages: []
        signal inTournamentChanged()
    }
    QtObject {
        id: commands
        property bool connected: true
        function sendTournamentChat(text) { return true }
    }
    Component {
        id: prefilledChat
        TournamentChat {
            tournamentModel: tournament
            wsModel: commands
            width: 640
            height: 851
        }
    }

    function init() {
        previousScale = Theme.uiScale
        tournament.chatMessages = []
        tournament.tournamentId = "event-" + Date.now()
        tournament.chatMessages = Array.from({length: 100}, (_, index) => ({
            sequence: index + 1, displayName: "Player " + index,
            text: "Message " + index + " with enough history to scroll"
        }))
        testWindow.requestActivate()
        const list = findChild(chat, "tournamentChatMessages")
        tryVerify(() => list.atYEnd && list.contentHeight > list.height * 2)
    }

    function cleanup() {
        Theme.uiScale = previousScale
        testWindow.width = 600
        testWindow.height = 720
        wait(50)
    }

    function dragScrollBar(fraction) {
        const bar = findChild(chat, "tournamentChatScrollBar")
        mousePress(bar, bar.width / 2, (bar.visualPosition + bar.visualSize / 2) * bar.height)
        mouseMove(bar, bar.width / 2, bar.height * fraction, 100)
        mouseRelease(bar, bar.width / 2, bar.height * fraction)
    }

    function visibleAnchor(list) {
        let index = -1
        for (let offset = 0; offset < 80 && index < 0; ++offset)
            index = list.indexAt(1, list.contentY + offset)
        verify(index >= 0)
        return {sequence: list.model.get(index).sequence,
                offset: list.itemAtIndex(index).y - list.contentY}
    }

    function appendMessage(sequence, trimOldest) {
        const previous = trimOldest ? tournament.chatMessages.slice(1) : tournament.chatMessages
        tournament.chatMessages = previous.concat([{
            sequence: sequence, displayName: "Another player", text: "A new incoming message"
        }])
    }

    function test_draggedHistorySurvivesAppendAndRetentionTrimming() {
        const list = findChild(chat, "tournamentChatMessages")
        dragScrollBar(0.4)
        tryVerify(() => !list.atYEnd && !list.followEnd)
        const anchor = visibleAnchor(list)
        appendMessage(101, true)
        waitForRendering(list)
        const retained = visibleAnchor(list)
        compare(retained.sequence, anchor.sequence)
        verify(Math.abs(retained.offset - anchor.offset) <= 1)
        verify(!list.atYEnd)

        dragScrollBar(1)
        tryVerify(() => list.atYEnd && list.followEnd)
        appendMessage(102, true)
        tryVerify(() => list.atYEnd && list.model.get(list.count - 1).sequence === 102)
    }

    function test_messageDuringScrollbarDragDoesNotPullBackToEnd() {
        const list = findChild(chat, "tournamentChatMessages")
        const bar = findChild(chat, "tournamentChatScrollBar")
        mousePress(bar, bar.width / 2, (bar.visualPosition + bar.visualSize / 2) * bar.height)
        mouseMove(bar, bar.width / 2, bar.height * 0.4, 100)
        verify(bar.pressed && !list.followEnd)
        const anchor = visibleAnchor(list)
        appendMessage(101, false)
        waitForRendering(list)
        compare(visibleAnchor(list).sequence, anchor.sequence)
        verify(!list.atYEnd)
        mouseRelease(bar, bar.width / 2, bar.height * 0.4)
        verify(!list.followEnd)
    }

    function test_prefilledHistoryKeepsAnchorAfterCreationAndDrag() {
        Theme.uiScale = 1.26375
        testWindow.width = 640
        testWindow.height = 851
        tournament.chatMessages = Array.from({length: 100}, (_, index) => ({
            sequence: index + 1, displayName: "Player " + index,
            text: "Message " + index + ": retained event history for reading-position verification."
        }))
        const freshChat = createTemporaryObject(prefilledChat, testWindow.contentItem)
        verify(freshChat)
        const list = findChild(freshChat, "tournamentChatMessages")
        const bar = findChild(freshChat, "tournamentChatScrollBar")
        tryVerify(() => list.atYEnd)
        waitForRendering(list)
        const startY = (bar.visualPosition + bar.visualSize / 2) * bar.height
        mousePress(bar, bar.width / 2, startY)
        for (let step = 1; step <= 12; ++step) {
            mouseMove(bar, bar.width / 2, startY + (bar.height / 2 - startY) * step / 12, 20)
            waitForRendering(list)
        }
        mouseRelease(bar, bar.width / 2, bar.height / 2)
        tryVerify(() => !list.atYEnd && !list.followEnd && !list.moving)
        const before = visibleAnchor(list)
        appendMessage(101, true)
        waitForRendering(list)
        const after = visibleAnchor(list)
        compare(after.sequence, before.sequence)
        verify(Math.abs(after.offset - before.offset) <= 1)
    }

    function test_wheelReadingKeepsPositionWhenMessageArrives() {
        const list = findChild(chat, "tournamentChatMessages")
        mouseWheel(list, list.width / 2, list.height / 2, 0, 480)
        tryVerify(() => !list.atYEnd && !list.followEnd)
        tryVerify(() => !list.moving)
        const anchor = visibleAnchor(list)
        appendMessage(101, false)
        waitForRendering(list)
        compare(visibleAnchor(list).sequence, anchor.sequence)
        verify(!list.atYEnd)
    }

    function test_switchingEventsClearsDraftAndResumesFollowing() {
        const list = findChild(chat, "tournamentChatMessages")
        const input = findChild(chat, "tournamentChatInput")
        dragScrollBar(0.4)
        input.text = "Unsent message in previous event"
        tournament.chatMessages = []
        tournament.tournamentId = "different-event"
        compare(input.text, "")
        tournament.chatMessages = [{sequence: 1, displayName: "New event", text: "Hello"}]
        tryVerify(() => list.count === 1 && list.followEnd && list.atYEnd)
        compare(list.model.get(0).displayName, "New event")
    }
}
