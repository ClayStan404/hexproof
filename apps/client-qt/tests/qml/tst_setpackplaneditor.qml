// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "SetPackPlanEditor"
    when: windowShown

    ApplicationWindow { id: window; width: 1100; height: 760; visible: true }
    readonly property var sets: [
        {id: "AAA", productId: "a", name: "Alpha", productName: "Alpha booster", cardsPerPack: 14, authentic: true},
        {id: "BBB", productId: "b", name: "Beta", productName: "Beta booster", cardsPerPack: 15, authentic: false},
        {id: "CCC", productId: "c", name: "Gamma", productName: "Gamma booster", cardsPerPack: 14, authentic: true}]
    QtObject {
        id: catalog
        function limitedProduct(id) { return {id: id, cardsPerPack: id === "b" ? 15 : 14} }
    }
    Component {
        id: editorComponent
        SetPackPlanEditor { width: 620; sets: testCase.sets; cardCatalogModel: catalog; defaultSetId: "AAA" }
    }
    id: testCase

    function test_defaultsStaySingleProductUntilCustomized() {
        const editor = createTemporaryObject(editorComponent, window.contentItem)
        compare(editor.custom, false)
        compare(editor.makePlan(), {})
        compare(editor.rows, [{setId: "AAA", count: "6"}])
        editor.eventType = "set_draft"
        compare(editor.rows.length, 3)
        compare(editor.totalPacks, 3)
        compare(editor.makePlan(), {})
    }

    function test_sealedMergesOnlyMatchingProductsInFirstAppearanceOrder() {
        const editor = createTemporaryObject(editorComponent, window.contentItem, {custom: true})
        editor.rows = [{setId: "BBB", count: "2"}, {setId: "AAA", count: "2"},
                       {setId: "CCC", count: "1"}, {setId: "BBB", count: "1"}]
        verify(editor.valid)
        compare(editor.totalPacks, 6)
        compare(editor.makePlan(), {products: [{id: "b", cardsPerPack: 15}, {id: "a", cardsPerPack: 14},
                                             {id: "c", cardsPerPack: 14}],
                                   entries: [{productId: "b", count: 3}, {productId: "a", count: 2},
                                             {productId: "c", count: 1}]})
        verify(findChild(editor, "setPackPlanSummary").text.includes("approximate"))
    }

    function test_rowEditsAndModeResetsKeepControlsInSync() {
        const editor = createTemporaryObject(editorComponent, window.contentItem, {custom: true})
        const firstSet = findChild(editor, "setPackPlanSet-0")
        const firstCount = findChild(editor, "setPackPlanCount-0")
        firstSet.selectedId = "BBB"
        firstCount.text = "2"
        compare(editor.makePlan().entries, [{productId: "b", count: 2}])
        editor.eventType = "set_draft"
        compare(editor.rows.length, 3)
        compare(findChild(editor, "setPackPlanSet-0").selectedId, "AAA")
        compare(findChild(editor, "setPackPlanCount-0").text, "1")
        compare(editor.makePlan().entries, [{productId: "a", count: 1}, {productId: "a", count: 1},
                                           {productId: "a", count: 1}])
        editor.eventType = "set_sealed"
        compare(findChild(editor, "setPackPlanCount-0").text, "6")
        findChild(editor, "setPackPlanAdd").clicked()
        compare(editor.rows.length, 2)
        findChild(editor, "setPackPlanSet-1").selectedId = "CCC"
        compare(editor.makePlan().entries, [{productId: "a", count: 6}, {productId: "c", count: 1}])
    }

    function test_summaryResolvesPackLengthFromProductDefinitions() {
        const summaries = sets.map(set => {
            const summary = Object.assign({}, set)
            delete summary.cardsPerPack
            return summary
        })
        const editor = createTemporaryObject(editorComponent, window.contentItem,
                                              {custom: true, sets: summaries})
        editor.rows = [{setId: "AAA", count: "2"}, {setId: "BBB", count: "2"}]
        const summary = findChild(editor, "setPackPlanSummary")
        verify(summary.text.includes("14 cards per pack"))
        verify(summary.text.includes("15 cards per pack"))
        editor.rows = [{setId: "BBB", count: "3"}]
        compare(Object.keys(editor.cachedProducts), ["b"])
        verify(summary.text.includes("15 cards per pack"))
    }

    function test_draftRetainsABAAndEachRoundHasOnePack() {
        const editor = createTemporaryObject(editorComponent, window.contentItem,
                                              {eventType: "set_draft", custom: true})
        editor.rows = [{setId: "AAA", count: "1"}, {setId: "BBB", count: "1"}, {setId: "AAA", count: "1"}]
        verify(editor.valid)
        compare(editor.makePlan().products.length, 2)
        compare(editor.makePlan().entries, [{productId: "a", count: 1}, {productId: "b", count: 1},
                                           {productId: "a", count: 1}])
        editor.updateRow(1, "count", "2")
        verify(!editor.valid)
        compare(editor.makePlan(), {})
        editor.rows = [{setId: "AAA", count: "1"}, {setId: "BBB", count: "1"}]
        verify(!editor.valid)
    }

    function test_invalidCountsAndTotals_data() {
        return [
            {tag: "zero", rows: [{setId: "AAA", count: "0"}]},
            {tag: "negative", rows: [{setId: "AAA", count: "-1"}]},
            {tag: "fraction", rows: [{setId: "AAA", count: "1.5"}]},
            {tag: "empty", rows: [{setId: "AAA", count: ""}]},
            {tag: "too-many", rows: [{setId: "AAA", count: "12"}, {setId: "BBB", count: "1"}]},
            {tag: "unknown", rows: [{setId: "unknown", count: "1"}]}]
    }
    function test_invalidCountsAndTotals(data) {
        const editor = createTemporaryObject(editorComponent, window.contentItem, {custom: true})
        editor.rows = data.rows
        verify(!editor.valid)
        compare(editor.makePlan(), {})
    }
}
