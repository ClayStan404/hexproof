// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    property string title: qsTr("Settings")
    property string subtitle: ""
    property string bodyObjectName: "settingsBody"
    default property alias contentData: contentColumn.data
    readonly property var appWindow: ApplicationWindow.window

    ScreenHeader {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(22)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        title: root.title
        subtitle: root.subtitle
        onBackRequested: root.appWindow.popScreen()
    }

    ScrollView {
        objectName: root.bodyObjectName
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(14)
        anchors.bottomMargin: Theme.size(28)
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            id: contentColumn
            width: Math.min(Theme.size(760), parent.width - Theme.size(72))
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.size(16)
        }
    }
}
