// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "Table"

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property var tableController
    required property string zoneKey

    readonly property var topCard:
        tableController.zoneState.displayedPublicZoneTopCard(
            tableController.roomSession.seatIndex, zoneKey)
    readonly property string zoneTitle:
        zoneKey === "graveyard" ? qsTr("Graveyard") : qsTr("Exile")

    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumWidth: Theme.size(54)

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusMedium
        color: "transparent"
        clip: true
        border.width: zoneDrop.containsDrag
                      ? 2 : (zoneDrag.containsMouse ? 1 : 0)
        border.color: zoneDrop.containsDrag || zoneDrag.containsMouse
                      ? Theme.primary : Theme.borderStrong

        Image {
            anchors.fill: parent
            visible: !!root.topCard.id
            source: root.tableController.presentation.tableCardImageSource(
                        root.topCard)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - Theme.size(10),
                            (parent.height - Theme.size(10)) * 63 / 88)
            height: width * 88 / 63
            visible: !root.topCard.id
            color: "transparent"
            radius: Theme.radiusSmall
            border.width: 1
            border.color: Theme.border
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.size(4)
            width: zoneLabel.implicitWidth + Theme.size(14)
            height: Theme.size(22)
            radius: height / 2
            color: Theme.badgeBackground
            border.width: 1
            border.color: Theme.badgeBorder

            Text {
                textFormat: Text.PlainText
                id: zoneLabel
                anchors.centerIn: parent
                text: root.zoneTitle + " "
                      + root.tableController.zoneState.zoneCardCount(
                          root.tableController.roomSession.seatIndex,
                          root.zoneKey)
                color: Theme.text
                font.pixelSize: Theme.fontSize(10)
                font.weight: Font.DemiBold
            }
        }
    }

    DropArea {
        id: zoneDrop
        objectName: root.zoneKey + "DropArea"
                    + root.tableController.roomSession.seatIndex
        property var cardSource: null
        anchors.fill: parent
        z: 2
        enabled: root.tableController.canAct
        keys: ["hexproof/card"]
        onEntered: function(drag) {
            cardSource = drag.source
        }
        onExited: cardSource = null
        onDropped: function(drop) {
            root.tableController.cardMoveCommands.finishPublicZoneDrop(
                zoneDrop, drop, root.zoneKey,
                root.tableController.roomSession.seatIndex)
        }
    }

    Item {
        id: zoneDragCard
        objectName: root.zoneKey + "DragCard"
                    + root.tableController.roomSession.seatIndex
        readonly property string cardId:
            root.topCard.id ? root.topCard.id : ""
        readonly property string zoneName: root.zoneKey
        readonly property int ownerSeat:
            root.tableController.roomSession.seatIndex
        readonly property int zoneSeat:
            root.tableController.roomSession.seatIndex
        property var modelData: root.topCard
        width: Theme.size(64)
        height: Theme.size(90)
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        visible: zoneDrag.drag.active
        z: 120
        Drag.active: zoneDrag.drag.active
        Drag.source: zoneDragCard
        Drag.keys: ["hexproof/card"]
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2
        states: State {
            when: zoneDragCard.Drag.active
            ParentChange {
                target: zoneDragCard
                parent: root.tableController
            }
        }

        Image {
            anchors.fill: parent
            source: root.tableController.presentation.tableCardImageSource(
                        root.topCard)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
    }

    MouseArea {
        id: zoneDrag
        objectName: root.zoneKey + "BrowserButton"
                    + root.tableController.roomSession.seatIndex
        anchors.fill: parent
        z: 3
        enabled: root.tableController.canAct
        hoverEnabled: true
        cursorShape: drag.active
                     ? Qt.ClosedHandCursor
                     : (root.topCard.id
                        ? Qt.OpenHandCursor : Qt.PointingHandCursor)
        drag.target: root.topCard.id ? zoneDragCard : null
        drag.threshold: Theme.size(5)
        preventStealing: true
        onEntered: root.tableController.presentation.inspectCard(
                       root.topCard, root)
        onExited: root.tableController.presentation.hideCardPreview(root)
        onClicked: root.tableController.publicZoneBrowser.showZone(
                       root.tableController.ownSeatData.displayName,
                       root.tableController.roomSession.seatIndex,
                       root.zoneKey)
        onReleased: {
            // MouseArea.drag.active may already be clear when release is
            // delivered. Calling drop() is harmless for an ordinary click and
            // preserves graveyard/exile drops that reached a DropArea.
            zoneDragCard.Drag.drop()
            Qt.callLater(function() {
                zoneDragCard.x = (root.width - zoneDragCard.width) / 2
                zoneDragCard.y = (root.height - zoneDragCard.height) / 2
            })
        }
    }
}
