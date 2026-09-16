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
    Component {
        id: visibleRowComponent
        CardListRow { }
    }
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
        Theme.uiScale = 1
        filters.reset()
        filters.query = ""
        activate.clear()
        window.width = 900
        window.height = 600
    }
    function cleanup() {
        Theme.uiScale = 1
        Theme.uiTheme = "classic"
    }
    function test_inactiveFilterPreservesTheExistingCollection() {
        verify(filters.filter(cards) === cards)
        filters.query = "   "
        verify(filters.filter(cards) === cards)
        filters.query = " CHINESE "
        compare(filters.filter(cards).map(card => card.instanceId), ["d"])
        filters.query = ""
        filters.colors = ["W", "G"]
        compare(filters.filter(cards).length, 3)
        filters.reset()
        verify(filters.filter(cards) === cards)
    }

    function test_categoriesCombineWithEverySelectedColor() {
        filters.colors = ["W", "G"]
        filters.types = ["Instant", "Creature"]
        compare(filters.filter(cards).length, 3)
        filters.rarities = ["rare", "mythic"]
        compare(filters.filter(cards).length, 3)
        filters.manaValues = ["0", "1"]
        compare(filters.filter(cards).length, 0)
        filters.reset()
        filters.types = ["Instant"]
        compare(filters.filter(cards)[0].name, "Chinese instant")
    }
    function test_colorSelectionsRequireEveryChosenColor_data() {
        return [
            {tag: "white and blue", selected: ["W", "U"], expected: ["WU", "WUG"]},
            {tag: "selection order", selected: ["U", "W"], expected: ["WU", "WUG"]},
            {tag: "three colors", selected: ["W", "U", "G"], expected: ["WUG"]},
            {tag: "blue", selected: ["U"], expected: ["U", "WU", "WUG", "UB"]},
            {tag: "white multicolor", selected: ["M", "W"], expected: ["WU", "WUG", "WG"]},
            {tag: "colorless", selected: ["C"], expected: [""]},
            {tag: "incompatible colors", selected: ["C", "W"], expected: []}
        ]
    }
    function test_colorSelectionsRequireEveryChosenColor(data) {
        const pool = ["W", "U", "WU", "WUG", "WG", "UB", "", undefined, null]
            .map(color => ({name: String(color), colors: color, manaValue: 2}))
        filters.colors = data.selected
        compare(filters.filter(pool).map(card => card.colors), data.expected)
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
    function test_compactFrameReservesNameAndCostAtNarrowWidths_data() {
        return [{tag: "normal", scale: 1}, {tag: "maximum", scale: 1.8}]
    }
    function test_compactFrameReservesNameAndCostAtNarrowWidths(data) {
        Theme.uiScale = data.scale
        // TestCase is invisible. Geometry fixtures must belong to the visible
        // window so nested layouts are polished as they are in the application.
        const row = createTemporaryObject(visibleRowComponent, window.contentItem, {
            width: 320, quantity: 100,
            card: {name: "Long canonical card name", displayName: "储电袭客电光人",
                cardColors: "WU", manaCost: "{X}{2}{W/U}{W/U}{U}{U}{W}"}
        })
        verify(row !== null)
        verify(row.visible)
        for (const width of [240, 320, 440, 240]) {
            row.width = width
            verify(waitForPolish(window))
            const name = findChild(row, "compactCardName")
            const cost = findChild(row, "compactCardManaCost")
            const quantity = findChild(row, "compactCardQuantity")
            const bounds = "row width=" + row.width + ", scale=" + data.scale
                + ", cost right=" + cost.mapToItem(row, cost.width, 0).x
            compare(name.text, "储电袭客电光人")
            compare(quantity.text, "100×")
            verify(name.width > 0, bounds)
            verify(cost.width > 0, bounds)
            verify(name.x + name.width <= cost.x, bounds)
            verify(Math.abs(cost.x + cost.width - cost.parent.width) <= Theme.size(1), bounds)
            verify(cost.mapToItem(row, cost.width, 0).x <= row.width, bounds)
            verify(quantity.mapToItem(row, quantity.width, 0).x
                   < name.mapToItem(row, 0, 0).x, bounds)
            const firstSymbol = findChild(cost, "manaSymbol-X")
            const lastSymbol = findChild(cost, "manaSymbol-W")
            verify(firstSymbol !== null && lastSymbol !== null)
            verify(firstSymbol.mapToItem(row, 0, 0).x
                   >= name.mapToItem(row, name.width, 0).x, bounds)
            verify(lastSymbol.mapToItem(row, lastSymbol.width, 0).x <= row.width, bounds)
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
    function test_advancedFiltersKeepMultipleSelectionsVisible_data() {
        return [{tag: "classic", theme: "classic"}, {tag: "glass", theme: "glass"}]
    }
    function test_advancedFiltersKeepMultipleSelectionsVisible(data) {
        Theme.uiTheme = data.theme
        window.height = 820
        findChild(toolbar, "advancedCardFiltersButton").clicked()
        const popup = findChild(toolbar, "advancedCardFilters")
        tryVerify(() => popup.opened)
        const white = findChild(popup.contentItem, "filter-colors-W")
        const blue = findChild(popup.contentItem, "filter-colors-U")
        const creature = findChild(popup.contentItem, "filter-types-Creature")
        const instant = findChild(popup.contentItem, "filter-types-Instant")
        for (const option of [white, blue, creature, instant]) {
            mouseClick(option, option.width / 2, option.height / 2)
            verify(option.checked)
        }
        compare(filters.colors, ["W", "U"])
        compare(filters.types, ["Creature", "Instant"])
        const pool = cards.concat([
            {name: "White-blue creature", colors: "WU", typeLine: "Creature"},
            {name: "White-blue-green instant", colors: "WUG", typeLine: "Instant"}
        ])
        compare(filters.filter(pool).map(card => card.name),
                ["White-blue creature", "White-blue-green instant"])
        const done = findChild(popup.contentItem, "closeAdvancedCardFilters")
        done.forceActiveFocus()
        for (const option of [white, blue, creature, instant]) {
            verify(!option.activeFocus)
            verify(option.checked)
            compare(option.leadingText, "☑")
            compare(option.variant, "primary")
        }
        verify(waitForPolish(window))
        mouseClick(done, done.width / 2, done.height / 2)
        tryVerify(() => !popup.opened)
        findChild(toolbar, "advancedCardFiltersButton").clicked()
        tryVerify(() => popup.opened)
        verify(white.checked && blue.checked && creature.checked && instant.checked)
        mouseClick(white, white.width / 2, white.height / 2)
        verify(!white.checked && blue.checked)
        compare(filters.colors, ["U"])
        compare(filters.filter(pool).map(card => card.name),
                ["Chinese instant", "White-blue creature", "White-blue-green instant"])
        filters.reset()
        for (const option of [white, blue, creature, instant]) verify(!option.checked)
        mouseClick(done, done.width / 2, done.height / 2)
    }
}
