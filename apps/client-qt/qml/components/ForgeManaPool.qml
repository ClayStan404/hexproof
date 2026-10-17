// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic

Rectangle {
    id: root
    property var manaPool: []
    property real unit: 1
    property int seat: -1
    // Zero preserves the original single row. Compact seat headers can fit
    // all six ordinary colors in two rows without changing the field height.
    property int maximumColumns: 0
    implicitWidth: entries.implicitWidth + 16 * unit
    implicitHeight: entries.implicitHeight + 10 * unit
    radius: 6 * unit
    color: Theme.surfaceElevated
    border.color: Theme.borderStrong
    visible: !!manaPool && (manaPool.length || manaPool.count || 0) > 0
    Accessible.name: qsTr("Unspent mana")
    Grid {
        id: entries
        anchors.centerIn: parent
        columns: root.maximumColumns > 0 ? root.maximumColumns : Math.max(1, poolEntries.count)
        columnSpacing: 6 * root.unit
        rowSpacing: 4 * root.unit
        Repeater {
            id: poolEntries
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
    }
    HoverHandler { id: hover }
    ToolTip.visible: hover.hovered
    ToolTip.text: qsTr("Unspent mana")
}
