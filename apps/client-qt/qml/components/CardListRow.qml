// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property var card: ({})
    property int quantity: 1
    property bool highlighted: false
    readonly property string cardColors: String(card.cardColors || "").toUpperCase()
    readonly property color frameColor: cardColors.length > 1 ? "#be9b42"
        : ({W: "#d5cba1", U: "#419dc6", B: "#777078", R: "#e0694e", G: "#39976a"})[cardColors] || "#8c9996"
    readonly property color namePlateColor: cardColors.length > 1 ? "#e1d5aa"
        : ({W: "#ece8d8", U: "#b5d8e8", B: "#beb9bd", R: "#f2bcaa", G: "#b0d4c1"})[cardColors] || "#c9d0cb"
    implicitHeight: Theme.size(36)
    implicitWidth: Theme.size(320)

    Rectangle {
        id: countBadge
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(Theme.size(36), countLabel.implicitWidth + Theme.size(15))
        height: parent.height - Theme.size(2)
        radius: height / 2
        color: "#0a0e0c"
        border.color: "#929a93"
        Text {
            id: countLabel
            textFormat: Text.PlainText
            objectName: "compactCardQuantity"
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -Theme.size(2)
            text: root.quantity + "×"
            color: "#f1eee4"
            font.pixelSize: Theme.fontSize(15)
        }
    }
    Rectangle {
        id: frame
        objectName: "compactCardFrame"
        anchors.left: countBadge.right
        anchors.leftMargin: -Theme.size(4)
        anchors.right: parent.right
        height: parent.height
        radius: Theme.size(11)
        border.width: root.highlighted ? Theme.size(2) : Theme.size(1)
        border.color: root.highlighted ? Theme.accent : "#b2b6aa"
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter(root.frameColor, 1.35) }
            GradientStop { position: 0.45; color: root.frameColor }
            GradientStop { position: 1; color: Qt.darker(root.frameColor, 1.25) }
        }
        Rectangle {
            id: namePlate
            anchors.fill: parent
            anchors.margins: Theme.size(4)
            radius: Theme.size(8)
            color: root.namePlateColor
            border.color: "#303630"
            border.width: Theme.size(2)
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.size(8)
                anchors.rightMargin: Theme.size(4)
                spacing: Theme.size(5)
                Text {
                    textFormat: Text.PlainText
                    objectName: "compactCardName"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: root.card.displayName || root.card.name || ""
                    color: "#141b16"
                    font.pixelSize: Theme.fontSize(13)
                    font.bold: true
                    elide: Text.ElideRight
                }
                CardManaCost {
                    objectName: "compactCardManaCost"
                    Layout.preferredWidth: Math.min(implicitWidth, Math.max(0, namePlate.width * 0.48))
                    Layout.minimumWidth: 0
                    cost: root.card.manaCost
                }
            }
        }
    }
}
