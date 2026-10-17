// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "SideboardPanel"

import QtQuick

Item {
    id: root

    required property var panel
    anchors.fill: parent
    readonly property real previewWidth: sideboardHoverPreview.width
    readonly property real previewHeight: sideboardHoverPreview.height
    onPreviewWidthChanged: if (root.panel.hoverPreviewVisible) root.panel.repositionSideboardCardPreview()
    onPreviewHeightChanged: if (root.panel.hoverPreviewVisible) root.panel.repositionSideboardCardPreview()

    function finishDrag() {
        dragPreview.Drag.drop()
    }

    Item {
        id: sideboardHoverPreview

        objectName: "sideboardHoverPreview"
        x: Math.max(Theme.size(12), Math.min(root.panel.hoverPreviewX,
                root.panel.width - width - Theme.size(12)))
        y: Math.max(Theme.size(12), Math.min(root.panel.hoverPreviewY,
                root.panel.height - height - Theme.size(12)))
        readonly property var previewSize: faceGallery.fittedSize(faceGallery.faceCount > 1
            ? Theme.size(320) : Math.min(Theme.size(320), root.panel.width * 0.25),
            root.panel.width - Theme.size(24), root.panel.height - Theme.size(24))
        width: previewSize.width
        height: previewSize.height
        z: 450
        visible: root.panel.hoverPreviewVisible
                 && root.panel.dragSource === null
                 && !!root.panel.inspectedCard.name
        opacity: visible ? 1 : 0

        onVisibleChanged: if (!visible) facePreview.resetFace()

        CardFacePreviewController {
            id: facePreview
            objectName: "sideboardFacePreviewController"
            catalogModel: root.panel.cardCatalogModel
            card: root.panel.inspectedCard
            sourceItem: root.panel.inspectedSourceItem
            active: sideboardHoverPreview.visible
        }

        HoverHandler {
            onHoveredChanged: root.panel.retainSideboardCardPreview(hovered)
        }

        Behavior on opacity {
            NumberAnimation { duration: Theme.motionFast }
        }

        CardFacePreviewGallery {
            id: faceGallery
            objectName: "sideboardHoverPreviewFaces"
            anchors.fill: parent
            controller: facePreview
            columns: sideboardHoverPreview.previewSize.columns
            artObjectName: "sideboardHoverPreviewArt"
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
