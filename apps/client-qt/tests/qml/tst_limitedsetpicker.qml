// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    name: "LimitedSetPicker"

    LimitedSetPicker {
        id: picker
        width: 500
        sets: [
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
    }

    function init() {
        picker.searchText = ""
        picker.selectedId = "DFT"
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
}
