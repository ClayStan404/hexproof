// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "TournamentDecklist"
    when: windowShown

    ApplicationWindow {
        id: window
        width: 1100
        height: 720
        visible: true
        property string banner: ""
        function showBanner(text) { banner = text }

        TournamentDecklistPopup {
            id: popup
            cardCatalogModel: catalog
            deckLibraryModel: library
        }
    }

    QtObject {
        id: catalog
        property int imageRevision: 0
        function imageSource(name, setCode, collector) { return "" }
        function cardDisplayName(name) { return name }
        function cardTypeLine(name, setCode, collector) {
            if (name === "Lightning Bolt")
                return "Instant"
            if (name === "Island")
                return "Basic Land — Island"
            if (name === "Atraxa, Praetors' Voice")
                return "Legendary Creature — Phyrexian Angel Horror"
            return ""
        }
    }

    QtObject {
        id: library
        property string lastError: ""
        property var copied: null
        property var saved: null
        property url lastSuggested: ""
        function copyPublishedDeckText(deck) {
            copied = deck
            return true
        }
        function savePublishedDeckText(deck, url) {
            saved = {deck: deck, url: url}
            return true
        }
        function suggestedPublishedDeckUrl(name, deckName) {
            lastSuggested = "file:///tmp/" + name + ".txt"
            return lastSuggested
        }
    }

    function cleanup() {
        popup.close()
        window.banner = ""
        library.copied = null
        library.saved = null
        Theme.uiScale = 1
    }

    function test_groupsCardsAndCopiesExport() {
        popup.showDeck("Alice", {
                           name: "Burn",
                           commanders: ["Atraxa, Praetors' Voice"],
                           mainboard: [
                               {name: "Atraxa, Praetors' Voice", count: 1,
                                setCode: "2X2", collectorNumber: "183"},
                               {name: "Lightning Bolt", count: 4,
                                setCode: "M11", collectorNumber: "149"},
                               {name: "Island", count: 20, setCode: "M11",
                                collectorNumber: "234"}
                           ],
                           sideboard: [
                               {name: "Negate", count: 2, typeLine: "Instant"}
                           ]
                       })
        tryCompare(popup, "opened", true)
        waitForRendering(popup.contentItem)
        compare(popup.mainboardCount, 25)
        compare(popup.sideboardCount, 2)
        compare(popup.mainboardGroups.length, 3)
        compare(popup.mainboardGroups[0].key, "Commander")
        compare(popup.mainboardGroups[1].key, "Spells")
        compare(popup.mainboardGroups[2].key, "Lands")
        verify(findChild(popup, "tournamentDecklistScroll") !== null)
        const exportButton = findChild(popup, "tournamentDecklistExportButton")
        verify(exportButton !== null)
        verify(exportButton.enabled)
        mouseClick(exportButton)
        const copyItem = findChild(popup, "tournamentDecklistCopyMenuItem")
        verify(copyItem !== null)
        mouseClick(copyItem)
        verify(library.copied !== null)
        compare(library.copied.name, "Burn")
        compare(window.banner, "Deck list copied")
    }

    function test_emptyDeckDisablesExport() {
        popup.showDeck("Bob", {name: "Empty"})
        tryCompare(popup, "opened", true)
        waitForRendering(popup.contentItem)
        compare(popup.canExport, false)
        compare(findChild(popup, "tournamentDecklistExportButton").enabled, false)
    }
}