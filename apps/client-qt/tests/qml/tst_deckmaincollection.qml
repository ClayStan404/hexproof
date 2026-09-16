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
    CardFilterState { id: creatureFilter; types: ["Creature"] }

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
        // Release both virtualized views before the test engine is destroyed.
        // The large-deck cases can leave buffered delegates incubating after
        // their final assertion, even when all visible rows already exist.
        collection.cards = []
        collection.viewModeIndex = 0
        waitForPolish(testWindow)
        tryCompare(findChild(collection, "mainDeckList"), "count", 0)
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

    function test_localizedSubtypesAndBackFacesDoNotBecomeLandGroups() {
        collection.cards = [
            {name: "Oswald Fiddlebender", displayName: "Oswald Fiddlebender",
             typeLine: "传奇生物 ～地侏／神器师", setCode: "AFR", collectorNumber: "28",
             count: 1, manaValue: 2, colors: "W"},
            {name: "Esper Sentinel", displayName: "Esper Sentinel",
             typeLine: "神器生物～人类／士兵", setCode: "MH2", collectorNumber: "12",
             count: 1, manaValue: 1, colors: "W"},
            {name: "Test front // Test back", displayName: "Test front // Test back", typeLine: "瞬间//地",
             setCode: "TST", collectorNumber: "1", count: 1, manaValue: 2, colors: "W"},
            {name: "Island", displayName: "Island", typeLine: "基本地～海岛", setCode: "TST", collectorNumber: "2",
             count: 5, manaValue: 0, colors: "U"}
        ]
        const expectedCreatures = ["Esper Sentinel", "Oswald Fiddlebender"]
        compare(creatureFilter.filter(collection.cards).map(card => card.name).sort(), expectedCreatures)
        compare(collection.groups.map(group => group.key), ["Creatures", "Instants", "Lands"])
        compare(collection.groups[0].cards.map(card => card.name).sort(), expectedCreatures,
                "Type grouping must agree with the local Creature filter")
        compare(collection.groups[0].label, "Creatures (2)")
        compare(collection.groups[1].cards[0].name, "Test front // Test back")
        compare(collection.groups[2].label, "Lands (5)")
        collection.groupModeIndex = 1
        compare(collection.groups.map(group => group.key), ["mana-1", "mana-2", "mana-land"])
        compare(collection.groups[1].cards.length, 2)
        compare(collection.groups[2].cards.map(card => card.name), ["Island"])
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
        tryVerify(() => findChild(collection, "groupedDeckGallery") !== null)
    }

    function makeCards(count) {
        const cards = []
        for (let index = 0; index < count; ++index) {
            cards.push({name: "Cube Card " + String(index).padStart(4, "0"),
                        displayName: "Cube Card " + String(index).padStart(4, "0"),
                        category: "Other", typeLine: "", count: 1, manaValue: -1,
                        setCode: "TST", collectorNumber: String(index), commander: false})
        }
        return cards
    }

    function visualCards(item) {
        let result = []
        if (item.card && typeof item.incrementRequested === "function")
            result.push(item)
        for (const child of item.children || [])
            result = result.concat(visualCards(child))
        return result
    }

    function test_visualModeOnlyCreatesViewportCards_data() {
        return [{tag: "EDH", count: 100}, {tag: "old threshold", count: 240},
                {tag: "Cube", count: 960}, {tag: "maximum entries", count: 5000}]
    }

    function test_visualModeOnlyCreatesViewportCards(data) {
        collection.cards = makeCards(data.count)
        collection.viewModeIndex = 1
        const gallery = findChild(collection, "groupedDeckGallery")
        verify(gallery !== null)
        waitForPolish(testWindow)
        waitForRendering(gallery)
        compare(gallery.count, Math.ceil(data.count / gallery.columns))
        const maximumDelegates = gallery.columns * (Math.ceil(gallery.height / Theme.size(380)) + 4)
        verify(visualCards(gallery).length <= maximumDelegates,
               "Only viewport rows and a bounded scroll buffer should instantiate card controls")
        compare(findChild(collection, "mainDeckList").count, 0,
                "The hidden list must not instantiate a second copy of the deck")
        gallery.positionViewAtEnd()
        waitForPolish(testWindow)
        tryVerify(() => findCardDelegate(gallery, "TST", String(data.count - 1)) !== null)
        verify(visualCards(gallery).length <= maximumDelegates)
        collection.viewModeIndex = 0
        tryVerify(() => findChild(collection, "groupedDeckGallery") === null, 5000,
                  "The hidden gallery should release its card controls")
    }

    function test_groupedRowsPreserveCategoriesAndEveryPrinting() {
        collection.cards = makeCards(100).concat(testCase.defaultCards)
        collection.viewModeIndex = 1
        const gallery = findChild(collection, "groupedDeckGallery")
        verify(gallery !== null)
        waitForPolish(testWindow)
        const rows = collection.galleryRows(gallery.columns)
        compare(rows[0].groupKey, "Creatures")
        compare(rows[1].groupKey, "Instants")
        compare(rows[2].groupKey, "Other")
        const allCards = [].concat.apply([], rows.map(row => row.cards))
        compare(allCards.length, 104)
        compare(allCards.filter(card => card.name === "Lightning Bolt").length, 2)
        compare(collection.groupTitle("Instants"), "Instants (5)")
    }

    function firstVisibleCard(view) {
        const rows = Array.from(view.contentItem.children).filter(item => item.visible
            && (item.card || item.row) && item.y + item.height > view.contentY
            && item.y < view.contentY + view.height).sort((a, b) => a.y - b.y)
        verify(rows.length > 0)
        const row = rows[0]
        const card = row.card || row.row.cards[0]
        return {identity: [card.name, card.setCode, card.collectorNumber],
                offset: row.y - view.contentY}
    }

    function test_viewSwitchRestoresReleasedViewport_data() {
        return [{tag: "gallery middle", view: 1, bottom: false},
                {tag: "gallery bottom", view: 1, bottom: true},
                {tag: "list middle", view: 0, bottom: false},
                {tag: "list bottom", view: 0, bottom: true}]
    }

    function test_viewSwitchRestoresReleasedViewport(data) {
        collection.cards = makeCards(100).map((card, index) => Object.assign({}, card, {
            typeLine: ["Creature", "Instant", "Sorcery", "Land"][Math.floor(index / 25)]}))
        collection.viewModeIndex = data.view
        const viewName = data.view === 1 ? "groupedDeckGallery" : "mainDeckList"
        let view = findChild(collection, viewName)
        waitForPolish(testWindow)
        if (data.bottom)
            view.positionViewAtEnd()
        else {
            view.positionViewAtIndex(Math.floor(view.count / 2), ListView.Beginning)
            view.contentY += Theme.size(17)
        }
        waitForPolish(testWindow)
        waitForRendering(view)
        const firstCard = firstVisibleCard(view)
        findChild(collection, "deckEditorViewMode").activated(1 - data.view)
        waitForPolish(testWindow)
        waitForRendering(findChild(collection, data.view === 1 ? "mainDeckList" : "groupedDeckGallery"))
        findChild(collection, "deckEditorViewMode").activated(data.view)
        view = findChild(collection, viewName)
        verify(view !== null)
        wait(50)
        const restoredCard = firstVisibleCard(view)
        compare(restoredCard.identity, firstCard.identity)
        compare(restoredCard.offset, firstCard.offset)
        if (data.bottom)
            tryVerify(() => findCardDelegate(view, "TST", "99") !== null)
    }

    function test_restoringAfterFilteringKeepsShortViewWithinBounds_data() {
        return [{tag: "list", view: 0}, {tag: "gallery", view: 1}]
    }

    function test_restoringAfterFilteringKeepsShortViewWithinBounds(data) {
        const cards = makeCards(100)
        collection.cards = cards
        collection.viewModeIndex = data.view
        const name = data.view === 1 ? "groupedDeckGallery" : "mainDeckList"
        let view = findChild(collection, name)
        waitForPolish(testWindow)
        view.positionViewAtIndex(Math.floor(view.count / 2), ListView.Beginning)
        view.contentY += Theme.size(17)
        waitForPolish(testWindow)
        waitForRendering(view)
        findChild(collection, "deckEditorViewMode").activated(1 - data.view)
        collection.cards = cards.slice(0, 3)
        waitForPolish(testWindow)
        waitForRendering(findChild(collection, data.view === 1 ? "mainDeckList" : "groupedDeckGallery"))
        findChild(collection, "deckEditorViewMode").activated(data.view)
        view = findChild(collection, name)
        wait(50)
        verify(view.contentHeight < view.height)
        compare(view.contentY, view.originY)
        compare(firstVisibleCard(view).identity, [cards[0].name, "TST", "0"])
    }

    function test_countUpdatePreservesScrolledViewportAndPrinting() {
        const cards = makeCards(100)
        collection.cards = cards
        collection.viewModeIndex = 1
        const gallery = findChild(collection, "groupedDeckGallery")
        waitForPolish(testWindow)
        gallery.positionViewAtEnd()
        waitForPolish(testWindow)
        const contentY = gallery.contentY
        const originalDelegate = findCardDelegate(gallery, "TST", "99")
        verify(originalDelegate !== null)
        fakeDeckLibrary.currentDeckCardsAboutToChange()
        const updated = cards.slice()
        updated[99] = Object.assign({}, cards[99], {count: 2})
        collection.cards = updated
        fakeDeckLibrary.currentDeckCardsChanged()
        wait(50)
        compare(gallery.contentY, contentY)
        tryVerify(() => findCardDelegate(gallery, "TST", "99") !== null)
        compare(findCardDelegate(gallery, "TST", "99"), originalDelegate)
        compare(findCardDelegate(gallery, "TST", "99").card.count, 2)
        compare(collection.groupTitle("Other"), "Other (101)")
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
        const gallery = findChild(collection, "groupedDeckGallery")
        verify(gallery !== null)
        tryVerify(() => findCardDelegate(gallery, "TST", "0") !== null)
        const card = findCardDelegate(gallery, "TST", "0")

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
