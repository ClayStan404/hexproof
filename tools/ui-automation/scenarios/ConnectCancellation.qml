// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: driver
    // The runner starts the healthy loopback hub. A separate loopback TCP
    // fixture accepts connections without answering the WebSocket upgrade.
    readonly property string stalledUrl: auditProbe.environment("HEXPROOF_AUDIT_STALLED_HUB_URL")
    readonly property string healthyUrl: ws.serverUrl
    property string savedHealthyUrl: ""
    property var steps: []
    property var assertions: []
    property int index: 0
    property bool dispatched: false
    property bool dispatching: false
    property bool finished: false
    property double started: Date.now()
    property double entered: 0

    function require(value, message) { if (!value) throw new Error(message) }
    function find(name) { return auditProbe.find(auditWindow, name, ({})) }
    function click(name) {
        const target = find(name)
        if (!target) return false
        require(auditProbe.click(target), "Cannot click " + name)
        return true
    }
    function fillUrl(url) {
        const field = find("customServerField")
        if (!field) return false
        require(auditProbe.click(field) && auditProbe.key(Qt.Key_A, Qt.ControlModifier)
                && auditProbe.text(url), "Cannot enter endpoint")
        require(field.text === url, "Endpoint input mismatch")
        return true
    }
    function add(name, action, check) {
        steps.push({name: name, action: action, check: check || (() => true)})
    }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
    }
    function plan() {
        savedHealthyUrl = healthyUrl
        require(savedHealthyUrl.startsWith("ws://127.0.0.1:"), "A runner-owned local hub is required")
        require(stalledUrl.startsWith("ws://127.0.0.1:"), "A local stalled-handshake fixture is required")
        add("Dismiss startup notices", () => {
            require(auditProbe.activate(), "Cannot activate test window")
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"])
                if (find(name)) { click(name); return false }
            return !!find("mainMenuConnectButton")
        }, () => !auditWindow.stack.busy)
        add("Record local fixture", () => auditProbe.fixture("stalled-upgrade", {
            stalledUrl: stalledUrl, healthyUrl: savedHealthyUrl,
            note: "TCP accepts without a WebSocket upgrade response; no public hub"
        }))
        for (const control of ["connectCancelButton", "screenBackButton"]) {
            add("Open connection page for " + control, () => click("mainMenuConnectButton"),
                () => !!find("connectSubmitButton") && !auditWindow.stack.busy)
            add("Enter stalled endpoint for " + control, () => fillUrl(stalledUrl))
            add("Begin pending handshake for " + control, () => click("connectSubmitButton"),
                () => ws.connecting)
            add("Capture cancellable handshake for " + control, () => capture("pending-" + control))
            add("Cancel using " + control, () => click(control),
                () => !ws.connecting && !ws.connected && !!find("mainMenuConnectButton") && !auditWindow.stack.busy)
        }
        add("Open a new connection after cancelling", () => click("mainMenuConnectButton"),
            () => !!find("connectSubmitButton") && !auditWindow.stack.busy)
        add("Enter healthy local endpoint", () => fillUrl(savedHealthyUrl))
        add("Connect to the healthy hub", () => click("connectSubmitButton"),
            () => ws.connected && !!find("mainMenuDisconnectButton") && !auditWindow.stack.busy)
        add("Verify final connection", () => {
            require(ws.serverUrl === savedHealthyUrl, "Wrong endpoint after cancellation")
            require(ws.roomSession.roomId.length === 0, "Unexpected stale room")
            require(ws.lastError.length === 0, "Stale connection error: " + ws.lastError)
            capture("connected-after-cancellation")
        })
        add("Disconnect through the main menu", () => click("mainMenuDisconnectButton"),
            () => !ws.connected && !!find("mainMenuConnectButton"))
    }
    function finish(error) {
        finished = true
        auditProbe.record("result", {status: error ? "failed" : "passed", error: error || "",
            assertions: assertions, pendingStep: index < steps.length ? steps[index].name : "",
            elapsedMs: Date.now() - started,
            requiredScreenshots: ["pending-connectCancelButton.png", "pending-screenBackButton.png",
                                  "connected-after-cancellation.png"],
            coverage: "Native cancellation by button/back during TCP handshake, fresh connection and disconnect"})
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
                driver.require(Date.now() - driver.entered < 12000, "Timeout: " + step.name)
                if (!driver.dispatched) driver.dispatched = step.action() !== false
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
