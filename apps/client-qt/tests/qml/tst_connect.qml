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
        property var serverEntries: defaultEntries()
        property int customServerIndex: serverEntries.length - 1
        property string serverDirectorySource: "bundled"
        property bool serverDirectoryRefreshing: false
        property bool serverDirectoryRefreshFailed: false
        property int directoryRefreshCalls: 0
        signal serverDirectoryChanged()
        onServerEntriesChanged: serverDirectoryChanged()
        function defaultEntries() {
            return [{id: "server-1", name: "Server 1", forge: 0, playerHosting: 0},
                    {id: "server-2", name: "Server 2", forge: 1},
                    {id: "server-3", name: "Server 3", forge: 1},
                    {id: "server-4", name: "Server 4", forge: -1},
                    {id: "server-5", name: "Server 5", forge: 0},
                    {id: "custom", forge: -1}]
        }
        function refreshServerDirectory(force) { ++directoryRefreshCalls }
        property int serverIndex: 5
        property bool connecting: false
        property string serverTransportState: ""
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
        mockWs.serverTransportState = ""
        mockWs.disconnectCalls = 0
        mockWs.serverEntries = mockWs.defaultEntries()
        mockWs.directoryRefreshCalls = 0
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

    function test_prefillsDisplayNameFromHub() {
        const field = findChild(page, "displayNameField")
        verify(field !== null)
        compare(field.text, "Tester")
    }

    function test_showsHomeServerRouteWhileConnecting() {
        mockWs.connecting = true
        mockWs.serverTransportState = "connecting"
        const status = findChild(page, "connectTransportStatus")
        verify(status.visible)
        compare(status.text, "Finding a server connection…")
        mockWs.serverTransportState = "relay"
        compare(status.text, "Server · relay")
        mockWs.serverTransportState = "direct"
        compare(status.text, "Server · direct")
        mockWs.serverTransportState = ""
        compare(status.text, "Opening connection…")
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

    function test_leaveCancelsPendingConnection() {
        mockWs.versionMismatch = false
        mockWs.connecting = true
        page.refreshConnectionError()
        waitForRendering(page)
        verify(findChild(page, "connectCancelButton") === null)
        const control = findChild(page, "screenBackButton")
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
            const card = findChild(page, "connectCard")
            const body = findChild(page, "connectBody")
            const cardBottom = card.mapToItem(body, 0, card.height).y
            verify(cardBottom <= body.height + 1,
                   "Compact form bottom " + cardBottom + " exceeds viewport " + body.height)
            verify(body.contentHeight <= body.height + 1, "A fitting form must not add scrolling")
        } finally {
            mockWs.versionMismatch = true
            testWindow.width = 1280
            testWindow.height = 720
        }
    }

    function test_formSitsInTheMiddleOfATallPage() {
        testWindow.width = 1600
        testWindow.height = 900
        mockWs.versionMismatch = false
        try {
            page.refreshConnectionError()
            waitForRendering(page)
            const card = findChild(page, "connectCard")
            const body = findChild(page, "connectBody")
            const top = card.mapToItem(body, 0, 0).y
            const leftover = body.height - card.height
            verify(leftover > 80, "A tall page must leave space around the form")
            fuzzyCompare(top, leftover / 2, 2)
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

    function test_directoryReorderPreservesSelectedIdAndRemovalClearsIt() {
        page.selectServer(1)
        const selected = mockWs.serverEntries[1]
        const custom = mockWs.serverEntries[5]
        mockWs.serverEntries = [selected, mockWs.serverEntries[0], custom]
        tryCompare(page, "selectedServerIndex", 0)
        compare(page.selectedServerId, "server-2")
        page.submit()
        compare(mockWs.lastConnectedIndex, 0)
        mockWs.serverEntries = [custom]
        tryCompare(page, "selectedServerIndex", -1)
        page.submit()
        compare(mockWs.configuredConnectCalls, 1)
        compare(mockWs.customConnectCalls, 0)
        mockWs.serverEntries = [selected, custom]
        tryCompare(page, "selectedServerIndex", -1)
    }

    function test_customSelectionFollowsDynamicIndex() {
        mockWs.serverEntries = [mockWs.serverEntries[0], mockWs.serverEntries[5]]
        tryCompare(page, "selectedServerIndex", 1)
        compare(page.selectedServerId, "custom")
        page.submit()
        compare(mockWs.customConnectCalls, 1)
    }

    function test_capabilitiesAndRefreshAction() {
        verify(!page.serverLabel(0).includes("Manual only"))
        verify(page.serverLabel(0).includes("Server 1"))
        compare(page.playModeSummary(0), "Manual only")
        compare(page.playModeSummary(1), "Server Forge")
        compare(page.playModeSummary(3), "Forge status unknown")
        const button = findChild(page, "refreshServerDirectoryButton")
        verify(button !== null)
        const count = mockWs.directoryRefreshCalls
        mouseClick(button)
        compare(mockWs.directoryRefreshCalls, count + 1)
    }

    function test_playerHostingDoesNotRequireServerForge() {
        mockWs.serverEntries = [
            {id: "relay", name: "Relay", forge: 0, playerHosting: 1, directPeer: 1, hostMigration: 1},
            {id: "older", name: "Older server", forge: 0},
            {id: "custom", forge: -1}]
        verify(!page.serverLabel(0).includes("Player hosting"))
        verify(page.playModeSummary(0).includes("Player hosting"))
        verify(page.playModeSummary(0).includes("Direct connection"))
        verify(page.playModeSummary(0).includes("Host migration"))
        verify(!page.playModeSummary(0).includes("Manual only"))
        compare(page.playModeSummary(1), "Server Forge unavailable")
        verify(findChild(page, "hostingCapabilitiesLabel") === null)
    }

    function test_connectFormOmitsMarketingCopy() {
        verify(findChild(page, "connectCancelButton") === null)
        function containsText(item, text) {
            if (item.text !== undefined && String(item.text).indexOf(text) >= 0)
                return true
            for (const child of item.children) {
                if (containsText(child, text))
                    return true
            }
            return false
        }
        verify(!containsText(page, "Enter the tabletop"))
        verify(!containsText(page, "One connection"))
        verify(!containsText(page, "Public hub preconfigured"))
        verify(!containsText(page, "Player hosting"))
        verify(!containsText(page, "Direct connection"))
        verify(findChild(page, "hostingCapabilitiesLabel") === null)
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

        if (body.contentHeight > body.height + 1) {
            body.contentY = Math.max(0, body.contentHeight - body.height)
            waitForRendering(page)
        }
        const buttonTop = button.mapToItem(body, 0, 0).y
        verify(buttonTop >= -1)
        verify(buttonTop + button.height <= body.height + 1)
    }
}
