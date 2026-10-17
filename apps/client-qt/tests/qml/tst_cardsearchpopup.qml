// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "CardSearchPopup"
    when: windowShown
    property bool respondAsynchronously: false

    ApplicationWindow {
        id: testWindow
        width: 1100
        height: 760
        visible: true

        QtObject {
            id: previewCatalog
            property var previewCards: []
            property var previewBatches: []
            property int imageRevision: 0
            function imageSource(name, setCode, collectorNumber) { return "" }
            function tableImageSource(name, setCode, collectorNumber) { return "" }
            function setSearchPreviewCards(cards) {
                previewCards = cards.slice()
                if (cards.length > 0) previewBatches = previewBatches.concat([cards.slice()])
            }
        }

        QtObject {
            id: mockDeckLibrary
            signal currentDeckChanged()

            function currentCardCopies(cardName) {
                return cardName === "Already Full" ? 4 : 0
            }

            function canAddCard(cardName, typeLine) {
                return cardName !== "Already Full"
            }
        }

        CardSearchPopup {
            id: searchPopup
            deckLibraryModel: mockDeckLibrary
            catalogModel: previewCatalog
            results: [{
                "name": "Lightning Bolt",
                "displayName": "Lightning Bolt",
                "typeLine": "Instant",
                "setCode": "M11",
                "collectorNumber": "149",
                "versionCount": 12
            }]
            onSearchRequested: if (testCase.respondAsynchronously) searching = true
        }
    }

    SignalSpy {
        id: searchSpy
        target: searchPopup
        signalName: "searchRequested"
    }

    SignalSpy {
        id: addSpy
        target: searchPopup
        signalName: "addRequested"
    }

    function init() {
        Theme.uiScale = 1
        testWindow.requestActivate()
        tryVerify(() => testWindow.active)
        searchPopup.close()
        respondAsynchronously = false
        searchPopup.searching = false
        searchPopup.resetFilters()
        searchPopup.query = ""
        searchPopup.selectedCard = null
        searchPopup.allowSideboard = true
        searchPopup.considerOnly = false
        searchPopup.results = [{name: "Lightning Bolt", displayName: "Lightning Bolt",
                                typeLine: "Instant", setCode: "M11", collectorNumber: "149"}]
        previewCatalog.previewCards = []
        previewCatalog.previewBatches = []
        searchSpy.clear()
        addSpy.clear()
    }

    function cleanup() {
        searchPopup.close()
        Theme.uiScale = 1
    }

    function findVisual(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const found = findVisual(child, name)
            if (found) return found
        }
        return null
    }

    function test_pendingSearchHidesPreviousResults_data() {
        return [{tag: "typed query", query: true}, {tag: "color filter", query: false}]
    }

    function test_pendingSearchHidesPreviousResults(data) {
        searchPopup.query = "Lightning"
        searchPopup.openSearch()
        tryCompare(searchPopup, "opened", true)
        tryCompare(searchSpy, "count", 1)
        const grid = findChild(searchPopup, "cardSearchResults")
        tryCompare(grid, "count", 1)
        waitForPolish(testWindow)
        tryVerify(() => grid.itemAtIndex(0) !== null)
        respondAsynchronously = true

        if (data.query) {
            const input = findVisual(searchPopup.contentItem, "workbenchSearch")
            mouseClick(input, input.width / 2, input.height / 2)
            tryVerify(() => input.activeFocus)
            keyClick(Qt.Key_A, Qt.ControlModifier)
            for (const character of "Counterspell") keyClick(character)
            compare(searchPopup.query, "Counterspell")
        } else {
            const color = findVisual(searchPopup.contentItem, "filterColor-U")
            verify(color !== null)
            mouseClick(color, color.width / 2, color.height / 2)
            compare(searchPopup.colorFilter, "U")
        }
        compare(searchSpy.count, 1, "The next database search is still debounced")
        compare(grid.count, 0, "Previous-query cards must stop being clickable immediately")
        compare(addSpy.count, 0)

        tryCompare(searchSpy, "count", 2)
        compare(grid.count, 0, "Pending database work must not restore the old result")
        searchPopup.results = [{name: "Counterspell", displayName: "Counterspell",
                                typeLine: "Instant", setCode: "MH2", collectorNumber: "267"}]
        searchPopup.searching = false
        tryCompare(grid, "count", 1)
        waitForPolish(testWindow)
        tryVerify(() => grid.itemAtIndex(0) !== null)
        const card = findChild(grid.itemAtIndex(0), "workbenchCard-Counterspell")
        verify(card !== null)
        mouseClick(card, card.width / 2, card.height / 2)
        compare(addSpy.count, 0, "Selecting a result must not add it yet")
        compare(searchPopup.selectedCard.name, "Counterspell")
        const addMain = findChild(searchPopup, "cardSearchAddMain")
        verify(addMain !== null && addMain.enabled)
        mouseClick(addMain, addMain.width / 2, addMain.height / 2)
        compare(addSpy.count, 1)
        compare(addSpy.signalArguments[0][0].name, "Counterspell")
        compare(addSpy.signalArguments[0][1], "main")
        compare(addSpy.signalArguments[0][0].setCode, "MH2")
        compare(addSpy.signalArguments[0][0].collectorNumber, "267")
    }

    function test_closeCancelsDebouncedSearchAndLateResultsStayHidden() {
        searchPopup.query = "Lightning"
        searchPopup.openSearch()
        tryCompare(searchPopup, "opened", true)
        tryCompare(searchSpy, "count", 1)
        const input = findVisual(searchPopup.contentItem, "workbenchSearch")
        mouseClick(input, input.width / 2, input.height / 2)
        tryVerify(() => input.activeFocus)
        keyClick(Qt.Key_A, Qt.ControlModifier)
        for (const character of "Counterspell") keyClick(character)
        compare(searchPopup.query, "Counterspell")
        const close = findChild(searchPopup, "cardSearchDoneButton")
        verify(close !== null)
        mouseClick(close, close.width / 2, close.height / 2)
        tryCompare(searchPopup, "opened", false)
        searchPopup.results = [{name: "A late result", setCode: "TST", collectorNumber: "9"}]
        wait(300)
        compare(searchSpy.count, 1, "Closing cancels a search that was still debounced")
        compare(previewCatalog.previewCards.length, 0)
        compare(findChild(searchPopup, "cardSearchResults").count, 0,
                "A closed popup must not rebuild stale result delegates")
        compare(addSpy.count, 0)
    }

    function test_previewsFollowViewportAndCancelOnSearchOrClose() {
        searchPopup.openSearch()
        tryCompare(searchPopup, "opened", true)
        searchPopup.query = "Razor"
        const candidates = []
        for (let index = 0; index < 40; ++index)
            candidates.push({name: "Razor " + index, setCode: "TST", collectorNumber: String(index)})
        searchPopup.results = candidates
        const grid = findChild(searchPopup, "cardSearchResults")
        tryVerify(() => previewCatalog.previewCards.length > 0)
        verify(previewCatalog.previewCards.length < candidates.length)
        compare(previewCatalog.previewCards, grid.visibleCards)
        grid.positionViewAtIndex(30, GridView.Beginning)
        tryVerify(() => previewCatalog.previewCards.some(card => card.name === "Razor 30"))
        compare(previewCatalog.previewCards, grid.visibleCards)
        searchPopup.query = "Razorgrass"
        compare(previewCatalog.previewCards.length, 0)
        searchPopup.results = [{name: "Razorgrass Ambush // Razorgrass Field",
                                setCode: "MH3", collectorNumber: "238"}]
        tryCompare(previewCatalog, "previewCards", searchPopup.results)
        searchPopup.close()
        compare(previewCatalog.previewCards.length, 0)
        const batchCount = previewCatalog.previewBatches.length
        wait(450)
        compare(previewCatalog.previewBatches.length, batchCount)
    }

    function test_hoverPreviewKeepsResultsGeometryAndWindowBounds_data() {
        return [{tag:"normal",scale:1},{tag:"large",scale:1.5}]
    }

    function test_hoverPreviewKeepsResultsGeometryAndWindowBounds(data) {
        Theme.uiScale = data.scale
        searchPopup.openSearch()
        tryCompare(searchPopup,"opened",true)
        searchPopup.query = "Lightning"
        const results = findChild(searchPopup,"cardSearchResults")
        tryCompare(results,"count",1)
        verify(waitForRendering(searchPopup.contentItem))
        mouseMove(testWindow,1,1)
        const thumbnail = findChild(results.itemAtIndex(0),"workbenchCard-Lightning Bolt")
        const originalResults = {x:results.x,y:results.y,width:results.width,height:results.height}
        mouseMove(thumbnail,thumbnail.width/2,thumbnail.height/2)
        const preview = findChild(searchPopup,"cardHoverPreviewArt").parent
        tryCompare(preview,"visible",true)
        verify(waitForRendering(searchPopup.contentItem))
        compare({x:results.x,y:results.y,width:results.width,height:results.height},originalResults)
        const point = preview.mapToItem(testWindow.contentItem,0,0)
        verify(point.x>=0 && point.y>=0)
        verify(point.x+preview.width<=testWindow.width && point.y+preview.height<=testWindow.height)
        const popupPoint = preview.mapToItem(searchPopup.contentItem.parent,0,0)
        verify(popupPoint.x>=0 && popupPoint.y>=0)
        verify(popupPoint.x+preview.width<=searchPopup.width && popupPoint.y+preview.height<=searchPopup.height)
    }

    function test_searchAddsWithoutEditingLiveDeck() {
        searchPopup.allowSideboard = true
        searchPopup.considerOnly = false
        searchPopup.query = "Lightning"
        searchPopup.openSearch()
        tryCompare(searchPopup, "opened", true)
        verify(findChild(searchPopup, "cardSearchDeckList") === null,
               "Catalog search must not keep a live deck list to edit")
        verify(findChild(searchPopup, "cardSearchDestination") === null)
        const addMain = findChild(searchPopup, "cardSearchAddMain")
        const addSideboard = findChild(searchPopup, "cardSearchAddSideboard")
        const addConsider = findChild(searchPopup, "cardSearchAddConsider")
        verify(addMain !== null && addSideboard !== null && addConsider !== null)
        verify(addSideboard.visible)
        verify(!addMain.enabled && !addSideboard.enabled && !addConsider.enabled)
        const grid = findChild(searchPopup, "cardSearchResults")
        tryCompare(grid, "count", 1)
        waitForPolish(testWindow)
        tryVerify(() => grid.itemAtIndex(0) !== null)
        const card = findChild(grid.itemAtIndex(0), "workbenchCard-Lightning Bolt")
        verify(card !== null)
        mouseClick(card, card.width / 2, card.height / 2)
        compare(addSpy.count, 0, "Selecting a result must not add it yet")
        compare(searchPopup.selectedCard.name, "Lightning Bolt")
        tryVerify(() => addMain.enabled && addSideboard.enabled && addConsider.enabled)
        mouseClick(addSideboard, addSideboard.width / 2, addSideboard.height / 2)
        compare(addSpy.count, 1)
        compare(addSpy.signalArguments[0][0].name, "Lightning Bolt")
        compare(addSpy.signalArguments[0][1], "sideboard")
        addSpy.clear()
        mouseClick(addConsider, addConsider.width / 2, addConsider.height / 2)
        compare(addSpy.signalArguments[0][1], "consider")
        searchPopup.close()
    }

    function test_commanderSearchOmitsSideboardAndCanAddToConsider() {
        searchPopup.allowSideboard = false
        searchPopup.considerOnly = false
        searchPopup.query = "Lightning"
        searchPopup.openSearch()
        tryCompare(searchPopup, "opened", true)
        verify(findChild(searchPopup, "cardSearchAddMain") !== null)
        verify(!findChild(searchPopup, "cardSearchAddSideboard").visible)
        const addConsider = findChild(searchPopup, "cardSearchAddConsider")
        verify(addConsider !== null)
        const grid = findChild(searchPopup, "cardSearchResults")
        tryCompare(grid, "count", 1)
        waitForPolish(testWindow)
        tryVerify(() => grid.itemAtIndex(0) !== null)
        const card = findChild(grid.itemAtIndex(0), "workbenchCard-Lightning Bolt")
        mouseClick(card, card.width / 2, card.height / 2)
        compare(addSpy.count, 0)
        tryVerify(() => addConsider.enabled)
        mouseClick(addConsider, addConsider.width / 2, addConsider.height / 2)
        compare(addSpy.count, 1)
        compare(addSpy.signalArguments[0][1], "consider")
        const scrollBar = findChild(grid, "cardArtGridScrollBar")
        verify(scrollBar !== null)
        searchPopup.close()
    }

    function test_opensLargeResultListAndSearchesByName() {
        searchPopup.openSearch()
        tryVerify(() => searchPopup.opened)
        verify(searchPopup.width >= Theme.size(900))

        const resultList = findChild(searchPopup, "cardSearchResults")
        verify(resultList !== null)
        tryVerify(() => resultList.height > Theme.size(260))
        findChild(searchPopup, "advancedCardFiltersButton").clicked()
        const advanced = findChild(searchPopup, "advancedCardFilters")
        tryVerify(() => advanced.opened)
        tryVerify(() => findChild(advanced.contentItem, "filter-types-Creature") !== null)
        verify(findChild(advanced.contentItem, "cardSearchSetFilter") !== null)
        verify(findChild(advanced.contentItem, "cardSearchLanguageFilter") !== null)
        verify(findChild(searchPopup.contentItem, "filterColor-W") !== null)
        verify(findChild(advanced.contentItem, "filter-rarities-rare") !== null)
        verify(findChild(advanced.contentItem, "cardSearchLegalityFilter") !== null)
        compare(searchPopup.legalityOptions.length, 24)
        compare(searchPopup.legalityOptions[1].value, "standard")
        compare(searchPopup.legalityOptions[2].value, "future")
        compare(searchPopup.legalityOptions[3].value, "pioneer")
        compare(searchPopup.legalityOptions[4].value, "modern")
        compare(searchPopup.legalityOptions[5].value, "legacy")
        compare(searchPopup.legalityOptions[6].value, "vintage")
        compare(searchPopup.legalityOptions[7].value, "pauper")
        compare(searchPopup.legalityOptions[8].value, "commander")
        compare(searchPopup.legalityOptions[9].value, "duel")
        compare(searchPopup.legalityOptions[23].value, "tlr")
        advanced.close()

        searchSpy.clear()
        searchPopup.query = "Lightning"
        tryCompare(searchSpy, "count", 1)
        compare(searchSpy.signalArguments[0][0], "Lightning")
        for (let index = 1; index < 7; ++index)
            compare(searchSpy.signalArguments[0][index], "")
        tryCompare(resultList, "count", 1)
    }

    function test_passesDatabaseFiltersAndSupportsFilterOnlySearch() {
        searchPopup.typeFilter = "Creature"
        searchPopup.setFilter = "mh3"
        searchPopup.languageFilter = "zhs"
        searchPopup.colorFilter = "W"
        searchPopup.rarityFilter = "mythic"
        searchPopup.legalityFilter = "commander"
        verify(searchPopup.filtersActive)
        verify(searchPopup.hasSearchCriteria)

        searchPopup.searchNow()
        compare(searchSpy.count, 1)
        compare(searchSpy.signalArguments[0][0], "")
        compare(searchSpy.signalArguments[0][1], "Creature")
        compare(searchSpy.signalArguments[0][2], "mh3")
        compare(searchSpy.signalArguments[0][3], "zhs")
        compare(searchSpy.signalArguments[0][4], "W")
        compare(searchSpy.signalArguments[0][5], "mythic")
        compare(searchSpy.signalArguments[0][6], "commander")

        searchPopup.resetFilters()
        verify(!searchPopup.filtersActive)
        verify(!searchPopup.hasSearchCriteria)
    }
}
