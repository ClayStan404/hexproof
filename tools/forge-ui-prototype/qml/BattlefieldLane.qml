// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick
import QtQuick.Controls.Basic

Item {
    id: root
    required property var cards
    property string assetRoot: ""
    property real unit: 1
    property bool dense: false
    property string caption: ""
    property var actionableIds: []
    property var selectedIds: []
    property var tappedIds: []
    property var statusLabels: ({})
    property string actionHint: ""
    signal activated(var card)
    signal inspected(var card)
    signal previewed(var card)
    signal previewEnded()
    readonly property real gap: (dense ? 12 : 16) * unit
    readonly property real cardWidth: dense ? 108 * unit
        : Math.min(180 * unit, (width - Math.max(0, cards.length - 1) * gap) / Math.max(1, cards.length))
    readonly property real cardHeight: cardWidth * 0.93
    readonly property int columns: dense ? Math.max(1, Math.floor((width - 14 * unit + gap) / (cardWidth + gap))) : Math.max(1, cards.length)
    readonly property real cellHeight: cardHeight + (dense ? 10 * unit : 0)
    readonly property real headerHeight: dense ? 18 * unit : 0
    readonly property real padding: dense ? 4 * unit : 0
    readonly property real scrollOffset: viewport.contentY
    readonly property Item scrollArea: viewport
    height: headerHeight + (dense ? 2 * cellHeight + 8 * unit : cardHeight)

    function itemFor(id) {
        for (let i = 0; i < cards.length; ++i) {
            if (cards[i].id === id) return repeater.itemAt(i)
        }
        return null
    }
    function isCardVisible(id) {
        const item = itemFor(id)
        return !!item && (!dense || (item.y >= viewport.contentY
            && item.y + item.height <= viewport.contentY + viewport.height))
    }
    function reveal(id) {
        const item = itemFor(id)
        if (!item) return false
        if (dense) viewport.contentY = Math.max(0, Math.min(item.y - padding,
            Math.max(0, viewport.contentHeight - viewport.height)))
        return true
    }
    onCardsChanged: viewport.contentY = 0
    StudyLabel {
        visible: root.dense
        text: root.caption + "  /  " + root.cards.length
        pointSize: 9
        font.letterSpacing: 1
        unit: root.unit
        color: "#9cafb8"
    }
    Flickable {
        id: viewport
        y: root.headerHeight
        width: root.width
        height: root.height - y
        clip: root.dense
        interactive: root.dense && contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: Math.ceil(root.cards.length / root.columns) * root.cellHeight + 2 * root.padding
        ScrollBar.vertical: ScrollBar {
            objectName: root.objectName + "Scroll"
            policy: root.dense ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        }
        Repeater {
            id: repeater
            model: root.cards
            delegate: StudyCard {
                required property var modelData
                required property int index
                x: root.dense ? root.padding + (index % root.columns) * (root.cardWidth + root.gap)
                    : (root.width - (root.cards.length * root.cardWidth + Math.max(0, root.cards.length - 1) * root.gap)) / 2
                        + index * (root.cardWidth + root.gap)
                y: root.padding + Math.floor(index / root.columns) * root.cellHeight
                width: root.cardWidth
                height: root.cardHeight
                card: modelData
                unit: root.unit
                assetRoot: root.assetRoot
                actionable: root.actionableIds.indexOf(card.id) >= 0
                selected: root.selectedIds.indexOf(card.id) >= 0
                tapped: root.tappedIds.indexOf(card.id) >= 0
                actionHint: root.actionHint
                statusText: root.statusLabels[card.id] || ""
                showActionHint: !root.dense
                onActiveFocusChanged: if (activeFocus) root.reveal(card.id)
                onActivated: root.activated(card)
                onInspected: card => root.inspected(card)
                onPreviewed: card => root.previewed(card)
                onPreviewEnded: root.previewEnded()
            }
        }
    }
}
