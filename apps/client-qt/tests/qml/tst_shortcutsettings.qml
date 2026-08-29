// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"

TestCase {
    id: testCase
    name: "ShortcutSettings"
    when: windowShown

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
        const capture = findChild(shortcutSettings, "shortcutCapturePopup")
        if (capture && capture.opened)
            capture.close()
        preferences.resetAllShortcuts()
        preferences.shortcutCaptureActive = false
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
        capture.startCapture("replay.speedHalf", "Set replay speed to 0.5×")
        tryVerify(() => capture.opened)
        const captureFocus = findChild(capture, "shortcutCaptureFocus")
        verify(captureFocus !== null)
        tryVerify(() => captureFocus.activeFocus)
        keyClick(Qt.Key_Delete)
        verify(capture.hasCaptured)
        compare(capture.capturedSequence, "")
        capture.acceptSequence()
        tryVerify(() => !capture.opened)
        compare(preferences.shortcutSequences("replay.speedHalf"), [])
    }
}
