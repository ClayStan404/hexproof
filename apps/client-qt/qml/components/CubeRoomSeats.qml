// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "CubeRoom"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var roomController
    required property var tournamentModel
    required property var limitedModel
    property bool showControls: true
    readonly property var seats: {
        const rows = []
        const players = tournamentModel.participants || []
        const capacity = Math.max(players.length, tournamentModel.maxPlayers || 2)
        for (let index = 0; index < capacity; ++index)
            rows.push(index < players.length ? players[index] : null)
        return rows
    }
    spacing: Theme.size(12)

    Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: qsTr("Seats · %1 / %2").arg(root.tournamentModel.participants.length)
                                      .arg(root.seats.length)
        color: Theme.text
        font.pixelSize: Theme.fontSize(20)
        font.weight: Font.DemiBold
    }

    Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        visible: root.tournamentModel.stage === "registration"
        text: qsTr("Share the room code, then get ready. The host can start drafting when everyone is ready.")
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSize(13)
        wrapMode: Text.WordWrap
    }

    Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        visible: root.tournamentModel.stage === "draft"
        text: qsTr("Short disconnects wait. The host can enable auto-draft only after a seat has been offline for over 3 minutes.")
        color: Theme.textMuted
        font.pixelSize: Theme.fontSize(12)
        wrapMode: Text.WordWrap
    }

    ListView {
        objectName: "cubeRoomSeats"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        model: root.seats
        spacing: Theme.size(8)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { }
        delegate: Surface {
            id: seat
            required property int index
            required property var modelData
            width: ListView.view.width
            height: Theme.size(66)
            color: modelData && modelData.participantId === root.tournamentModel.participantId
                   ? Theme.primaryMuted : Theme.surfaceElevated
            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.size(12)
                spacing: Theme.size(10)
                Text {
                    textFormat: Text.PlainText
                    text: seat.index + 1
                    color: Theme.accent
                    font.pixelSize: Theme.fontSize(18)
                    Layout.preferredWidth: Theme.size(25)
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: seat.modelData ? seat.modelData.displayName : qsTr("Empty seat")
                    color: seat.modelData ? Theme.text : Theme.textMuted
                    font.pixelSize: Theme.fontSize(14)
                    font.weight: seat.modelData ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                }
                StatusPill {
                    visible: !!seat.modelData
                    text: root.seatStatus(seat.modelData)
                    statusColor: seat.modelData && seat.modelData.online
                                 ? (seat.modelData.checkedIn ? Theme.success : Theme.warning)
                                 : Theme.textMuted
                }
                AppButton {
                    objectName: "cubeAutoDraftSeat-" + (seat.modelData ? seat.modelData.participantId : "")
                    visible: !!seat.modelData && root.roomController.isHost
                        && seat.modelData.participantId !== root.tournamentModel.participantId
                        && root.tournamentModel.stage === "draft" && !seat.modelData.online
                        && !root.roomController.progressFor(seat.modelData.participantId).autoDraft
                    enabled: !!seat.modelData && root.roomController.canEnableAutoDraft(seat.modelData.participantId)
                    compact: true
                    text: qsTr("Auto-draft")
                    onClicked: root.roomController.requestAutoDraft(seat.modelData.participantId)
                }
            }
        }
    }

    AppButton {
        objectName: "cubeSelfDraftControlButton"
        Layout.fillWidth: true
        visible: root.roomController.isParticipant && root.tournamentModel.stage === "draft" && !root.roomController.closed
        enabled: root.roomController.connected
        text: root.roomController.automaticDraft ? qsTr("Reclaim control") : qsTr("Enable auto-draft")
        onClicked: {
            if (root.roomController.automaticDraft) root.roomController.reclaimDraft()
            else root.roomController.requestAutoDraft(root.tournamentModel.participantId)
        }
    }
    Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        visible: root.roomController.sittingOut && root.tournamentModel.stage === "competition"
            && !root.limitedModel.deckSubmitted
        text: qsTr("Submit a deck in Edit deck before rejoining free play.")
        color: Theme.textMuted
        font.pixelSize: Theme.fontSize(12)
        wrapMode: Text.WordWrap
    }
    AppButton {
        objectName: "cubeParticipationButton"
        Layout.fillWidth: true
        visible: root.roomController.isParticipant && !root.roomController.closed
            && (root.tournamentModel.stage === "deck_building" || root.tournamentModel.stage === "competition")
        enabled: root.roomController.canChangeParticipation(root.roomController.sittingOut)
        text: root.roomController.sittingOut ? qsTr("Rejoin free play") : qsTr("Sit out of free play")
        onClicked: root.roomController.changeParticipation()
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.showControls && root.tournamentModel.stage === "registration"
        spacing: Theme.size(10)
        AppButton {
            objectName: "cubeReadyButton"
            Layout.fillWidth: true
            text: root.roomController.selfReady ? qsTr("Not ready") : qsTr("Ready")
            variant: root.roomController.selfReady ? "secondary" : "primary"
            enabled: root.roomController.isParticipant && root.roomController.connected
            onClicked: root.roomController.setReady()
        }
        AppButton {
            objectName: "cubeStartDraftButton"
            Layout.fillWidth: true
            visible: root.roomController.isHost
            variant: "primary"
            text: qsTr("Start drafting")
            enabled: root.roomController.canStart
            onClicked: root.roomController.startDraft()
        }
    }

    function seatStatus(player) {
        if (!player) return ""
        const progress = root.roomController.progressFor(player.participantId)
        if (progress.withdrawn) return qsTr("Sitting out")
        if (tournamentModel.stage === "draft" && progress.autoDraft) return qsTr("Auto-draft")
        if (!player.online) return qsTr("Offline")
        if (tournamentModel.stage === "registration")
            return player.checkedIn ? qsTr("Ready") : qsTr("Not ready")
        for (const progress of limitedModel.participants || []) {
            if (progress.participantId !== player.participantId) continue
            if (tournamentModel.stage === "draft")
                return qsTr("%1 picked").arg(progress.picked || 0)
            if (tournamentModel.stage === "deck_building")
                return progress.deckSubmitted ? qsTr("Deck ready") : qsTr("Building deck")
        }
        return qsTr("Online")
    }
}
