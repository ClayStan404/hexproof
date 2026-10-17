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
    implicitWidth: entries.implicitWidth + 16 * unit
    implicitHeight: entries.implicitHeight + 10 * unit
    radius: 6 * unit
    color: Theme.surfaceElevated
    border.color: Theme.borderStrong
    visible: !!manaPool && (manaPool.length || manaPool.count || 0) > 0
    Accessible.name: qsTr("Unspent mana")
    Row {
        id: entries
        anchors.centerIn: parent
        spacing: 6 * root.unit
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
    }
    HoverHandler { id: hover }
    ToolTip.visible: hover.hovered
    ToolTip.text: qsTr("Unspent mana")
}
