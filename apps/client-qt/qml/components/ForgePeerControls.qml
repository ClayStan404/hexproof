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
    spacing: Theme.size(compact ? 4 : 8)

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
    RowLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: Theme.size(root.compact ? 8 : 10)

        Text {
            objectName: "forgePeerStatus"
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            textFormat: Text.PlainText
            text: root.compact ? qsTr("P2P: %1").arg(root.statusText()) : root.statusText()
            color: root.transport === "direct" ? Theme.accent : Theme.textSecondary
            wrapMode: root.compact ? Text.NoWrap : Text.WordWrap
            elide: root.compact ? Text.ElideRight : Text.ElideNone
            font.pixelSize: Theme.fontSize(root.compact ? 12 : 13)
        }
        AppButton {
            objectName: "forgePeerEnable"
            text: root.optedIn ? qsTr("Use relay only") : qsTr("Agree to P2P")
            enabled: root.available
            disabledReason: root.available ? "" : root.statusText()
            compact: true
            variant: root.optedIn || root.compact ? "secondary" : "primary"
            onClicked: root.wsModel.setDirectPeerEnabled(!root.optedIn)
        }
        AppButton {
            objectName: "forgePeerRetry"
            visible: root.optedIn && root.transport === "relay"
            text: qsTr("Retry direct")
            compact: true
            variant: "ghost"
            onClicked: root.wsModel.setDirectPeerEnabled(true, true)
        }
    }
    Text {
        objectName: "forgePeerConsentNotice"
        Layout.fillWidth: true
        visible: root.available && !root.optedIn
        textFormat: Text.PlainText
        text: qsTr("Both players must agree to share network addresses and use a STUN service.")
        color: Theme.textMuted
        wrapMode: root.compact ? Text.NoWrap : Text.WordWrap
        elide: root.compact ? Text.ElideRight : Text.ElideNone
        font.pixelSize: Theme.fontSize(root.compact ? 11 : 12)
    }
}
