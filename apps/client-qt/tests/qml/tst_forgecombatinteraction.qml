// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    name: "ForgeCombatInteraction"
    property int serial: 600

    QtObject {
        id: combatContext
        property bool contextActive: true
        property bool canRespond: true
        property int promptRevision: 0
    }
    QtObject {
        id: controller
        property var rulesSession: testRulesPrompt.session
        property var interaction: combatContext
        property int localSeat: 0
    }
    ForgeCombatInteraction {
        id: combat
        tableController: controller
    }
    Connections {
        target: testRulesPrompt.session
        function onPromptChanged() { combatContext.promptRevision++ }
    }

    function cleanup() {
        testRulesPrompt.clear()
    }

    function prepare(validTargets, maximum) {
        verify(testRulesPrompt.applyPrompt({
            roomId: "BLOCK1", gameId: "attacker-first", pending: true, supported: true,
            promptId: ++serial, kind: "chooseBlockers", options: [], choices: [], cards: [],
            targets: [], contextCards: [], contextTargets: [], damageTargets: [], scryDestinations: [], totalDamage: 0,
            combatSources: [
                {responseId: "block-reach", objectId: "reach-blocker", label: "Reach blocker",
                    validTargetIds: ["attack-a", "attack-b", "attack-c"], maxAssignments: 1},
                {responseId: "block-other", objectId: "other-blocker", label: "Other blocker",
                    validTargetIds: validTargets, maxAssignments: maximum}],
            combatTargets: ["a", "b", "c"].map(id => ({responseId: "attack-" + id,
                kind: "attacker", objectId: "attacker-" + id, label: "Attacker " + id,
                maxAssignments: 2}))
        }))
        verify(combat.canAct)
        compare(combat.assignments, ({}))
    }

    function test_ineligibleBlockerPreservesArmedAttackerAndDraft_data() {
        return [
            {tag: "single-target-unassigned", targets: ["attack-b"], maximum: 1, assigned: []},
            {tag: "single-target-already-assigned", targets: ["attack-b"], maximum: 1, assigned: ["attack-b"]},
            {tag: "other-targets-unassigned", targets: ["attack-b", "attack-c"], maximum: 1, assigned: []},
            {tag: "other-targets-already-assigned", targets: ["attack-b", "attack-c"], maximum: 1, assigned: ["attack-b"]},
            {tag: "multiple-blocker-at-capacity", targets: ["attack-a", "attack-b", "attack-c"], maximum: 2,
                assigned: ["attack-b", "attack-c"]}
        ]
    }

    function test_ineligibleBlockerPreservesArmedAttackerAndDraft(data) {
        prepare(data.targets, data.maximum)
        for (const target of data.assigned) {
            if (data.maximum > 1) combat.toggleAssignment("block-other", target, data.maximum)
            else combat.setAssignment("block-other", target)
        }
        const original = JSON.parse(JSON.stringify(combat.assignments))
        verify(combat.activate("attacker-a"))
        compare(combat.pendingAttacker, "attacker-a")

        verify(combat.activate("other-blocker"))
        compare(combat.assignments, original, "An ineligible click must not change a different attacker's block")
        compare(combat.pendingAttacker, "attacker-a", "The chosen attacker remains armed for an eligible blocker")
        compare(combat.selectedSource, "")

        verify(combat.activate("reach-blocker"))
        compare(combat.assignments, Object.assign({}, original, {"block-reach": "attack-a"}))
        compare(combat.pendingAttacker, "")
        compare(combat.selectedSource, "")
    }

    function test_singleTargetShortcutStillTogglesWithoutArmedAttacker() {
        prepare(["attack-b"], 1)
        verify(combat.activate("other-blocker"))
        compare(combat.selectedTargets("block-other"), ["attack-b"])
        verify(combat.activate("other-blocker"))
        compare(combat.assignments, ({}))
    }

    function test_armedAssignedPairCanBeRemovedAtCapacity() {
        prepare(["attack-a", "attack-b"], 2)
        combat.toggleAssignment("block-other", "attack-a", 2)
        combat.toggleAssignment("block-other", "attack-b", 2)
        verify(combat.activate("attacker-a"))
        verify(combat.activate("other-blocker"))
        compare(combat.selectedTargets("block-other"), ["attack-b"])
        compare(combat.pendingAttacker, "")
        compare(combat.selectedSource, "")
    }
}
