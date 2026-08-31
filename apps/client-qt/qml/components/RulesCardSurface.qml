// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic

Rectangle {
    id: root

    required property var cardCatalogModel
    required property url cardBackSource
    required property bool visibleIdentity
    required property string name
    required property string setCode
    required property string collectorNumber
    required property bool tapped
    required property bool faceDown
    required property bool attacking
    required property string power
    required property string toughness
    required property string countersSummary
    property bool rotateTapped: true

    function imageSource() {
        if (!root.visibleIdentity || root.faceDown)
            return root.cardBackSource
        if (!root.name || !root.cardCatalogModel
                || typeof root.cardCatalogModel.tableImageSource !== "function")
            return ""
        void root.cardCatalogModel.imageRevision
        return root.cardCatalogModel.tableImageSource(
                    root.name, root.setCode || "", root.collectorNumber || "")
    }

    radius: Theme.radiusSmall
    color: Theme.surfaceHover
    border.width: attacking ? Theme.size(2) : 1
    border.color: attacking ? Theme.error : Theme.borderStrong
    rotation: rotateTapped && tapped ? 90 : 0
    transformOrigin: Item.Center
    clip: true

    Image {
        id: cardArt
        anchors.fill: parent
        anchors.margins: Theme.size(2)
        source: root.imageSource()
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
    }

    Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        width: parent.width - Theme.size(10)
        visible: cardArt.status !== Image.Ready
        text: root.visibleIdentity && !root.faceDown && root.name
              ? root.name : qsTr("Hidden card")
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSize(8)
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Theme.size(22)
        color: Theme.badgeBackground

        Text {
            textFormat: Text.PlainText
            anchors.fill: parent
            anchors.leftMargin: Theme.size(4)
            anchors.rightMargin: Theme.size(4)
            text: root.visibleIdentity && !root.faceDown
                  ? root.name : qsTr("Face-down card")
            color: Theme.text
            font.pixelSize: Theme.fontSize(8)
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
    }

    StatusPill {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.size(4)
        visible: root.power.length > 0 || root.toughness.length > 0
        text: root.power + "/" + root.toughness
        statusColor: Theme.primary
    }

    ToolTip.visible: hover.hovered
    ToolTip.text: root.visibleIdentity && !root.faceDown
                  ? [root.name,
                     root.power.length > 0
                     ? root.power + "/" + root.toughness : "",
                     root.countersSummary]
                    .filter(value => value.length > 0).join(" · ")
                  : qsTr("Face-down card")

    HoverHandler { id: hover }
}
