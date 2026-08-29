// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic

Rectangle {
    id: root

    required property var card
    required property var catalogModel
    property string actionText: ""
    property bool emphasized: false
    signal activated()

    readonly property string imageSource: {
        if (!root.card || !root.card.name || !root.catalogModel)
            return ""
        void root.catalogModel.imageRevision
        return root.catalogModel.tableImageSource(
                    root.card.name, root.card.setCode || "",
                    root.card.collectorNumber || "")
    }

    radius: Theme.radiusSmall
    color: Theme.surfaceElevated
    border.width: root.emphasized ? 3 : 1
    border.color: root.emphasized ? Theme.primary : Theme.border
    clip: true

    Image {
        id: art
        anchors.fill: parent
        anchors.margins: Theme.size(3)
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        source: root.imageSource
    }

    Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        width: parent.width - Theme.size(16)
        visible: art.status !== Image.Ready
        text: root.card && root.card.name ? root.card.name : qsTr("Unknown card")
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSize(11)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Theme.size(34)
        color: Theme.inactiveSelection

        Text {
            textFormat: Text.PlainText
            anchors.fill: parent
            anchors.margins: Theme.size(5)
            text: root.card && root.card.name ? root.card.name : qsTr("Unknown card")
            color: Theme.text
            font.pixelSize: Theme.fontSize(9)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
    }

    Rectangle {
        visible: root.actionText.length > 0
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.size(5)
        width: Theme.size(26)
        height: width
        radius: width / 2
        color: root.emphasized ? Theme.primary : Theme.surfaceElevated
        border.width: 1
        border.color: root.emphasized ? Theme.primary : Theme.border

        Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: root.actionText
            color: root.emphasized ? Theme.primaryInk : Theme.text
            font.pixelSize: Theme.fontSize(13)
            font.weight: Font.Bold
        }
    }

    TapHandler {
        onTapped: root.activated()
    }

    HoverHandler { id: hover }
    ToolTip.visible: hover.hovered
    ToolTip.delay: 350
    ToolTip.text: root.card && root.card.name
                  ? root.card.name + " · " + (root.card.setCode || "")
                    + " #" + (root.card.collectorNumber || "")
                  : ""
}
