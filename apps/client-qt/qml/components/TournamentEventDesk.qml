// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "TournamentLobby"

import QtQuick
import QtQuick.Layouts

Surface {
    id: root

    required property var lobbyController
    required property var tournamentModel
    required property var wsModel
    required property var cancelDialogTarget
    Layout.preferredWidth: Theme.size(330)
    Layout.fillHeight: true
    elevated: true

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.size(22)
        spacing: Theme.size(12)

        Text {
            textFormat: Text.PlainText
            text: qsTr("Event desk")
            color: Theme.text
            font.pixelSize: Theme.fontSize(19)
            font.weight: Font.DemiBold
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Organizer: %1").arg(
                      root.tournamentModel.organizerName)
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(12)
            elide: Text.ElideRight
        }

        Surface {
            Layout.fillWidth: true
            implicitHeight: Theme.size(112)
            color: Theme.surfaceMuted

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.size(13)
                spacing: Theme.size(5)
                Text {
                    textFormat: Text.PlainText
                    text: root.tournamentModel.status === "registration"
                          ? qsTr("Registration")
                          : qsTr("Round %1 of %2")
                            .arg(root.tournamentModel.currentRound)
                            .arg(root.tournamentModel.plannedRounds)
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(15)
                    font.weight: Font.DemiBold
                }
                Text {
                    textFormat: Text.PlainText
                    text: qsTr("%1 registered · %2 checked in")
                          .arg(root.tournamentModel.registered)
                          .arg(root.tournamentModel.checkedIn)
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                }
                Text {
                    textFormat: Text.PlainText
                    visible: root.tournamentModel.status === "running"
                    text: root.tournamentModel.roundComplete
                          ? qsTr("All results confirmed")
                          : qsTr("Results in progress")
                    color: root.tournamentModel.roundComplete
                           ? Theme.success : Theme.warning
                    font.pixelSize: Theme.fontSize(11)
                }
                Text {
                    textFormat: Text.PlainText
                    visible: root.tournamentModel.status === "running"
                    text: qsTr("Round clock: %1").arg(root.lobbyController.roundClock())
                    color: root.lobbyController.roundSecondsRemaining() > 0
                           ? Theme.accent : Theme.warning
                    font.pixelSize: Theme.fontSize(12)
                    font.weight: Font.DemiBold
                }
            }
        }

        AppButton {
            Layout.fillWidth: true
            visible: root.tournamentModel.canRegister
            variant: "primary"
            text: qsTr("Register")
            onClicked: root.wsModel.registerTournament()
        }

        AppButton {
            Layout.fillWidth: true
            visible: root.lobbyController.isParticipant
                     && root.tournamentModel.status === "registration"
            variant: root.lobbyController.selfCheckedIn ? "secondary" : "primary"
            text: root.lobbyController.selfCheckedIn ? qsTr("Undo check-in")
                                     : qsTr("Check in")
            onClicked: root.wsModel.setTournamentCheckedIn(
                           !root.lobbyController.selfCheckedIn)
        }

        AppButton {
            Layout.fillWidth: true
            visible: root.lobbyController.isParticipant
                     && root.tournamentModel.status === "registration"
            variant: "danger"
            text: qsTr("Withdraw registration")
            onClicked: root.wsModel.unregisterTournament()
        }

        AppButton {
            Layout.fillWidth: true
            visible: root.lobbyController.isOrganizer
                     && root.tournamentModel.status === "registration"
            variant: "primary"
            text: qsTr("Start tournament")
            enabled: root.tournamentModel.checkedIn >= 4
            onClicked: root.wsModel.startTournament()
        }

        AppButton {
            Layout.fillWidth: true
            visible: root.lobbyController.isOrganizer
                     && root.tournamentModel.status === "running"
            variant: "primary"
            text: root.tournamentModel.currentRound >= root.tournamentModel.plannedRounds
                  ? qsTr("Finish tournament")
                  : qsTr("Publish next round")
            enabled: root.tournamentModel.roundComplete
            onClicked: root.wsModel.startNextTournamentRound()
        }

        AppButton {
            Layout.fillWidth: true
            visible: root.lobbyController.isParticipant
                     && root.tournamentModel.status === "running"
                     && root.lobbyController.selfParticipant
                     && root.lobbyController.selfParticipant.competing
                     && !root.lobbyController.selfParticipant.dropped
            variant: "danger"
            text: qsTr("Drop from tournament")
            onClicked: root.wsModel.dropTournament()
        }

        Item { Layout.fillHeight: true }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Standings use match points, OMW%, GW%, then OGW%. Pairing rooms are private and hidden from the ordinary room list.")
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize(10)
            lineHeight: 1.35
            wrapMode: Text.WordWrap
        }

        AppButton {
            Layout.fillWidth: true
            visible: root.lobbyController.isOrganizer
                     && root.tournamentModel.status !== "cancelled"
                     && root.tournamentModel.status !== "completed"
            variant: "danger"
            compact: true
            text: qsTr("Cancel tournament")
            onClicked: root.cancelDialogTarget.open()
        }
    }
}
