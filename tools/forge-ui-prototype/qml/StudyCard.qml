// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick

Rectangle {
    id: root
    required property var card
    property string assetRoot: ""
    property real unit: 1
    property bool actionable: false
    property bool selected: false
    property bool tapped: false
    property bool fullFace: false
    property bool pointerEnabled: true
    property bool focusRing: activeFocus
    property string actionHint: ""
    property string statusText: ""
    property bool showActionHint: true
    readonly property bool compact: width < 128 * unit
    signal activated()
    signal inspected(var card)
    signal previewed(var card)
    signal previewEnded()
    objectName: "studyCard-" + card.id
    width: 160 * unit
    height: (fullFace ? 223 : 145) * unit
    radius: 10 * unit
    color: "#15222b"
    border.width: selected || focusRing ? 3 : actionable ? 2 : 1
    border.color: selected ? "#e5bd73" : focusRing ? "#f3dcae" : actionable ? "#79b8c5" : "#536570"
    activeFocusOnTab: pointerEnabled
    Accessible.role: Accessible.Button
    Accessible.name: card.name + (card.counters ? ", " + card.counters : "")
        + (actionHint ? ", " + actionHint : "")
    Keys.onReturnPressed: actionable ? activated() : inspected(card)
    Keys.onSpacePressed: actionable ? activated() : inspected(card)

    Rectangle {
        anchors.fill: parent
        anchors.margins: -4 * root.unit
        radius: root.radius + 3 * root.unit
        color: "transparent"
        border.color: root.selected ? "#75623e" : "#3c6271"
        visible: root.selected || root.actionable
        z: -1
    }
    Item {
        anchors.fill: parent
        anchors.margins: 3 * root.unit
        clip: true
        Image {
            anchors.fill: parent
            source: root.assetRoot ? root.assetRoot + root.card.key + (root.fullFace ? "-full.jpg" : "-art.jpg") : ""
            fillMode: root.fullFace ? Image.PreserveAspectFit : Image.PreserveAspectCrop
            asynchronous: true
            opacity: root.tapped ? 0.52 : 1
            sourceSize.width: root.fullFace ? 488 : 420
        }
        Rectangle {
            anchors.fill: parent
            visible: !root.fullFace
            gradient: Gradient {
                GradientStop { position: 0; color: "#c8101a22" }
                GradientStop { position: 0.30; color: "#08101a22" }
                GradientStop { position: 0.65; color: "#08101a22" }
                GradientStop { position: 1; color: "#e5101a22" }
            }
        }
        Text {
            textFormat: Text.PlainText
            visible: !root.fullFace
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 8 * root.unit
            text: root.card.name
            color: "#f3f1e9"
            font.pixelSize: 12 * root.unit
            font.weight: Font.DemiBold
            maximumLineCount: 2
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
        }
        Text {
            textFormat: Text.PlainText
            visible: !root.fullFace && root.tapped
            anchors.centerIn: parent
            text: "↷"
            color: "#ffffff"
            font.pixelSize: 46 * root.unit
        }
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 5 * root.unit
            visible: !root.fullFace && !!root.card.stats
            width: statsLabel.implicitWidth + 14 * root.unit
            height: 25 * root.unit
            radius: 5 * root.unit
            color: "#e2e5df"
            Text {
                id: statsLabel
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: root.card.stats || ""
                color: "#18212a"
                font.pixelSize: 14 * root.unit
                font.weight: Font.Bold
            }
        }
        Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 7 * root.unit
            anchors.bottomMargin: root.compact && root.card.stats ? 35 * root.unit : 7 * root.unit
            width: parent.width - 14 * root.unit
            visible: !root.fullFace
            text: root.card.counters || (root.card.kind.indexOf("land") >= 0 || root.card.kind === "Land" ? root.card.cost : "")
            elide: Text.ElideRight
            color: root.card.counters ? "#e9c785" : "#f3f1e9"
            font.pixelSize: 11 * root.unit
            font.weight: Font.DemiBold
        }
    }
    Rectangle {
        visible: root.showActionHint && (root.selected || root.statusText !== "" || (root.actionable && root.actionHint !== ""))
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.bottom
        anchors.topMargin: -2 * root.unit
        width: hint.implicitWidth + 16 * root.unit
        height: 21 * root.unit
        radius: 4 * root.unit
        color: root.selected ? "#e1bf82" : "#254652"
        Text {
            id: hint
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: root.statusText || (root.selected ? "SELECTED" : root.actionHint)
            color: root.selected ? "#19232b" : "#bee1e7"
            font.pixelSize: 9 * root.unit
            font.letterSpacing: 1
            font.weight: Font.Bold
        }
    }
    HoverHandler {
        id: hover
        enabled: root.pointerEnabled
        onHoveredChanged: hovered ? root.previewed(root.card) : root.previewEnded()
        cursorShape: root.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    TapHandler {
        enabled: root.pointerEnabled
        acceptedButtons: Qt.LeftButton
        onTapped: root.actionable ? root.activated() : root.inspected(root.card)
    }
    TapHandler {
        enabled: root.pointerEnabled
        acceptedButtons: Qt.RightButton
        onTapped: root.inspected(root.card)
    }
}
