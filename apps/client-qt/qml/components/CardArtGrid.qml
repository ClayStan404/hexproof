// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "CardWorkbench"
import QtQuick
import QtQuick.Controls.Basic

GridView {
    id: root
    property var cards: []
    required property var catalogModel
    property string selectedKey: ""
    property var selectedKeys: []
    property bool doubleClickEnabled: false
    property string cardObjectPrefix: "workbenchCard-"
    property real preferredCardWidth: Theme.size(205)
    property real maximumCardWidth: Theme.size(250)
    property string emptyText: qsTranslate("CardWorkbench", "No cards match the current filters.")
    signal cardActivated(var card)
    signal cardDoubleActivated(var card)
    signal cardInspected(var card, var sourceItem)
    signal cardInspectionEnded(var sourceItem)
    readonly property int columns: Math.max(1, Math.floor(width / (preferredCardWidth + Theme.size(14))))
    readonly property real artWidth: Math.max(1, Math.min(maximumCardWidth, cellWidth - Theme.size(16)))
    model: cards
    cellWidth: Math.max(1, width / columns)
    cellHeight: artWidth * 88 / 63 + Theme.size(26)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    cacheBuffer: cellHeight
    ScrollBar.vertical: ScrollBar { }
    Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        width: parent.width - Theme.size(24)
        visible: root.count === 0
        text: root.emptyText
        color: Theme.textMuted
        font.pixelSize: Theme.fontSize(14)
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
    }
    delegate: Item {
        id: tile
        required property var modelData
        width: root.cellWidth
        height: root.cellHeight
        LimitedCardTile {
            id: art
            objectName: root.cardObjectPrefix + (tile.modelData.instanceId || tile.modelData.name)
            width: root.artWidth
            height: width * 88 / 63
            anchors.horizontalCenter: parent.horizontalCenter
            card: tile.modelData
            catalogModel: root.catalogModel
            showFooter: false
            doubleClickEnabled: root.doubleClickEnabled
            emphasized: (!!root.selectedKey && root.selectedKey === (tile.modelData.instanceId || tile.modelData.name))
                        || root.selectedKeys.indexOf(tile.modelData.instanceId || tile.modelData.name) >= 0
            onActivated: root.cardActivated(tile.modelData)
            onDoubleActivated: root.cardDoubleActivated(tile.modelData)
            onInspectionRequested: root.cardInspected(tile.modelData, art)
            onInspectionEnded: root.cardInspectionEnded(art)
        }
        Row {
            anchors.top: art.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: art.width
            height: Theme.size(22)
            spacing: Theme.size(4)
            Text {
                textFormat: Text.PlainText
                text: "◆"
                color: art.rarity === "common" ? Theme.textSecondary : art.rarityColor()
                width: Theme.size(10)
                height: parent.height
                font.pixelSize: Theme.fontSize(10)
                verticalAlignment: Text.AlignVCenter
            }
            Text {
                textFormat: Text.PlainText
                width: Math.max(0, parent.width - Theme.size(14))
                height: parent.height
                text: tile.modelData.displayName || tile.modelData.name || ""
                color: Theme.textSecondary
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSize(10)
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
