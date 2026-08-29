// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: root
    clip: true

    Rectangle {
        anchors.fill: parent
        color: Theme.background
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Theme.background }
            GradientStop { position: 0.62; color: Theme.backgroundRaised }
            GradientStop { position: 1.0; color: "#0B1B15" }
        }
    }

    Rectangle {
        width: Math.max(520, root.width * 0.52)
        height: width
        radius: width / 2
        x: root.width - width * 0.62
        y: -height * 0.58
        color: "#0D4B37"
        opacity: 0.18
    }

    Rectangle {
        width: Math.max(360, root.width * 0.34)
        height: width
        radius: width / 2
        x: -width * 0.48
        y: root.height - height * 0.42
        color: "#755B2B"
        opacity: 0.07
    }

    Rectangle {
        width: 250
        height: 356
        radius: 22
        x: root.width - 162
        y: root.height * 0.43
        rotation: 13
        color: "transparent"
        border.width: 1
        border.color: "#217557"
        opacity: 0.14
    }

    Rectangle {
        width: 220
        height: 314
        radius: 20
        x: root.width - 255
        y: root.height * 0.56
        rotation: -5
        color: "transparent"
        border.width: 1
        border.color: Theme.accent
        opacity: 0.07
    }
}
