// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

// Cached local decks/art are fixture setup. Room creation, joining, Ready,
// turns, departure and restart use native production controls. Only transport
// interruption is an explicit loopback fault; recovery uses the real client.
Item {
    id: driver
    readonly property int actor: Number(auditProbe.environment("HEXPROOF_AUDIT_SEAT"))
    readonly property int participants: Number(auditProbe.environment("HEXPROOF_AUDIT_PLAYERS"))
    readonly property string departureVariant: auditProbe.environment("HEXPROOF_AUDIT_VARIANT") || "edh-starter"
    readonly property bool startingDeparture: departureVariant !== "edh-nonstarter"
    property int step: 0
    property double entered: Date.now()
    property bool busy: false
    property bool comboOpened: false
    property int ownSeat: -1
    property var order: []
    property int departedSeat: -1
    property int hostBefore: -1
    property int hostAfter: -1
    property bool departedStartingPlayer: false
    property string departureCoverageGap: ""
    property string roleBefore: ""
    property var remainingOrder: []
    property var checks: []
    property var screenshots: []
    property int turnIndex: 0
    property bool turnSubmitted: false
    property int restarts: 0
    property bool sawDisconnect: false
    property var resumeBefore: ({})
    property var layoutChecks: []
    property string pendingLayoutSignature: ""
    property double pendingLayoutAt: 0
    property var presentationChecks: []
    property bool phaseSelectorOpened: false
    property bool phaseNavigationSubmitted: false
    property bool phaseNavigationConfirmed: false

    function require(ok, message) { if (!ok) throw new Error(message + "; " + auditProbe.lastError) }
    function find(name) { return auditProbe.find(auditWindow, name) }
    function click(name) {
        const target = find(name)
        if (!target) return false
        require(auditProbe.click(target), "Cannot click " + name)
        return true
    }
    function key(value, modifiers) {
        require(auditProbe.key(value, modifiers || 0), "Cannot deliver native shortcut")
    }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        screenshots.push(name + ".png")
    }
    function shared(name) { return auditProbe.readShared(name) || {} }
    function actors(includeDeparted) {
        const result = []
        for (let i = 1; i <= participants; ++i) {
            const entry = shared("seat-" + i)
            if (includeDeparted || entry.seat !== departedSeat) result.push(i)
        }
        return result
    }
    function all(name, includeDeparted) {
        return actors(includeDeparted).every(value => shared(name + "-" + value).ready)
    }
    function mark(name, detail) {
        require(auditProbe.share(name + "-" + actor, Object.assign({ready:true}, detail || {})), "Cannot share barrier")
    }
    function next(label) {
        checks.push({step:step, label:label, elapsedMs:Date.now() - entered})
        require(auditProbe.record("progress", {step:step, label:label}), "Cannot record progress")
        step++; entered = Date.now()
    }
    function hand() {
        const model = gameTable.zoneModel(ws.roomSession.seatIndex, "hand"), rows = []
        require(model, "Owner hand model is not ready for authenticated seat " + ws.roomSession.seatIndex)
        for (let i = 0; i < model.count; ++i) {
            const card = model.get(i)
            rows.push({id:card.id, name:card.name, setCode:card.setCode, collectorNumber:card.collectorNumber})
        }
        return rows
    }
    function privateState() {
        const ownPublic = Object.assign({}, gameTable.seatData(ownSeat))
        // Delegate revisions are local rendering bookkeeping, not recoverable
        // game state. A reconnect may rebuild them without changing a card.
        delete ownPublic.modelRevision
        return {roomId:ws.roomSession.roomId, seat:ws.roomSession.seatIndex, host:ws.roomSession.host,
            gameNumber:ws.gameSession.gameNumber, startingSeat:ws.gameSession.startingSeat,
            activeSeat:ws.gameSession.activeSeat, turnOrder:ws.gameSession.turnOrder,
            score:ws.gameSession.score, hand:hand(), ownPublic:ownPublic}
    }
    function privacy() {
        require(hand().length > 0 && hand().every(card => card.id && card.name), "Owner private hand absent")
        for (let i = 0; i < ws.roomSession.maxSeats; ++i) {
            if (i === ownSeat) continue
            const model = gameTable.zoneModel(i, "hand")
            // A never-occupied fourth seat has no model in a three-player
            // projection. Every actual participant must still have a model;
            // any retained model for a released/empty seat must be redacted.
            if ((ws.gameSession.turnOrder || []).includes(i))
                require(model, "Participating opponent hand projection is not ready")
            if (model) require(model.count === 0, "Opponent hand identities exposed")
        }
    }
    function numericCycleEquivalent(values) {
        const numeric = Array.from(values).sort((left, right) => left - right)
        const offset = numeric.indexOf(values[0])
        return values.every((seat, index) => seat === numeric[(offset + index) % numeric.length])
    }
    function expectedBattlefieldPositions(values, viewerSeat) {
        require([2,3,4].includes(values.length) && new Set(values).size === values.length,
            "Battlefield geometry needs two to four unique participating seats")
        const offset = values.indexOf(viewerSeat)
        require(offset >= 0, "Rendered battlefield viewer is absent from the authoritative order")
        const relative = values.slice(offset).concat(values.slice(0, offset))
        if (values.length === 4)
            return [{seat:relative[1], position:"upper-left", row:0, column:0, fullWidth:false},
                {seat:relative[2], position:"upper-right", row:0, column:1, fullWidth:false},
                {seat:relative[0], position:"lower-left", row:1, column:0, fullWidth:false},
                {seat:relative[3], position:"lower-right", row:1, column:1, fullWidth:false}]
        if (values.length === 3)
            return [{seat:relative[1], position:"upper-left", row:0, column:0, fullWidth:false},
                {seat:relative[2], position:"upper-right", row:0, column:1, fullWidth:false},
                {seat:relative[0], position:"lower-full-width", row:1, column:0, fullWidth:true}]
        return [{seat:relative[1], position:"upper-full-width", row:0, column:0, fullWidth:true},
            {seat:relative[0], position:"lower-full-width", row:1, column:0, fullWidth:true}]
    }
    function assertBattlefieldGeometry(values, viewerSeat, grid, fields) {
        const expected = expectedBattlefieldPositions(values, viewerSeat)
        const tolerance = 2
        const midX = grid.x + grid.width / 2, midY = grid.y + grid.height / 2
        require(grid.width > 0 && grid.height > 0 && fields.length === expected.length
            && new Set(fields.map(field => field.seat)).size === expected.length,
            "Rendered battlefield grid is incomplete or duplicates a participant")
        for (const placement of expected) {
            const field = fields.find(value => value.seat === placement.seat)
            require(field, "No rendered battlefield for authoritative seat " + placement.seat)
            const rect = field.rect
            const right = rect.x + rect.width, bottom = rect.y + rect.height
            require([rect.x, rect.y, rect.width, rect.height].every(Number.isFinite)
                && rect.width >= grid.width * (placement.fullWidth ? 0.9 : 0.4)
                && rect.height >= grid.height * 0.3,
                "Rendered battlefield has invalid or collapsed geometry for seat " + placement.seat)
            require(rect.x >= grid.x - tolerance && rect.y >= grid.y - tolerance
                && right <= grid.x + grid.width + tolerance && bottom <= grid.y + grid.height + tolerance,
                "Rendered battlefield escapes its grid for seat " + placement.seat)
            const vertical = placement.row === 0 ? bottom <= midY + tolerance : rect.y >= midY - tolerance
            const horizontal = placement.fullWidth
                ? Math.abs(rect.x - grid.x) <= tolerance && Math.abs(right - grid.x - grid.width) <= tolerance
                : (placement.column === 0 ? right <= midX + tolerance : rect.x >= midX - tolerance)
            require(vertical && horizontal,
                "Rendered battlefield seat " + placement.seat + " is not " + placement.position
                + " in the authoritative rolled order " + JSON.stringify(values))
        }
        for (let left = 0; left < fields.length; ++left) {
            for (let right = left + 1; right < fields.length; ++right) {
                const a = fields[left].rect, b = fields[right].rect
                const width = Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x)
                const height = Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y)
                require(width <= tolerance || height <= tolerance,
                    "Rendered participant battlefields overlap")
            }
        }
        return expected
    }
    function verifyRenderedBattlefields(label, values) {
        // Observe real visible QQuickItem rectangles. Never read the model's
        // intended placement or force its projection/layout to refresh.
        const observed = auditProbe.observe(auditWindow)
        const items = Array.from(observed.items || []).filter(value => value.visible && value.inViewport)
        const grids = items.filter(value => value.objectName === "battlefieldGrid")
        const zones = items.filter(value => /^battlefieldZone[0-9]+$/.test(value.objectName))
        if (grids.length !== 1 || zones.length !== values.length) return false
        const grid = Object.assign({}, grids[0].rect)
        const fields = zones.map(value => ({seat:Number(value.objectName.slice("battlefieldZone".length)),
            objectName:value.objectName, rect:Object.assign({}, value.rect)})).sort((a, b) => a.seat - b.seat)
        const signature = JSON.stringify({label:label, grid:grid, fields:fields})
        // Let native layout polish settle across separate driver callbacks.
        // Every client waits at this barrier before any next game action.
        if (signature !== pendingLayoutSignature) {
            pendingLayoutSignature = signature
            pendingLayoutAt = Date.now()
            return false
        }
        if (Date.now() - pendingLayoutAt < 150) return false
        const detail = {label:label, verified:false, viewerSeat:ownSeat,
            authoritativeOrder:Array.from(values), grid:grid, renderedFields:fields,
            numericCycleEquivalent:numericCycleEquivalent(values),
            distinguishesNumericSeatOrdering:!numericCycleEquivalent(values),
            beforeFirstTypedGameAction:label === "opening",
            settledAcrossCallbacksMs:Date.now() - pendingLayoutAt}
        require(auditProbe.record("battlefield-geometry-" + label, detail), "Cannot record rendered battlefield geometry")
        detail.expectedPositions = assertBattlefieldGeometry(values, ownSeat, grid, fields)
        detail.verified = true
        require(auditProbe.record("battlefield-geometry-" + label, detail), "Cannot record verified battlefield geometry")
        layoutChecks.push(detail)
        pendingLayoutSignature = ""
        return true
    }
    function renderedItem(name, scope) {
        const item = scope || auditWindow.contentItem
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const found = renderedItem(name, child)
            if (found) return found
        }
        return null
    }
    function fullItemRect(item) {
        const a = item.mapToItem(auditWindow.contentItem, 0, 0)
        const b = item.mapToItem(auditWindow.contentItem, item.width, item.height)
        return {x:a.x, y:a.y, width:b.x - a.x, height:b.y - a.y}
    }
    function intersectRects(a, b) {
        const x = Math.max(a.x, b.x), y = Math.max(a.y, b.y)
        return {x:x, y:y, width:Math.max(0, Math.min(a.x+a.width, b.x+b.width)-x),
            height:Math.max(0, Math.min(a.y+a.height, b.y+b.height)-y)}
    }
    function fullyRendered(name) {
        const item = renderedItem(name)
        require(item && item.visible, "Missing visible manual control " + name)
        const full = fullItemRect(item)
        let clipped = intersectRects(full, {x:0, y:0, width:auditWindow.width, height:auditWindow.height})
        // Inactive players' phase controls are disabled but still visible.
        // Read actual ancestor clipping without treating disabled as hidden.
        for (let ancestor = item; ancestor; ancestor = ancestor.parent) {
            require(ancestor.visible && ancestor.opacity > 0, "Hidden ancestor for " + name)
            if (ancestor.clip) clipped = intersectRects(clipped, fullItemRect(ancestor))
        }
        require(full.width > 0 && full.height > 0
            && ["x","y","width","height"].every(key => Math.abs(full[key]-clipped[key]) <= 1),
            "Manual control is clipped: " + name + " " + JSON.stringify({full:full, clipped:clipped}))
        return {objectName:name, text:String(item.text || ""), enabled:item.enabled,
            fullRect:full, clippedRect:clipped}
    }
    function verifyManualPresentation(label, eliminatedSeat) {
        const phases = ["untap","upkeep","draw","main_1","begin_combat","declare_attackers",
            "declare_blockers","combat_damage","end_combat","main_2","end"]
        const selector = renderedItem("compactPhaseSelector")
        require(selector, "Manual phase selector is missing")
        const detail = {label:label, seat:ownSeat, phase:ws.gameSession.currentPhase,
            phaseMode:selector.visible ? "selector" : "complete-list", controls:[], eliminatedSeat:eliminatedSeat}
        if (selector.visible) {
            require(selector.count === phases.length
                && JSON.stringify(selector.model.map(row => row.id)) === JSON.stringify(phases),
                "Phase selector does not expose the exact eleven steps")
            require(selector.currentIndex === phases.indexOf(ws.gameSession.currentPhase),
                "Phase selector differs from authoritative current phase")
            detail.controls.push(fullyRendered("compactPhaseSelector"))
        } else {
            for (let index = 0; index < phases.length; ++index)
                detail.controls.push(fullyRendered("phaseButton" + index))
        }
        detail.controls.push(fullyRendered("nextPhaseButton"), fullyRendered("nextTurnButton"))
        if (eliminatedSeat >= 0) {
            require(gameTable.seatData(eliminatedSeat).eliminated === true,
                "Released manual seat has no authoritative elimination")
            detail.eliminatedStatus = fullyRendered("battlefieldSeatStatus" + eliminatedSeat)
            require(detail.eliminatedStatus.text === qsTranslate("HexproofDynamic", "Eliminated"),
                "Eliminated battlefield does not show its explicit localized status")
            const items = auditProbe.observe(auditWindow).items
            detail.hiddenOrdinaryIndicators = ["playerTurnCount", "activeTurnBadge", "responseStatusBadge",
                "battlefieldPlayerSummary"].map(prefix => {
                    const item = items.find(value => value.objectName === prefix + eliminatedSeat)
                    require(item && !item.visible, "Eliminated seat still shows " + prefix)
                    return {objectName:item.objectName, visible:item.visible}
                })
        }
        presentationChecks.push(detail)
        require(auditProbe.record("manual-ui-" + label, detail), "Cannot record manual presentation")
    }
    function verifyReconnectPresentation() {
        const items = auditProbe.observe(auditWindow).items
        const overlays = items.filter(value => value.objectName === "tableReconnectOverlay" && value.visible)
        const banners = items.filter(value => value.objectName === "applicationReconnectBanner")
        require(overlays.length === 1 && overlays[0].inViewport,
            "Manual table must show one full recovery overlay")
        require(banners.length === 1 && !banners[0].visible,
            "Application reconnect banner duplicates the table recovery overlay")
        const detail = {label:"reconnecting", seat:ownSeat, remaining:ws.reconnectSecondsRemaining,
            overlay:overlays[0], applicationBanner:banners[0], countdown:fullyRendered("tableReconnectCountdown")}
        require(detail.countdown.text.length > 0, "Recovery countdown/status is empty")
        if (detail.remaining > 0) {
            const time = Math.floor(detail.remaining / 60) + ":" + String(detail.remaining % 60).padStart(2, "0")
            require(detail.countdown.text.includes(time), "Recovery countdown differs from live transport timer")
        }
        presentationChecks.push(detail)
        require(auditProbe.record("manual-ui-reconnecting", detail), "Cannot record recovery presentation")
    }
    function finish(error) {
        clock.enabled = false
        if (error) capture("failure")
        const geometry = auditProbe.observe(auditWindow)
        require(auditProbe.record("window-geometry", geometry), "Cannot record geometry")
        auditProbe.record("result", {status:error ? "failed" : "passed", error:error || "",
            scenario:"manual-edh-recovery", evidence:auditProbe.environment("HEXPROOF_AUDIT_OS_INPUT_HELPER") ? "system-input" : "native-qt-input",
            roomAndDeckSetup:"cached-decks-fixture/native-room-controls", gameActions:"production-controls",
            completedGame:false, participants:participants, actor:actor, seat:ownSeat,
            originalOrder:order, departedSeat:departedSeat, remainingOrder:remainingOrder,
            requestedDepartureKind:startingDeparture ? "starting-seat" : "nonstarting-seat",
            departureKind:departedStartingPlayer ? "starting-seat" : "nonstarting-seat",
            departedStartingPlayer:departedStartingPlayer, departureCoverageGap:departureCoverageGap,
            hostBefore:hostBefore, hostAfter:hostAfter >= 0 ? hostAfter : shared("remaining-host").seat,
            roleBefore:roleBefore, roleAtFinish:ws.roomSession.role,
            authenticatedSeatAtFinish:ws.roomSession.seatIndex,
            authenticatedResume:sawDisconnect, restartEvents:restarts, checks:checks,
            renderedBattlefieldChecks:layoutChecks,
            manualPresentationChecks:presentationChecks,
            actualEndPhaseSelection:{selectedByOwnSeat:phaseNavigationConfirmed,
                confirmation:shared("end-phase-selected")},
            openingOrderDiscriminatesNumericCycle:order.length > 0 && !numericCycleEquivalent(order),
            layoutCoverageGap:order.length > 0 && numericCycleEquivalent(order)
                ? "The naturally rolled opening order is a rotation of numeric seat order; this run cannot distinguish the opening ordering regression." : "",
            requiredScreenshots:screenshots, windowMode:geometry.windowMode,
            width:geometry.width, height:geometry.height, dpr:geometry.dpr, screenGeometry:geometry.screenGeometry})
        auditProbe.finish(error ? 1 : 0)
    }
    function selectFormat() {
        if (!comboOpened) {
            if (!click("roomNameField")) return false
            require(auditProbe.type("Native EDH recovery"), "Cannot type room name")
            if (!click("roomFormatSelector")) return false
            comboOpened = true
            return false
        }
        const options = auditWindow.stack.currentItem.selectableFormatOptions
        const index = options.findIndex(value => value.value === "commander")
        require(index >= 0, "Commander format absent")
        key(Qt.Key_Home)
        for (let i = 0; i < index; ++i) key(Qt.Key_Down)
        key(Qt.Key_Return)
        return true
    }
    function tick() {
        require([3,4].includes(participants), "Recovery requires three or four player clients")
        require(["edh-starter", "edh-nonstarter"].includes(departureVariant), "Unsupported manual departure variant")
        require(Date.now() - entered < 60000, "Timed out at step " + step)
        if (auditWindow.stack.busy) return
        const room = ws.roomSession, game = ws.gameSession
        switch (step) {
        case 0:
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"])
                if (find(name)) { click(name); return }
            if (click("mainMenuConnectButton")) next("Open connection form")
            return
        case 1:
            if (click("connectSubmitButton")) next("Connect to isolated loopback hub")
            return
        case 2:
            if (!ws.connected) return
            if (click(actor === 1 ? "mainMenuCreateRoomButton" : "mainMenuJoinRoomButton")) next("Open room form")
            return
        case 3:
            if (actor === 1) {
                if (selectFormat()) next("Choose manual Commander BO1")
            } else if (shared("room").code && click("joinRoomCodeField")) {
                require(auditProbe.type(shared("room").code), "Cannot type room code")
                next("Enter shared room code")
            }
            return
        case 4:
            if (click(actor === 1 ? "createRoomSubmitButton" : "joinRoomSubmitButton")) next("Submit room form")
            else if (actor === 1 && find("createRoomBody"))
                require(auditProbe.wheel(find("createRoomBody"), -360), "Cannot scroll room form")
            return
        case 5:
            if (!ws.inRoom) return
            require(room.rulesMode === "manual" && room.format === "edh" && room.deckFormat === "commander", "Unexpected room mode")
            require(room.matchMode === "bo1", "EDH offered a multi-game series")
            ownSeat = room.seatIndex
            roleBefore = room.role
            if (actor === 1) require(auditProbe.share("room", {code:room.roomId}), "Cannot share room")
            if (click("waitingRoomSelectDeckButton")) next("Open cached deck picker")
            return
        case 6:
            if (click("selectMatchDeckButton")) next("Select cached Commander deck")
            return
        case 7:
            if (!room.selectedDeckName) return
            mark("seat", {seat:ownSeat})
            if (!all("seat", true)) return
            require(room.seats.filter(value => value.occupied).length === participants, "Unexpected occupied player count")
            if (click("playerReadyButton")) next("All occupied players Ready")
            return
        case 8:
            if (!gameTable.hasSnapshot || !gameTable.zoneModel(room.seatIndex, "hand")
                || !find("increaseLifeButton" + ownSeat)) return
            order = Array.from(game.turnOrder)
            require(order.length === participants && new Set(order).size === participants, "Incomplete turn order")
            require(order[0] === game.startingSeat && game.activeSeat === order[0], "Opening starter/order differ")
            require(hand().length === 7, "Opening hand is not seven")
            for (const value of order) require(gameTable.seatData(value).life === 40, "Incorrect EDH opening life")
            privacy()
            if (!verifyRenderedBattlefields("opening", order)) return
            verifyManualPresentation("opening", -1)
            const hosts = room.seats.map((value, seat) => ({seat:seat, occupied:value.occupied, host:value.host}))
                .filter(value => value.occupied && value.host)
            require(hosts.length === 1, "Opening room must have exactly one occupied host")
            hostBefore = hosts[0].seat
            departedSeat = order[startingDeparture ? 0 : 1]
            if (departedSeat === hostBefore) {
                // Intentional host leave disbands the room. Keep the naturally
                // rolled order and exercise another genuine non-host departure;
                // report the missing starter branch instead of redefining it.
                departedSeat = order.find(value => value !== hostBefore
                    && (startingDeparture || value !== order[0]))
                if (startingDeparture)
                    departureCoverageGap = "Rolled starter is host; intentional host leave disbands. This run covers nonstarting non-host departure instead."
            }
            departedStartingPlayer = departedSeat === order[0]
            remainingOrder = order.filter(value => value !== departedSeat)
            capture("01-edh-opening")
            auditProbe.record("opening", privateState())
            auditProbe.record("departure-plan", {variant:departureVariant, requestedStartingDeparture:startingDeparture,
                departedStartingPlayer:departedStartingPlayer, departedSeat:departedSeat,
                hostBefore:hostBefore, role:roleBefore, coverageGap:departureCoverageGap})
            mark("opened", {order:order})
            next("Opening layout, rolled cyclic order and private projection")
            return
        case 9:
            if (!all("opened", true)) return
            for (const value of actors(true))
                require(JSON.stringify(shared("opened-" + value).order) === JSON.stringify(order), "Peers disagree on opening order")
            if (actor > 1 && !shared("life-" + (actor - 1)).ready) return
            if (gameTable.seatData(ownSeat).life === 41) { mark("life"); next("Set public life marker for restart reset"); return }
            click("increaseLifeButton" + ownSeat)
            return
        case 10: {
            if (!all("life", true)) return
            if (turnIndex >= participants) { next("One complete cyclic round through every player"); return }
            const before = order[turnIndex], after = order[(turnIndex + 1) % order.length]
            const published = shared("turn-" + turnIndex)
            if (!published.ready && ownSeat === before) {
                if (turnIndex === 0 && !phaseNavigationConfirmed) {
                    if (!phaseNavigationSubmitted) {
                        const selector = find("compactPhaseSelector")
                        if (selector) {
                            if (!phaseSelectorOpened) {
                                if (click("compactPhaseSelector")) phaseSelectorOpened = true
                                return
                            }
                            key(Qt.Key_End); key(Qt.Key_Return)
                            phaseNavigationSubmitted = true
                        } else if (click("phaseButton10")) phaseNavigationSubmitted = true
                        return
                    }
                    if (game.currentPhase !== "end") return
                    verifyManualPresentation("end-phase-selected", -1)
                    capture("01b-end-phase-navigation")
                    phaseNavigationConfirmed = true
                    require(auditProbe.share("end-phase-selected", {ready:true, seat:ownSeat, phase:game.currentPhase}),
                        "Cannot record actual End phase selection")
                    return
                }
                if (!turnSubmitted) { if (click("nextTurnButton")) turnSubmitted = true; return }
                if (game.activeSeat !== after) return
                require(auditProbe.share("turn-" + turnIndex, {ready:true, before:before, after:after}), "Cannot share turn")
                return
            }
            if (!published.ready) return
            if (!shared("turn-seen-" + turnIndex + "-" + actor).ready) {
                if (game.activeSeat !== after) return
                require(game.currentPhase === "untap", "Turn did not reset phase")
                require(hand().length === 7, "Turn advancement drew a card automatically")
                mark("turn-seen-" + turnIndex)
            }
            if (!all("turn-seen-" + turnIndex, true)) return
            turnIndex++; turnSubmitted = false
            return
        }
        case 11:
            if (ownSeat === departedSeat) {
                key(Qt.Key_W, Qt.ControlModifier | Qt.ShiftModifier)
                next("Open intentional departure confirmation")
            } else next("Wait for starting/nonstarting seat departure")
            return
        case 12:
            if (ownSeat === departedSeat) {
                if (!click("confirmButton")) return
            }
            next("Confirm intentional room leave")
            return
        case 13:
            if (ownSeat === departedSeat) {
                if (ws.inRoom) return
                capture("02-departed-main-menu"); mark("departed")
                next("Released player returns to menu")
            } else {
                if (room.seats[departedSeat].occupied || !actors(true).some(value => shared("departed-" + value).ready)) return
                require(!game.finished, "Partial EDH departure ended the match")
                require(!gameTable.seatData(ownSeat).eliminated, "Remaining seat was eliminated")
                require(game.activeSeat !== departedSeat, "Turn remained on released seat")
                const hosts = room.seats.map((value, seat) => ({seat:seat, occupied:value.occupied, host:value.host}))
                    .filter(value => value.occupied && value.host)
                require(hosts.length === 1 && hosts[0].seat === hostBefore, "Non-host departure changed or duplicated host authority")
                hostAfter = hosts[0].seat
                if (!gameTable.seatData(departedSeat).eliminated) return
                if (!verifyRenderedBattlefields("after-departure", order)) return
                verifyManualPresentation("after-departure", departedSeat)
                require(room.role === "player" && room.seatIndex === ownSeat, "Remaining membership changed")
                auditProbe.share("remaining-host", {seat:hostAfter})
                auditProbe.record("departure-host-status", {hostBefore:hostBefore, hostAfter:hostAfter,
                    role:room.role, seat:room.seatIndex, host:room.host,
                    occupiedSeats:room.seats.map((value, seat) => ({seat:seat, occupied:value.occupied, host:value.host}))})
                capture("02-after-departure"); mark("departure-seen", {seat:ownSeat, role:room.role, host:room.host})
                next("Remaining players continue; released active seat skipped")
            }
            return
        case 14:
            if (ownSeat === departedSeat) {
                if (all("resumed", false)) finish("")
                return
            }
            if (!all("departure-seen", false)) return
            const survivingHosts = actors(false).map(value => shared("departure-seen-" + value)).filter(value => value.host)
            require(survivingHosts.length === 1 && survivingHosts[0].seat === hostAfter,
                "Remaining authenticated clients disagree on unique host")
            if (room.host) {
                key(Qt.Key_R, Qt.ControlModifier | Qt.ShiftModifier)
                next("Surviving room host opens restart confirmation")
            } else next("Wait for surviving host restart")
            return
        case 15:
            if (room.host && !click("confirmButton")) return
            next("Confirm restart of same game")
            return
        case 16:
            if (restarts === 0) return
            require(game.gameNumber === 1 && !game.finished && !game.sideboarding, "Restart changed match lifecycle")
            require(JSON.stringify(game.turnOrder) === JSON.stringify(remainingOrder), "Restart changed remaining relative order")
            require(game.startingSeat === remainingOrder[0] && game.activeSeat === remainingOrder[0], "Restart starter did not advance to occupied successor")
            for (const value of remainingOrder)
                require(gameTable.seatData(value).life === 40 && !gameTable.seatData(value).eliminated, "Restart did not reset active participant")
            require(hand().length === 7, "Restart did not restore seven-card opening hand")
            privacy()
            if (!verifyRenderedBattlefields("restarted", remainingOrder)) return
            verifyManualPresentation("restarted", -1)
            capture("03-restarted-remaining-players")
            auditProbe.record("restarted", privateState()); mark("restarted")
            next("Same-game restart resets life and keeps surviving cyclic order")
            return
        case 17:
            if (!all("restarted", false)) return
            for (const value of actors(false)) {
                if (value >= actor) break
                if (!shared("resumed-" + value).ready) return
            }
            key(Qt.Key_D, Qt.ControlModifier | Qt.AltModifier)
            next("Draw one physical card before transport recovery")
            return
        case 18:
            if (hand().length !== 8) return
            privacy(); resumeBefore = privateState()
            auditProbe.record("before-reconnect", resumeBefore)
            require(auditProbe.interruptTransport(ws), "Cannot interrupt owned loopback transport")
            next("Interrupt loopback transport without releasing membership")
            return
        case 19:
            if (ws.reconnecting || !ws.connected) {
                if (!sawDisconnect) {
                    verifyReconnectPresentation()
                    capture("04-reconnecting"); sawDisconnect = true
                }
                return
            }
            if (!sawDisconnect || !ws.inRoom || !gameTable.hasSnapshot || !find("increaseLifeButton" + ownSeat)) return
            require(JSON.stringify(privateState()) === JSON.stringify(resumeBefore), "Authenticated recovery changed exact private/public state")
            privacy()
            if (!verifyRenderedBattlefields("resumed", remainingOrder)) return
            verifyManualPresentation("resumed", -1)
            capture("05-resumed-private-hand")
            auditProbe.record("after-reconnect", privateState()); mark("resumed")
            next("Authenticated recovery restores same seat, host, exact physical hand and turn state")
            return
        case 20:
            if (all("resumed", false)) finish("")
            return
        }
    }
    Component.onCompleted: auditProbe.fixture("cached-local-decks", {description:"Only saved decks/art are preloaded; all room/game actions use native input."})
    Connections {
        target: ws
        function onGameRestarted() { driver.restarts++ }
    }
    Connections {
        id: clock
        target: auditProbe
        function onStepRequested() {
            if (driver.busy) return
            driver.busy = true
            try { driver.require(auditProbe.beginInput(), "Cannot acquire native input"); driver.tick() }
            catch (error) { driver.finish(String(error)) }
            finally { auditProbe.endInput(); driver.busy = false }
        }
    }
}
