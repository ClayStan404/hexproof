// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: driver
    property int seat: Number(auditProbe.environment("HEXPROOF_AUDIT_SEAT"))
    property int stage: -2
    property bool busy: false
    property double started: Date.now()
    function require(ok, message) { if (!ok) throw new Error(message + "; " + auditProbe.lastError) }
    function item(name) { return auditProbe.find(auditWindow, name) }
    function click(name) {
        const target = item(name)
        if (!target) return false
        require(auditProbe.click(target), "Cannot click " + name)
        return true
    }
    function capture(name) { require(auditProbe.capture(auditWindow,name), "Capture failed") }
    function scrollTo(name) {
        if (item(name)) return true
        const body = item("createRoomBody")
        if (body) require(auditProbe.wheel(body,-220), "Cannot scroll setup form")
        return false
    }
    function finish(error) {
        timer.stop()
        if (error) capture("failure")
        auditProbe.record("result", {status:error ? "failed" : "passed", error:error || "", stage:stage,
            scenario:"player-hosting-setup", seat:seat, requiredScreenshots:seat === 1
                ? ["hosting-preparation.png","hosting-options.png","hosting-cache-cleared.png",
                   "create-player-host.png","waiting-host.png"]
                : ["join-host-consent.png","waiting-joined.png"]})
        auditProbe.finish(error ? 1 : 0)
    }
    function tick() {
        require(Date.now()-started < 90000,"Setup timed out")
        require(!ws.lastError,"Unexpected server error: " + ws.lastError)
        if (stage === -2) {
            for (const name of ["dismissSponsorsButton","laterCardArtRepairButton"])
                if (item(name)) { click(name); return }
            if (click("mainMenuConnectButton")) stage = -1
            return
        }
        if (stage === -1) { if (click("connectSubmitButton")) stage = 0; return }
        if (!ws.connected || auditWindow.stack.busy) return
        if (seat === 1) {
            if (stage === 0) {
                require(ws.playerHostingAvailable && !ws.forgeRulesAvailable,"Expected relay-only hub")
                auditProbe.fixture("open-create-room-route")
                auditWindow.pushScreen("screens/CreateRoom.qml", {roomName:"Trusted hosting UI"})
                stage = 1; return
            }
            if (stage === 1) {
                if (!item("roomNameField")) return
                stage = 2; return
            }
            if (stage === 2 || stage === 3) {
                const control = item(stage === 2 ? "forgeRulesMode" : "forgeHostingMode")
                if (!control) return
                require(auditProbe.click(control,control.width*0.75,control.height/2),"Cannot choose hosting mode")
                stage++; return
            }
            if (stage === 4) {
                if (ws.forgeHost.busy) return
                require(ws.forgeHost.ready,"Pinned fixture runtime not installed")
                if (scrollTo("prepareForgeHostButton") && click("prepareForgeHostButton")) stage = 5
                return
            }
            if (stage === 5) {
                require(ws.forgeHost.busy,"Preparation completed before cancellation probe")
                capture("hosting-preparation")
                if (click("prepareForgeHostButton")) stage = 6
                return
            }
            if (stage === 6) {
                if (ws.forgeHost.busy) return
                require(!ws.forgeHost.ready,"Cancelled preparation incorrectly ready")
                if (click("prepareForgeHostButton")) stage = 7
                return
            }
            if (stage === 7) {
                if (ws.forgeHost.busy) return
                require(ws.forgeHost.ready,"Runtime retry failed")
                capture("create-player-host")
                if (scrollTo("forgeHostingOptions") && click("forgeHostingOptions")) stage = 70
                return
            }
            if (stage === 70) {
                if (!item("forgeClearCache")) return
                capture("hosting-options")
                if (click("forgeClearCache")) stage = 71
                return
            }
            if (stage === 71) {
                if (ws.forgeHost.busy) return
                require(ws.forgeHost.ready,"Cache cleanup lost the current runtime")
                require(ws.forgeHost.status.indexOf("Freed") >= 0,"Cache cleanup failed")
                capture("hosting-cache-cleared")
                if (click("forgeHostingClose")) stage = 72
                return
            }
            if (stage === 72) {
                if (scrollTo("createRoomSubmitButton") && click("createRoomSubmitButton")) stage = 8
                return
            }
            if (stage === 8) {
                if (!ws.inRoom || !ws.roomSession.hostConnected) return
                require(ws.roomSession.hostingMode === "player","Creation lost hosting mode")
                auditProbe.share("host-ui-room",{roomId:ws.roomSession.roomId})
                stage = 9; return
            }
            if (stage === 9) {
                if (!(auditProbe.readShared("host-ui-joined-2") || {}).done ||
                    !(auditProbe.readShared("host-ui-joined-3") || {}).done) return
                capture("waiting-host")
                auditProbe.share("host-ui-finished",{done:true})
                finish("")
            }
            return
        }
        if (stage === 0) {
            const shared = auditProbe.readShared("host-ui-room") || {}
            if (!shared.roomId) return
            auditProbe.fixture("open-trusted-host-join-route",{roomId:shared.roomId})
            auditWindow.pushScreen("screens/JoinRoom.qml",{roomCode:shared.roomId,asSpectator:seat === 3,hostingMode:"player"})
            stage = 1; return
        }
        if (stage === 1) {
            const submit = auditProbe.observe(auditWindow).items.find(control => control.objectName === "joinRoomSubmitButton" && control.visible)
            if (!submit) return
            require(!submit.enabled,"Join enabled without consent")
            capture("join-host-consent")
            stage = 2; return
        }
        if (stage === 2) {
            require(!ws.inRoom,"Joined without host consent")
            if (click("trustPlayerHost")) stage = 3
            return
        }
        if (stage === 3) { if (click("joinRoomSubmitButton")) stage = 4; return }
        if (stage === 4) {
            if (!ws.inRoom || !ws.roomSession.hostConnected) return
            require(!ws.forgeHost.busy && !ws.forgeHost.hosting,"Joiner started a local engine")
            capture("waiting-joined")
            auditProbe.share("host-ui-joined-"+seat,{done:true})
            stage = 5; return
        }
        if (stage === 5 && (auditProbe.readShared("host-ui-finished") || {}).done) finish("")
    }
    Timer {
        id: timer
        interval: 100; repeat: true; running: true
        onTriggered: {
            if (driver.busy) return
            driver.busy = true
            try { driver.tick() } catch (error) { driver.finish(String(error)) }
            driver.busy = false
        }
    }
}
