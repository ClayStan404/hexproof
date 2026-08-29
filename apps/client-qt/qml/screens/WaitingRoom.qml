// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root

    required property var wsModel
    property var deckLibraryModel: null
    readonly property var roomSession: wsModel.roomSession
    readonly property var appWindow: ApplicationWindow.window
    property int pendingSeat: -1
    property int pendingSpectator: -1
    property string pendingName: ""
    readonly property bool compactLayout: Theme.isCompactWidth(width)
    readonly property bool limitedPairing: roomSession.deckFormat === "limited"

    background: AppBackground { }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: Theme.size(22)
        anchors.bottomMargin: Theme.size(24)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        spacing: Theme.size(18)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(14)

            BrandMark { markSize: Theme.size(40) }

            ColumnLayout {
                spacing: Theme.size(2)

                RowLayout {
                    spacing: Theme.size(10)
                    Text {
                        textFormat: Text.PlainText
                        objectName: "waitingRoomTitle"
                        text: root.roomSession.roomName.length > 0
                              ? root.roomSession.roomName : qsTr("Untitled room")
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(22)
                        font.weight: Font.DemiBold
                    }
                    StatusPill {
                        text: root.roomSession.playtest
                              ? qsTr("Playtest") + " · "
                                + I18n.formatLabel(root.roomSession.deckFormat)
                              : I18n.formatLabel(root.roomSession.deckFormat)
                        statusColor: Theme.accent
                    }
                    StatusPill {
                        visible: root.roomSession.rulesMode === "forge"
                        text: qsTr("Forge rules")
                        statusColor: Theme.success
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    text: root.roomSession.playtest
                          ? qsTr("Solo playtest · Select a deck and ready up")
                          : (root.roomSession.host
                             ? qsTr("Waiting room · You are the host")
                             : qsTr("Waiting room"))
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(12)
                }
            }

            Item { Layout.fillWidth: true }

            Surface {
                visible: !root.roomSession.playtest
                implicitWidth: roomCodeRow.implicitWidth + Theme.size(26)
                implicitHeight: Theme.size(44)
                radius: Theme.radiusMedium
                color: Theme.surfaceMuted

                Row {
                    id: roomCodeRow
                    anchors.centerIn: parent
                    spacing: Theme.size(10)

                    Text {
                        textFormat: Text.PlainText
                        text: qsTr("ROOM CODE")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(10)
                        font.weight: Font.Bold
                        font.letterSpacing: 1.0
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        textFormat: Text.PlainText
                        objectName: "waitingRoomCode"
                        text: root.roomSession.roomId
                        color: Theme.primary
                        font.pixelSize: Theme.fontSize(17)
                        font.weight: Font.Bold
                        font.letterSpacing: 2.0
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            AppButton {
                objectName: "copyRoomCodeButton"
                visible: !root.roomSession.playtest
                compact: true
                text: qsTr("Copy code")
                leadingText: "□"
                enabled: root.roomSession.roomId.length > 0
                onClicked: {
                    root.wsModel.copyToClipboard(root.roomSession.roomId)
                    root.appWindow.showBanner(qsTr("Room code copied"))
                }
            }
        }

        InfoBanner {
            objectName: "spectatorHandsPolicyBanner"
            Layout.fillWidth: true
            visible: !root.roomSession.playtest
                     && root.roomSession.spectatorsSeeHands === true
            tone: "warning"
            message: qsTr("Spectators can continuously inspect every player's hand in this room. Players still cannot see each other's hands.")
        }

        Flickable {
            id: waitingRoomBody
            objectName: "waitingRoomBody"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: Math.max(height, waitingRoomContent.implicitHeight)

            GridLayout {
                id: waitingRoomContent
                objectName: "waitingRoomContent"
                width: waitingRoomBody.width
                height: root.compactLayout ? implicitHeight : waitingRoomBody.height
                columns: root.compactLayout ? 1 : 2
                columnSpacing: Theme.size(18)
                rowSpacing: Theme.size(18)

            Surface {
                objectName: "waitingRoomSeats"
                Layout.fillWidth: true
                Layout.fillHeight: !root.compactLayout
                Layout.preferredWidth: root.compactLayout ? -1 : Theme.size(720)
                Layout.preferredHeight: root.compactLayout ? implicitHeight : -1
                implicitHeight: waitingRoomSeatsColumn.implicitHeight + Theme.size(48)
                elevated: true

                ColumnLayout {
                    id: waitingRoomSeatsColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.size(24)
                    height: root.compactLayout ? implicitHeight
                                               : parent.height - Theme.size(48)
                    spacing: Theme.size(10)

                    RowLayout {
                        Layout.fillWidth: true

                        ColumnLayout {
                            spacing: Theme.size(3)
                            Text {
                                textFormat: Text.PlainText
                                text: root.roomSession.playtest
                                      ? qsTr("Playtest seat")
                                      : qsTr("Player seats")
                                color: Theme.text
                                font.pixelSize: Theme.fontSize(18)
                                font.weight: Font.DemiBold
                            }
                            Text {
                                textFormat: Text.PlainText
                                text: root.roomSession.playtest
                                      ? qsTr("No opponent is required")
                                      : qsTr("%1 of %2 seats filled")
                                        .arg(root.occupiedSeatCount())
                                        .arg(root.roomSession.maxSeats)
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSize(12)
                            }
                        }

                        Item { Layout.fillWidth: true }

                        StatusPill {
                            objectName: "waitingRoomSeatStatus"
                            text: root.roomSession.playtest
                                  ? qsTr("Solo table")
                                  : (root.occupiedSeatCount()
                                     === root.roomSession.maxSeats
                                     ? qsTr("Table full")
                                     : (root.hasEnoughPlayersToStart()
                                        ? qsTr("Ready to start")
                                        : qsTr("Waiting for players")))
                            statusColor: root.hasEnoughPlayersToStart()
                                         ? Theme.success : Theme.warning
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        Layout.topMargin: Theme.size(4)
                        Layout.bottomMargin: Theme.size(2)
                        color: Theme.divider
                    }

                    Repeater {
                        model: root.roomSession.seats

                        delegate: Surface {
                            required property int index
                            required property var modelData
                            objectName: "waitingRoomSeatRow"

                            Layout.fillWidth: true
                            Layout.fillHeight: !root.compactLayout
                            Layout.minimumHeight: Theme.size(66)
                            Layout.preferredHeight: Theme.size(66)
                            Layout.maximumHeight: Theme.size(82)
                            radius: Theme.radiusMedium
                            color: modelData.occupied ? Theme.surfaceMuted : "#0B1512"
                            border.color: modelData.occupied ? Theme.border : Theme.divider

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.size(14)
                                anchors.rightMargin: Theme.size(12)
                                spacing: Theme.size(14)

                                Rectangle {
                                    Layout.preferredWidth: Theme.size(38)
                                    Layout.preferredHeight: Theme.size(38)
                                    radius: Theme.size(12)
                                    color: modelData.occupied ? Theme.primaryMuted : Theme.disabled
                                    border.width: 1
                                    border.color: modelData.occupied ? "#2B654E" : Theme.border

                                    Text {
                                        textFormat: Text.PlainText
                                        anchors.centerIn: parent
                                        text: index + 1
                                        color: modelData.occupied ? Theme.primary : Theme.textMuted
                                        font.pixelSize: Theme.fontSize(15)
                                        font.weight: Font.Bold
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.size(3)

                                    RowLayout {
                                        spacing: Theme.size(8)
                                        Text {
                                            textFormat: Text.PlainText
                                            text: modelData.occupied ? modelData.displayName : qsTr("Open seat")
                                            color: modelData.occupied ? Theme.text : Theme.textMuted
                                            font.pixelSize: Theme.fontSize(14)
                                            font.weight: modelData.occupied ? Font.DemiBold : Font.Medium
                                        }
                                        Text {
                                            textFormat: Text.PlainText
                                            visible: modelData.host
                                            text: qsTr("HOST")
                                            color: Theme.accent
                                            font.pixelSize: Theme.fontSize(9)
                                            font.weight: Font.Bold
                                            font.letterSpacing: 1.0
                                        }
                                    }

                                    Text {
                                        textFormat: Text.PlainText
                                        text: modelData.occupied
                                              ? (modelData.ready
                                                 ? qsTr("Deck selected and ready")
                                                 : (modelData.deckSelected
                                                    ? qsTr("Deck selected, not ready")
                                                    : qsTr("Choosing a deck")))
                                              : qsTr("Share the room code to invite a player")
                                        color: Theme.textMuted
                                        font.pixelSize: Theme.fontSize(11)
                                    }
                                }

                                StatusPill {
                                    visible: modelData.occupied
                                    text: modelData.ready ? qsTr("Ready") : qsTr("Not ready")
                                    statusColor: modelData.ready ? Theme.success : Theme.textMuted
                                }

                                AppButton {
                                    visible: root.roomSession.host && modelData.occupied && !modelData.host
                                    compact: true
                                    variant: "ghost"
                                    text: qsTr("Remove")
                                    onClicked: {
                                        root.pendingSeat = index
                                        root.pendingName = modelData.displayName
                                        kickSeatDialog.open()
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        Layout.fillHeight: !root.compactLayout
                        visible: !root.compactLayout
                    }
                }
            }

            ColumnLayout {
                id: waitingRoomDetails
                objectName: "waitingRoomDetails"
                visible: !root.roomSession.playtest
                Layout.fillWidth: true
                Layout.fillHeight: !root.compactLayout
                Layout.preferredWidth: root.compactLayout ? -1 : Theme.size(330)
                Layout.maximumWidth: root.compactLayout ? Number.POSITIVE_INFINITY
                                                        : Theme.size(370)
                spacing: Theme.size(18)

                Surface {
                    Layout.fillWidth: true
                    implicitHeight: Theme.size(260)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.size(20)
                        spacing: Theme.size(13)

                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("Room details")
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(16)
                            font.weight: Font.DemiBold
                        }

                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.divider }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { textFormat: Text.PlainText; text: qsTr("Format"); color: Theme.textMuted; font.pixelSize: Theme.fontSize(12) }
                            Item { Layout.fillWidth: true }
                            Text { textFormat: Text.PlainText; text: I18n.formatLabel(root.roomSession.deckFormat); color: Theme.text; font.pixelSize: Theme.fontSize(13); font.weight: Font.Medium }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { textFormat: Text.PlainText; text: qsTr("Seats"); color: Theme.textMuted; font.pixelSize: Theme.fontSize(12) }
                            Item { Layout.fillWidth: true }
                            Text { textFormat: Text.PlainText; text: root.roomSession.maxSeats; color: Theme.text; font.pixelSize: Theme.fontSize(13); font.weight: Font.Medium }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { textFormat: Text.PlainText; text: qsTr("Card images"); color: Theme.textMuted; font.pixelSize: Theme.fontSize(12) }
                            Item { Layout.fillWidth: true }
                            Text {
                                textFormat: Text.PlainText
                                text: root.roomSession.cardLoadMode === "background"
                                      ? qsTr("Load in background")
                                      : qsTr("Preload before game")
                                color: Theme.text
                                font.pixelSize: Theme.fontSize(13)
                                font.weight: Font.Medium
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { textFormat: Text.PlainText; text: qsTr("Your role"); color: Theme.textMuted; font.pixelSize: Theme.fontSize(12) }
                            Item { Layout.fillWidth: true }
                            Text {
                                textFormat: Text.PlainText
                                text: root.roomSession.host ? qsTr("Host")
                                                   : (root.roomSession.role === "spectator"
                                                      ? qsTr("Spectator") : qsTr("Player"))
                                color: root.roomSession.host ? Theme.accent : Theme.text
                                font.pixelSize: Theme.fontSize(13)
                                font.weight: Font.Medium
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { textFormat: Text.PlainText; text: qsTr("Spectator hands"); color: Theme.textMuted; font.pixelSize: Theme.fontSize(12) }
                            Item { Layout.fillWidth: true }
                            Text {
                                textFormat: Text.PlainText
                                text: root.roomSession.spectatorsSeeHands === true
                                      ? qsTr("Visible") : qsTr("Hidden")
                                color: root.roomSession.spectatorsSeeHands === true
                                       ? Theme.warning : Theme.text
                                font.pixelSize: Theme.fontSize(13)
                                font.weight: Font.Medium
                            }
                        }
                    }
                }

                Surface {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.size(20)
                        spacing: Theme.size(10)

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                textFormat: Text.PlainText
                                text: qsTr("Spectators")
                                color: Theme.text
                                font.pixelSize: Theme.fontSize(16)
                                font.weight: Font.DemiBold
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                textFormat: Text.PlainText
                                text: root.roomSession.spectators.length + " / 8"
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSize(12)
                            }
                        }

                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.divider }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: root.roomSession.spectators.length === 0
                            spacing: Theme.size(8)

                            Item { Layout.fillHeight: true }
                            Text {
                                textFormat: Text.PlainText
                                Layout.alignment: Qt.AlignHCenter
                                text: "○"
                                color: Theme.borderStrong
                                font.pixelSize: Theme.fontSize(28)
                            }
                            Text {
                                textFormat: Text.PlainText
                                Layout.alignment: Qt.AlignHCenter
                                text: qsTr("No one is watching")
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSize(12)
                            }
                            Item { Layout.fillHeight: true }
                        }

                        Repeater {
                            model: root.roomSession.spectators

                            delegate: RowLayout {
                                required property int index
                                required property var modelData

                                Layout.fillWidth: true
                                Layout.preferredHeight: Theme.size(40)
                                spacing: Theme.size(10)

                                Rectangle {
                                    Layout.preferredWidth: Theme.size(28)
                                    Layout.preferredHeight: Theme.size(28)
                                    radius: Theme.size(9)
                                    color: Theme.surfaceHover
                                    Text {
                                        textFormat: Text.PlainText
                                        anchors.centerIn: parent
                                        text: modelData.displayName.length > 0 ? modelData.displayName.charAt(0).toUpperCase() : "?"
                                        color: Theme.textSecondary
                                        font.pixelSize: Theme.fontSize(12)
                                        font.weight: Font.Bold
                                    }
                                }

                                Text {
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: modelData.displayName
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSize(13)
                                    elide: Text.ElideRight
                                }

                                AppButton {
                                    visible: root.roomSession.host
                                    compact: true
                                    variant: "ghost"
                                    text: qsTr("Remove")
                                    onClicked: {
                                        root.pendingSpectator = index
                                        root.pendingName = modelData.displayName
                                        kickSpectatorDialog.open()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            }
        }

        InfoBanner {
            Layout.fillWidth: true
            message: I18n.status(root.wsModel.lastError)
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.size(8)

            Text {
                textFormat: Text.PlainText
                text: root.roomSession.playtest
                      ? qsTr("Select a deck and ready up to open the playtest table.")
                      : (root.limitedPairing
                         ? qsTr("Your submitted Limited deck is locked for this pairing. Ready up to play.")
                         : qsTr("The match starts automatically once every player is ready."))
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
            }

            Text {
                textFormat: Text.PlainText
                id: readyBlocker
                objectName: "readyBlockerText"
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.readyBlockerReason()
                color: Theme.warning
                font.pixelSize: Theme.fontSize(12)
                horizontalAlignment: Text.AlignRight
                wrapMode: Text.WordWrap
            }

            RowLayout {
                id: waitingRoomActionsHost
                objectName: "waitingRoomActionsHost"
                Layout.fillWidth: true
                spacing: 0

                Item {
                    Layout.fillWidth: true
                }

                // A trailing Row plus spacer keeps the group right-aligned;
                // Flow+AlignRight does not right-align children.
                Row {
                    id: waitingRoomActions
                    objectName: "waitingRoomActions"
                    spacing: Theme.size(10)

                    AppButton {
                        objectName: "waitingRoomSelectDeckButton"
                        visible: root.roomSession.role === "player"
                                 && !root.limitedPairing
                        text: root.selectedDeckLabel()
                        leadingText: "◇"
                        onClicked: deckPicker.showForFormat(root.roomSession.format,
                                                            root.roomSession.deckFormat)
                    }

                    StatusPill {
                        objectName: "waitingRoomLimitedDeckStatus"
                        visible: root.roomSession.role === "player"
                                 && root.limitedPairing
                        text: root.myDeckSelected()
                              ? qsTr("Limited deck locked")
                              : qsTr("Waiting for submitted Limited deck")
                        statusColor: root.myDeckSelected()
                                     ? Theme.success : Theme.warning
                    }

                    AppButton {
                        objectName: "playerReadyButton"
                        visible: root.roomSession.role === "player"
                        variant: root.myReady() ? "ghost" : "primary"
                        text: root.myReady() ? qsTr("Cancel ready") : qsTr("Ready up")
                        enabled: root.myReady()
                                 || (root.hasEnoughPlayersToStart()
                                     && root.myDeckSelected())
                        disabledReason: root.readyBlockerReason()
                        onClicked: root.wsModel.setReady(!root.myReady())
                    }

                    AppButton {
                        objectName: "waitingRoomDeckLibraryButton"
                        text: qsTr("Deck library")
                        leadingText: "◇"
                        variant: "ghost"
                        visible: !root.compactLayout
                        onClicked: root.appWindow.pushScreen("screens/DeckLibrary.qml")
                    }

                    AppButton {
                        objectName: "waitingRoomLeaveButton"
                        variant: "ghost"
                        text: qsTr("Leave room")
                        visible: !root.compactLayout && !root.roomSession.playtest
                        onClicked: leaveDialog.open()
                    }

                    AppButton {
                        objectName: "waitingRoomDisbandButton"
                        visible: !root.compactLayout && root.roomSession.host
                        variant: "danger"
                        text: root.roomSession.playtest
                              ? qsTr("End playtest")
                              : qsTr("Disband room")
                        onClicked: disbandDialog.open()
                    }

                    AppButton {
                        objectName: "waitingRoomOverflowButton"
                        visible: root.compactLayout
                        text: qsTr("More")
                        leadingText: "⋯"
                        onClicked: waitingRoomOverflowMenu.popup()
                    }
                }
            }
        }
    }

    Menu {
        id: waitingRoomOverflowMenu
        objectName: "waitingRoomOverflowMenu"

        MenuItem {
            objectName: "overflowDeckLibraryAction"
            text: qsTr("Deck library")
            onTriggered: root.appWindow.pushScreen("screens/DeckLibrary.qml")
        }
        ConditionalMenuItem {
            objectName: "overflowLeaveAction"
            text: qsTr("Leave room")
            visible: !root.roomSession.playtest
            onTriggered: leaveDialog.open()
        }
        ConditionalMenuItem {
            objectName: "overflowDisbandAction"
            text: root.roomSession.playtest
                  ? qsTr("End playtest")
                  : qsTr("Disband room")
            visible: root.roomSession.host
            onTriggered: disbandDialog.open()
        }
    }

    ConfirmDialog {
        id: leaveDialog
        titleText: qsTr("Leave this room?")
        message: qsTr("You will return to the main menu and give up your current seat.")
        confirmText: qsTr("Leave room")
        onConfirmed: root.wsModel.leaveRoom()
    }

    DeckPicker {
        id: deckPicker
        deckLibraryModel: root.deckLibraryModel
        allowMissingArt: root.roomSession.cardLoadMode === "background"

        onSelected: (deckId, deckName) => {
            const deck = root.deckLibraryModel.deckForMatch(
                           deckId, deckPicker.allowMissingArt)
            if (!deck.name)
                return
            root.deckLibraryModel.setActiveMatchDeck(deckId)
            root.wsModel.selectDeck(deck)
        }

        onOpenDeckLibraryRequested:
            root.appWindow.pushScreen("screens/DeckLibrary.qml")
    }

    ConfirmDialog {
        id: disbandDialog
        titleText: root.roomSession.playtest
                   ? qsTr("End this playtest?")
                   : qsTr("Disband the room?")
        message: root.roomSession.playtest
                 ? qsTr("You will return to the main menu.")
                 : qsTr("Every player and spectator will be returned to the main menu. This cannot be undone.")
        confirmText: root.roomSession.playtest
                     ? qsTr("End playtest")
                     : qsTr("Disband")
        dangerous: true
        onConfirmed: root.wsModel.disbandRoom()
    }

    ConfirmDialog {
        id: kickSeatDialog
        titleText: qsTr("Remove %1?").arg(root.pendingName)
        message: qsTr("This player will be removed and their seat will become available immediately.")
        confirmText: qsTr("Remove player")
        dangerous: true
        onConfirmed: {
            if (root.pendingSeat >= 0)
                root.wsModel.kickSeat(root.pendingSeat)
        }
    }

    ConfirmDialog {
        id: kickSpectatorDialog
        titleText: qsTr("Remove %1?").arg(root.pendingName)
        message: qsTr("This spectator will no longer be able to watch the room.")
        confirmText: qsTr("Remove spectator")
        dangerous: true
        onConfirmed: {
            if (root.pendingSpectator >= 0)
                root.wsModel.kickSpectator(root.pendingSpectator)
        }
    }

    function occupiedSeatCount() {
        let count = 0
        for (let i = 0; i < root.roomSession.seats.length; ++i) {
            if (root.roomSession.seats[i].occupied)
                ++count
        }
        return count
    }

    function minimumPlayersToStart() {
        if (root.roomSession.playtest || root.roomSession.maxSeats <= 1)
            return 1
        if (root.roomSession.format === "edh"
                && root.roomSession.maxSeats >= 3) {
            return 3
        }
        return root.roomSession.maxSeats
    }

    function hasEnoughPlayersToStart() {
        return root.occupiedSeatCount() >= root.minimumPlayersToStart()
    }

    function myDeckSelected() {
        return root.roomSession.seatIndex >= 0 && root.roomSession.seatIndex < root.roomSession.seats.length
               && root.roomSession.seats[root.roomSession.seatIndex].deckSelected
    }

    function myReady() {
        return root.roomSession.seatIndex >= 0 && root.roomSession.seatIndex < root.roomSession.seats.length
               && root.roomSession.seats[root.roomSession.seatIndex].ready
    }

    function readyBlockerReason() {
        if (root.roomSession.role !== "player" || root.myReady())
            return ""
        const missingSeats = Math.max(
            0, root.minimumPlayersToStart() - root.occupiedSeatCount())
        if (missingSeats === 1)
            return qsTr("Waiting for 1 more player")
        if (missingSeats > 1)
            return qsTr("Waiting for %1 more players").arg(missingSeats)
        if (!root.myDeckSelected())
            return root.limitedPairing
                   ? qsTr("Waiting for submitted Limited deck")
                   : qsTr("Select a deck before readying up")
        return ""
    }

    function selectedDeckLabel() {
        if (root.roomSession.selectedDeckName.length === 0)
            return qsTr("Select deck")
        return root.roomSession.selectedDeckName.length > 22
               ? root.roomSession.selectedDeckName.slice(0, 21) + "…" : root.roomSession.selectedDeckName
    }
}
