// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    required property var tableController
    required property var cardMenu
    readonly property var cardItems: new Map()

    function registerCard(cardId, item) {
        cardItems.set(cardId, item)
    }

    function unregisterCard(cardId, item) {
        if (cardItems.get(cardId) !== item)
            return
        cardItems.delete(cardId)
    }

    function cardAtTablePoint(tableX, tableY) {
        const listPoint = handList.mapFromItem(
                            tableController, tableX, tableY)
        if (listPoint.x < 0 || listPoint.x > handList.width
            || listPoint.y < 0 || listPoint.y > handList.height) {
            return false
        }
        let found = false
        cardItems.forEach(function(item) {
            if (found)
                return
            if (!item || !item.visible || !item.parent)
                return
            const localPoint = item.mapFromItem(
                                 tableController, tableX, tableY)
            if (localPoint.x >= 0 && localPoint.x <= item.width
                && localPoint.y >= 0 && localPoint.y <= item.height) {
                found = true
            }
        })
        return found
    }

    function scrollByWheel(wheel) {
        const maximumX = Math.max(
            0, handList.contentWidth - handList.width)
        if (maximumX <= 0) {
            wheel.accepted = false
            return
        }

        const pixelX = wheel.pixelDelta.x
        const pixelY = wheel.pixelDelta.y
        const pixelDelta = Math.abs(pixelX) > Math.abs(pixelY)
                           ? pixelX : pixelY
        const angleX = wheel.angleDelta.x
        const angleY = wheel.angleDelta.y
        const angleDelta = Math.abs(angleX) > Math.abs(angleY)
                           ? angleX : angleY
        const delta = pixelDelta !== 0
                      ? pixelDelta
                      : angleDelta / 120 * Theme.size(72)
        if (delta === 0) {
            wheel.accepted = false
            return
        }

        const previousX = handList.contentX
        handList.contentX = Math.max(
            0, Math.min(maximumX, previousX - delta))
        wheel.accepted = handList.contentX !== previousX
    }

    DropArea {
        id: handDropArea
        objectName: "handDropArea"
        property var cardSource: null
        anchors.fill: parent
        enabled: root.tableController.canAct
        keys: ["hexproof/card"]

        onEntered: function(drag) {
            handDropArea.cardSource = drag.source
        }
        onExited: handDropArea.cardSource = null
        onDropped: function(drop) {
            // Use the drop event as the authoritative source. A transient
            // leave can clear the cached source immediately before release.
            const source = drop.source ? drop.source : handDropArea.cardSource
            if (!root.tableController.cardMoveCommands.canMoveToHand(source)) {
                drop.accepted = false
                return
            }
            root.tableController.cardMoveCommands.moveCardToShared(
                        source.cardId, source.zoneName, "hand")
            handDropArea.cardSource = null
            drop.acceptProposedAction()
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        radius: Theme.radiusMedium
        border.width: handDropArea.containsDrag ? Theme.size(2) : 0
        border.color: Theme.primary
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.size(4)
        spacing: Theme.size(3)

        RowLayout {
            Layout.fillWidth: true

            Text {
                textFormat: Text.PlainText
                id: ownHandLabel
                text: qsTr("Your hand") + " · "
                      + root.tableController.projectionSync.visibleOwnHandCount()
                color: root.tableController.rulesAssist.oversizedHand(
                           root.tableController.ownSeatData)
                       ? Theme.warning : Theme.text
                font.pixelSize: Theme.fontSize(12)
                font.weight: Font.DemiBold
                HoverHandler { id: handLimitHover }
                ToolTip.visible: handLimitHover.hovered
                                 && root.tableController.rulesAssist.oversizedHand(
                                     root.tableController.ownSeatData)
                ToolTip.text: qsTr("The usual maximum hand size is 7. Card effects may change it.")
            }
            Slider {
                id: handScrollSlider
                objectName: "handScrollSlider"
                Layout.fillWidth: true
                Layout.leftMargin: Theme.size(14)
                from: 0
                to: Math.max(0, handList.contentWidth - handList.width)
                value: handList.contentX
                enabled: to > 0
                onMoved: handList.contentX = value
                ToolTip.visible: hovered && enabled
                ToolTip.text: qsTr("Scroll hand")
            }
        }

        ListView {
            id: handList
            objectName: "ownHand"
            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: ListView.Horizontal
            spacing: Theme.size(7)
            clip: true
            model: root.tableController.ownHand
            boundsBehavior: Flickable.StopAtBounds

            function focusCard(targetIndex) {
                if (count <= 0)
                    return
                const bounded = Math.max(0, Math.min(count - 1,
                                                     targetIndex))
                currentIndex = bounded
                positionViewAtIndex(bounded, ListView.Contain)
                Qt.callLater(() => {
                    const item = itemAtIndex(bounded)
                    if (item)
                        item.forceActiveFocus()
                })
            }

            delegate: Item {
                id: handCard
                required property var modelData
                required property int index
                readonly property string cardId: modelData.id
                readonly property string zoneName: "hand"
                readonly property int ownerSeat:
                    root.tableController.roomSession.seatIndex
                readonly property int zoneSeat:
                    root.tableController.roomSession.seatIndex
                readonly property bool pendingDeparture:
                    root.tableController.optimisticCommands.isCardPendingFrom(
                        cardId, "hand",
                        root.tableController.roomSession.seatIndex)
                objectName: "handCard" + index
                // Visibility already removes a delegate from tab traversal.
                // Keeping this constant avoids changing activeFocusOnTab while
                // the card still owns active focus during an optimistic move.
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: modelData.name ? modelData.name : qsTr("Card")
                width: pendingDeparture
                       ? 0 : root.tableController.handCardWidth
                height: handList.height
                clip: true
                z: handDrag.drag.active ? 100 : 0
                visible: !pendingDeparture
                scale: handDrag.drag.active ? 1.045 : 1
                opacity: handDrag.drag.active ? 0.94 : 1

                Behavior on scale {
                    NumberAnimation {
                        duration: Theme.motionFast
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on opacity {
                    NumberAnimation { duration: Theme.motionFast }
                }

                Drag.active: handDrag.drag.active
                Drag.source: handCard
                Drag.keys: ["hexproof/card"]
                Drag.hotSpot.x: width / 2
                Drag.hotSpot.y: height / 2

                function openCardMenu(localX, localY) {
                    root.tableController.selection.clear()
                    root.tableController.selectedHandCard =
                        handCard.modelData || ({})
                    const position = handCard.mapToItem(
                        root.tableController, localX, localY)
                    root.cardMenu.x = position.x
                    root.cardMenu.y = position.y
                    root.cardMenu.open()
                }

                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Left) {
                        handList.focusCard(index - 1)
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_Right) {
                        handList.focusCard(index + 1)
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_Home) {
                        handList.focusCard(0)
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_End) {
                        handList.focusCard(handList.count - 1)
                        event.accepted = true
                        return
                    }
                    if (event.key !== Qt.Key_Return
                            && event.key !== Qt.Key_Enter
                            && event.key !== Qt.Key_Menu) {
                        return
                    }
                    handCard.openCardMenu(width / 2, height / 2)
                    event.accepted = true
                }

                states: State {
                    when: handCard.Drag.active
                    ParentChange {
                        target: handCard
                        parent: root.tableController
                    }
                }

                Image {
                    id: cardArt
                    anchors.fill: parent
                    source: root.tableController.presentation.tableCardImageSource(
                                handCard.modelData)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
                Rectangle {
                    anchors.fill: parent
                    visible: cardArt.status !== Image.Ready
                             && handCard.modelData.faceDown !== true
                    color: Theme.surfaceElevated
                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        width: parent.width - Theme.size(10)
                        text: root.tableController.presentation.tableCardPlaceholderName(
                                  handCard.modelData)
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(10)
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    z: 20
                    color: "transparent"
                    radius: Theme.radiusSmall
                    border.width: handCard.activeFocus ? Theme.size(2) : 0
                    border.color: Theme.primary
                }
                StatusPill {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Theme.size(5)
                    visible: handCard.modelData.pending === true
                    text: qsTr("Syncing…")
                    statusColor: Theme.primary
                }
                MouseArea {
                    id: handDrag
                    anchors.fill: parent
                    enabled: root.tableController.canAct
                             && !root.tableController.tableModalOpen
                    hoverEnabled: true
                    cursorShape: drag.active
                                 ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    drag.target: handCard
                    drag.threshold: Theme.size(5)
                    preventStealing: true
                    onEntered: root.tableController.presentation.inspectCard(
                                   handCard.modelData, handCard)
                    onExited: root.tableController.presentation.hideCardPreview(
                                  handCard)
                    onPressed: {
                        root.tableController.presentation.hideCardPreview()
                        root.tableController.activeHandDragCardId =
                            handCard.cardId
                    }
                    onReleased: {
                        handCard.Drag.drop()
                        Qt.callLater(() => {
                            root.tableController.projectionSync.finishHandDrag()
                            handList.forceLayout()
                        })
                    }
                    onCanceled: root.tableController.projectionSync.finishHandDrag()
                }
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    enabled: !root.tableController.tableModalOpen
                    onTapped: function(point) {
                        handCard.openCardMenu(point.position.x,
                                              point.position.y)
                    }
                }
                Component.onCompleted:
                    root.registerCard(modelData.id, handCard)
                Component.onDestruction:
                    root.unregisterCard(modelData.id, handCard)
            }
        }
    }

    MouseArea {
        objectName: "handWheelMouseArea"
        parent: handList
        anchors.fill: parent
        z: 1000
        acceptedButtons: Qt.NoButton
        onWheel: function(wheel) {
            root.scrollByWheel(wheel)
        }
    }
}
