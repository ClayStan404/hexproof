// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "ExportDeckDialog"
    when: windowShown

    ApplicationWindow {
        id: window
        width: 640
        height: 480
        visible: true

        ExportDeckDialog {
            id: dialog
            deckName: "Burn"
        }
    }

    SignalSpy {
        id: copySpy
        target: dialog
        signalName: "copyRequested"
    }

    SignalSpy {
        id: saveSpy
        target: dialog
        signalName: "saveRequested"
    }

    SignalSpy {
        id: artSpy
        target: dialog
        signalName: "cardArtRequested"
    }

    function cleanup() {
        dialog.close()
        window.width = 640
        window.height = 480
        dialog.deckName = "Burn"
        Theme.uiScale = 1
    }

    function test_cardArtActionRemainsReachable_data() {
        return [{tag: "normal", scale: 1}, {tag: "maximum", scale: 1.8}]
    }

    function test_cardArtActionRemainsReachable(data) {
        artSpy.clear()
        Theme.uiScale = data.scale
        window.width = 900
        window.height = 620
        dialog.deckName = "A very long Cube name ".repeat(12)
        dialog.open()
        tryVerify(() => dialog.opened)
        waitForPolish(window)
        verify(dialog.height <= window.height)
        const body = findChild(dialog, "deckExportBody")
        verify(body.height > 0)
        body.contentY = Math.max(0, body.contentHeight - body.height)
        waitForPolish(window)
        const button = findChild(dialog, "exportDeckArtButton")
        const point = button.mapToItem(window.contentItem, 0, 0)
        verify(point.x >= 0 && point.x + button.width <= window.width)
        verify(point.y >= 0 && point.y + button.height <= window.height)
        mouseClick(button)
        tryVerify(() => !dialog.opened)
        compare(artSpy.count, 1)
    }

    function test_copyAndSaveButtonsEmit() {
        copySpy.clear()
        saveSpy.clear()
        dialog.open()
        tryVerify(() => dialog.opened)
        waitForPolish(window)
        const copyButton = findChild(dialog, "copyDeckExportButton")
        const saveButton = findChild(dialog, "saveDeckExportButton")
        verify(copyButton !== null)
        verify(saveButton !== null)
        mouseClick(copyButton)
        tryVerify(() => !dialog.opened)
        compare(copySpy.count, 1)
        compare(saveSpy.count, 0)

        dialog.open()
        tryVerify(() => dialog.opened)
        waitForPolish(window)
        mouseClick(saveButton)
        tryVerify(() => !dialog.opened)
        compare(saveSpy.count, 1)
        compare(copySpy.count, 1)
    }
}
