// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    property var wsModel: null
    property bool compact: false
    readonly property bool eligible: wsModel && wsModel.roomSession
        ? wsModel.roomSession.hostingMode === "player" && wsModel.roomSession.role === "player"
          && wsModel.roomSession.seatIndex >= 0 : false
    readonly property bool available: eligible && wsModel.peerTransportAvailable === true
    readonly property bool optedIn: available && wsModel.directPeerEnabled === true
    readonly property string transport: available && wsModel.peerTransportState !== undefined ? wsModel.peerTransportState : "off"
    visible: eligible
    spacing: Theme.size(compact ? 5 : 8)

    function statusText() {
        if (!available) return qsTr("This server does not support direct connections.")
        switch (transport) {
        case "direct": return qsTr("Direct connection active")
        case "connecting": return qsTr("Connecting…")
        case "waiting": return qsTr("Waiting for the other player")
        case "migrating": return qsTr("Transferring host…")
        case "reconnecting": return qsTr("Reconnecting to server…")
        case "relay": return qsTr("Server relay · Retry available")
        default: return qsTr("Server relay")
        }
    }
    Text {
        Layout.fillWidth: true
        visible: !root.compact
        textFormat: Text.PlainText
        text: qsTr("Player direct connection (P2P)")
        color: Theme.text
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.fontSize(14)
        font.weight: Font.DemiBold
    }
    Text {
        objectName: "forgePeerStatus"
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: root.compact ? qsTr("P2P: %1").arg(root.statusText()) : root.statusText()
        color: root.transport === "direct" ? Theme.accent : Theme.textSecondary
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.fontSize(root.compact ? 11 : 13)
    }
    Text {
        objectName: "forgePeerConsentNotice"
        Layout.fillWidth: true
        visible: root.available && !root.optedIn
        textFormat: Text.PlainText
        text: qsTr("Both players must agree to share network addresses and use a STUN service.")
        color: Theme.textMuted
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.fontSize(root.compact ? 10 : 12)
    }
    Flow {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: Theme.size(root.compact ? 5 : 8)
        AppButton {
            objectName: "forgePeerEnable"
            text: root.optedIn ? qsTr("Use relay only") : qsTr("Agree to P2P")
            enabled: root.available
            disabledReason: root.available ? "" : root.statusText()
            compact: root.compact
            implicitHeight: Theme.size(root.compact ? 30 : 40)
            font.pixelSize: Theme.fontSize(root.compact ? 11 : 13)
            variant: root.optedIn ? "secondary" : "primary"
            onClicked: root.wsModel.setDirectPeerEnabled(!root.optedIn)
        }
        AppButton {
            objectName: "forgePeerRetry"
            visible: root.optedIn && root.transport === "relay"
            text: qsTr("Retry direct")
            compact: root.compact
            implicitHeight: Theme.size(root.compact ? 30 : 40)
            font.pixelSize: Theme.fontSize(root.compact ? 11 : 13)
            variant: "secondary"
            onClicked: root.wsModel.setDirectPeerEnabled(true, true)
        }
    }
}
