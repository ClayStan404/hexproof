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

    background: AppBackground { }
    Component.onCompleted: ws.requestRoomList()

    RoomListQuery {
        id: roomQuery
        objectName: "roomListQuery"
        rooms: ws.roomList
    }

    readonly property var availabilityOptions: [
        {"label": qsTr("All rooms"), "value": "all"},
        {"label": qsTr("Can join"), "value": "joinable"},
        {"label": qsTr("Can watch"), "value": "watchable"}
    ]
    readonly property var phaseOptions: [
        {"label": qsTr("Any status"), "value": "all"},
        {"label": qsTr("Waiting"), "value": "waiting"},
        {"label": qsTr("In game"), "value": "in_game"}
    ]
    readonly property var accessOptions: [
        {"label": qsTr("Any access"), "value": "all"},
        {"label": qsTr("Open"), "value": "open"},
        {"label": qsTr("Password"), "value": "locked"}
    ]
    readonly property var formatOptions: [
        {"label": qsTr("All tables"), "value": "all"},
        {"label": qsTr("Generic 1v1"), "value": "modern"},
        {"label": I18n.formatLabel("duel"), "value": "duel"},
        {"label": I18n.formatLabel("commander"), "value": "edh"}
    ]
    readonly property var sortOptions: [
        {"label": qsTr("Joinable first"), "value": "joinable"},
        {"label": qsTr("Name"), "value": "name"},
        {"label": qsTr("Open seats"), "value": "seats"}
    ]

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: Theme.size(22)
        anchors.bottomMargin: Theme.size(28)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        spacing: Theme.size(16)

        ScreenHeader {
            Layout.fillWidth: true
            title: qsTr("Rooms on this hub")
            subtitle: qsTr("Only tables hosted on your connected server are shown")
            onBackRequested: root.appWindow.popScreen()
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.size(8)

            Flow {
                objectName: "roomBrowserFilters"
                Layout.fillWidth: true
                spacing: Theme.size(8)

                AppTextField {
                    id: roomSearchField
                    objectName: "roomSearchField"
                    width: Theme.size(220)
                    placeholderText: qsTr("Search name or room code")
                    text: roomQuery.searchText
                    onTextEdited: roomQuery.searchText = text
                }
                AppComboBox {
                    objectName: "roomAvailabilityFilter"
                    width: Theme.size(168)
                    model: root.availabilityOptions
                    textRole: "label"
                    valueRole: "value"
                    currentIndex: root.optionIndex(root.availabilityOptions,
                                                   roomQuery.availabilityFilter)
                    onActivated: index => roomQuery.availabilityFilter =
                                 root.availabilityOptions[index].value
                }
                AppComboBox {
                    objectName: "roomPhaseFilter"
                    width: Theme.size(150)
                    model: root.phaseOptions
                    textRole: "label"
                    valueRole: "value"
                    currentIndex: root.optionIndex(root.phaseOptions,
                                                   roomQuery.phaseFilter)
                    onActivated: index => roomQuery.phaseFilter =
                                 root.phaseOptions[index].value
                }
                AppComboBox {
                    objectName: "roomAccessFilter"
                    width: Theme.size(150)
                    model: root.accessOptions
                    textRole: "label"
                    valueRole: "value"
                    currentIndex: root.optionIndex(root.accessOptions,
                                                   roomQuery.accessFilter)
                    onActivated: index => roomQuery.accessFilter =
                                 root.accessOptions[index].value
                }
                AppComboBox {
                    objectName: "roomFormatFilter"
                    width: Theme.size(180)
                    model: root.formatOptions
                    textRole: "label"
                    valueRole: "value"
                    currentIndex: root.optionIndex(root.formatOptions,
                                                   roomQuery.formatFilter)
                    onActivated: index => roomQuery.formatFilter =
                                 root.formatOptions[index].value
                }
                AppComboBox {
                    objectName: "roomSortMode"
                    width: Theme.size(168)
                    model: root.sortOptions
                    textRole: "label"
                    valueRole: "value"
                    currentIndex: root.optionIndex(root.sortOptions,
                                                   roomQuery.sortMode)
                    onActivated: index => roomQuery.sortMode =
                                 root.sortOptions[index].value
                }
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    textFormat: Text.PlainText
                    objectName: "roomListSummary"
                    text: roomQuery.hasActiveFilters
                          ? qsTr("%1 of %n room(s)", "", ws.roomList.length)
                            .arg(roomQuery.visibleRooms.length)
                          : qsTr("%n room(s) available", "", ws.roomList.length)
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(13)
                }
                Item { Layout.fillWidth: true }
                AppButton {
                    objectName: "clearRoomFiltersButton"
                    compact: true
                    visible: roomQuery.hasActiveFilters
                    text: qsTr("Clear filters")
                    onClicked: roomQuery.clearFilters()
                }
                AppButton {
                    objectName: "refreshRoomListButton"
                    compact: true
                    text: qsTr("Refresh")
                    leadingText: "↻"
                    enabled: ws.connected
                    onClicked: ws.requestRoomList()
                }
            }
        }

        Surface {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.surfaceMuted

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - Theme.size(60), Theme.size(520))
                objectName: "emptyHubRoomState"
                visible: ws.roomList.length === 0
                spacing: Theme.size(10)

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("No rooms are open on this hub yet.")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(16)
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Create a table now, or refresh after a friend shares one.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(12)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    AppButton {
                        variant: "primary"
                        text: qsTr("Create room")
                        leadingText: "+"
                        onClicked: root.appWindow.pushScreen("screens/CreateRoom.qml")
                    }
                    AppButton {
                        text: qsTr("Refresh")
                        leadingText: "↻"
                        onClicked: ws.requestRoomList()
                    }
                }
            }

            ColumnLayout {
                objectName: "filteredRoomEmptyState"
                anchors.centerIn: parent
                width: Math.min(parent.width - Theme.size(60), Theme.size(520))
                visible: ws.roomList.length > 0 && roomQuery.visibleRooms.length === 0
                spacing: Theme.size(10)

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("No rooms match these filters.")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(16)
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Clear the search or filters to see every public table on this hub.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(12)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
                AppButton {
                    Layout.alignment: Qt.AlignHCenter
                    variant: "primary"
                    text: qsTr("Clear filters")
                    onClicked: roomQuery.clearFilters()
                }
            }

            ListView {
                id: roomListView
                objectName: "hubRoomList"
                anchors.fill: parent
                anchors.margins: Theme.size(14)
                visible: roomQuery.visibleRooms.length > 0
                model: roomQuery.visibleRooms
                spacing: Theme.size(10)
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                delegate: Surface {
                    id: roomRow
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: Theme.size(112)
                    color: Theme.surfaceElevated
                    interactive: true

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.size(16)
                        spacing: Theme.size(14)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.size(5)

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: roomRow.modelData.name
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSize(16)
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                StatusPill {
                                    text: roomRow.modelData.hasPassword
                                          ? qsTr("Locked") : qsTr("Open")
                                    statusColor: roomRow.modelData.hasPassword
                                                 ? Theme.warning : Theme.success
                                }
                                StatusPill {
                                    objectName: "spectatorHandsVisibleBadge"
                                    visible: roomRow.modelData.spectatorsSeeHands === true
                                    text: qsTr("Hands visible")
                                    statusColor: Theme.warning
                                }
                            }

                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: roomRow.modelData.roomId + " · "
                                      + I18n.formatLabel(roomRow.modelData.deckFormat
                                                         || roomRow.modelData.format)
                                      + " · "
                                      + root.matchLabel(roomRow.modelData.matchMode)
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSize(12)
                                elide: Text.ElideRight
                            }

                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: qsTr("Players") + " "
                                      + roomRow.modelData.playerCount + "/"
                                      + roomRow.modelData.maxSeats + " · "
                                      + qsTr("Spectators") + " "
                                      + roomRow.modelData.spectatorCount + " · "
                                      + root.phaseLabel(roomRow.modelData.phase)
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSize(11)
                                elide: Text.ElideRight
                            }
                        }

                        AppButton {
                            compact: true
                            variant: "primary"
                            text: qsTr("Join")
                            enabled: roomRow.modelData.playerJoinable
                            onClicked: root.joinRoom(roomRow.modelData, false)
                        }
                        AppButton {
                            compact: true
                            text: qsTr("Watch")
                            enabled: roomRow.modelData.spectatorJoinable
                            onClicked: root.joinRoom(roomRow.modelData, true)
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: ws
        function onLastErrorChanged() {
            if (ws.lastError && ws.lastError.length > 0)
                root.appWindow.showBanner(I18n.status(ws.lastError))
        }
    }

    function optionIndex(options, value) {
        for (let index = 0; index < options.length; ++index) {
            if (options[index].value === value)
                return index
        }
        return 0
    }

    function joinRoom(room, spectator) {
        if (room.hasPassword) {
            appWindow.pushScreen("screens/JoinRoom.qml", {
                "roomCode": room.roomId,
                "asSpectator": spectator
            })
            return
        }
        ws.joinRoom(room.roomId, spectator, "")
    }

    function matchLabel(mode) {
        return mode === "bo3" ? qsTr("BO 3") : qsTr("BO 1")
    }

    function phaseLabel(phase) {
        if (phase === "started")
            return qsTr("In game")
        if (phase === "loading")
            return qsTr("Loading")
        return qsTr("Waiting")
    }
}
