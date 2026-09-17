// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"

TestCase {
    name: "PlayerHostJoin"
    when: windowShown
    ApplicationWindow { id: testWindow; width: 1400; height: 1000; visible: true }
    QtObject {
        id: mockWs
        property string lastError: ""
        property bool inRoom: false
        property int joins: 0
        property bool accepted: false
        function joinRoom(code, spectator, password, trust) { joins++; accepted = trust }
    }
    Component { id: pageComponent; JoinRoom { wsModel: mockWs; roomCode: "ABCDEF" } }
    property var page
    function init() {
        mockWs.lastError = ""; mockWs.joins = 0; mockWs.accepted = false
        page = pageComponent.createObject(testWindow.contentItem)
        page.anchors.fill = testWindow.contentItem
    }
    function cleanup() { page.destroy() }
    function test_consentGatesButtonAndKeyboard() {
        page.hostingMode = "player"
        const submit = findChild(page,"joinRoomSubmitButton")
        verify(!submit.enabled)
        page.submit()
        compare(mockWs.joins,0)
        findChild(page,"trustPlayerHost").checked = true
        verify(submit.enabled)
        page.submit()
        compare(mockWs.joins,1)
        verify(mockWs.accepted)
    }
    function test_codeLookupDisclosesHostingBeforeRetry() {
        page.submit()
        verify(!mockWs.accepted)
        mockWs.lastError = "player_host_trust_required: test"
        compare(page.hostingMode,"player")
        verify(!findChild(page,"joinRoomSubmitButton").enabled)
    }
}
