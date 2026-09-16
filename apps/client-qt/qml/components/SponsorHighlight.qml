// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window

Rectangle {
    id: root

    objectName: "sponsorHighlight"
    radius: Theme.radiusLarge
    border.width: 1
    border.color: "#AB8C58"
    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: "#30352D" }
        GradientStop { position: 0.55; color: "#1B3437" }
        GradientStop { position: 1; color: "#302C40" }
    }
    Accessible.ignored: true

    Rectangle {
        id: halo
        objectName: "sponsorHighlightGlow"
        anchors.fill: parent
        anchors.margins: Theme.size(3)
        radius: Math.max(0, root.radius - Theme.size(3))
        color: "transparent"
        border.width: 1
        border.color: "#F2D49B"
        opacity: 0.35
    }

    // Animate only the decorative light, never the card's geometry or text.
    SequentialAnimation {
        running: root.visible && root.Window.active
        loops: Animation.Infinite
        NumberAnimation {
            target: halo; property: "opacity"; from: 0.35; to: 0.85
            duration: 2600; easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: halo; property: "opacity"; from: 0.85; to: 0.35
            duration: 2600; easing.type: Easing.InOutSine
        }
    }

    Repeater {
        model: [{x:0.72, y:0.20, size:12}, {x:0.85, y:0.65, size:20}, {x:0.94, y:0.26, size:10}]
        delegate: Text {
            required property var modelData
            x: root.width * modelData.x
            y: root.height * modelData.y - height / 2
            textFormat: Text.PlainText
            text: "✦"
            color: "#E6D5AE"
            opacity: 0.15
            font.pixelSize: Theme.fontSize(modelData.size)
        }
    }
}
