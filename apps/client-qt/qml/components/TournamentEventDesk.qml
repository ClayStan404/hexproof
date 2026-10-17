// SPDX-License-Identifier: GPL-3.0-or-later
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
    readonly property bool isCasual: tournamentModel.coordinator === "casual"
    // Server snapshots carry the authoritative floor; 4 is the pre-1.0.6
    // constructed fallback for servers that do not send minimumPlayers.
    readonly property int minimumCheckedIn:
        tournamentModel.minimumPlayers > 0 ? tournamentModel.minimumPlayers : 4
    readonly property var casualReadyPlayers: buildCasualReadyPlayers()
    property double clockNow: Date.now()
    readonly property int roundSecondsRemaining: {
        const duration = Math.max(0, root.tournamentModel.roundMinutes) * 60
        if (!root.tournamentModel.roundStartedAt)
            return duration
        const started = Date.parse(root.tournamentModel.roundStartedAt)
        if (isNaN(started))
            return duration
        return Math.max(0, Math.ceil(
                            (started + duration * 1000 - root.clockNow) / 1000))
    }
    readonly property string roundClock: {
        if (root.roundSecondsRemaining <= 0)
            return qsTranslate("TournamentLobby", "Time expired")
        const minutes = Math.floor(root.roundSecondsRemaining / 60)
        const seconds = root.roundSecondsRemaining % 60
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }
    Layout.preferredWidth: Theme.size(330)
    Layout.fillHeight: true
    elevated: true
    implicitHeight: deskContent.implicitHeight + Theme.size(44)

    ColumnLayout {
        id: deskContent
        anchors.fill: parent
        anchors.margins: Theme.size(22)
        spacing: Theme.size(12)

        Text {
            textFormat: Text.PlainText
            text: qsTranslate("TournamentLobby", "Event desk")
            color: Theme.text
            font.pixelSize: Theme.fontSize(19)
            font.weight: Font.DemiBold
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTranslate("TournamentLobby", "Organizer: %1").arg(
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
                          ? qsTranslate("TournamentLobby", "Registration")
                          : (root.tournamentModel.stage === "draft"
                             ? qsTranslate("TournamentLobby", "Drafting")
                             : (root.tournamentModel.stage === "deck_building"
                                ? qsTranslate("TournamentLobby", "Deck building")
                                : (root.isCasual
                                   ? qsTranslate("TournamentLobby", "Casual tables")
                                   : qsTranslate("TournamentLobby", "Round %1 of %2")
                                     .arg(root.tournamentModel.currentRound)
                                     .arg(root.tournamentModel.plannedRounds))))
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(15)
                    font.weight: Font.DemiBold
                }
                Text {
                    textFormat: Text.PlainText
                    text: qsTranslate("TournamentLobby", "%1 registered · %2 checked in")
                          .arg(root.tournamentModel.registered)
                          .arg(root.tournamentModel.checkedIn)
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                }
                Text {
                    textFormat: Text.PlainText
                    visible: !root.isCasual
                             && root.tournamentModel.status === "running"
                             && root.tournamentModel.stage === "competition"
                    text: root.tournamentModel.roundComplete
                          ? qsTranslate("TournamentLobby", "All results confirmed")
                          : qsTranslate("TournamentLobby", "Results in progress")
                    color: root.tournamentModel.roundComplete
                           ? Theme.success : Theme.warning
                    font.pixelSize: Theme.fontSize(11)
                }
                Text {
                    textFormat: Text.PlainText
                    visible: !root.isCasual
                             && root.tournamentModel.status === "running"
                             && root.tournamentModel.stage === "competition"
                    text: qsTranslate("TournamentLobby", "Round clock: %1").arg(root.roundClock)
                    color: root.roundSecondsRemaining > 0
                           ? Theme.accent : Theme.warning
                    font.pixelSize: Theme.fontSize(12)
                    font.weight: Font.DemiBold
                }
            }
        }

        AppButton {
            objectName: "registerLimitedPlayerButton"
            Layout.fillWidth: true
            visible: root.tournamentModel.canRegister
            variant: "primary"
            text: root.lobbyController.isOrganizer ? qsTranslate("TournamentLobby", "Register as a player") : qsTranslate("TournamentLobby", "Register")
            onClicked: root.wsModel.registerTournament()
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: root.lobbyController.isOrganizer && !root.lobbyController.isParticipant
            text: qsTranslate("TournamentLobby", "You are organizing only. You do not take a player seat or receive a pool.")
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize(11)
            wrapMode: Text.WordWrap
        }

        AppButton {
            Layout.fillWidth: true
            visible: root.lobbyController.isParticipant
                     && root.tournamentModel.status === "registration"
            variant: root.lobbyController.selfCheckedIn ? "secondary" : "primary"
            text: root.lobbyController.selfCheckedIn ? qsTranslate("TournamentLobby", "Undo check-in")
                                     : qsTranslate("TournamentLobby", "Check in")
            onClicked: root.wsModel.setTournamentCheckedIn(
                           !root.lobbyController.selfCheckedIn)
        }

        AppButton {
            Layout.fillWidth: true
            visible: root.lobbyController.isParticipant
                     && root.tournamentModel.status === "registration"
            variant: "danger"
            text: qsTranslate("TournamentLobby", "Withdraw registration")
            onClicked: root.wsModel.unregisterTournament()
        }

        AppButton {
            objectName: "startTournamentButton"
            Layout.fillWidth: true
            visible: root.lobbyController.isOrganizer
                     && root.tournamentModel.status === "registration"
            variant: "primary"
            text: root.isCasual ? qsTranslate("TournamentLobby", "Start room") : qsTranslate("TournamentLobby", "Start tournament")
            enabled: root.tournamentModel.checkedIn >= root.minimumCheckedIn
            onClicked: root.wsModel.startTournament()
        }

        AppButton {
            objectName: "openLimitedCompetitionButton"
            Layout.fillWidth: true
            visible: root.lobbyController.isOrganizer
                     && root.tournamentModel.status === "running"
                     && root.tournamentModel.stage === "deck_building"
                     && root.limitedModel.allDecksSubmitted
            variant: "primary"
            text: root.isCasual ? qsTranslate("TournamentLobby", "Open casual tables")
                                : qsTranslate("TournamentLobby", "Publish round one")
            onClicked: root.wsModel.startTournament()
        }

        AppButton {
            Layout.fillWidth: true
            visible: root.lobbyController.isOrganizer
                     && !root.isCasual
                     && root.tournamentModel.status === "running"
                     && root.tournamentModel.stage === "competition"
            variant: "primary"
            text: root.tournamentModel.currentRound >= root.tournamentModel.plannedRounds
                  ? qsTranslate("TournamentLobby", "Finish tournament")
                  : qsTranslate("TournamentLobby", "Publish next round")
            enabled: root.tournamentModel.roundComplete
            onClicked: root.wsModel.startNextTournamentRound()
        }

        AppButton {
            Layout.fillWidth: true
            visible: root.lobbyController.isParticipant
                     && !root.isCasual
                     && root.tournamentModel.status === "running"
                     && root.tournamentModel.stage === "competition"
                     && root.lobbyController.selfParticipant
                     && root.lobbyController.selfParticipant.competing
                     && !root.lobbyController.selfParticipant.dropped
            variant: "danger"
            text: qsTranslate("TournamentLobby", "Drop from tournament")
            onClicked: root.wsModel.dropTournament()
        }

        Surface {
            Layout.fillWidth: true
            implicitHeight: casualMatchForm.implicitHeight + Theme.size(24)
            visible: root.isCasual && root.lobbyController.isOrganizer
                     && root.tournamentModel.status === "running"
                     && root.tournamentModel.stage === "competition"
            color: Theme.surfaceMuted

            ColumnLayout {
                id: casualMatchForm
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.size(12)
                spacing: Theme.size(7)

                Text {
                    textFormat: Text.PlainText
                    text: qsTranslate("TournamentLobby", "CREATE PRIVATE TABLE")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(10)
                    font.weight: Font.Bold
                }
                AppComboBox {
                    id: casualPlayerA
                    objectName: "casualPlayerASelector"
                    Layout.fillWidth: true
                    model: root.casualReadyPlayers
                    textRole: "displayName"
                    valueRole: "participantId"
                }
                AppComboBox {
                    id: casualPlayerB
                    objectName: "casualPlayerBSelector"
                    Layout.fillWidth: true
                    model: root.casualReadyPlayers
                    textRole: "displayName"
                    valueRole: "participantId"
                    currentIndex: root.casualReadyPlayers.length > 1 ? 1 : 0
                }
                AppButton {
                    objectName: "createCasualTableButton"
                    Layout.fillWidth: true
                    variant: "primary"
                    text: qsTranslate("TournamentLobby", "Create table")
                    enabled: casualPlayerA.currentIndex >= 0
                             && casualPlayerB.currentIndex >= 0
                             && casualPlayerA.currentValue !== casualPlayerB.currentValue
                    onClicked: root.wsModel.createLimitedCasualMatch(
                                   casualPlayerA.currentValue,
                                   casualPlayerB.currentValue)
                }
            }
        }

        Item { Layout.fillHeight: true }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.isCasual
                  ? qsTranslate("TournamentLobby", "The organizer chooses any two online players with submitted decks. Tables are private and do not affect standings.")
                  : qsTranslate("TournamentLobby", "Standings use match points, OMW%, GW%, then OGW%. Pairing rooms are private and hidden from the ordinary room list.")
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
            text: root.isCasual ? qsTranslate("TournamentLobby", "Close room") : qsTranslate("TournamentLobby", "Cancel tournament")
            onClicked: root.cancelDialogTarget.open()
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: !root.isCasual
                 && root.tournamentModel.status === "running"
                 && root.tournamentModel.stage === "competition"
        onTriggered: root.clockNow = Date.now()
    }

    required property var limitedModel

    function buildCasualReadyPlayers() {
        const submitted = ({})
        for (let index = 0; index < root.limitedModel.participants.length; ++index) {
            const participant = root.limitedModel.participants[index]
            if (participant.deckSubmitted)
                submitted[participant.participantId] = true
        }
        const result = []
        const busy = ({})
        for (const pairing of root.tournamentModel.pairings || []) {
            busy[pairing.playerAId] = true
            busy[pairing.playerBId] = true
        }
        for (let index = 0; index < root.tournamentModel.participants.length; ++index) {
            const participant = root.tournamentModel.participants[index]
            if (participant.online && participant.competing && !participant.dropped
                    && submitted[participant.participantId]
                    && !busy[participant.participantId]) {
                result.push({"participantId": participant.participantId,
                             "displayName": participant.displayName})
            }
        }
        return result
    }
}
