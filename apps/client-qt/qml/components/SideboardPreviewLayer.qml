// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "SideboardPanel"

import QtQuick

Item {
    id: root

    required property var panel
    anchors.fill: parent

    function finishDrag() {
        dragPreview.Drag.drop()
    }

    Item {
        id: sideboardHoverPreview

        objectName: "sideboardHoverPreview"
        x: root.panel.hoverPreviewX
        y: root.panel.hoverPreviewY
        width: Math.min(Theme.size(320), root.panel.width * 0.25)
        height: Math.round(width * 88 / 63)
        z: 450
        visible: root.panel.hoverPreviewVisible
                 && root.panel.dragSource === null
                 && !!root.panel.inspectedCard.name
        enabled: false
        opacity: visible ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.motionFast }
        }

        Image {
            id: sideboardHoverPreviewArt

            objectName: "sideboardHoverPreviewArt"
            anchors.fill: parent
            source: root.panel.cardImageSource(root.panel.inspectedCard)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
        }

        Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            width: parent.width - Theme.size(20)
            visible: sideboardHoverPreviewArt.status !== Image.Ready
            text: root.panel.inspectedCard.name
                  ? root.panel.inspectedCard.name : ""
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(14)
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }
    }

    Surface {
        id: dragPreview

        z: 500
        visible: root.panel.dragSource !== null
        width: root.panel.dragSource
               ? Math.max(Theme.size(72),
                          Math.min(root.panel.dragSource.width,
                                   Theme.size(150)))
               : Theme.size(96)
        height: width * 88 / 63
        x: Math.max(0, Math.min(root.panel.width - width,
                               root.panel.dragPosition.x - width / 2))
        y: Math.max(0, Math.min(root.panel.height - height,
                               root.panel.dragPosition.y - height / 2))
        color: Theme.surfaceElevated
        border.width: Theme.size(2)
        border.color: Theme.primary
        elevated: true
        opacity: 0.94
        clip: true

        Drag.active: root.panel.dragSource !== null
        Drag.source: root.panel.dragSource
        Drag.keys: ["hexproof/sideboard-card"]
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2

        Image {
            id: dragPreviewArt
            anchors.fill: parent
            source: root.panel.tableCardImageSource(root.panel.dragCard)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }

        Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Theme.size(6)
            visible: dragPreviewArt.status !== Image.Ready
            text: root.panel.dragCard.name ? root.panel.dragCard.name : ""
            color: Theme.text
            font.pixelSize: Theme.fontSize(10)
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
