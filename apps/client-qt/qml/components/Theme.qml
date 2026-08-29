// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma Singleton

import QtQuick

QtObject {
    property real uiScale: 1.0

    function automaticScale(viewportWidth, viewportHeight) {
        return Math.max(1.0, Math.min(1.35,
            Math.min(viewportWidth / 1280, viewportHeight / 800)))
    }

    function effectiveScale(viewportWidth, viewportHeight, interfaceScale) {
        return Math.max(0.75, Math.min(1.8,
            automaticScale(viewportWidth, viewportHeight) * interfaceScale))
    }

    readonly property int compactWidthThreshold: 1100

    function isCompactWidth(viewportWidth) {
        return viewportWidth < compactWidthThreshold
    }

    function size(value) { return Math.round(value * uiScale) }
    function fontSize(value) { return Math.round(value * uiScale) }

    readonly property color background: "#08110E"
    readonly property color backgroundRaised: "#0C1713"
    readonly property color surface: "#101D18"
    readonly property color surfaceHover: "#152721"
    readonly property color surfaceElevated: "#172720"
    readonly property color surfaceMuted: "#0D1815"
    readonly property color disabled: "#17201D"

    readonly property color border: "#253B33"
    readonly property color borderStrong: "#37594B"
    readonly property color divider: "#1C3029"
    readonly property color badgeBackground: "#F20B1512"
    readonly property color badgeBorder: "#66FFFFFF"
    readonly property color modalScrim: "#E608130F"
    readonly property color inactiveSelection: "#E60B1512"

    readonly property color primary: "#7DE2B8"
    readonly property color primaryStrong: "#55C996"
    readonly property color primaryMuted: "#1A3E31"
    readonly property color primaryInk: "#07130F"
    readonly property color accent: "#E0BD78"
    readonly property color accentMuted: "#3B321F"

    readonly property color text: "#F2F6F2"
    readonly property color textSecondary: "#B5C3BD"
    readonly property color textMuted: "#7F9189"
    readonly property color textDisabled: "#52625C"

    readonly property color success: "#75D8A7"
    readonly property color warning: "#E8C477"
    readonly property color error: "#FF8589"
    readonly property color errorMuted: "#3C2022"

    readonly property int radiusSmall: size(8)
    readonly property int radiusMedium: size(12)
    readonly property int radiusLarge: size(20)
    readonly property int controlHeight: size(48)
    readonly property int pageMargin: size(32)

    readonly property int motionFast: 120
    readonly property int motionNormal: 220
    readonly property int motionSlow: 360
}
