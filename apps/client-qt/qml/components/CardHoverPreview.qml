// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import "TokenPresentation.js" as TokenPresentation

Item {
    id: root
    required property var catalogModel
    property var card: ({})
    property var sourceItem: null
    property bool tokenArt: false
    readonly property string cardLanguage: tokenArt && catalogModel ? catalogModel.language || "en" : ""
    onCardLanguageChanged: if (tokenArt && visible) TokenPresentation.prioritize(catalogModel, card)
    readonly property var tokenDetails: TokenPresentation.details(tokenArt ? catalogModel : null, card)
    onSourceItemChanged: if (!sourceItem) visible = false
    property string artObjectName: "cardHoverPreviewArt"
    width: Math.max(1, Math.min(Theme.size(380), parent.width * 0.55, (parent.height - Theme.size(24)) * 63 / 88))
    height: width * 88 / 63
    visible: false
    enabled: false
    z: 1000
    Image {
        id: art
        objectName: root.artObjectName
        anchors.fill: parent
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        source: {
            if (!root.visible || !root.card.name || !root.catalogModel) return ""
            void root.catalogModel.imageRevision
            if (root.tokenArt) void root.catalogModel.language
            return root.tokenArt
                    ? root.catalogModel.tokenImageSource(root.card.name, root.card.setCode || "", root.card.collectorNumber || "")
                    : root.catalogModel.imageSource(root.card.name, root.card.setCode || "", root.card.collectorNumber || "")
        }
    }
    Rectangle {
        anchors.fill: parent
        color: Theme.backgroundRaised
        border.color: Theme.accent
        radius: Theme.radiusMedium
        visible: art.status !== Image.Ready
        Text {
            textFormat: Text.PlainText
            objectName: "cardHoverPreviewFallbackText"
            anchors.centerIn: parent
            width: parent.width - Theme.size(24)
            height: parent.height - Theme.size(24)
            text: root.tokenArt ? TokenPresentation.fullText(root.tokenDetails)
                  : [root.card.displayName || root.card.name || "", root.card.typeLine || ""].join("\n\n")
            color: Theme.text
            font.pixelSize: Theme.fontSize(17)
            fontSizeMode: Text.Fit
            minimumPixelSize: Theme.fontSize(11)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            clip: true
        }
    }
    function inspect(value, item) {
        if (!value || !value.name || !item) return
        if (tokenArt) TokenPresentation.prioritize(catalogModel, value)
        card = value
        sourceItem = item
        const origin = item.mapToItem(parent, 0, 0)
        const right = origin.x + item.width + Theme.size(12)
        x = Math.max(0, Math.min(parent.width - width, right + width <= parent.width ? right : origin.x - width - Theme.size(12)))
        y = Math.max(0, Math.min(parent.height - height, origin.y))
        visible = true
    }
    function hide(item) {
        if (item && sourceItem && item !== sourceItem) return
        visible = false
        sourceItem = null
    }
}
