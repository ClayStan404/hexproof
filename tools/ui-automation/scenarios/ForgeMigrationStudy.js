// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
.pragma library

function tick(d, ws, probe) {
    if (!d.migrationAudit || d.migrationDone || d.spectator || !d.session.active || !d.table || !d.table.presentation) return false
    let shared = probe.readShared("forge-migration") || {}
    if (!shared.started && d.seat === 1 && d.session.turn >= Number(probe.environment("HEXPROOF_AUDIT_MIGRATION_TURN") || "3") && d.session.promptPending
        && d.session.promptKind === "chooseAction" && !ws.rulesResponsePending) {
        probe.share("forge-migration", {started:true})
        shared = {started:true}
    }
    if (!shared.started) return false
    d.progress = Date.now()
    const state = ws.roomSession.hostStatus || {}
    if (state.migrationError) throw new Error("Native GUI migration verification failed")
    if (d.migrationStep === 0) {
        if (ws.rulesResponsePending) return true
        if (d.click("forgeHostingOptions")) d.migrationStep = 1
        return true
    }
    if (d.migrationStep === 1) {
        if (d.seat === 2) {
            if (!d.checkedBackup) { ws.forgeHost.check(); d.checkedBackup = true; return true }
            if (ws.forgeHost.busy) return true
            d.require(ws.forgeHost.ready, "Backup runtime is not prepared")
            if (d.click("forgeOfferBackup")) d.migrationStep = 2
        } else if (state.backupConnected === true && d.click("forgeApproveBackup")) {
            d.capture("migration-approved"); d.migrationStep = 2
        }
        return true
    }
    if (d.migrationStep === 2) {
        if (d.seat === 1 && state.backupApproved && state.backupConnected && state.migrationAvailable
            ) {
            if (probe.environment("HEXPROOF_AUDIT_MIGRATION") === "loss") {
                probe.fixture("stop-owned-host-helper", {reason:"migration-loss-test"})
                ws.forgeHost.cancel(); d.migrationStep = 3
            } else if (d.click("forgeMigrateHost")) d.migrationStep = 3
        }
        if (state.migrating) {
            d.capture("migration-verifying"); d.migrationStep = 3
        }
        return true
    }
    if (state.hostSeat === 1 && !state.migrating) {
        d.capture("migration-completed")
        if (d.click("forgeHostingClose")) {
            d.migrationDone = true
            if (d.seat === 1) probe.share("forge-migration", {started:true, done:true})
        }
    }
    return true
}
