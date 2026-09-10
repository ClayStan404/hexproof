// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"
import "../../qml/components"

TestCase {
    id: testCase
    name: "ShortcutSettings"
    when: windowShown

    ShortcutActionCatalog { id: catalog }

    ApplicationWindow {
        id: testWindow
        width: 1000
        height: 760
        visible: true

        function popScreen() { }

        ShortcutSettings {
            id: shortcutSettings
            anchors.fill: parent
        }
    }

    function init() {
        preferences.shortcutCaptureActive = false
        preferences.resetAllShortcuts()
        preferences.clearLastError()
    }

    function cleanup() {
        Theme.uiScale = 1
        testWindow.width = 1000
        testWindow.height = 760
        shortcutSettings.query = ""
        const capture = findChild(shortcutSettings, "shortcutCapturePopup")
        if (capture && capture.opened)
            capture.close()
        preferences.resetAllShortcuts()
        preferences.shortcutCaptureActive = false
    }

    function test_customizedActionRemainsReadableAndEditable_data() {
        return [{tag: "large", scale: 1.5}, {tag: "maximum", scale: 1.8}]
    }

    function test_customizedActionRemainsReadableAndEditable(data) {
        testWindow.width = 900
        testWindow.height = 620
        Theme.uiScale = data.scale
        verify(preferences.setShortcutSequence("table.library.drawOne", "Ctrl+Alt+J"))
        shortcutSettings.query = "draw one"
        waitForRendering(shortcutSettings)
        const row = findChild(shortcutSettings, "shortcutAction-table.library.drawOne")
        verify(row !== null)
        const label = findChild(row, "shortcutActionLabel")
        verify(label.width >= Theme.size(120))
        for (const name of ["resetShortcutButton", "changeShortcutButton"]) {
            const button = findChild(row, name)
            const point = button.mapToItem(row, 0, 0)
            verify(point.x >= 0 && point.x + button.width <= row.width + 1)
        }
        mouseClick(findChild(row, "changeShortcutButton"))
        const capture = findChild(shortcutSettings, "shortcutCapturePopup")
        tryVerify(() => capture.opened)
        compare(capture.actionId, "table.library.drawOne")
        keyClick(Qt.Key_Escape)
        tryVerify(() => !capture.opened)
        mouseClick(findChild(row, "resetShortcutButton"))
        tryVerify(() => !preferences.shortcutCustomized("table.library.drawOne"))
    }

    function test_capturesRejectsConflictAndSavesBinding() {
        testWindow.requestActivate()
        tryVerify(() => testWindow.active)
        const capture = findChild(shortcutSettings, "shortcutCapturePopup")
        verify(capture !== null)
        capture.startCapture("app.fullscreen", "Toggle full screen")
        tryVerify(() => capture.opened)
        const captureFocus = findChild(capture, "shortcutCaptureFocus")
        verify(captureFocus !== null)
        tryVerify(() => captureFocus.activeFocus)
        verify(preferences.shortcutCaptureActive)

        keyClick(Qt.Key_Right, Qt.ControlModifier)
        compare(capture.capturedSequence, "Ctrl+Right")
        compare(capture.conflictAction, "table.advancePhase")

        keyClick(Qt.Key_F, Qt.ControlModifier | Qt.AltModifier)
        compare(capture.capturedSequence, "Ctrl+Alt+F")
        compare(capture.conflictAction, "")
        capture.acceptSequence()

        tryVerify(() => !capture.opened)
        verify(!preferences.shortcutCaptureActive)
        compare(preferences.shortcutSequences("app.fullscreen"), ["Ctrl+Alt+F"])
    }

    function test_deleteLeavesActionUnassigned() {
        testWindow.requestActivate()
        tryVerify(() => testWindow.active)
        const capture = findChild(shortcutSettings, "shortcutCapturePopup")
        capture.startCapture("table.help", "Show or hide shortcut help")
        tryVerify(() => capture.opened)
        const captureFocus = findChild(capture, "shortcutCaptureFocus")
        verify(captureFocus !== null)
        tryVerify(() => captureFocus.activeFocus)
        keyClick(Qt.Key_Delete)
        verify(capture.hasCaptured)
        compare(capture.capturedSequence, "")
        capture.acceptSequence()
        tryVerify(() => !capture.opened)
        compare(preferences.shortcutSequences("table.help"), [])
    }

    function test_replayActionsAreRemoved() {
        for (const group of catalog.groups) {
            verify(group.id !== "replay")
            for (const action of group.actions)
                verify(!action.id.startsWith("replay."))
        }
        for (const action of ["playPause", "previous", "next", "reset", "speedHalf",
                              "speedNormal", "speedDouble", "speedQuadruple"]) {
            compare(preferences.shortcutSequences("replay." + action), [])
            verify(!preferences.setShortcutSequence("replay." + action, "F10"))
        }
    }
}
