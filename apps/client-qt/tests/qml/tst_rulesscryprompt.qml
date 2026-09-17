// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "RulesScryPrompt"
    when: windowShown

    ApplicationWindow {
        width: 760
        height: 320
        visible: true

        QtObject {
            id: fakeWs
            property int responseCount: 0
            property int lastPromptId: 0
            property var lastPiles: []

            function respondRulesPromptWithScry(promptId, piles) {
                responseCount++
                lastPromptId = promptId
                lastPiles = piles
            }
        }

        QtObject {
            id: fakeCatalog
            property int imageRevision: 0

            function tableImageSource(name, setCode, collectorNumber) {
                return ""
            }
        }

        RulesScryPrompt {
            id: prompt
            anchors.fill: parent
            anchors.margins: 20
            wsModel: fakeWs
            cardCatalogModel: fakeCatalog
            cardModel: testRulesPrompt.session.promptCards
            destinations: testRulesPrompt.session.promptScryDestinations
            promptId: testRulesPrompt.session.promptId
        }
    }

    function applyPrompt(promptId, destinations, cards) {
        verify(testRulesPrompt.applyPrompt({
            "roomId": "RULE01", "gameId": "rules-scry-fixture",
            "pending": true, "promptId": promptId, "kind": "scry", "supported": true,
            "options": [], "choices": [], "targets": [], "contextCards": [],
            "contextTargets": [], "combatSources": [], "combatTargets": [],
            "damageTargets": [], "totalDamage": 0, "scryDestinations": destinations,
            "cards": cards === undefined ? [
                {"id": "scry:0", "name": "Island", "setCode": "M21",
                 "collectorNumber": "310", "token": false},
                {"id": "scry:1", "name": "Opt", "setCode": "M21",
                 "collectorNumber": "59", "token": false}
            ] : cards
        }))
    }

    function init() {
        fakeWs.responseCount = 0
        fakeWs.lastPromptId = 0
        fakeWs.lastPiles = []
        prompt.cardModel = testRulesPrompt.session.promptCards
        applyPrompt(72, ["libraryTop", "graveyard"])
    }

    function test_realModelExposesCardsToProductionComponent() {
        compare(typeof testRulesPrompt.session.promptCards.items, "function")
        const cards = testRulesPrompt.session.promptCards.items()
        compare(cards.length, 2)
        compare(cards[0].cardId, "scry:0")
        compare(cards[0].name, "Island")
        compare(cards[0].setCode, "M21")
        compare(cards[0].collectorNumber, "310")
        compare(cards[0].token, false)
        compare(prompt.cardsForPile(0).length, 2)
        tryVerify(() => findChild(prompt, "rulesScryCard-scry:0") !== null)
        verify(findChild(prompt, "confirmScryButton").enabled)
    }

    function test_partitionsOrdersAndSubmitsOpaqueCards_data() {
        return [
            {tag: "scry", destination: "libraryBottom"},
            {tag: "surveil", destination: "graveyard"}
        ]
    }

    function test_twoCardsOnTopCanBeReorderedWithVisibleButtons() {
        applyPrompt(73, ["libraryTop", "libraryBottom"])
        tryVerify(() => findChild(prompt, "rulesScryLater-scry:0") !== null)
        const later = findChild(prompt, "rulesScryLater-scry:0")
        verify(later.visible && later.enabled)
        mouseClick(later, later.width / 2, later.height / 2)
        compare(prompt.cardsForPile(0)[0].cardId, "scry:1")
        compare(prompt.cardsForPile(0)[1].cardId, "scry:0")
        const confirm = findChild(prompt, "confirmScryButton")
        mouseClick(confirm, confirm.width / 2, confirm.height / 2)
        compare(fakeWs.lastPiles[0].cardIds.join(","), "scry:1,scry:0")
        compare(fakeWs.lastPiles[1].cardIds.length, 0)
    }

    function test_partitionsOrdersAndSubmitsOpaqueCards(data) {
        applyPrompt(72, ["libraryTop", data.destination])
        compare(prompt.cardsForPile(0).length, 2)
        compare(prompt.cardsForPile(1).length, 0)
        verify(prompt.moveWithinPile("scry:1", 0, -1))
        compare(prompt.cardsForPile(0)[0].cardId, "scry:1")
        verify(prompt.moveCard("scry:0", 0, 1))
        compare(prompt.cardsForPile(0).length, 1)
        compare(prompt.cardsForPile(1)[0].cardId, "scry:0")

        const button = findChild(prompt, "confirmScryButton")
        verify(button.enabled)
        mouseClick(button, button.width / 2, button.height / 2)
        compare(fakeWs.responseCount, 1)
        compare(fakeWs.lastPromptId, 72)
        compare(fakeWs.lastPiles.length, 2)
        compare(fakeWs.lastPiles[0].destination, "libraryTop")
        compare(fakeWs.lastPiles[0].cardIds[0], "scry:1")
        compare(fakeWs.lastPiles[1].destination, data.destination)
        compare(fakeWs.lastPiles[1].cardIds[0], "scry:0")
    }

    function test_rejectsIncompleteOrInvalidPartition_data() {
        return [
            {tag: "empty", ids: [[], []]},
            {tag: "missing", ids: [["scry:0"], []]},
            {tag: "duplicate", ids: [["scry:0"], ["scry:0"]]},
            {tag: "foreign", ids: [["scry:0"], ["scry:9"]]},
            {tag: "missing-destination", ids: [["scry:0", "scry:1"]]}
        ]
    }

    function test_rejectsIncompleteOrInvalidPartition(data) {
        prompt.piles = data.ids.map(ids => ids.map(id => ({
            "cardId": id, "name": "Island", "setCode": "M21",
            "collectorNumber": "310", "token": false
        })))
        const button = findChild(prompt, "confirmScryButton")
        verify(!button.enabled)
        mouseClick(button, button.width / 2, button.height / 2)
        prompt.submitPiles()
        compare(fakeWs.responseCount, 0)
    }

    function test_missingModelCannotSubmitEmptyPlacement() {
        prompt.cardModel = null
        verify(!findChild(prompt, "confirmScryButton").enabled)
        prompt.submitPiles()
        compare(fakeWs.responseCount, 0)
    }

    function test_modelResetReplacesPreviousCards() {
        verify(prompt.moveCard("scry:0", 0, 1))
        applyPrompt(73, ["libraryTop", "graveyard"], [
            {"id": "scry:0", "name": "Solitude", "setCode": "MH2",
             "collectorNumber": "32", "token": false}
        ])
        compare(prompt.cardsForPile(0).length, 1)
        compare(prompt.cardsForPile(0)[0].name, "Solitude")
        compare(prompt.cardsForPile(1).length, 0)
        verify(findChild(prompt, "confirmScryButton").enabled)
    }

    function test_emptyUpstreamPromptAllowsCompleteEmptyPartition() {
        applyPrompt(74, ["libraryTop", "libraryBottom"], [])
        compare(prompt.cardsForPile(0).length, 0)
        verify(findChild(prompt, "confirmScryButton").enabled)
        prompt.submitPiles()
        compare(fakeWs.responseCount, 1)
        compare(fakeWs.lastPiles[0].cardIds.length, 0)
        compare(fakeWs.lastPiles[1].cardIds.length, 0)
    }
}
