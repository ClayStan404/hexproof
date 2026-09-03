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

    function scrollByWheel(wheel) {
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
        handList.contentX = Math.max(
                    handScrollMinimum,
                    Math.min(handScrollMaximum, previousX - delta))
        wheel.accepted = handList.contentX !== previousX
    }

    function clampHandScrollPosition() {
        const boundedX = Math.max(
                    handScrollMinimum, Math.min(handScrollMaximum, handList.contentX))
        if (handList.contentX !== boundedX)
            handList.contentX = boundedX
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
                text: qsTr("Spectator hand view")
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
                           : qsTr("Seat") + " " + (modelData.seat + 1))
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
                text: qsTr("This hand is empty")
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
                    width: root.tableController.handCardWidth
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
                    root.scrollByWheel(wheel)
                }
            }
        }
    }
}
