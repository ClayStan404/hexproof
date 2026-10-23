// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import "NativeMotion.js" as Motion

// All setup and gameplay mutations go through visible production controls.
Item {
    id: driver
    readonly property int seat: Number(auditProbe.environment("AUDIT_SEAT"))
    readonly property string variant: auditProbe.environment("HEXPROOF_AUDIT_VARIANT")
    readonly property bool onlineModelPractice: variant === "model-online"
    readonly property bool modelPractice: variant === "model-local" || onlineModelPractice
    readonly property string modelSource: onlineModelPractice ? "online" : "local"
    readonly property bool aiPractice: variant.startsWith("ai-") || modelPractice
    readonly property string aiDifficulty: variant.startsWith("ai-") ? variant.slice(3) : ""
    readonly property bool playerHosted: auditProbe.environment("HEXPROOF_AUDIT_PLAYER_HOSTED") === "1"
    property var deck: null
    readonly property string importedDeckName: deck ? deck.name.trim() : ""
    property var steps: []
    property var assertions: []
    property int index: 0
    property bool acted: false
    property bool busy: false
    property bool finished: false
    property double entered: Date.now()
    property int initialDecks: 0

    function require(value, message) { if (!value) throw new Error(message + "; " + auditProbe.lastError) }
    function find(name, identity) { return auditProbe.find(auditWindow, name, identity || {}) }
    function page() { return auditWindow.stack.currentItem }
    function walk(root, predicate) {
        if (!root || !root.visible || !root.enabled) return null
        if (predicate(root)) return root
        for (const child of root.children || []) { const found = walk(child, predicate); if (found) return found }
        return null
    }
    function click(name, scrollName) {
        const scroll = scrollName ? find(scrollName) : null
        const motion = scroll && scroll.moving === undefined ? scroll.contentItem : scroll
        if (!Motion.settled(motion)) return false
        if (Motion.stopNeeded(motion)) { require(auditProbe.click(scroll, 1, 1), "Cannot stop scrolling"); return false }
        const target = find(name)
        if (target) { require(auditProbe.click(target), "Cannot click " + name); return true }
        if (scroll) { Motion.scrolled(motion); require(auditProbe.wheel(scroll, -360), "Cannot scroll " + scrollName) }
        return false
    }
    function clickText(text, scrollName) {
        const scroll = scrollName ? find(scrollName) : null
        if (!Motion.settled(scroll)) return false
        if (Motion.stopNeeded(scroll)) { require(auditProbe.click(scroll, 1, 1), "Cannot stop scrolling"); return false }
        const target = walk(auditWindow.contentItem, item => item.text === text
            && typeof item.clicked === "function" && auditProbe.canInteract(item))
        if (target) { require(auditProbe.click(target), "Cannot click " + text); return true }
        if (scroll) { Motion.scrolled(scroll); require(auditProbe.wheel(scroll, -360), "Cannot scroll to " + text) }
        return false
    }
    function fill(name, text, scrollName) {
        const target = find(name)
        if (!target) { if (scrollName) click(name, scrollName); return false }
        if (!click(name, scrollName)) return false
        require(auditProbe.key(Qt.Key_A, Qt.ControlModifier)
                && auditProbe.type(text), "Cannot type " + name)
        require(target.text === text, "System keyboard text differs in " + name)
        return true
    }
    function combo(name, choice, scrollName) {
        if (!click(name, scrollName)) return false
        require(choice >= 0, "Missing format choice")
        require(auditProbe.key(Qt.Key_Home), "Cannot select first option")
        for (let i = 0; i < choice; ++i) require(auditProbe.key(Qt.Key_Down), "Cannot select option")
        require(auditProbe.key(Qt.Key_Return), "Cannot accept format")
        return true
    }
    function segment(name, choice, scrollName) {
        const control = find(name)
        const target = control && walk(control, item => item.index === choice
            && typeof item.clicked === "function" && auditProbe.canInteract(item))
        if (target) { require(auditProbe.click(target), "Cannot choose " + name); return true }
        const scroll = scrollName ? find(scrollName) : null
        if (scroll && Motion.settled(scroll)) {
            Motion.scrolled(scroll)
            require(auditProbe.wheel(scroll, -360), "Cannot scroll to " + name)
        }
        return false
    }
    function selectImportedDeck() {
        const row = find("matchDeckOption0", {"modelData.deckName":importedDeckName})
        const button = row && auditProbe.find(row, "selectMatchDeckButton")
        return !!button && auditProbe.click(button)
    }
    function add(name, action, check) { steps.push({name:name, action:action, check:check || (() => true)}) }
    function capture(name) { require(auditProbe.capture(auditWindow, name), "Cannot capture " + name) }
    function printingTotals(cards) {
        const totals = new Map()
        for (const card of cards) {
            const identity = JSON.stringify([card.name, card.setCode.toUpperCase(), card.collectorNumber])
            totals.set(identity, (totals.get(identity) || 0) + card.count)
        }
        return totals
    }
    function plan() {
        const manifest = JSON.parse(auditProbe.readText(auditProbe.environment("AUDIT_DECK_MANIFEST")))
        deck = manifest.decks[seat - 1]
        require(deck && ["standard", "pioneer", "modern", "legacy"].includes(deck.deckFormat), "Missing constructed deck")
        require(!aiPractice || (seat === 1 && (modelPractice || ["easy", "normal", "hard"].includes(aiDifficulty))), "Invalid AI scenario")
        initialDecks = deckLibrary.count
        const rows = cards => cards.map(c => c.count + " " + c.name + " (" + c.setCode + ") " + c.collectorNumber).join("\n")
        const text = rows(deck.mainboard) + (deck.sideboard.length ? "\n\nSideboard\n" + rows(deck.sideboard) : "")
        add("Dismiss startup notices", () => {
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"])
                if (find(name)) { click(name); return false }
            return !!find("mainMenuDeckLibraryButton")
        })
        if (modelPractice) {
            let endpoint = auditProbe.environment("HEXPROOF_AUDIT_MODEL_ENDPOINT")
            let model = "hexproof-test-fixture"
            let credentials = null
            if (onlineModelPractice) {
                // The owner explicitly supplies this existing file. Never put
                // credentials in runner arguments, environment, or artifacts.
                const settingsPath = auditProbe.environment("HEXPROOF_AUDIT_CLAUDE_SETTINGS")
                require(settingsPath.startsWith("/"), "Online verification requires an explicit settings file")
                credentials = JSON.parse(auditProbe.readText(settingsPath)).env
                const base = String(credentials.ANTHROPIC_BASE_URL || "").replace(/\/+$/, "")
                require(base.startsWith("https://") && !!credentials.ANTHROPIC_AUTH_TOKEN,
                    "Online verification requires HTTPS and a session credential")
                endpoint = base.endsWith("/v1") ? base : base + "/v1"
                model = auditProbe.environment("HEXPROOF_AUDIT_MODEL_NAME")
                require(model.length > 0, "Online verification requires an explicit model identifier")
            } else {
                require(/^http:\/\/127\.0\.0\.1:\d+\/v1$/.test(endpoint), "Model fixture must use a loopback endpoint")
            }
            add("Open model settings hub", () => click("mainMenuSettingsButton", "mainMenuBody"), () => !!find("settingsBody"))
            add("Open model settings", () => click("settingsModelOpponent", "settingsBody"), () => !!find("modelEndpoint"))
            if (onlineModelPractice)
                add("Select online profile", () => segment("modelProfileSource", 1), () => page().source === "online")
            add("Configure model endpoint", () => fill("modelEndpoint", endpoint))
            add("Configure model name", () => fill("modelIdentifier", model))
            add("Capture model endpoint", () => capture("model-endpoint"))
            if (onlineModelPractice) {
                add("Enter session credential", () => fill("modelApiKey", credentials.ANTHROPIC_AUTH_TOKEN))
                add("Bound online requests", () => fill("modelMaxCalls", "120", "settingsBody"))
                add("Allow structured model output", () => fill("modelMaxOutput", "4096", "settingsBody"))
                add("Bound online game tokens", () => fill("modelTokenBudget", "4000000", "settingsBody"))
                add("Select compatible output limit", () => combo("modelTokenParameter", 0, "settingsBody"))
            }
            add("Save model connection", () => click("modelSave", "settingsBody"),
                () => ws.modelOpponent.configured(modelSource))
            add("Release credential reference", () => { credentials = null })
            add("Test model connection", () => click("modelTest", "settingsBody"),
                () => !ws.modelOpponent.busy && ws.modelOpponent.testStatus === "passed")
            add("Capture model settings", () => capture("model-settings"))
            add("Return to settings hub", () => click("screenBackButton"), () => !!find("settingsModelOpponent"))
            add("Return to main menu", () => click("screenBackButton"), () => !!find("mainMenuDeckLibraryButton"))
        }
        add("Open deck library", () => click("mainMenuDeckLibraryButton", "mainMenuBody"), () => !!find("deckLibraryImportButton"))
        add("Open deck import", () => click("deckLibraryImportButton"), () => !!find("importDeckName"))
        add("Type deck name", () => fill("importDeckName", deck.name))
        add("Choose deck format", () => combo("importDeckFormat", page().formatOptions.findIndex(o => o.value === deck.deckFormat)),
            () => page().deckFormat === deck.deckFormat)
        if (/[^\x00-\x7f]/.test(text)) {
            const file = auditProbe.environment("AUDIT_DECK_TEXT_FILE")
            require(file && auditProbe.readText(file) === text, "Missing exact UTF-8 deck import file")
            add("Open source file chooser", () => click("chooseDeckListFileButton", "importDeckBody"),
                () => auditProbe.fileDialogState("importDeckFileDialog").visible === true)
            add("Choose complete UTF-8 source deck", () => {
                require(auditProbe.chooseFile("importDeckFileDialog", file), "Cannot select deck source file")
                require(find("importDeckText").text === text, "File import changed source deck text")
            })
        } else {
            add("Type complete source deck", () => fill("importDeckText", text))
        }
        add("Import source deck", () => click("importDeckSubmitButton", "importDeckBody"),
            () => !deckLibrary.importingDeck && deckLibrary.count === initialDecks + 1 && !!find("deckLibraryImportButton"))
        add("Review imported deck", () => {
            const label = find("libraryDeckName", {text:importedDeckName})
            return !!label && auditProbe.doubleClick(label)
        }, () => !!find("deckFormatSelector"))
        add("Verify actual card identities", () => {}, () => {
            if (!deckLibrary.currentValidationVerified) return false
            require(deckLibrary.currentDeckName === importedDeckName && deckLibrary.currentDeckFormat === deck.deckFormat, "Import metadata changed")
            require(deckLibrary.currentValidationIssues.length === 0,
                "Imported source deck is not selectable: " + JSON.stringify(Array.from(deckLibrary.currentValidationIssues)))
            for (const [expected, actual] of [[deck.mainboard, Array.from(deckLibrary.mainCards)],
                                             [deck.sideboard, Array.from(deckLibrary.sideboardCards)]]) {
                // Published lists may split copies across rows. The importer
                // merges equal printings; compare their physical-card totals.
                const wanted = printingTotals(expected)
                const imported = printingTotals(actual)
                require(wanted.size === imported.size, "Import changed distinct printings")
                for (const [identity, count] of wanted)
                    require(imported.get(identity) === count, "Import changed card count or identity: " + identity)
            }
            capture("imported-deck")
            auditProbe.record("registered-source-deck", deck)
            return true
        })
        add("Return to library", () => click("screenBackButton"), () => !!find("deckLibraryImportButton"))
        add("Return to main menu", () => click("screenBackButton"), () => !!find("mainMenuConnectButton"))
        add("Open server connection", () => click("mainMenuConnectButton"), () => !!find("connectSubmitButton"))
        add("Connect to local hub", () => click("connectSubmitButton"), () => ws.connected && !auditWindow.stack.busy)
        if (seat === 1) {
            add("Open room form", () => click("mainMenuCreateRoomButton", "mainMenuBody"), () => !!find("roomFormatSelector"))
            add("Name room", () => fill("roomNameField", "OS match " + deck.deckFormat))
            add("Choose room format", () => combo("roomFormatSelector", page().selectableFormatOptions.findIndex(o => o.value === deck.deckFormat)),
                () => page().deckFormat === deck.deckFormat)
            add("Enable Forge rules", () => clickText("Forge rules", "createRoomBody"), () => page().rulesMode === "forge")
            if (playerHosted) {
                add("Choose local player hosting", () => segment("forgeHostingMode", 1, "createRoomBody"),
                    () => page().hostingMode === "player" && !ws.forgeHost.busy && ws.forgeHost.ready)
            }
            add("Choose background art loading", () => clickText("Load in background", "createRoomBody"), () => page().cardLoadMode === "background")
            if (aiPractice) {
                add("Choose AI opponent", () => segment("roomOpponentControl", onlineModelPractice ? 3 : modelPractice ? 2 : 1, "createRoomBody"),
                    () => page().aiPractice && (!modelPractice || page().aiSource === modelSource))
                if (!modelPractice) add("Choose AI strength", () => segment("roomAiDifficultyControl", ["easy", "normal", "hard"].indexOf(aiDifficulty), "createRoomBody"),
                    () => page().aiDifficulty === aiDifficulty)
                add("Capture AI setup", () => capture("ai-create-room"))
            }
            add("Create room", () => click("createRoomSubmitButton", "createRoomBody"), () => ws.inRoom)
            add("Share visible room code", () => auditProbe.share("desktop-room", {id:ws.roomSession.roomId}))
        } else {
            add("Wait for room code", () => {}, () => !!(auditProbe.readShared("desktop-room") || {}).id)
            add("Open join form", () => click("mainMenuJoinRoomButton", "mainMenuBody"), () => !!find("joinRoomCodeField"))
            add("Type room code", () => fill("joinRoomCodeField", auditProbe.readShared("desktop-room").id))
            add("Join room", () => click("joinRoomSubmitButton", "joinRoomBody"), () => ws.inRoom)
        }
        add("Open deck picker", () => click("waitingRoomSelectDeckButton", "waitingRoomBody"), () => !!find("matchDeckOptions"))
        add("Select imported deck", selectImportedDeck, () => ws.roomSession.selectedDeckName === importedDeckName)
        if (aiPractice) {
            add("Open AI deck picker", () => click("waitingRoomSelectAiDeckButton", "waitingRoomBody"), () => !!find("matchDeckOptions"))
            add("Select AI deck independently", selectImportedDeck, () => {
                const opponent = Array.from(ws.roomSession.seats).find(s => s.controller === (modelPractice ? "modelAi" : "forgeAi"))
                return !!opponent && opponent.deckSelected && opponent.ready
            })
            add("Verify AI room", () => {
                const opponent = Array.from(ws.roomSession.seats).find(s => s.controller === (modelPractice ? "modelAi" : "forgeAi"))
                if (modelPractice) require(ws.roomSession.aiSource === modelSource, "Model source changed")
                else require(ws.roomSession.aiDifficulty === aiDifficulty && opponent.aiDifficulty === aiDifficulty, "AI strength changed")
                require(ws.roomSession.matchMode === "bo1" && ws.roomSession.rulesMode === "forge", "Incorrect AI match mode")
                capture("ready-room")
                auditProbe.record("ai-setup", {difficulty:aiDifficulty, controller:opponent.controller, deck:importedDeckName})
            })
        } else {
            add("Verify ready room", () => {
                require(ws.roomSession.rulesMode === "forge" && ws.roomSession.deckFormat === deck.deckFormat, "Incorrect room mode")
                capture("ready-room")
                auditProbe.share("desktop-selected-" + seat, {ready:true})
            }, () => !!(auditProbe.readShared("desktop-selected-" + (seat === 1 ? 2 : 1)) || {}).ready)
        }
        add("Ready through the player button", () => click("playerReadyButton", "waitingRoomBody"), () => ws.rulesSession.active)
    }
    Loader {
        id: match
        active: false
        onLoaded: item.deck()
    }
    Component.onCompleted: { try { plan() } catch (error) { fail(String(error)) } }
    function fail(error) {
        finished = true
        auditProbe.capture(auditWindow, "failure")
        auditProbe.record("failure-observation", auditProbe.observe(auditWindow))
        auditProbe.record("result", {status:"failed", error:error, step:index < steps.length ? steps[index].name : "handoff", serverError:ws.lastError,
            modelStatus:ws.modelOpponent.status, modelError:ws.modelOpponent.lastError})
        auditProbe.finish(1)
    }
    Connections {
        target: auditProbe
        function onStepRequested() {
            if (driver.busy || driver.finished) return
            driver.busy = true
            try {
                driver.require(auditProbe.beginInput(), "Cannot acquire desktop input")
                if (!auditWindow.active && !auditProbe.fileDialogState("importDeckFileDialog").visible)
                    driver.require(auditProbe.activate(), "Cannot focus setup window")
                driver.require(!ws.lastError, "Server error " + ws.lastError)
                driver.require(Date.now() - driver.entered < 60000, "Setup timed out")
                if (auditWindow.stack.busy) return
                if (driver.index >= driver.steps.length) {
                    auditProbe.record("desktop-setup", {assertions:driver.assertions, deck:driver.deck.name, allMutations:"system-input"})
                    driver.finished = true
                    match.setSource("ForgeDuelMatch.qml", {productionSetup:true, stage:3,
                        variant:driver.aiPractice ? "format-" + driver.deck.deckFormat : driver.variant})
                    match.active = true
                    return
                }
                const step = driver.steps[driver.index]
                if (!driver.acted) driver.acted = step.action() !== false
                if (driver.acted && step.check()) {
                    driver.assertions.push({name:step.name, elapsedMs:Date.now() - driver.entered})
                    driver.index++; driver.acted = false; driver.entered = Date.now()
                    auditProbe.record("desktop-progress", {index:driver.index, next:driver.index < driver.steps.length ? driver.steps[driver.index].name : "match"})
                }
            } catch (error) { driver.fail(String(error)) }
            finally { auditProbe.endInput(); driver.busy = false }
        }
    }
}
