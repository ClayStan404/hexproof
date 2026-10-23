// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: driver
    property var steps: []
    property var assertions: []
    property var screenshots: []
    property int index: 0
    property bool acted: false
    property bool dispatching: false
    property bool finished: false
    property double entered: 0
    property string loginCode: ""
    property string accountId: ""
    property string expectedRoom: ""
    readonly property int seat: Number(auditProbe.environment("HEXPROOF_AUDIT_SEAT"))
    function require(value, message) { if (!value) throw new Error(message) }
    function find(name) { return auditProbe.find(auditWindow, name, ({})) }
    function click(name, scrollName) {
        const scroll = scrollName ? find(scrollName) : null
        const body = scroll && scroll.contentItem ? scroll.contentItem : scroll
        if (body && body.moving) return false
        const item = find(name)
        if (item) { require(auditProbe.click(item), "Cannot click " + name); return true }
        if (scroll) require(auditProbe.wheel(scroll, -300), "Cannot scroll")
        return false
    }
    function choose(name, selected) {
        const item = find(name)
        if (!item) return false
        require(auditProbe.click(item), "Cannot open " + name)
        require(auditProbe.key(Qt.Key_Home), "Cannot select first option")
        for (let i = 0; i < selected; ++i) require(auditProbe.key(Qt.Key_Down), "Cannot select option")
        require(auditProbe.key(Qt.Key_Return), "Cannot accept option")
        return true
    }
    function type(name, value) {
        if (!click(name)) return false
        require(auditProbe.key(Qt.Key_A, Qt.ControlModifier), "Cannot select input")
        require(auditProbe.type(value), "Cannot type input")
        return true
    }
    function add(name, action, check) { steps.push({name: name, action: action, check: check || (() => true)}) }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture")
        screenshots.push(name + ".png")
    }
    function plan() {
        if (seat >= 2) {
            add("Wait for isolated account and room", () => {
                const saved = auditProbe.readShared("test-account")
                if (!saved || !saved.room || (seat === 3 && !auditProbe.readShared("cluster-restored"))) return false
                loginCode = saved.loginCode; accountId = saved.accountId; expectedRoom = saved.room
            })
        }
        add("Dismiss startup notices", () => {
            require(auditProbe.activate(), "Cannot activate owned test window")
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"])
                if (find(name)) { click(name); return false }
            return !!find("mainMenuConnectButton") && !auditWindow.stack.busy
        })
        add("Open login screen", () => click("mainMenuConnectButton"),
            () => !!find("accountConnectionMode") && !auditWindow.stack.busy)
        add("Choose the first official entry node", () => choose("serverSelector", 0))
        add("Choose account action", () => choose("accountConnectionMode", seat === 1 ? 2 : seat === 2 ? 1 : 4),
            () => find("accountConnectionMode").currentIndex === (seat === 1 ? 2 : seat === 2 ? 1 : 4))
        if (seat === 2) add("Enter private login code", () => type("accountConnectionCode", loginCode))
        add("Submit account action", () => click("connectSubmitButton", "connectBody"),
            () => (seat === 3 ? ws.connected : ws.account.authenticated) && !ws.account.busy && !auditWindow.stack.busy)
        if (seat === 1) {
            add("Inspect generated masked backup codes", () => {
                require(ws.account.supported && ws.account.loginCode && ws.account.recoveryCode, "Missing account backup")
                require(find("accountGeneratedLoginCode").echoMode === TextInput.Password, "Login code is visible")
                require(find("accountGeneratedRecoveryCode").echoMode === TextInput.Password, "Recovery code is visible")
                loginCode = ws.account.loginCode; accountId = ws.account.accountId
                capture("account-backup")
            })
            add("Acknowledge backup", () => click("accountBackupAcknowledged", "settingsBody"),
                () => !ws.account.loginCode && !ws.account.recoveryCode)
            add("Return to menu", () => click("screenBackButton"),
                () => !!find("mainMenuCreateRoomButton") && !auditWindow.stack.busy)
            add("Create room", () => click("mainMenuCreateRoomButton"),
                () => !!find("roomNameField") && !auditWindow.stack.busy)
            add("Name room", () => {
                require(ws.globalCode("TEST") === "N1:TEST", "Creation did not start at N1")
                return type("roomNameField", "Cross-node native room")
            })
            add("Submit room", () => click("createRoomSubmitButton", "createRoomBody"),
                () => ws.inRoom && !auditWindow.stack.busy)
            add("Publish disposable test credentials to second isolated profile", () => {
                require(ws.globalCode(ws.roomSession.roomId) === "N2:" + ws.roomSession.roomId, "Room was not allocated to N2")
                require(find("waitingRoomCode").text === ws.globalCode(ws.roomSession.roomId), "Invitation lacks the node prefix")
                capture("allocated-room")
                require(auditProbe.share("test-account", {accountId: accountId, loginCode: loginCode, room: ws.roomSession.roomId}), "Cannot share fixture")
                loginCode = ""
            })
            add("Old device stops reconnecting after handover", () => true,
                () => !ws.connected && !ws.connecting && ws.lastError.indexOf("account_replaced") >= 0)
        } else if (seat === 2) {
            add("Recover room without local room token", () => true,
                () => ws.inRoom && ws.roomSession.roomId === expectedRoom && !auditWindow.stack.busy)
            add("Verify original account identity and restored seat", () => {
                require(ws.account.accountId === accountId, "Identity changed")
                require(ws.account.displayName === "Audit Player 1", "Nickname was not restored")
                require(ws.roomSession.host, "Host seat was not restored")
                require(ws.globalCode(expectedRoom) === "N2:" + expectedRoom, "Recovery stayed at the entry node")
                require(auditProbe.share("cluster-restored", {ready: true}), "Cannot publish recovery")
                capture("restored-room")
                loginCode = ""
            })
            add("Wait for the cross-node spectator", () => true,
                () => !!auditProbe.readShared("cluster-spectator"))
            add("Inspect joined room", () => {
                capture("host-with-spectator")
                require(auditProbe.share("cluster-inspected", {ready: true}), "Cannot publish inspection")
            })
        } else {
            add("Browse the global lobby", () => click("mainMenuBrowseHubButton"),
                () => !!find("watchListedRoomButton") && !auditWindow.stack.busy)
            add("Inspect cross-node listing", () => {
                require(ws.globalCode("TEST") === "N1:TEST", "Browser did not begin at N1")
                require(ws.roomList.length === 1 && ws.roomList[0].roomId === "N2:" + expectedRoom, "N2 room is absent from N1 lobby")
                capture("global-lobby")
            })
            add("Watch the listed room", () => click("watchListedRoomButton", "roomBrowserBody"),
                () => ws.inRoom && ws.roomSession.role === "spectator" && !auditWindow.stack.busy)
            add("Inspect routed spectator", () => {
                require(ws.globalCode(expectedRoom) === "N2:" + expectedRoom, "Spectator did not reach N2")
                require(!ws.account.authenticated, "Guest unexpectedly owns an account")
                capture("routed-spectator")
                require(auditProbe.share("cluster-spectator", {ready: true}), "Cannot publish spectator")
            })
            add("Wait for host inspection", () => true,
                () => !!auditProbe.readShared("cluster-inspected"))
        }
    }
    function finish(error) {
        finished = true
        if (error) capture("failure")
        const geometry = auditProbe.observe(auditWindow)
        auditProbe.record("result", {status: error ? "failed" : "passed", error: error || "",
            assertions: assertions, pendingStep: index < steps.length ? steps[index].name : "",
            requiredScreenshots: screenshots, requestedWindowMode: geometry.requestedWindowMode,
            windowMode: geometry.windowMode, width: geometry.width, height: geometry.height,
            dpr: geometry.dpr, screenGeometry: geometry.screenGeometry,
            coverage: "Native N1 to N2 allocation, global invitation and listing, cross-node UID recovery, guest spectator routing and takeover disconnect"})
        auditProbe.finish(error ? 1 : 0)
    }
    Component.onCompleted: { try { plan() } catch (error) { finish(String(error)) } }
    Timer {
        interval: 100
        repeat: true
        running: !driver.finished
        onTriggered: {
            if (driver.dispatching) return
            driver.dispatching = true
            try {
                if (driver.index >= driver.steps.length) { driver.finish(""); return }
                const step = driver.steps[driver.index]
                if (driver.entered === 0) driver.entered = Date.now()
                driver.require(Date.now() - driver.entered < 120000, "Timeout: " + step.name)
                if (!driver.acted) driver.acted = step.action() !== false
                if (driver.acted && step.check()) {
                    driver.assertions.push({name: step.name, passed: true})
                    ++driver.index; driver.entered = 0; driver.acted = false
                }
            } catch (error) { driver.finish(String(error)) }
            finally { driver.dispatching = false }
        }
    }
}
