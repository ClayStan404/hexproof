// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick

Rectangle {
    id: root
    property string playerName: "You"
    property string subtitle: "Boros Energy"
    property int life: 18
    property real unit: 1
    property bool priority: false
    property bool actionable: false
    property bool selected: false
    signal activated()
    width: 240 * unit
    height: 61 * unit
    radius: 12 * unit
    color: "#ed15232d"
    border.width: actionable || selected ? 2 : 1
    border.color: selected ? "#e5bd73" : actionable ? "#79b8c5" : priority ? "#a58d62" : "#3b4f5c"
    activeFocusOnTab: actionable
    Accessible.role: Accessible.Button
    Accessible.name: playerName + ", " + life + " life" + (actionable ? ", select target" : "")
    Keys.onReturnPressed: if (actionable) activated()
    Keys.onSpacePressed: if (actionable) activated()
    Rectangle {
        x: 11 * root.unit
        y: 11 * root.unit
        width: 38 * root.unit
        height: width
        radius: 9 * root.unit
        color: root.priority ? "#3a3b31" : "#263844"
        Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: root.playerName === "You" ? "H" : "S"
            color: root.priority ? "#e5c58c" : "#a9bcca"
            font.pixelSize: 24 * root.unit
            font.family: "serif"
        }
    }
    Column {
        x: 61 * root.unit
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3 * root.unit
        Text {
            textFormat: Text.PlainText
            text: root.playerName
            color: "#e9ece7"
            font.pixelSize: 14 * root.unit
            font.weight: Font.DemiBold
        }
        Text {
            textFormat: Text.PlainText
            text: root.subtitle
            color: "#93a5b3"
            font.pixelSize: 10 * root.unit
        }
    }
    Text {
        textFormat: Text.PlainText
        anchors.right: parent.right
        anchors.rightMargin: 15 * root.unit
        anchors.verticalCenter: parent.verticalCenter
        text: root.life
        color: root.priority ? "#eed3a0" : "#d6e4e7"
        font.pixelSize: 31 * root.unit
        font.weight: Font.Medium
    }
    TapHandler { onTapped: if (root.actionable) root.activated() }
    HoverHandler { cursorShape: root.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor }
}
