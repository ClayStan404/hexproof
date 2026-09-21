// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root

    readonly property var appWindow: ApplicationWindow.window
    property var wsModel
    property var updaterModel
    readonly property var hub: wsModel ? wsModel : ws
    readonly property var updater: updaterModel ? updaterModel : appUpdater
    readonly property int customServerIndex: root.hub.customServerIndex
    property int selectedServerIndex: -1
    property string selectedServerId: ""
    property int latencyRefreshCountdown: 0
    readonly property bool compactHeight: root.height < Theme.size(700)

    Component.onCompleted: {
        root.selectServer(root.hub.serverIndex)
        root.hub.refreshServerDirectory()
        Qt.callLater(root.syncServerSelector)
    }
    onSelectedServerIndexChanged: Qt.callLater(root.syncServerSelector)

    background: AppBackground { }

    ScreenHeader {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(22)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        title: qsTr("Connect to server")
        onBackRequested: root.leaveScreen()
    }

    Flickable {
        id: connectBody
        objectName: "connectBody"
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(14)
        anchors.bottomMargin: Theme.size(28)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: Math.max(height, form.implicitHeight)
        ScrollBar.vertical: ScrollBar {
            policy: connectBody.contentHeight > connectBody.height
                    ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        }
    }

    ColumnLayout {
        id: form
        objectName: "connectCard"
        parent: connectBody.contentItem
        width: Math.min(Theme.size(760), connectBody.width - Theme.size(72))
        height: implicitHeight
        x: Math.max(0, Math.round((connectBody.width - width) / 2))
        y: Math.max(0, Math.round((connectBody.height - height) / 2))
        spacing: Theme.size(root.compactHeight ? 10 : 14)

                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Server")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                    font.weight: Font.DemiBold
                }

                AppComboBox {
                    id: serverSelector
                    objectName: "serverSelector"
                    Layout.fillWidth: true
                    model: root.customServerIndex + 1
                    textForIndex: function(index) {
                        return root.serverLabel(index)
                    }
                    displayText: root.serverLabel(root.selectedServerIndex)
                    enabled: !root.hub.connecting
                    onActivated: function(index) {
                        root.selectServer(index)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        objectName: "serverDirectoryStatus"
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Theme.fontSize(11)
                        color: Theme.textMuted
                        text: root.hub.serverDirectoryRefreshing
                              ? qsTr("Refreshing server list…")
                              : root.hub.serverDirectoryRefreshFailed
                                ? qsTr("Using saved server list; refresh unavailable")
                                : root.hub.serverDirectorySource === "online"
                                  ? qsTr("Online server list")
                                  : root.hub.serverDirectorySource === "cache"
                                    ? qsTr("Saved server list") : qsTr("Built-in server list")
                    }
                    AppButton {
                        objectName: "refreshServerDirectoryButton"
                        text: qsTr("Refresh list")
                        implicitHeight: Theme.size(28)
                        enabled: !root.hub.serverDirectoryRefreshing && !root.hub.connecting
                        onClicked: root.hub.refreshServerDirectory(true)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.selectedServerIndex
                             === root.customServerIndex
                    spacing: Theme.size(6)

                    Text {
                        textFormat: Text.PlainText
                        text: qsTr("Server address")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(11)
                        font.weight: Font.DemiBold
                    }

                    AppTextField {
                        id: customServerField
                        objectName: "customServerField"
                        Layout.fillWidth: true
                        placeholderText: "wss://example.com/ws"
                        enabled: !root.hub.connecting
                        onAccepted: root.submit()
                        Component.onCompleted: text = root.hub.customServerUrl
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: qsTr("Use a ws:// or wss:// Hexproof server address.")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(10)
                        wrapMode: Text.WordWrap
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.topMargin: Theme.size(8)
                    text: qsTr("Display name")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                    font.weight: Font.DemiBold
                }

                AppTextField {
                    id: nameField
                    objectName: "displayNameField"
                    Layout.fillWidth: true
                    placeholderText: qsTr("How other players will see you")
                    maximumLength: 40
                    enabled: !root.hub.connecting
                    onAccepted: root.submit()
                    Component.onCompleted: text = root.hub.displayName
                }

                InfoBanner {
                    id: errorBanner
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.size(6)
                    message: ""
                }

                AppButton {
                    Layout.fillWidth: true
                    visible: root.hub.versionMismatch
                    text: root.matchingUpdateButtonText()
                    variant: "secondary"
                    enabled: !root.updater.checking && !root.updater.downloading
                    onClicked: root.handleMatchingUpdate()
                }

                InfoBanner {
                    Layout.fillWidth: true
                    visible: root.hub.versionMismatch
                             && root.updater.lastError.length > 0
                    tone: "warning"
                    message: I18n.status(root.updater.lastError)
                }

                AppButton {
                    Layout.fillWidth: true
                    visible: root.hub.versionMismatch
                             && root.updater.lastError.length > 0
                    variant: "ghost"
                    text: qsTr("View releases")
                    onClicked: Qt.openUrlExternally(root.hub.releaseDownloadUrl)
                }

                Row {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.size(8)
                    visible: root.hub.connecting
                    spacing: Theme.size(9)

                    ActivityRing {
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        textFormat: Text.PlainText
                        text: qsTr("Opening connection…")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(12)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                AppButton {
                    objectName: "connectSubmitButton"
                    Layout.fillWidth: true
                    variant: "primary"
                    text: root.hub.connecting ? qsTr("Connecting") : qsTr("Connect")
                    leadingText: root.hub.connecting ? "" : "→"
                    enabled: root.selectedServerIndex >= 0
                             && (root.selectedServerIndex
                                 !== root.customServerIndex
                                 || customServerField.text.trim().length > 0)
                             && nameField.text.trim().length > 0
                             && !root.hub.connecting
                    onClicked: root.submit()
                }
    }

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.visible && !root.hub.connecting
        onTriggered: {
            if (root.latencyRefreshCountdown <= 1) {
                root.hub.refreshServerDirectory()
                root.hub.refreshServerLatencies()
                root.latencyRefreshCountdown = 5
            } else {
                root.latencyRefreshCountdown -= 1
            }
        }
    }

    function serverLabel(index) {
        const entries = root.hub.serverEntries
        if (index < 0 || index >= entries.length)
            return qsTr("Choose a server")
        const entry = entries[index]
        const numbered = /^Server ([0-9]+)$/.exec(String(entry.name || ""))
        let name = index === root.customServerIndex ? qsTr("Custom server")
                   : numbered ? qsTr("Server %1").arg(numbered[1]) : entry.name
        if (entry.sponsor)
            name += qsTr(" (sponsored by %1)").arg(entry.sponsor)
        if (index === root.customServerIndex
            && root.hub.customServerUrl.length === 0) {
            return name
        }
        const latencies = root.hub.serverLatencies
        const latency = latencies.length > index ? latencies[index] : -2
        if (latency >= 0)
            return name + " · " + latency + " ms"
        if (latency === -1)
            return name + " · " + qsTr("Unavailable")
        return name + " · " + qsTr("Checking…")
    }

    function playModeSummary(index) {
        const entry = root.hub.serverEntries[index] || ({})
        const parts = []
        if (entry.forge === 1)
            parts.push(qsTr("Server Forge"))
        if (entry.playerHosting === 1)
            parts.push(qsTr("Player hosting"))
        if (entry.directPeer === 1)
            parts.push(qsTr("Direct connection"))
        if (entry.hostMigration === 1)
            parts.push(qsTr("Host migration"))
        if (parts.length)
            return parts.join(" · ")
        if (entry.forge === 0 && entry.playerHosting === 0)
            return qsTr("Manual only")
        if (entry.forge === 0)
            return qsTr("Server Forge unavailable")
        return qsTr("Forge status unknown")
    }

    function selectServer(index) {
        const entries = root.hub.serverEntries
        root.selectedServerIndex = index >= 0 && index < entries.length ? index : -1
        root.selectedServerId = root.selectedServerIndex >= 0 ? entries[index].id : ""
    }

    function reconcileServerSelection() {
        const entries = root.hub.serverEntries
        let selected = -1
        for (let index = 0; index < entries.length; ++index) {
            if (entries[index].id === root.selectedServerId) {
                selected = index
                break
            }
        }
        root.selectedServerIndex = selected
        if (selected < 0)
            root.selectedServerId = ""
    }

    function syncServerSelector() {
        if (serverSelector.currentIndex !== root.selectedServerIndex)
            serverSelector.currentIndex = root.selectedServerIndex
    }

    function leaveScreen() {
        if (root.hub.connecting)
            root.hub.disconnectFromHub()
        root.appWindow.popScreen()
    }

    function submit() {
        if (root.selectedServerIndex < 0
                || nameField.text.trim().length === 0
                || root.hub.connecting)
            return
        errorBanner.message = ""
        if (root.selectedServerIndex === root.customServerIndex) {
            root.hub.connectToCustomServer(customServerField.text.trim(),
                                           nameField.text.trim())
        } else {
            root.hub.connectToServer(root.selectedServerIndex,
                                     nameField.text.trim())
        }
    }

    function refreshConnectionError() {
        if (root.hub.connected) {
            errorBanner.message = ""
            return
        }
        if (root.hub.versionMismatch) {
            const versions = root.hub.requiredVersion.length > 0
                ? qsTr("Required version") + ": " + root.hub.requiredVersion
                  + "\n" + qsTr("Installed version") + ": " + root.hub.clientVersion
                : qsTr("The server and client versions do not match.")
            errorBanner.message = versions + "\n"
                + qsTr("Download and install the matching version before reconnecting.")
            return
        }
        errorBanner.message = I18n.status(root.hub.lastError)
    }

    function matchingUpdateReady() {
        return root.updater.releaseAvailable && root.updater.exactVersion
                && root.updater.targetVersion === root.hub.requiredVersion
    }

    function matchingUpdateButtonText() {
        if (root.updater.checking)
            return qsTr("Checking matching version…")
        if (matchingUpdateReady() && root.updater.downloadReady)
            return qsTr("Open download folder")
        if (matchingUpdateReady() && root.updater.downloading)
            return qsTr("Downloading update…")
        if (matchingUpdateReady())
            return qsTr("Download matching version")
        if (root.updater.lastError.length > 0)
            return qsTr("Retry matching version")
        return qsTr("Find matching version")
    }

    function handleMatchingUpdate() {
        if (matchingUpdateReady() && root.updater.downloadReady) {
            root.updater.openDownloadLocation()
        } else if (matchingUpdateReady()) {
            root.updater.downloadUpdate()
        } else if (root.hub.requiredVersion.length > 0) {
            root.updater.clearLastError()
            root.updater.checkForVersion(root.hub.requiredVersion)
        } else {
            root.updater.openReleasePage()
        }
    }

    Connections {
        target: root.hub
        function onServerDirectoryChanged() {
            root.reconcileServerSelection()
        }
        function onLastErrorChanged() {
            root.refreshConnectionError()
        }
        function onVersionMismatchChanged() {
            root.refreshConnectionError()
            if (root.hub.versionMismatch && root.hub.requiredVersion.length > 0
                    && (!root.updater.exactVersion
                        || root.updater.targetVersion !== root.hub.requiredVersion)) {
                root.updater.checkForVersion(root.hub.requiredVersion)
            }
        }
    }

    Connections {
        target: root.updater
        function onStateChanged() {
            if (root.hub.versionMismatch && root.hub.requiredVersion.length > 0
                    && !root.updater.checking && !root.updater.downloading
                    && root.updater.lastError.length === 0
                    && (!root.updater.exactVersion
                        || root.updater.targetVersion !== root.hub.requiredVersion)) {
                root.updater.checkForVersion(root.hub.requiredVersion)
            }
        }
    }
}
