// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import "ForgeStackStudy.js" as StackStudy
import "ForgeBorosStudy.js" as BorosStudy
import "ForgeCardChoiceStudy.js" as CardChoiceStudy
import "ForgePauperStudy.js" as PauperStudy
import "ForgeEldraziStudy.js" as EldraziStudy
import "ForgeTournamentStudy.js" as TournamentStudy
import "ForgeMigrationStudy.js" as MigrationStudy
import "ForgePeerStudy.js" as PeerStudy

// Room/deck setup is recorded fixture preparation. Every rules decision is
// delivered through production controls in the two exposed native windows.
Item {
    id: driver
    property int seat: Number(auditProbe.environment("HEXPROOF_AUDIT_SEAT"))
    property string variant: auditProbe.environment("HEXPROOF_AUDIT_VARIANT") || "modern"
    readonly property bool playerHosted: auditProbe.environment("HEXPROOF_AUDIT_PLAYER_HOSTED") === "1"
    readonly property bool migrationAudit: ["1", "loss"].includes(auditProbe.environment("HEXPROOF_AUDIT_MIGRATION"))
    readonly property bool peerAudit: auditProbe.environment("HEXPROOF_AUDIT_PEER") === "1"
    readonly property string peerExpected: auditProbe.environment("HEXPROOF_AUDIT_PEER_EXPECTED") || "direct"
    property bool peerConnectingObserved: false
    property int peerStep: 0
    property bool peerDone: false
    property double peerStartedAt: 0
    property int migrationStep: 0
    property bool migrationDone: false
    property bool checkedBackup: false
    readonly property bool spectator: seat > 2
    property bool checkedRuntime: false
    readonly property bool recoveryAudit: variant === "recovery"
    property int recoveryStep: 0
    property bool capturedPause: false
    property bool capturedAbort: false
    readonly property string format: variant.startsWith("duel") ? "duel" : "modern"
    readonly property bool extended: variant.endsWith("-bo3")
    readonly property bool stackStudy: variant === "stack"
    readonly property bool borosStudy: variant === "boros" || variant === "boros-zones"
    readonly property bool cardChoiceStudy: variant === "boros-zones"
    readonly property bool pauperStudy: variant === "pauper"
    readonly property bool eldraziStudy: variant === "eldrazi"
    readonly property bool tournamentStudy: variant === "affinity" || variant === "duel-phelia"
    readonly property string deckFormat: pauperStudy ? "pauper" : format
    property var stackObserved: ({})
    property var stackReview: null
    property int stage: -2
    property bool busy: false
    property double progress: Date.now()
    property int promptId: -1
    property int decisions: 0
    property int attacks: 0
    property int casts: 0
    property int lands: 0
    property int payments: 0
    property bool capturedStack: false
    property bool capturedCombat: false
    property var seenKinds: ({})
    property int blocks: 0
    property int damageDecisions: 0
    property int commanderReturns: 0
    property int commanderStays: 0
    property int maximumTax: 0
    property int completedGames: 0
    property string previousGame: ""
    property double observedSnapshot: -1
    property int expectedStarter: -1
    property bool liveResumed: false
    property bool sideboardResumed: false
    property bool resultResumed: false
    property bool sawDisconnect: false
    property bool privateChoiceResumed: false
    property var resumeState: ({})
    property int boardMoveStage: 0
    property string blockedPrompt: ""
    readonly property var session: ws.rulesSession
    readonly property var table: auditWindow ? auditWindow.stack.currentItem : null

    function require(ok, message) { if (!ok) throw new Error(message + "; " + auditProbe.lastError) }
    function item(name) { return auditProbe.find(auditWindow, name) }
    function click(name) {
        const target = item(name)
        if (!target) return false
        require(auditProbe.click(target), "Input failed: " + name)
        progress = Date.now()
        return true
    }
    function capture(name) { require(auditProbe.capture(auditWindow, name), "Capture failed") }
    function deck() {
        if (tournamentStudy) return TournamentStudy.deck(driver)
        if (eldraziStudy) return BorosStudy.deck(driver)
        if (pauperStudy) return PauperStudy.deck(seat)
        if (borosStudy) return BorosStudy.deck(driver)
        if (stackStudy) return StackStudy.deck(seat)
        if (format === "duel") {
            return {name:"Native Duel Commander", format:"duel", deckFormat:"duel",
                commanders:["Isamaru, Hound of Konda"], mainboard:[
                    {name:"Plains", count:99, setCode:"C15", collectorNumber:"323", typeLine:"Basic Land — Plains"},
                    {name:"Isamaru, Hound of Konda", count:1, setCode:"CHK", collectorNumber:"19", typeLine:"Legendary Creature — Dog"}],
                sideboard:[]}
        }
        if (extended && seat === 1) {
            const creatures = [["Garruk's Companion", "M11", "176"], ["Centaur Courser", "M10", "172"],
                ["Rumbling Baloth", "M14", "193"], ["Colossal Dreadmaw", "XLN", "180"], ["Duskdale Wurm", "EVE", "67"]]
            return {name:"Native trample combat", format:"modern", deckFormat:"modern",
                mainboard:[{name:"Forest", count:40, setCode:"LEA", collectorNumber:"294", typeLine:"Basic Land — Forest"}]
                    .concat(creatures.map(card => ({name:card[0], count:4, setCode:card[1], collectorNumber:card[2], typeLine:"Creature"}))),
                sideboard:[{name:"Grizzly Bears", count:1, setCode:"LEA", collectorNumber:"199", typeLine:"Creature — Bear"}]}
        }
        // Exact paper printings verified in the local catalog, also supported
        // by the pinned Forge resource set. The room protocol requires them.
        const mainboard = [{name:"Plains", count:40, setCode:"C15", collectorNumber:"323", typeLine:"Basic Land — Plains"}]
        for (const printing of [["Silvercoat Lion", "M13", "35"], ["Youthful Knight", "10E", "62"],
            ["Glory Seeker", "ROE", "22"], ["Oreskos Swiftclaw", "M15", "22"], ["Traveling Philosopher", "THS", "34"]])
            mainboard.push({name:printing[0], count:4, setCode:printing[1], collectorNumber:printing[2], typeLine:"Creature"})
        return {name:"Native Forge creatures", format:"modern", deckFormat:"modern", mainboard:mainboard, sideboard:[]}
    }
    function state() {
        return {stage:stage, seat:seat, format:format, deckFormat:deckFormat, gameId:session.gameId, turn:session.turn, step:session.step,
            promptId:session.promptId, promptKind:session.promptKind, promptPending:session.promptPending,
            rulesResponsePending:ws.rulesResponsePending, roomConnected:table ? table.roomConnected : false,
            options:session.promptOptionItems(), title:session.promptTitle, detail:session.promptDetail,
            realDeckReview:borosStudy ? BorosStudy.snapshot(driver) : null,
            eldraziReview:eldraziStudy ? EldraziStudy.state() : null,
            tournamentReview:tournamentStudy ? TournamentStudy.state() : null,
            cardChoiceReview:cardChoiceStudy ? CardChoiceStudy.state() : null,
            commander:commander(), error:ws.lastError, decisions:decisions, lands:lands,
            casts:casts, attacks:attacks, payments:payments, kinds:Object.keys(seenKinds),
            winnerSeat:session.winnerSeat, gameOver:session.gameOver,
            result:ws.gameSession.result, roomPhase:ws.roomSession.phase, stackObserved:stackObserved, migrationDone:migrationDone, peerDone:peerDone, directPeerDecisions:ws.directPeerDecisions, peerFallbacks:ws.peerFallbacks, peerTransport:ws.peerTransportState, peerMetrics:ws.peerTransportMetrics}
    }
    function extendedState() {
        return {blocks:blocks, damageDecisions:damageDecisions, commanderReturns:commanderReturns,
            commanderStays:commanderStays, maximumTax:maximumTax, completedGames:completedGames,
            liveResumed:liveResumed, sideboardResumed:sideboardResumed, resultResumed:resultResumed,
            privateChoiceResumed:privateChoiceResumed,
            sideboardMoves:boardMoveStage, score:ws.gameSession.score}
    }
    function commander() {
        // Read the actual typed delegate even when an inspection overlay covers
        // it. Input selectors intentionally reject covered targets.
        const panel = table && table.presentation ? table.presentation.children.find(child =>
            child.objectName === "forgeCommanders-" + ws.roomSession.seatIndex) : null
        return panel && panel.commanders.length ? panel.commanders[0] : null
    }
    function interrupt(where) {
        resumeState = {where:where, gameId:session.gameId, promptId:session.promptId,
            hand:session.zoneCount(ws.roomSession.seatIndex, "hand"), sideboard:ws.gameSession.sideboard,
            score:ws.gameSession.score}
        auditProbe.record("before-reconnect-" + where, resumeState)
        require(auditProbe.interruptTransport(ws), "Cannot interrupt test transport")
        stage = 50; sawDisconnect = false; progress = Date.now()
    }
    function extendedTick() {
        const ownCommander = commander()
        if (ownCommander) maximumTax = Math.max(maximumTax, ownCommander.tax)
        if (session.gameId !== previousGame && previousGame.length > 0) {
            // The new rules snapshot precedes its match metadata on the wire.
            if (ws.gameSession.sideboarding || ws.gameSession.gameNumber <= completedGames) return true
            require(ws.gameSession.startingSeat === expectedStarter, "Next game did not give the loser the first turn")
            require(Object.keys(table.combatInteraction.assignments).length === 0, "Old combat selection survived the next game")
            auditProbe.record("next-game-" + ws.gameSession.gameNumber, state())
            previousGame = ""; promptId = -1
        }
        if (!liveResumed && session.promptPending && ["chooseAttackers", "chooseBlockers"].includes(session.promptKind)) {
            interrupt("live"); return true
        }
        if (ws.gameSession.sideboarding) {
            if (previousGame !== session.gameId) {
                previousGame = session.gameId; expectedStarter = 1 - session.winnerSeat; completedGames++
                capture("sideboard-" + completedGames)
            }
            if (format === "modern" && seat === 1 && boardMoveStage < 4) {
                const data = ws.gameSession.sideboard
                if (boardMoveStage === 0 || boardMoveStage === 2) {
                    const from = boardMoveStage === 0 ? "sideboard" : "mainboard"
                    const to = boardMoveStage === 0 ? "mainboard" : "sideboard"
                    const source = item("sideboardCard-" + from + "-0")
                    const target = item("sideboardZone-" + to)
                    if (source && target) { require(auditProbe.drag(source, target), "Sideboard card drag failed"); boardMoveStage++ }
                    return true
                }
                const count = data.seats[0].sideboardCount
                if ((boardMoveStage === 1 && count === 0) || (boardMoveStage === 3 && count === 1)) boardMoveStage++
                return true
            }
            if (!sideboardResumed) { interrupt("sideboard"); return true }
            if (!ws.gameSession.sideboard.seats.find(value => value.seat === ws.roomSession.seatIndex).ready)
                click("sideboardReadyButton")
            return true
        }
        if (session.gameOver && ws.gameSession.result.matchFinished && !resultResumed) {
            interrupt("result"); return true
        }
        return false
    }
    function wheelToCard(id, hand) {
        // Resolve the card's actual lane, including offscreen lands and other
        // permanents. Reading geometry guides input; never move the view by
        // assigning contentX/contentY or invoking its reveal helper.
        for (const lane of table.presentation.children) {
            if (!lane.visibleCards || !lane.scrollArea) continue
            const card = lane.visibleCards.find(value => value.cardId === id)
            if (!card) continue
            const view = lane.scrollArea
            const horizontal = lane.category === undefined
            const before = horizontal ? card.x < view.contentX : card.y < view.contentY
            require(auditProbe.wheel(view, before ? 160 : -160), "Cannot reach card " + id)
            return false
        }
        return false
    }
    function cardAction(option) {
        if (table.cardActionPicker.opened)
            return click("rulesCardAction-" + option.responseId)
        const hand = item("forgeHandCard-" + option.cardId)
        const board = hand ? null : item("forgeCard-" + option.cardId)
        if (hand || board) {
            require(auditProbe.click(hand || board), "Cannot activate native card action")
            progress = Date.now()
            return true
        }
        const commanderControl = format === "duel" ? item("forgeCommander-" + ws.roomSession.seatIndex + "-0") : null
        if (commanderControl && commanderControl.objectId === option.cardId && commanderControl.actionable) {
            require(auditProbe.click(commanderControl), "Cannot activate commander action")
            progress = Date.now(); return true
        }
        if (click("rulesZoneAction-" + option.responseId)) return true
        if (click("rulesPromptOption-" + option.responseId)) return true
        return wheelToCard(option.cardId, true)
    }
    function availableMana() {
        let available = 0
        for (const laneName of ["forgeOwnLands", "forgeOwnOther"]) {
            const lane = item(laneName)
            if (lane) for (const card of lane.visibleCards) if (["Plains", "Forest", "Mountain", "Island"].includes(card.name) && !card.tapped) available++
        }
        return available
    }
    function observePublicTable() {
        if (table.priorityInputBlocked) return
        if (session.stackObjectIds().length > 0 && !capturedStack) {
            capture("stack"); capturedStack = true
        }
        // A defending player may have no creatures or priority decision. Its
        // real combat evidence is the opponent's declared, visible attacker.
        if (!capturedCombat) for (const lane of table.presentation.children) {
            if (!lane.visibleCards || !lane.scrollArea || lane.category === undefined) continue
            const view = lane.scrollArea
            if (lane.visibleCards.some(card => card.attacking && card.y >= view.contentY
                && card.y + card.height <= view.contentY + view.height)) {
                capture("combat"); capturedCombat = true; break
            }
        }
    }
    function act() {
        if (!session.promptPending || ws.rulesResponsePending || !session.promptSupported
            || (table.priorityInputBlocked && !table.presentation.decisionDialogActive)) return
        if (session.promptId !== promptId) {
            promptId = session.promptId; decisions++; progress = Date.now()
            seenKinds[session.promptKind] = true
            auditProbe.record("prompt-" + decisions, state())
        }
        const options = session.promptOptionItems()
        if (pauperStudy) PauperStudy.observe(driver)
        if (cardChoiceStudy && CardChoiceStudy.act(driver)) return
        if (eldraziStudy && EldraziStudy.act(driver)) return
        if (tournamentStudy && TournamentStudy.act(driver)) return
        if (borosStudy && BorosStudy.act(driver, cardChoiceStudy ? CardChoiceStudy.actionOptions(driver) : null)) return
        switch (session.promptKind) {
        case "diceRolled": click("rulesPromptOption-$ack"); return
        case "revealCards": click("acknowledgeRevealButton"); return
        case "scry":
            require(pauperStudy, "Unexpected scry in the selected fixture")
            PauperStudy.scry(driver); return
        case "mulligan": click("rulesPromptOption-$keep"); return
        case "chooseBoolean": case "chooseFromSelection": {
            if (pauperStudy) { BorosStudy.chooseScalar(driver); return }
            const list = item("rulesScalarCandidates")
            const ownCommander = extended && format === "duel" ? commander() : null
            const destination = ownCommander && (session.promptTitle + " " + session.promptDetail).toLowerCase().includes("command")
            const stay = destination && ownCommander.casts >= 3 && seat === 1
            const choice = list ? list.itemAtIndex(destination && !stay ? 1 : 0) : null
            if (session.promptKind === "chooseFromSelection" && choice && choice.count > 0
                && click("rulesConfirmChoices")) return
            if (destination) capture("commander-destination")
            if (choice && click("rulesScalarChoice-" + choice.responseId) && destination) {
                if (stay) commanderStays++; else commanderReturns++
            }
            return
        }
        case "chooseAction": {
            if ((stackStudy || pauperStudy) && !table.priority.fullControl) {
                if (!item("forgeGameDrawer").visible) click("forgeGameMenu")
                click("rulesFullControl")
                click("forgeGameMenu")
                return
            }
            if (stackStudy && StackStudy.observe(driver)) return
            const land = options.find(option => option.kind === "playLand")
            if (land) { if (cardAction(land)) lands++; return }
            // Fixture costs guide choices; native Forge still validates payment.
            const mana = availableMana()
            const costs = {"Garruk's Companion":2, "Centaur Courser":3, "Rumbling Baloth":4, "Colossal Dreadmaw":6, "Duskdale Wurm":7, "Grizzly Bears":2}
            const spell = options.find(option => {
                if (option.kind !== "cast") return false
                const card = session.cardForInspection(option.cardId)
                if ((stackStudy || pauperStudy) && !StackStudy.castAllowed(driver, card.name)) return false
                const command = commander()
                const cost = pauperStudy ? PauperStudy.cost(card) : stackStudy ? StackStudy.costs[card.name]
                    : format === "duel" ? command ? 1 + command.tax : Infinity
                    : extended && seat === 1 ? costs[card.name] : 2
                return mana >= cost
            })
            if (spell) {
                if (pauperStudy) PauperStudy.trackCast(driver, spell)
                if (cardAction(spell)) casts++
                return
            }
            click("rulesPromptOption-$pass"); return
        }
        case "payManaCost": {
            for (const id of ["$pay", "$auto-pay"]) {
                if (options.some(option => option.responseId === id)) { if (click("rulesPromptOption-" + id)) payments++; return }
            }
            const mana = options.find(option => option.kind === "activateAbility")
            if (mana) { if (cardAction(mana)) payments++; return }
            throw new Error("No legal payment control in fixture")
        }
        case "chooseAttackers": {
            if (stackStudy && !StackStudy.complete(driver)) { click("rulesConfirmCombat-attackers"); return }
            if (pauperStudy && !PauperStudy.complete()) { click("rulesConfirmCombat-attackers"); return }
            for (const source of session.promptCombat.sourceItems()) {
                if (cardChoiceStudy && !CardChoiceStudy.allowAttack(source.name)) continue
                if (extended && format === "modern" && !(auditProbe.readShared("complex-damage") || {}).done
                    && (seat === 2 || !["Colossal Dreadmaw", "Duskdale Wurm"].includes(source.name))) continue
                if (source.validTargets.length && !table.combatInteraction.selectedTargets(source.responseId).length) {
                    if (table.combatInteraction.selectedSource === source.responseId) {
                        const target = source.validTargets.find(value => value.kind === "player") || source.validTargets[0]
                        if (click(target.kind === "player" ? "rulesPlayerTarget" + target.seat : "forgeCard-" + target.objectId)) attacks++
                    } else if (click("forgeCard-" + source.objectId)) {
                        if (source.validTargets.length === 1) attacks++
                    } else wheelToCard(source.objectId, false)
                    return
                }
            }
            if (!capturedCombat && table.combatInteraction.links.length) { capture("combat"); capturedCombat = true }
            click("rulesConfirmCombat-attackers"); return
        }
        case "chooseBlockers": {
            if (extended) {
                const command = commander()
                const shouldBlock = format === "duel" ? command && command.casts <= 3
                    : seat === 2 && !(auditProbe.readShared("complex-damage") || {}).done
                const sources = session.promptCombat.sourceItems()
                const desired = format === "duel" ? 1 : 2
                if (shouldBlock && sources.length >= desired) {
                    const target = sources[0].validTargets.find(candidate => sources.slice(0, desired)
                        .every(source => source.validTargets.some(value => value.responseId === candidate.responseId)))
                    if (target) for (const source of sources.slice(0, desired)) {
                        if (table.combatInteraction.selectedTargets(source.responseId).includes(target.responseId)) continue
                        if (table.combatInteraction.selectedSource !== source.responseId) click("forgeCard-" + source.objectId)
                        else if (click("forgeCard-" + target.objectId)) blocks++
                        return
                    }
                    if (table.combatInteraction.links.length) {
                        capture("blocking")
                        if (!capturedCombat) { capture("combat"); capturedCombat = true }
                    }
                }
            }
            // Deliberately take damage so the complete-game oracle is bounded.
            // Block assignment interaction has separate real-model GUI tests.
            click("rulesConfirmCombat-blockers"); return
        }
        case "chooseCombatDamageAssignment": {
            const confirm = item("rulesConfirmDamage")
            if (confirm && confirm.enabled) {
                capture("damage")
                if (click("rulesConfirmDamage")) {
                    damageDecisions++
                    auditProbe.share("complex-damage", {done:true})
                }
            } else click("rulesAutoAssignDamage")
            return
        }
        case "chooseDamageAssignmentOrder": case "reorder": click("rulesConfirmOrder"); return
        case "chooseBoardTargets": StackStudy.chooseTarget(driver); return
        case "chooseCards": case "mulliganPutBack": {
            const list = item("rulesCardCandidates")
            const confirm = item("rulesConfirmCards")
            if (confirm && confirm.enabled) { click("rulesConfirmCards"); return }
            if (list) for (let i = 0; i < list.count; ++i) {
                const candidate = list.itemAtIndex(i)
                if (candidate && !candidate.selected) {
                    const visible = item(candidate.objectName)
                    if (visible) { require(auditProbe.click(visible), "Cannot select required card"); return }
                }
            }
            if (list) require(auditProbe.wheel(list, -160), "Cannot scroll required cards")
            return
        }
        default: throw new Error("Unhandled native fixture decision: " + session.promptKind)
        }
    }
    function recoverHostedGame() {
        const fault = auditProbe.readShared("host-fault") || {}
        if (!fault.started || recoveryStep >= 3) return false
        if (ws.lastError) {
            require(ws.lastError.startsWith("player_host_lost:") || ws.lastError.startsWith("rules_unavailable:") || ws.lastError.startsWith("rules_action_rejected:"), "Unexpected failure: " + ws.lastError)
            auditProbe.fixture("acknowledge-host-failure", {code:ws.lastError.split(":")[0]})
            ws.requestRoomList()
        }
        if (ws.roomSession.phase === "started") {
            if (!ws.roomSession.hostConnected && !capturedPause && table && table.hostingPaused === true) {
                require(!table.interaction.canRespond, "Paused game still accepts decisions")
                capture("host-paused"); capturedPause = true
            }
            return true
        }
        require(!session.active && !ws.gameSession.result.matchFinished, "Engine loss invented a match result")
        if (!capturedAbort) { capture("host-aborted"); capturedAbort = true }
        if (seat === 1 && recoveryStep === 0 && !ws.forgeHost.busy) {
            auditProbe.fixture("request-fresh-host-helper")
            ws.preparePlayerHosting(); recoveryStep = 1
        }
        if (!ws.roomSession.hostConnected) return true
        recoveryStep = 3; stage = spectator ? 3 : 2; promptId = -1; progress = Date.now()
        auditProbe.record("host-recovered", {abortedGame:fault.gameId, capturedPause:capturedPause, waitingReset:true})
        return true
    }
    function tick() {
        if (PeerStudy.tick(driver, ws, auditProbe)) return
        if (MigrationStudy.tick(driver, ws, auditProbe)) return
        if (recoveryAudit && recoverHostedGame()) return
        // A real-deck turn can contain many decisions. Spectators observe
        // published snapshots, not private prompts or only turn boundaries.
        if (spectator && session.active && session.snapshotRevision !== observedSnapshot) {
            observedSnapshot = session.snapshotRevision
            progress = Date.now()
        }
        require(!ws.lastError, "Server error: " + ws.lastError)
        require(Date.now() - progress < 75000, "No observable progress for 75 seconds")
        if (auditWindow.stack.busy) return
        if (stage === -2) { if (click("mainMenuConnectButton")) stage = -1; return }
        if (stage === -1) { if (click("connectSubmitButton")) stage = 0; return }
        if (stage === 50) {
            if (ws.reconnecting) {
                if (resumeState.where === "private-choice") {
                    if (table && table.presentation)
                        require(!table.presentation.cardChoiceActive && !table.presentation.decisionDock.expanded,
                            "Disconnected private choice reappeared in the fallback dock")
                    if (!sawDisconnect) capture("private-choice-disconnected")
                }
                sawDisconnect = true; return
            }
            if (!sawDisconnect || !ws.inRoom || !table || !table.presentation
                || table.presentation.objectName !== "forgeDuelTable" || !session.active) return
            require(session.gameId === resumeState.gameId, "Reconnect replaced the engine game")
            require(JSON.stringify(ws.gameSession.score) === JSON.stringify(resumeState.score), "Reconnect changed match score")
            if (resumeState.where === "live" || resumeState.where === "private-choice") {
                if (!session.promptPending) return
                require(session.promptId === resumeState.promptId, "Pending prompt was not restored")
                require(session.zoneCount(ws.roomSession.seatIndex, "hand") === resumeState.hand, "Private hand lost on reconnect")
                if (resumeState.where === "private-choice") {
                    require(table.presentation.cardChoiceActive, "Private choice did not reopen after authenticated resume")
                    privateChoiceResumed = true
                    auditProbe.record("private-choice-resumed", {gameId:session.gameId, promptId:session.promptId})
                } else liveResumed = true
            } else if (resumeState.where === "sideboard") {
                if (!ws.gameSession.sideboarding) return
                require(JSON.stringify(ws.gameSession.sideboard.mainboard) === JSON.stringify(resumeState.sideboard.mainboard), "Sideboard edits lost on reconnect")
                sideboardResumed = true
            } else { if (!ws.gameSession.result.matchFinished) return; resultResumed = true }
            capture("reconnect-" + resumeState.where)
            stage = 4; progress = Date.now(); return
        }
        if (stage === 0) {
            if (!ws.connected) return
            if (seat === 1) {
                require(["modern", "duel", "modern-bo3", "duel-bo3", "stack", "boros", "boros-zones", "pauper", "recovery", "eldrazi", "affinity", "duel-phelia"].includes(variant), "Unsupported test variant")
                if (playerHosted) {
                    require(ws.playerHostingAvailable && !ws.forgeRulesAvailable, "Expected relay-only hub")
                    if (!checkedRuntime) { ws.forgeHost.check(); checkedRuntime = true; return }
                    if (ws.forgeHost.busy) return
                    require(ws.forgeHost.ready, "Prepare the pinned test runtime before this scenario")
                }
                auditProbe.fixture("create-loopback-forge-room", {rulesMode:"forge", format:format})
                ws.createRoom("Native Forge duel", format, deckFormat, true, false, extended ? "bo3" : "bo1", "background", "", false, "forge", playerHosted ? "player" : "server")
                stage = 1
            } else {
                const shared = auditProbe.readShared("forge-room")
                if (shared && shared.id) {
                    auditProbe.fixture("join-loopback-forge-room", {roomId:shared.id})
                    ws.joinRoom(shared.id, spectator, "", playerHosted); stage = 1
                }
            }
            return
        }
        if (stage === 1) {
            if (!ws.inRoom) return
            if (seat === 1) auditProbe.share("forge-room", {id:ws.roomSession.roomId})
            if (spectator) { stage = 3; progress = Date.now(); return }
            const fixtureDeck = deck()
            auditProbe.fixture("select-test-deck", fixtureDeck)
            ws.selectDeck(fixtureDeck); stage = 2; progress = Date.now(); return
        }
        if (stage === 2) {
            if (!ws.roomSession.selectedDeckName || (playerHosted && !ws.roomSession.hostConnected)) return
            if (ws.roomSession.seats.length !== 2 || ws.roomSession.seats.some(value => !value.deckSelected)) return
            auditProbe.fixture("ready-for-real-engine-game")
            ws.setReady(true); stage = 3; progress = Date.now(); return
        }
        if (stage === 3) {
            if (!session.active || !item("forgeDuelTable")) return
            require(ws.roomSession.rulesMode === "forge" && ws.roomSession.maxSeats === 2, "Wrong rules mode or seats")
            require(item("rulesPlayerTarget0").life === 20 && item("rulesPlayerTarget1").life === 20, "Incorrect starting life")
            capture("opening"); stage = 4; progress = Date.now()
            if (spectator) { stage = 60; return }
            if (format === "duel") {
                require(table.zoneCount(ws.roomSession.seatIndex, "command") === 1, "Commander missing from command zone")
                if (click("forgeZone-command")) stage = 31
            }
            return
        }
        if (stage === 60) {
            require(!session.promptPending && session.promptOptionItems().length === 0, "Spectator received private decisions")
            if ((auditProbe.readShared("forge-host-finished") || {}).done) {
                capture("spectator-finished")
                auditProbe.record("result", {status:"passed", scenario:"forge-player-host-spectator", seat:seat, privatePrompts:false,
                    requiredScreenshots:["opening.png", "spectator-finished.png"].concat(recoveryAudit ? ["host-aborted.png"] : [])})
                driverClock.enabled = false; auditProbe.finish(0)
            }
            return
        }
        if (stage === 31) {
            if (!item("forgeZoneCards")) return
            capture("command-zone")
            if (click("forgeCloseZonePopup")) stage = 4
            return
        }
        if (stage === 4) {
            if (recoveryAudit && seat === 1 && recoveryStep === 0 && decisions > 5 && session.promptPending) {
                capture("before-host-crash")
                auditProbe.share("host-fault", {started:true, gameId:session.gameId})
                require(auditProbe.crashHostingHelper(ws), "Cannot inject helper exit")
                return
            }
            observePublicTable()
            if (extended && extendedTick()) return
            if (session.gameOver) {
                // Terminal metadata follows the final rules snapshot on the wire.
                if (!ws.gameSession.result.matchFinished) return
                require(session.hasWinner && session.turn > 1 && decisions > 10 && lands > 0 && casts > 0,
                    "Missing evidence of natural gameplay")
                require(capturedStack && capturedCombat, "Missing stack or combat observation")
                require(ws.gameSession.result.concededSeat === -1, "Fixture must end naturally")
                if (stackStudy) require(StackStudy.complete(driver), "Stack relationship coverage incomplete")
                if (cardChoiceStudy) {
                    require(CardChoiceStudy.complete(), "Real-deck card-choice coverage incomplete")
                    if (seat === 1) require(privateChoiceResumed, "Private choice reconnect was not exercised")
                }
                if (pauperStudy) require(PauperStudy.complete(), "Pauper resolution coverage incomplete")
                if (extended) {
                    require(liveResumed && sideboardResumed && resultResumed && completedGames >= 1, "BO3/reconnect coverage incomplete")
                    if (format === "duel") require(maximumTax >= 6 && commanderReturns >= 2 && (seat !== 1 || commanderStays > 0), "Commander repeat casting/destination coverage incomplete")
                    else require((seat !== 1 || damageDecisions > 0 && boardMoveStage === 4) && (seat !== 2 || blocks >= 2), "Trample/sideboard coverage incomplete")
                    completedGames++
                }
                if (migrationAudit) require(migrationDone, "Host migration GUI was not exercised")
                if (peerAudit) {
                    require(peerDone, "Peer consent/connection UI was not exercised")
                    if (peerExpected === "relay")
                        require(ws.directPeerDecisions === 0 && ws.peerTransportState === "relay",
                            "Blocked direct path did not remain on relay")
                }
                capture("finished")
                auditProbe.record("result", Object.assign({status:"passed", scenario:"forge-duel-match",
                    evidence:"native-qt-input", roomAndDeckSetup:"fixture", gameActions:"production-controls",
                    requiredScreenshots:["opening.png", "stack.png", "combat.png", "finished.png"]
                        .concat(format === "duel" ? ["command-zone.png"] : [])
                        .concat(migrationAudit ? ["migration-completed.png"] : [])
                        .concat(peerAudit ? [peerExpected === "relay" ? "peer-fallback.png" : "peer-connected.png"] : [])
                        .concat(recoveryAudit ? ["host-paused.png", "host-aborted.png"] : [])
                        .concat(cardChoiceStudy && seat === 1 ? ["private-choice-disconnected.png", "reconnect-private-choice.png"] : [])
                        .concat(extended ? ["sideboard-1.png", "reconnect-live.png", "reconnect-sideboard.png", "reconnect-result.png"] : [])}, state(), extendedState()))
                if (seat === 1) auditProbe.share("forge-host-finished", {done:true})
                driverClock.enabled = false; auditProbe.finish(0); return
            }
            act()
        }
    }
    Connections {
        id: driverClock
        target: auditProbe
        function onStepRequested() {
            if (driver.busy) return
            driver.busy = true
            try { driver.tick() }
            catch (error) {
                driverClock.enabled = false
                // A window grab can polish pending layouts; retain the
                // inaccessible control geometry before requesting a frame.
                auditProbe.record("failure-observation", auditProbe.observe(auditWindow))
                driver.capture("failure")
                auditProbe.record("result", Object.assign(driver.state(), {status:"failed", error:String(error)}))
                auditProbe.finish(1)
            } finally { driver.busy = false }
        }
    }
}
