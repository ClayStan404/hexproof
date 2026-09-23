// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: driver
    readonly property string endpoint: auditProbe.environment("HEXPROOF_AUDIT_FAILURE_URL")
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
    function segment(name, index, scrollName) {
        const target = find(name)
        if (!target) { if (scrollName) click(name, scrollName); return false }
        require(auditProbe.click(target, target.width * (index + 0.5) / target.options.length,
                                target.height / 2), "Cannot select " + name)
        return true
    }
    function plan() {
        require(/^ws:\/\/(127\.0\.0\.1|\[::1\]):[0-9]+\/ws$/.test(endpoint),
                "Failure audit requires an isolated loopback fixture server")
        add("Activate maximized test window", () => {
            require(auditProbe.activate(), "Cannot activate test window")
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"])
                if (find(name)) { click(name); return false }
            require(auditProbe.observe(auditWindow).windowMode === "maximized", "Expected maximized native window")
            return !!find("mainMenuSettingsButton")
        }, () => !auditWindow.stack.busy)
        add("Open settings", () => click("mainMenuSettingsButton"), () => !!find("settingsBody"))
        add("Open language settings", () => click("settingsLanguageModule", "settingsBody"),
            () => !!find("settingsLanguageSelector"))
        add("Select Chinese using the visible control", () => segment("settingsLanguageSelector", 1),
            () => preferences.uiLanguage === "zh")
        add("Return to settings categories", () => click("screenBackButton"), () => !!find("settingsBody"))
        add("Return to main menu", () => click("screenBackButton"), () => !!find("mainMenuConnectButton"))
        add("Open connection page", () => click("mainMenuConnectButton"),
            () => !!find("serverSelector") && !auditWindow.stack.busy)
        add("Select custom endpoint", () => {
            if (!click("serverSelector")) return false
            require(auditProbe.key(Qt.Key_End) && auditProbe.key(Qt.Key_Return), "Cannot select custom endpoint")
        }, () => !!find("customServerField"))
        add("Enter local fixture URL", () => fill("customServerField", endpoint))
        add("Enter isolated player name", () => fill("displayNameField", "Failure audit"))
        add("Connect to local fixture", () => click("connectSubmitButton"),
            () => ws.connected && !!find("mainMenuDisconnectButton") && !auditWindow.stack.busy)
        add("Open room form", () => click("mainMenuCreateRoomButton", "mainMenuBody"),
            () => !!find("roomNameField") && !auditWindow.stack.busy)
        add("Name temporary fixture room", () => fill("roomNameField", "Local Forge failure verification"))
        add("Enable Forge rules", () => segment("forgeRulesMode", 1, "createRoomBody"),
            () => auditWindow.stack.currentItem.rulesMode === "forge")
        add("Create fixture room", () => click("createRoomSubmitButton", "createRoomBody"),
            () => ws.inRoom && !!find("waitingRoomTitle") && !auditWindow.stack.busy)
        add("Observe prepared fixture seats", () => {
            createdRoom = ws.roomSession.roomId
            require(ws.roomSession.rulesMode === "forge", "Expected Forge room")
            require(ws.roomSession.seats[0].deckSelected, "Fixture did not retain selected deck")
        })
        add("Ready and enter the loading screen", () => click("playerReadyButton", "waitingRoomBody"),
            () => !!find("matchLoadingBody"))
        add("Capture real loading screen", () => capture("01-loading"))
        add("Wait for startup failure and return to room", () => true,
            () => ws.roomSession.phase === "waiting"
                && !!find("rulesStartFailureDialogCopyButton") && !auditWindow.stack.busy)
        add("Verify private localized multiline details", () => {
            const details = find("rulesStartFailureText")
            require(details && details.text.indexOf("Forest (M21 999999)") >= 0, "Missing first printing identity")
            require(details.text.indexOf("Island (ZZZZ 1)") >= 0, "Missing second printing identity")
            require(details.text.indexOf("当前 Forge 运行包无法识别此牌或所选印刷") >= 0,
                    "Detailed diagnostic was not localized")
            require(details.text.indexOf("private raw engine exception") < 0, "Raw exception reached UI")
            require(ws.rulesStartFailure.issues.length === 2, "Lost private details during return to room")
            capture("02-chinese-start-failure-details")
        })
        add("Copy detailed error using native input", () => click("rulesStartFailureDialogCopyButton"))
        add("Close details while preserving failure", () => click("rulesStartFailureDialogCloseButton"),
            () => !find("rulesStartFailureDialogCloseButton") && !!find("rulesStartFailureDetailsButton"))
        add("Verify persistent notice is above scrolling room content", () => {
            const notice = find("waitingRoomStartFailure")
            const body = find("waitingRoomBody")
            const page = auditWindow.stack.currentItem
            require(notice && body && notice.mapToItem(page, 0, 0).y + notice.height <= body.mapToItem(page, 0, 0).y + 1,
                    "Failure notice is not visible above room content")
            require(ws.rulesStartFailure.reason === "deck_rejected", "Closing details erased failure")
            require(ws.roomSession.seats[0].deckSelected && !ws.roomSession.seats[0].ready,
                    "Failure changed selected deck or retained ready")
            capture("03-persistent-top-notice")
        })
        add("Reopen detailed error", () => click("rulesStartFailureDetailsButton"),
            () => !!find("rulesStartFailureDialogCloseButton"))
        add("Close reopened details", () => click("rulesStartFailureDialogCloseButton"),
            () => !!find("rulesStartFailureDismissButton"))
        add("Dismiss reviewed failure", () => click("rulesStartFailureDismissButton"),
            () => !ws.rulesStartFailure.reason && !find("rulesStartFailureDetailsButton"))
        add("Leave fixture room", () => {
            if (find("waitingRoomLeaveButton")) return click("waitingRoomLeaveButton")
            if (find("overflowLeaveAction")) return click("overflowLeaveAction")
            if (find("waitingRoomOverflowButton")) click("waitingRoomOverflowButton")
            return false
        }, () => !!find("confirmButton"))
        add("Confirm leaving room", () => click("confirmButton"),
            () => !ws.inRoom && ws.connected && !auditWindow.stack.busy && !!find("mainMenuDisconnectButton"))
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
            status: error ? "failed" : "passed", scenario: "forge-start-failure", error: error || "",
            endpoint: endpoint, createdRoom: createdRoom, roomLeft: !ws.inRoom,
            assertions: assertions, pendingStep: index < steps.length ? steps[index].name : "",
            requiredScreenshots: screenshots, elapsedMs: Date.now() - started,
            requestedWindowMode: geometry.requestedWindowMode, windowMode: geometry.windowMode,
            width: geometry.width, height: geometry.height, dpr: geometry.dpr,
            screenGeometry: geometry.screenGeometry,
            coverage: "Loopback WebSocket fixtures through production client; native Chinese loading-to-room, detailed error, copy/close/reopen/dismiss/leave. Runtime validation and recipient privacy covered by separate server/Java tests."
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
