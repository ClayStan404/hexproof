// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "CardWorkbench"
import QtQuick
import QtQuick.Controls.Basic

Row {
    id: root
    property var cards: []
    readonly property var buckets: buildBuckets()
    readonly property int largest: Math.max(1, ...buckets)
    spacing: Theme.size(2)
    height: Theme.size(42)
    Repeater {
        model: 8
        delegate: Item {
            id: bucket
            required property int index
            width: Theme.size(10)
            height: root.height
            Rectangle {
                width: parent.width
                anchors.bottom: label.top
                height: Math.max(1, (parent.height - Theme.size(14)) * root.buckets[bucket.index] / root.largest)
                color: Theme.accent
            }
            Text {
                textFormat: Text.PlainText
                id: label
                anchors.bottom: parent.bottom
                text: bucket.index === 7 ? "7+" : bucket.index
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(8)
            }
            ToolTip.visible: hover.hovered
            ToolTip.text: qsTranslate("CardWorkbench", "Mana value %1: %2 cards").arg(index === 7 ? "7+" : index).arg(root.buckets[index])
            HoverHandler { id: hover }
        }
    }
    function buildBuckets() {
        const values = [0,0,0,0,0,0,0,0]
        for (const card of cards) {
            const type = String(card.typeLine || "").split(/[—–]/)[0]
            if (card.manaValue === undefined || card.manaValue < 0 || /land|地/i.test(type)) continue
            values[Math.min(7, Math.floor(Number(card.manaValue)))] += Number(card.count || 1)
        }
        return values
    }
}
