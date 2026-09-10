// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "TournamentLobby"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ListView {
    id: root
    required property var lobbyController
    required property var tournamentModel
    required property var wsModel
    objectName: "tournamentParticipantList"
    model: root.tournamentModel.participants
    spacing: Theme.size(7)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { }

    delegate: Surface {
        id: participantRow
        required property var modelData
        width: ListView.view.width
        height: Theme.size(64)
        color: modelData.participantId
               === root.tournamentModel.participantId
               ? Theme.primaryMuted
               : Theme.surfaceElevated

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.size(12)
            spacing: Theme.size(10)

            Rectangle {
                Layout.preferredWidth: Theme.size(8)
                Layout.preferredHeight: Theme.size(8)
                radius: Theme.size(4)
                color: participantRow.modelData.online
                       ? Theme.success : Theme.textMuted
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: participantRow.modelData.displayName
                color: Theme.text
                font.pixelSize: Theme.fontSize(13)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            StatusPill {
                text: root.lobbyController.participantStatus(
                          participantRow.modelData)
                statusColor: participantRow.modelData.dropped
                             ? Theme.error
                             : (participantRow.modelData.checkedIn
                                ? Theme.success
                                : Theme.warning)
            }

            AppButton {
                visible: root.lobbyController.isOrganizer
                         && root.tournamentModel.status
                            === "registration"
                compact: true
                text: participantRow.modelData.checkedIn
                      ? qsTranslate("TournamentLobby", "Undo check-in")
                      : qsTranslate("TournamentLobby", "Check in")
                onClicked: root.wsModel.setTournamentCheckedIn(
                               !participantRow.modelData.checkedIn,
                               participantRow.modelData.participantId)
            }

            AppButton {
                visible: root.lobbyController.isOrganizer
                         && root.tournamentModel.status
                            === "registration"
                compact: true
                variant: "danger"
                text: qsTranslate("TournamentLobby", "Remove")
                onClicked: root.wsModel.unregisterTournament(
                               participantRow.modelData.participantId)
            }

            AppButton {
                visible: !root.lobbyController.isCasual
                         && root.lobbyController.isOrganizer
                         && root.tournamentModel.status === "running"
                         && participantRow.modelData.competing
                         && !participantRow.modelData.dropped
                compact: true
                variant: "danger"
                text: qsTranslate("TournamentLobby", "Drop")
                onClicked: root.wsModel.dropTournament(
                               participantRow.modelData.participantId)
            }
        }
    }
}
