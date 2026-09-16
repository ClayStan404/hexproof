// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: driver
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
    function add(name, action, check) {
        steps.push({name: name, action: action, check: check || (() => true)})
    }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
    }
    function plan() {
        add("Dismiss startup notices", () => {
            require(auditProbe.activate(), "Cannot activate test window")
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"])
                if (find(name)) { click(name); return false }
            return !!find("mainMenuConnectButton")
        }, () => !auditWindow.stack.busy)
        add("Open connection page", () => click("mainMenuConnectButton"),
            () => !!find("serverSelector") && !auditWindow.stack.busy)
        add("Refresh online catalog", () => click("refreshServerDirectoryButton"),
            () => !ws.serverDirectoryRefreshing && ws.serverDirectorySource === "online")
        add("Check current fleet and custom endpoint", () => {
            require(ws.serverEntries.length === 4, "Expected three maintained nodes and custom")
            require(ws.serverEntries[0].forge === 0, "Server 1 should be manual-only")
            require(ws.serverEntries[1].forge === 1 && ws.serverEntries[2].forge === 1,
                    "Servers 2 and 3 should advertise Forge")
            require(find("serverSelector").currentIndex === ws.customServerIndex,
                    "Refresh changed the custom selection")
            capture("directory-online")
        })
        add("Open server choices", () => click("serverSelector"),
            () => find("serverSelector").popup.opened)
        add("Inspect supported modes", () => capture("directory-choices"))
        add("Select Server 3 with native keyboard", () => {
            require(auditProbe.key(Qt.Key_Home), "Cannot select first entry")
            require(auditProbe.key(Qt.Key_Down) && auditProbe.key(Qt.Key_Down), "Cannot select Server 3")
            require(auditProbe.key(Qt.Key_Return), "Cannot accept Server 3")
        }, () => find("serverSelector").currentIndex === 2)
        add("Capture selected server", () => capture("directory-server3"))
        add("Leave without connecting to a public hub", () => click("connectCancelButton"),
            () => !!find("mainMenuConnectButton") && !auditWindow.stack.busy)
    }
    function finish(error) {
        finished = true
        auditProbe.record("result", {status: error ? "failed" : "passed", error: error || "",
            assertions: assertions, pendingStep: index < steps.length ? steps[index].name : "",
            elapsedMs: Date.now() - started,
            requiredScreenshots: ["directory-online.png", "directory-choices.png", "directory-server3.png"],
            coverage: "Native maximized connection screen, online fleet, Forge labels, stable custom selection and keyboard selection"})
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
