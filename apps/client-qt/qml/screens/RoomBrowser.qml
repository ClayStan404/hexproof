// SPDX-License-Identifier: GPL-3.0-or-later
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
    Component.onCompleted: {
        if (ws.connected)
            ws.requestRoomList()
    }

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
        {"label": qsTr("In game"), "value": "in_game"},
        {"label": qsTr("Drafting"), "value": "draft"},
        {"label": qsTr("Deck building"), "value": "deck_building"},
        {"label": qsTr("Free play"), "value": "free_play"}
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
        {"label": I18n.formatLabel("commander"), "value": "edh"},
        {"label": qsTr("Cube"), "value": "cube"}
    ]
    readonly property var sortOptions: [
        {"label": qsTr("Joinable first"), "value": "joinable"},
        {"label": qsTr("Name"), "value": "name"},
        {"label": qsTr("Open seats"), "value": "seats"}
    ]

    ScreenHeader {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(22)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        title: qsTr("Rooms on this hub")
        subtitle: qsTr("Only tables hosted on your connected server are shown")
        onBackRequested: root.appWindow.popScreen()
    }

    Flickable {
        id: browserBody
        objectName: "roomBrowserBody"
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(16)
        anchors.bottomMargin: Theme.size(28)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        contentWidth: width
        contentHeight: browserContent.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: browserContent
            width: browserBody.width
            height: Math.max(browserBody.height, implicitHeight)
            spacing: Theme.size(16)

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
                Layout.minimumHeight: ws.roomList.length === 0
                                      ? emptyHubState.implicitHeight + Theme.size(48)
                                      : roomQuery.visibleRooms.length === 0
                                        ? filteredEmptyState.implicitHeight + Theme.size(48)
                                        : Theme.size(220)
                color: Theme.surfaceMuted

                ColumnLayout {
                    id: emptyHubState
                    anchors.centerIn: parent
                    width: Math.min(parent.width - Theme.size(60), Theme.size(520))
                    objectName: "emptyHubRoomState"
                    visible: ws.roomList.length === 0 || !ws.connected
                    spacing: Theme.size(10)

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: ws.connected ? qsTr("No rooms are open on this hub yet.")
                                           : qsTr("You are disconnected from the server.")
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(16)
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: ws.connected
                              ? qsTr("Create a table now, or refresh after a friend shares one.")
                              : qsTr("Connect to a server to browse rooms.")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(12)
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        AppButton {
                            objectName: "emptyRoomCreateButton"
                            visible: ws.connected
                            variant: "primary"
                            text: qsTr("Create room")
                            leadingText: "+"
                            onClicked: root.appWindow.pushScreen("screens/CreateRoom.qml")
                        }
                        AppButton {
                            objectName: "emptyRoomRefreshButton"
                            visible: ws.connected
                            text: qsTr("Refresh")
                            leadingText: "↻"
                            onClicked: ws.requestRoomList()
                        }
                        AppButton {
                            objectName: "roomBrowserConnectButton"
                            visible: !ws.connected
                            variant: "primary"
                            text: qsTr("Connect to server")
                            onClicked: root.appWindow.pushScreen("screens/Connect.qml")
                        }
                    }
                }

                ColumnLayout {
                    id: filteredEmptyState
                    objectName: "filteredRoomEmptyState"
                    anchors.centerIn: parent
                    width: Math.min(parent.width - Theme.size(60), Theme.size(520))
                    visible: ws.connected && ws.roomList.length > 0
                             && roomQuery.visibleRooms.length === 0
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
                    visible: ws.connected && roomQuery.visibleRooms.length > 0
                    model: roomQuery.visibleRooms
                    spacing: Theme.size(10)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    ScrollChainHandler {
                        innerFlickable: roomListView
                        outerFlickable: browserBody
                    }

                    delegate: Surface {
                        id: roomRow
                        required property var modelData
                        required property int index
                        readonly property bool canReturnToCube: modelData.roomKind === "cube"
                            && ws.hasCubeRoomCredential(modelData.roomId)
                        width: ListView.view.width
                        height: Math.max(Theme.size(112), roomRowContent.implicitHeight + Theme.size(32))
                        color: Theme.surfaceElevated
                        interactive: true

                        GridLayout {
                            id: roomRowContent
                            columns: root.width < Theme.size(1050) ? 1 : 2
                            anchors.fill: parent
                            anchors.margins: Theme.size(16)
                            columnSpacing: Theme.size(14)
                            rowSpacing: Theme.size(8)

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
                                    StatusPill {
                                        visible: roomRow.modelData.rulesMode === "forge"
                                        text: qsTr("Forge rules")
                                        statusColor: Theme.accent
                                    }
                                }

                                Text {
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: roomRow.modelData.roomId + " · "
                                          + I18n.formatLabel(roomRow.modelData.roomKind === "cube"
                                                             && roomRow.modelData.format === "edh"
                                                             ? "commander_cube" : roomRow.modelData.deckFormat
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

                            RowLayout {
                                Layout.alignment: Qt.AlignRight
                                spacing: Theme.size(8)
                                AppButton {
                                    objectName: "joinListedRoomButton"
                                    compact: true
                                    variant: "primary"
                                    text: roomRow.canReturnToCube ? qsTr("Return to room") : qsTr("Join")
                                    enabled: ws.connected
                                             && (roomRow.modelData.playerJoinable || roomRow.canReturnToCube)
                                    onClicked: root.joinRoom(roomRow.modelData, false)
                                }
                                AppButton {
                                    objectName: "watchListedRoomButton"
                                    compact: true
                                    text: qsTr("Watch")
                                    enabled: ws.connected && roomRow.modelData.spectatorJoinable
                                    onClicked: root.joinRoom(roomRow.modelData, true)
                                }
                            }
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
        if (!ws.connected)
            return
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
        if (phase === "draft")
            return qsTr("Drafting")
        if (phase === "deck_building")
            return qsTr("Deck building")
        if (phase === "free_play")
            return qsTr("Free play")
        if (phase === "started")
            return qsTr("In game")
        if (phase === "loading")
            return qsTr("Loading")
        return qsTr("Waiting")
    }
}
