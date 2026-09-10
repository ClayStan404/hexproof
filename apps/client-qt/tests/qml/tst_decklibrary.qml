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
        window.openedScreen = ""
    }
    function cleanup() { Theme.uiScale = 1 }

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
                            "deckLibraryImportButton", "editLibraryDeckButton",
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
}
