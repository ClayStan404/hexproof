// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "RulesCardSelectionCancellation"
    when: windowShown

    ApplicationWindow {
        width: 760
        height: 260
        visible: true

        QtObject {
            id: transport
            property int responses: 0
            property string responseId: ""
            property int promptId: 0
            function respondRulesPrompt(id, response) {
                responses++
                promptId = id
                responseId = response
            }
        }

        RulesCardSelectionPrompt {
            id: prompt
            anchors.fill: parent
            anchors.margins: 20
            wsModel: transport
            cardCatalogModel: null
            cardModel: testRulesPrompt.session.promptCards
            promptId: testRulesPrompt.session.promptId
            minimumSelections: testRulesPrompt.session.promptMinCardSelections
            maximumSelections: testRulesPrompt.session.promptMaxCardSelections
            cancellable: testRulesPrompt.session.promptCancellable
            confirmationText: "Confirm cards"
        }
    }

    function applyPrompt(cancellable) {
        verify(testRulesPrompt.applyPrompt({
            roomId: "RULE01", gameId: "card-cost", pending: true,
            promptId: 81, kind: "chooseCards", supported: true,
            title: "Discard a card", detail: "Choose a card to pay the cost",
            options: [], choices: [], cards: [{id: "card-1", name: "Plains", setCode: "", collectorNumber: "", token: false}],
            minCardSelections: 1, maxCardSelections: 1, cancellable: cancellable,
            scryDestinations: [], targets: [], contextCards: [], contextTargets: [],
            combatSources: [], combatTargets: [], damageTargets: [], totalDamage: 0
        }))
    }

    function init() {
        transport.responses = 0
        transport.responseId = ""
        prompt.enabled = true
        prompt.resetSelection()
        applyPrompt(true)
    }

    function test_cancelDoesNotRequirePayingTheCost() {
        compare(prompt.validSelection, false)
        const cancel = findChild(prompt, "rulesCancelCards")
        verify(cancel.visible && cancel.enabled)
        mouseClick(cancel)
        compare(transport.responses, 1)
        compare(transport.promptId, 81)
        compare(transport.responseId, "$cancel")
    }

    function test_cancelDoesNotSubmitSelectedCards() {
        prompt.toggleCard("card-1")
        compare(prompt.selectedCount, 1)
        mouseClick(findChild(prompt, "rulesCancelCards"))
        compare(transport.responses, 1)
        compare(transport.responseId, "$cancel")
    }

    function test_mandatoryAndPendingInputsCannotCancel() {
        applyPrompt(false)
        const cancel = findChild(prompt, "rulesCancelCards")
        verify(!cancel.visible)
        applyPrompt(true)
        prompt.enabled = false
        verify(!cancel.enabled)
        compare(transport.responses, 0)
    }
}
