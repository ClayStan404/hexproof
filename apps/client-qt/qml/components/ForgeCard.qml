// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
import QtQuick

Rectangle {
    id: root
    required property var tableController
    required property var card
    property real unit: 1
    property bool fullFace: false
    property bool pointerEnabled: true
    property bool located: false
    property string objectKind: "card"
    readonly property string objectId: card.cardId || card.objectId || ""
    readonly property bool publicFace: card.visibleIdentity !== false && !card.faceDown && !!card.name
    readonly property var combat: tableController.combatInteraction
    readonly property bool actionable: combat && combat.active && objectKind === "card"
        ? combat.actionable(objectId) : tableController.interaction.objectActionable(objectKind, objectId)
    readonly property bool selected: located || (combat && combat.active && objectKind === "card"
        ? combat.selected(objectId) : tableController.interaction.objectSelected(objectKind, objectId))
    readonly property string combatLabel: combat && combat.active ? combat.labelFor(objectId) : ""
    readonly property bool previewActive: pointerEnabled && visible && (hover.hovered || activeFocus)
    signal activated()

    function activate() {
        if (combat && combat.active && objectKind === "card" && combat.activate(objectId)) return
        if (!tableController.interaction.activateObject(objectKind, objectId, publicFace ? card.name : ""))
            tableController.openCardDetails(objectId)
        activated()
    }
    onPreviewActiveChanged: {
        if (previewActive) tableController.previewCard(objectId, root)
        else tableController.endCardPreview(root)
    }
    Component.onDestruction: if (previewActive) tableController.endCardPreview(root)
    width: 180 * unit
    height: width * (fullFace ? 1.394 : 0.93)
    radius: 8 * unit
    color: "#172732"
    border.width: selected || activeFocus ? 3 : actionable ? 2 : 1
    border.color: selected ? "#e5bd73" : actionable ? "#79b8c5" : activeFocus ? "#eee0c5" : "#536570"
    activeFocusOnTab: pointerEnabled
    Keys.onReturnPressed: activate()
    Keys.onSpacePressed: activate()
    Accessible.role: Accessible.Button
    Accessible.name: publicFace ? card.name : qsTr("Hidden card")
    Accessible.onPressAction: activate()

    Item {
        anchors.fill: parent
        anchors.margins: 3 * root.unit
        clip: true
        Image {
            id: art
            // Clip in scene coordinates: the cached image provider supplies a
            // complete thumbnail and does not implement Image.sourceClipRect.
            readonly property bool cropArt: root.publicFace && !root.fullFace
            width: cropArt ? Math.max(parent.width / 0.84, parent.height / (1.394 * 0.43)) : parent.width
            height: cropArt ? width * 1.394 : parent.height
            x: (parent.width - width) / 2
            y: cropArt ? -height * 0.14 : 0
            source: root.publicFace ? root.tableController.cardImage(root.card.name, root.card.setCode, root.card.collectorNumber)
                                    : root.tableController.cardBackSource
            sourceSize.width: 320
            sourceSize.height: 448
            fillMode: root.fullFace ? Image.PreserveAspectFit : Image.PreserveAspectCrop
            asynchronous: true
            opacity: root.card.tapped ? 0.5 : 1
        }
        Rectangle {
            anchors.fill: parent
            visible: !root.fullFace
            gradient: Gradient {
                GradientStop { position: 0; color: "#d5101a22" }
                GradientStop { position: 0.4; color: "#08101a22" }
                GradientStop { position: 1; color: "#ed101a22" }
            }
        }
        Text {
            textFormat: Text.PlainText
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 7 * root.unit
            visible: !root.fullFace || art.status !== Image.Ready
            text: root.publicFace ? root.card.name : qsTr("Hidden card")
            color: "#f3f1e9"
            font.pixelSize: 12 * root.unit
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            visible: root.card.tapped === true
            text: "↷"
            color: "white"
            font.pixelSize: 42 * root.unit
        }
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 4 * root.unit
            visible: !root.fullFace && (!!root.card.power || !!root.card.toughness)
            width: powerLabel.implicitWidth + 12 * root.unit
            height: 25 * root.unit
            radius: 5 * root.unit
            color: "#e2e5df"
            Text {
                id: powerLabel
                objectName: "forgeCardStats-" + root.objectId
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: (root.card.power || "") + " / " + (root.card.toughness || "")
                color: "#18212a"
                font.pixelSize: 14 * root.unit
                font.weight: Font.Bold
            }
        }
        Text {
            objectName: "forgeCardState-" + root.objectId
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 6 * root.unit
            anchors.bottomMargin: root.card.power || root.card.toughness ? 34 * root.unit : 6 * root.unit
            visible: !root.fullFace
            text: [root.card.countersSummary || "", root.card.damage > 0 ? qsTr("%1 dmg").arg(root.card.damage) : "",
                   root.card.attachedTo ? qsTr("Attached") : "",
                   root.card.exiledCardCount > 0 ? qsTr("Exiled: %1").arg(root.card.exiledCardCount) : ""].filter(v => v.length).join(" · ")
            color: "#e9c785"
            font.pixelSize: 10 * root.unit
            elide: Text.ElideRight
        }
    }
    Rectangle {
        visible: root.combatLabel.length > 0 || root.card.attacking === true
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -14 * root.unit
        width: hint.implicitWidth + 14 * root.unit
        height: 19 * root.unit
        radius: 4 * root.unit
        color: "#e1bf82"
        Text {
            id: hint
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: root.combatLabel || qsTr("Attacking")
            color: "#19232b"
            font.pixelSize: 9 * root.unit
            font.weight: Font.Bold
        }
    }
    HoverHandler { id: hover; enabled: root.pointerEnabled; cursorShape: root.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler { enabled: root.pointerEnabled; acceptedButtons: Qt.LeftButton; onTapped: root.activate() }
    TapHandler { enabled: root.pointerEnabled; acceptedButtons: Qt.RightButton; onTapped: root.tableController.openCardDetails(root.objectId) }
}
