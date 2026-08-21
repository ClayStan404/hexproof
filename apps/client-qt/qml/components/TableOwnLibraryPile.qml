// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "Table"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    required property var tableController
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumWidth: Theme.size(54)
    readonly property var topCard: ({})

    HoverHandler { id: emptyLibraryHover }
    ToolTip.visible: emptyLibraryHover.hovered
                     && root.tableController.rulesAssist.emptyLibrary(
                         root.tableController.ownSeatData)
    ToolTip.text: qsTr("Library empty. Attempting to draw may cause a loss unless a card effect says otherwise.")

    Action {
        id: ownLibraryDrawAction
        objectName: "drawCardButton"
                    + root.tableController.roomSession.seatIndex
        enabled: root.tableController.canAct
                 && !root.tableController.tableModalOpen
                 && root.tableController.ownSeatData.libraryCount > 0
        // Drawing is intentionally explicit through Draw X.
        onTriggered: root.tableController.wsModel.drawCards(1)
    }
    Action {
        id: ownLibrarySearchAction
        objectName: "searchLibraryButton"
                    + root.tableController.roomSession.seatIndex
        enabled: root.tableController.canAct
                 && root.tableController.ownSeatData.libraryCount > 0
        onTriggered: root.tableController.wsModel.dumpLibrary(
                         root.tableController.roomSession.seatIndex)
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusMedium
        color: "transparent"
        border.width:
            ownLibraryDrag.containsMouse ? 1 : 0
        border.color: ownLibraryDrag.containsMouse
                      ? Theme.primary
                      : Theme.borderStrong

        Image {
            id: ownLibraryCardBack
            objectName: "ownLibraryCardBack"
            anchors.centerIn: parent
            width: Math.min(
                       parent.width,
                       parent.height * 63 / 88)
            height: width * 88 / 63
            visible: root.tableController.ownSeatData.libraryCount > 0
            source: root.tableController.cardBackSource
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
        }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(
                       parent.width
                       - Theme.size(10),
                       (parent.height
                        - Theme.size(10))
                       * 63 / 88)
            height: width * 88 / 63
            visible: root.tableController.ownSeatData.libraryCount <= 0
            color: "transparent"
            radius: Theme.radiusSmall
            border.width: 1
            border.color: root.tableController.rulesAssist.emptyLibrary(
                              root.tableController.ownSeatData)
                          ? Theme.warning : Theme.border
        }
        Rectangle {
            anchors.horizontalCenter:
                parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.size(4)
            width: ownLibraryLabel.implicitWidth
                   + Theme.size(14)
            height: Theme.size(22)
            radius: height / 2
            color: Theme.badgeBackground
            border.width: 1
            border.color: Theme.badgeBorder
            Text {
                textFormat: Text.PlainText
                id: ownLibraryLabel
                anchors.centerIn: parent
                text: qsTr("Library") + " "
                      + root.tableController.ownSeatData.libraryCount
                color: root.tableController.rulesAssist.emptyLibrary(
                           root.tableController.ownSeatData)
                       ? Theme.warning : Theme.text
                font.pixelSize:
                    Theme.fontSize(10)
                font.weight: Font.DemiBold
            }
        }
    }
    Item {
        id: ownLibraryDragCard
        readonly property string cardId:
            "__library_top__"
        readonly property string zoneName: "library"
        readonly property int ownerSeat:
            root.tableController.roomSession.seatIndex
        readonly property int zoneSeat:
            root.tableController.roomSession.seatIndex
        property var modelData: ({})
        width: Theme.size(64)
        height: Theme.size(90)
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        visible: ownLibraryDrag.drag.active
        z: 120
        Drag.active: ownLibraryDrag.drag.active
        Drag.source: ownLibraryDragCard
        Drag.keys: ["hexproof/card"]
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2
        states: State {
            when: ownLibraryDragCard.Drag.active
            ParentChange {
                target: ownLibraryDragCard
                parent: root.tableController
            }
        }
        Image {
            anchors.fill: parent
            source: root.tableController.cardBackSource
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
        }
    }
    DropArea {
        id: ownLibraryDrop
        objectName: "libraryDropArea"
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
            root.tableController.cardMoveCommands.finishLibraryDrop(
                        ownLibraryDrop, drop)
        }
    }
    MouseArea {
        id: ownLibraryDrag
        objectName: "ownLibraryZone"
        anchors.fill: parent
        z: 3
        acceptedButtons:
            Qt.LeftButton | Qt.RightButton
        enabled: root.tableController.canAct
                 && !root.tableController.tableModalOpen
                 && root.tableController.ownSeatData.libraryCount > 0
        hoverEnabled: true
        cursorShape: drag.active
                     ? Qt.ClosedHandCursor
                     : Qt.OpenHandCursor
        drag.target: ownLibraryDragCard
        drag.threshold: Theme.size(5)
        preventStealing: true
        onClicked: function(mouse) {
            if (mouse.button !== Qt.RightButton)
                return
            const position =
                root.mapToItem(
                    root.tableController, mouse.x, mouse.y)
            root.tableController.ownLibraryMenu.x = position.x
            root.tableController.ownLibraryMenu.y = position.y
            root.tableController.ownLibraryMenu.open()
        }
        onReleased: {
            // drop() emits the DropArea event.
            // Do not gate it on MouseArea.drag.active:
            // Qt may clear that state as release is
            // delivered even though the attached
            // drag still has a valid target.
            ownLibraryDragCard.Drag.drop()
            Qt.callLater(function() {
                ownLibraryDragCard.x =
                    (root.width
                     - ownLibraryDragCard.width) / 2
                ownLibraryDragCard.y =
                    (root.height
                     - ownLibraryDragCard.height) / 2
            })
        }
    }
}
