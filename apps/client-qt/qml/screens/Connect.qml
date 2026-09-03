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
    property int selectedServerIndex: root.hub.serverIndex
    property int latencyRefreshCountdown: 0

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
        subtitle: qsTr("Your name is session-only — no account required")
        onBackRequested: root.appWindow.popScreen()
    }

    Flickable {
        id: connectBody
        objectName: "connectBody"
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(18)
        anchors.bottomMargin: Theme.size(24)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: Math.max(height,
                                contentRow.y + contentRow.height
                                + Theme.size(24))
        ScrollBar.vertical: ScrollBar {
            policy: connectBody.contentHeight > connectBody.height
                    ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        }
    }

    RowLayout {
        id: contentRow
        parent: connectBody.contentItem
        width: Math.min(connectBody.width - Theme.size(80), Theme.size(980))
        height: implicitHeight
        x: Math.max(0, Math.round((connectBody.width - width) / 2))
        y: Math.max(0, Math.round((connectBody.height - height) / 2))
        spacing: Theme.size(24)

        Surface {
            id: formCard
            objectName: "connectCard"
            Layout.fillWidth: true
            Layout.preferredWidth: Theme.size(570)
            Layout.preferredHeight: Math.max(Theme.size(570),
                                             form.implicitHeight
                                             + Theme.size(64))
            elevated: true

            ColumnLayout {
                id: form
                anchors.fill: parent
                anchors.margins: Theme.size(32)
                spacing: Theme.size(10)

                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Enter the tabletop")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(28)
                    font.weight: Font.DemiBold
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    Layout.bottomMargin: Theme.size(16)
                    text: qsTr("Choose a Hexproof server, then enter the name other players will see.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(14)
                    lineHeight: 1.35
                    wrapMode: Text.WordWrap
                }

                Text {
                    textFormat: Text.PlainText
                    text: qsTr("SERVER")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                    font.weight: Font.Bold
                    font.letterSpacing: 1.1
                }

                AppComboBox {
                    id: serverSelector
                    objectName: "serverSelector"
                    Layout.fillWidth: true
                    model: root.customServerIndex + 1
                    textForIndex: function(index) {
                        return root.serverLabel(index)
                    }
                    currentIndex: root.selectedServerIndex
                    enabled: !root.hub.connecting
                    onActivated: function(index) {
                        root.selectedServerIndex = index
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    objectName: "serverLatencyRefreshStatus"
                    Layout.fillWidth: true
                    text: qsTr("Auto refresh") + " · "
                          + root.latencyRefreshCountdown + " "
                          + qsTr("sec")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(10)
                    horizontalAlignment: Text.AlignRight
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.selectedServerIndex
                             === root.customServerIndex
                    spacing: Theme.size(6)

                    Text {
                        textFormat: Text.PlainText
                        text: qsTr("SERVER ADDRESS")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(11)
                        font.weight: Font.Bold
                        font.letterSpacing: 1.1
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
                    text: qsTr("DISPLAY NAME")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                    font.weight: Font.Bold
                    font.letterSpacing: 1.1
                }

                AppTextField {
                    id: nameField
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

                Item { Layout.fillHeight: true; Layout.minimumHeight: 8 }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.size(10)

                    AppButton {
                        variant: "ghost"
                        text: qsTr("Cancel")
                        enabled: !root.hub.connecting
                        onClicked: root.appWindow.popScreen()
                    }

                    Item { Layout.fillWidth: true }

                    Row {
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
            }
        }

        Surface {
            Layout.preferredWidth: Theme.size(300)
            Layout.fillHeight: true
            visible: root.width >= 1000
            color: Theme.surfaceMuted

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.size(26)
                spacing: Theme.size(16)

                Rectangle {
                    Layout.preferredWidth: Theme.size(46)
                    Layout.preferredHeight: Theme.size(46)
                    radius: Theme.size(14)
                    color: Theme.primaryMuted

                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: "↗"
                        color: Theme.primary
                        font.pixelSize: Theme.fontSize(22)
                        font.weight: Font.DemiBold
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    text: qsTr("One connection,\nmany tables.")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(22)
                    font.weight: Font.DemiBold
                    lineHeight: 1.05
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("The hub coordinates rooms and game state. Card images stay cached on your device.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(13)
                    lineHeight: 1.45
                    wrapMode: Text.WordWrap
                }

                Item { Layout.fillHeight: true }

                Row {
                    spacing: Theme.size(9)
                    Rectangle {
                        width: Theme.size(7); height: Theme.size(7); radius: Theme.size(4)
                        color: Theme.success
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        textFormat: Text.PlainText
                        text: qsTr("Public hub preconfigured")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(12)
                    }
                }
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.visible && !root.hub.connecting
        onTriggered: {
            if (root.latencyRefreshCountdown <= 1) {
                root.hub.refreshServerLatencies()
                root.latencyRefreshCountdown = 5
            } else {
                root.latencyRefreshCountdown -= 1
            }
        }
    }

    function serverLabel(index) {
        const name = index === 0 ? qsTr("Server 1 (sponsored by 情报)")
                   : index === 1 ? qsTr("Server 2")
                   : index === 2 ? qsTr("Server 3")
                   : index === 3 ? qsTr("Server 4")
                   : index === 4 ? qsTr("Test server")
                                 : qsTr("Custom server")
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
