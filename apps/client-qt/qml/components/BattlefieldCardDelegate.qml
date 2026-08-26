// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "BattlefieldView"

import QtQuick
import QtQuick.Controls.Basic

Item {
    id: root

    required property var tableController
    required property var cardMenu
    required property var seatData
    required property bool isOwn
    required property var zoneArea
    required property string playerAttackTargetName
    required property var cardData
    required property string cardId
    required property int ownerSeat
    required property bool hasPosition
    required property real positionX
    required property real positionY
    required property var counters
    readonly property var modelData:
        cardData
    readonly property int cardOwnerSeat:
        ownerSeat >= 0
        ? ownerSeat
        : root.seatData.seat
    readonly property var cardCounters:
        counters ? counters : []
    readonly property bool hiddenAsCrossLaneAttachment: {
        void root.tableController.tableAttachments
        return !!(root.tableController.attachmentUi
                  && root.tableController.attachmentUi.hidesHomeLaneCard(
                         cardId, root.seatData.seat))
    }
    objectName: "battlefieldCard" + cardId
    // Hidden delegates are already skipped by focus
    // traversal. Keep this constant so a focused card
    // is never switched to activeFocusOnTab=false while
    // an optimistic move hides it.
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: modelData.name
                     ? modelData.name
                     : qsTr("Card")
    visible:
        root.tableController.pendingBattlefieldMove.cardId
        !== cardId
        && !root.tableController.optimisticCommands.isCardPendingFrom(
            cardId,
            "battlefield",
            root.seatData.seat)
        && !hiddenAsCrossLaneAttachment
    width: root.tableController.battlefieldCardWidth
    height: root.tableController.battlefieldCardHeight
    x: Math.max(0, Math.min(
                    root.zoneArea.width - width,
                    (hasPosition
                     ? positionX : 0.08)
                    * Math.max(
                        0,
                        root.zoneArea.width - width)))
    y: Math.max(0, Math.min(
                    root.zoneArea.height - height,
                    root.tableController.battlefieldLayout.yForView(
                        root.seatData.seat,
                        hasPosition
                        ? positionY
                        : undefined,
                        0.18)
                    * Math.max(
                        0,
                        root.zoneArea.height - height)))
    z: battlefieldDrag.drag.active
       ? 100
       : (root.tableController.cardMoveCommands
          .battlefieldCardNeedsPriority(
              root.modelData,
              root.seatData.seat)
          ? 10 : 0)
    onXChanged:
        root.tableController.battlefieldScene.schedulePointRefresh()
    onYChanged:
        root.tableController.battlefieldScene.schedulePointRefresh()
    onWidthChanged:
        root.tableController.battlefieldScene.schedulePointRefresh()
    onHeightChanged:
        root.tableController.battlefieldScene.schedulePointRefresh()
    onVisibleChanged:
        root.tableController.battlefieldScene.schedulePointRefresh()

    function openCardMenu(localX, localY) {
        root.tableController.suppressBattlefieldAreaMenu = true
        root.tableController.selectedHandCard = ({})
        root.tableController.selection.selectCardForMenu(
            root.modelData,
            root.seatData.seat)
        const position = battlefieldDragCard.mapToItem(
            root.tableController, localX, localY)
        root.cardMenu.x = position.x
        root.cardMenu.y = position.y
        root.cardMenu.open()
        Qt.callLater(function() {
            root.tableController.suppressBattlefieldAreaMenu = false
        })
    }

    Keys.onPressed: function(event) {
        if (event.key !== Qt.Key_Return
                && event.key !== Qt.Key_Enter
                && event.key !== Qt.Key_Menu) {
            return
        }
        root.openCardMenu(width / 2, height / 2)
        event.accepted = true
    }

    Item {
        id: battlefieldDragCard
        readonly property string cardId:
            root.modelData.id
        readonly property string zoneName:
            "battlefield"
        readonly property int ownerSeat:
            root.cardOwnerSeat
        readonly property int zoneSeat:
            root.seatData.seat
        property var modelData:
            root.modelData
        width: root.width
        height: root.height
        z: battlefieldDrag.drag.active
           ? 2000 : 0
        scale: battlefieldDrag.drag.active
               ? 1.045 : 1
        opacity: battlefieldDrag.drag.active
                 ? 0.94 : 1
        rotation:
            root.tableController.gameValues.displayedTapped(
                root.modelData)
            ? 90 : 0

        Drag.active: battlefieldDrag.drag.active
        Drag.source: battlefieldDragCard
        Drag.keys: ["hexproof/card"]
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2

        states: State {
            when: battlefieldDragCard.Drag.active
            ParentChange {
                target: battlefieldDragCard
                parent: root.tableController
            }
        }

        Behavior on x {
            enabled: !battlefieldDrag.drag.active
            NumberAnimation {
                duration: Theme.motionNormal
                easing.type: Easing.OutCubic
            }
        }
        Behavior on y {
            enabled: !battlefieldDrag.drag.active
            NumberAnimation {
                duration: Theme.motionNormal
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Theme.motionFast
                easing.type: Easing.OutCubic
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.motionFast
            }
        }
        Behavior on rotation {
            NumberAnimation {
                duration: Theme.motionNormal
                easing.type: Easing.InOutCubic
            }
        }
        Rectangle {
            anchors.fill: parent
            z: 20
            color: "transparent"
            radius: Theme.radiusSmall
            border.width: root.activeFocus
                          ? Theme.size(2) : 0
            border.color: Theme.primary
        }

        Item {
            anchors.fill: parent
            clip: true

            Image {
                id: battlefieldArt
                anchors.fill: parent
                source:
                    root.tableController.presentation.tableCardImageSource(
                        root.modelData)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }
            Rectangle {
                anchors.fill: parent
                visible: battlefieldArt.status
                         !== Image.Ready
                color: Theme.surfaceElevated
                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    width: parent.width
                           - Theme.size(10)
                    text: root.tableController.presentation.tableCardPlaceholderName(
                              root.modelData)
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(9)
                    wrapMode: Text.WordWrap
                    horizontalAlignment:
                        Text.AlignHCenter
                }
            }
            Rectangle {
                anchors.fill: parent
                visible:
                    root.tableController.selection.cardSelected(
                        root.modelData.id)
                color: "transparent"
                border.width: Theme.size(3)
                border.color: Theme.primary
            }
        }
        Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: Theme.size(5)
            width: Theme.size(27)
            height: width
            radius: width / 2
            visible:
                root.tableController.cardActions.numberCounterValue(
                    root.cardCounters) > 0
            color: Theme.accent
            border.width: 1
            border.color: Theme.primaryInk
            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: String(
                    root.tableController.cardActions.numberCounterValue(
                        root.cardCounters))
                color: Theme.primaryInk
                font.pixelSize:
                    Theme.fontSize(10)
                font.weight: Font.Bold
            }
        }
        StatusPill {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.size(5)
            visible: root.modelData.token === true
            text: qsTr("Token")
            statusColor: Theme.warning
        }
        Rectangle {
            objectName:
                "battlefieldCommanderBadge"
                + root.modelData.id
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins:
                Theme.size(5)
            width: Theme.size(22)
            height: width
            radius: width / 2
            z: 6
            visible:
                root.modelData.commander
                === true
            color: "#E8C477F2"
            border.width: 1
            border.color: "#FFF4D6"
            Text {
                textFormat: Text.PlainText
                anchors.centerIn:
                    parent
                text: "♛"
                color:
                    Theme.primaryInk
                font.pixelSize:
                    Theme.fontSize(11)
                font.weight: Font.Bold
            }
            HoverHandler {
                id: commanderBadgeHover
            }
            ToolTip.visible:
                commanderBadgeHover.hovered
            ToolTip.text:
                qsTr("Commander")
        }
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.leftMargin:
                Theme.size(5)
            anchors.topMargin:
                Theme.size(5)
                + (root.modelData.commander
                   === true
                   ? Theme.size(26)
                   : 0)
            width: Theme.size(22)
            height: width
            radius: width / 2
            z: 30
            visible:
                root.tableController.cardActions.abilityCounters(
                    root.cardCounters).length
                > 0
            color: "#F2B84BEF"
            border.width: 1
            border.color: "#FFF4D6"
            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "◆"
                color: "#201506"
                font.pixelSize:
                    Theme.fontSize(10)
                font.weight: Font.Bold
            }
            HoverHandler {
                id: abilityBadgeHover
            }
            ToolTip.visible:
                abilityBadgeHover.hovered
            ToolTip.delay: 250
            ToolTip.text:
                root.tableController.cardActions.abilityCounterSummary(
                    root.cardCounters)
        }
        Rectangle {
            id: ownerBadge
            objectName:
                "battlefieldOwnerBadge"
                + root.modelData.id
            readonly property string toolTipText:
                qsTr("Owner") + " · "
                + root.tableController.sharedZones.displayNameForSeat(
                    root.cardOwnerSeat)
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Theme.size(5)
            width: Theme.size(22)
            height: width
            radius: width / 2
            z: 5
            visible:
                root.cardOwnerSeat
                !== root.seatData.seat
            color: "#287CEAF2"
            border.width: 1
            border.color: "#DCEBFF"
            Text {
                textFormat: Text.PlainText
                objectName:
                    "battlefieldOwnerGlyph"
                    + root.modelData.id
                anchors.centerIn: parent
                text: "◇"
                color: "white"
                font.pixelSize:
                    Theme.fontSize(13)
                font.weight: Font.Bold
            }
            HoverHandler {
                id: ownerBadgeHover
            }
            ToolTip.visible:
                ownerBadgeHover.hovered
            ToolTip.text:
                ownerBadge.toolTipText
        }
        MouseArea {
            id: battlefieldDrag
            objectName:
                "battlefieldDrag"
                + root.modelData.id
            anchors.fill: parent
            enabled:
                !root.tableController.tableModalOpen
            hoverEnabled: true
            cursorShape:
                drag.active
                ? Qt.ClosedHandCursor
                : (root.tableController.cardMoveCommands.canDragBattlefieldCard(
                       battlefieldDragCard)
                   ? Qt.OpenHandCursor
                   : Qt.PointingHandCursor)
            drag.target:
                root.tableController.cardMoveCommands.canDragBattlefieldCard(
                    battlefieldDragCard)
                ? battlefieldDragCard : null
            drag.threshold: Theme.size(5)
            preventStealing: true
            onEntered:
                root.tableController.presentation.inspectCard(
                    root.modelData,
                    battlefieldDragCard)
            onExited:
                root.tableController.presentation.hideCardPreview(
                    battlefieldDragCard)
            onPressed: {
                root.tableController.presentation.hideCardPreview()
                if (root.tableController.cardMoveCommands.canDragBattlefieldCard(
                        battlefieldDragCard)) {
                    root.tableController.activeBattlefieldDragCardId =
                        battlefieldDragCard.cardId
                }
            }
            onClicked: function(mouse) {
                root.tableController.selectedHandCard = ({})
                root.tableController.selection.selectCard(
                    root.modelData,
                    root.seatData.seat,
                    (mouse.modifiers
                     & Qt.ControlModifier)
                    || (mouse.modifiers
                        & Qt.ShiftModifier))
            }
            onDoubleClicked: {
                if (root.tableController.canAct
                    && root.isOwn) {
                    root.tableController.gameValues.toggleTapped(
                        root.modelData)
                }
            }
            onReleased: {
                if (root.tableController.cardMoveCommands.canDragBattlefieldCard(
                        battlefieldDragCard)) {
                    battlefieldDragCard.Drag.drop()
                    Qt.callLater(() => {
                        battlefieldDragCard.x = 0
                        battlefieldDragCard.y = 0
                        root.tableController.projectionSync.finishBattlefieldDrag()
                    })
                } else {
                    root.tableController.projectionSync.finishBattlefieldDrag()
                }
            }
            onCanceled:
                root.tableController.projectionSync.finishBattlefieldDrag()
        }
        TapHandler {
            acceptedButtons:
                Qt.RightButton
            enabled:
                !root.tableController.tableModalOpen
            onTapped: function(point) {
                root.openCardMenu(
                    point.position.x, point.position.y)
            }
        }
    }
    Rectangle {
        id: playerAttackBadge
        objectName: "playerAttackBadge"
                    + root.cardId
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.size(5)
        width: Math.min(
                   parent.width - Theme.size(8),
                   playerAttackLabel.implicitWidth
                   + Theme.size(14))
        height: Theme.size(20)
        radius: height / 2
        z: 300
        visible:
            root.playerAttackTargetName.length
            > 0
        color: Qt.rgba(
                   Theme.error.r,
                   Theme.error.g,
                   Theme.error.b, 0.90)
        border.width: 1
        border.color: Theme.text

        Text {
            textFormat: Text.PlainText
            id: playerAttackLabel
            objectName: "playerAttackLabel"
                        + root.cardId
            anchors.fill: parent
            anchors.leftMargin: Theme.size(5)
            anchors.rightMargin: Theme.size(5)
            text: qsTr("Attacking %1").arg(
                      root.playerAttackTargetName)
            color: "white"
            font.pixelSize: Theme.fontSize(8)
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        HoverHandler {
            id: playerAttackBadgeHover
        }
        ToolTip.visible:
            playerAttackBadgeHover.hovered
        ToolTip.text: playerAttackLabel.text
    }
    Component.onCompleted:
        root.tableController.battlefieldScene.registerCard(
            cardId, root)
    Component.onDestruction:
        root.tableController.battlefieldScene.unregisterCard(
            cardId, root)
}
