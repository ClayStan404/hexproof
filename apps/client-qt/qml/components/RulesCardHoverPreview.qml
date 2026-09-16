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
    width: Math.min(Theme.size(360), parent.width * 0.42, (parent.height - Theme.size(32)) * 63 / 88)
    height: width * 88 / 63
    radius: Theme.radiusMedium
    color: Theme.surfaceElevated
    border.color: Theme.primary
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
        x = Math.max(gap, Math.min(parent.width - width - gap,
            right + width <= parent.width - gap ? right : origin.x - width - gap))
        y = Math.max(gap, Math.min(parent.height - height - gap, origin.y))
    }
    onVisibleChanged: if (visible) reposition()
    // The source can move through a fan animation, layout or scroll without
    // receiving a new hover event. Keep its adjacent preview inside the window.
    FrameAnimation { running: root.visible; onTriggered: root.reposition() }
    Image {
        id: artwork
        objectName: "rulesCardHoverPreviewArt"
        anchors.fill: parent
        anchors.margins: 2
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
        objectName: "rulesCardHoverPreviewFallback"
        textFormat: Text.PlainText
        anchors.fill: parent
        anchors.margins: Theme.size(18)
        visible: artwork.status !== Image.Ready
        text: root.inspector.hasIdentity
            ? [root.inspector.card.name, root.inspector.card.rulesText || ""].filter(v => v.length).join("\n\n")
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
