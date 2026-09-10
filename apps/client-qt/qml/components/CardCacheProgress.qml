// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: root

    required property var catalogModel
    readonly property real progressValue:
        Math.max(0, Math.min(1, Number(catalogModel.progress) || 0))

    visible: catalogModel.busy && !catalogModel.searching && !catalogModel.tokenSearching
    spacing: Theme.size(5)

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.size(10)

        Text {
            objectName: "cardCacheProgressStatus"
            textFormat: Text.PlainText
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: I18n.status(root.catalogModel.status)
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(11)
            elide: Text.ElideRight
        }
        Text {
            objectName: "cardCacheProgressPercent"
            textFormat: Text.PlainText
            text: Math.round(root.progressValue * 100) + "%"
            color: Theme.primary
            font.pixelSize: Theme.fontSize(11)
        }
    }

    ProgressBar {
        id: progressBar
        objectName: "cardCacheProgressBar"
        Layout.fillWidth: true
        implicitHeight: Theme.size(8)
        from: 0
        to: 1
        value: root.progressValue

        background: Rectangle {
            color: Theme.disabled
            radius: height / 2
        }
        contentItem: Item {
            Rectangle {
                width: parent.width * progressBar.visualPosition
                height: parent.height
                radius: height / 2
                color: Theme.primary
            }
        }
    }
}
