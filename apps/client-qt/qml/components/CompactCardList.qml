// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "CardWorkbench"
import QtQuick
import QtQuick.Controls.Basic

ListView {
    id: root
    property var cards: []
    property string cardObjectPrefix: "compactCard-"
    property string emptyText: qsTranslate("CardWorkbench", "No cards yet")
    property Item dropTarget: null
    signal cardActivated(var card)
    signal cardInspected(var card, var sourceItem)
    signal cardInspectionEnded(var sourceItem)
    signal cardDropped(var card)
    readonly property var rows: aggregate(cards)
    model: rows
    spacing: Theme.size(3)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { }
    Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        width: parent.width - Theme.size(20)
        text: root.emptyText
        visible: root.count === 0
        color: Theme.textMuted
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
    }
    delegate: CardListRow {
        id: row
        required property var modelData
        objectName: root.cardObjectPrefix + (modelData.card.instanceId || modelData.card.name)
        width: ListView.view.width - Theme.size(8)
        card: modelData.card
        quantity: modelData.count
        highlighted: hover.hovered
        opacity: drag.active ? 0.45 : 1
        TapHandler { onTapped: root.cardActivated(row.modelData.card) }
        DragHandler {
            id: drag
            enabled: root.dropTarget !== null
            target: null
            cursorShape: active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            onActiveChanged: {
                if (active) root.cardInspectionEnded(row)
                else if (root.dropTarget) {
                    const point = root.dropTarget.mapFromItem(null, centroid.scenePosition.x, centroid.scenePosition.y)
                    if (root.dropTarget.visible && point.x >= 0 && point.y >= 0
                            && point.x <= root.dropTarget.width && point.y <= root.dropTarget.height)
                        root.cardDropped(row.modelData.card)
                }
            }
        }
        CardListRow {
            parent: Overlay.overlay
            visible: drag.active
            enabled: false
            z: 1000
            width: row.width
            height: row.height
            card: row.card
            quantity: 1
            highlighted: true
            readonly property point position: parent
                ? parent.mapFromItem(null, drag.centroid.scenePosition.x, drag.centroid.scenePosition.y) : Qt.point(0, 0)
            x: position.x + Theme.size(12)
            y: position.y + Theme.size(12)
        }
        HoverHandler {
            id: hover
            onHoveredChanged: {
                if (hovered && !drag.active) root.cardInspected(row.modelData.card, row)
                else root.cardInspectionEnded(row)
            }
        }
        Accessible.role: Accessible.Button
        Accessible.name: modelData.count + " " + (modelData.card.displayName || modelData.card.name)
        Accessible.onPressAction: root.cardActivated(modelData.card)
    }
    function aggregate(cards) {
        const grouped = new Map()
        for (const card of cards) {
            // Never merge different printings or virtual basics into a physical row.
            const key = JSON.stringify([card.name, card.setCode || "", card.collectorNumber || "", !!card.virtualBasic,
                                        !!card.fallbackCommander, card.commanderColor || ""])
            const existing = grouped.get(key)
            if (existing) existing.count += Number(card.count || 1)
            else grouped.set(key, {card: card, count: Number(card.count || 1)})
        }
        return Array.from(grouped.values()).sort((left, right) => {
            const a = left.card, b = right.card
            const landA = /land|地/i.test(String(a.typeLine || "").split(/[—–]/)[0]) ? 1 : 0
            const landB = /land|地/i.test(String(b.typeLine || "").split(/[—–]/)[0]) ? 1 : 0
            return landA - landB || Number(a.manaValue || 0) - Number(b.manaValue || 0)
                    || String(a.name).localeCompare(String(b.name))
                    || String(a.setCode || "").localeCompare(String(b.setCode || ""))
                    || String(a.collectorNumber || "").localeCompare(String(b.collectorNumber || ""))
        })
    }
}
