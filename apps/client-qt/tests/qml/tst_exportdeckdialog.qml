// SPDX-License-Identifier: GPL-2.0-only
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

    function test_copyAndSaveButtonsEmit() {
        copySpy.clear()
        saveSpy.clear()
        dialog.open()
        tryVerify(() => dialog.opened)
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
        mouseClick(saveButton)
        tryVerify(() => !dialog.opened)
        compare(saveSpy.count, 1)
        compare(copySpy.count, 1)
    }
}
