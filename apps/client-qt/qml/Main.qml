// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import "components"

ApplicationWindow {
    id: root

    property alias stack: stack
    property string notifiedUpdateVersion: ""
    property string notifiedDownloadPath: ""

    title: Qt.application.name
    width: 1280
    height: 800
    minimumWidth: 900
    minimumHeight: 620
    visibility: Qt.application.arguments.indexOf("--windowed") >= 0
                ? Window.Windowed : Window.Maximized
    color: Theme.background

    function syncUiScale() {
        Theme.uiScale = Theme.effectiveScale(
            width, height, preferences.interfaceScale)
    }

    onWidthChanged: syncUiScale()
    onHeightChanged: syncUiScale()
    Component.onCompleted: syncUiScale()

    Connections {
        target: preferences
        function onInterfaceScaleChanged() { root.syncUiScale() }
    }

    Connections {
        target: appUpdater

        function onStateChanged() {
            if (appUpdater.downloadReady
                    && appUpdater.downloadPath !== root.notifiedDownloadPath) {
                root.notifiedDownloadPath = appUpdater.downloadPath
                root.showBanner(qsTr("Application update downloaded and verified"))
            } else if (appUpdater.updateAvailable && !appUpdater.exactVersion
                       && !appUpdater.checking && !appUpdater.downloading
                       && appUpdater.targetVersion
                          !== root.notifiedUpdateVersion) {
                root.notifiedUpdateVersion = appUpdater.targetVersion
                root.showBanner(qsTr("Hexproof %1 is available")
                                .arg(appUpdater.targetVersion))
            }
        }
    }

    ConfigurableShortcut {
        actionId: "app.fullscreen"
        onActivated: root.visibility = root.visibility === Window.FullScreen
                     ? Window.Maximized : Window.FullScreen
    }

    StackView {
        id: stack
        anchors.fill: parent
        initialItem: "screens/MainMenu.qml"

        pushEnter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.motionNormal }
                NumberAnimation { property: "x"; from: 28; to: 0; duration: Theme.motionSlow; easing.type: Easing.OutCubic }
            }
        }
        pushExit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 1; to: 0.35; duration: Theme.motionNormal }
                NumberAnimation { property: "x"; from: 0; to: -16; duration: Theme.motionSlow; easing.type: Easing.OutCubic }
            }
        }
        popEnter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0.35; to: 1; duration: Theme.motionNormal }
                NumberAnimation { property: "x"; from: -16; to: 0; duration: Theme.motionSlow; easing.type: Easing.OutCubic }
            }
        }
        popExit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.motionNormal }
                NumberAnimation { property: "x"; from: 0; to: 28; duration: Theme.motionSlow; easing.type: Easing.OutCubic }
            }
        }
        replaceEnter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.motionSlow }
        }
        replaceExit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.motionNormal }
        }
    }

    function pushScreen(url, properties) { stack.push(url, properties || {}) }
    function popScreen() { stack.pop() }
    function tableScreenProperties() {
        return {
            "wsModel": ws,
            "gameTableModel": gameTable,
            "optimisticCommandModel": optimisticCommands,
            "sideboardTableModel": sideboardTable,
            "cardCatalogModel": cardCatalog,
            "preferencesModel": preferences,
            "deckLibraryModel": deckLibrary,
            "tournamentModel": tournament
        }
    }
    function showWaitingRoom() {
        stack.replace(null, "screens/WaitingRoom.qml",
                      {
                          "wsModel": ws,
                          "deckLibraryModel": deckLibrary
                      })
    }
    function showTable() {
        if (ws.roomSession.rulesMode === "forge") {
            stack.replace(null, "screens/RulesTable.qml",
                          {
                              "wsModel": ws,
                              "cardCatalogModel": cardCatalog
                          })
        } else {
            stack.replace(null, "screens/Table.qml",
                          root.tableScreenProperties())
        }
    }

    Connections {
        target: ws

        function onWelcomeReceived() {
            stack.replace(null, "screens/MainMenu.qml")
        }

        function onInRoomChanged() {
            if (ws.reconnecting)
                return
            if (ws.inRoom) {
                if (ws.roomSession.phase === "started")
                    root.showTable()
                else
                    root.showWaitingRoom()
            } else if (ws.connected) {
                root.showTournamentOrMenu()
            }
        }

        function onLoadRequired() {
            if (ws.roomSession.cardLoadMode === "preload") {
                stack.replace(null, "screens/MatchLoading.qml",
                              { "wsModel": ws, "loaderModel": matchLoader })
            }
        }

        function onLoadCancelled() {
            if (ws.inRoom)
                root.showWaitingRoom()
        }

        function onMatchStarted() {
            root.showTable()
        }

        function onMatchReturnedToRoom() {
            if (ws.inRoom)
                root.showWaitingRoom()
        }

        function onKicked() {
            root.showBanner(qsTr("You were removed from the room"))
        }
        function onRoomDisbanded() {
            root.showBanner(qsTr("The room was disbanded"))
        }
        function onLeftRoom() {
            root.showBanner(qsTr("You left the room"))
        }
        function onReconnectExpired() {
            root.showBanner(qsTr("The reconnect window expired."))
            if (ws.connected)
                root.showTournamentOrMenu()
            else
                stack.replace(null, "screens/MainMenu.qml")
        }
    }

    Connections {
        target: tournament

        function onInTournamentChanged() {
            if (tournament.inTournament && ws.connected && !ws.inRoom)
                stack.replace(null, "screens/TournamentLobby.qml")
            else if (!tournament.inTournament && ws.connected && !ws.inRoom)
                stack.replace(null, "screens/MainMenu.qml")
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Theme.size(24)
        width: reconnectContent.implicitWidth + Theme.size(34)
        height: Theme.size(48)
        radius: Theme.size(14)
        color: Theme.surfaceElevated
        border.width: 1
        border.color: Theme.accent
        visible: ws.reconnecting
        z: 120

        Row {
            id: reconnectContent
            anchors.centerIn: parent
            spacing: Theme.size(10)

            ActivityRing {
                anchors.verticalCenter: parent.verticalCenter
                ringColor: Theme.accent
            }

            Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: ws.reconnectSecondsRemaining > 0
                      ? qsTr("Connection lost · restoring your seat… %1 remaining")
                        .arg(root.reconnectTimeLabel(
                                 ws.reconnectSecondsRemaining))
                      : qsTr("Connection lost · restoring your seat…")
                color: Theme.text
                font.pixelSize: Theme.fontSize(12)
                font.weight: Font.DemiBold
            }
        }
    }

    Rectangle {
        id: banner

        property string message: ""

        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(Theme.size(520), bannerContent.implicitWidth + Theme.size(34))
        height: Theme.size(48)
        radius: Theme.size(14)
        color: Theme.surfaceElevated
        border.width: 1
        border.color: Theme.borderStrong
        opacity: 0
        visible: opacity > 0
        y: parent.height - height - Theme.size(28)
           + (opacity < 0.5 ? Theme.size(10) : 0)
        z: 100

        Row {
            id: bannerContent
            anchors.centerIn: parent
            spacing: Theme.size(10)

            Rectangle {
                width: Theme.size(8)
                height: Theme.size(8)
                radius: Theme.size(4)
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                textFormat: Text.PlainText
                text: banner.message
                color: Theme.text
                font.pixelSize: Theme.fontSize(13)
                font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Timer {
            id: hideTimer
            onTriggered: banner.opacity = 0
        }

        Behavior on opacity { NumberAnimation { duration: Theme.motionNormal } }
        Behavior on y { NumberAnimation { duration: Theme.motionNormal; easing.type: Easing.OutCubic } }

        function show(message, duration) {
            banner.message = message
            banner.opacity = 1
            hideTimer.interval = duration
            hideTimer.restart()
        }
    }

    function showBanner(message) { banner.show(message, 2600) }

    function reconnectTimeLabel(totalSeconds) {
        const minutes = Math.floor(totalSeconds / 60)
        const seconds = totalSeconds % 60
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }

    function showTournamentOrMenu() {
        stack.replace(null, tournament.inTournament
                      ? "screens/TournamentLobby.qml"
                      : "screens/MainMenu.qml")
    }
}
