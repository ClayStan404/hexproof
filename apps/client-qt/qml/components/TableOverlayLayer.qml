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
    anchors.fill: parent
    z: 4000

    AppButton {
        objectName: "restoreGameLogRailButton"
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.size(8)
        z: 4000
        visible: !root.tableController.showGameLogRail && !root.tableController.gameSession.sideboarding
        compact: true
        variant: "secondary"
        text: qsTr("Show game log")
        onClicked: root.tableController.sessionUi.setGameLogRailVisible(true)
    }

    Rectangle {
        objectName: "tableReconnectOverlay"
        anchors.fill: parent
        z: 4400
        visible: root.tableController.wsModel.reconnecting === true
        color: Theme.background
        opacity: 0.94

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: mouse => mouse.accepted = true
            onWheel: wheel => wheel.accepted = true
        }

        Column {
            anchors.centerIn: parent
            spacing: Theme.size(10)

            ActivityRing {
                anchors.horizontalCenter: parent.horizontalCenter
                ringColor: Theme.accent
            }
            Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Restoring your seat")
                color: Theme.text
                font.pixelSize: Theme.fontSize(20)
                font.weight: Font.DemiBold
            }
            Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: {
                    const remaining = root.tableController.wsModel
                                      .reconnectSecondsRemaining
                    if (!remaining || remaining <= 0)
                        return qsTr("Table actions are paused while reconnecting.")
                    const minutes = Math.floor(remaining / 60)
                    const seconds = remaining % 60
                    const time = minutes + ":"
                                 + (seconds < 10 ? "0" : "") + seconds
                    return qsTr("Table actions are paused · %1 remaining")
                        .arg(time)
                }
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(13)
            }
        }
    }

    Item {
        objectName: "tableModalInputShield"
        anchors.fill: parent
        z: 4500
        visible: root.tableController.tableModalOpen
        enabled: visible

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            hoverEnabled: true
            preventStealing: true
            propagateComposedEvents: false
            onPressed: mouse => mouse.accepted = true
            onClicked: mouse => mouse.accepted = true
            onDoubleClicked: mouse => mouse.accepted = true
            onWheel: wheel => wheel.accepted = true
        }
    }

    Item {
        id: cardHoverPreview
        objectName: "cardHoverPreview"
        x: root.tableController.hoverPreviewX
        y: root.tableController.hoverPreviewY
        width: Theme.size(250)
        height: Math.round(width * 88 / 63)
        z: 5000
        visible: !root.tableController.tableModalOpen && root.tableController.hoverPreviewVisible
                 && !!root.tableController.inspectedCard.name
        enabled: false
        opacity: visible ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.motionFast }
        }

        Image {
            id: hoverPreviewArt
            objectName: "cardHoverPreviewArt"
            anchors.fill: parent
            source: root.tableController.presentation.tableCardImageSource
                    ? root.tableController.presentation.tableCardImageSource(
                          root.tableController.inspectedCard)
                    : root.tableController.presentation.cardImageSource(
                          root.tableController.inspectedCard)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
        }

        Text {
            textFormat: Text.PlainText
            objectName: "cardHoverPreviewName"
            anchors.centerIn: parent
            width: parent.width - Theme.size(20)
            visible: hoverPreviewArt.status === Image.Error
                     && root.tableController.inspectedCard.faceDown !== true
            text: root.tableController.presentation.tableCardPlaceholderName
                  ? root.tableController.presentation.tableCardPlaceholderName(
                        root.tableController.inspectedCard)
                  : (root.tableController.inspectedCard.name
                     ? root.tableController.inspectedCard.name : "")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(12)
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
