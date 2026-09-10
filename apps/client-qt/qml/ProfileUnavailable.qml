// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "components"

ApplicationWindow {
    id: root
    required property bool profileOccupied
    property string windowTitle: Qt.application.name
    width: 560
    height: 300
    minimumWidth: 360
    minimumHeight: 260
    visible: true
    title: windowTitle
    color: Theme.background

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 16
        ScrollView {
            id: explanationScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ColumnLayout {
                width: explanationScroll.availableWidth
                spacing: 16
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: root.profileOccupied ? qsTr("This profile is already open")
                                               : qsTr("Cannot open this profile")
                    font.pixelSize: 22
                    font.bold: true
                    color: Theme.text
                    wrapMode: Text.WordWrap
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: root.profileOccupied
                          ? qsTr("Use the existing Hexproof window, or close it before opening this profile again. Use the multi-client launcher for independent test profiles.")
                          : qsTr("Hexproof could not lock its data directory. Check its permissions and available disk space, then try again.")
                    color: Theme.textSecondary
                    wrapMode: Text.WordWrap
                }
            }
        }
        AppButton {
            objectName: "closeProfileNotice"
            Layout.alignment: Qt.AlignRight
            text: qsTr("Close")
            onClicked: root.close()
        }
    }
}
