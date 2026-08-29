// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Surface {
    id: root

    required property var tableController

    color: Theme.surfaceMuted
    radius: 0
    border.width: 0

    function eligibleTargetSeat(seat) {
        const data = tableController.gameTableModel.seatData(seat)
        return !!data.displayName && data.eliminated !== true
    }

    function targetSeatLabel(seat) {
        const data = tableController.gameTableModel.seatData(seat)
        return data.displayName ? data.displayName
                                : qsTr("Seat") + " " + (seat + 1)
    }

    function targetPlayer(sourceCardId, seat) {
        if (!sourceCardId || !eligibleTargetSeat(seat))
            return
        tableController.sharedZones.targetPlayer(sourceCardId, seat)
    }

    function sourceHasTarget(sourceCardId) {
        const arrow = tableController.gameTableModel.arrowForSource(sourceCardId)
        return arrow.kind === "target"
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.size(4)
        spacing: 0

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            DropArea {
                id: sharedDropArea
                objectName: "sharedDropArea"
                property var cardSource: null
                anchors.fill: parent
                enabled: root.tableController.canAct
                keys: ["hexproof/card"]

                onEntered: function(drag) {
                    sharedDropArea.cardSource = drag.source
                }
                onExited: sharedDropArea.cardSource = null
                onDropped: function(drop) {
                    root.tableController.cardMoveCommands.finishStackDrop(
                                sharedDropArea, drop)
                }
            }

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: sharedDropArea.containsDrag ? Theme.size(2) : 0
                border.color: Theme.primary
            }

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                visible: sharedGrid.count === 0
                text: qsTr("Stack")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
                font.weight: Font.DemiBold
            }

            ListView {
                id: sharedGrid
                objectName: "sharedCards"
                anchors.fill: parent
                anchors.topMargin: 0
                anchors.bottomMargin: sharedActions.visible
                                      ? sharedActions.height + Theme.size(6) : 0
                orientation: ListView.Vertical
                spacing: -Theme.size(64)
                clip: true
                model: root.tableController.sharedCards
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: sharedCard
                    required property var modelData
                    required property int index
                    readonly property string cardId: modelData.id
                    readonly property string zoneName: modelData.sharedZone
                    readonly property int ownerSeat: modelData.ownerSeat
                    readonly property string ownerDisplayName:
                        modelData.ownerDisplayName
                        ? modelData.ownerDisplayName : qsTr("Player")
                    readonly property int zoneSeat: -1
                    readonly property real revealDividerHeight:
                        modelData.revealDivider === true ? Theme.size(70) : 0
                    objectName: "sharedCard" + index
                    width: ListView.view.width
                    height: Math.round(width * 88 / 63) + revealDividerHeight
                    x: 0
                    z: sharedDrag.drag.active ? 1000 : index
                    visible: root.tableController.pendingBattlefieldMove.cardId
                             !== sharedCard.cardId
                             && !root.tableController.optimisticCommands.isCardPendingFrom(
                                 sharedCard.cardId, sharedCard.zoneName, -1)
                    scale: sharedDrag.drag.active ? 1.045 : 1
                    opacity: sharedDrag.drag.active ? 0.94 : 1
                    onXChanged:
                        root.tableController.battlefieldScene.schedulePointRefresh()
                    onYChanged:
                        root.tableController.battlefieldScene.schedulePointRefresh()
                    onWidthChanged:
                        root.tableController.battlefieldScene.schedulePointRefresh()
                    onHeightChanged:
                        root.tableController.battlefieldScene.schedulePointRefresh()

                    Drag.active: sharedDrag.drag.active
                    Drag.source: sharedCard
                    Drag.keys: ["hexproof/card"]
                    Drag.hotSpot.x: width / 2
                    Drag.hotSpot.y: revealDividerHeight
                                    + (height - revealDividerHeight) / 2

                    states: State {
                        when: sharedCard.Drag.active
                        ParentChange {
                            target: sharedCard
                            parent: root.tableController
                        }
                    }

                    Item {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: sharedCard.revealDividerHeight
                        visible: height > 0

                        RowLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.size(6)

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: Theme.borderStrong
                            }
                            Text {
                                textFormat: Text.PlainText
                                text: sharedCard.modelData.revealDividerLabel
                                      ? sharedCard.modelData.revealDividerLabel
                                      : qsTr("Player")
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSize(9)
                                font.weight: Font.DemiBold
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: Theme.borderStrong
                            }
                        }
                    }

                    Surface {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.topMargin: sharedCard.revealDividerHeight
                        radius: Theme.radiusSmall
                        color: Theme.surfaceHover
                        border.width:
                            root.tableController.selectedSharedCard.id
                            === sharedCard.cardId ? Theme.size(2) : 1
                        border.color:
                            root.tableController.selectedSharedCard.id
                            === sharedCard.cardId
                            ? Theme.primary : Theme.border
                        clip: true

                        Image {
                            id: sharedArt
                            anchors.fill: parent
                            anchors.margins: Theme.size(2)
                            source: root.tableController.presentation.tableCardImageSource(
                                        sharedCard.modelData)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            width: parent.width - Theme.size(8)
                            visible: sharedArt.status !== Image.Ready
                            text: root.tableController.presentation.tableCardPlaceholderName(
                                      sharedCard.modelData)
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSize(8)
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Rectangle {
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.topMargin: Theme.size(22)
                            visible: sharedCard.zoneName === "stack"
                            width: Math.min(
                                       parent.width - Theme.size(6),
                                       sharedOwnerLabel.implicitWidth
                                       + Theme.size(12))
                            height: Theme.size(18)
                            radius: height / 2
                            color: Theme.badgeBackground
                            border.width: 1
                            border.color: Theme.badgeBorder

                            Text {
                                textFormat: Text.PlainText
                                id: sharedOwnerLabel
                                objectName: "sharedCardOwner" + sharedCard.index
                                anchors.fill: parent
                                anchors.leftMargin: Theme.size(6)
                                anchors.rightMargin: Theme.size(6)
                                text: sharedCard.ownerDisplayName
                                color: Theme.text
                                font.pixelSize: Theme.fontSize(8)
                                font.weight: Font.DemiBold
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                        }
                    }

                    MouseArea {
                        id: sharedDrag
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.topMargin: sharedCard.revealDividerHeight
                        hoverEnabled: true
                        cursorShape: drag.active
                                     ? Qt.ClosedHandCursor
                                     : (root.tableController.canAct
                                        && sharedCard.ownerSeat
                                           === root.tableController.roomSession.seatIndex
                                        ? Qt.OpenHandCursor
                                        : Qt.PointingHandCursor)
                        drag.target: root.tableController.canAct
                                     && sharedCard.ownerSeat
                                        === root.tableController.roomSession.seatIndex
                                     ? sharedCard : null
                        drag.threshold: Theme.size(5)
                        preventStealing: true
                        onClicked: root.tableController.sharedZones.selectCard(
                                       sharedCard.modelData,
                                       sharedCard.zoneName)
                        onEntered: root.tableController.presentation.inspectCard(
                                       sharedCard.modelData, sharedCard)
                        onExited: root.tableController.presentation.hideCardPreview(
                                      sharedCard)
                        onPressed: root.tableController.presentation.hideCardPreview()
                        onReleased: {
                            sharedCard.Drag.drop()
                            Qt.callLater(() => sharedGrid.forceLayout())
                        }
                    }

                    Component.onCompleted:
                        root.tableController.battlefieldScene.registerCard(
                            cardId, sharedCard)
                    Component.onDestruction:
                        root.tableController.battlefieldScene.unregisterCard(
                            cardId, sharedCard)
                }
            }

            Grid {
                id: sharedActions
                columns: 2
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.size(3)
                spacing: Theme.size(3)
                visible: root.tableController.selectedSharedOwned
                         && root.tableController.selectedSharedCard.id
                            !== undefined

                AppButton {
                    id: sharedTargetButton
                    objectName: "sharedChooseTargetButton"
                    compact: true
                    implicitWidth: Theme.size(30)
                    implicitHeight: Theme.size(30)
                    visible: root.tableController.selectedSharedZone === "stack"
                    text: "◎"
                    enabled: root.tableController.canAct
                    onClicked: {
                        const position = sharedTargetButton.mapToItem(
                                           root, 0,
                                           sharedTargetButton.height)
                        sharedTargetMenu.sourceCardId =
                            root.tableController.selectedSharedCard.id
                        sharedTargetMenu.x = position.x
                        sharedTargetMenu.y = position.y
                        sharedTargetMenu.open()
                    }
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Choose target")
                }
                AppButton {
                    objectName: "sharedToBattlefieldButton"
                    compact: true
                    implicitWidth: Theme.size(30)
                    implicitHeight: Theme.size(30)
                    text: "↗"
                    enabled: root.tableController.canAct
                    onClicked:
                        root.tableController.cardMoveCommands.moveSelectedSharedCard("battlefield")
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("To battlefield")
                }
                AppButton {
                    objectName: "sharedToGraveyardButton"
                    compact: true
                    implicitWidth: Theme.size(30)
                    implicitHeight: Theme.size(30)
                    text: "†"
                    enabled: root.tableController.canAct
                    onClicked:
                        root.tableController.cardMoveCommands.moveSelectedSharedCard("graveyard")
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("To graveyard")
                }
                AppButton {
                    objectName: "sharedToHandButton"
                    compact: true
                    implicitWidth: Theme.size(30)
                    implicitHeight: Theme.size(30)
                    text: "⌂"
                    enabled: root.tableController.canAct
                    onClicked: root.tableController.cardMoveCommands.moveSelectedSharedCard("hand")
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Back to hand")
                }
            }
        }
    }

    Menu {
        id: sharedTargetMenu
        objectName: "sharedTargetMenu"
        property string sourceCardId: ""

        ConditionalMenuItem {
            objectName: "sharedTargetSeat0Action"
            visible: root.eligibleTargetSeat(0)
            text: qsTr("Target %1").arg(root.targetSeatLabel(0))
            onTriggered: root.targetPlayer(sharedTargetMenu.sourceCardId, 0)
        }
        ConditionalMenuItem {
            objectName: "sharedTargetSeat1Action"
            visible: root.eligibleTargetSeat(1)
            text: qsTr("Target %1").arg(root.targetSeatLabel(1))
            onTriggered: root.targetPlayer(sharedTargetMenu.sourceCardId, 1)
        }
        ConditionalMenuItem {
            objectName: "sharedTargetSeat2Action"
            visible: root.eligibleTargetSeat(2)
            text: qsTr("Target %1").arg(root.targetSeatLabel(2))
            onTriggered: root.targetPlayer(sharedTargetMenu.sourceCardId, 2)
        }
        ConditionalMenuItem {
            objectName: "sharedTargetSeat3Action"
            visible: root.eligibleTargetSeat(3)
            text: qsTr("Target %1").arg(root.targetSeatLabel(3))
            onTriggered: root.targetPlayer(sharedTargetMenu.sourceCardId, 3)
        }
        MenuSeparator { }
        MenuItem {
            objectName: "sharedTargetBattlefieldCardAction"
            text: qsTr("Target a battlefield card…")
            onTriggered: {
                root.tableController.selection.beginRelationTargetForSources(
                            "arrow", [sharedTargetMenu.sourceCardId])
                root.tableController.sharedZones.clearSelection()
            }
        }
        MenuItem {
            objectName: "clearSharedTargetAction"
            text: qsTr("Clear target")
            enabled: root.sourceHasTarget(sharedTargetMenu.sourceCardId)
            onTriggered: {
                root.tableController.sharedZones.clearTarget(
                            sharedTargetMenu.sourceCardId)
            }
        }
    }
}
