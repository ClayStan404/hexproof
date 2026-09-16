// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "RulesTableInteraction"
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 520; height: 350; visible: true
        RulesTargetSelectionPrompt {
            id: targetPrompt
            anchors.fill: parent
            anchors.margins: 12
            interaction: tableInteraction
            wsModel: responder
            cardCatalogModel: null
            targetModel: controller.rulesSession.promptTargets
            promptId: controller.rulesSession.promptId
            minimumSelections: controller.rulesSession.promptMinSelections
            maximumSelections: controller.rulesSession.promptMaxSelections
            cancellable: controller.rulesSession.promptCancellable
            enabled: !controller.rulesResponsePending
        }
    }
    QtObject {
        id: controller
        property var rulesSession: testRulesPrompt.session
        property bool roomConnected: true
        property bool sideboarding: false
        property bool rulesResponsePending: false
        property int localSeat: 0
        property int handOwnerSeat: 0
        property bool stackTargetsVisible: true
        property var wsModel: responder
        property var cardActionPicker: picker
    }
    QtObject {
        id: responder
        property var responses: []
        function respondRulesPrompt(promptId, responseId) {
            responses = responses.concat([{promptId: promptId, responseId: responseId}])
            controller.rulesResponsePending = true
        }
        function respondRulesPromptWithTargets(promptId, responseId, targets) {
            responses = responses.concat([{promptId: promptId, responseId: responseId, targets: targets}])
            controller.rulesResponsePending = true
        }
    }
    QtObject {
        id: picker
        property string cardId: ""
        property var actions: []
        function showFor(id, name, options) { cardId = id; actions = options }
    }
    RulesTableInteraction { id: tableInteraction; tableController: controller }

    function snapshot(gameId) {
        function card(id, name) {
            return {id: id, visible: true, identity: {name: name}, ownerSeat: 0, controllerSeat: 0}
        }
        return {
            roomId: "DIRECT", gameId: gameId || "direct-game", turn: 1, step: "main1",
            activeSeat: 0, prioritySeat: 0, players: [{seat: 0, name: "Same name", life: 20},
                {seat: 2, name: "Same name", life: 20}],
            zones: [{zone: "battlefield", ownerSeat: 0, count: 1, cards: [card("card:mana", "Forest")]},
                {zone: "hand", ownerSeat: 0, count: 1, cards: [card("card:hand", "Forest")]},
                {zone: "graveyard", ownerSeat: 0, count: 1, cards: [card("card:grave", "Grizzly Bears")]}],
            stack: [{id: "stack:spell", name: "Lightning Bolt", controllerSeat: 0}]
        }
    }
    function prompt(kind, options, targets, minimum, maximum) {
        return {roomId: "DIRECT", gameId: "direct-game", pending: true, promptId: 7,
            supported: true, kind: kind, title: "Choose", detail: "Choose an action or target",
            options: options || [], targets: targets || [], minSelections: minimum || 0,
            maxSelections: maximum || 0, cancellable: true, totalDamage: 0,
            choices: [], cards: [], scryDestinations: [], contextCards: [], contextTargets: [],
            combatSources: [], combatTargets: [], damageTargets: []}
    }
    function target(id, kind, objectId, seat) {
        const row = {responseId: id, kind: kind, objectId: objectId, label: "Same name"}
        if (seat !== undefined) row.seat = seat
        return row
    }
    function applyTargets(maximum, extra) {
        const rows = [target("target:0", "card", "card:mana"), target("target:1", "player", "", 2)]
        verify(testRulesPrompt.applyPrompt(prompt("chooseBoardTargets", [], rows.concat(extra || []), 1, maximum)))
    }
    function init() {
        testWindow.requestActivate()
        testRulesPrompt.clear()
        controller.roomConnected = true
        controller.sideboarding = false
        controller.rulesResponsePending = false
        controller.localSeat = 0
        controller.stackTargetsVisible = true
        responder.responses = []
        picker.cardId = ""
        picker.actions = []
        verify(testRulesPrompt.applySnapshot(snapshot()))
    }
    function cleanup() { testRulesPrompt.clear() }

    function test_singleCardActionsUseCurrentOpaqueResponse_data() {
        return [{tag: "land", kind: "playLand", promptKind: "chooseAction", cardId: "card:hand"},
            {tag: "spell", kind: "cast", promptKind: "chooseAction", cardId: "card:hand"},
            {tag: "ability", kind: "activateAbility", promptKind: "chooseAction", cardId: "card:mana"},
            {tag: "mana", kind: "activateAbility", promptKind: "payManaCost", cardId: "card:mana"}]
    }
    function test_singleCardActionsUseCurrentOpaqueResponse(data) {
        verify(testRulesPrompt.applyPrompt(prompt(data.promptKind,
            [{responseId: "action:opaque", cardId: data.cardId, kind: data.kind, label: "Use this card"}])))
        verify(tableInteraction.objectActionable("card", data.cardId))
        verify(tableInteraction.actionOnTable(data.cardId, data.kind))
        verify(!tableInteraction.objectActionable("spell", data.cardId))
        verify(tableInteraction.activateObject("card", data.cardId, "Forest"))
        compare(responder.responses, [{promptId: 7, responseId: "action:opaque"}])
        verify(!tableInteraction.activateObject("card", data.cardId, "Forest"))
        compare(responder.responses.length, 1)
        verify(tableInteraction.actionOnTable(data.cardId, data.kind))
    }
    function test_multipleAbilitiesAndReplacedPrompt() {
        const actions = [0, 1].map(i => ({responseId: "action:" + i, cardId: "card:mana",
            kind: "activateAbility", label: "Ability " + i}))
        verify(testRulesPrompt.applyPrompt(prompt("chooseAction", actions)))
        verify(tableInteraction.activateObject("card", "card:mana", "Forest"))
        compare(picker.actions.length, 2)
        compare(responder.responses.length, 0)
        verify(testRulesPrompt.applyPrompt(prompt("chooseAction", [actions[1]])))
        verify(!tableInteraction.submitCardAction("card:mana", "action:0"))
        verify(tableInteraction.submitCardAction("card:mana", "action:1"))
        compare(responder.responses[0].responseId, "action:1")
    }
    function test_singleTargetSubmitsImmediatelyAndOnce_data() {
        return [{tag: "card", player: false}, {tag: "player", player: true}]
    }
    function test_singleTargetSubmitsImmediatelyAndOnce(data) {
        applyTargets(1)
        verify(data.player ? tableInteraction.activateSeat(2)
                           : tableInteraction.activateObject("card", "card:mana", "Forest"))
        compare(responder.responses[0].targets, [data.player ? "target:1" : "target:0"])
        verify(!tableInteraction.activateSeat(2))
        compare(responder.responses.length, 1)
    }
    function test_multipleTargetsShareBoardAndPanelState() {
        applyTargets(2, [target("target:2", "card", "card:grave")])
        verify(tableInteraction.activateObject("card", "card:mana", "Forest"))
        compare(targetPrompt.selectedCount, 1)
        verify(tableInteraction.objectSelected("card", "card:mana"))
        tryCompare(findChild(targetPrompt, "rulesTargetCandidates"), "count", 1)
        tryVerify(() => findChild(targetPrompt, "rulesTarget-target:2") !== null)
        const fallback = findChild(targetPrompt, "rulesTarget-target:2")
        verify(fallback !== null)
        mouseClick(fallback)
        compare(tableInteraction.selectedCount, 2)
        verify(!tableInteraction.toggleTarget("target:1"))
        mouseClick(findChild(targetPrompt, "rulesConfirmTargets"))
        compare(responder.responses[0].targets, ["target:0", "target:2"])
    }
    function test_onlyReachableUnambiguousTargetsLeaveThePanel() {
        applyTargets(2, [target("target:2", "card", "card:grave"), target("target:3", "player", ""),
            target("target:4", "spell", "stack:spell")])
        compare(tableInteraction.fallbackTargets.map(row => row.responseId), ["target:2", "target:3"])
        controller.stackTargetsVisible = false
        compare(tableInteraction.fallbackTargets.map(row => row.responseId), ["target:2", "target:3", "target:4"])
        applyTargets(2, [target("target:2", "card", "card:mana")])
        verify(!tableInteraction.objectActionable("card", "card:mana"))
        compare(tableInteraction.fallbackTargets.map(row => row.responseId), ["target:0", "target:2"])
        verify(!tableInteraction.activateObject("spell", "card:mana", "Forest"))
    }
    function test_resetAndPermissionGuards_data() {
        return [{tag: "republished"}, {tag: "disconnect"}, {tag: "spectator"},
            {tag: "seat-change"}, {tag: "sideboard"}, {tag: "game-change"}]
    }
    function test_resetAndPermissionGuards(data) {
        applyTargets(2)
        tableInteraction.activateSeat(2)
        compare(tableInteraction.selectedCount, 1)
        switch (data.tag) {
        case "republished": applyTargets(2); break
        case "disconnect": controller.roomConnected = false; break
        case "spectator": controller.localSeat = -1; break
        case "seat-change": controller.localSeat = 2; break
        case "sideboard": controller.sideboarding = true; break
        case "game-change": verify(testRulesPrompt.applySnapshot(snapshot("next-game"))); break
        }
        compare(tableInteraction.selectedCount, 0)
        verify(!tableInteraction.submitTargets("$submit"))
        compare(responder.responses.length, 0)
    }
    function test_cancelAndUnknownResponses() {
        applyTargets(2)
        verify(!tableInteraction.toggleTarget("target:unknown"))
        verify(!tableInteraction.submitTargets("$unknown"))
        verify(tableInteraction.submitTargets("$cancel"))
        compare(responder.responses[0].targets, [])
        compare(responder.responses[0].responseId, "$cancel")
    }
}
