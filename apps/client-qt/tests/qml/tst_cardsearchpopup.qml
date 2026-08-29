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
        searchPopup.close()
        searchPopup.resetFilters()
        searchPopup.query = ""
        searchSpy.clear()
    }

    function cleanup() {
        searchPopup.close()
    }

    function test_opensLargeResultListAndSearchesByName() {
        searchPopup.openSearch()
        tryVerify(() => searchPopup.opened)
        verify(searchPopup.width >= Theme.size(900))

        const resultList = findChild(searchPopup, "cardSearchResults")
        verify(resultList !== null)
        verify(resultList.height > Theme.size(260))
        verify(findChild(searchPopup, "cardSearchTypeFilter") !== null)
        verify(findChild(searchPopup, "cardSearchSetFilter") !== null)
        verify(findChild(searchPopup, "cardSearchLanguageFilter") !== null)
        verify(findChild(searchPopup, "cardSearchColorFilter") !== null)
        verify(findChild(searchPopup, "cardSearchRarityFilter") !== null)
        verify(findChild(searchPopup, "cardSearchLegalityFilter") !== null)
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
