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
        function cardFaces(name, setCode, collector) {
            if (name !== "Front") return []
            return [{name:"Front", faceName:"", setCode:setCode, collectorNumber:collector},
                    {name:"Back", faceName:"Back", setCode:setCode, collectorNumber:collector}]
        }
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

    function findCard(item, name) {
        if (item.card && item.card.name === name && item.width > 0) return item
        for (const child of item.children || []) {
            const match = findCard(child, name)
            if (match) return match
        }
        return null
    }

    function test_bothFacesPreservePublishedDeck() {
        const deck = {name:"Face Deck", mainboard:[{name:"Front", count:4, setCode:"TST", collectorNumber:"7"}]}
        popup.showDeck("Alice", deck)
        tryCompare(popup, "opened", true)
        verify(waitForPolish(window))
        const source = findCard(popup.contentItem, "Front")
        verify(source !== null)
        mouseMove(window, 1, 1)
        mouseMove(source)
        const preview = findChild(popup, "cardHoverPreview")
        tryCompare(preview, "visible", true)
        compare(preview.facePreview.displayFaces.map(face => face.name), ["Front", "Back"])
        const reverse = findChild(preview, "tournamentDecklistHoverPreviewArt-1")
        verify(reverse !== null)
        verify(findChild(preview, "viewOtherFaceButton") === null)
        mouseMove(reverse)
        wait(400)
        verify(preview.visible)
        compare(JSON.stringify(popup.deck), JSON.stringify(deck))
        compare(popup.mainboardCount, 4)
        compare(library.copied, null)
        compare(library.saved, null)
        popup.close()
        tryCompare(preview, "visible", false)
    }
}
