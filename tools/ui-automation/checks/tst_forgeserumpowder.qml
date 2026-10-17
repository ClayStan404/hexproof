// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../../apps/client-qt/qml/components" as Components
import "../scenarios/ForgeSerumPowderStudy.js" as Powder

TestCase {
    id: testCase
    name: "ForgeSerumPowderPlayer"
    width: 1280
    height: 720
    visible: true
    when: windowShown
    property var answers: []

    QtObject {
        id: auditProbe
        function record(name, value) {}
    }
    QtObject {
        id: wsModel
        function respondRulesPromptWithCards(promptId, responseId, ids) {
            testCase.answers.push({promptId:promptId, responseId:responseId, ids:ids})
        }
    }
    ListModel {
        id: cards
        ListElement { cardId: "powder-first"; name: "Serum Powder"; setCode: "IMA"; collectorNumber: "228"; token: false }
        ListElement { cardId: "powder-second"; name: "Serum Powder"; setCode: "IMA"; collectorNumber: "228"; token: false }
        ListElement { cardId: "plains"; name: "Plains"; setCode: "C15"; collectorNumber: "323"; token: false }
        ListElement { cardId: "stone"; name: "Mind Stone"; setCode: "WTH"; collectorNumber: "153"; token: false }
    }
    Components.RulesCardSelectionPrompt {
        id: selection
        width: testCase.width
        height: implicitHeight
        wsModel: wsModel
        cardCatalogModel: null
        cardModel: cards
        promptId: 1
        minimumSelections: 1
        maximumSelections: 1
        confirmationText: "Put on bottom"
    }

    function test_londonBottomKeepsTheExactRequestedPowder_data() {
        return [{tag:"one owed", owed:1, retained:"powder-first", expected:["powder-second"]},
            {tag:"two owed and second Powder retained", owed:2, retained:"powder-second", expected:["powder-first", "stone"]}]
    }
    function test_londonBottomKeepsTheExactRequestedPowder(data) {
        answers = []
        selection.minimumSelections = data.owed
        selection.maximumSelections = data.owed
        selection.promptId++
        const driver = {variant:"serum-powder-mulligan",
            session:{promptMinCardSelections:data.owed, promptMaxCardSelections:data.owed},
            item:name => findChild(selection, name), capture:() => {},
            require:(ok, message) => verify(ok, message),
            click:name => {
                const control = findChild(selection, name)
                verify(!!control, name)
                mouseClick(control)
                return true
            }}
        for (let i = 0; i <= data.owed; i++) {
            Powder.bottomCards(driver, data.owed, data.retained)
            wait(0)
        }
        compare(answers.length, 1)
        compare(answers[0].promptId, selection.promptId)
        compare(answers[0].responseId, "$submit")
        compare(answers[0].ids, data.expected)
        verify(!answers[0].ids.includes(data.retained))
    }

    function test_spellCostsUseRegistrationRatherThanMissingViewerRoles() {
        // Actual RulesCardModel/cardForInspection exposes no manaValue role.
        const registration = {mainboard:[{name:"Serum Powder", manaValue:3},
            {name:"Mind Stone", manaValue:2}]}
        compare(Powder.registeredCost({cardId:"powder", name:"Serum Powder", zone:"hand"}, registration), 3)
        compare(Powder.registeredCost({cardId:"stone", name:"Mind Stone", zone:"hand"}, registration), 2)
        compare(Powder.registeredCost({name:"Unknown identity"}, registration), Infinity)
    }
}
