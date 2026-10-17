// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    required property var controller
    property string artObjectName: "cardHoverPreviewArt"
    property string fallbackObjectName: "cardHoverPreviewFallbackText"
    property var imageSourceResolver: null
    property int columns: 0
    property real gap: Theme.size(8)
    property real minimumFaceWidth: Theme.size(180)
    readonly property var displayFaces: controller ? controller.displayFaces || [] : []
    readonly property int faceCount: displayFaces.length
    readonly property int columnCount: columns > 0 ? Math.min(columns, Math.max(1, faceCount))
        : faceCount > 1 && width >= 2 * minimumFaceWidth + gap ? 2 : 1
    readonly property int rowCount: Math.ceil(Math.max(1, faceCount) / columnCount)
    readonly property real faceWidth: Math.max(0, (width - (columnCount - 1) * gap) / columnCount)
    readonly property real aspectRatio: implicitHeight > 0 ? width / implicitHeight : 63 / 88
    implicitHeight: rowCount * faceWidth * 88 / 63 + (rowCount - 1) * gap

    function fittedSize(maxFaceWidth, availableWidth, availableHeight) {
        const count = Math.max(1, faceCount)
        const widthLimit = Math.max(0, availableWidth)
        const heightLimit = Math.max(0, availableHeight)
        const cols = faceCount > 1 && widthLimit >= 2 * minimumFaceWidth + gap ? 2 : 1
        const rows = Math.ceil(count / cols)
        const cardWidth = Math.max(0, Math.min(maxFaceWidth,
            (widthLimit - (cols - 1) * gap) / cols,
            (heightLimit - (rows - 1) * gap) * 63 / 88 / rows))
        return {width: cardWidth * cols + (cols - 1) * gap,
                height: cardWidth * 88 / 63 * rows + (rows - 1) * gap, columns: cols}
    }
    function faceArt(index) {
        const item = faceRepeater.itemAt(index) as FaceItem
        return item ? item.art : null
    }

    component FaceItem: Item {
        id: faceItem
        required property int index
        readonly property var face: root.displayFaces[index] || ({})
        objectName: "cardPreviewFace-" + index
        width: root.faceWidth
        height: width * 88 / 63
        property alias art: faceImage
        Image {
            id: faceImage
            objectName: faceItem.index === 0 ? root.artObjectName : root.artObjectName + "-" + faceItem.index
            anchors.fill: parent
            source: typeof root.imageSourceResolver === "function"
                ? root.imageSourceResolver(faceItem.face) || "" : faceItem.face.imageSource || ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            sourceSize: Qt.size(Math.max(1, Math.ceil(width * Screen.devicePixelRatio)),
                                Math.max(1, Math.ceil(height * Screen.devicePixelRatio)))
        }
        Rectangle {
            anchors.fill: parent
            visible: faceImage.status !== Image.Ready
            color: Theme.surfaceElevated
            radius: Theme.radiusSmall
            border.color: Theme.border
            Text {
                objectName: faceItem.index === 0 ? root.fallbackObjectName : root.fallbackObjectName + "-" + faceItem.index
                anchors.fill: parent
                anchors.margins: Theme.size(12)
                text: faceItem.face.fallbackText || faceItem.face.displayName || faceItem.face.name || ""
                textFormat: Text.PlainText
                color: Theme.text
                font.pixelSize: Theme.fontSize(15)
                fontSizeMode: Text.Fit
                minimumPixelSize: Theme.fontSize(10)
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                clip: true
            }
        }
    }

    Grid {
        width: root.width
        columns: root.columnCount
        spacing: root.gap
        Repeater {
            id: faceRepeater
            // Keep image delegates alive when cache revisions update sources.
            // Only the face count changes the presentation item model.
            model: root.faceCount
            delegate: FaceItem {}
        }
    }
}
