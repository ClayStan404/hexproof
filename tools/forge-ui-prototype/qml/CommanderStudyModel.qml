// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick
import "FixtureData.js" as Fixtures

QtObject {
    id: root
    property string state: "ready"
    property string location: "command"
    property int castCount: 1
    property var reserved: []
    property var paid: []
    readonly property var commander: Fixtures.commander()
    readonly property var sources: ["duel-land-1", "duel-land-2", "duel-land-3"]
    // Published fixture values. Production receives costs and choices from Forge.
    readonly property string nextCost: castCount === 1 ? "2 W" : "4 W"
    readonly property string additionalCost: castCount === 1 ? "+2" : "+4"
    readonly property bool canPay: state === "payment" && reserved.length === 3
    readonly property var stack: state === "stack" ? [{id:"commander-spell", key:"isamaru",
        name:commander.name, kind:"Commander · creature", owner:"You", targetId:"",
        targetName:"", description:"Paid W + 2 additional mana."}] : []

    function reset(example) {
        state = example === "return" ? "return" : "ready"
        location = example === "return" ? "graveyard" : "command"
        castCount = example === "return" ? 2 : 1
        reserved = []
        paid = []
    }
    function cast() {
        if (state !== "ready" || location !== "command" || castCount !== 1) return
        reserved = []
        state = "payment"
    }
    function reserve(id) {
        if (state !== "payment" || sources.indexOf(id) < 0 || paid.indexOf(id) >= 0) return
        reserved = reserved.indexOf(id) >= 0 ? reserved.filter(value => value !== id) : reserved.concat([id])
    }
    function cancel() {
        if (state !== "payment") return
        reserved = []
        state = "ready"
    }
    function pay() {
        if (!canPay) return
        paid = reserved.slice()
        reserved = []
        castCount = 2
        location = "stack"
        state = "stack"
    }
    function autoPay() {
        if (state !== "payment") return
        reserved = sources.slice()
        pay()
    }
    function resolve() {
        if (state !== "stack") return
        location = "battlefield"
        state = "battlefield"
    }
    function destination(zone) {
        if (state !== "return" || ["command", "graveyard"].indexOf(zone) < 0) return
        location = zone
        state = "finished"
    }
}
