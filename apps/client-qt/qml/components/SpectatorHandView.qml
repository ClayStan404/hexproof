// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "Table"

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    objectName: "spectatorHandView"
    required property var tableController
    property int selectedSeat: -1
    readonly property var seats: tableController.authoritativeSeats
                                 ? tableController.authoritativeSeats : []
    readonly property var selectedSeatData: seatData(selectedSeat)
    readonly property var selectedHandModel:
        selectedSeat >= 0
        ? tableController.zoneState.zoneDelegateModel(selectedSeat, "hand")
        : []
    readonly property real handScrollMinimum: handList.originX
    readonly property real handScrollMaximum:
        handScrollMinimum + Math.max(0, handList.contentWidth - handList.width)
    readonly property real fittedHandCardWidth:
        Math.max(root.tableController.handCardWidth,
                 Math.round(Math.max(0, handList.height) * 63 / 88))

    function seatData(seatIndex) {
        for (let index = 0; index < seats.length; ++index) {
            if (seats[index].seat === seatIndex)
                return seats[index]
        }
        return ({})
    }

    function ensureSelectedSeat() {
        if (selectedSeatData.seat !== undefined)
            return
        selectedSeat = seats.length > 0 ? seats[0].seat : -1
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
        const pixelDelta = Math.abs(wheel.pixelDelta.x)
                           > Math.abs(wheel.pixelDelta.y)
                           ? wheel.pixelDelta.x : wheel.pixelDelta.y
        const angleDelta = Math.abs(wheel.angleDelta.x)
                           > Math.abs(wheel.angleDelta.y)
                           ? wheel.angleDelta.x : wheel.angleDelta.y
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

    Component.onCompleted: ensureSelectedSeat()
    onSelectedSeatChanged: tableController.presentation.hideCardPreview()

    Connections {
        target: root.tableController.gameTableModel
        function onSnapshotChanged() {
            root.ensureSelectedSeat()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.size(4)
        spacing: Theme.size(4)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(6)

            Text {
                textFormat: Text.PlainText
                text: qsTranslate("Table", "Spectator hand view")
                color: Theme.text
                font.pixelSize: Theme.fontSize(12)
                font.weight: Font.DemiBold
            }

            Repeater {
                model: root.seats

                delegate: AppButton {
                    required property var modelData
                    required property int index
                    objectName: "spectatorHandSeat" + modelData.seat
                    Layout.fillWidth: true
                    compact: true
                    variant: root.selectedSeat === modelData.seat
                             ? "primary" : "ghost"
                    text: (modelData.displayName
                           ? modelData.displayName
                           : qsTranslate("Table", "Seat") + " " + (modelData.seat + 1))
                          + " · " + modelData.handCount
                    onClicked: root.selectedSeat = modelData.seat
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                visible: handList.count === 0
                text: qsTranslate("Table", "This hand is empty")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
            }

            ListView {
                id: handList
                objectName: "spectatorHandList"
                anchors.fill: parent
                orientation: ListView.Horizontal
                spacing: Theme.size(7)
                clip: true
                interactive: false
                pixelAligned: false
                cacheBuffer: count * Theme.size(160)
                boundsBehavior: Flickable.StopAtBounds
                model: root.selectedHandModel
                onCountChanged: Qt.callLater(root.clampHandScrollPosition)
                onContentWidthChanged:
                    Qt.callLater(root.clampHandScrollPosition)
                onOriginXChanged: Qt.callLater(root.clampHandScrollPosition)
                onWidthChanged: Qt.callLater(root.clampHandScrollPosition)

                delegate: Item {
                    id: spectatorHandCard
                    required property var modelData
                    required property int index
                    objectName: "spectatorHandCard" + index
                    width: root.fittedHandCardWidth
                    height: handList.height
                    clip: true

                    Image {
                        id: cardArt
                        anchors.fill: parent
                        source: root.tableController.presentation.tableCardImageSource(
                                    spectatorHandCard.modelData)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: cardArt.status !== Image.Ready
                        color: Theme.surfaceElevated

                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            width: parent.width - Theme.size(10)
                            text: root.tableController.presentation.tableCardPlaceholderName(
                                      spectatorHandCard.modelData)
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSize(10)
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered:
                            root.tableController.presentation.inspectCard(
                                spectatorHandCard.modelData,
                                spectatorHandCard)
                        onExited:
                            root.tableController.presentation.hideCardPreview(
                                spectatorHandCard)
                    }

                    Component.onDestruction:
                        root.tableController.presentation.hideCardPreview(
                            spectatorHandCard)
                }
            }

            MouseArea {
                parent: handList
                anchors.fill: parent
                z: 1000
                acceptedButtons: Qt.NoButton
                onWheel: function(wheel) {
                    root.scrollByWheel(wheel, true)
                }
            }
        }
    }
}
