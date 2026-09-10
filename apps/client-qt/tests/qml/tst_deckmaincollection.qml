// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "DeckMainCollection"
    when: windowShown

    readonly property var defaultCards: [
        {"name": "Wild Nacatl", "displayName": "Wild Nacatl",
         "category": "Creatures", "typeLine": "Creature — Cat Warrior",
         "count": 4, "manaValue": 1, "setCode": "ALA",
         "collectorNumber": "152", "commander": false},
        {"name": "Scion of Draco", "displayName": "Scion of Draco",
         "category": "Creatures", "typeLine": "Artifact Creature — Dragon",
         "count": 2, "manaValue": 12, "setCode": "MH2",
         "collectorNumber": "234", "commander": false},
        {"name": "Lightning Bolt", "displayName": "Lightning Bolt",
         "category": "Spells", "typeLine": "Instant",
         "count": 4, "manaValue": 1, "setCode": "M11",
         "collectorNumber": "149", "commander": false},
        {"name": "Lightning Bolt", "displayName": "Lightning Bolt",
         "category": "Spells", "typeLine": "Instant",
         "count": 1, "manaValue": 1, "setCode": "2X2",
         "collectorNumber": "117", "commander": false}
    ]

    QtObject {
        id: fakeDeckLibrary
        signal currentDeckCardsAboutToChange()
        signal currentDeckCardsChanged()
        property var lastMove: []
        property var lastCountChange: []
        function canAddCard() { return true }
        function moveCard() {
            lastMove = Array.prototype.slice.call(arguments)
        }
        function moveCardToConsider() {}
        function changeCardCount() {
            lastCountChange = Array.prototype.slice.call(arguments)
        }
        function setCommander() {}
    }

    QtObject {
        id: fakeCatalog
        property bool installed: true
        property int imageRevision: -1
        function imageSource() { return "" }
    }

    ApplicationWindow {
        id: testWindow
        width: 1100
        height: 720
        visible: true

        DeckMainCollection {
            id: collection
            anchors.fill: parent
            anchors.margins: 20
            deckLibraryModel: fakeDeckLibrary
            catalogModel: fakeCatalog
            cards: testCase.defaultCards
        }
    }

    SignalSpy { id: customArtSpy; target: collection; signalName: "customArtRequested" }

    function init() {
        testTranslations.setLanguage("en")
        collection.cards = testCase.defaultCards
        collection.viewModeIndex = 0
        collection.groupModeIndex = 0
        collection.sortModeIndex = 0
        fakeDeckLibrary.lastMove = []
        fakeDeckLibrary.lastCountChange = []
        collection.customArtEnabled = false
    }

    function test_customArtActionPreservesPrintingAcrossViews_data() {
        return [{tag: "list", view: 0}, {tag: "visual", view: 1}]
    }
    function test_customArtActionPreservesPrintingAcrossViews(data) {
        collection.cards = [testCase.defaultCards[3]]
        collection.customArtEnabled = true
        collection.viewModeIndex = data.view
        customArtSpy.clear()
        waitForPolish(testWindow)
        const view = findChild(collection, data.view === 0 ? "mainDeckList" : "groupedDeckGallery")
        verify(view !== null)
        const card = findCardDelegate(view, "2X2", "117")
        verify(card !== null)
        verify(card.customArtEnabled)
        card.customArtRequested()
        compare(customArtSpy.count, 1)
        compare(customArtSpy.signalArguments[0][0].name, "Lightning Bolt")
        compare(customArtSpy.signalArguments[0][0].setCode, "2X2")
        compare(customArtSpy.signalArguments[0][0].collectorNumber, "117")
    }

    function cleanup() {
        testTranslations.setLanguage("en")
    }

    function test_categoryLabelsFollowInterfaceLanguage() {
        testTranslations.setLanguage("zh")
        compare(collection.groups[0].key, "Creatures")
        compare(collection.groups[0].label, "生物 (6)")
        compare(collection.groups[1].label, "瞬间 (5)")
        compare(collection.groupLabel("Artifacts"), "神器")
        compare(collection.groupLabel("Enchantments"), "结界")
        compare(collection.groupLabel("Planeswalkers"), "鹏洛客")
        compare(collection.groupLabel("Lands"), "地")
        testTranslations.setLanguage("en")
        compare(collection.groups[0].label, "Creatures (6)")
    }

    function test_typeGroupsShowCopyCounts() {
        compare(collection.groups.length, 2)
        compare(collection.groups[0].key, "Creatures")
        compare(collection.groups[0].label, "Creatures (6)")
        compare(collection.groups[1].key, "Instants")
        compare(collection.groups[1].label, "Instants (5)")
    }

    function test_manaGroupingAndSorting() {
        collection.groupModeIndex = 1
        collection.sortModeIndex = 1
        compare(collection.groups.length, 2)
        compare(collection.groups[0].key, "mana-1")
        compare(collection.groups[0].cards.length, 3)
        compare(collection.groups[1].key, "mana-7+")
        compare(collection.groups[1].cards[0].name, "Scion of Draco")
    }

    function test_visualModeIsAvailable() {
        collection.viewModeIndex = 1
        compare(collection.viewModeIndex, 1)
        tryVerify(() => findChild(collection, "groupedDeckGallery") !== null
                         && findChild(collection, "largeDeckGallery") === null)
    }

    function test_largeVisualModeUsesVirtualizedGallery() {
        const cards = []
        for (let index = 0; index < 1000; ++index) {
            cards.push({
                "name": "Cube Card " + index,
                "displayName": "Cube Card " + index,
                "category": "Other",
                "typeLine": "",
                "count": 1,
                "manaValue": -1,
                "setCode": "TST",
                "collectorNumber": String(index),
                "commander": false
            })
        }
        collection.cards = cards
        collection.viewModeIndex = 1

        tryVerify(() => findChild(collection, "largeDeckGallery") !== null
                         && findChild(collection, "groupedDeckGallery") === null)
        waitForRendering(findChild(collection, "largeDeckGallery"))
    }

    function test_listButtonsForwardPrintingIdentity() {
        const list = findChild(collection, "mainDeckList")
        verify(list !== null)
        tryVerify(() => list.itemAtIndex(3) !== null)
        let boltRow = null
        for (let index = 0; index < list.count; ++index) {
            const candidate = list.itemAtIndex(index)
            if (candidate && candidate.card.setCode === "M11")
                boltRow = candidate
        }
        verify(boltRow !== null)
        compare(boltRow.card.name, "Lightning Bolt")

        boltRow.incrementRequested()
        compare(fakeDeckLibrary.lastCountChange,
                ["Lightning Bolt", "M11", "149", false, 1])
        boltRow.decrementRequested()
        compare(fakeDeckLibrary.lastCountChange,
                ["Lightning Bolt", "M11", "149", false, -1])
        boltRow.moveRequested()
        compare(fakeDeckLibrary.lastMove,
                ["Lightning Bolt", "M11", "149", true])
    }

    function findCardDelegate(item, setCode, collectorNumber) {
        if (!item)
            return null
        if (item.card && item.card.setCode === setCode
                && item.card.collectorNumber === collectorNumber)
            return item
        const itemChildren = item.children || []
        for (let index = 0; index < itemChildren.length; ++index) {
            const result = findCardDelegate(itemChildren[index], setCode,
                                            collectorNumber)
            if (result)
                return result
        }
        return null
    }

    function test_groupedVisualControlsForwardPrintingIdentity() {
        collection.viewModeIndex = 1
        const gallery = findChild(collection, "groupedDeckGallery")
        verify(gallery !== null)
        tryVerify(() => findCardDelegate(gallery, "2X2", "117") !== null)
        const card = findCardDelegate(gallery, "2X2", "117")

        card.incrementRequested()
        compare(fakeDeckLibrary.lastCountChange,
                ["Lightning Bolt", "2X2", "117", false, 1])
        card.decrementRequested()
        compare(fakeDeckLibrary.lastCountChange,
                ["Lightning Bolt", "2X2", "117", false, -1])
        card.moveRequested()
        compare(fakeDeckLibrary.lastMove,
                ["Lightning Bolt", "2X2", "117", true])
    }

    function test_virtualizedVisualControlsForwardPrintingIdentity() {
        const cards = []
        for (let index = 0; index < 1000; ++index) {
            cards.push({
                "name": "Cube Card " + index,
                "displayName": "Cube Card " + index,
                "category": "Other",
                "typeLine": "",
                "count": 1,
                "manaValue": -1,
                "setCode": "TST",
                "collectorNumber": String(index),
                "commander": false
            })
        }
        collection.cards = cards
        collection.viewModeIndex = 1
        const gallery = findChild(collection, "largeDeckGallery")
        verify(gallery !== null)
        tryVerify(() => gallery.itemAtIndex(0) !== null)
        const card = gallery.itemAtIndex(0)

        card.incrementRequested()
        compare(fakeDeckLibrary.lastCountChange,
                [card.card.name, "TST", card.card.collectorNumber, false, 1])
        card.decrementRequested()
        compare(fakeDeckLibrary.lastCountChange,
                [card.card.name, "TST", card.card.collectorNumber, false, -1])
        card.moveRequested()
        compare(fakeDeckLibrary.lastMove,
                [card.card.name, "TST", card.card.collectorNumber, true])
    }
}
