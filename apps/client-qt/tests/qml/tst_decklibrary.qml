// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"
import "../../qml/components"

TestCase {
    name: "DeckLibrary"
    when: windowShown
    ApplicationWindow {
        id: window
        width: 900
        height: 620
        visible: true
        property string openedScreen: ""
        function pushScreen(path) { openedScreen = path }
        function popScreen() { }
        function showBanner(message) { }
    }
    ListModel {
        id: library
        property string lastError: ""
        property string formatFilter: "all"
        property bool hasMissingArt: false
        property string openedDeck: ""
        property string exportedDeck: ""
        property string currentDeckFormat: ""
        property string createdName: ""
        property string createdFormat: ""
        property bool rejectCreation: false
        function createDeck(name, format) {
            if (rejectCreation) {
                lastError = "The local deck library cannot be updated safely."
                return false
            }
            createdName = name
            createdFormat = format
            currentDeckFormat = format
            return true
        }
        function clearLastError() { lastError = "" }
        function openDeck(id) { openedDeck = id; return true }
        function refreshMissingArt() { }
        function retryMissingArt() { }
        function cardArtExportRequests(id) {
            exportedDeck = id
            return [{name: "Lightning Bolt", setCode: "M11", collectorNumber: "149"}]
        }
    }
    QtObject {
        id: catalog
        property string lastError: ""
        property bool busy: false
        property bool searching: false
        property bool tokenSearching: false
        property real progress: 0
        property string status: ""
        function clearLastError() { }
    }
    Component {
        id: pageComponent
        DeckLibrary {
            property var deckLibrary: library
            property var cardCatalog: catalog
        }
    }
    function init() {
        library.clear()
        library.append({deckId:"audit", deckName:"A long Commander deck name with exact printings",
                        deckFormat:"commander", tableMode:"edh", mainCount:100, sideboardCount:0,
                        ready:true, status:"Card database required to verify deck legality.",
                        commander:"A long commander name", legalityVerified:false,
                        legalityIssues:[], legalityWarnings:[]})
        library.openedDeck = ""
        library.exportedDeck = ""
        library.createdName = ""
        library.createdFormat = ""
        library.rejectCreation = false
        library.lastError = ""
        library.formatFilter = "all"
        window.openedScreen = ""
    }
    function cleanup() {
        Theme.uiScale = 1
        Theme.uiTheme = "classic"
        testTranslations.setLanguage("en")
    }

    function test_cacheLibraryArtMatchesImportButtonStyle() {
        Theme.uiTheme = "glass"
        const page = createTemporaryObject(pageComponent, window.contentItem,
                                          {width: window.width, height: window.height})
        verify(page !== null)
        waitForRendering(page)
        const cache = findChild(page, "cacheDeckArtButton")
        const importButton = findChild(page, "deckLibraryImportButton")
        verify(cache !== null)
        verify(importButton !== null)
        verify(cache.visible)
        compare(cache.variant, importButton.variant)
        compare(cache.compact, importButton.compact)
        compare(cache.implicitHeight, importButton.implicitHeight)
        verify(Theme.useGlass)
    }

    function test_libraryArtExportTargetsSelectedDeck() {
        const page = createTemporaryObject(pageComponent, window.contentItem,
                                          {width: window.width, height: window.height})
        verify(page !== null)
        waitForPolish(window)
        const button = findChild(page, "exportDeckButton")
        verify(button !== null)
        mouseClick(button)
        const menu = findChild(page, "exportDeckDialog")
        tryVerify(() => menu.opened)
        waitForPolish(window)
        const body = findChild(menu, "deckExportBody")
        body.contentY = Math.max(0, body.contentHeight - body.height)
        waitForPolish(window)
        mouseClick(findChild(menu, "exportDeckArtButton"))
        const artDialog = findChild(page, "libraryDeckArtExportDialog")
        tryVerify(() => artDialog.opened)
        compare(library.exportedDeck, "audit")
        compare(artDialog.deckName, "A long Commander deck name with exact printings")
        compare(artDialog.cardRequests[0].setCode, "M11")
        page.pendingDeckId = "another-deck"
        page.pendingDeckName = "Another deck"
        compare(artDialog.deckName, "A long Commander deck name with exact printings")
        compare(artDialog.cardRequests[0].name, "Lightning Bolt")
        artDialog.close()
    }
    function test_deckActionsRemainReachable_data() {
        return [{tag:"normal", scale:1}, {tag:"large", scale:1.5},
                {tag:"maximum", scale:1.8}]
    }
    function test_deckActionsRemainReachable(data) {
        Theme.uiScale = data.scale
        const page = createTemporaryObject(pageComponent, window.contentItem,
                                            {width:window.width, height:window.height})
        verify(page !== null)
        waitForRendering(page)
        for (const name of ["deckLibraryFormatFilter", "deckLibrarySettingsButton",
                            "deckLibraryCreateButton", "deckLibraryImportButton", "editLibraryDeckButton",
                            "exportDeckButton", "deleteLibraryDeckButton"]) {
            const item = findChild(page, name)
            verify(item !== null, name)
            const position = item.mapToItem(page, 0, 0)
            verify(position.x >= 0 && position.x + item.width <= page.width + 1, name)
        }
        const deckName = findChild(page, "libraryDeckName")
        verify(deckName.width >= Theme.size(80), "The deck name must remain readable")
        const edit = findChild(page, "editLibraryDeckButton")
        const body = findChild(page, "deckLibraryBody")
        body.contentY = Math.max(0, body.contentHeight - body.height)
        const list = findChild(page, "libraryDeckList")
        list.contentY = Math.max(0, list.contentHeight - list.height)
        waitForRendering(page)
        const editPoint = edit.mapToItem(page, 0, 0)
        verify(editPoint.y >= 0 && editPoint.y + edit.height <= page.height)
        mouseClick(edit)
        compare(library.openedDeck, "audit")
        compare(window.openedScreen, "screens/DeckEditor.qml")
    }

    function test_createCancelAndConfirmFromEmptyLibrary() {
        library.clear()
        const page = createTemporaryObject(pageComponent, window.contentItem,
                                          {width:window.width, height:window.height})
        verify(page !== null)
        waitForRendering(page)
        const dialog = findChild(page, "createDeckDialog")
        mouseClick(findChild(page, "deckLibraryCreateButton"))
        tryVerify(() => dialog.opened)
        const name = findChild(dialog, "createDeckNameField")
        name.text = "Cancelled draft"
        mouseClick(findChild(dialog, "cancelCreateDeckButton"))
        tryVerify(() => !dialog.opened)
        compare(library.createdName, "")
        compare(library.count, 0)
        compare(window.openedScreen, "")

        const body = findChild(page, "deckLibraryBody")
        body.contentY = Math.max(0, body.contentHeight - body.height)
        waitForPolish(window)
        mouseClick(findChild(page, "createFirstDeckButton"))
        tryVerify(() => dialog.opened)
        compare(name.text, "")
        const format = findChild(dialog, "createDeckFormatField")
        compare(format.currentValue, "modern")
        name.text = "My Commander draft"
        format.currentIndex = 1
        library.formatFilter = "vintage"
        mouseClick(findChild(dialog, "confirmCreateDeckButton"))
        tryVerify(() => !dialog.opened)
        compare(library.createdName, "My Commander draft")
        compare(library.createdFormat, "commander")
        compare(library.formatFilter, "all")
        compare(window.openedScreen, "screens/DeckEditor.qml")
    }

    function test_failedCreationKeepsFormAndShowsError() {
        const page = createTemporaryObject(pageComponent, window.contentItem,
                                          {width:window.width, height:window.height})
        verify(page !== null)
        const dialog = findChild(page, "createDeckDialog")
        dialog.open()
        tryVerify(() => dialog.opened)
        const name = findChild(dialog, "createDeckNameField")
        name.text = "Retained name"
        library.rejectCreation = true
        mouseClick(findChild(dialog, "confirmCreateDeckButton"))
        verify(dialog.opened)
        compare(name.text, "Retained name")
        verify(findChild(dialog, "createDeckError").visible)
        compare(window.openedScreen, "")
        dialog.close()
    }

    function test_createActionsReachableAtLargeScale_data() {
        return [{tag:"normal", scale:1}, {tag:"large", scale:1.5},
                {tag:"maximum", scale:1.8}]
    }
    function test_createActionsReachableAtLargeScale(data) {
        Theme.uiScale = data.scale
        testTranslations.setLanguage("zh")
        library.clear()
        const page = createTemporaryObject(pageComponent, window.contentItem,
                                          {width:window.width, height:window.height})
        verify(page !== null)
        const dialog = findChild(page, "createDeckDialog")
        const body = findChild(page, "deckLibraryBody")
        waitForPolish(window)
        const entry = findChild(page, "deckLibraryCreateButton")
        const point = entry.mapToItem(body, 0, 0)
        body.contentY = Math.max(0, Math.min(body.contentHeight - body.height, point.y))
        waitForPolish(window)
        mouseClick(entry)
        tryVerify(() => dialog.opened)
        waitForPolish(window)
        for (const itemName of ["cancelCreateDeckButton", "confirmCreateDeckButton"]) {
            const button = findChild(dialog, itemName)
            const rect = button.mapToItem(window.contentItem, 0, 0, button.width, button.height)
            verify(rect.x >= 0 && rect.x + rect.width <= window.width, itemName)
            verify(rect.y >= 0 && rect.y + rect.height <= window.height, itemName)
        }
        compare(findChild(dialog, "confirmCreateDeckButton").text, "创建套牌")
        mouseClick(findChild(dialog, "cancelCreateDeckButton"))
        tryVerify(() => !dialog.opened)
        compare(library.createdName, "")
    }
}
