// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root

    readonly property var appWindow: ApplicationWindow.window
    readonly property int customServerIndex: ws.customServerIndex
    property int selectedServerIndex: ws.serverIndex
    property int latencyRefreshCountdown: 0
    readonly property var serverOptions: [
        {"label": root.serverLabel(0)},
        {"label": root.serverLabel(1)},
        {"label": root.serverLabel(2)},
        {"label": root.serverLabel(root.customServerIndex)}
    ]

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

    RowLayout {
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: Theme.size(18)
        anchors.bottomMargin: Theme.size(42)
        width: Math.min(parent.width - Theme.size(80), Theme.size(980))
        spacing: Theme.size(24)

        Surface {
            Layout.fillWidth: true
            Layout.preferredWidth: Theme.size(570)
            Layout.fillHeight: true
            Layout.maximumHeight: Theme.size(570)
            Layout.alignment: Qt.AlignVCenter
            elevated: true

            ColumnLayout {
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
                    model: root.serverOptions
                    textRole: "label"
                    currentIndex: root.selectedServerIndex
                    enabled: !ws.connecting
                    onActivated: root.selectedServerIndex = currentIndex
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
                        enabled: !ws.connecting
                        onAccepted: root.submit()
                        Component.onCompleted: text = ws.customServerUrl
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
                    enabled: !ws.connecting
                    onAccepted: root.submit()
                    Component.onCompleted: text = ws.displayName
                }

                InfoBanner {
                    id: errorBanner
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.size(6)
                    message: ""
                }

                AppButton {
                    Layout.fillWidth: true
                    visible: ws.versionMismatch
                    text: root.matchingUpdateButtonText()
                    variant: "secondary"
                    enabled: !appUpdater.checking && !appUpdater.downloading
                    onClicked: root.handleMatchingUpdate()
                }

                InfoBanner {
                    Layout.fillWidth: true
                    visible: ws.versionMismatch && appUpdater.lastError.length > 0
                    tone: "warning"
                    message: I18n.status(appUpdater.lastError)
                }

                AppButton {
                    Layout.fillWidth: true
                    visible: ws.versionMismatch && appUpdater.lastError.length > 0
                    variant: "ghost"
                    text: qsTr("View releases")
                    onClicked: Qt.openUrlExternally(ws.releaseDownloadUrl)
                }

                Item { Layout.fillHeight: true; Layout.minimumHeight: 8 }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.size(10)

                    AppButton {
                        variant: "ghost"
                        text: qsTr("Cancel")
                        enabled: !ws.connecting
                        onClicked: root.appWindow.popScreen()
                    }

                    Item { Layout.fillWidth: true }

                    Row {
                        visible: ws.connecting
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
                        variant: "primary"
                        text: ws.connecting ? qsTr("Connecting") : qsTr("Connect")
                        leadingText: ws.connecting ? "" : "→"
                        enabled: serverSelector.currentIndex >= 0
                                 && (root.selectedServerIndex
                                     !== root.customServerIndex
                                     || customServerField.text.trim().length > 0)
                                 && nameField.text.trim().length > 0
                                 && !ws.connecting
                        onClicked: root.submit()
                    }
                }
            }
        }

        Surface {
            Layout.preferredWidth: Theme.size(300)
            Layout.fillHeight: true
            Layout.maximumHeight: Theme.size(570)
            Layout.alignment: Qt.AlignVCenter
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
        running: root.visible && !ws.connecting
        onTriggered: {
            if (root.latencyRefreshCountdown <= 1) {
                ws.refreshServerLatencies()
                root.latencyRefreshCountdown = 5
            } else {
                root.latencyRefreshCountdown -= 1
            }
        }
    }

    function serverLabel(index) {
        const name = index === 0 ? qsTr("Server 1")
                   : index === 1 ? qsTr("Server 2")
                   : index === 2 ? qsTr("Server 3")
                                 : qsTr("Custom server")
        if (index === root.customServerIndex
            && ws.customServerUrl.length === 0) {
            return name
        }
        const latencies = ws.serverLatencies
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
                || ws.connecting)
            return
        errorBanner.message = ""
        if (root.selectedServerIndex === root.customServerIndex) {
            ws.connectToCustomServer(customServerField.text.trim(),
                                     nameField.text.trim())
        } else {
            ws.connectToServer(root.selectedServerIndex,
                               nameField.text.trim())
        }
    }

    function refreshConnectionError() {
        if (ws.connected) {
            errorBanner.message = ""
            return
        }
        if (ws.versionMismatch) {
            const versions = ws.requiredVersion.length > 0
                ? qsTr("Required version") + ": " + ws.requiredVersion
                  + "\n" + qsTr("Installed version") + ": " + ws.clientVersion
                : qsTr("The server and client versions do not match.")
            errorBanner.message = versions + "\n"
                + qsTr("Download and install the matching version before reconnecting.")
            return
        }
        errorBanner.message = I18n.status(ws.lastError)
    }

    function matchingUpdateReady() {
        return appUpdater.releaseAvailable && appUpdater.exactVersion
                && appUpdater.targetVersion === ws.requiredVersion
    }

    function matchingUpdateButtonText() {
        if (appUpdater.checking)
            return qsTr("Checking matching version…")
        if (matchingUpdateReady() && appUpdater.downloadReady)
            return qsTr("Open download folder")
        if (matchingUpdateReady() && appUpdater.downloading)
            return qsTr("Downloading update…")
        if (matchingUpdateReady())
            return qsTr("Download matching version")
        if (appUpdater.lastError.length > 0)
            return qsTr("Retry matching version")
        return qsTr("Find matching version")
    }

    function handleMatchingUpdate() {
        if (matchingUpdateReady() && appUpdater.downloadReady) {
            appUpdater.openDownloadLocation()
        } else if (matchingUpdateReady()) {
            appUpdater.downloadUpdate()
        } else if (ws.requiredVersion.length > 0) {
            appUpdater.clearLastError()
            appUpdater.checkForVersion(ws.requiredVersion)
        } else {
            appUpdater.openReleasePage()
        }
    }

    Connections {
        target: ws
        function onLastErrorChanged() {
            root.refreshConnectionError()
        }
        function onVersionMismatchChanged() {
            root.refreshConnectionError()
            if (ws.versionMismatch && ws.requiredVersion.length > 0
                    && (!appUpdater.exactVersion
                        || appUpdater.targetVersion !== ws.requiredVersion)) {
                appUpdater.checkForVersion(ws.requiredVersion)
            }
        }
    }

    Connections {
        target: appUpdater
        function onStateChanged() {
            if (ws.versionMismatch && ws.requiredVersion.length > 0
                    && !appUpdater.checking && !appUpdater.downloading
                    && appUpdater.lastError.length === 0
                    && (!appUpdater.exactVersion
                        || appUpdater.targetVersion !== ws.requiredVersion)) {
                appUpdater.checkForVersion(ws.requiredVersion)
            }
        }
    }
}
