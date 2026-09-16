// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick

Item {
    id: root
    required property var cards
    property string assetRoot: ""
    property real unit: 1
    property real maxCardWidth: 180 * unit
    property bool lands: false
    property var actionableIds: []
    property var tappedIds: []
    property string selectedId: ""
    property var selectedIds: []
    property string actionHint: ""
    signal activated(var card)
    signal inspected(var card)
    signal previewed(var card)
    signal previewEnded()
    readonly property real gap: (lands ? 10 : 16) * unit
    readonly property real cardWidth: Math.min(maxCardWidth, (width - Math.max(0, cards.length - 1) * gap) / Math.max(1, cards.length))
    readonly property real totalWidth: cards.length * cardWidth + Math.max(0, cards.length - 1) * gap
    height: cardWidth * (lands ? 0.82 : 0.93)

    function itemFor(id) {
        for (let i = 0; i < cards.length; ++i) {
            if (cards[i].id === id) return repeater.itemAt(i)
        }
        return null
    }

    Repeater {
        id: repeater
        model: root.cards
        delegate: StudyCard {
            required property var modelData
            required property int index
            x: (root.width - root.totalWidth) / 2 + index * (root.cardWidth + root.gap)
            y: 0
            width: root.cardWidth
            height: root.height
            card: modelData
            assetRoot: root.assetRoot
            unit: root.unit
            actionable: root.actionableIds.indexOf(card.id) >= 0
            selected: root.selectedId === card.id || root.selectedIds.indexOf(card.id) >= 0
            tapped: root.tappedIds.indexOf(card.id) >= 0
            actionHint: root.actionHint
            onActivated: root.activated(card)
            onInspected: card => root.inspected(card)
            onPreviewed: card => root.previewed(card)
            onPreviewEnded: root.previewEnded()
        }
    }
}
