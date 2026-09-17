// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    property var wsModel: null
    readonly property var room: wsModel ? wsModel.roomSession : null
    readonly property var hostingState: room && room.hostStatus ? room.hostStatus : ({})
    readonly property int hostSeat: hostingState.hostSeat !== undefined ? hostingState.hostSeat : 0
    readonly property int backupSeat: hostingState.backupSeat !== undefined ? hostingState.backupSeat : -1
    readonly property int seat: room ? room.seatIndex : -1
    readonly property bool isHost: seat >= 0 && seat === hostSeat
    readonly property bool isBackup: seat >= 0 && seat === backupSeat
    readonly property bool migrating: hostingState.migrating === true
    visible: room !== null && room.hostingMode === "player"
    spacing: Theme.size(10)
    function playerName(index) {
        if (!room || !room.seats || index < 0 || index >= room.seats.length) return ""
        return room.seats[index].displayName || qsTr("Player %1").arg(index + 1)
    }
    Text {
        objectName: "forgeEngineHostLabel"
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: qsTr("Forge host: %1").arg(root.playerName(root.hostSeat))
        color: Theme.text
        font.pixelSize: Theme.fontSize(14)
        wrapMode: Text.WordWrap
    }
    Text {
        objectName: "forgeMigrationStatus"
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: root.migrating ? qsTr("Verifying the game on the new host. Play is paused…")
            : root.hostingState.migrationError ? qsTr("Migration verification failed. The original host is kept if available.")
            : root.backupSeat < 0 ? qsTr("No backup host. The opponent can volunteer after preparing local Forge.")
            : !root.hostingState.backupApproved ? qsTr("%1 volunteered. The current host must approve.").arg(root.playerName(root.backupSeat))
            : !root.hostingState.backupConnected ? qsTr("Approved backup %1 is offline.").arg(root.playerName(root.backupSeat))
            : qsTr("Approved backup: %1. Recovery is automatic if the engine is lost and the position can be verified.").arg(root.playerName(root.backupSeat))
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSize(12)
        wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: qsTr("An approved successor receives both decks, the random seed and private choices during transfer. Only approve someone both players trust. Room ownership stays unchanged.")
        color: Theme.textMuted
        font.pixelSize: Theme.fontSize(12)
        wrapMode: Text.WordWrap
    }
    AppButton {
        objectName: "forgeOfferBackup"
        visible: root.seat >= 0 && !root.isHost && !root.isBackup
        text: qsTr("Volunteer as trusted backup")
        enabled: root.wsModel && root.wsModel.forgeHost ? root.wsModel.forgeHost.ready && !root.wsModel.forgeHost.busy && !root.migrating : false
        onClicked: root.wsModel.playerHostingAction("offer")
    }
    AppButton {
        objectName: "forgeApproveBackup"
        visible: root.isHost && root.backupSeat >= 0 && !root.hostingState.backupApproved
        text: qsTr("Trust and approve %1").arg(root.playerName(root.backupSeat))
        enabled: !root.migrating
        onClicked: root.wsModel.playerHostingAction("approve")
    }
    AppButton {
        objectName: "forgeMigrateHost"
        visible: root.hostingState.backupApproved === true && (root.isHost || root.isBackup && !root.hostingState.connected)
        text: root.isHost ? qsTr("Transfer Forge to %1").arg(root.playerName(root.backupSeat)) : qsTr("Recover Forge here")
        enabled: root.hostingState.backupConnected === true && root.hostingState.migrationAvailable === true && !root.migrating
        onClicked: root.wsModel.playerHostingAction("migrate")
    }
    Text {
        Layout.fillWidth: true
        visible: root.hostingState.backupApproved === true && root.room && root.room.phase === "started" && !root.hostingState.migrationAvailable && !root.migrating
        textFormat: Text.PlainText
        text: qsTr("This position cannot be migrated. Continue with the current host.")
        color: Theme.warning
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.fontSize(12)
    }
    AppButton {
        objectName: "forgeWithdrawBackup"
        visible: root.isBackup || root.isHost && root.backupSeat >= 0
        text: root.isBackup ? qsTr("Withdraw backup offer") : qsTr("Revoke backup approval")
        variant: "secondary"
        enabled: !root.migrating
        onClicked: root.wsModel.playerHostingAction(root.isBackup ? "withdraw" : "revoke")
    }
}
