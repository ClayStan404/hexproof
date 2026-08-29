// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "Table"

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property var tableController
    readonly property var cards:
        root.tableController.zoneState.zoneCardsForSeat(
            root.tableController.roomSession.seatIndex,
            "command")
    readonly property var topCard:
        cards.length > 0 ? cards[0] : ({})
    visible: root.tableController.isCommanderFormat
    Layout.fillWidth: visible
    Layout.fillHeight: true
    Layout.minimumWidth:
        visible ? Theme.size(54) : 0

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusMedium
        color: "transparent"
        clip: true
        border.width:
            ownCommandDrop.containsDrag
            ? 2
            : (ownCommanderMouse.containsMouse
               ? 1 : 0)
        border.color:
            ownCommandDrop.containsDrag
            || ownCommanderMouse.containsMouse
            ? Theme.primary
            : Theme.borderStrong

        Image {
            id: ownCommanderPrimaryArt
            objectName:
                "ownCommanderCard"
                + root.tableController.roomSession.seatIndex
            width:
                parent.width
                * (root.cards.length
                   > 1 ? 0.72 : 1)
            height: parent.height
            visible:
                !!root.topCard.name
            source:
                root.tableController.presentation.tableCardImageSource(
                    root.topCard)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
        }
        Image {
            objectName:
                "ownCommanderCard"
                + root.tableController.roomSession.seatIndex + "-1"
            x: parent.width * 0.28
            width: parent.width * 0.72
            height: parent.height
            z: 1
            visible:
                root.cards.length
                > 1
            source:
                visible
                ? root.tableController.presentation.tableCardImageSource(
                      root.cards[1])
                : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
        }
        Rectangle {
            anchors.fill:
                ownCommanderPrimaryArt
            z: 2
            visible:
                !!root.topCard.name
                && ownCommanderPrimaryArt.status
                   !== Image.Ready
            color: Theme.surfaceMuted

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                width:
                    parent.width
                    - Theme.size(8)
                text:
                    root.topCard.name
                    ? root.topCard.name
                    : qsTr("Commander")
                color: Theme.textSecondary
                font.pixelSize:
                    Theme.fontSize(8)
                wrapMode: Text.WordWrap
                horizontalAlignment:
                    Text.AlignHCenter
            }
        }
        Rectangle {
            id: ownCommanderEmptyFrame
            anchors.centerIn: parent
            width: Math.min(
                       parent.width
                       - Theme.size(10),
                       (parent.height
                        - Theme.size(10))
                       * 63 / 88)
            height: width * 88 / 63
            visible:
                !root.topCard.name
            color: "transparent"
            radius: Theme.radiusSmall
            border.width: 1
            border.color: Theme.border
        }
        Rectangle {
            objectName:
                "commanderZoneBadge"
                + root.tableController.roomSession.seatIndex
            readonly property real cardVisualBottom:
                ownCommanderPrimaryArt.paintedHeight > 0
                ? ownCommanderPrimaryArt.y
                  + (ownCommanderPrimaryArt.height
                     + ownCommanderPrimaryArt.paintedHeight) / 2
                : ownCommanderEmptyFrame.y
                  + ownCommanderEmptyFrame.height
            anchors.horizontalCenter:
                parent.horizontalCenter
            y: Math.max(
                   Theme.size(4),
                   cardVisualBottom - height - Theme.size(4))
            width: Math.min(
                       parent.width
                       - Theme.size(4),
                       ownCommanderLabel.implicitWidth
                       + Theme.size(12))
            height: Theme.size(22)
            z: 4
            radius: height / 2
            color: Theme.badgeBackground
            border.width: 1
            border.color: Theme.badgeBorder
            Text {
                textFormat: Text.PlainText
                id: ownCommanderLabel
                objectName:
                    "commanderZoneLabel"
                    + root.tableController.roomSession.seatIndex
                anchors.centerIn: parent
                text:
                    qsTr("Command")
                    + " "
                    + root.tableController.zoneState.zoneCardCount(
                        root.tableController.roomSession.seatIndex,
                        "command")
                color: Theme.text
                font.pixelSize: Theme.fontSize(9)
                font.weight: Font.DemiBold
                horizontalAlignment:
                    Text.AlignHCenter
            }
        }
    }
    DropArea {
        id: ownCommandDrop
        objectName: "commandDropArea"
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
                        ownCommandDrop, drop,
                        "command",
                        root.tableController.roomSession.seatIndex)
        }
    }
    Item {
        id: ownCommanderDragCard
        objectName: "commanderDragCard"
                    + root.tableController.roomSession.seatIndex
        readonly property string cardId:
            modelData.id ? modelData.id : ""
        readonly property string zoneName:
            "command"
        readonly property int ownerSeat:
            root.tableController.roomSession.seatIndex
        readonly property int zoneSeat:
            root.tableController.roomSession.seatIndex
        property var modelData:
            ownCommanderMouse.selectedCard.id
            ? ownCommanderMouse.selectedCard
            : root.topCard
        width: Theme.size(64)
        height: Theme.size(90)
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        visible: ownCommanderMouse.drag.active
        z: 120
        Drag.active:
            ownCommanderMouse.drag.active
        Drag.source: ownCommanderDragCard
        Drag.keys: ["hexproof/card"]
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2
        states: State {
            when: ownCommanderDragCard.Drag.active
            ParentChange {
                target: ownCommanderDragCard
                parent: root.tableController
            }
        }
        Image {
            anchors.fill: parent
            source: root.tableController.presentation.tableCardImageSource(
                        ownCommanderDragCard.modelData)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
        }
    }
    MouseArea {
        id: ownCommanderMouse
        objectName: "commandZoneButton"
                    + root.tableController.roomSession.seatIndex
        property var selectedCard: ({})
        property bool completedDrag: false
        anchors.fill: parent
        z: 3
        enabled: root.tableController.isCommanderFormat
        hoverEnabled: true
        cursorShape:
            drag.active
            ? Qt.ClosedHandCursor
            : (root.tableController.canAct
               && root.topCard.id
               ? Qt.OpenHandCursor
               : Qt.PointingHandCursor)
        drag.target:
            root.tableController.canAct
            && root.topCard.id
            ? ownCommanderDragCard : null
        drag.threshold: Theme.size(5)
        preventStealing: true
        function cardAt(positionX) {
            if (root.cards.length
                > 1
                && positionX
                   >= root.width
                      * 0.28) {
                return root.cards[1]
            }
            return root.topCard
        }
        function resetDragCard() {
            Qt.callLater(function() {
                ownCommanderDragCard.x =
                    (root.width
                     - ownCommanderDragCard.width) / 2
                ownCommanderDragCard.y =
                    (root.height
                     - ownCommanderDragCard.height) / 2
                selectedCard = ({})
            })
        }
        onEntered: root.tableController.presentation.inspectCard(
                       cardAt(mouseX),
                       root)
        onPositionChanged: function(mouse) {
            if (drag.active) {
                completedDrag = true
            } else {
                root.tableController.presentation.inspectCard(
                    cardAt(mouse.x),
                    root)
            }
        }
        onExited: root.tableController.presentation.hideCardPreview(root)
        onPressed: function(mouse) {
            completedDrag = false
            selectedCard = Object.assign(
                {}, cardAt(mouse.x))
            root.tableController.presentation.hideCardPreview()
        }
        onReleased: {
            // MouseArea.drag.active may already be cleared
            // when release is delivered. Calling drop()
            // unconditionally still completes an attached
            // drag and is a no-op for an ordinary click.
            ownCommanderDragCard.Drag.drop()
            resetDragCard()
        }
        onCanceled: resetDragCard()
        onClicked: {
            if (!completedDrag) {
                root.tableController.publicZoneBrowser.showZone(
                    root.tableController.ownSeatData.displayName,
                    root.tableController.roomSession.seatIndex,
                    "command")
            }
        }
    }
}
