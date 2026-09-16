// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma Singleton

import QtQuick

QtObject {
    property real uiScale: 1.0
    property string uiTheme: "classic"
    property Item backdropBlur: null
    property Item backdropScene: null

    readonly property bool useGlass: uiTheme === "glass"

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

    function withAlpha(base, alpha) {
        // A neutral factor coerces string colors on every supported Qt version.
        const resolved = Qt.darker(base, 1.0)
        return Qt.rgba(resolved.r, resolved.g, resolved.b, alpha)
    }

    readonly property color playmatFelt: "#1A1610"
    readonly property color playmatWell: "#12100C"
    readonly property color playmatRail: "#1C1814"
    readonly property color playmatStitch: "#4A3A28"
    readonly property color playmatLamp: "#E0C48A"
    readonly property color playmatLeather: "#4A3422"
    readonly property color tableRailFill: useGlass ? withAlpha("#0A0806", 0.55)
                                           : surfaceMuted
    readonly property color tableHandFill: useGlass ? withAlpha("#0A0806", 0.50)
                                           : surfaceMuted
    readonly property color tableDivider: useGlass ? playmatStitch : borderStrong

    property color background: "#08110E"
    property color backgroundRaised: "#0C1713"
    property color surface: "#101D18"
    property color surfaceHover: "#152721"
    property color surfaceElevated: "#172720"
    property color surfaceMuted: "#0D1815"
    property color disabled: "#17201D"

    property color border: "#253B33"
    property color borderStrong: "#37594B"
    property color divider: "#1C3029"
    property color badgeBackground: "#F20B1512"
    property color badgeBorder: "#66FFFFFF"
    property color modalScrim: "#E608130F"
    property color inactiveSelection: "#E60B1512"

    property color glass: "#1FFFFFFF"
    property color glassElevated: "#2EFFFFFF"
    property color glassBorder: "#3DFFFFFF"

    property color primary: "#7DE2B8"
    property color primaryStrong: "#55C996"
    property color primaryHover: "#91E9C4"
    property color primaryMuted: "#1A3E31"
    property color primaryInk: "#07130F"
    property color highlightHover: "#214A3B"
    property color highlightPressed: "#214D3D"
    property color accent: "#E0BD78"
    property color accentMuted: "#3B321F"

    property color text: "#F2F6F2"
    property color textSecondary: "#B5C3BD"
    property color textMuted: "#7F9189"
    property color textDisabled: "#52625C"

    property color success: "#75D8A7"
    property color warning: "#E8C477"
    property color error: "#FF8589"
    property color errorMuted: "#3C2022"
    property color errorHover: "#482528"
    property color errorBorder: "#653337"

    readonly property int radiusSmall: size(8)
    readonly property int radiusMedium: size(12)
    readonly property int radiusLarge: size(20)
    readonly property int radiusXLarge: size(28)
    readonly property int controlHeight: size(48)
    readonly property int pageMargin: size(32)

    readonly property int motionFast: 120
    readonly property int motionNormal: 220
    readonly property int motionSlow: 360

    function applyPalette(swatch) {
        background = swatch.background
        backgroundRaised = swatch.backgroundRaised
        surface = swatch.surface
        surfaceHover = swatch.surfaceHover
        surfaceElevated = swatch.surfaceElevated
        surfaceMuted = swatch.surfaceMuted
        disabled = swatch.disabled
        border = swatch.border
        borderStrong = swatch.borderStrong
        divider = swatch.divider
        badgeBackground = swatch.badgeBackground
        badgeBorder = swatch.badgeBorder
        modalScrim = swatch.modalScrim
        inactiveSelection = swatch.inactiveSelection
        glass = swatch.glass
        glassElevated = swatch.glassElevated
        glassBorder = swatch.glassBorder
        primary = swatch.primary
        primaryStrong = swatch.primaryStrong
        primaryHover = swatch.primaryHover
        primaryMuted = swatch.primaryMuted
        primaryInk = swatch.primaryInk
        highlightHover = swatch.highlightHover
        highlightPressed = swatch.highlightPressed
        accent = swatch.accent
        accentMuted = swatch.accentMuted
        text = swatch.text
        textSecondary = swatch.textSecondary
        textMuted = swatch.textMuted
        textDisabled = swatch.textDisabled
        success = swatch.success
        warning = swatch.warning
        error = swatch.error
        errorMuted = swatch.errorMuted
        errorHover = swatch.errorHover
        errorBorder = swatch.errorBorder
    }

    readonly property var classicPalette: ({
        background: "#08110E",
        backgroundRaised: "#0C1713",
        surface: "#101D18",
        surfaceHover: "#152721",
        surfaceElevated: "#172720",
        surfaceMuted: "#0D1815",
        disabled: "#17201D",
        border: "#253B33",
        borderStrong: "#37594B",
        divider: "#1C3029",
        badgeBackground: "#F20B1512",
        badgeBorder: "#66FFFFFF",
        modalScrim: "#E608130F",
        inactiveSelection: "#E60B1512",
        glass: "#1A7DE2B8",
        glassElevated: "#267DE2B8",
        glassBorder: "#3D253B33",
        primary: "#7DE2B8",
        primaryStrong: "#55C996",
        primaryHover: "#91E9C4",
        primaryMuted: "#1A3E31",
        primaryInk: "#07130F",
        highlightHover: "#214A3B",
        highlightPressed: "#214D3D",
        accent: "#E0BD78",
        accentMuted: "#3B321F",
        text: "#F2F6F2",
        textSecondary: "#B5C3BD",
        textMuted: "#7F9189",
        textDisabled: "#52625C",
        success: "#75D8A7",
        warning: "#E8C477",
        error: "#FF8589",
        errorMuted: "#3C2022",
        errorHover: "#482528",
        errorBorder: "#653337"
    })

    readonly property var glassPalette: ({
        background: "#061014",
        backgroundRaised: "#0A1618",
        surface: "#121C22",
        surfaceHover: "#1A262E",
        surfaceElevated: "#1C2A32",
        surfaceMuted: "#0E171C",
        disabled: "#152026",
        border: "#2A3A40",
        borderStrong: "#3D5258",
        divider: "#1C2A2E",
        badgeBackground: "#F2081014",
        badgeBorder: "#66FFFFFF",
        modalScrim: "#D205080C",
        inactiveSelection: "#E6081014",
        glass: "#1FFFFFFF",
        glassElevated: "#2EFFFFFF",
        glassBorder: "#3DFFFFFF",
        primary: "#7EE8C4",
        primaryStrong: "#5FD4A8",
        primaryHover: "#96F0D0",
        primaryMuted: "#1A3D36",
        primaryInk: "#061410",
        highlightHover: "#214A3B",
        highlightPressed: "#214D3D",
        accent: "#E8C98A",
        accentMuted: "#3A3220",
        text: "#F4F7F6",
        textSecondary: "#B8C6C2",
        textMuted: "#7E908B",
        textDisabled: "#52625C",
        success: "#75D8A7",
        warning: "#E8C477",
        error: "#FF8589",
        errorMuted: "#3C2022",
        errorHover: "#482528",
        errorBorder: "#653337"
    })

    onUiThemeChanged: applyPalette(uiTheme === "glass" ? glassPalette : classicPalette)
    Component.onCompleted: applyPalette(uiTheme === "glass" ? glassPalette : classicPalette)
}
