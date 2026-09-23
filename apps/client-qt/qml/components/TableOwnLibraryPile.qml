// SPDX-License-Identifier: GPL-3.0-or-later
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
    readonly property var topCard: root.tableController.ownSeatData.libraryTopCard || ({})
    readonly property string topImage: topCard.name
        ? root.tableController.presentation.tableCardImageSource(topCard) : ""

    function refreshTopCardPreview() {
        if (emptyLibraryHover.hovered && root.topCard.name
                && !root.tableController.tableModalOpen)
            root.tableController.presentation.inspectCard(root.topCard, root)
        else root.tableController.presentation.hideCardPreview(root)
    }
    onTopCardChanged: refreshTopCardPreview()

    HoverHandler {
        id: emptyLibraryHover
        onHoveredChanged: root.refreshTopCardPreview()
    }
    ToolTip.visible: emptyLibraryHover.hovered
                     && !ownLibraryDrag.drag.active
                     && !root.tableController.tableModalOpen
    ToolTip.delay: 600
    ToolTip.text: root.tableController.rulesAssist.emptyLibrary(
                      root.tableController.ownSeatData)
                  ? qsTranslate("Table", "Library empty. Attempting to draw may cause a loss unless a card effect says otherwise.")
                  : qsTranslate("Table", "Drag the top card to a zone. Hold Shift while dragging to exile to keep it face down; no player may look. Right-click for more actions.")

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
            source: root.topImage || root.tableController.cardBackSource
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
            width: Math.min(parent.width - Theme.size(4),
                            ownLibraryLabel.implicitWidth + Theme.size(14))
            height: Theme.size(22)
            radius: height / 2
            color: Theme.badgeBackground
            border.width: 1
            border.color: Theme.badgeBorder
            Text {
                textFormat: Text.PlainText
                id: ownLibraryLabel
                anchors.centerIn: parent
                width: parent.width - Theme.size(8)
                fontSizeMode: Text.Fit
                minimumPixelSize: Theme.fontSize(6)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                text: qsTranslate("Table", "Library") + " "
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
        objectName: "ownLibraryDragCard"
        property bool faceDownRequested: false
        property point dragGrabPosition: Qt.point(width / 2, height / 2)
        readonly property string cardId:
            "__library_top__"
        readonly property string zoneName: "library"
        readonly property int ownerSeat:
            root.tableController.roomSession.seatIndex
        readonly property int zoneSeat:
            root.tableController.roomSession.seatIndex
        property var modelData: root.topCard
        width: Theme.size(64)
        height: Theme.size(90)
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        visible: ownLibraryDrag.drag.active
        z: 120
        Drag.active: ownLibraryDrag.drag.active
        Drag.source: ownLibraryDragCard
        Drag.keys: ["hexproof/card"]
        Drag.hotSpot.x: dragGrabPosition.x
        Drag.hotSpot.y: dragGrabPosition.y
        states: State {
            when: ownLibraryDragCard.Drag.active
            ParentChange {
                target: ownLibraryDragCard
                parent: root.tableController
            }
        }
        Image {
            anchors.fill: parent
            source: root.topImage || root.tableController.cardBackSource
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
        hoverEnabled: true
        cursorShape: drag.active
                     ? Qt.ClosedHandCursor
                     : Qt.OpenHandCursor
        drag.target: root.tableController.ownSeatData.libraryCount > 0
                     ? ownLibraryDragCard : null
        drag.threshold: Theme.size(5)
        drag.smoothed: false
        preventStealing: true
        onPressed: function(mouse) {
            ownLibraryDragCard.dragGrabPosition = root.mapToItem(
                ownLibraryDragCard, mouse.x, mouse.y)
            ownLibraryDragCard.faceDownRequested =
                (mouse.modifiers & Qt.ShiftModifier) !== 0
        }
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
        onReleased: function(mouse) {
            // drop() emits the DropArea event.
            // Do not gate it on MouseArea.drag.active:
            // Qt may clear that state as release is
            // delivered even though the attached
            // drag still has a valid target.
            ownLibraryDragCard.faceDownRequested =
                (mouse.modifiers & Qt.ShiftModifier) !== 0
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
