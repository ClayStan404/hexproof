// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"

TestCase {
    name: "ReplayViewer"
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 1100
        height: 760
        visible: true
        function popScreen() {}
    }

    property var page: null

    Component {
        id: pageComponent
        ReplayViewer {
            replayPayload: ({
                "replay": {
                    "roomName": "Friday Night",
                    "players": ["Alice", "Bob"],
                    "deckFormat": "modern",
                    "gameNumber": 1
                },
                "log": [
                    {"kind": "system", "text": "Game started"},
                    {"kind": "system", "text": "Alice drew a card"},
                    {"kind": "chat", "text": "Good luck"}
                ]
            })
        }
    }

    function init() {
        page = pageComponent.createObject(testWindow.contentItem)
        verify(page !== null)
        page.anchors.fill = testWindow.contentItem
    }

    function cleanup() {
        if (page !== null)
            page.destroy()
        page = null
    }

    function test_speedButtonsChangePlaybackInterval() {
        compare(page.playbackSpeed, 1)
        const half = findChild(page, "replaySpeed0_5")
        const doubleSpeed = findChild(page, "replaySpeed2")
        verify(half !== null)
        verify(doubleSpeed !== null)
        half.clicked()
        compare(page.playbackSpeed, 0.5)
        doubleSpeed.clicked()
        compare(page.playbackSpeed, 2)
    }

    function test_keyboardControlsAdvanceTimeline() {
        compare(page.visibleCount, 1)
        keyClick(Qt.Key_Right)
        tryCompare(page, "visibleCount", 2)
        keyClick(Qt.Key_Space)
        tryCompare(page, "playing", true)
        keyClick(Qt.Key_Space)
        tryCompare(page, "playing", false)
        keyClick(Qt.Key_Left)
        tryCompare(page, "visibleCount", 1)
        keyClick(Qt.Key_Right)
        keyClick(Qt.Key_Right)
        tryCompare(page, "visibleCount", 3)
        keyClick(Qt.Key_Home)
        tryCompare(page, "visibleCount", 1)
        keyClick(Qt.Key_4)
        tryCompare(page, "playbackSpeed", 4)
    }
}
