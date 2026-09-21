// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
import QtQuick

Rectangle {
    id: root
    required property var tableController
    required property var inspector
    readonly property var sourceItem: inspector.previewSource
    objectName: "rulesCardHoverPreview"
    readonly property bool hasLinkedSummary: inspector.exiledSummary.length > 0
    readonly property real linkedBand: hasLinkedSummary ? linkedCards.implicitHeight + Theme.size(10) : 0
    width: Math.min(Theme.size(360), parent.width * 0.42, (parent.height - Theme.size(32)) * 63 / 88)
    height: Math.min(parent.height - Theme.size(24), width * 88 / 63 + linkedBand)
    radius: Theme.radiusMedium
    color: Theme.surfaceElevated
    border.color: Theme.primary
    clip: true
    enabled: false
    z: 1000
    visible: inspector.previewCardId.length > 0 && inspector.hasCard && !!sourceItem
        && tableController.roomConnected && !tableController.sideboarding
        && !tableController.priorityInputBlocked

    function reposition() {
        if (!sourceItem || !parent) return
        const gap = Theme.size(12)
        const origin = sourceItem.mapToItem(parent, 0, 0)
        const right = origin.x + sourceItem.width + gap
        const left = origin.x - width - gap
        const maxX = parent.width - width - gap
        const maxY = parent.height - height - gap
        const above = origin.y - height - gap
        let nextX = right <= maxX ? right : Math.max(gap, Math.min(maxX, left))
        let nextY = Math.max(gap, Math.min(maxY, origin.y))
        const overlaps = nextX < origin.x + sourceItem.width && nextX + width > origin.x
            && nextY < origin.y + sourceItem.height && nextY + height > origin.y
        if ((overlaps || origin.y + sourceItem.height > parent.height * 0.72) && above >= gap) {
            nextY = above
            nextX = Math.max(gap, Math.min(maxX, origin.x))
        }
        x = nextX
        y = nextY
    }
    onVisibleChanged: if (visible) reposition()
    // The source can move through a fan animation, layout or scroll without
    // receiving a new hover event. Keep its adjacent preview inside the window.
    FrameAnimation { running: root.visible; onTriggered: root.reposition() }
    Image {
        id: artwork
        objectName: "rulesCardHoverPreviewArt"
        width: parent.width
        height: width * 88 / 63
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        source: {
            if (!root.visible) return ""
            if (!root.inspector.hasIdentity) return root.tableController.cardBackSource
            const catalog = root.tableController.cardCatalogModel
            if (!catalog || typeof catalog.imageSource !== "function") return ""
            void catalog.imageRevision
            const card = root.inspector.card
            return catalog.imageSource(card.name, card.setCode || "", card.collectorNumber || "")
        }
    }
    Text {
        id: linkedCards
        objectName: "rulesCardHoverLinkedCards"
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.size(6)
        visible: root.hasLinkedSummary
        text: root.inspector.exiledSummary
        color: Theme.text
        font.pixelSize: Theme.fontSize(12)
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
    }
    Text {
        objectName: "rulesCardHoverPreviewFallback"
        textFormat: Text.PlainText
        anchors.fill: parent
        anchors.margins: Theme.size(18)
        visible: artwork.status !== Image.Ready
        text: root.inspector.hasIdentity
            ? [typeof root.tableController.cardDisplayName === "function"
               ? root.tableController.cardDisplayName(root.inspector.card.name)
               : root.inspector.card.name,
               root.inspector.card.rulesText || ""].filter(v => v.length).join("\n\n")
            : qsTranslate("ForgeCard", "Hidden card")
        color: Theme.text
        font.pixelSize: Theme.fontSize(18)
        fontSizeMode: Text.Fit
        minimumPixelSize: Theme.fontSize(11)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
    }
}
