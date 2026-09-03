// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    id: testCase

    name: "LimitedSetPicker"
    readonly property var setFixtures: [
        {
            "id": "DFT",
            "setCode": "DFT",
            "name": "DFT · Aetherdrift",
            "productName": "Aetherdrift Play Booster"
        },
        {
            "id": "NEO",
            "setCode": "NEO",
            "name": "NEO · Kamigawa: Neon Dynasty",
            "productName": "Kamigawa: Neon Dynasty Draft Booster"
        },
        {
            "id": "WOE",
            "setCode": "WOE",
            "name": "WOE · Wilds of Eldraine",
            "productName": "艾卓仙踪 Draft Booster"
        }
    ]
    property var delayedSets: []

    LimitedSetPicker {
        id: picker
        width: 500
        sets: testCase.setFixtures
    }

    LimitedSetPicker {
        id: delayedPicker
        width: 500
        sets: testCase.delayedSets
    }

    function init() {
        picker.searchText = ""
        picker.selectedId = "DFT"
        delayedSets = []
        delayedPicker.searchText = ""
        delayedPicker.selectedId = ""
    }

    function test_defaultsToAVisibleSet() {
        verify(picker.hasSelection)
        compare(picker.selectedSet.id, "DFT")
        compare(picker.filteredSets.length, 3)
    }

    function test_filtersByCodeAndSelectsTheMatch() {
        picker.searchText = "neo"
        tryCompare(picker, "selectedId", "NEO")
        compare(picker.filteredSets.length, 1)
        compare(picker.selectedSet.productName,
                "Kamigawa: Neon Dynasty Draft Booster")
    }

    function test_filtersLocalizedNamesAndClearsNoMatch() {
        picker.searchText = "艾卓"
        tryCompare(picker, "selectedId", "WOE")
        compare(picker.filteredSets.length, 1)

        picker.searchText = "not-a-real-set"
        tryCompare(picker, "selectedId", "")
        verify(!picker.hasSelection)
        compare(picker.filteredSets.length, 0)

        picker.searchText = ""
        tryCompare(picker, "selectedId", "DFT")
        compare(picker.filteredSets.length, 3)
    }

    function test_delayedSetsKeepComboTextInSyncWhileSearching() {
        const selector = findChild(delayedPicker, "limitedSetSelector")
        verify(selector)
        compare(selector.currentIndex, -1)
        compare(selector.displayText, "")

        delayedSets = setFixtures
        tryCompare(delayedPicker, "selectedId", "DFT")
        tryCompare(selector, "currentIndex", 0)
        tryCompare(selector, "displayText", "DFT · Aetherdrift")

        delayedPicker.searchText = "neo"
        tryCompare(delayedPicker, "selectedId", "NEO")
        tryCompare(selector, "currentIndex", 0)
        tryCompare(selector, "displayText", "NEO · Kamigawa: Neon Dynasty")

        delayedPicker.searchText = "not-a-real-set"
        tryCompare(delayedPicker, "selectedId", "")
        tryCompare(selector, "currentIndex", -1)
        tryCompare(selector, "displayText", "")

        delayedPicker.searchText = ""
        tryCompare(delayedPicker, "selectedId", "DFT")
        tryCompare(selector, "currentIndex", 0)
        tryCompare(selector, "displayText", "DFT · Aetherdrift")
    }
}
