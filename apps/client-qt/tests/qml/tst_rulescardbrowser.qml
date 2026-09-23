// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "RulesCardBrowser"
    when: windowShown
    ApplicationWindow { id: window; width: 1180; height: 850; visible: true }
    QtObject {
        id: transport
        property var responses: []
        function respondRulesPrompt(id, response) { responses.push({id:id, response:response}) }
        function respondRulesPromptWithCards(id, response, cards) {
            responses.push({id:id, response:response, cards:cards})
        }
    }
    Component {
        id: selection
        RulesCardSelectionPrompt {
            expandedView: true
            wsModel: transport
            cardCatalogModel: null
            cardModel: testRulesPrompt.session.promptCards
            promptId: testRulesPrompt.session.promptId
            minimumSelections: testRulesPrompt.session.promptMinCardSelections
            maximumSelections: testRulesPrompt.session.promptMaxCardSelections
            cancellable: testRulesPrompt.session.promptCancellable
            confirmationText: qsTranslate("RulesPromptPanel", "Confirm cards")
        }
    }
    Component {
        id: reveal
        RulesRevealPrompt {
            expandedView: true
            wsModel: transport
            cardCatalogModel: null
            cardModel: testRulesPrompt.session.promptCards
            promptId: testRulesPrompt.session.promptId
        }
    }
    function publish(id, kind, minimum, maximum, names, selected, readOnly) {
        verify(testRulesPrompt.applyPrompt({roomId:"CARDS", gameId:"card-browser", pending:true,
            promptId:id, kind:kind, supported:true, title:"Choose cards", detail:"", options:[], choices:[],
            cards:names.map((name, index) => ({id:"candidate-" + index, name:name, setCode:"", collectorNumber:"", token:false,
                selected:(selected || []).includes(index), readOnly:(readOnly || []).includes(index)})),
            minCardSelections:minimum, maxCardSelections:maximum, cancellable:kind === "chooseCards",
            scryDestinations:[], targets:[], contextCards:[], contextTargets:[], combatSources:[], combatTargets:[],
            damageTargets:[], totalDamage:0}))
    }
    function create(component, width, height) {
        const prompt = createTemporaryObject(component, window.contentItem, {width:width || 960, height:height || 700})
        verify(prompt !== null)
        waitForRendering(prompt)
        return prompt
    }
    function grid(prompt, name) {
        const result = findChild(prompt, name || "rulesCardCandidates")
        verify(result !== null)
        return result
    }
    function choose(list, index) {
        list.positionViewAtIndex(index, GridView.Contain)
        waitForRendering(list)
        verify(list.itemAtIndex(index) !== null)
        mouseClick(list.itemAtIndex(index))
    }
    function init() {
        window.requestActivate()
        tryCompare(window, "active", true)
        Theme.uiScale = 1
        testTranslations.setLanguage("en")
        transport.responses = []
        publish(1, "chooseCards", 2, 2, ["Sacred Foundry", "Sacred Foundry", "Plains", "Mountain"])
    }
    function cleanup() {
        testRulesPrompt.clear()
        Theme.uiScale = 1
        testTranslations.setLanguage("en")
    }
    function test_nativeSelectionPersistsWithoutResubmitting_data() {
        return [{tag:"compact", expanded:false}, {tag:"expanded", expanded:true}]
    }
    function test_nativeSelectionPersistsWithoutResubmitting(data) {
        publish(2, "chooseCards", 1, 1, ["Forest", "Island", "Ornithopter"], [0])
        const prompt = create(selection)
        prompt.expandedView = data.expanded
        const list = grid(prompt)
        tryCompare(list, "count", 3)
        waitForRendering(list)
        const first = list.itemAtIndex(0)
        verify(first !== null)
        compare(first.nativeSelected, true)
        compare(first.selected, false)
        compare(first.selectionLabel, "Already selected")
        compare(prompt.nativeSelectedCount, 1)
        compare(prompt.selectedCount, 0)
        verify(!findChild(prompt, "rulesConfirmCards").enabled,
            "An existing engine selection is not a new click")
        mouseClick(first)
        compare(first.selectionLabel, "Undo selection")
        mouseClick(findChild(prompt, "rulesConfirmCards"))
        compare(transport.responses[0].cards, ["candidate-0"])
        publish(3, "chooseCards", 1, 1, ["Forest", "Island", "Ornithopter"], [])
        tryCompare(prompt, "nativeSelectedCount", 0)
        compare(prompt.selectedCount, 0)
        publish(4, "chooseCards", 1, 1, ["Forest", "Island", "Ornithopter"], [0])
        tryCompare(prompt, "nativeSelectedCount", 1)
        waitForRendering(list)
        mouseClick(list.itemAtIndex(1))
        mouseClick(findChild(prompt, "rulesConfirmCards"))
        compare(transport.responses[1].cards, ["candidate-1"],
            "Continuing the effect must not toggle off the previous selection")
        if (data.expanded) {
            prompt.resetSelection()
            mouseClick(findChild(prompt, "rulesSelectedCardsOnly"))
            tryCompare(list, "count", 1)
            compare(list.itemAtIndex(0).nativeSelected, true)
        }
    }
    function test_filterPreservesExactSelectionsAndBounds() {
        const prompt = create(selection), list = grid(prompt)
        const search = findChild(prompt, "rulesCardFilter")
        tryCompare(list, "count", 4)
        search.text = "  sACred  "
        tryCompare(list, "count", 2)
        choose(list, 1)
        compare(prompt.selectedIds, {"candidate-1":true})
        search.text = "plains"
        tryCompare(list, "count", 1)
        choose(list, 0)
        compare(prompt.selectedCount, 2)
        search.text = "mountain"
        choose(list, 0)
        compare(prompt.selectedCount, 2, "Filtering must not bypass the native maximum")
        search.text = "no such candidate"
        tryCompare(list, "count", 0)
        const confirm = findChild(prompt, "rulesConfirmCards")
        verify(confirm.enabled, "Hidden selected cards remain part of the decision")
        mouseClick(confirm)
        compare(transport.responses, [{id:1, response:"$submit", cards:["candidate-1", "candidate-2"]}])
    }
    function test_selectedOnlyAllowsDeselectingFilteredCards() {
        const prompt = create(selection), list = grid(prompt)
        choose(list, 0); choose(list, 2)
        mouseClick(findChild(prompt, "rulesSelectedCardsOnly"))
        tryCompare(list, "count", 2)
        choose(list, 0)
        tryCompare(list, "count", 1)
        compare(prompt.selectedCount, 1)
        verify(!findChild(prompt, "rulesConfirmCards").enabled)
        mouseClick(findChild(prompt, "rulesCancelCards"))
        compare(transport.responses, [{id:1, response:"$cancel"}])
    }
    function test_completeDisclosureAndSelectableFilter() {
        publish(2, "chooseCards", 1, 1, ["Swamp", "Forest", "Grizzly Bears", "Swamp"], [], [1, 2])
        const prompt = create(selection), list = grid(prompt)
        const filter = findChild(prompt, "rulesSelectableCardsOnly")
        const search = findChild(prompt, "rulesCardFilter")
        compare(filter.checked, false)
        tryCompare(list, "count", 4)
        choose(list, 1)
        compare(list.itemAtIndex(1).selectionLabel, "Not selectable")
        compare(prompt.selectedCount, 0)
        list.forceActiveFocus()
        keyClick(Qt.Key_Space)
        keyClick(Qt.Key_Return)
        compare(prompt.selectedCount, 0, "Keyboard cannot select display-only cards")
        prompt.toggleCard("candidate-2")
        compare(prompt.selectedCount, 0)
        choose(list, 3)
        mouseClick(filter)
        tryCompare(list, "count", 2)
        compare(prompt.selectedIds, {"candidate-3":true})
        compare(list.itemAtIndex(1).cardId, "candidate-3", "Same-name cards retain exact identities")
        search.text = "Forest"
        tryCompare(list, "count", 0)
        mouseClick(filter)
        tryCompare(list, "count", 1)
        choose(list, 0)
        compare(prompt.selectedIds, {"candidate-3":true})
        mouseClick(findChild(prompt, "rulesConfirmCards"))
        compare(transport.responses, [{id:2, response:"$submit", cards:["candidate-3"]}])
        mouseClick(filter)
        publish(3, "chooseCards", 0, 0, ["Mountain"], [], [0])
        tryCompare(list, "count", 1)
        compare(filter.checked, false)
        compare(search.text, "")
        compare(prompt.selectedCount, 0)
        mouseClick(filter)
        tryCompare(list, "count", 0)
        mouseClick(findChild(prompt, "rulesConfirmCards"))
        compare(transport.responses[1], {id:3, response:"$submit", cards:[]})
    }
    function test_compactDisclosureCannotSelect() {
        publish(2, "chooseCards", 1, 1, ["Forest", "Grizzly Bears"], [], [0])
        const prompt = create(selection)
        prompt.expandedView = false
        const list = grid(prompt)
        tryCompare(list, "count", 2)
        waitForRendering(list)
        mouseClick(list.itemAtIndex(0))
        compare(prompt.selectedCount, 0)
        list.itemAtIndex(0).forceActiveFocus()
        keyClick(Qt.Key_Space)
        keyClick(Qt.Key_Return)
        compare(prompt.selectedCount, 0)
        mouseClick(list.itemAtIndex(1))
        mouseClick(findChild(prompt, "rulesConfirmCards"))
        compare(transport.responses, [{id:2, response:"$submit", cards:["candidate-1"]}])
    }
    function test_newPromptClearsFilterAndSelection() {
        const prompt = create(selection), list = grid(prompt)
        const search = findChild(prompt, "rulesCardFilter")
        search.text = "Sacred"
        choose(list, 0)
        publish(2, "chooseCards", 1, 1, ["Guide of Souls"])
        tryCompare(list, "count", 1)
        compare(search.text, "")
        compare(prompt.selectedCount, 0)
        choose(list, 0)
        mouseClick(findChild(prompt, "rulesConfirmCards"))
        compare(transport.responses, [{id:2, response:"$submit", cards:["candidate-0"]}])
    }
    function test_readOnlyRevealCannotSelect_data() {
        return [{tag:"cards", names:["Sacred Foundry", "Plains"]}, {tag:"empty", names:[]}]
    }
    function test_readOnlyRevealCannotSelect(data) {
        publish(2, "revealCards", 0, 0, data.names)
        const prompt = create(reveal), list = grid(prompt, "revealCardList")
        tryCompare(list, "count", data.names.length)
        if (list.count > 0) choose(list, 0)
        compare(transport.responses.length, 0)
        verify(!findChild(prompt, "rulesSelectedCardsOnly").visible)
        verify(!findChild(prompt, "rulesSelectableCardsOnly").visible)
        mouseClick(findChild(prompt, "acknowledgeRevealButton"))
        compare(transport.responses, [{id:2, response:"$ack"}])
    }
    function test_largeListsAndTranslatedControlsRemainReachable_data() {
        return [{tag:"desktop", width:1080, height:780, scale:1, language:"en"},
            {tag:"compact", width:680, height:510, scale:1, language:"zh"},
            {tag:"scaled", width:960, height:740, scale:1.35, language:"zh"}]
    }
    function test_largeListsAndTranslatedControlsRemainReachable(data) {
        Theme.uiScale = data.scale
        testTranslations.setLanguage(data.language)
        publish(3, "chooseCards", 1, 1, Array.from({length:100}, (_, i) => "Card " + i))
        const prompt = create(selection, data.width, data.height), list = grid(prompt)
        tryCompare(list, "count", 100)
        list.forceActiveFocus()
        keyClick(Qt.Key_End)
        waitForRendering(list)
        verify(list.contentY > 0)
        const before = list.contentY
        keyClick(Qt.Key_Space)
        compare(prompt.selectedIds, {"candidate-99":true})
        compare(list.contentY, before, "Selecting a late card must not jump back to the first row")
        const confirm = findChild(prompt, "rulesConfirmCards")
        const edge = confirm.mapToItem(prompt, confirm.width, confirm.height)
        verify(edge.x <= prompt.width + 1 && edge.y <= prompt.height + 1)
        verify(confirm.mapToItem(list, 0, 0).y >= list.height)
        mouseClick(confirm)
        compare(transport.responses, [{id:3, response:"$submit", cards:["candidate-99"]}])
    }
}
