// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQml.Models

Item {
    id: root

    required property var tableController
    required property var cardMenu
    readonly property var cardItems: new Map()
    readonly property real handScrollMinimum: handList.originX
    readonly property real handScrollMaximum:
        handScrollMinimum + Math.max(0, handList.contentWidth - handList.width)
    readonly property real fittedHandCardWidth:
        Math.max(root.tableController.handCardWidth,
                 Math.round(Math.max(0, handList.height) * 63 / 88))

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

    function stopHandScrollAnimation() {
        if (handScrollAnimation.running)
            handScrollAnimation.stop()
    }

    function applyHandScroll(nextX, animate) {
        const bounded = Math.max(
                    handScrollMinimum, Math.min(handScrollMaximum, nextX))
        if (animate && Math.abs(bounded - handList.contentX) > 0.5) {
            handScrollAnimation.to = bounded
            handScrollAnimation.restart()
            return
        }
        stopHandScrollAnimation()
        if (handList.contentX !== bounded)
            handList.contentX = bounded
    }

    function scrollByWheel(wheel, smooth) {
        if (handScrollMaximum <= handScrollMinimum) {
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
        const nextX = Math.max(
                    handScrollMinimum,
                    Math.min(handScrollMaximum, previousX - delta))
        if (nextX === previousX && !handScrollAnimation.running) {
            wheel.accepted = false
            return
        }
        applyHandScroll(nextX, smooth === true && pixelDelta === 0)
        wheel.accepted = true
    }

    function clampHandScrollPosition() {
        if (handScrollAnimation.running) {
            const target = Math.max(
                        handScrollMinimum,
                        Math.min(handScrollMaximum, handScrollAnimation.to))
            if (target !== handScrollAnimation.to)
                handScrollAnimation.to = target
            return
        }
        const boundedX = Math.max(
            handScrollMinimum, Math.min(handScrollMaximum, handList.contentX))
        if (handList.contentX !== boundedX)
            handList.contentX = boundedX
    }

    SmoothedAnimation {
        id: handScrollAnimation
        target: handList
        property: "contentX"
        reversingMode: SmoothedAnimation.Immediate
        duration: Theme.motionNormal
        velocity: Theme.size(1400)
    }

    DropArea {
        id: handDropArea
        objectName: "handDropArea"
        property var cardSource: null
        anchors.fill: parent
        enabled: root.tableController.canAct
        keys: ["hexproof/card"]

        function reorderOwnHandAt(source, areaX, areaY) {
            if (!source || source.zoneName !== "hand"
                    || source.ownerSeat
                       !== root.tableController.roomSession.seatIndex) {
                return
            }
            const point = handList.mapFromItem(
                            handDropArea, areaX, areaY)
            if (point.y < 0 || point.y > handList.height
                    || point.x < 0 || point.x > handList.width) {
                return
            }
            const stride = root.fittedHandCardWidth
                           + handList.spacing
            const contentCenter = handList.contentX + point.x
            const targetIndex = Math.max(
                        0, Math.min(handVisualModel.count - 1,
                                    Math.round((contentCenter
                                                - handList.originX
                                                - root.fittedHandCardWidth
                                                  / 2) / stride)))
            const sourceIndex = source.visualIndex
            if (sourceIndex >= 0 && targetIndex >= 0
                    && sourceIndex !== targetIndex) {
                handVisualModel.items.move(sourceIndex, targetIndex)
            }
        }

        onEntered: function(drag) {
            handDropArea.cardSource = drag.source
            reorderOwnHandAt(drag.source, drag.x, drag.y)
        }
        onPositionChanged: function(drag) {
            reorderOwnHandAt(drag.source, drag.x, drag.y)
        }
        onExited: handDropArea.cardSource = null
        onDropped: function(drop) {
            // Use the drop event as the authoritative source. A transient
            // leave can clear the cached source immediately before release.
            const source = drop.source ? drop.source : handDropArea.cardSource
            if (source && source.zoneName === "hand"
                    && source.ownerSeat
                       === root.tableController.roomSession.seatIndex) {
                handDropArea.cardSource = null
                drop.acceptProposedAction()
                return
            }
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
            id: ownHandHeader
            objectName: "ownHandHeader"
            Layout.fillWidth: true
            Layout.preferredHeight: ownHandLabel.implicitHeight
            Layout.maximumHeight: ownHandLabel.implicitHeight
            spacing: Theme.size(14)

            Text {
                textFormat: Text.PlainText
                id: ownHandLabel
                objectName: "ownHandLabel"
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
            Item {
                id: handScrollSlider
                objectName: "handScrollSlider"
                Layout.fillWidth: true
                Layout.preferredHeight: ownHandLabel.implicitHeight
                Layout.maximumHeight: ownHandLabel.implicitHeight
                implicitHeight: ownHandLabel.implicitHeight
                visible: to > from
                enabled: visible
                property real from: root.handScrollMinimum
                property real to: root.handScrollMaximum
                readonly property real value: handList.contentX
                readonly property real handleTravel:
                    Math.max(0, width - handScrollThumb.width)
                readonly property real handleWidth: {
                    const range = Math.max(0, to - from)
                    if (range <= 0 || width <= 0 || handList.width <= 0)
                        return Math.max(Theme.size(28), width)
                    return Math.max(
                                Theme.size(28),
                                width * handList.width
                                / (handList.width + range))
                }

                function contentXForHandle(handleX) {
                    if (handleTravel <= 0)
                        return from
                    return from + (handleX / handleTravel) * (to - from)
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: Theme.size(3)
                    radius: height / 2
                    color: Theme.border
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: function(mouse) {
                        const targetX = Math.max(
                                          0, Math.min(
                                              handScrollSlider.handleTravel,
                                              mouse.x - handScrollThumb.width / 2))
                        root.applyHandScroll(
                                    handScrollSlider.contentXForHandle(targetX),
                                    true)
                    }
                    ToolTip.visible: containsMouse && !thumbDrag.active
                    ToolTip.text: qsTr("Scroll hand")
                }

                Rectangle {
                    id: handScrollThumb
                    objectName: "handScrollThumb"
                    width: handScrollSlider.handleWidth
                    height: Math.max(Theme.size(10), parent.height)
                    radius: height / 2
                    y: (parent.height - height) / 2
                    z: 1
                    color: thumbDrag.active ? Theme.primaryHover
                                            : Theme.primary

                    MouseArea {
                        id: thumbDrag
                        anchors.fill: parent
                        preventStealing: true
                        cursorShape: drag.active ? Qt.ClosedHandCursor
                                                 : Qt.OpenHandCursor
                        drag.target: handScrollThumb
                        drag.axis: Drag.XAxis
                        drag.minimumX: 0
                        drag.maximumX: handScrollSlider.handleTravel
                        drag.smoothed: false
                        onPressed: root.stopHandScrollAnimation()
                        onPositionChanged: {
                            if (!drag.active)
                                return
                            root.applyHandScroll(
                                        handScrollSlider.contentXForHandle(
                                            handScrollThumb.x),
                                        false)
                        }
                    }
                }

                Binding {
                    target: handScrollThumb
                    property: "x"
                    value: {
                        const range = handScrollSlider.to
                                      - handScrollSlider.from
                        if (handScrollSlider.handleTravel <= 0 || range === 0)
                            return 0
                        return handScrollSlider.handleTravel
                               * (handScrollSlider.value - handScrollSlider.from)
                               / range
                    }
                    when: !thumbDrag.active
                    restoreMode: Binding.RestoreNone
                }
            }
        }

        Component {
            id: handCardDelegate

            Item {
                id: handCard
                required property var modelData
                readonly property int visualIndex: DelegateModel.itemsIndex
                property int dragStartVisualIndex: -1
                property point dragGrabPosition: Qt.point(width / 2, height / 2)
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
                objectName: "handCard" + visualIndex
                // Visibility already removes a delegate from tab traversal.
                // Keeping this constant avoids changing activeFocusOnTab while
                // the card still owns active focus during an optimistic move.
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: modelData.name ? modelData.name : qsTr("Card")
                width: pendingDeparture
                       ? 0 : root.fittedHandCardWidth
                height: handList.height
                clip: true
                z: handDrag.drag.active ? 100 : 0
                visible: !pendingDeparture
                property real dragScale: handDrag.drag.active ? 1.045 : 1
                opacity: handDrag.drag.active ? 0.94 : 1

                // Enlarge around the grab point so edge presses do not gain a
                // second hotspot offset while the lift animation runs.
                transform: Scale {
                    origin.x: handCard.dragGrabPosition.x
                    origin.y: handCard.dragGrabPosition.y
                    xScale: handCard.dragScale
                    yScale: handCard.dragScale
                }
                Behavior on dragScale {
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
                Drag.hotSpot.x: dragGrabPosition.x
                Drag.hotSpot.y: dragGrabPosition.y

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
                        handList.focusCard(visualIndex - 1)
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_Right) {
                        handList.focusCard(visualIndex + 1)
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
                    objectName: "handCardInteraction" + handCard.visualIndex
                    anchors.fill: parent
                    enabled: !root.tableController.tableModalOpen
                    hoverEnabled: true
                    cursorShape: drag.active
                                 ? Qt.ClosedHandCursor
                                 : root.tableController.canAct
                                   ? Qt.OpenHandCursor : Qt.PointingHandCursor
                    drag.target: root.tableController.canAct ? handCard : null
                    drag.threshold: Theme.size(5)
                    // Preserve the grab position when crossing the threshold.
                    // A fast first move must not offset drops from the pointer.
                    drag.smoothed: false
                    preventStealing: true
                    onEntered: root.tableController.presentation.inspectCard(
                                   handCard.modelData, handCard)
                    onExited: root.tableController.presentation.hideCardPreview(
                                  handCard)
                    onPressed: function(mouse) {
                        handCard.dragGrabPosition = Qt.point(mouse.x, mouse.y)
                        handCard.forceActiveFocus(Qt.MouseFocusReason)
                        root.tableController.presentation.hideCardPreview()
                        if (!root.tableController.canAct)
                            return
                        handCard.dragStartVisualIndex = handCard.visualIndex
                        root.tableController.activeHandDragCardId =
                            handCard.cardId
                    }
                    onReleased: {
                        if (!root.tableController.canAct)
                            return
                        const cardId = handCard.cardId
                        const targetIndex = handCard.visualIndex
                        handCard.Drag.drop()
                        Qt.callLater(() => {
                            root.tableController.projectionSync.reorderDisplayedHandCard(
                                        cardId, targetIndex)
                            root.tableController.projectionSync.finishHandDrag()
                            handList.forceLayout()
                        })
                    }
                    onCanceled: {
                        const currentIndex = handCard.visualIndex
                        if (currentIndex >= 0
                                && handCard.dragStartVisualIndex >= 0
                                && currentIndex
                                   !== handCard.dragStartVisualIndex) {
                            handVisualModel.items.move(
                                        currentIndex,
                                        handCard.dragStartVisualIndex)
                        }
                        root.tableController.projectionSync.finishHandDrag()
                    }
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

        DelegateModel {
            id: handVisualModel
            objectName: "handVisualModel"
            model: root.tableController.ownHand
            delegate: handCardDelegate
        }

        // Wrap the view so its content-tracking implicit size never feeds
        // back into this layout: fitted card widths depend on the view
        // height, so an unwrapped view re-polishes the column on every
        // resize and can loop on slower machines.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: handList
                objectName: "ownHand"
                anchors.fill: parent
                orientation: ListView.Horizontal
                spacing: Theme.size(7)
                clip: true
                interactive: false
                pixelAligned: false
                cacheBuffer: count * Theme.size(160)
                model: handVisualModel
                boundsBehavior: Flickable.StopAtBounds
                onCountChanged: {
                    forceLayout()
                    Qt.callLater(root.clampHandScrollPosition)
                }
                onContentWidthChanged: Qt.callLater(root.clampHandScrollPosition)
                onOriginXChanged: Qt.callLater(root.clampHandScrollPosition)
                onWidthChanged: Qt.callLater(root.clampHandScrollPosition)
                Component.onCompleted: {
                    forceLayout()
                    Qt.callLater(root.clampHandScrollPosition)
                }

                moveDisplaced: Transition {
                    NumberAnimation {
                        properties: "x"
                        duration: Theme.motionFast
                        easing.type: Easing.OutCubic
                    }
                }

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
            root.scrollByWheel(wheel, true)
        }
    }
}
