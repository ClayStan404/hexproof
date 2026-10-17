// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick
import "FixtureData.js" as Fixtures

QtObject {
    id: root
    property string scene: "board"
    property string stage: "board"
    property var ownCreatures: Fixtures.ownCreatures()
    property var opponentCreatures: Fixtures.opponentCreatures()
    property var ownLands: Fixtures.ownLands()
    property var opponentLands: Fixtures.opponentLands()
    property var hand: Fixtures.hand()
    property var stack: []
    property string selectedTargetId: ""
    property string selectedTargetName: ""
    property string selectedManaId: ""
    property string paidManaId: ""
    property bool fullControl: true
    property var phaseStops: [false, false, true, false, false]
    property string notice: ""
    property int ownLife: 18
    property int opponentLife: 16
    property var history: ["Turn 4 — your first main phase.", "Guide of Souls entered the battlefield."]
    property CombatStudyModel combat: CombatStudyModel {}
    property CommanderStudyModel duel: CommanderStudyModel {}
    readonly property bool combatActive: scene === "combat"
    readonly property bool duelActive: scene === "commander"
    readonly property bool crowded: scene === "crowded"
    readonly property var visibleOwnCreatures: duelActive && duel.location === "battlefield"
        ? ownCreatures.concat([duel.commander]) : ownCreatures
    readonly property var visibleStack: duelActive ? duel.stack : stack
    readonly property bool choosing: stage === "target" || stage === "payment"
    readonly property bool canPay: stage === "payment" && selectedManaId !== ""
    readonly property var activeStack: visibleStack.length ? visibleStack[visibleStack.length - 1] : null
    readonly property var redSources: ["foundry", "mountain"]
    readonly property var targetIds: ownCreatures.concat(opponentCreatures).map(c => c.id).concat(["you", "opponent"])

    function reset(nextScene) {
        scene = nextScene
        stage = nextScene
        ownCreatures = Fixtures.ownCreatures()
        opponentCreatures = Fixtures.opponentCreatures()
        ownLands = Fixtures.ownLands()
        opponentLands = Fixtures.opponentLands()
        hand = Fixtures.hand()
        stack = nextScene === "response" ? [Fixtures.ability(), Fixtures.spell("ballista", "Walking Ballista")] : []
        selectedTargetId = ""
        selectedTargetName = ""
        selectedManaId = ""
        paidManaId = ""
        ownLife = 18
        opponentLife = 16
        notice = ""
        history = ["Turn 4 — your first main phase.", "Guide of Souls entered the battlefield."]
        combat.reset("attack")
        duel.reset("cast")
        if (nextScene === "response") {
            hand = hand.filter(c => c.id !== "bolt")
            paidManaId = "mountain"
        } else if (nextScene === "payment") {
            selectedTargetId = "ballista"
            selectedTargetName = "Walking Ballista"
        } else if (nextScene === "combat") {
            ownCreatures = Fixtures.combatCreatures()
        } else if (nextScene === "commander") {
            ownCreatures = Fixtures.duelCreatures(false)
            opponentCreatures = Fixtures.duelCreatures(true)
            ownLands = Fixtures.duelLands("duel-land-")
            opponentLands = Fixtures.duelLands("enemy-land-")
            hand = Fixtures.duelHand()
            ownLife = 20
            opponentLife = 20
        } else if (nextScene === "crowded") {
            ownCreatures = Fixtures.crowdedCreatures(false)
            opponentCreatures = Fixtures.crowdedCreatures(true)
            hand = Fixtures.crowdedHand()
            stack = Fixtures.crowdedStack()
        }
    }

    function castBolt() {
        if (choosing || combatActive || duelActive || !hand.some(c => c.id === "bolt"))
            return
        stage = "target"
        selectedTargetId = ""
        selectedTargetName = ""
        selectedManaId = ""
        notice = ""
    }

    function chooseTarget(id, name) {
        if (stage !== "target" || targetIds.indexOf(id) < 0)
            return
        selectedTargetId = id
        selectedTargetName = name
        stage = "payment"
    }

    function chooseMana(id) {
        if (stage !== "payment" || redSources.indexOf(id) < 0 || paidManaId === id)
            return
        selectedManaId = selectedManaId === id ? "" : id
    }

    function autoPay() {
        if (stage !== "payment")
            return
        const available = redSources.filter(id => id !== paidManaId)
        if (available.length)
            selectedManaId = available[0]
        pay()
    }

    function pay() {
        if (!canPay || !selectedTargetId)
            return
        paidManaId = selectedManaId
        hand = hand.filter(c => c.id !== "bolt")
        stack = stack.concat([Fixtures.spell(selectedTargetId, selectedTargetName)])
        history = history.concat(["You cast Lightning Bolt targeting " + selectedTargetName + "."])
        selectedManaId = ""
        stage = "response"
        notice = "Lightning Bolt is on the stack. You have priority."
    }

    function changeTarget() {
        if (stage !== "payment")
            return
        selectedTargetId = ""
        selectedTargetName = ""
        selectedManaId = ""
        stage = "target"
    }

    function cancel() {
        if (combatActive) { combat.reset(combat.mode); return }
        if (duelActive) { duel.cancel(); return }
        if (!choosing)
            return
        selectedTargetId = ""
        selectedTargetName = ""
        selectedManaId = ""
        stage = stack.length ? "response" : "board"
        notice = "Cast cancelled. Your hand and mana are unchanged."
    }

    function resolve() {
        if (choosing || !stack.length)
            return
        const entry = activeStack
        stack = stack.slice(0, -1)
        // These are prescribed visual fixture outcomes, not a rules implementation.
        if (entry.id === "bolt-spell") {
            ownCreatures = ownCreatures.filter(c => c.id !== entry.targetId)
            opponentCreatures = opponentCreatures.filter(c => c.id !== entry.targetId)
            if (entry.targetId === "you") ownLife -= 3
            if (entry.targetId === "opponent") opponentLife -= 3
        }
        history = history.concat([entry.name + " resolved in the preview."])
        selectedTargetId = ""
        stage = stack.length ? "response" : "board"
        notice = entry.name + " resolved."
    }

    function toggleStop(index) {
        const next = phaseStops.slice()
        next[index] = !next[index]
        phaseStops = next
    }
}
