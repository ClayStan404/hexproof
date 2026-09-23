// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import "NativeMotion.js" as Motion

// Run only against an explicitly authorized home hub, with an isolated profile.
// All application mutations, including failure cleanup, use visible controls.
Item {
    id: driver
    readonly property string endpoint: auditProbe.environment("HEXPROOF_AUDIT_HOME_URL")
    readonly property string expectedName: auditProbe.environment("HEXPROOF_AUDIT_HOME_NAME")
    readonly property string expectedVersion: auditProbe.environment("HEXPROOF_AUDIT_HOME_VERSION")
    readonly property string runId: auditProbe.environment("HEXPROOF_AUDIT_RUN_ID")
    readonly property string humanDeck: "Home verification human"
    readonly property string opponentDeck: "Home verification opponent"
    property var steps: []
    property var assertions: []
    property var screenshots: []
    property int index: 0
    property bool acted: false
    property bool busy: false
    property bool finished: false
    property double entered: Date.now()
    property double started: Date.now()
    property string createdRoom: ""
    property string actualTransport: ""
    property string failure: ""
    property double cleanupStarted: 0
    property bool nativePracticeStarted: false

    function require(value, message) { if (!value) throw new Error(message) }
    function find(name, identity) { return auditProbe.find(auditWindow, name, identity || {}) }
    function page() { return auditWindow.stack.currentItem }
    function walk(root, predicate) {
        if (!root || !root.visible || !root.enabled) return null
        if (predicate(root)) return root
        for (const child of root.children || []) {
            const found = walk(child, predicate)
            if (found) return found
        }
        return null
    }
    function click(name, scrollName) {
        const scroll = scrollName ? find(scrollName) : null
        const motion = scroll && scroll.moving === undefined ? scroll.contentItem : scroll
        if (!Motion.settled(motion)) return false
        if (Motion.stopNeeded(motion)) {
            require(auditProbe.click(scroll, 1, 1), "Cannot stop scrolling")
            return false
        }
        const target = find(name)
        if (target) { require(auditProbe.click(target), "Cannot click " + name); return true }
        if (scroll) {
            Motion.scrolled(motion)
            require(auditProbe.wheel(scroll, -360), "Cannot scroll " + scrollName)
        }
        return false
    }
    function clickText(text, scrollName) {
        const target = walk(auditWindow.contentItem, item => item.text === text
            && typeof item.clicked === "function" && auditProbe.canInteract(item))
        if (target) { require(auditProbe.click(target), "Cannot click " + text); return true }
        return click("missing-text-target", scrollName)
    }
    function fill(name, value, scrollName) {
        const target = find(name)
        if (!target || !click(name, scrollName)) {
            if (!target && scrollName) click(name, scrollName)
            return false
        }
        require(auditProbe.key(Qt.Key_A, Qt.ControlModifier) && auditProbe.type(value),
                "Cannot type " + name)
        require(target.text === value, "Typed value differs in " + name)
        return true
    }
    function combo(name, choice, scrollName) {
        if (!click(name, scrollName)) return false
        require(choice >= 0 && auditProbe.key(Qt.Key_Home), "Missing selector choice")
        for (let i = 0; i < choice; ++i)
            require(auditProbe.key(Qt.Key_Down), "Cannot move selector")
        require(auditProbe.key(Qt.Key_Return), "Cannot accept selector")
        return true
    }
    function segment(name, choice, scrollName) {
        const control = find(name)
        const target = control && walk(control, item => item.index === choice
            && typeof item.clicked === "function" && auditProbe.canInteract(item))
        if (target) { require(auditProbe.click(target), "Cannot choose " + name); return true }
        return click("missing-segment-target", scrollName)
    }
    function selectDeck(name) {
        for (let i = 0; i < deckLibrary.count; ++i) {
            const row = find("matchDeckOption" + i, {"modelData.deckName": name})
            const button = row && auditProbe.find(row, "selectMatchDeckButton")
            if (button) return auditProbe.click(button)
        }
        return false
    }
    function opponent() {
        return Array.from(ws.roomSession.seats).find(seat => seat.controller === "forgeAi")
    }
    function add(name, action, check) {
        steps.push({name: name, action: action, check: check || (() => true)})
    }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        screenshots.push(name + ".png")
    }
    function importDeck(name, text, count) {
        add("Open import for " + name, () => click("deckLibraryImportButton"),
            () => !!find("importDeckName"))
        add("Name " + name, () => fill("importDeckName", name))
        add("Select Modern for " + name, () => combo("importDeckFormat",
            page().formatOptions.findIndex(option => option.value === "modern")),
            () => page().deckFormat === "modern")
        add("Enter cards for " + name, () => fill("importDeckText", text))
        add("Import " + name, () => click("importDeckSubmitButton", "importDeckBody"),
            () => !deckLibrary.importingDeck && deckLibrary.count === count
                  && !!find("deckLibraryImportButton"))
    }
    function plan() {
        require(/^wss:\/\/[^/?#@]+\/home\/[a-z0-9][a-z0-9-]{0,62}\/ws$/.test(endpoint),
                "An explicitly authorized WSS home endpoint is required")
        require(["Server Debian", "Server Radxa"].includes(expectedName)
                && expectedVersion === "2.0.6", "Expected home name and version are required")
        require(/^[a-f0-9]{32}$/.test(runId), "The isolated native runner is required")
        const manifest = JSON.parse(auditProbe.readText(
            auditProbe.environment("HEXPROOF_AUDIT_DECK_MANIFEST")))
        const deck = manifest.decks[0]
        require(deck.deckFormat === "modern", "A Modern verification fixture is required")
        const text = deck.mainboard.map(card => card.count + " " + card.name
            + " (" + card.setCode + ") " + card.collectorNumber).join("\n")
        const initialCount = deckLibrary.count
        add("Activate maximized isolated client", () => {
            require(auditProbe.activate(), "Cannot activate test window")
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"])
                if (find(name)) { click(name); return false }
            require(auditProbe.observe(auditWindow).windowMode === "maximized",
                    "Expected a maximized native window")
            require(ws.clientVersion === expectedVersion, "Wrong local client version")
            return !!find("mainMenuDeckLibraryButton")
        })
        add("Open isolated deck library", () => click("mainMenuDeckLibraryButton", "mainMenuBody"),
            () => !!find("deckLibraryImportButton"))
        importDeck(humanDeck, text, initialCount + 1)
        importDeck(opponentDeck, text, initialCount + 2)
        add("Return to main menu", () => click("screenBackButton"),
            () => !!find("mainMenuConnectButton"))
        add("Open maintained server catalog", () => click("mainMenuConnectButton"),
            () => !!find("serverSelector"))
        add("Verify both renamed home entries", () => {}, () => {
            const entries = Array.from(ws.serverEntries)
            return entries.some(entry => entry.name === "Server Debian")
                && entries.some(entry => entry.name === "Server Radxa")
        })
        add("Select the authorized home hub", () => combo("serverSelector",
            Array.from(ws.serverEntries).findIndex(entry => entry.url === endpoint
                && entry.name === expectedName)),
            () => find("serverSelector").displayText.includes(expectedName))
        add("Name isolated player", () => fill("displayNameField", "Home AI audit " + runId.slice(0, 6)))
        add("Capture renamed server selector", () => capture("01-home-ai-catalog"))
        add("Connect to upgraded home hub", () => click("connectSubmitButton"),
            () => ws.connected && !!find("mainMenuDisconnectButton"))
        add("Verify home authority and native AI", () => {
            require(ws.serverUrl === endpoint && !ws.versionMismatch, "Home endpoint/version changed")
            require(ws.forgeRulesAvailable && ws.forgeAIAvailable, "Home hub lacks native Forge AI")
            require(["direct", "relay"].includes(ws.serverTransportState), "Missing home transport route")
            actualTransport = ws.serverTransportState
            require(find("connectedServerStatus").text.includes(expectedName), "Connected name is missing")
            capture("02-home-ai-connected")
        })
        add("Open practice room form", () => click("mainMenuCreateRoomButton", "mainMenuBody"),
            () => !!find("roomFormatSelector"))
        add("Name temporary practice", () => fill("roomNameField", "Home AI verification " + runId.slice(0, 6)))
        add("Choose Modern", () => combo("roomFormatSelector",
            page().selectableFormatOptions.findIndex(option => option.value === "modern")),
            () => page().deckFormat === "modern")
        add("Enable Forge rules", () => clickText("Forge rules", "createRoomBody"),
            () => page().rulesMode === "forge")
        add("Choose background card art", () => clickText("Load in background", "createRoomBody"),
            () => page().cardLoadMode === "background")
        add("Choose native Forge AI", () => segment("roomOpponentControl", 1, "createRoomBody"),
            () => page().aiPractice && page().aiBackendAvailable && page().hostingMode === "server")
        add("Protect temporary room", () => fill("roomPasswordField", "verification-" + runId, "createRoomBody"))
        add("Disable spectators", () => page().allowSpectators
            ? click("allowSpectatorsToggle", "createRoomBody") : true,
            () => !page().allowSpectators)
        add("Create private AI practice", () => click("createRoomSubmitButton", "createRoomBody"),
            () => ws.inRoom && !!find("waitingRoomTitle"))
        add("Record owned temporary room", () => {
            createdRoom = ws.roomSession.roomId
            require(ws.roomSession.host && opponent(), "Home did not create one human/AI room")
            auditProbe.record("owned-room", {roomId: createdRoom, endpoint: endpoint})
        })
        add("Open human deck picker", () => click("waitingRoomSelectDeckButton", "waitingRoomBody"),
            () => !!find("matchDeckOptions"))
        add("Choose human deck", () => selectDeck(humanDeck),
            () => ws.roomSession.selectedDeckName === humanDeck)
        add("Open initial AI deck picker", () => click("waitingRoomSelectAiDeckButton", "waitingRoomBody"),
            () => !!find("matchDeckOptions"))
        add("Set initial AI deck", () => selectDeck(humanDeck),
            () => opponent() && opponent().deckSelected && opponent().ready)
        add("Reopen AI deck editor", () => click("waitingRoomSelectAiDeckButton", "waitingRoomBody"),
            () => !!find("matchDeckOptions"))
        add("Change AI deck independently", () => selectDeck(opponentDeck),
            () => !find("matchDeckOptions") && opponent() && opponent().deckSelected && opponent().ready)
        add("Change waiting-room difficulty", () => segment("waitingRoomAiDifficultyControl", 2, "waitingRoomBody"),
            () => ws.roomSession.aiDifficulty === "hard" && opponent().aiDifficulty === "hard")
        add("Verify ready practice room", () => {
            require(ws.roomSession.selectedDeckName === humanDeck, "AI deck editing changed the human deck")
            require(ws.roomSession.rulesMode === "forge" && ws.roomSession.matchMode === "bo1",
                    "Unexpected AI match mode")
            capture("03-home-ai-ready")
        })
        add("Start server-run native AI practice", () => click("playerReadyButton", "waitingRoomBody"),
            () => ws.rulesSession.active)
        add("Reach native opening-hand decision", () => {
            if (ws.rulesSession.promptKind === "mulligan" && find("rulesPromptOption-$keep")) return true
            if (find("rulesPromptOption-$ack")) click("rulesPromptOption-$ack")
            else if (["chooseBoolean", "chooseFromSelection"].includes(ws.rulesSession.promptKind)) {
                const list = find("rulesScalarCandidates")
                const choice = list ? list.itemAtIndex(0) : null
                if (ws.rulesSession.promptKind === "chooseFromSelection" && choice && choice.count > 0)
                    click("rulesConfirmChoices")
                else if (choice) click("rulesScalarChoice-" + choice.responseId)
            }
            return false
        })
        add("Verify native practice has started", () => {
            nativePracticeStarted = true
            require(ws.roomSession.roomId === createdRoom && ws.rulesSession.gameId.length > 0,
                    "Native practice lost home room identity")
            capture("04-home-ai-opening-hand")
        })
        add("Keep native opening hand", () => click("rulesPromptOption-$keep"),
            () => !ws.rulesResponsePending && ws.rulesSession.promptKind !== "mulligan")
        add("Open game settings", () => click("forgeGameMenu"),
            () => !!find("rulesLeaveRoomButton"))
        add("Leave owned AI practice", () => click("rulesLeaveRoomButton"),
            () => !!find("confirmButton"))
        add("Confirm final-human cleanup", () => click("confirmButton"),
            () => !ws.inRoom && !!find("mainMenuDisconnectButton"))
        add("Verify room and engine released by client", () => {
            require(ws.roomSession.roomId.length === 0 && !ws.rulesSession.active,
                    "Client retained the departed room/game")
            capture("05-home-ai-left")
        })
        add("Disconnect isolated player", () => click("mainMenuDisconnectButton"),
            () => !ws.connected && !ws.reconnecting)
    }
    function finish(error) {
        if (finished) return
        finished = true
        const geometry = auditProbe.observe(auditWindow)
        auditProbe.record("window-geometry", geometry)
        auditProbe.record("result", {
            status: error ? "failed" : "passed", scenario: "home-server-ai", error: error || "",
            endpoint: endpoint, serverName: expectedName, clientVersion: ws.clientVersion,
            transport: actualTransport, createdRoom: createdRoom, roomLeft: !ws.inRoom,
            nativePracticeStarted: nativePracticeStarted, assertions: assertions,
            pendingStep: index < steps.length ? steps[index].name : "",
            requiredScreenshots: screenshots, elapsedMs: Date.now() - started,
            requestedWindowMode: geometry.requestedWindowMode, windowMode: geometry.windowMode,
            width: geometry.width, height: geometry.height, dpr: geometry.dpr,
            screenGeometry: geometry.screenGeometry,
            coverage: "Native home catalog/AI setup/deck editing/start/leave; no full-game or maximum-capacity claim"
        })
        auditProbe.finish(error ? 1 : 0)
    }
    function cleanupFailure() {
        if (!ws.inRoom) { finish(failure); return }
        if (Date.now() - cleanupStarted > 30000) { finish(failure + "; room cleanup timed out"); return }
        if (find("confirmButton")) { click("confirmButton"); return }
        if (find("rulesLeaveRoomButton")) { click("rulesLeaveRoomButton"); return }
        if (find("forgeGameMenu")) { click("forgeGameMenu"); return }
        if (find("waitingRoomLeaveButton")) { click("waitingRoomLeaveButton"); return }
        if (find("overflowLeaveAction")) { click("overflowLeaveAction"); return }
        if (find("waitingRoomOverflowButton")) { click("waitingRoomOverflowButton"); return }
        auditProbe.key(Qt.Key_Escape)
    }
    Component.onCompleted: { try { plan() } catch (error) { finish(String(error)) } }
    Timer {
        interval: 150
        repeat: true
        running: !driver.finished
        onTriggered: {
            if (driver.busy) return
            driver.busy = true
            try {
                if (driver.failure) { driver.cleanupFailure(); return }
                if (auditWindow.stack.busy) return
                if (driver.index >= driver.steps.length) { driver.finish(""); return }
                const step = driver.steps[driver.index]
                driver.require(Date.now() - driver.entered < 90000,
                               "Timeout: " + step.name + "; " + ws.lastError)
                driver.require(!ws.lastError, "Server error: " + ws.lastError)
                if (!driver.acted) driver.acted = step.action() !== false
                if (driver.acted && step.check()) {
                    driver.assertions.push({name: step.name, elapsedMs: Date.now() - driver.entered})
                    ++driver.index
                    driver.acted = false
                    driver.entered = Date.now()
                    auditProbe.record("progress", {index: driver.index,
                        next: driver.index < driver.steps.length ? driver.steps[driver.index].name : "complete"})
                }
            } catch (error) {
                driver.failure = String(error)
                driver.cleanupStarted = Date.now()
                if (auditProbe.capture(auditWindow, "failure")) driver.screenshots.push("failure.png")
            } finally { driver.busy = false }
        }
    }
}
