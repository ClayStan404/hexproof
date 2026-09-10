// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "TournamentLobby"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var lobbyController
    required property var tournamentModel
    required property var limitedModel
    required property var wsModel
    required property var cancelDialogTarget
    property int selectedTab: 0
    Layout.preferredWidth: Theme.size(330)
    Layout.fillHeight: true
    Layout.fillWidth: false

    SegmentedControl {
        objectName: "tournamentSidebarTabs"
        Layout.fillWidth: true
        options: [qsTranslate("TournamentLobby", "Event desk"), qsTranslate("TournamentLobby", "Chat")]
        currentIndex: root.selectedTab
        onActivated: index => root.selectedTab = index
    }
    Flickable {
        id: deskScroll
        objectName: "tournamentEventDeskScroll"
        visible: root.selectedTab === 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentWidth: width
        contentHeight: desk.height
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { }
        TournamentEventDesk {
            id: desk
            width: deskScroll.width
            height: Math.max(deskScroll.height, implicitHeight)
            lobbyController: root.lobbyController
            tournamentModel: root.tournamentModel
            limitedModel: root.limitedModel
            wsModel: root.wsModel
            cancelDialogTarget: root.cancelDialogTarget
        }
    }
    TournamentChat {
        visible: root.selectedTab === 1
        Layout.fillWidth: true
        Layout.fillHeight: true
        tournamentModel: root.tournamentModel
        wsModel: root.wsModel
    }
}
