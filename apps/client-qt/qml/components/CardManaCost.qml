// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic

Item {
    id: root
    property var cost: undefined
    readonly property var symbols: cost === undefined ? ["?"]
        : (String(cost).match(/\{[^}]+\}|\/\//g) || []).slice(0, 32)
            .map(token => token.replace(/[{}]/g, ""))
    implicitWidth: glyphs.implicitWidth
    implicitHeight: Theme.size(22)
    Accessible.name: cost === undefined ? "?" : String(cost)
    Row {
        id: glyphs
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.size(2)
        scale: Math.min(1, root.width / Math.max(1, implicitWidth))
        transformOrigin: Item.Right
        Repeater {
            model: root.symbols
            CardManaSymbol {
                required property string modelData
                objectName: "manaSymbol-" + modelData
                symbol: modelData
            }
        }
    }
    HoverHandler { id: hover }
    ToolTip.visible: hover.hovered && root.cost !== undefined
    ToolTip.text: String(root.cost || "")
}
