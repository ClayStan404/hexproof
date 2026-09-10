// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"

TestCase {
    id: testCase
    name: "CardArtManagerRefresh"
    when: windowShown
    readonly property var artManager: manager
    readonly property var catalogModel: catalog
    readonly property var storageService: storage
    ApplicationWindow {
        id: window
        width: 1000
        height: 720
        visible: true
        function popScreen() {}
        function pushScreen() {}
    }
    QtObject {
        id: manager
        property bool busy: false
        property var inventory: ({})
        property var packPreview: ({})
        property var auditResult: ({})
        property bool repairNeeded: false
        property string storagePath: "/test/images"
        property string lastResult: ""
        property string lastError: ""
        property string status: ""
        property string rejection: ""
        property int calls: 0
        signal packInspectionFinished()
        signal auditFinished()
        function clearMessages() { lastError = ""; lastResult = "" }
        function refresh() {
            ++calls
            lastError = rejection
            if (!rejection)
                inventory = {imageCount: 82, groups: []}
        }
    }
    QtObject { id: catalog; property bool busy: false }
    QtObject {
        id: storage
        property bool busy: false
        property bool restartRequired: false
        property bool defaultLocation: true
        property bool available: true
        property string currentDirectory: "/test"
        property string lastError: ""
        property string lastResult: ""
        property string status: ""
        property real progress: 0
    }
    Component {
        id: pageComponent
        CardArtManager {
            property var cardArtManager: testCase.artManager
            property var cardCatalog: testCase.catalogModel
            property var cardArtStorage: testCase.storageService
        }
    }
    function init() {
        manager.calls = 0
        manager.busy = false
        manager.inventory = ({})
        manager.rejection = ""
        manager.lastError = ""
        catalog.busy = false
        storage.restartRequired = false
        storage.available = true
    }
    function page() {
        const value = createTemporaryObject(pageComponent, window.contentItem,
                                           {width: window.width, height: window.height})
        verify(value !== null)
        return value
    }
    function test_initialInventoryWaitsForCatalogWork() {
        catalog.busy = true
        const value = page()
        compare(manager.calls, 0)
        verify(value.inventoryRefreshPending)
        catalog.busy = false
        tryCompare(manager, "calls", 1)
        compare(manager.inventory.imageCount, 82)
        verify(!value.inventoryRefreshPending)
    }
    function test_transientBackendGuardRetriesButRealErrorsDoNot() {
        manager.rejection = "Wait for the current card operation to finish."
        const value = page()
        compare(manager.calls, 1)
        compare(manager.lastError, "")
        verify(value.inventoryRefreshPending)
        manager.rejection = ""
        tryCompare(manager, "calls", 2)
        verify(!value.inventoryRefreshPending)
        manager.rejection = "Could not read the cache directory."
        value.requestInventoryRefresh()
        compare(manager.calls, 3)
        compare(manager.lastError, manager.rejection)
        verify(!value.inventoryRefreshPending)
        wait(550)
        compare(manager.calls, 3)
    }
    function test_hiddenPageAndPendingRestartDoNotKeepScanning() {
        catalog.busy = true
        const value = page()
        value.visible = false
        catalog.busy = false
        wait(550)
        compare(manager.calls, 0)
        value.visible = true
        tryCompare(manager, "calls", 1)
        storage.restartRequired = true
        value.requestInventoryRefresh()
        wait(550)
        compare(manager.calls, 1)
    }
    function test_unavailableStorageAndPersistentGuardDoNotLoopForever() {
        storage.available = false
        const value = page()
        compare(manager.calls, 0)
        verify(!value.inventoryRefreshPending)
        storage.available = true
        manager.rejection = "Wait for the current card operation to finish."
        value.requestInventoryRefresh()
        for (let index = 0; index < 10; ++index)
            value.refreshInventoryWhenReady()
        compare(manager.calls, 11)
        verify(!value.inventoryRefreshPending)
        compare(manager.lastError, manager.rejection)
        wait(550)
        compare(manager.calls, 11)
    }
}
