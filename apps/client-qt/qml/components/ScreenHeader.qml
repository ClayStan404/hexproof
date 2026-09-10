// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property string title: ""
    property string subtitle: ""
    property bool showBack: true
    signal backRequested()

    implicitHeight: Math.max(Theme.size(58), headerRow.implicitHeight)

    RowLayout {
        id: headerRow
        anchors.fill: parent
        spacing: Theme.size(14)

        AppButton {
            visible: root.showBack
            variant: "ghost"
            compact: true
            text: qsTr("Back")
            leadingText: "‹"
            onClicked: root.backRequested()
        }

        BrandMark {
            visible: !root.showBack
            markSize: Theme.size(34)
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.size(2)

            Text {
                objectName: "screenHeaderTitle"
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.title
                color: Theme.text
                font.pixelSize: Theme.fontSize(18)
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
            }

            Text {
                objectName: "screenHeaderSubtitle"
                textFormat: Text.PlainText
                Layout.fillWidth: true
                visible: root.subtitle.length > 0
                text: root.subtitle
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
                wrapMode: Text.Wrap
            }
        }

    }
}
