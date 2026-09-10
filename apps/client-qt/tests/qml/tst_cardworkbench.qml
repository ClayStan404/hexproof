// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: test
    name: "CardWorkbench"
    when: windowShown
    readonly property var cards: [
        {instanceId: "a", name: "Shared name", setCode: "ONE", collectorNumber: "1",
         typeLine: "Artifact Creature", colors: "WG", manaValue: 3, rarity: "rare"},
        {instanceId: "b", name: "Shared name", setCode: "ONE", collectorNumber: "1",
         typeLine: "Artifact Creature", colors: "WG", manaValue: 3, rarity: "rare"},
        {instanceId: "c", name: "Shared name", setCode: "TWO", collectorNumber: "7†",
         typeLine: "Artifact Creature", colors: "WG", manaValue: 3, rarity: "mythic"},
        {instanceId: "d", name: "Chinese instant", typeLine: "瞬间", colors: "U", manaValue: 1, rarity: "common"}
    ]
    CardFilterState { id: filters }
    ApplicationWindow {
        id: window
        width: 900
        height: 600
        visible: true
        CardFilterBar {
            id: toolbar
            width: parent.width
            filters: filters
        }
        CompactCardList {
            id: list
            width: 320
            anchors.top: toolbar.bottom
            anchors.bottom: parent.bottom
            cards: test.cards
        }
    }
    SignalSpy { id: activate; target: list; signalName: "cardActivated" }
    CardManaCost { id: costSymbols }
    CardListRow { id: presentation; width: 320 }
    LimitedCardTile { id: rarityTile; card: ({}); catalogModel: null }
    function test_knownRarityLabels_data() {
        return [
            {tag: "common", rarity: "common", code: "C", label: "Common"},
            {tag: "uncommon", rarity: "uncommon", code: "U", label: "Uncommon"},
            {tag: "rare", rarity: "rare", code: "R", label: "Rare"},
            {tag: "mythic", rarity: "mythic", code: "M", label: "Mythic rare"},
            {tag: "special", rarity: "special", code: "S", label: "Special"},
            {tag: "bonus", rarity: "bonus", code: "B", label: "Bonus"},
            {tag: "normalized", rarity: " Mythic ", code: "M", label: "Mythic rare"},
            {tag: "unknown", rarity: "unknown", code: "?", label: "Unknown rarity"},
            {tag: "missing", rarity: "", code: "?", label: "Unknown rarity"}
        ]
    }
    function test_knownRarityLabels(data) {
        rarityTile.card = {name: "Exact printing", setCode: "TST", collectorNumber: "1", rarity: data.rarity}
        compare(rarityTile.rarityCode(), data.code)
        compare(rarityTile.rarityLabel(), data.label)
        verify(rarityTile.ToolTip.text.endsWith(data.label))
    }
    function init() {
        filters.reset()
        filters.query = ""
        activate.clear()
        window.width = 900
        window.height = 600
    }
    function test_categoriesUseUnionWithinAndIntersectionBetween() {
        filters.colors = ["U", "G"]
        filters.types = ["Instant", "Creature"]
        compare(filters.filter(cards).length, 4)
        filters.rarities = ["rare", "mythic"]
        compare(filters.filter(cards).length, 3)
        filters.manaValues = ["0", "1"]
        compare(filters.filter(cards).length, 0)
        filters.reset()
        filters.types = ["Instant"]
        compare(filters.filter(cards)[0].name, "Chinese instant")
    }
    function test_presentationUsesCardColorsAndFullCost() {
        presentation.card = {cardColors: ""}
        const neutral = String(presentation.frameColor)
        presentation.card = {colors: "WU", cardColors: ""}
        compare(String(presentation.frameColor), neutral)
        presentation.card = {cardColors: "U"}
        const blue = String(presentation.frameColor)
        presentation.card = {cardColors: "W"}
        verify(String(presentation.frameColor) !== blue)
        presentation.card = {colors: "WU"}
        compare(String(presentation.frameColor), neutral)
        costSymbols.cost = "{2}{U}{U}"
        compare(costSymbols.symbols, ["2", "U", "U"])
        costSymbols.cost = "{X}{W/U}{B/P}"
        compare(costSymbols.symbols, ["X", "W/U", "B/P"])
        costSymbols.cost = ""
        compare(costSymbols.symbols, [])
        costSymbols.cost = undefined
        compare(costSymbols.symbols, ["?"])
    }
    function test_bundledManaGlyphsAndHybridCosts() {
        tryCompare(ManaSymbols, "status", FontLoader.Ready)
        compare(ManaSymbols.name, "Mana")
        costSymbols.cost = "{2}{W}{U}{B}{R}{G}{C}{S}{X}{W/U}{2/B}{G/P}{W/U/P} // {R}"
        wait(0)
        for (const token of ["2", "W", "U", "B", "R", "G", "C", "S", "X"]) {
            const symbol = findChild(costSymbols, "manaSymbol-" + token)
            verify(symbol !== null)
            compare(findChild(symbol, "manaGlyph-0").text, ManaSymbols.glyph(token))
            verify(ManaSymbols.glyph(token) !== token)
        }
        const hybrid = findChild(costSymbols, "manaSymbol-W/U")
        verify(hybrid.hybrid)
        compare(hybrid.glyphParts, ["W", "U"])
        compare(findChild(costSymbols, "manaSymbol-2/B").glyphParts, ["2", "B"])
        const phyrexian = findChild(costSymbols, "manaSymbol-G/P")
        verify(phyrexian.phyrexian)
        verify(!phyrexian.hybrid)
        compare(phyrexian.glyphParts, ["P"])
        const hybridPhyrexian = findChild(costSymbols, "manaSymbol-W/U/P")
        verify(hybridPhyrexian.hybrid && hybridPhyrexian.phyrexian)
        compare(hybridPhyrexian.glyphParts, ["P", "P"])
        compare(findChild(costSymbols, "manaSymbol-//").border.width, 0)
    }
    function test_colorFilterGlyphsRetainLabelsAndActions() {
        for (const token of ["W", "U", "B", "R", "G", "C"]) {
            const button = findChild(toolbar, "filterColor-" + token)
            compare(button.contentItem.text, ManaSymbols.glyph(token))
            verify(button.Accessible.name.length > 0)
            button.clicked()
            verify(filters.colors.includes(token))
        }
        costSymbols.cost = undefined
        wait(0)
        const unknown = findChild(costSymbols, "manaSymbol-?")
        compare(findChild(unknown, "manaGlyph-0").text, "?")
        verify(findChild(unknown, "manaGlyph-0").font.family !== ManaSymbols.name)
    }
    function test_compactFrameReservesNameAndCostAtNarrowWidths() {
        presentation.card = {name: "Long canonical card name", displayName: "储电袭客电光人",
            cardColors: "WU", manaCost: "{X}{2}{W/U}{W/U}{U}{U}{U}"}
        presentation.quantity = 100
        for (const width of [240, 320, 440]) {
            presentation.width = width
            wait(0)
            const name = findChild(presentation, "compactCardName")
            const cost = findChild(presentation, "compactCardManaCost")
            const quantity = findChild(presentation, "compactCardQuantity")
            compare(name.text, "储电袭客电光人")
            compare(quantity.text, "100×")
            verify(name.width > 0)
            verify(name.x + name.width <= cost.x)
            verify(cost.mapToItem(presentation, cost.width, 0).x <= presentation.width)
            verify(quantity.mapToItem(presentation, quantity.width, 0).x < name.mapToItem(presentation, 0, 0).x)
        }
    }
    function test_printingRowsRetainOnePhysicalInstance() {
        compare(list.rows.length, 3)
        const rows = list.rows.filter(row => row.card.name === "Shared name")
        compare(rows[0].count, 2)
        compare(rows[1].count, 1)
        compare(rows[0].card.instanceId, "a")
        compare(rows[1].card.collectorNumber, "7†")
        tryVerify(() => list.itemAtIndex(1) !== null)
        const row = list.itemAtIndex(1)
        mouseClick(row, row.width / 2, row.height / 2)
        compare(activate.count, 1)
        compare(activate.signalArguments[0][0].instanceId, "a")
    }
    function test_deckCategorySearchAndSearchFocus() {
        window.requestActivate()
        filters.query = "ramp"
        compare(filters.filter([{name: "Mana rock", category: "Ramp"}]).length, 1)
        toolbar.focusSearch()
        const field = findChild(toolbar, "workbenchSearch")
        tryVerify(() => field.activeFocus)
        compare(field.selectedText, "ramp")
    }
    function test_advancedFiltersScrollWithPinnedDoneAtShortSize() {
        window.width = 580
        window.height = 340
        findChild(toolbar, "advancedCardFiltersButton").clicked()
        const popup = findChild(toolbar, "advancedCardFilters")
        tryVerify(() => popup.opened)
        const done = findChild(popup.contentItem, "closeAdvancedCardFilters")
        tryVerify(() => done.height > 0)
        tryVerify(() => done.mapToItem(window.contentItem, done.width, done.height).y <= window.height)
        verify(done.mapToItem(window.contentItem, done.width, done.height).x <= window.width)
        const creature = findChild(popup.contentItem, "filter-types-Creature")
        creature.clicked()
        compare(filters.types, ["Creature"])
        done.clicked()
        tryVerify(() => !popup.opened)
        compare(filters.types, ["Creature"])
    }
}
