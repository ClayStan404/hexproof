// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    required property var tableController
    required property real unit
    required property int ownerSeat
    required property string zone
    property bool compact: false

    readonly property int count: tableController.zoneCount(ownerSeat, zone)
    readonly property var face: tableController.topPublicZoneCard(ownerSeat, zone)
    readonly property string cardId: face && face.cardId ? face.cardId : ""
    readonly property bool showsPublicFace:
        !!(face && face.visibleIdentity && !face.faceDown && face.name)
    readonly property string shortLabel: {
        switch (zone) {
        case "library": return qsTr("Library")
        case "graveyard": return qsTr("GY")
        case "exile": return qsTr("Exile")
        case "command": return qsTr("Cmd")
        default: return tableController.zoneLabel(zone)
        }
    }
    readonly property color accent: {
        switch (zone) {
        case "graveyard": return "#C48AA0"
        case "exile": return Theme.primary
        case "command": return Theme.accent
        default: return Theme.borderStrong
        }
    }
    readonly property url faceSource: showsPublicFace
        ? tableController.cardImage(face.name, face.setCode || "", face.collectorNumber || "")
        : tableController.cardBackSource
    readonly property int stackDepth: count <= 0 ? 0 : Math.min(2, count - (count > 0 ? 1 : 0))
    readonly property real faceBudgetWidth: Math.max(0, width - stackDepth * 2 * unit)
    readonly property real faceBudgetHeight: Math.max(
        0, height - (compact ? 0 : 15 * unit) - stackDepth * 2 * unit)
    readonly property real cardFaceWidth: Math.min(
        faceBudgetWidth, faceBudgetHeight * 63 / 88)
    readonly property real cardFaceHeight: cardFaceWidth * 88 / 63

    signal activated()

    Accessible.role: Accessible.Button
    Accessible.name: tableController.zoneLabel(zone) + " · " + count
    Accessible.onPressAction: activated()

    Repeater {
        model: root.stackDepth
        delegate: Rectangle {
            required property int index
            readonly property real lift: (index + 1) * 2 * root.unit
            x: pileFace.x + lift
            y: pileFace.y + lift
            width: pileFace.width
            height: pileFace.height
            radius: pileFace.radius
            antialiasing: true
            z: index
            color: Theme.withAlpha("#0A1012", 0.72)
            border.width: 1
            border.color: Theme.withAlpha(root.accent, 0.28)
        }
    }

    Rectangle {
        id: pileFace
        objectName: "forgeZonePileFace"
        x: Math.max(0, (root.faceBudgetWidth - width) / 2)
        y: 0
        width: root.count > 0 ? root.cardFaceWidth : root.faceBudgetWidth
        height: root.count > 0 ? root.cardFaceHeight : root.faceBudgetHeight
        radius: 7 * root.unit
        antialiasing: true
        clip: true
        z: 3
        color: Theme.withAlpha("#10161A", root.count > 0 ? 0.88 : 0.42)
        border.width: pileMouse.containsMouse || root.activeFocus ? 2 : 1
        border.color: pileMouse.containsMouse || root.activeFocus ? root.accent
                      : Theme.withAlpha(root.accent, 0.45)

        Image {
            objectName: "forgeZonePileArt"
            anchors.fill: parent
            anchors.margins: 2 * root.unit
            visible: root.count > 0
            source: root.faceSource
            sourceSize.width: 180
            sourceSize.height: 252
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
        }

        Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 4 * root.unit
            visible: root.compact && root.count > 0
            text: root.shortLabel
            color: "#F3F1E9"
            style: Text.Outline
            styleColor: Theme.withAlpha("#000000", 0.7)
            font.pixelSize: 11 * root.unit
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            visible: root.count <= 0
            text: root.shortLabel
            color: Theme.textMuted
            font.pixelSize: 10 * root.unit
            font.weight: Font.DemiBold
        }
    }

    Rectangle {
        visible: root.count > 0
        anchors.right: pileFace.right
        anchors.top: pileFace.top
        anchors.margins: -3 * root.unit
        z: 4
        width: Math.max(22 * root.unit, badgeLabel.implicitWidth + 10 * root.unit)
        height: 20 * root.unit
        radius: height / 2
        color: Theme.withAlpha(Theme.surface, 0.92)
        border.width: 1
        border.color: Theme.withAlpha(root.accent, 0.7)
        Text {
            id: badgeLabel
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: root.count
            color: Theme.text
            font.pixelSize: 12 * root.unit
            font.weight: Font.DemiBold
        }
    }

    Text {
        textFormat: Text.PlainText
        visible: !root.compact
        anchors.horizontalCenter: pileFace.horizontalCenter
        anchors.top: pileFace.bottom
        anchors.topMargin: 2 * root.unit
        width: root.width
        text: root.shortLabel
        color: Theme.textSecondary
        style: Text.Outline
        styleColor: Theme.withAlpha("#000000", 0.55)
        font.pixelSize: 10 * root.unit
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
    }

    MouseArea {
        id: pileMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
        onEntered: {
            if (root.showsPublicFace && root.cardId.length)
                root.tableController.previewCard(root.cardId, root)
        }
        onExited: root.tableController.endCardPreview(root)
    }

    Component.onDestruction: root.tableController.endCardPreview(root)
}
