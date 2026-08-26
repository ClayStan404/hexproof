// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root

    readonly property var appWindow: ApplicationWindow.window
    readonly property bool isOrganizer: tournament.role === "organizer"
    readonly property bool isParticipant: tournament.participantId.length > 0
    readonly property bool isCasual: tournament.coordinator === "casual"
    readonly property var selfParticipant: findParticipant(
                                                   tournament.participantId)
    readonly property bool selfCheckedIn: selfParticipant
                                          ? selfParticipant.checkedIn : false
    property int selectedTab: 0
    property double clockNow: Date.now()

    background: AppBackground { }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: Theme.size(18)
        anchors.bottomMargin: Theme.size(24)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        spacing: Theme.size(14)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(14)

            AppButton {
                variant: "ghost"
                compact: true
                text: qsTr("Leave view")
                leadingText: "‹"
                onClicked: ws.leaveTournament()
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(2)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.size(10)

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: tournament.name || (root.isCasual
                              ? qsTr("Limited room") : qsTr("Tournament"))
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(22)
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    StatusPill {
                        text: root.statusLabel(tournament.status)
                        statusColor: tournament.status === "registration"
                                     ? Theme.success
                                     : (tournament.status === "cancelled"
                                        ? Theme.error : Theme.accent)
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: tournament.tournamentId + " · "
                          + (root.isCasual ? qsTr("Casual room")
                                           : qsTr("Swiss tournament")) + " · "
                          + root.eventTypeLabel(tournament.eventType,
                                                tournament.format)
                          + " · " + root.matchLabel(tournament.matchMode)
                          + " · "
                          + qsTr("%1 minutes").arg(tournament.roundMinutes)
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(12)
                    elide: Text.ElideRight
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.size(14)

            Surface {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.surfaceMuted

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.size(16)
                    spacing: Theme.size(12)

                    SegmentedControl {
                        Layout.preferredWidth: Math.min(Theme.size(680),
                                                        parent.width)
                        options: root.isCasual
                                 ? [qsTr("Tables"), qsTr("Players")]
                                 : tournament.status === "completed"
                                 ? [qsTr("Current pairings"),
                                    qsTr("Standings"), qsTr("Players"),
                                    qsTr("Decklists")]
                                 : [qsTr("Current pairings"),
                                    qsTr("Standings"), qsTr("Players")]
                        currentIndex: root.selectedTab
                        visible: tournament.stage === "competition"
                                 || tournament.stage === "completed"
                        onActivated: index => root.selectedTab = index
                    }

                    LimitedDraftView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: tournament.stage === "draft"
                        limitedModel: limited
                        wsModel: ws
                        cardCatalogModel: cardCatalog
                    }

                    LimitedDeckBuilder {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: tournament.stage === "deck_building"
                        limitedModel: limited
                        wsModel: ws
                        cardCatalogModel: cardCatalog
                    }

                    Item {
                        id: competitionViews
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: tournament.stage === "competition"
                                 || tournament.stage === "completed"

                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            visible: root.selectedTab === 0
                                     && tournament.pairings.length === 0
                            text: tournament.status === "registration"
                                  ? qsTr("Pairings appear after the organizer starts the tournament.")
                                  : qsTr("No pairings are available.")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(14)
                        }

                        ListView {
                            id: pairingList
                            objectName: "tournamentPairingList"
                            anchors.fill: parent
                            visible: root.selectedTab === 0
                            model: tournament.pairings
                            spacing: Theme.size(8)
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Surface {
                                id: pairingRow
                                required property var modelData

                                readonly property bool ownPairing:
                                    root.isParticipant
                                    && (modelData.playerAId
                                        === tournament.participantId
                                        || modelData.playerBId
                                        === tournament.participantId)

                                width: ListView.view.width
                                height: Theme.size(94)
                                color: ownPairing ? Theme.primaryMuted
                                                  : Theme.surfaceElevated

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.size(14)
                                    spacing: Theme.size(10)

                                    Rectangle {
                                        Layout.preferredWidth: Theme.size(44)
                                        Layout.preferredHeight: Theme.size(44)
                                        radius: Theme.radiusMedium
                                        color: Theme.surface

                                        Text {
                                            textFormat: Text.PlainText
                                            anchors.centerIn: parent
                                            text: pairingRow.modelData.table
                                            color: Theme.accent
                                            font.pixelSize: Theme.fontSize(17)
                                            font.weight: Font.Bold
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.size(4)

                                        Text {
                                            textFormat: Text.PlainText
                                            Layout.fillWidth: true
                                            text: pairingRow.modelData.bye
                                                  ? pairingRow.modelData.playerAName
                                                    + " · " + qsTr("Bye")
                                                  : pairingRow.modelData.playerAName
                                                    + "  vs  "
                                                    + pairingRow.modelData.playerBName
                                            color: Theme.text
                                            font.pixelSize: Theme.fontSize(15)
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            textFormat: Text.PlainText
                                            Layout.fillWidth: true
                                            text: root.pairingStatus(
                                                      pairingRow.modelData)
                                            color: pairingRow.modelData.status
                                                   === "confirmed"
                                                   ? Theme.success
                                                   : Theme.textMuted
                                            font.pixelSize: Theme.fontSize(11)
                                            elide: Text.ElideRight
                                        }
                                    }

                                    AppButton {
                                        visible: pairingRow.ownPairing
                                                 && tournament.status === "running"
                                                 && !pairingRow.modelData.bye
                                                 && pairingRow.modelData.status
                                                    !== "confirmed"
                                        compact: true
                                        text: pairingRow.modelData.roomId
                                              ? qsTr("Return to match")
                                              : qsTr("Open match")
                                        onClicked: ws.openTournamentMatch(
                                                       pairingRow.modelData.pairingId)
                                    }

                                    AppButton {
                                        visible: !root.isCasual
                                                 && pairingRow.ownPairing
                                                 && tournament.status === "running"
                                                 && !pairingRow.modelData.bye
                                                 && pairingRow.modelData.status
                                                    === "open"
                                        compact: true
                                        variant: "primary"
                                        text: qsTr("Report")
                                        onClicked: scoreEditor.openFor(
                                                       pairingRow.modelData,
                                                       false,
                                                       root.tabletopScoreForPairing(
                                                           pairingRow.modelData))
                                    }

                                    AppButton {
                                        visible: !root.isCasual
                                                 && pairingRow.modelData.status
                                                 === "reported"
                                                 && tournament.status === "running"
                                                 && ((pairingRow.ownPairing
                                                      && pairingRow.modelData.reporterId
                                                         !== tournament.participantId)
                                                     || (root.isOrganizer
                                                         && !pairingRow.ownPairing))
                                        compact: true
                                        variant: "primary"
                                        text: qsTr("Confirm")
                                        onClicked: ws.confirmTournamentResult(
                                                       pairingRow.modelData.pairingId)
                                    }

                                    AppButton {
                                        visible: !root.isCasual
                                                 && pairingRow.modelData.status
                                                 === "reported"
                                                 && tournament.status === "running"
                                                 && ((pairingRow.ownPairing
                                                      && pairingRow.modelData.reporterId
                                                         !== tournament.participantId)
                                                     || (root.isOrganizer
                                                         && !pairingRow.ownPairing))
                                        compact: true
                                        variant: "danger"
                                        text: qsTr("Reject")
                                        onClicked: ws.rejectTournamentResult(
                                                       pairingRow.modelData.pairingId)
                                    }

                                    AppButton {
                                        visible: !root.isCasual
                                                 && root.isOrganizer
                                                 && tournament.status !== "cancelled"
                                                 && !pairingRow.modelData.bye
                                                 && pairingRow.modelData.status
                                                    !== "reported"
                                        compact: true
                                        text: qsTr("Correct")
                                        onClicked: scoreEditor.openFor(
                                                       pairingRow.modelData,
                                                       true)
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            visible: !root.isCasual && root.selectedTab === 1
                            spacing: Theme.size(6)

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: Theme.size(14)
                                Layout.rightMargin: Theme.size(14)

                                Text { textFormat: Text.PlainText; Layout.fillWidth: true; text: qsTr("Rank / player"); color: Theme.textMuted; font.pixelSize: Theme.fontSize(11) }
                                Text { textFormat: Text.PlainText; Layout.preferredWidth: Theme.size(90); text: qsTr("Record"); color: Theme.textMuted; font.pixelSize: Theme.fontSize(11); horizontalAlignment: Text.AlignHCenter }
                                Text { textFormat: Text.PlainText; Layout.preferredWidth: Theme.size(58); text: qsTr("Points"); color: Theme.textMuted; font.pixelSize: Theme.fontSize(11); horizontalAlignment: Text.AlignHCenter }
                                Text { textFormat: Text.PlainText; Layout.preferredWidth: Theme.size(90); text: qsTr("OMW%"); color: Theme.textMuted; font.pixelSize: Theme.fontSize(11); horizontalAlignment: Text.AlignRight }
                                Text { textFormat: Text.PlainText; Layout.preferredWidth: Theme.size(90); text: qsTr("GW%"); color: Theme.textMuted; font.pixelSize: Theme.fontSize(11); horizontalAlignment: Text.AlignRight }
                                Text { textFormat: Text.PlainText; Layout.preferredWidth: Theme.size(90); text: qsTr("OGW%"); color: Theme.textMuted; font.pixelSize: Theme.fontSize(11); horizontalAlignment: Text.AlignRight }
                            }

                            ListView {
                                id: standingList
                                objectName: "tournamentStandingList"
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                model: tournament.standings
                                spacing: Theme.size(6)
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                delegate: Surface {
                                    id: standingRow
                                    required property var modelData
                                    width: ListView.view.width
                                    height: Theme.size(58)
                                    color: modelData.participantId
                                           === tournament.participantId
                                           ? Theme.primaryMuted
                                           : Theme.surfaceElevated

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.size(14)
                                        anchors.rightMargin: Theme.size(14)

                                        Text {
                                            textFormat: Text.PlainText
                                            Layout.fillWidth: true
                                            text: standingRow.modelData.rank + ".  "
                                                  + standingRow.modelData.displayName
                                                  + (standingRow.modelData.dropped
                                                     ? " · " + qsTr("Dropped") : "")
                                            color: Theme.text
                                            font.pixelSize: Theme.fontSize(13)
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }
                                        Text { textFormat: Text.PlainText; Layout.preferredWidth: Theme.size(90); text: standingRow.modelData.wins + "–" + standingRow.modelData.losses + "–" + standingRow.modelData.draws; color: Theme.textSecondary; font.pixelSize: Theme.fontSize(12); horizontalAlignment: Text.AlignHCenter }
                                        Text { textFormat: Text.PlainText; Layout.preferredWidth: Theme.size(58); text: standingRow.modelData.matchPoints; color: Theme.accent; font.pixelSize: Theme.fontSize(14); font.weight: Font.Bold; horizontalAlignment: Text.AlignHCenter }
                                        Text { textFormat: Text.PlainText; Layout.preferredWidth: Theme.size(90); text: root.percent(standingRow.modelData.oppMatchWin); color: Theme.textMuted; font.pixelSize: Theme.fontSize(11); horizontalAlignment: Text.AlignRight }
                                        Text { textFormat: Text.PlainText; Layout.preferredWidth: Theme.size(90); text: root.percent(standingRow.modelData.gameWin); color: Theme.textMuted; font.pixelSize: Theme.fontSize(11); horizontalAlignment: Text.AlignRight }
                                        Text { textFormat: Text.PlainText; Layout.preferredWidth: Theme.size(90); text: root.percent(standingRow.modelData.oppGameWin); color: Theme.textMuted; font.pixelSize: Theme.fontSize(11); horizontalAlignment: Text.AlignRight }
                                    }
                                }
                            }
                        }

                        ListView {
                            id: participantList
                            objectName: "tournamentParticipantList"
                            anchors.fill: parent
                            visible: root.selectedTab === (root.isCasual ? 1 : 2)
                            model: tournament.participants
                            spacing: Theme.size(7)
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Surface {
                                id: participantRow
                                required property var modelData
                                width: ListView.view.width
                                height: Theme.size(64)
                                color: modelData.participantId
                                       === tournament.participantId
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
                                        text: root.participantStatus(
                                                  participantRow.modelData)
                                        statusColor: participantRow.modelData.dropped
                                                     ? Theme.error
                                                     : (participantRow.modelData.checkedIn
                                                        ? Theme.success
                                                        : Theme.warning)
                                    }

                                    AppButton {
                                        visible: root.isOrganizer
                                                 && tournament.status
                                                    === "registration"
                                        compact: true
                                        text: participantRow.modelData.checkedIn
                                              ? qsTr("Undo check-in")
                                              : qsTr("Check in")
                                        onClicked: ws.setTournamentCheckedIn(
                                                       !participantRow.modelData.checkedIn,
                                                       participantRow.modelData.participantId)
                                    }

                                    AppButton {
                                        visible: root.isOrganizer
                                                 && tournament.status
                                                    === "registration"
                                        compact: true
                                        variant: "danger"
                                        text: qsTr("Remove")
                                        onClicked: ws.unregisterTournament(
                                                       participantRow.modelData.participantId)
                                    }

                                    AppButton {
                                        visible: !root.isCasual
                                                 && root.isOrganizer
                                                 && tournament.status === "running"
                                                 && participantRow.modelData.competing
                                                 && !participantRow.modelData.dropped
                                        compact: true
                                        variant: "danger"
                                        text: qsTr("Drop")
                                        onClicked: ws.dropTournament(
                                                       participantRow.modelData.participantId)
                                    }
                                }
                            }
                        }

                        ListView {
                            id: decklistList
                            objectName: "tournamentDecklistList"
                            anchors.fill: parent
                            visible: !root.isCasual && root.selectedTab === 3
                                     && tournament.status === "completed"
                            model: tournament.participants
                            spacing: Theme.size(8)
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Surface {
                                id: decklistRow
                                required property var modelData
                                width: ListView.view.width
                                height: Theme.size(76)
                                color: Theme.surfaceElevated

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.size(13)
                                    spacing: Theme.size(12)

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.size(4)

                                        Text {
                                            textFormat: Text.PlainText
                                            Layout.fillWidth: true
                                            text: decklistRow.modelData.displayName
                                            color: Theme.text
                                            font.pixelSize: Theme.fontSize(14)
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            textFormat: Text.PlainText
                                            Layout.fillWidth: true
                                            text: decklistRow.modelData.deck
                                                  ? decklistRow.modelData.deck.name
                                                    + " · "
                                                    + qsTr("%1 main · %2 side")
                                                      .arg(root.deckCardCount(
                                                               decklistRow.modelData.deck.mainboard))
                                                      .arg(root.deckCardCount(
                                                               decklistRow.modelData.deck.sideboard))
                                                  : qsTr("No decklist was recorded")
                                            color: Theme.textMuted
                                            font.pixelSize: Theme.fontSize(11)
                                            elide: Text.ElideRight
                                        }
                                    }

                                    AppButton {
                                        compact: true
                                        variant: "primary"
                                        text: qsTr("View decklist")
                                        enabled: !!decklistRow.modelData.deck
                                        onClicked: decklistViewer.showDeck(
                                                       decklistRow.modelData.displayName,
                                                       decklistRow.modelData.deck)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            TournamentEventDesk {
                lobbyController: root
                tournamentModel: tournament
                limitedModel: limited
                wsModel: ws
                cancelDialogTarget: cancelDialog
            }
        }
    }

    TournamentScoreEditor {
        id: scoreEditor
        wsModel: ws
    }

    TournamentDecklistPopup {
        id: decklistViewer
        cardCatalogModel: cardCatalog
    }

    ConfirmDialog {
        id: cancelDialog
        titleText: root.isCasual ? qsTr("Close limited room?")
                                 : qsTr("Cancel tournament?")
        message: root.isCasual
                 ? qsTr("The room will close and no new private tables can be created.")
                 : qsTr("The event will stop and no further rounds can be created.")
        confirmText: root.isCasual ? qsTr("Close room")
                                   : qsTr("Cancel tournament")
        dangerous: true
        onConfirmed: ws.cancelTournament()
    }

    Timer {
        interval: 1000
        repeat: true
        running: tournament.status === "running"
        onTriggered: root.clockNow = Date.now()
    }

    Connections {
        target: ws
        function onLastErrorChanged() {
            if (ws.lastError)
                root.appWindow.showBanner(I18n.status(ws.lastError))
        }
    }

    function findParticipant(id) {
        for (let index = 0; index < tournament.participants.length; ++index) {
            if (tournament.participants[index].participantId === id)
                return tournament.participants[index]
        }
        return null
    }

    function matchLabel(mode) {
        return mode === "bo3" ? qsTr("BO 3") : qsTr("BO 1")
    }

    function eventTypeLabel(eventType, format) {
        if (eventType === "set_sealed")
            return qsTr("Set sealed")
        if (eventType === "set_draft")
            return qsTr("Set draft")
        if (eventType === "cube_draft")
            return qsTr("Cube")
        return I18n.tournamentFormatLabel(format)
    }

    function statusLabel(status) {
        if (status === "registration")
            return qsTr("Registration")
        if (status === "running")
            return qsTr("Running")
        if (status === "completed")
            return qsTr("Completed")
        return qsTr("Cancelled")
    }

    function tabletopScoreForPairing(pairing) {
        if (!pairing || !pairing.roomId)
            return ({})
        return tournament.tabletopScoreForRoom(pairing.roomId)
    }

    function pairingStatus(pairing) {
        if (root.isCasual)
            return pairing.roomId ? qsTr("Private table open")
                                  : qsTr("Players may open this table")
        if (pairing.bye)
            return qsTr("Bye · 2–0 match win")
        if (pairing.status === "open")
            return qsTr("Awaiting result")
        const score = pairing.playerAWins + "–" + pairing.playerBWins
                      + (pairing.drawnGames > 0
                         ? " (" + qsTr("%n draw(s)", "",
                                        pairing.drawnGames)
                           + ")" : "")
        if (pairing.status === "reported")
            return score + " · " + qsTr("Awaiting opponent confirmation")
        return score + (pairing.corrected ? " · " + qsTr("Corrected") : "")
    }

    function participantStatus(participant) {
        if (participant.dropped)
            return qsTr("Dropped")
        if (participant.competing)
            return qsTr("Playing")
        if (participant.checkedIn)
            return qsTr("Checked in")
        return qsTr("Registered")
    }

    function percent(value) {
        return (Number(value || 0) * 100).toFixed(2) + "%"
    }

    function deckCardCount(cards) {
        let count = 0
        const values = cards || []
        for (let index = 0; index < values.length; ++index)
            count += Number(values[index].count || 0)
        return count
    }

    function roundSecondsRemaining() {
        if (!tournament.roundStartedAt)
            return tournament.roundMinutes * 60
        const started = Date.parse(tournament.roundStartedAt)
        if (isNaN(started))
            return tournament.roundMinutes * 60
        return Math.max(0, Math.ceil(
                            (started + tournament.roundMinutes * 60000
                             - clockNow) / 1000))
    }

    function roundClock() {
        const remaining = roundSecondsRemaining()
        if (remaining <= 0)
            return qsTr("Time expired")
        const minutes = Math.floor(remaining / 60)
        const seconds = remaining % 60
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }
}
