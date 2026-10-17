// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "Table"

import QtQuick

Item {
    id: root

    required property var tableController
    anchors.fill: parent
    z: 4000

    Connections {
        target: root.tableController
        function onTableModalOpenChanged() {
            if (root.tableController.tableModalOpen)
                root.tableController.presentation.hideCardPreview()
        }
    }
    Connections {
        target: root.tableController.wsModel
        ignoreUnknownSignals: true
        function onReconnectingChanged() {
            if (root.tableController.wsModel.reconnecting)
                root.tableController.presentation.hideCardPreview()
        }
        function onInRoomChanged() {
            if (root.tableController.wsModel.inRoom === false)
                root.tableController.presentation.hideCardPreview()
        }
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
                text: qsTranslate("Table", "Restoring your seat")
                color: Theme.text
                font.pixelSize: Theme.fontSize(20)
                font.weight: Font.DemiBold
            }
            Text {
                objectName: "tableReconnectCountdown"
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: {
                    const remaining = root.tableController.wsModel
                                      .reconnectSecondsRemaining
                    if (!remaining || remaining <= 0)
                        return qsTranslate("Table", "Table actions are paused while reconnecting.")
                    const minutes = Math.floor(remaining / 60)
                    const seconds = remaining % 60
                    const time = minutes + ":"
                                 + (seconds < 10 ? "0" : "") + seconds
                    return qsTranslate("Table", "Table actions are paused · %1 remaining")
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
        readonly property var facePreview: root.tableController.presentation.facePreview
        readonly property var previewSize: faceGallery.fittedSize(Theme.size(250),
            parent.width - Theme.size(24), parent.height - Theme.size(24))
        readonly property bool previewHeld: previewHover.hovered
        width: previewSize.width
        height: previewSize.height
        z: 5000
        visible: !root.tableController.tableModalOpen && !root.tableController.wsModel.reconnecting
                 && root.tableController.hoverPreviewVisible
                 && !!root.tableController.inspectedCard.name
        enabled: visible && facePreview.canSwitch
        onPreviewHeldChanged: root.tableController.presentation.previewHeld = previewHeld
        opacity: visible ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.motionFast }
        }

        CardFacePreviewGallery {
            id: faceGallery
            objectName: "cardHoverPreviewFaces"
            controller: cardHoverPreview.facePreview
            anchors.fill: parent
            columns: cardHoverPreview.previewSize.columns
            artObjectName: "cardHoverPreviewArt"
            fallbackObjectName: "cardHoverPreviewName"
        }
        Image {
            objectName: "cardHoverPreviewHiddenArt"
            anchors.fill: parent
            visible: root.tableController.inspectedCard.faceDown === true
            source: visible ? root.tableController.cardBackSource : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
        Binding {
            target: root.tableController.presentation
            property: "hoverPreviewWidth"
            value: cardHoverPreview.width
        }
        Binding {
            target: root.tableController.presentation
            property: "hoverPreviewHeight"
            value: cardHoverPreview.height
        }
        HoverHandler { id: previewHover }
    }
}
