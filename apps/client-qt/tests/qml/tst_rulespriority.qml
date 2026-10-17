// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "RulesPriority"
    when: windowShown

    QtObject {
        id: controller
        property var rulesSession: testRulesPrompt.session
        property bool roomConnected: true
        property bool sideboarding: false
        property bool rulesResponsePending: false
        property bool priorityInputBlocked: false
        property int localSeat: 0
        property var cardActionPicker: picker
        property var wsModel: responder
    }
    QtObject { id: picker; property bool opened: false }
    QtObject {
        id: responder
        property var responses: []
        property string lastError: ""
        function respondRulesPrompt(promptId, responseId) {
            responses = responses.concat([{promptId: promptId, responseId: responseId}])
            controller.rulesResponsePending = true
        }
    }
    RulesPriorityController { id: priority; tableController: controller; settings: preferences }

    function snapshot(turn, step, activeSeat, stackIds, gameId) {
        return {roomId: "FLOW", gameId: gameId || "flow-1", turn: turn || 1,
            step: step || "main1", activeSeat: activeSeat || 0, prioritySeat: 0,
            players: [{seat: 0, name: "Alice", life: 20}, {seat: 1, name: "Bob", life: 20}],
            zones: [], stack: (stackIds || []).map(id => ({id: id, name: id, controllerSeat: 1}))}
    }
    function prompt(id, eligible, kind) {
        const data = {roomId: "FLOW", gameId: "flow-1", promptId: id, pending: true,
            kind: kind || "chooseAction", supported: true, title: "Choose", detail: "Choose",
            options: [{responseId: "$pass", kind: "pass", label: "Pass"}],
            choices: [], cards: [], targets: [], scryDestinations: [], contextCards: [], contextTargets: [],
            combatSources: [], combatTargets: [], damageTargets: [], totalDamage: 0}
        if (eligible !== undefined)
            data.autoPassEligible = eligible
        return data
    }
    function applyPrompt(id, eligible, kind) {
        controller.rulesResponsePending = false
        verify(testRulesPrompt.applyPrompt(prompt(id, eligible, kind)))
    }
    function expectNoResponse() {
        wait(140)
        compare(responder.responses.length, 0)
    }
    function init() {
        testRulesPrompt.clear()
        controller.roomConnected = true
        controller.sideboarding = false
        controller.rulesResponsePending = false
        controller.priorityInputBlocked = false
        controller.localSeat = 0
        picker.opened = false
        responder.responses = []
        responder.lastError = ""
        preferences.forgePhaseStops = ({})
        preferences.forgeFullControl = false
        priority.passMenuOpen = false
        priority.resetTransient()
        verify(testRulesPrompt.applySnapshot(snapshot()))
    }
    function cleanup() { testRulesPrompt.clear() }

    function test_preferencesSurviveTableRecreationAndSeatChanges() {
        priority.setFullControl(true)
        priority.toggleStop("end", false)
        controller.localSeat = 1
        verify(priority.fullControl)
        verify(priority.hasStop("end", false))
        const component = Qt.createComponent("../../qml/components/RulesPriorityController.qml")
        compare(component.status, Component.Ready)
        const fresh = component.createObject(testCase, {tableController: controller, settings: preferences})
        verify(fresh.fullControl)
        verify(fresh.hasStop("end", false))
        preferences.toggleForgePhaseStop("draw", true)
        verify(priority.hasStop("draw", true))
        verify(fresh.hasStop("draw", true))
        fresh.destroy()
    }
    function test_explicitYieldPreservesFullControlPreference() {
        priority.setFullControl(true)
        applyPrompt(1, true)
        expectNoResponse()
        verify(priority.beginYield("turn"))
        tryCompare(responder, "responses", [{promptId: 1, responseId: "$pass"}])
        verify(preferences.forgeFullControl)
        verify(testRulesPrompt.applySnapshot(snapshot(2)))
        applyPrompt(2, true)
        compare(priority.yieldMode, "")
        wait(140)
        compare(responder.responses.length, 1)
    }

    function test_reselectingFullControlCancelsTemporaryYield() {
        priority.setFullControl(true)
        applyPrompt(1, true)
        verify(priority.beginYield("turn"))
        priority.setFullControl(true)
        compare(priority.yieldMode, "")
        expectNoResponse()
    }

    function test_defaultPassingRequiresExplicitEngineEvidence_data() {
        return [{tag: "no available action", eligible: true, passes: true},
            {tag: "action available", eligible: false, passes: false},
            {tag: "legacy unknown", passes: false}]
    }
    function test_defaultPassingRequiresExplicitEngineEvidence(data) {
        applyPrompt(1, data.eligible)
        if (data.passes) {
            tryCompare(responder, "responses", [{promptId: 1, responseId: "$pass"}])
            verify(controller.rulesResponsePending)
        } else {
            expectNoResponse()
        }
    }
    function test_smartEmptyStackDefaults_data() {
        return [{tag: "own upkeep", step: "upkeep", seat: 0, passes: true},
            {tag: "opponent draw", step: "draw", seat: 1, passes: true},
            {tag: "opponent main", step: "main1", seat: 1, passes: true},
            {tag: "own end", step: "end", seat: 0, passes: true},
            {tag: "end combat", step: "end_combat", seat: 0, passes: true},
            {tag: "own main", step: "main1", seat: 0, passes: false},
            {tag: "own second main", step: "main2", seat: 0, passes: false},
            {tag: "opponent end", step: "end", seat: 1, passes: false},
            {tag: "combat", step: "begin_combat", seat: 1, passes: false},
            {tag: "after attackers", step: "declare_attackers", seat: 0, passes: false},
            {tag: "after blockers", step: "declare_blockers", seat: 1, passes: false},
            {tag: "damage window", step: "combat_damage", seat: 0, passes: false},
            {tag: "unknown step", step: "unknown", seat: 1, passes: false}]
    }
    function test_smartEmptyStackDefaults(data) {
        verify(testRulesPrompt.applySnapshot(snapshot(1, data.step, data.seat)))
        applyPrompt(1, false)
        if (data.passes)
            tryCompare(responder, "responses", [{promptId: 1, responseId: "$pass"}])
        else
            expectNoResponse()
    }
    function test_smartPriorityDoesNotPassOpponentOrMixedStack_data() {
        return [{tag: "opponent spell", owners: [1], passes: false},
            {tag: "own spell", owners: [0], passes: true},
            {tag: "mixed stack", owners: [0, 1], passes: false},
            {tag: "own triggers", owners: [0, 0], passes: true}]
    }
    function test_smartPriorityDoesNotPassOpponentOrMixedStack(data) {
        const state = snapshot(1, "upkeep", 0)
        state.stack = data.owners.map((seat, index) => ({id: "spell:" + index,
            identity: {name: "Spell"}, controllerSeat: seat, ownerSeat: seat}))
        verify(testRulesPrompt.applySnapshot(state))
        applyPrompt(1, false)
        if (data.passes)
            tryCompare(responder, "responses", [{promptId: 1, responseId: "$pass"}])
        else
            expectNoResponse()
    }
    function test_fullControlAndStopsOverrideSmartDefaults() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, "upkeep", 0)))
        priority.setFullControl(true)
        applyPrompt(1, false)
        expectNoResponse()
        priority.toggleStop("upkeep", true)
        priority.setFullControl(false)
        expectNoResponse()
        const state = snapshot(1, "upkeep", 0)
        state.stack = [{id: "own-spell", identity: {name: "Spell"}, controllerSeat: 0, ownerSeat: 0}]
        verify(testRulesPrompt.applySnapshot(state))
        applyPrompt(2, false)
        expectNoResponse()
    }
    function test_collidingCardIdentityDoesNotImplyOwnStack() {
        const state = snapshot(1, "upkeep", 0)
        state.stack = [{id: "shared-id", identity: {name: "Opponent spell"}, controllerSeat: 1, ownerSeat: 1}]
        state.zones = [{zone: "battlefield", ownerSeat: 0, count: 1,
            cards: [{id: "shared-id", visible: true, identity: {name: "Own permanent"},
                controllerSeat: 0, ownerSeat: 0}]}]
        verify(testRulesPrompt.applySnapshot(state))
        applyPrompt(1, false)
        verify(!priority.ownStack)
        expectNoResponse()
    }
    function test_decisionsAreNeverAutomaticallyAnswered_data() {
        return ["payManaCost", "chooseBoardTargets", "chooseAttackers", "chooseBlockers",
            "chooseBoolean", "mulligan", "chooseCards"].map(kind => ({tag: kind, kind: kind}))
    }
    function test_decisionsAreNeverAutomaticallyAnswered(data) {
        applyPrompt(1, true, data.kind)
        verify(!priority.isPriorityPrompt)
        expectNoResponse()
    }
    function test_fullControlSurvivesPaymentAndTargets() {
        priority.setFullControl(true)
        applyPrompt(1, true)
        expectNoResponse()
        applyPrompt(2, true, "payManaCost")
        applyPrompt(3, true, "chooseBoardTargets")
        applyPrompt(4, true)
        verify(priority.fullControl)
        expectNoResponse()
        priority.setFullControl(false)
        tryCompare(responder, "responses", [{promptId: 4, responseId: "$pass"}])
    }
    function test_stopPausesOncePerPhaseAndAgainOnNextTurn() {
        priority.toggleStop("main1", true)
        applyPrompt(1, true)
        verify(priority.stopped)
        expectNoResponse()
        verify(priority.passOnce())
        compare(responder.responses.length, 1)
        applyPrompt(2, true)
        tryCompare(responder, "responses", [{promptId: 1, responseId: "$pass"},
            {promptId: 2, responseId: "$pass"}])
        verify(testRulesPrompt.applySnapshot(snapshot(2)))
        responder.responses = []
        applyPrompt(3, true)
        verify(priority.stopped)
        expectNoResponse()
    }
    function test_otherPlayersStopDoesNotStopOwnPhase() {
        priority.toggleStop("main1", false)
        applyPrompt(1, true)
        tryCompare(responder, "responses", [{promptId: 1, responseId: "$pass"}])
        verify(testRulesPrompt.applySnapshot(snapshot(2, "main1", 1)))
        responder.responses = []
        applyPrompt(2, true)
        expectNoResponse()
    }
    function test_staleOrRejectedPromptDoesNotLoop() {
        applyPrompt(1, true)
        tryCompare(responder, "responses", [{promptId: 1, responseId: "$pass"}])
        applyPrompt(1, true)
        wait(140)
        compare(responder.responses.length, 1)
        verify(priority.passOnce())
        compare(responder.responses.length, 2)
    }
    function test_replacementCancelsScheduledPass() {
        applyPrompt(1, true)
        verify(priority.automaticallyPassing)
        applyPrompt(2, false)
        expectNoResponse()
    }
    function test_contextAndInputGuards_data() {
        return ["disconnected", "spectator", "sideboarding", "pending", "modal", "picker", "menu"]
            .map(tag => ({tag: tag}))
    }
    function test_contextAndInputGuards(data) {
        applyPrompt(1, true)
        switch (data.tag) {
        case "disconnected": controller.roomConnected = false; break
        case "spectator": controller.localSeat = -1; break
        case "sideboarding": controller.sideboarding = true; break
        case "pending": controller.rulesResponsePending = true; break
        case "modal": controller.priorityInputBlocked = true; break
        case "picker": picker.opened = true; break
        case "menu": priority.passMenuOpen = true; break
        }
        expectNoResponse()
    }
    function test_continuousPassingStopsOnNewStackObject_data() {
        return [{tag: "until response", mode: "response"}, {tag: "current stack", mode: "stack"}]
    }
    function test_continuousPassingStopsOnNewStackObject(data) {
        verify(testRulesPrompt.applySnapshot(snapshot(1, "main1", 0, ["spell:a"])))
        applyPrompt(1, false)
        verify(priority.beginYield(data.mode))
        tryCompare(responder, "responses", [{promptId: 1, responseId: "$pass"}])
        verify(testRulesPrompt.applySnapshot(snapshot(1, "main1", 0, ["spell:b"])))
        compare(priority.yieldMode, "")
        responder.responses = []
        applyPrompt(2, false)
        expectNoResponse()
    }
    function test_stackPassingEndsWhenOriginalStackIsEmpty() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, "main1", 0, ["spell:a", "spell:b"])))
        applyPrompt(1, false)
        verify(priority.beginYield("stack"))
        tryCompare(responder, "responses", [{promptId: 1, responseId: "$pass"}])
        verify(testRulesPrompt.applySnapshot(snapshot(1, "main1", 0, ["spell:a"])))
        applyPrompt(2, false)
        tryCompare(responder, "responses", [{promptId: 1, responseId: "$pass"}, {promptId: 2, responseId: "$pass"}])
        verify(testRulesPrompt.applySnapshot(snapshot()))
        compare(priority.yieldMode, "")
    }
    function test_cancelWhileWaitingHoldsNextPriorityEvenWithoutAvailableActions() {
        const waiting = prompt(1, false)
        waiting.pending = false
        verify(testRulesPrompt.applyPrompt(waiting))
        verify(priority.beginYield("turn"))
        priority.cancelYield()
        applyPrompt(2, true)
        expectNoResponse()
        verify(priority.passOnce())
        compare(responder.responses, [{promptId: 2, responseId: "$pass"}])
    }
    function test_newStackSnapshotBeforePromptPreservesResponseWindow() {
        applyPrompt(1, false)
        verify(priority.beginYield("response"))
        tryCompare(responder, "responses", [{promptId: 1, responseId: "$pass"}])
        verify(testRulesPrompt.applySnapshot(snapshot(1, "main1", 0, ["new-spell"])))
        compare(priority.yieldMode, "")
        responder.responses = []
        applyPrompt(2, true)
        expectNoResponse()
    }
    function test_turnPassingExpiresAndCanBeCancelled() {
        applyPrompt(1, false)
        verify(priority.beginYield("turn"))
        priority.cancelYield()
        compare(priority.yieldMode, "")
        expectNoResponse()
        verify(priority.beginYield("turn"))
        tryCompare(responder, "responses", [{promptId: 1, responseId: "$pass"}])
        verify(testRulesPrompt.applySnapshot(snapshot(2)))
        compare(priority.yieldMode, "")
        responder.responses = []
        applyPrompt(2, false)
        expectNoResponse()
    }
    function test_phaseStopAndRequiredChoiceCancelContinuousPassing() {
        priority.toggleStop("end", false)
        applyPrompt(1, false)
        verify(priority.beginYield("turn"))
        applyPrompt(2, true, "chooseBoolean")
        compare(priority.yieldMode, "")
        expectNoResponse()
        applyPrompt(3, false)
        verify(priority.beginYield("response"))
        verify(testRulesPrompt.applySnapshot(snapshot(1, "end", 1)))
        compare(priority.yieldMode, "")
        expectNoResponse()
    }
}
