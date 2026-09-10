// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "StorageLocationPanel"
    when: windowShown
    ApplicationWindow {
        id: window
        width: 900
        height: 620
        visible: true
        ScrollView {
            anchors.fill: parent
            contentWidth: availableWidth
            StorageLocationPanel {
                id: panel
                width: parent.width
                service: storage
            }
        }
    }
    QtObject {
        id: storage
        property bool busy: false
        property bool restartRequired: false
        property bool defaultLocation: true
        property bool available: true
        property bool invalidPreview: false
        property real progress: 0
        property string status: ""
        property string lastError: ""
        property string lastResult: ""
        property string currentDirectory: "/profile"
        property var preview: ({})
        property var calls: []
        function previewDirectory(url) {
            if (invalidPreview)
                return {ok: false, error: "Invalid parent directory."}
            preview = {ok: true, managedDirectory: "/selected/hexproof-art-profile", baseDirectory: "/selected"}
            return preview
        }
        function previewDefault() {
            preview = {ok: true, managedDirectory: "/profile", isDefault: true}
            return preview
        }
        function migrateTo(url) { calls = ["migrateTo", String(url)]; busy = true }
        function resetToDefault() { calls = ["resetToDefault"]; busy = true }
    }
    function init() {
        Theme.uiScale = 1
        storage.busy = false
        storage.restartRequired = false
        storage.defaultLocation = true
        storage.lastError = ""
        storage.lastResult = ""
        storage.calls = []
        storage.invalidPreview = false
        panel.previewError = ""
        panel.operationsBusy = false
        findChild(panel, "cardArtLocationConfirmation").close()
        waitForPolish(window)
    }
    function cleanup() {
        findChild(panel, "cardArtLocationConfirmation").close()
        Theme.uiScale = 1
    }
    function test_folderChoiceRequiresManagedDestinationConfirmation() {
        const chooser = findChild(panel, "cardArtLocationFolderDialog")
        chooser.open()
        tryVerify(() => chooser.visible)
        chooser.selectedFolder = "file:///tmp"
        compare(chooser.selectedFolder.toString(), "file:///tmp")
        chooser.accepted()
        chooser.close()
        const confirmation = findChild(panel, "cardArtLocationConfirmation")
        tryVerify(() => confirmation.opened)
        compare(storage.calls.length, 0)
        verify(confirmation.message.indexOf("/selected/hexproof-art-profile") >= 0)
        verify(confirmation.message.indexOf("Original files will not be removed") >= 0)
        waitForPolish(window)
        mouseClick(findChild(confirmation, "confirmButton"))
        compare(storage.calls, ["migrateTo", "file:///tmp"])
        verify(!findChild(panel, "chooseCardArtLocationButton").enabled)
        storage.progress = 0.5
        compare(findChild(panel, "cardArtLocationProgress").value, 0.5)
        storage.busy = false
        storage.restartRequired = true
        storage.lastResult = "Card art copied. Original files are kept. Restart Hexproof."
        verify(!panel.canChange)
        verify(findChild(panel, "cardArtLocationResult").visible)
    }
    function test_cancelPreservesLocationAndDefaultIsExplicit() {
        panel.previewFolder("file:///tmp")
        const confirmation = findChild(panel, "cardArtLocationConfirmation")
        tryVerify(() => confirmation.opened)
        confirmation.close()
        compare(storage.calls.length, 0)
        storage.defaultLocation = false
        panel.previewDefault()
        tryVerify(() => confirmation.opened)
        verify(confirmation.message.indexOf("/profile") >= 0)
        waitForPolish(window)
        mouseClick(findChild(confirmation, "confirmButton"))
        compare(storage.calls, ["resetToDefault"])
    }
    function test_busyAndMigrationFailuresRemainVisible() {
        panel.operationsBusy = true
        panel.previewFolder("file:///tmp")
        verify(!findChild(panel, "cardArtLocationConfirmation").opened)
        verify(!panel.canChange)
        panel.operationsBusy = false
        panel.previewFolder("file:///tmp")
        panel.confirmLocation()
        storage.busy = false
        storage.lastError = "Destination is not writable."
        verify(panel.canChange)
        compare(findChild(panel, "cardArtLocationError").message, "Destination is not writable.")
        verify(findChild(panel, "cardArtLocationError").visible)
    }
    function test_invalidPreviewIsShownWithoutStartingMigration() {
        storage.invalidPreview = true
        panel.previewFolder("file:///tmp")
        compare(storage.calls.length, 0)
        verify(!findChild(panel, "cardArtLocationConfirmation").opened)
        compare(findChild(panel, "cardArtLocationError").message, "Invalid parent directory.")
        storage.invalidPreview = false
        panel.previewFolder("file:///tmp")
        compare(panel.previewError, "")
    }
    function test_scaledConfirmationButtonsRemainReachable() {
        Theme.uiScale = 1.8
        panel.previewFolder("file:///tmp")
        const confirmation = findChild(panel, "cardArtLocationConfirmation")
        tryVerify(() => confirmation.opened)
        waitForPolish(window)
        for (const name of ["confirmButton", "cancelButton"]) {
            const button = findChild(confirmation, name)
            const point = button.mapToItem(window.contentItem, 0, 0)
            verify(point.x >= 0 && point.x + button.width <= window.width)
            verify(point.y >= 0 && point.y + button.height <= window.height)
        }
    }
}
