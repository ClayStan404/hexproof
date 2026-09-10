// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "CardSearchPopup"
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 1100
        height: 760
        visible: true

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
            results: [{
                "name": "Lightning Bolt",
                "displayName": "Lightning Bolt",
                "typeLine": "Instant",
                "setCode": "M11",
                "collectorNumber": "149",
                "versionCount": 12
            }]
        }
    }

    SignalSpy {
        id: searchSpy
        target: searchPopup
        signalName: "searchRequested"
    }

    function init() {
        Theme.uiScale = 1
        searchPopup.close()
        searchPopup.resetFilters()
        searchPopup.query = ""
        searchSpy.clear()
    }

    function cleanup() {
        searchPopup.close()
        Theme.uiScale = 1
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
