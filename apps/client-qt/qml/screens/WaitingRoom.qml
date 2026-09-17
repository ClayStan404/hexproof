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
    readonly property bool engineHost: roomSession.hostStatus && roomSession.hostStatus.hostSeat !== undefined
        ? roomSession.seatIndex === roomSession.hostStatus.hostSeat : roomSession.host
    readonly property var appWindow: ApplicationWindow.window
    property int pendingSeat: -1
    property int pendingSpectator: -1
    property string pendingName: ""
    readonly property bool compactLayout: width < Theme.size(1100)
    readonly property bool limitedPairing: roomSession.deckFormat === "limited"
                                          || roomSession.deckFormat === "commander_limited"

    background: AppBackground { }

    ForgeHostingDialog {
        id: hostingOptions
        service: root.wsModel.forgeHost ? root.wsModel.forgeHost : null
        wsModel: root.wsModel
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: Theme.size(22)
        anchors.bottomMargin: Theme.size(24)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        spacing: Theme.size(18)

        Flickable {
            id: waitingRoomBody
            objectName: "waitingRoomBody"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            contentWidth: width
            contentHeight: Math.max(height, waitingRoomScrollContent.implicitHeight)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: waitingRoomScrollContent
                width: waitingRoomBody.width
                height: Math.max(implicitHeight, waitingRoomBody.height)
                spacing: Theme.size(18)

                GridLayout {
                    Layout.fillWidth: true
                    columns: root.compactLayout ? 1 : 2
                    columnSpacing: Theme.size(14)
                    rowSpacing: Theme.size(10)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.size(14)
                        BrandMark { markSize: Theme.size(40) }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.size(4)
                            Text {
                                objectName: "waitingRoomTitle"
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: root.roomSession.roomName.length > 0
                                      ? root.roomSession.roomName : qsTr("Untitled room")
                                color: Theme.text
                                font.pixelSize: Theme.fontSize(22)
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: Theme.size(8)
                                StatusPill {
                                    text: root.roomSession.playtest
                                          ? qsTr("Playtest") + " · "
                                            + I18n.formatLabel(root.roomSession.deckFormat)
                                          : I18n.formatLabel(root.roomSession.deckFormat)
                                    statusColor: Theme.accent
                                }
                                StatusPill {
                                    visible: root.roomSession.rulesMode === "forge"
                                    text: root.roomSession.hostingMode === "player"
                                          ? qsTr("Forge · Player hosted") : qsTr("Forge · Server hosted")
                                    statusColor: Theme.success
                                }
                            }
                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: root.roomSession.playtest
                                      ? qsTr("Solo playtest · Select a deck and ready up")
                                      : (root.roomSession.host
                                         ? qsTr("Waiting room · You are the host")
                                         : qsTr("Waiting room"))
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSize(12)
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    RowLayout {
                        visible: !root.roomSession.playtest
                        Layout.alignment: Qt.AlignRight
                        spacing: Theme.size(10)
                        Surface {
                            implicitWidth: roomCodeRow.implicitWidth + Theme.size(26)
                            implicitHeight: Theme.size(44)
                            Row {
                                id: roomCodeRow
                                anchors.centerIn: parent
                                spacing: Theme.size(10)
                                Text {
                                    textFormat: Text.PlainText
                                    text: qsTr("ROOM CODE")
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fontSize(10)
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    objectName: "waitingRoomCode"
                                    textFormat: Text.PlainText
                                    text: root.roomSession.roomId
                                    color: Theme.accent
                                    font.pixelSize: Theme.fontSize(18)
                                    font.weight: Font.DemiBold
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                        AppButton {
                            objectName: "copyRoomCodeButton"
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
                }
                Surface {
                    objectName: "waitingRoomPeerConnection"
                    Layout.fillWidth: true
                    implicitHeight: peerControls.implicitHeight + Theme.size(24)
                    visible: peerControls.eligible
                    ForgePeerControls {
                        id: peerControls
                        anchors.fill: parent
                        anchors.margins: Theme.size(12)
                        wsModel: root.wsModel
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

                    GridLayout {
                        id: waitingRoomContent
                        objectName: "waitingRoomContent"
                        Layout.fillWidth: true
                        Layout.fillHeight: !root.compactLayout
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
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.size(3)

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: Theme.size(8)
                                                Text {
                                                    textFormat: Text.PlainText
                                                    objectName: "waitingRoomPlayerName"
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
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
                                                    font.weight: Font.DemiBold
                                                    font.letterSpacing: 1.0
                                                }
                                            }

                                            Text {
                                                textFormat: Text.PlainText
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
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
                                            objectName: "waitingRoomRemovePlayerButton"
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
                            implicitHeight: Math.max(Theme.size(260), roomDetailsContent.implicitHeight + Theme.size(40))

                            ColumnLayout {
                                id: roomDetailsContent
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
                            objectName: "waitingRoomSpectators"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            implicitHeight: Math.max(Theme.size(180), spectatorsContent.implicitHeight + Theme.size(40))

                            ColumnLayout {
                                id: spectatorsContent
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
                                                font.weight: Font.DemiBold
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
                                            objectName: "waitingRoomRemoveSpectatorButton"
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
                InfoBanner {
                    objectName: "waitingRoomErrorBanner"
                    Layout.fillWidth: true
                    message: I18n.status(root.wsModel.lastError)
                             + (root.roomSession.rulesMode === "forge"
                                && String(root.wsModel.lastError).indexOf("rules_unavailable:") === 0
                                ? "\n" + qsTr("Forge could not continue. Your seats and selected decks are kept. Ready again to start a fresh game.")
                                : "")
                }

            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.size(8)

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.roomSession.playtest
                      ? qsTr("Select a deck and ready up to open the playtest table.")
                      : (root.limitedPairing
                         ? qsTr("Your submitted Limited deck is locked for this pairing. Ready up to play.")
                         : qsTr("The match starts automatically once every player is ready."))
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
            }

            Text {
                Layout.fillWidth: true
                visible: root.roomSession.hostingMode === "player"
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                text: root.roomSession.hostConnected === true
                    ? qsTr("Player-hosted game · The creator must keep Hexproof open.")
                    : qsTr("Waiting for the creator's local Forge connection…")
                color: root.roomSession.hostConnected === true ? Theme.textMuted : Theme.warning
                font.pixelSize: Theme.fontSize(12)
            }
            Text {
                Layout.fillWidth: true
                visible: root.roomSession.hostingMode === "player" && root.engineHost
                textFormat: Text.PlainText
                text: root.wsModel.forgeHost ? root.wsModel.forgeHost.status : ""
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSize(12)
            }
            AppButton {
                objectName: "retryPlayerHosting"
                visible: root.roomSession.hostingMode === "player" && root.engineHost
                         && root.roomSession.hostConnected !== true
                text: root.wsModel.forgeHost && root.wsModel.forgeHost.busy && !root.wsModel.forgeHost.hosting
                    ? qsTr("Cancel") : root.wsModel.forgeHost && root.wsModel.forgeHost.ready
                    ? qsTr("Connect local Forge") : qsTr("Prepare local Forge")
                enabled: root.wsModel.forgeHost ? !root.wsModel.forgeHost.hosting : false
                onClicked: {
                    if (root.wsModel.forgeHost.busy) root.wsModel.forgeHost.cancel()
                    else if (!root.wsModel.forgeHost.ready) root.wsModel.forgeHost.prepare()
                    else root.wsModel.preparePlayerHosting()
                }
            }
            AppButton {
                objectName: "forgeHostingOptions"
                visible: root.roomSession.hostingMode === "player"
                text: qsTr("Hosting, downloads and diagnostics")
                variant: "ghost"
                onClicked: hostingOptions.open()
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
                        width: Math.min(implicitWidth, Math.max(Theme.size(100),
                                             waitingRoomActionsHost.width - Theme.size(240)))
                        text: root.selectedDeckLabel()
                        leadingText: "◇"
                        onClicked: deckPicker.showForFormat(root.roomSession.format,
                                                            root.roomSession.deckFormat)
                    }

                    StatusPill {
                        objectName: "waitingRoomLimitedDeckStatus"
                        maximumWidth: Math.max(Theme.size(100), waitingRoomActionsHost.width - Theme.size(240))
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
                                     && root.myDeckSelected()
                                     && (root.roomSession.hostingMode !== "player" || root.roomSession.hostConnected === true))
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
        if (root.roomSession.deckFormat === "commander_limited")
            return root.roomSession.maxSeats
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
        if (root.roomSession.hostingMode === "player" && root.roomSession.hostConnected !== true)
            return qsTr("Waiting for the creator's local Forge connection…")
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
