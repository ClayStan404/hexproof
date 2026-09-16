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
        property int popCount: 0
        function popScreen() { ++popCount }
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
        property int customConnectCalls: 0
        property int configuredConnectCalls: 0
        property string lastConnectedUrl: ""
        property int lastConnectedIndex: -1
        property int disconnectCalls: 0
        function disconnectFromHub() {
            ++disconnectCalls
            connecting = false
        }
        function refreshServerLatencies() { }
        function connectToCustomServer(url, name) {
            customConnectCalls += 1
            lastConnectedUrl = url
        }
        function connectToServer(index, name) {
            configuredConnectCalls += 1
            lastConnectedIndex = index
        }
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
        testWindow.popCount = 0
        mockWs.connecting = false
        mockWs.disconnectCalls = 0
        mockWs.serverIndex = 5
        mockWs.customConnectCalls = 0
        mockWs.configuredConnectCalls = 0
        mockWs.lastConnectedUrl = ""
        mockWs.lastConnectedIndex = -1
        mockWs.serverLatencies = [-2, -2, -2, -2, -2, -2]
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

    function test_coldStartKeepsCustomEndpointSelected() {
        const selector = findChild(page, "serverSelector")
        const customField = findChild(page, "customServerField")
        verify(selector !== null)
        verify(customField !== null)

        tryCompare(selector, "currentIndex", mockWs.customServerIndex)
        verify(selector.displayText.startsWith("Custom server"))
        verify(customField.visible)

        page.submit()
        compare(mockWs.customConnectCalls, 1)
        compare(mockWs.configuredConnectCalls, 0)
        compare(mockWs.lastConnectedUrl, mockWs.customServerUrl)
    }

    function test_leaveCancelsPendingConnection_data() {
        return [{tag: "cancel", control: "connectCancelButton"},
                {tag: "back", control: "screenBackButton"}]
    }

    function test_leaveCancelsPendingConnection(data) {
        mockWs.versionMismatch = false
        mockWs.connecting = true
        page.refreshConnectionError()
        waitForRendering(page)
        const control = findChild(page, data.control)
        verify(control !== null)
        verify(control.enabled, "A pending handshake must remain cancellable")
        mouseClick(control)
        compare(mockWs.disconnectCalls, 1)
        compare(testWindow.popCount, 1)
        verify(!mockWs.connecting)
    }

    function test_minimumWindowShowsNormalConnectionActionsWithoutScrolling() {
        testWindow.width = 900
        testWindow.height = 620
        mockWs.versionMismatch = false
        try {
            page.refreshConnectionError()
            waitForRendering(page)
            const button = findChild(page, "connectSubmitButton")
            verify(button !== null)
            const position = button.mapToItem(page, 0, 0)
            verify(position.y >= 0)
            verify(position.y + button.height <= page.height)
        } finally {
            mockWs.versionMismatch = true
            testWindow.width = 1280
            testWindow.height = 720
        }
    }

    function test_latencyRefreshDoesNotChangeColdStartSelection() {
        const selector = findChild(page, "serverSelector")
        verify(selector !== null)
        tryCompare(selector, "currentIndex", mockWs.customServerIndex)

        mockWs.serverLatencies = [34, 48, -1, 72, 15, 1]

        tryCompare(selector, "displayText", "Custom server · 1 ms")
        compare(selector.currentIndex, mockWs.customServerIndex)
        compare(page.selectedServerIndex, mockWs.customServerIndex)
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
