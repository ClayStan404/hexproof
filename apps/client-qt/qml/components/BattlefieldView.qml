// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Surface {
    id: root

    required property var tableController
    required property var areaMenu
    required property var cardMenu
    required property var publicZoneBrowserPopup
    color: Theme.surfaceMuted
    radius: 0
    border.width: 0

    function playerAttackTargetName(sourceCardId) {
        const relations = root.tableController.tableArrows
                          ? root.tableController.tableArrows : []
        for (let index = 0; index < relations.length; ++index) {
            const relation = relations[index]
            if (relation.sourceCardId !== sourceCardId
                    || relation.kind !== "attack"
                    || relation.targetCardId
                    || relation.targetSeat === undefined
                    || relation.targetSeat === null
                    || relation.targetSeat < 0) {
                continue
            }
            const target = root.tableController.gameTableModel.seatData(
                               relation.targetSeat)
            return target.displayName ? target.displayName
                                      : qsTr("Seat") + " "
                                        + (relation.targetSeat + 1)
        }
        return ""
    }

    ColumnLayout {
        id: battlefieldArea
        objectName: "battlefieldArea"
        anchors.fill: parent
        anchors.margins: Theme.size(4)
        spacing: Theme.size(3)

        RowLayout {
            Layout.fillWidth: true
            visible: root.tableController.battlefieldInteractionMode.length > 0
            Layout.preferredHeight: visible ? implicitHeight : 0
            spacing: Theme.size(8)

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.tableController.battlefieldInteractionMode === "arrow"
                      ? qsTr("Select a target card")
                      : root.tableController.battlefieldInteractionMode === "attack"
                        ? qsTr("Select an opposing battlefield permanent to attack")
                      : root.tableController.battlefieldInteractionMode === "block"
                        ? qsTr("Select an attacking permanent to block")
                      : qsTr("Select an attachment target")
                color: Theme.primary
                font.pixelSize: Theme.fontSize(11)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }

        GridLayout {
            id: battlefieldGrid
            objectName: "battlefieldGrid"
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: root.tableController.edhFocusLayout
                     ? 4
                     : (root.tableController.usesEDHBattlefieldLayout ? 2 : 1)
            rows: root.tableController.edhFocusLayout
                  ? root.tableController.battlefieldLayout.focusLaneCount()
                  : (root.tableController.usesEDHBattlefieldLayout
                     ? 2
                     : Math.max(
                           1,
                           root.tableController.battlefieldSeats.length))
            columnSpacing: Theme.size(6)
            rowSpacing: Theme.size(6)

            Repeater {
                model: root.tableController.battlefieldSeats

                delegate: Surface {
                    id: battlefieldZone
                    required property var modelData
                    required property int index
                    readonly property bool isOwn: modelData.seat
                                                          === root.tableController.roomSession.seatIndex
                    readonly property var cards: modelData.battlefieldModel
                    readonly property int cardCount:
                        root.tableController.zoneState.modelCardCount(cards)
                    readonly property bool isActiveTurn:
                        modelData.seat
                        === root.tableController.gameSession.activeSeat
                    readonly property bool isPrimaryBattlefield:
                        root.tableController.edhFocusLayout
                        && modelData.seat
                           === root.tableController.battlefieldLayout.effectiveFocusSeat()
                    readonly property bool zonePanelExpanded:
                        !isOwn
                        && root.tableController.sharedZones.opponentZoneExpanded(
                            modelData.seat)
                    objectName: "battlefieldZone" + modelData.seat
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth:
                        root.tableController.edhFocusLayout
                        ? (modelData.seat
                           === root.tableController.battlefieldLayout.effectiveFocusSeat()
                           ? battlefieldGrid.width * 0.75
                           : battlefieldGrid.width * 0.25)
                        : -1
                    Layout.preferredHeight:
                        root.tableController.edhFocusLayout
                        ? (modelData.seat
                           === root.tableController.battlefieldLayout.effectiveFocusSeat()
                           ? battlefieldGrid.height
                           : battlefieldGrid.height
                             / root.tableController.battlefieldLayout.focusLaneCount())
                        : -1
                    Layout.row:
                        root.tableController.edhFocusLayout
                        ? root.tableController.battlefieldLayout.focusRow(modelData.seat)
                        : (root.tableController.usesEDHBattlefieldLayout
                           ? root.tableController.battlefieldLayout.overviewRow(
                                 modelData.seat, index)
                           : index)
                    Layout.column:
                        root.tableController.edhFocusLayout
                        ? root.tableController.battlefieldLayout.focusColumn(modelData.seat)
                        : (root.tableController.usesEDHBattlefieldLayout
                           ? root.tableController.battlefieldLayout.overviewColumn(
                                 modelData.seat, index)
                           : 0)
                    Layout.rowSpan:
                        root.tableController.edhFocusLayout
                        && modelData.seat
                           === root.tableController.battlefieldLayout.effectiveFocusSeat()
                        ? root.tableController.battlefieldLayout.focusLaneCount()
                        : 1
                    Layout.columnSpan:
                        root.tableController.edhFocusLayout
                        && modelData.seat
                           === root.tableController.battlefieldLayout.effectiveFocusSeat()
                        ? 3
                        : root.tableController.battlefieldLayout.overviewColumnSpan(
                              modelData.seat)
                    color: isOwn ? Theme.primaryMuted : Theme.surfaceHover
                    radius: 0
                    border.width: isActiveTurn ? Theme.size(2) : 1
                    border.color: isActiveTurn
                                  ? Theme.primary : Theme.border
                    opacity: modelData.eliminated === true ? 0.58 : 1
                    Component.onCompleted:
                        root.tableController.battlefieldScene.registerSeat(
                            modelData.seat, battlefieldSeatTarget)
                    Component.onDestruction:
                        root.tableController.battlefieldScene.unregisterSeat(
                            modelData.seat, battlefieldSeatTarget)
                    onXChanged:
                        root.tableController.battlefieldScene.schedulePointRefresh()
                    onYChanged:
                        root.tableController.battlefieldScene.schedulePointRefresh()
                    onWidthChanged:
                        root.tableController.battlefieldScene.schedulePointRefresh()
                    onHeightChanged:
                        root.tableController.battlefieldScene.schedulePointRefresh()

                    Text {
                        textFormat: Text.PlainText
                        id: battlefieldPlayerName
                        objectName: "battlefieldPlayerName"
                                    + battlefieldZone.modelData.seat
                        anchors.left: parent.left
                        anchors.right: battlefieldHeader.left
                        anchors.top: parent.top
                        anchors.leftMargin: Theme.size(9)
                        anchors.rightMargin: Theme.size(8)
                        anchors.topMargin: Theme.size(7)
                        height: Theme.size(24)
                        z: 220
                        text: battlefieldZone.modelData.displayName
                              ? battlefieldZone.modelData.displayName
                              : qsTr("Seat") + " "
                                + (battlefieldZone.modelData.seat + 1)
                        color: battlefieldZone.isOwn
                               ? Theme.primary : Theme.text
                        font.pixelSize: Theme.fontSize(11)
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }

                    RowLayout {
                        id: battlefieldHeader
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.size(7)
                        spacing: Theme.size(8)
                        z: 220

                        StatusPill {
                            objectName: "activeTurnBadge"
                                        + battlefieldZone.modelData.seat
                            visible: battlefieldZone.isActiveTurn
                                     && battlefieldZone.width
                                        >= Theme.size(360)
                            text: battlefieldZone.isOwn
                                  ? I18n.tr("Your turn")
                                  : I18n.tr("Current turn")
                            statusColor: Theme.primary
                        }

                        StatusPill {
                            objectName: "responseStatusBadge"
                                        + battlefieldZone.modelData.seat
                            visible: battlefieldZone.modelData.responseStatus
                                     === "pass"
                                     || battlefieldZone.modelData.responseStatus
                                        === "hold"
                            text: battlefieldZone.modelData.responseStatus
                                  === "hold" ? qsTr("Wait") : qsTr("Passed")
                            statusColor:
                                battlefieldZone.modelData.responseStatus
                                === "hold" ? Theme.warning : Theme.success
                        }

                        Text {
                            textFormat: Text.PlainText
                            objectName: "battlefieldPlayerSummary"
                                        + battlefieldZone.modelData.seat
                            visible: !battlefieldZone.isOwn
                            text: root.tableController.gameValues.displayedLife(
                                      battlefieldZone.modelData)
                                  + qsTr("HP") + " / "
                                  + battlefieldZone.modelData.handCount
                                  + qsTr("H") + " / "
                                  + battlefieldZone.modelData.libraryCount
                                  + qsTr("D")
                                  + (battlefieldZone.modelData.mulliganCount > 0
                                     ? " / M"
                                       + battlefieldZone.modelData.mulliganCount
                                     : "")
                            color:
                                root.tableController.rulesAssist.possibleLoss(
                                    battlefieldZone.modelData)
                                ? Theme.error
                                : (root.tableController.rulesAssist.emptyLibrary(
                                       battlefieldZone.modelData)
                                   || root.tableController.rulesAssist.oversizedHand(
                                       battlefieldZone.modelData)
                                   ? Theme.warning : Theme.textSecondary)
                            font.pixelSize: Theme.fontSize(11)
                            font.weight: Font.DemiBold
                        }
                        AppButton {
                            objectName: "focusBattlefieldButton"
                                        + battlefieldZone.modelData.seat
                            visible:
                                root.tableController.usesEDHBattlefieldLayout
                            compact: true
                            Layout.preferredWidth:
                                Theme.size(30)
                            implicitHeight: Theme.size(24)
                            variant: battlefieldZone.isPrimaryBattlefield
                                     ? "primary" : "ghost"
                            text: battlefieldZone.isPrimaryBattlefield
                                  ? "▦" : "▣"
                            accessibleName:
                                battlefieldZone.isPrimaryBattlefield
                                ? qsTr("Overview layout")
                                : qsTr("Set as primary battlefield")
                            onClicked:
                                root.tableController.battlefieldLayout.toggleFocusSeat(
                                    battlefieldZone.modelData.seat)
                            ToolTip.visible: hovered
                            ToolTip.text:
                                battlefieldZone.isPrimaryBattlefield
                                ? qsTr("Overview layout")
                                : qsTr("Set as primary battlefield")
                        }
                        AppButton {
                            objectName: "opponentZoneToggle"
                                        + battlefieldZone.modelData.seat
                            visible: !battlefieldZone.isOwn
                            compact: true
                            Layout.preferredWidth: Theme.size(30)
                            implicitHeight: Theme.size(24)
                            text: battlefieldZone.zonePanelExpanded
                                  ? "▴" : "▾"
                            onClicked:
                                root.tableController.sharedZones.setOpponentZoneExpanded(
                                    battlefieldZone.modelData.seat,
                                    !battlefieldZone.zonePanelExpanded)
                            ToolTip.visible: hovered
                            ToolTip.text:
                                battlefieldZone.zonePanelExpanded
                                ? qsTr("Hide zones")
                                : qsTr("Show zones")
                        }
                    }

                    Item {
                        id: battlefieldSeatTarget
                        x: parent.width / 2
                        y: Theme.size(8)
                        width: 1
                        height: 1
                    }

                    Item {
                        id: battlefieldZoneArea
                        anchors.fill: parent
                        anchors.margins: Theme.size(6)

                    MouseArea {
                        objectName: "battlefieldBackgroundMouseArea"
                                    + battlefieldZone.modelData.seat
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        enabled: battlefieldZone.isOwn
                                 && root.tableController.canAct
                                 && !root.tableController.tableModalOpen
                        onClicked: function(mouse) {
                            if (root.tableController.suppressBattlefieldAreaMenu)
                                return
                            const position =
                                battlefieldZoneArea.mapToItem(
                                    root.tableController,
                                    mouse.x,
                                    mouse.y)
                            if (root.tableController.battlefieldScene.cardAtRootPoint(
                                        position.x,
                                        position.y)) {
                                return
                            }
                            root.areaMenu.x = position.x
                            root.areaMenu.y = position.y
                            root.areaMenu.open()
                        }
                    }

                    DropArea {
                        id: zoneDropArea
                        objectName: battlefieldZone.isOwn
                                    ? "battlefieldDropArea"
                                    : "opponentBattlefieldDropArea"
                                      + battlefieldZone.modelData.seat
                        property var cardSource: null
                        anchors.fill: parent
                        enabled: root.tableController.canAct
                        keys: ["hexproof/card"]

                        onEntered: function(drag) {
                            zoneDropArea.cardSource = drag.source
                        }
                        onExited: zoneDropArea.cardSource = null
                        onDropped: function(drop) {
                            // The cached source is only for hover feedback. A
                            // snapshot or transient leave event may clear it
                            // immediately before the drop; DragEvent.source is
                            // the authoritative source for this operation.
                            const source = drop.source
                                           ? drop.source
                                           : zoneDropArea.cardSource
                            if (!root.tableController.cardMoveCommands.canMoveSharedSource(source)
                                || !root.tableController.cardMoveCommands.canMoveToBattlefield(
                                    source)) {
                                zoneDropArea.cardSource = null
                                drop.accepted = false
                                return
                            }
                            const cardWidth =
                                root.tableController.battlefieldCardWidth
                            const cardHeight =
                                root.tableController.battlefieldCardHeight
                            const viewX = Math.max(
                                0, Math.min(
                                    1,
                                    (drop.x - cardWidth / 2)
                                    / Math.max(
                                        1, width - cardWidth)))
                            const viewY = Math.max(
                                0, Math.min(
                                    1,
                                    (drop.y - cardHeight / 2)
                                    / Math.max(
                                        1, height - cardHeight)))
                            const storedPosition =
                                root.tableController.battlefieldLayout.positionFromView(
                                    battlefieldZone.modelData.seat,
                                    viewX, viewY)
                            if (!root.tableController.cardMoveCommands.moveDroppedCardToBattlefield(
                                        source,
                                        battlefieldZone.modelData.seat,
                                        storedPosition.x,
                                        storedPosition.y)) {
                                zoneDropArea.cardSource = null
                                drop.accepted = false
                                return
                            }
                            zoneDropArea.cardSource = null
                            drop.acceptProposedAction()
                        }
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        visible: battlefieldZone.cardCount === 0
                                 && root.tableController.zoneState.pendingBattlefieldMovesForSeat(
                                     battlefieldZone.modelData.seat).length
                                    === 0
                        text: battlefieldZone.isOwn
                              ? qsTr("Drag a card from your hand onto the battlefield")
                              : qsTr("No permanents")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(9)
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        radius: Theme.radiusMedium
                        border.width: zoneDropArea.containsDrag
                                      ? Theme.size(2) : 0
                        border.color: Theme.primary
                    }

                    Repeater {
                        model:
                            root.tableController.zoneState.pendingBattlefieldMovesForSeat(
                                battlefieldZone.modelData.seat)

                        delegate: Surface {
                            id: pendingCardDelegate
                            required property var modelData
                            required property int index
                            objectName:
                                battlefieldZone.isOwn
                                ? (index === 0
                                   ? "pendingBattlefieldCard"
                                   : "pendingBattlefieldCard-"
                                     + modelData.cardId)
                                : (index === 0
                                   ? "opponentPendingBattlefieldCard"
                                     + battlefieldZone.modelData.seat
                                   : "opponentPendingBattlefieldCard"
                                     + battlefieldZone.modelData.seat
                                     + "-" + modelData.cardId)
                            width: root.tableController.battlefieldCardWidth
                            height: root.tableController.battlefieldCardHeight
                            // Optimistic cards are visual feedback only. If they
                            // participate in hit testing, several pending moves
                            // can cover both real cards and the battlefield
                            // DropArea until their snapshots arrive.
                            enabled: false
                            x: Math.max(
                                   0, Math.min(
                                       battlefieldZoneArea.width
                                       - width,
                                       modelData.x
                                       * Math.max(
                                           0,
                                           battlefieldZoneArea.width
                                           - width)))
                            y: Math.max(
                                   0, Math.min(
                                       battlefieldZoneArea.height
                                       - height,
                                       root.tableController.battlefieldLayout.yForView(
                                           battlefieldZone.modelData.seat,
                                           modelData.y,
                                           0)
                                       * Math.max(
                                           0,
                                           battlefieldZoneArea.height
                                           - height)))
                            z: 90 + index
                            color: "transparent"
                            border.width: 0
                            opacity: 0.78
                            clip: true
                            rotation:
                                modelData.tapped === true
                                ? 90 : 0

                            Image {
                                anchors.fill: parent
                                source:
                                    root.tableController.presentation.tableCardImageSource(
                                        pendingCardDelegate.modelData)
                                fillMode:
                                    Image.PreserveAspectFit
                                asynchronous: true
                            }
                            StatusPill {
                                anchors.horizontalCenter:
                                    parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin:
                                    Theme.size(5)
                                text: qsTr("Syncing…")
                                statusColor: Theme.primary
                            }
                        }
                    }

                    Repeater {
                        model: battlefieldZone.cards

                        delegate: BattlefieldCardDelegate {
                            tableController: root.tableController
                            cardMenu: root.cardMenu
                            seatData: battlefieldZone.modelData
                            isOwn: battlefieldZone.isOwn
                            zoneArea: battlefieldZoneArea
                            playerAttackTargetName:
                                root.playerAttackTargetName(cardId)
                        }
                    }
                }
            }
        }
        }
    }

    MouseArea {
        objectName: "battlefieldScaleWheelArea"
        anchors.fill: parent
        z: 1000
        acceptedButtons: Qt.NoButton
        onWheel: function(wheel) {
            if (!(wheel.modifiers & Qt.ControlModifier)) {
                wheel.accepted = false
                return
            }
            const delta = wheel.angleDelta.y !== 0
                        ? wheel.angleDelta.y : wheel.angleDelta.x
            if (delta === 0) {
                wheel.accepted = false
                return
            }
            root.tableController.battlefieldLayout.adjustCardScale(delta)
            wheel.accepted = true
        }
    }
}
