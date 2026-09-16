// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "RulesCardNamePrompt"
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 760
        height: 320
        visible: true

        QtObject {
            id: fakeWs
            property int responseCount: 0
            property int lastPromptId: 0
            property string lastName: ""
            property string lastResponseId: ""

            function respondRulesPromptWithName(promptId, name) {
                responseCount++
                lastPromptId = promptId
                lastName = name
            }
            function respondRulesPrompt(promptId, responseId) {
                responseCount++
                lastPromptId = promptId
                lastResponseId = responseId
            }
        }

        QtObject {
            id: fakeCatalog
            property bool installed: true
            property int searchCount: 0
            property string lastQuery: ""
            property var searchResults: []

            function search(query) {
                searchCount++
                lastQuery = query
                searchResults = [{name: "Lightning Bolt", displayName: "闪电击"}]
            }
            function tableImageSource() { fail("Card-name suggestions must not request art") }
            function setSearchPreviewCards() { fail("Card-name suggestions must not prefetch art") }
        }

        RulesCardNamePrompt {
            id: prompt
            anchors.fill: parent
            anchors.margins: 20
            wsModel: fakeWs
            cardCatalogModel: fakeCatalog
            promptId: testRulesPrompt.session.promptId
            cancellable: testRulesPrompt.session.promptCancellable
        }
    }

    function applyPrompt(id, cancellable) {
        verify(testRulesPrompt.applyPrompt({
            "roomId": "RULE01", "gameId": "card-name-fixture", "pending": true,
            "promptId": id, "kind": "chooseCardName", "supported": true,
            "title": "Name a card", "detail": "Choose a nonland card name",
            "options": [], "choices": [], "cards": [], "scryDestinations": [],
            "targets": [], "contextCards": [], "contextTargets": [],
            "combatSources": [], "combatTargets": [], "damageTargets": [], "totalDamage": 0,
            "cancellable": cancellable
        }))
    }

    function init() {
        prompt.enabled = true
        fakeCatalog.installed = true
        fakeCatalog.searchCount = 0
        fakeCatalog.searchResults = []
        fakeWs.responseCount = 0
        fakeWs.lastPromptId = 0
        fakeWs.lastName = ""
        fakeWs.lastResponseId = ""
        applyPrompt(91, false)
        prompt.resetInput()
    }

    function test_freeNameWorksWithoutCatalog() {
        fakeCatalog.installed = false
        const input = findChild(prompt, "rulesCardNameInput")
        input.text = "  A New Card Name  "
        const confirm = findChild(prompt, "confirmCardNameButton")
        verify(confirm.enabled)
        mouseClick(confirm)
        compare(fakeWs.responseCount, 1)
        compare(fakeWs.lastPromptId, 91)
        compare(fakeWs.lastName, "A New Card Name")
        compare(fakeCatalog.searchCount, 0)
    }

    function test_localSuggestionUsesEnglishNameWithoutSubmitting() {
        const input = findChild(prompt, "rulesCardNameInput")
        testWindow.requestActivate()
        input.forceActiveFocus()
        tryVerify(() => input.activeFocus)
        keyClick(Qt.Key_L)
        compare(input.text.toLowerCase(), "l")
        tryCompare(fakeCatalog, "searchCount", 1)
        compare(fakeCatalog.lastQuery.toLowerCase(), "l")
        const list = findChild(prompt, "rulesCardNameSuggestions")
        tryCompare(list, "count", 1)
        tryVerify(() => list.itemAtIndex(0) !== null)
        mouseClick(list.itemAtIndex(0))
        compare(input.text, "Lightning Bolt")
        compare(fakeWs.responseCount, 0)
        keyClick(Qt.Key_Return)
        compare(fakeWs.responseCount, 1)
        compare(fakeWs.lastName, "Lightning Bolt")
    }

    function test_invalidNamesDoNotSubmit_data() {
        return [
            {tag: "empty", value: "  "},
            {tag: "control", value: "Bad\u0001Name"},
            {tag: "long", value: "a".repeat(257)}
        ]
    }

    function test_invalidNamesDoNotSubmit(data) {
        findChild(prompt, "rulesCardNameInput").text = data.value
        verify(!findChild(prompt, "confirmCardNameButton").enabled)
        prompt.submitName()
        compare(fakeWs.responseCount, 0)
    }

    function test_pendingResponseBlocksDuplicateSubmission() {
        findChild(prompt, "rulesCardNameInput").text = "Lightning Bolt"
        prompt.enabled = false
        prompt.submitName()
        compare(fakeWs.responseCount, 0)
    }

    function test_newPromptClearsInputAndExposesAllowedCancel() {
        verify(!findChild(prompt, "cancelCardNameButton").visible)
        findChild(prompt, "rulesCardNameInput").text = "Lightning Bolt"
        applyPrompt(92, true)
        compare(findChild(prompt, "rulesCardNameInput").text, "")
        verify(!findChild(prompt, "confirmCardNameButton").enabled)
        const cancel = findChild(prompt, "cancelCardNameButton")
        verify(cancel.visible)
        mouseClick(cancel)
        compare(fakeWs.lastPromptId, 92)
        compare(fakeWs.lastResponseId, "$cancel")
        compare(fakeWs.lastName, "")
    }
}
