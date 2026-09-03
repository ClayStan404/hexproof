// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"

TestCase {
    name: "Connect"
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 1280
        height: 720
        visible: true
        function popScreen() { }
    }

    QtObject {
        id: mockWs
        property int customServerIndex: 5
        property int serverIndex: 5
        property bool connecting: false
        property bool connected: false
        property bool versionMismatch: true
        property string customServerUrl: "ws://127.0.0.1:57320/ws"
        property string displayName: "Tester"
        property string requiredVersion: "1.0.5"
        property string clientVersion: "1.0.6"
        property string releaseDownloadUrl: "https://example.com/releases"
        property string lastError: ""
        property var serverLatencies: [-2, -2, -2, -2, -2, -2]
        function refreshServerLatencies() { }
        function connectToCustomServer(url, name) { }
        function connectToServer(index, name) { }
    }

    QtObject {
        id: mockUpdater
        property bool checking: false
        property bool downloading: false
        property bool releaseAvailable: false
        property bool exactVersion: false
        property bool downloadReady: false
        property string targetVersion: ""
        property string lastError: "error.update_check_failed"
        signal stateChanged()
        function clearLastError() { }
        function checkForVersion(version) { }
        function downloadUpdate() { }
        function openDownloadLocation() { }
        function openReleasePage() { }
    }

    property var page: null

    Component {
        id: pageComponent
        Connect {
            wsModel: mockWs
            updaterModel: mockUpdater
        }
    }

    function init() {
        page = pageComponent.createObject(testWindow.contentItem)
        verify(page !== null)
        page.anchors.fill = testWindow.contentItem
        page.refreshConnectionError()
        waitForRendering(page)
    }

    function cleanup() {
        if (page !== null)
            page.destroy()
        page = null
    }

    function test_connectButtonStaysInsideCardAndReachable() {
        const body = findChild(page, "connectBody")
        const card = findChild(page, "connectCard")
        const button = findChild(page, "connectSubmitButton")
        verify(body !== null)
        verify(card !== null)
        verify(button !== null)

        const buttonTopInCard = button.mapToItem(card, 0, 0).y
        verify(buttonTopInCard >= -1)
        verify(buttonTopInCard + button.height <= card.height + 1)

        const buttonBottom = button.mapToItem(body.contentItem,
                                              0, button.height).y
        verify(body.contentHeight + 0.5 >= buttonBottom)
        verify(body.contentHeight > body.height)

        body.contentY = Math.max(0, body.contentHeight - body.height)
        waitForRendering(page)
        const buttonTop = button.mapToItem(body, 0, 0).y
        verify(buttonTop >= -1)
        verify(buttonTop + button.height <= body.height + 1)
    }
}
