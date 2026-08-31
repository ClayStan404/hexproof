// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: root

    required property var card
    required property var catalogModel
    property string actionText: ""
    property bool emphasized: false
    signal activated()
    signal inspectionRequested()
    signal inspectionEnded()

    readonly property string rarity: root.card && root.card.rarity
                                             ? String(root.card.rarity).toLowerCase()
                                             : "unknown"

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
        id: footer

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Theme.size(34)
        color: Theme.inactiveSelection

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.size(4)
            spacing: Theme.size(3)

            Rectangle {
                Layout.preferredWidth: Theme.size(22)
                Layout.preferredHeight: Theme.size(22)
                radius: height / 2
                color: Theme.backgroundRaised
                border.width: 1
                border.color: root.rarityColor()

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: root.rarityCode()
                    color: root.rarityColor()
                    font.pixelSize: Theme.fontSize(8)
                    font.weight: Font.Bold
                }
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.card && root.card.name
                      ? root.card.name : qsTr("Unknown card")
                color: Theme.text
                font.pixelSize: Theme.fontSize(9)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }

            Rectangle {
                visible: root.actionText.length > 0
                Layout.preferredWidth: Theme.size(26)
                Layout.preferredHeight: Theme.size(26)
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
        }
    }

    TapHandler {
        onTapped: root.activated()
    }

    HoverHandler {
        id: hover

        onHoveredChanged: {
            if (hovered)
                root.inspectionRequested()
            else
                root.inspectionEnded()
        }
    }
    ToolTip.visible: hover.hovered
    ToolTip.delay: 350
    ToolTip.text: root.card && root.card.name
                  ? root.card.name + " · " + (root.card.setCode || "")
                    + " #" + (root.card.collectorNumber || "")
                    + " · " + root.rarityLabel()
                  : ""

    function rarityCode() {
        if (rarity === "common")
            return "C"
        if (rarity === "uncommon")
            return "U"
        if (rarity === "rare")
            return "R"
        if (rarity === "mythic")
            return "M"
        return "?"
    }

    function rarityColor() {
        if (rarity === "mythic")
            return "#E88943"
        if (rarity === "rare")
            return Theme.accent
        if (rarity === "uncommon")
            return "#C4CFCA"
        return Theme.borderStrong
    }

    function rarityLabel() {
        if (rarity === "mythic")
            return qsTr("Mythic rare")
        if (rarity === "rare")
            return qsTr("Rare")
        if (rarity === "uncommon")
            return qsTr("Uncommon")
        if (rarity === "common")
            return qsTr("Common")
        return qsTr("Unknown rarity")
    }
}
