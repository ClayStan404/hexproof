// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick
import QtQuick.Window

Window {
    id: window
    width: 1600
    height: 1000
    minimumWidth: 1100
    minimumHeight: 720
    visible: true
    visibility: Window.Maximized
    title: "Hexproof — Forge UI Study (offline)"
    color: "#0f1923"
    property int captureNumber: 0
    readonly property string captureDirectory: argument("capture-dir", "")

    function argument(name, fallback) {
        const prefix = "--" + name + "="
        for (const value of Qt.application.arguments) {
            if (value.indexOf(prefix) === 0) return value.slice(prefix.length)
        }
        return fallback
    }
    function capture() {
        if (!captureDirectory) return
        const path = captureDirectory + "/" + (++captureNumber) + "-" + model.stage + ".png"
        view.grabToImage(function(result) {
            const saved = result.saveToFile(path)
            console.info("STUDY_CAPTURE " + JSON.stringify({path: path, saved: saved,
                geometry: view.geometryReport(), maximized: window.visibility === Window.Maximized,
                screenWidth: Screen.width, screenHeight: Screen.height, dpr: Screen.devicePixelRatio}))
        })
    }
    StudyModel { id: model }
    StudyBoard {
        id: view
        anchors.fill: parent
        controller: model
        assetRoot: window.argument("assets", Qt.resolvedUrl("../../../build/forge-ui-prototype/assets/").toString())
    }
    Component.onCompleted: {
        view.chooseScene(argument("scene", "board"))
        captureTimer.restart()
    }
    Connections {
        target: model
        function onStageChanged() { captureTimer.restart() }
        function onSelectedManaIdChanged() { captureTimer.restart() }
        function onStackChanged() { captureTimer.restart() }
    }
    Connections {
        target: model.combat
        function onModeChanged() { captureTimer.restart() }
        function onAttackersChanged() { captureTimer.restart() }
        function onBlocksChanged() { captureTimer.restart() }
        function onDamageChanged() { captureTimer.restart() }
        function onCommittedChanged() { captureTimer.restart() }
    }
    Connections {
        target: model.duel
        function onStateChanged() { captureTimer.restart() }
        function onReservedChanged() { captureTimer.restart() }
    }
    Timer { id: captureTimer; interval: 1100; onTriggered: window.capture() }
    Shortcut { sequence: "F1"; onActivated: view.chooseScene("board") }
    Shortcut { sequence: "F2"; onActivated: view.chooseScene("response") }
    Shortcut { sequence: "F3"; onActivated: view.chooseScene("target") }
    Shortcut { sequence: "F4"; onActivated: view.chooseScene("payment") }
    Shortcut { sequence: "F5"; onActivated: view.chooseScene("combat") }
    Shortcut { sequence: "F6"; onActivated: view.chooseScene("commander") }
    Shortcut { sequence: "F7"; onActivated: view.chooseScene("crowded") }
    Shortcut { sequence: "F8"; onActivated: console.info("STUDY_GEOMETRY " + JSON.stringify(view.geometryReport())) }
    Shortcut { sequence: "F9"; onActivated: window.capture() }
    Shortcut {
        sequence: "Escape"
        onActivated: {
            model.cancel()
            view.pinnedCard = null
            view.hoveredCard = null
            view.logOpen = false
        }
    }
    Shortcut {
        sequence: "Space"
        onActivated: view.primaryAction()
    }
}
