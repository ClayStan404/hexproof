// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root

    property string titleText: ""
    property string subtitleText: ""
    property bool showClose: false
    property string closeObjectName: ""
    signal closeRequested()

    spacing: Theme.size(10)
    Layout.fillWidth: true

    ColumnLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: Theme.size(3)

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.titleText
            elide: Text.ElideRight
            wrapMode: root.subtitleText.length > 0 ? Text.NoWrap : Text.WordWrap
            color: Theme.text
            font.pixelSize: Theme.fontSize(18)
            font.weight: Font.DemiBold
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: root.subtitleText.length > 0
            text: root.subtitleText
            wrapMode: Text.WordWrap
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(12)
        }
    }

    AppButton {
        objectName: root.closeObjectName
        visible: root.showClose
        compact: true
        variant: "ghost"
        text: "×"
        accessibleName: qsTr("Close")
        Layout.preferredWidth: Theme.size(40)
        onClicked: root.closeRequested()
    }
}
