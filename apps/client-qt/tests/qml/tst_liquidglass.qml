// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    name: "LiquidGlass"

    LiquidGlass {
        id: pane
        width: 120
        height: 48
        radius: 16
        elevated: true
    }

    LiquidGlass {
        id: fullPane
        width: 120
        height: 68
        radius: 16
        compact: false
        quiet: false
        elevated: true
    }

    AppBackground {
        id: playmat
        width: 320
        height: 180
        variant: "playmat"
        visible: false
    }

    function cleanup() {
        Theme.uiTheme = "classic"
        TableBackgrounds.currentId = "default"
        Theme.backdropScene = null
        Theme.backdropBlur = null
        pane.compact = false
        pane.elevated = true
        pane.height = 48
    }

    function test_defaultThemeIsClassic() {
        compare(Theme.uiTheme, "classic")
        verify(!Theme.useGlass)
        verify(Qt.colorEqual(Theme.background, "#08110E"))
        verify(!pane.drawn)
    }

    function test_glassSwitchesPaletteAndDrawsLens() {
        Theme.uiTheme = "glass"
        verify(Theme.useGlass)
        verify(Qt.colorEqual(Theme.background, "#061014"))
        verify(pane.drawn)
        verify(findChild(pane, "liquidGlassLens") !== null)
    }

    function test_playmatSelectionIsIndependentOfTheme() {
        TableBackgrounds.currentId = "forest"
        playmat.visible = true
        verify(playmat.playmatLook)
        const image = findChild(playmat, "tableBackgroundImage")
        verify(image !== null)
        for (const theme of ["classic", "glass", "classic"]) {
            Theme.uiTheme = theme
            verify(playmat.playmatLook)
            verify(String(image.source).endsWith("/backgrounds/forest.png"))
        }
        playmat.visible = false
    }

    function test_exposesLensShader() {
        const lens = findChild(pane, "liquidGlassLens")
        verify(lens !== null)
        compare(lens.fragmentShader, "qrc:/shaders/qml/shaders/liquidglass.frag.qsb")
    }

    function test_fallsBackWithoutBackdrop() {
        verify(Theme.backdropScene === null)
        verify(!pane.live)
    }

    function test_withAlphaPreservesRgb_data() {
        return [
            {tag: "white-highlight", base: "#FFFFFF", alpha: 0.08,
                expected: Qt.rgba(1, 1, 1, 0.08)},
            {tag: "warm-rail", base: "#0A0806", alpha: 0.55,
                expected: Qt.rgba(10 / 255, 8 / 255, 6 / 255, 0.55)},
            {tag: "named-color", base: "red", alpha: 0.35,
                expected: Qt.rgba(1, 0, 0, 0.35)},
            {tag: "color-value", base: Qt.rgba(0.2, 0.4, 0.6, 0.3), alpha: 0.75,
                expected: Qt.rgba(0.2, 0.4, 0.6, 0.75)}
        ]
    }

    function test_withAlphaPreservesRgb(data) {
        verify(Qt.colorEqual(Theme.withAlpha(data.base, data.alpha), data.expected))
    }

    function test_neverPaintsOffsetCastPlate() {
        pane.compact = false
        pane.elevated = true
        pane.height = 400
        verify(!pane.castsPanelShadow)
        compare(findChild(pane, "liquidGlassCast"), null)
        pane.compact = true
        pane.height = 48
        verify(!pane.castsPanelShadow)
    }

    function test_shortElevatedRowIsQuiet() {
        pane.compact = false
        pane.elevated = true
        pane.height = 68
        verify(pane.quiet)
        verify(!pane.well)
    }

    function test_tallElevatedPanelIsNotQuiet() {
        pane.compact = false
        pane.elevated = true
        pane.height = 400
        verify(!pane.quiet)
        verify(!pane.well)
    }

    function test_quietCanStayOffOnShortPanels() {
        verify(fullPane.height < Theme.size(200))
        verify(!fullPane.quiet)
    }

    function test_compactWellDoesNotSampleBackdrop() {
        Theme.uiTheme = "glass"
        Theme.backdropScene = playmat
        playmat.visible = true
        pane.compact = true
        pane.height = 48
        verify(pane.well)
        verify(pane.drawn)
        verify(!pane.live)
        playmat.visible = false
        Theme.backdropScene = null
    }
}
