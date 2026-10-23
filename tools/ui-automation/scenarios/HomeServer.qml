// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: driver
    readonly property string endpoint: auditProbe.environment("HEXPROOF_AUDIT_HOME_URL")
    readonly property string expectedTransport: auditProbe.environment("HEXPROOF_HOME_FORCE_RELAY") === "1" ? "relay" : "direct"
    property var steps: []
    property var assertions: []
    property var screenshots: []
    property int index: 0
    property bool dispatched: false
    property bool dispatching: false
    property bool finished: false
    property double entered: 0
    property double started: Date.now()
    property string createdRoom: ""

    function require(value, message) { if (!value) throw new Error(message) }
    function find(name) { return auditProbe.find(auditWindow, name, ({})) }
    function click(name, scrollName) {
        const target = find(name)
        if (target) {
            require(auditProbe.click(target), "Cannot click " + name)
            return true
        }
        const scroll = scrollName ? find(scrollName) : null
        if (scroll && !scroll.moving)
            require(auditProbe.wheel(scroll, -280), "Cannot scroll " + scrollName)
        return false
    }
    function fill(name, value) {
        const target = find(name)
        if (!target || !click(name)) return false
        require(auditProbe.key(Qt.Key_A, Qt.ControlModifier) && auditProbe.type(value),
                "Cannot type " + name)
        require(target.text === value, "Typed value differs in " + name)
        return true
    }
    function add(name, action, check) {
        steps.push({name: name, action: action, check: check || (() => true)})
    }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        screenshots.push(name + ".png")
    }
    function plan() {
        require(/^ws:\/\/(127\.0\.0\.1|\[::1\]):[0-9]+\/home\/[a-z0-9-]+\/ws$/.test(endpoint),
                "Home audit requires an isolated loopback gateway")
        add("Activate maximized test window", () => {
            require(auditProbe.activate(), "Cannot activate test window")
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"])
                if (find(name)) { click(name); return false }
            require(auditProbe.observe(auditWindow).windowMode === "maximized", "Expected maximized native window")
            return !!find("mainMenuConnectButton")
        }, () => !auditWindow.stack.busy)
        add("Open connection page", () => click("mainMenuConnectButton"),
            () => !!find("serverSelector") && !auditWindow.stack.busy)
        add("Select custom endpoint", () => {
            if (!click("serverSelector")) return false
            require(auditProbe.key(Qt.Key_End) && auditProbe.key(Qt.Key_Return), "Cannot select custom endpoint")
        }, () => !!find("customServerField"))
        add("Enter home gateway URL", () => fill("customServerField", endpoint))
        add("Enter isolated player name", () => fill("displayNameField", "Home audit " + expectedTransport))
        add("Connect through home transport", () => click("connectSubmitButton"),
            () => ws.connected && !!find("mainMenuDisconnectButton") && !auditWindow.stack.busy)
        add("Verify route and logical URL", () => {
            require(ws.serverUrl === endpoint, "Transport replaced the logical server URL")
            require(ws.serverTransportState === expectedTransport, "Expected " + expectedTransport + ", got " + ws.serverTransportState)
            require(find("connectedServerStatus").text.indexOf(expectedTransport) >= 0, "Connection status omits route")
            capture("01-home-" + expectedTransport + "-connected")
        })
        add("Open manual room form", () => click("mainMenuCreateRoomButton", "mainMenuBody"),
            () => !!find("roomNameField") && !auditWindow.stack.busy)
        add("Name temporary room", () => fill("roomNameField", "Home transport " + expectedTransport))
        add("Create temporary manual room", () => click("createRoomSubmitButton", "createRoomBody"),
            () => ws.inRoom && !!find("waitingRoomTitle") && !auditWindow.stack.busy)
        add("Verify home room state and route", () => {
            createdRoom = ws.roomSession.roomId
            require(createdRoom.length > 0 && ws.roomSession.host, "Room creation did not grant host seat")
            require(ws.roomSession.rulesMode === "manual", "Audit must not launch Java")
            require(ws.serverTransportState === expectedTransport, "Room creation changed transport")
            require(find("waitingRoomServerTransport").text.indexOf(expectedTransport) >= 0, "Waiting room omits route")
            capture("02-home-" + expectedTransport + "-room")
        })
        add("Leave temporary room", () => {
            if (find("waitingRoomLeaveButton")) return click("waitingRoomLeaveButton")
            if (find("overflowLeaveAction")) return click("overflowLeaveAction")
            if (find("waitingRoomOverflowButton")) click("waitingRoomOverflowButton")
            return false
        }, () => !!find("confirmButton"))
        add("Confirm leaving room", () => click("confirmButton"),
            () => !ws.inRoom && ws.connected && !auditWindow.stack.busy && !!find("mainMenuDisconnectButton"))
        add("Verify seat released", () => {
            require(ws.roomSession.roomId.length === 0, "Left room identity was retained")
            require(ws.serverTransportState === expectedTransport, "Leave lost home transport")
            capture("03-home-" + expectedTransport + "-left")
        })
        add("Disconnect isolated client", () => click("mainMenuDisconnectButton"),
            () => !ws.connected && !ws.reconnecting && !auditWindow.stack.busy)
    }
    function finish(error) {
        if (finished) return
        finished = true
        if (error && auditProbe.capture(auditWindow, "failure")) screenshots.push("failure.png")
        const geometry = auditProbe.observe(auditWindow)
        auditProbe.record("window-geometry", geometry)
        auditProbe.record("result", {
            status: error ? "failed" : "passed", scenario: "home-server", error: error || "",
            expectedTransport: expectedTransport, endpoint: endpoint, createdRoom: createdRoom,
            assertions: assertions, pendingStep: index < steps.length ? steps[index].name : "",
            requiredScreenshots: screenshots, elapsedMs: Date.now() - started,
            requestedWindowMode: geometry.requestedWindowMode, windowMode: geometry.windowMode,
            width: geometry.width, height: geometry.height, dpr: geometry.dpr,
            screenGeometry: geometry.screenGeometry,
            coverage: "Real local home gateway/node/helper, native connect/create/leave/disconnect; no Internet NAT or TURN qualification"
        })
        auditProbe.finish(error ? 1 : 0)
    }
    Component.onCompleted: { try { plan() } catch (error) { finish(String(error)) } }
    Timer {
        interval: 120
        repeat: true
        running: !driver.finished
        onTriggered: {
            if (driver.dispatching) return
            driver.dispatching = true
            try {
                if (driver.index >= driver.steps.length) { driver.finish(""); return }
                const step = driver.steps[driver.index]
                if (driver.entered === 0) driver.entered = Date.now()
                driver.require(Date.now() - driver.entered < 60000, "Timeout: " + step.name + "; " + ws.lastError)
                if (!driver.dispatched && !auditWindow.stack.busy)
                    driver.dispatched = step.action() !== false
                if (driver.dispatched && step.check()) {
                    driver.assertions.push({name: step.name, passed: true, elapsedMs: Date.now() - driver.entered})
                    ++driver.index
                    driver.entered = 0
                    driver.dispatched = false
                }
            } catch (error) { driver.finish(String(error)) }
            finally { driver.dispatching = false }
        }
    }
}
