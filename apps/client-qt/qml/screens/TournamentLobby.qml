// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root
    property var tournamentModel: tournament
    property var limitedModel: limited
    property var wsModel: ws
    property var cardCatalogModel: cardCatalog
    property var preferencesModel: preferences

    readonly property var appWindow: ApplicationWindow.window
    readonly property bool isOrganizer: root.tournamentModel.role === "organizer"
    readonly property bool isParticipant: root.tournamentModel.participantId.length > 0
    readonly property bool isCasual: root.tournamentModel.coordinator === "casual"
    readonly property var selfParticipant: findParticipant(
                                                   root.tournamentModel.participantId)
    readonly property bool selfCheckedIn: selfParticipant
                                          ? selfParticipant.checkedIn : false
    readonly property bool isCompeting: !!selfParticipant && !!selfParticipant.competing
    readonly property bool focusedLimited: isCompeting
        && (tournamentModel.stage === "draft" || tournamentModel.stage === "deck_building")
    readonly property bool compactLayout: width < Theme.size(1100)
    readonly property bool showEventDrawer: focusedLimited || compactLayout
    readonly property bool showPlayers: root.tournamentModel.status === "registration"
                                       || root.selectedTab === (root.isCasual ? 1 : 2)
    property int selectedTab: 0

    onShowEventDrawerChanged: {
        if (!root.showEventDrawer)
            eventPopup.close()
    }

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
                onClicked: root.wsModel.leaveTournament()
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
                        text: root.tournamentModel.name || (root.isCasual
                              ? qsTr("Limited room") : qsTr("Tournament"))
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(22)
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    StatusPill {
                        text: root.statusLabel(root.tournamentModel.status)
                        statusColor: root.tournamentModel.status === "registration"
                                     ? Theme.success
                                     : (root.tournamentModel.status === "cancelled"
                                        ? Theme.error : Theme.accent)
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    objectName: "tournamentLobbySummary"
                    Layout.fillWidth: true
                    text: root.tournamentModel.tournamentId + " · "
                          + (root.isCasual ? qsTr("Casual room")
                                           : qsTr("Swiss tournament")) + " · "
                          + root.eventTypeLabel(root.tournamentModel.eventType,
                                                root.tournamentModel.format)
                          + " · " + root.matchLabel(root.tournamentModel.matchMode)
                          + (root.isCasual ? "" : " · "
                             + qsTr("%1 minutes").arg(root.tournamentModel.roundMinutes))
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(12)
                    elide: Text.ElideRight
                }
            }
        }

        AppButton {
            objectName: "limitedEventDeskButton"
            visible: root.showEventDrawer
            compact: true
            text: qsTr("Event desk") + " / " + qsTr("Chat")
            onClicked: eventPopup.open()
        }

        LimitedProductArtPanel {
            Layout.fillWidth: true
            visible: root.tournamentModel.stage === "registration"
                     && (root.tournamentModel.eventType === "set_sealed"
                         || root.tournamentModel.eventType === "set_draft")
                     && root.tournamentModel.product.id
            product: root.tournamentModel.product
            cardCatalogModel: root.cardCatalogModel
            preferencesModel: root.preferencesModel
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
                                 : root.tournamentModel.status === "completed"
                                 ? [qsTr("Current pairings"),
                                    qsTr("Standings"), qsTr("Players"),
                                    qsTr("Decklists")]
                                 : [qsTr("Current pairings"),
                                    qsTr("Standings"), qsTr("Players")]
                        currentIndex: root.selectedTab
                        visible: root.tournamentModel.stage === "competition"
                                 || root.tournamentModel.stage === "completed"
                        onActivated: index => root.selectedTab = index
                    }

                    LimitedDraftView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.tournamentModel.stage === "draft" && root.isCompeting
                        limitedModel: root.limitedModel
                        tournamentModel: root.tournamentModel
                        wsModel: root.wsModel
                        cardCatalogModel: root.cardCatalogModel
                    }

                    LimitedDeckBuilder {
                        participantId: root.tournamentModel.participantId
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.tournamentModel.stage === "deck_building" && root.isCompeting
                        limitedModel: root.limitedModel
                        wsModel: root.wsModel
                        cardCatalogModel: root.cardCatalogModel
                    }

                    LimitedEventProgress {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: !root.isCompeting
                                 && (root.tournamentModel.stage === "draft"
                                     || root.tournamentModel.stage === "deck_building")
                        limitedModel: root.limitedModel
                    }

                    Item {
                        id: competitionViews
                        readonly property real standingContentWidth:
                            Math.max(0, width - Theme.size(28))
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.tournamentModel.stage === "competition"
                                 || root.tournamentModel.stage === "completed"
                                 || root.tournamentModel.status === "registration"

                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            visible: !root.showPlayers && root.selectedTab === 0
                                     && root.tournamentModel.pairings.length === 0
                            text: root.tournamentModel.status === "registration"
                                  ? qsTr("Pairings appear after the organizer starts the tournament.")
                                  : qsTr("No pairings are available.")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(14)
                        }

                        ListView {
                            id: pairingList
                            objectName: "tournamentPairingList"
                            anchors.fill: parent
                            visible: !root.showPlayers && root.selectedTab === 0
                            model: root.tournamentModel.pairings
                            spacing: Theme.size(8)
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Surface {
                                id: pairingRow
                                required property var modelData

                                readonly property bool ownPairing:
                                    root.isParticipant
                                    && (modelData.playerAId
                                        === root.tournamentModel.participantId
                                        || modelData.playerBId
                                        === root.tournamentModel.participantId)

                                width: ListView.view.width
                                height: Math.max(Theme.size(94), pairingContent.implicitHeight + Theme.size(28))
                                color: ownPairing ? Theme.primaryMuted
                                                  : Theme.surfaceElevated

                                GridLayout {
                                    id: pairingContent
                                    anchors.fill: parent
                                    anchors.margins: Theme.size(14)
                                    columns: width < Theme.size(850) ? 1 : 2
                                    columnSpacing: Theme.size(10)
                                    rowSpacing: Theme.size(8)

                                    RowLayout {
                                        Layout.fillWidth: true
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

                                    }
                                    RowLayout {
                                        Layout.alignment: Qt.AlignRight
                                        spacing: Theme.size(10)
                                        AppButton {
                                            visible: pairingRow.ownPairing
                                                     && root.tournamentModel.status === "running"
                                                     && !pairingRow.modelData.bye
                                                     && pairingRow.modelData.status
                                                        !== "confirmed"
                                            compact: true
                                            text: pairingRow.modelData.roomId
                                                  ? qsTr("Return to match")
                                                  : qsTr("Open match")
                                            onClicked: root.wsModel.openTournamentMatch(
                                                           pairingRow.modelData.pairingId)
                                        }

                                        AppButton {
                                            objectName: "watchTournamentMatchButton"
                                            visible: !pairingRow.ownPairing
                                                     && !pairingRow.modelData.bye
                                                     && !!pairingRow.modelData.roomId
                                            compact: true
                                            text: qsTr("Watch match")
                                            onClicked: root.wsModel.joinRoom(
                                                           pairingRow.modelData.roomId,
                                                           true, "")
                                        }

                                        AppButton {
                                            visible: !root.isCasual
                                                     && pairingRow.ownPairing
                                                     && root.tournamentModel.status === "running"
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
                                                     && root.tournamentModel.status === "running"
                                                     && ((pairingRow.ownPairing
                                                          && pairingRow.modelData.reporterId
                                                             !== root.tournamentModel.participantId)
                                                         || (root.isOrganizer
                                                             && !pairingRow.ownPairing))
                                            compact: true
                                            variant: "primary"
                                            text: qsTr("Confirm")
                                            onClicked: root.wsModel.confirmTournamentResult(
                                                           pairingRow.modelData.pairingId)
                                        }

                                        AppButton {
                                            visible: !root.isCasual
                                                     && pairingRow.modelData.status
                                                     === "reported"
                                                     && root.tournamentModel.status === "running"
                                                     && ((pairingRow.ownPairing
                                                          && pairingRow.modelData.reporterId
                                                             !== root.tournamentModel.participantId)
                                                         || (root.isOrganizer
                                                             && !pairingRow.ownPairing))
                                            compact: true
                                            variant: "danger"
                                            text: qsTr("Reject")
                                            onClicked: root.wsModel.rejectTournamentResult(
                                                           pairingRow.modelData.pairingId)
                                        }

                                        AppButton {
                                            objectName: "correctTournamentResultButton"
                                            visible: !root.isCasual
                                                     && root.isOrganizer
                                                     && root.tournamentModel.status === "running"
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
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            visible: !root.showPlayers && !root.isCasual && root.selectedTab === 1
                            spacing: Theme.size(6)

                            RowLayout {
                                objectName: "tournamentStandingHeader"
                                Layout.fillWidth: true
                                Layout.leftMargin: Theme.size(14)
                                Layout.rightMargin: Theme.size(14)

                                Text { textFormat: Text.PlainText; Layout.fillWidth: true; Layout.minimumWidth: 0; text: qsTr("Rank / player"); color: Theme.textMuted; font.pixelSize: Theme.fontSize(11); elide: Text.ElideRight }
                                Text { textFormat: Text.PlainText; Layout.preferredWidth: competitionViews.standingContentWidth * 0.16; text: qsTr("Record"); color: Theme.textMuted; font.pixelSize: Theme.fontSize(11); horizontalAlignment: Text.AlignHCenter }
                                Text { textFormat: Text.PlainText; Layout.preferredWidth: competitionViews.standingContentWidth * 0.10; text: qsTr("Points"); color: Theme.textMuted; font.pixelSize: Theme.fontSize(11); horizontalAlignment: Text.AlignHCenter }
                                Text { textFormat: Text.PlainText; Layout.preferredWidth: competitionViews.standingContentWidth * 0.14; text: qsTr("OMW%"); color: Theme.textMuted; font.pixelSize: Theme.fontSize(11); horizontalAlignment: Text.AlignRight }
                                Text { textFormat: Text.PlainText; Layout.preferredWidth: competitionViews.standingContentWidth * 0.14; text: qsTr("GW%"); color: Theme.textMuted; font.pixelSize: Theme.fontSize(11); horizontalAlignment: Text.AlignRight }
                                Text { textFormat: Text.PlainText; Layout.preferredWidth: competitionViews.standingContentWidth * 0.14; text: qsTr("OGW%"); color: Theme.textMuted; font.pixelSize: Theme.fontSize(11); horizontalAlignment: Text.AlignRight }
                            }

                            ListView {
                                id: standingList
                                objectName: "tournamentStandingList"
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                model: root.tournamentModel.standings
                                spacing: Theme.size(6)
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                delegate: Surface {
                                    id: standingRow
                                    required property var modelData
                                    width: ListView.view.width
                                    height: Theme.size(58)
                                    color: modelData.participantId
                                           === root.tournamentModel.participantId
                                           ? Theme.primaryMuted
                                           : Theme.surfaceElevated

                                    RowLayout {
                                        objectName: "tournamentStandingColumns"
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.size(14)
                                        anchors.rightMargin: Theme.size(14)

                                        Text {
                                            textFormat: Text.PlainText
                                            Layout.fillWidth: true
                                            objectName: "tournamentStandingPlayerName"
                                            text: standingRow.modelData.rank + ".  "
                                                  + standingRow.modelData.displayName
                                                  + (standingRow.modelData.dropped
                                                     ? " · " + qsTr("Dropped") : "")
                                            color: Theme.text
                                            font.pixelSize: Theme.fontSize(13)
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }
                                        Text { textFormat: Text.PlainText; Layout.preferredWidth: competitionViews.standingContentWidth * 0.16; text: standingRow.modelData.wins + "–" + standingRow.modelData.losses + "–" + standingRow.modelData.draws; color: Theme.textSecondary; font.pixelSize: Theme.fontSize(12); horizontalAlignment: Text.AlignHCenter }
                                        Text { textFormat: Text.PlainText; Layout.preferredWidth: competitionViews.standingContentWidth * 0.10; text: standingRow.modelData.matchPoints; color: Theme.accent; font.pixelSize: Theme.fontSize(14); font.weight: Font.Bold; horizontalAlignment: Text.AlignHCenter }
                                        Text { textFormat: Text.PlainText; Layout.preferredWidth: competitionViews.standingContentWidth * 0.14; text: root.percent(standingRow.modelData.oppMatchWin); color: Theme.textMuted; font.pixelSize: Theme.fontSize(11); horizontalAlignment: Text.AlignRight }
                                        Text { textFormat: Text.PlainText; Layout.preferredWidth: competitionViews.standingContentWidth * 0.14; text: root.percent(standingRow.modelData.gameWin); color: Theme.textMuted; font.pixelSize: Theme.fontSize(11); horizontalAlignment: Text.AlignRight }
                                        Text { textFormat: Text.PlainText; Layout.preferredWidth: competitionViews.standingContentWidth * 0.14; text: root.percent(standingRow.modelData.oppGameWin); color: Theme.textMuted; font.pixelSize: Theme.fontSize(11); horizontalAlignment: Text.AlignRight }
                                    }
                                }
                            }
                        }

                        TournamentPlayers {
                            anchors.fill: parent
                            visible: root.showPlayers
                            lobbyController: root
                            tournamentModel: root.tournamentModel
                            wsModel: root.wsModel
                        }

                        ListView {
                            id: decklistList
                            objectName: "tournamentDecklistList"
                            anchors.fill: parent
                            visible: !root.isCasual && root.selectedTab === 3
                                     && root.tournamentModel.status === "completed"
                            model: root.tournamentModel.participants
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

            TournamentSidebar {
                visible: !root.showEventDrawer
                lobbyController: root
                tournamentModel: root.tournamentModel
                limitedModel: root.limitedModel
                wsModel: root.wsModel
                cancelDialogTarget: cancelDialog
            }
        }
    }

    Popup {
        id: eventPopup
        objectName: "tournamentEventPopup"
        parent: Overlay.overlay
        width: Math.min(Theme.size(380), parent ? parent.width - Theme.size(24) : 380)
        height: parent ? parent.height - Theme.size(32) : Theme.size(600)
        x: parent ? parent.width - width - Theme.size(16) : 0
        y: Theme.size(16)
        modal: true
        focus: true
        background: Surface { elevated: true }
        contentItem: TournamentSidebar {
            lobbyController: root
            tournamentModel: root.tournamentModel
            limitedModel: root.limitedModel
            wsModel: root.wsModel
            cancelDialogTarget: cancelDialog
        }
    }

    TournamentScoreEditor {
        id: scoreEditor
        objectName: "tournamentScoreEditor"
        wsModel: root.wsModel
        enabled: root.tournamentModel.status === "running"
        onEnabledChanged: {
            if (!enabled)
                close()
        }
    }

    TournamentDecklistPopup {
        id: decklistViewer
        cardCatalogModel: root.cardCatalogModel
        deckLibraryModel: typeof deckLibrary !== "undefined" ? deckLibrary : null
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
        onConfirmed: root.wsModel.cancelTournament()
    }

    Connections {
        target: root.wsModel
        function onLastErrorChanged() {
            if (root.wsModel.lastError)
                root.appWindow.showBanner(I18n.status(root.wsModel.lastError))
        }
    }

    function findParticipant(id) {
        for (let index = 0; index < root.tournamentModel.participants.length; ++index) {
            if (root.tournamentModel.participants[index].participantId === id)
                return root.tournamentModel.participants[index]
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
        return root.tournamentModel.tabletopScoreForRoom(pairing.roomId)
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

}
