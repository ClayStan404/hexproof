// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick

QtObject {
    id: root
    property string mode: "attack"
    property bool committed: false
    property var attackers: []
    property string selectedBlocker: ""
    property var blocks: []
    property var damage: ({ballista: 2, walker: 4})
    readonly property var attackCandidates: ["own-ravager", "ragavan", "guide", "ajani"]
    readonly property var incomingAttackers: ["ravager", "ballista"]
    readonly property int damageTotal: 6
    readonly property int assignedDamage: damage.ballista + damage.walker
    readonly property bool canConfirm: !committed && (mode !== "damage" || assignedDamage === damageTotal)
    readonly property var links: mode === "attack"
        ? attackers.map(id => ({from: id, to: "opponent", label: "Attack"}))
        : mode === "block" ? blocks.map(pair => ({from: pair.blocker, to: pair.attacker, label: "Block"}))
        : [{from:"own-ravager", to:"ballista", label:damage.ballista + " damage"},
           {from:"own-ravager", to:"walker", label:damage.walker + " damage"}]

    function reset(nextMode) {
        mode = nextMode || "attack"
        committed = false
        attackers = []
        selectedBlocker = ""
        blocks = []
        damage = {ballista: 2, walker: 4}
    }
    function selectOwn(id) {
        if (committed || attackCandidates.indexOf(id) < 0) return
        if (mode === "attack") {
            attackers = attackers.indexOf(id) >= 0 ? attackers.filter(value => value !== id) : attackers.concat([id])
        } else if (mode === "block") {
            selectedBlocker = selectedBlocker === id ? "" : id
        }
    }
    function selectAttacker(id) {
        if (committed || mode !== "block" || !selectedBlocker || incomingAttackers.indexOf(id) < 0) return
        const exists = blocks.some(pair => pair.blocker === selectedBlocker && pair.attacker === id)
        const next = blocks.filter(pair => pair.blocker !== selectedBlocker)
        blocks = exists ? next : next.concat([{blocker: selectedBlocker, attacker: id}])
        selectedBlocker = ""
    }
    function adjustDamage(id, delta) {
        if (committed || mode !== "damage" || ["ballista", "walker"].indexOf(id) < 0) return
        const next = Object.assign({}, damage)
        next[id] = Math.max(0, Math.min(damageTotal, next[id] + delta))
        damage = next
    }
    function confirm() {
        if (!canConfirm) return
        selectedBlocker = ""
        committed = true
    }
    function labels(own) {
        const result = {}
        if (mode === "attack" && own) attackers.forEach(id => result[id] = "ATTACKING")
        if (mode === "block") {
            if (own) blocks.forEach(pair => result[pair.blocker] = "BLOCKING")
            else incomingAttackers.forEach(id => {
                const count = blocks.filter(pair => pair.attacker === id).length
                result[id] = count ? count + (count === 1 ? " BLOCKER" : " BLOCKERS") : "ATTACKING"
            })
        }
        if (mode === "damage") {
            if (own) result["own-ravager"] = "6 DAMAGE"
            else { result.ballista = damage.ballista + " DAMAGE"; result.walker = damage.walker + " DAMAGE" }
        }
        return result
    }
}
