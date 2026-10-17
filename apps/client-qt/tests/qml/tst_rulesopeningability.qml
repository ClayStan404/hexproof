// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "RulesOpeningAbility"
    when: windowShown

    ApplicationWindow {
        id: window
        width: 1120; height: 850; visible: true
        RulesCardChoiceDialog { id: dialog; tableController: controller }
    }
    QtObject {
        id: transport
        property var responses: []
        function respondRulesPromptWithCards(promptId, responseId, cards) {
            responses = responses.concat([{promptId: promptId, responseId: responseId, cards: cards}])
        }
    }
    QtObject {
        id: controller
        property var rulesSession: testRulesPrompt.session
        property var interaction: ({contextActive: rulesSession.promptPending})
        property var cardCatalogModel: null
        property var wsModel: transport
        property bool rulesResponsePending: false
        property int localSeat: 1
        function cardDisplayName(name) { return name }
        function promptTitle(kind, title) { return RulesText.title(kind, title, "") }
        function promptDetail(kind, detail) { return RulesText.text(detail) }
    }

    function apply(cards) {
        verify(testRulesPrompt.applyPrompt({
            roomId: "OPEN01", gameId: "opening-ability", pending: true,
            promptId: 71, kind: "chooseCards", supported: true,
            title: "Choose cards to activate from opening hand and their order",
            detail: "", options: [], choices: [], cards: cards,
            minCardSelections: 0, maxCardSelections: cards.length,
            scryDestinations: [], targets: [], contextCards: [], contextTargets: [],
            combatSources: [], combatTargets: [], damageTargets: [], totalDamage: 0
        }))
        tryCompare(dialog, "visible", true)
    }
    function init() {
        testTranslations.setLanguage("en")
        transport.responses = []
    }
    function cleanup() { testRulesPrompt.clear() }

    function test_optionalOpeningAbilityKeepsNativeCardResponse_data() {
        return [
            {tag: "gemstone-use", name: "Gemstone Caverns", use: true},
            {tag: "gemstone-leave", name: "Gemstone Caverns", use: false},
            {tag: "devourer-use", name: "Devourer of Destiny", use: true},
            {tag: "leyline-leave", name: "Leyline of the Void", use: false}
        ]
    }
    function test_optionalOpeningAbilityKeepsNativeCardResponse(data) {
        apply([{id: "opaque-opening-card", name: data.name}])
        const content = dialog.contentItem
        tryVerify(() => findChild(content, "rulesOpeningAbilityUse") !== null)
        compare(findChild(content, "rulesChoiceTitle").text, "Use " + data.name + "'s opening ability?")
        compare(findChild(content, "rulesChoiceDetail").text,
                "Use this card's opening ability, or leave it in your hand.")
        tryVerify(() => findChild(content, "rulesCardSelectionPrompt") === null)
        mouseClick(findChild(content, data.use ? "rulesOpeningAbilityUse" : "rulesOpeningAbilitySkip"))
        compare(transport.responses, [{promptId: 71, responseId: "$submit",
            cards: data.use ? ["opaque-opening-card"] : []}])
    }
    function test_multipleOpeningAbilitiesKeepOrderedSelection() {
        apply([{id: "opaque-leyline", name: "Leyline of the Void"},
               {id: "opaque-gemstone", name: "Gemstone Caverns"}])
        tryVerify(() => findChild(dialog.contentItem, "rulesCardSelectionPrompt") !== null)
        verify(findChild(dialog.contentItem, "rulesOpeningAbilityUse") === null)
        compare(transport.responses.length, 0)
    }
}
