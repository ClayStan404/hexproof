// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic

Row {
    id: root
    property var manaPool: []
    property real unit: 1
    property int seat: -1
    spacing: 6 * unit
    visible: !!manaPool && (manaPool.length || manaPool.count || 0) > 0
    Accessible.name: qsTr("Unspent mana")
    Repeater {
        model: root.manaPool || []
        Row {
            id: entry
            required property var modelData
            objectName: "forgeMana-" + root.seat + "-" + modelData.color
            spacing: 2 * root.unit
            CardManaSymbol {
                symbol: entry.modelData.color
                width: 18 * root.unit
                height: width
            }
            Text {
                textFormat: Text.PlainText
                text: entry.modelData.amount
                color: Theme.text
                font.pixelSize: 13 * root.unit
                font.bold: true
            }
        }
    }
    HoverHandler { id: hover }
    ToolTip.visible: hover.hovered
    ToolTip.text: qsTr("Unspent mana")
}
