// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
import QtQuick

Rectangle {
    id: root
    property string symbol: ""
    readonly property var parts: symbol.split("/")
    readonly property bool phyrexian: parts.length > 1 && parts[parts.length - 1] === "P"
    readonly property bool hybrid: parts.length === (phyrexian ? 3 : 2)
    readonly property var glyphParts: hybrid
        ? (phyrexian ? ["P", "P"] : parts) : [phyrexian ? "P" : symbol]
    implicitWidth: Theme.size(symbol === "//" ? 14 : 22)
    implicitHeight: Theme.size(22)
    radius: width / 2
    color: symbol === "//" ? "transparent" : ManaSymbols.tint(parts[0])
    border.width: symbol === "//" ? 0 : Math.max(1, Theme.size(1))
    border.color: "#252724"
    Accessible.name: symbol

    Canvas {
        id: splitBackground
        anchors.fill: parent
        anchors.margins: root.border.width
        visible: root.hybrid
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: root
            function onSymbolChanged() { splitBackground.requestPaint() }
        }
        onPaint: {
            const context = getContext("2d")
            context.reset()
            if (!root.hybrid) return
            context.fillStyle = ManaSymbols.tint(root.parts[1])
            context.beginPath()
            // The lower-right half of a diagonally divided hybrid mana disc.
            context.arc(width / 2, height / 2, width / 2, -Math.PI / 4, 3 * Math.PI / 4)
            context.closePath()
            context.fill()
        }
    }
    Repeater {
        model: root.glyphParts
        Text {
            required property string modelData
            required property int index
            textFormat: Text.PlainText
            objectName: "manaGlyph-" + index
            readonly property string glyph: ManaSymbols.glyph(modelData)
            text: glyph || modelData
            font.family: glyph ? ManaSymbols.name : "sans-serif"
            font.pixelSize: Math.round(root.height * (root.hybrid ? 0.46 : 0.72))
            font.bold: !glyph
            color: "#141613"
            width: root.width * (root.hybrid ? 0.62 : 1)
            height: root.height * (root.hybrid ? 0.62 : 1)
            x: root.hybrid && index === 1 ? root.width - width : 0
            y: root.hybrid && index === 1 ? root.height - height : 0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
