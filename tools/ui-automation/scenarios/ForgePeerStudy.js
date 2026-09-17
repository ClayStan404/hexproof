// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
.pragma library

function tick(d, ws, probe) {
    if (!d.peerAudit || d.peerDone || d.spectator || !d.session.active || !d.table || !d.table.presentation) return false
    let shared = probe.readShared("forge-peer-study") || {}
    if (!shared.started && d.seat === 1 && d.session.turn >= 2 && d.session.promptPending
        && d.session.promptKind === "chooseAction" && !ws.rulesResponsePending) {
        probe.share("forge-peer-study", {started:true})
        shared = {started:true}
    }
    if (!shared.started) return false
    d.progress = Date.now()
    if (d.peerStep === 0) {
        if (ws.rulesResponsePending) return true
        d.require(!d.table.presentation.modalOpen, "Direct connection must be accessible on the table")
        if (d.click("forgePeerEnable")) { d.peerStep = 1; d.peerStartedAt = Date.now() }
        return true
    }
    if (d.peerStep === 1) {
        const state = ws.peerTransportState
        if (state === "connecting") d.peerConnectingObserved = true
        d.require(Date.now() - d.peerStartedAt < 25000, "Expected peer state was not reached: " + d.peerExpected + "; actual: " + state)
        if (d.peerExpected === "relay") {
            d.require(state !== "direct", "Blocked candidate fixture unexpectedly connected directly")
            if (!d.peerConnectingObserved || state !== "relay") return true
            d.capture("peer-fallback")
        } else {
            if (state !== "direct") return true
            d.capture("peer-connected")
        }
        probe.record("peer-ready", {state:state, expected:d.peerExpected,
            connectingObserved:d.peerConnectingObserved, javaRequired:d.seat === 1})
        d.peerStep = 2
        d.peerDone = true
    }
    return true
}
