// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

// A complete constructed Swiss event through production controls. The six
// manual BO1 tables end by explicit concession; this is not natural Forge play.
Item {
    id: driver
    readonly property int seat: Number(auditProbe.environment("HEXPROOF_AUDIT_SEAT"))
    readonly property int players: Number(auditProbe.environment("HEXPROOF_AUDIT_PLAYERS"))
    property var steps: []
    property var assertions: []
    property var screenshots: []
    property var rounds: []
    property var opponents: ({})
    property int index: 0
    property bool acted: false
    property bool acknowledged: false
    property bool dispatching: false
    property bool finished: false
    property double entered: Date.now()
    property double disconnectedAt: 0
    property string recoveryState: ""
    property var registeredDeck: ({})
    property var waitingResume: ({})
    property bool waitingSawDisconnect: false
    property bool waitingSawSnapshot: false
    property var waitingConnectionTrace: []
    Connections {
        target: ws
        function onConnectionStateChanged() {
            if (!driver.waitingResume.roomId) return
            driver.waitingConnectionTrace = driver.waitingConnectionTrace.concat([
                {state:Number(ws.connectionState), reconnecting:ws.reconnecting === true,
                 connected:ws.connected === true, elapsedMs:Date.now() - driver.disconnectedAt}])
            if (ws.reconnecting) driver.waitingSawDisconnect = true
        }
    }
    Connections {
        target: ws.roomSession
        function onSnapshotChanged() {
            if (!driver.waitingResume.roomId) return
            driver.waitingConnectionTrace = driver.waitingConnectionTrace.concat([
                {roomSnapshot:true, roomId:ws.roomSession.roomId, role:ws.roomSession.role,
                 seat:ws.roomSession.seatIndex, ownDeckName:ws.roomSession.selectedDeckName,
                 sawDisconnect:driver.waitingSawDisconnect, connected:ws.connected === true,
                 reconnecting:ws.reconnecting === true,
                 elapsedMs:Date.now() - driver.disconnectedAt}])
            // applySnapshot emits before completePendingEntry transitions the
            // connection to InRoom. Latch this fresh, correctly scoped snapshot
            // after the actual disconnect edge; the step's final guard still
            // requires connected, not reconnecting, and the same membership.
            if (driver.waitingSawDisconnect
                    && ws.roomSession.roomId === driver.waitingResume.roomId
                    && ws.roomSession.role === driver.waitingResume.role
                    && ws.roomSession.seatIndex === driver.waitingResume.seat
                    && ws.roomSession.phase === "waiting"
                    && ws.roomSession.selectedDeckName === driver.waitingResume.registeredDeckName)
                driver.waitingSawSnapshot = true
        }
    }

    function require(ok, message) { if (!ok) throw new Error(message + "; " + auditProbe.lastError) }
    // QVariantList entries are live QML property wrappers. Persist plain
    // JSON values so a later round cannot rebind an earlier round's results.
    function detached(value) { return JSON.parse(JSON.stringify(value)) }
    function find(name, scope) { return auditProbe.find(scope || auditWindow, name) }
    function page() { return auditWindow.stack.currentItem }
    function walk(root, predicate) {
        if (!root || !root.visible || !root.enabled) return null
        if (predicate(root)) return root
        for (const child of root.children || []) {
            const value = walk(child, predicate)
            if (value) return value
        }
        return null
    }
    function view(name) { return walk(auditWindow.contentItem, item => item.objectName === name) }
    // Geometry also includes visible disabled actions (for example Ready
    // before the opponent enters). Input lookup keeps its strict usable guard.
    function visibleGeometryItem(name) {
        function visit(node) {
            if (!node || node.visible === false) return null
            if (node.objectName === name) return node
            for (const child of node.children || []) {
                const found = visit(child)
                if (found) return found
            }
            return null
        }
        return visit(auditWindow.contentItem)
    }
    function click(name, scrollName, scope) {
        const scroll = scrollName ? view(scrollName) : null
        if (scroll && scroll.moving) return false
        const target = find(name, scope)
        if (target) { require(auditProbe.click(target), "Cannot click " + name); return true }
        if (scroll) require(auditProbe.wheel(scroll, -360), "Cannot scroll " + scrollName)
        return false
    }
    function clickText(text, scrollName, scope) {
        const scroll = scrollName ? view(scrollName) : null
        if (scroll && scroll.moving) return false
        const target = walk(scope || auditWindow.contentItem, item => item.text === text
            && typeof item.clicked === "function" && auditProbe.canInteract(item))
        if (target) { require(auditProbe.click(target), "Cannot click " + text); return true }
        if (scroll) require(auditProbe.wheel(scroll, -360), "Cannot scroll to " + text)
        return false
    }
    function fill(name, text, scrollName) {
        if (!click(name, scrollName)) return false
        require(auditProbe.key(Qt.Key_A, Qt.ControlModifier) && auditProbe.type(text), "Cannot type " + name)
        require(find(name).text === text, "Native text input differs in " + name)
        return true
    }
    function combo(name, option, scrollName) {
        if (!click(name, scrollName)) return false
        require(option >= 0 && auditProbe.key(Qt.Key_Home), "Cannot select first option")
        for (let value = 0; value < option; ++value)
            require(auditProbe.key(Qt.Key_Down), "Cannot select option")
        require(auditProbe.key(Qt.Key_Return), "Cannot confirm option")
        return true
    }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        screenshots.push(name + ".png")
    }
    function share(name, value) { require(auditProbe.share(name, value), "Cannot share " + name) }
    function read(name) { return auditProbe.readShared(name) || ({}) }
    function add(name, actor, action, check, timeout) {
        steps.push({name:name, actor:actor, action:action, check:check || (() => true), timeout:timeout || 45000})
    }
    function pairing() {
        return Array.from(tournament.pairings).find(value => value.playerAId === tournament.participantId
            || value.playerBId === tournament.participantId)
    }
    function pairingRow() {
        const own = pairing()
        return own ? walk(auditWindow.contentItem, item => item.ownPairing !== undefined
            && item.modelData && item.modelData.pairingId === own.pairingId) : null
    }
    function enterPairingMatch() {
        const row = pairingRow()
        if (!row) return false
        // Use the current production label. Missing roomId is an
        // optional projection field and is not a reliable UI-label oracle.
        const button = walk(row, item => (item.text === "Open match" || item.text === "Return to match")
            && typeof item.clicked === "function" && auditProbe.canInteract(item))
        if (button) {
            require(auditProbe.click(button), "Cannot enter the current pairing match")
            return true
        }
        const scroll = view("tournamentPairingList")
        if (scroll && !scroll.moving && !scroll.atYEnd)
            require(auditProbe.wheel(scroll, -360), "Cannot reveal the current pairing")
        return false
    }
    function ownSeat() { return ws.roomSession.seatIndex }
    function ownHand() { return gameTable.zoneModel(ownSeat(), "hand") }
    function ownDeckSelected() {
        const room = ws.roomSession
        const seatIndex = ownSeat()
        return ws.inRoom && seatIndex >= 0 && seatIndex < room.seats.length
            && room.seats[seatIndex].deckSelected === true
    }
    function firstRoundDeckSelected() {
        return ownDeckSelected() && registeredDeck.name
            && ws.roomSession.selectedDeckName === registeredDeck.name
    }
    function selectDeck() {
        const options = deckLibrary.matchDecks("modern")
        const readyIndex = options.findIndex(value => value.ready)
        const ready = options[readyIndex]
        require(ready, "The isolated fixture needs a selectable saved Modern deck with cached art")
        const row = auditProbe.find(auditWindow, "matchDeckOption" + readyIndex, {"modelData.deckName":ready.deckName})
        const button = row && find("selectMatchDeckButton", row)
        if (!button) return false
        const deck = deckLibrary.deckForMatch(ready.deckId, true)
        require(deck.name === ready.deckName && deck.deckFormat === "modern",
            "The rendered first-round picker identifies a different saved deck")
        registeredDeck = detached(deck)
        require(auditProbe.click(button), "Cannot select the saved Modern deck")
        return true
    }
    function observeAutomaticRegisteredDeck(round) {
        if (!ownDeckSelected()) return false
        require(registeredDeck.name && tournament.currentRound === round && round >= 2,
            "Automatic deck verification has no first-round registered deck identity")
        require(ws.roomSession.seats[ownSeat()].deckLocked === true,
            "The automatically selected later-round deck is not projected as locked")
        require(ws.roomSession.selectedDeckName === registeredDeck.name,
            "The automatically applied registered deck name was not restored privately")
        return true
    }
    function verifyLockedDeckControls(round) {
        require(observeAutomaticRegisteredDeck(round), "The later-round registered deck is unavailable")
        const waiting = page()
        const status = find("waitingRoomTournamentDeckStatus")
        const selector = find("waitingRoomSelectDeckButton")
        const name = view("waitingRoomRegisteredDeckName")
        require(waiting && waiting.tournamentDeckLocked === true
            && status && status.visible && (!selector || !selector.visible),
            "The locked later-round deck still exposes a selector or hides its lock status")
        require(name && name.visible && name.text === registeredDeck.name && name.textFormat === Text.PlainText,
            "The locked waiting room hides or formats the authenticated owner's exact registered name")
        const position = name.mapToItem(auditWindow.contentItem, 0, 0)
        const ready = visibleGeometryItem("playerReadyButton"), readyPosition = ready && ready.mapToItem(auditWindow.contentItem, 0, 0)
        require(position.x >= 0 && position.y >= 0 && position.x + name.width <= auditWindow.width + 0.5
            && ready && readyPosition.y >= position.y + name.height - 0.5
            && readyPosition.y + ready.height <= auditWindow.height + 0.5,
            "Registered name or Ready action is clipped in the locked waiting room")
        // Only the owner name is private room metadata during a running event.
        // Compare complete first-round card registration after public completion.
        auditProbe.record("locked-deck-round-" + round, {
            participantId:tournament.participantId, actualSeat:ownSeat(),
            registeredDeckName:registeredDeck.name, deckSelected:true, deckLocked:true,
            restoredOwnName:ws.roomSession.selectedDeckName, visibleOwnName:name.text,
            selectorVisible:!!selector && selector.visible, lockStatusVisible:status.visible,
            serverDeckIdentityVerification:"completed-event-publication"
        })
        capture("locked-deck-round-" + round)
    }
    function deckCardSignature(cards) {
        return Array.from(cards || []).map(card => [card.name, card.setCode || "",
            card.collectorNumber || "", card.count].join("\u001f")).sort().join("\u001e")
    }
    function verifyCompletedRegisteredDeck() {
        require(tournament.status === "completed", "Private registered deck was requested before completion")
        const self = Array.from(tournament.participants).find(value =>
            value.participantId === tournament.participantId)
        require(self && self.deck && registeredDeck.name
            && self.deck.name === registeredDeck.name
            && deckCardSignature(self.deck.mainboard) === deckCardSignature(registeredDeck.mainboard)
            && deckCardSignature(self.deck.sideboard) === deckCardSignature(registeredDeck.sideboard),
            "The completed server registration differs from the first-round selected deck name or exact list")
        auditProbe.record("completed-registered-deck", {
            participantId:self.participantId, registeredDeckName:self.deck.name,
            mainboardSignature:deckCardSignature(self.deck.mainboard),
            sideboardSignature:deckCardSignature(self.deck.sideboard)
        })
    }
    function isReporter() { return pairing().playerAId === tournament.participantId }
    function expectedScore(round) { return read("score-" + round + "-" + pairing().pairingId) }
    function returnedToEvent() {
        return !ws.inRoom && ws.connected && !ws.reconnecting
            && tournament.inTournament && tournament.tournamentId === read("swiss-event").id
            && !!find("tournamentPairingList")
    }
    function returnedFromTable() {
        return returnedToEvent() || (ws.inRoom && ws.roomSession.phase === "waiting")
    }
    function returnCompletedTable() {
        if (returnedFromTable()) return true
        return ws.inRoom ? click("resultReturnToRoomButton") : false
    }
    function openTableLeaveConfirmation() {
        // The first participant opened each private room as its host. Its
        // intentional leave disbands the room, returning the other participant
        // to the event before that participant's serialized exit steps run.
        if (returnedToEvent()) return true
        return ws.inRoom && ws.roomSession.phase === "waiting"
            ? click("waitingRoomLeaveButton") : false
    }
    function confirmTableLeave() {
        if (returnedToEvent()) return true
        return ws.inRoom && ws.roomSession.phase === "waiting" ? click("confirmButton") : false
    }
    function recordTableScore(round) {
        const own = pairing(), room = ws.roomSession, game = ws.gameSession
        require(game.finished && game.result.matchFinished && game.result.winnerSeat === 1,
            "The bounded BO1 concession did not finish consistently")
        const winner = room.seats[1].displayName
        require(winner === own.playerAName || winner === own.playerBName, "Pairing and table player names differ")
        const score = {pairingId:own.pairingId, roomId:room.roomId, gameNumber:game.gameNumber,
            playerAWins:winner === own.playerAName ? 1 : 0,
            playerBWins:winner === own.playerBName ? 1 : 0, drawnGames:0, winner:winner}
        share("score-" + round + "-" + own.pairingId, score)
        auditProbe.record("table-result-round-" + round, score)
        capture("table-result-round-" + round)
    }
    function verifyScoreEditor(round, attempt) {
        const own = pairing(), expected = expectedScore(round)
        const hint = find("scorePrefillHint")
        const playerA = find("playerAWinsField"), playerB = find("playerBWinsField")
        const draws = find("drawnGamesField")
        require(hint && hint.visible, "The result editor did not show its finished-table prefill hint")
        require(expected.pairingId === own.pairingId && expected.roomId,
            "The retained table score belongs to another pairing")
        require(playerA && playerB && draws
            && playerA.text === String(expected.playerAWins)
            && playerB.text === String(expected.playerBWins)
            && draws.text === String(expected.drawnGames),
            "The native report fields do not map the completed table players correctly")
        require(walk(playerA.parent, item => item.text === own.playerAName)
            && walk(playerB.parent, item => item.text === own.playerBName),
            "The report fields label different players from the completed pairing")
        auditProbe.record("score-prefill-round-" + round + "-attempt-" + attempt, {
            pairingId:own.pairingId, roomId:expected.roomId, prefillHintVisible:hint.visible,
            playerAName:own.playerAName, playerBName:own.playerBName,
            playerAWins:playerA.text, playerBWins:playerB.text, drawnGames:draws.text
        })
        capture("score-prefill-round-" + round + "-attempt-" + attempt)
    }
    function recordRound(round) {
        require(tournament.status === "running"
            && Array.from(tournament.participants).every(value => !value.deck),
            "A running event exposed a registered participant deck")
        const values = detached(tournament.pairings)
        require(values.length === 2 && values.every(value => !value.bye && value.status === "open"),
            "Four checked-in players did not receive two fresh pairings")
        const participants = []
        for (const value of values) {
            const key = [value.playerAId, value.playerBId].sort().join("|")
            require(!opponents[key], "The four-player Swiss event repeated an opponent")
            opponents[key] = true
            participants.push(value.playerAId, value.playerBId)
        }
        require(new Set(participants).size === 4, "A participant appears more than once in a round")
        rounds.push({round:round, pairings:values})
        auditProbe.record("round-" + round, {pairings:values, standings:detached(tournament.standings)})
    }
    function verifyStandings(round) {
        const standings = detached(tournament.standings)
        const confirmedPairings = detached(tournament.pairings)
        const history = rounds[round - 1]
        require(history && history.round === round
            && history.pairings.map(value => value.pairingId).sort().join("|")
                === confirmedPairings.map(value => value.pairingId).sort().join("|"),
            "Confirmed pairing identities differ from the recorded round")
        for (const value of confirmedPairings) {
            const expected = read("score-" + round + "-" + value.pairingId)
            require(value.status === "confirmed" && value.playerAWins === expected.playerAWins
                && value.playerBWins === expected.playerBWins && value.drawnGames === 0,
                "The confirmed report differs from its completed table")
        }
        history.confirmedPairings = confirmedPairings
        history.standings = standings
        require(standings.length === 4, "Standings lost a checked-in participant")
        require(standings.every(value => value.wins + value.losses + value.draws === round
            && value.draws === 0 && value.byes === 0 && value.matchPoints === value.wins * 3),
            "Confirmed BO1 results and final standings disagree")
        require(standings.reduce((sum, value) => sum + value.wins, 0) === round * 2,
            "The round awarded a different number of match wins")
        const expectedRecords = ({})
        for (let completedRound = 0; completedRound < round; ++completedRound) {
            const confirmed = rounds[completedRound].confirmedPairings
            require(confirmed && confirmed.length === 2,
                "A completed round has no two confirmed pairing results")
            for (const value of confirmed) {
                require(!value.bye && value.status === "confirmed" && value.drawnGames === 0
                    && ((value.playerAWins === 1 && value.playerBWins === 0)
                        || (value.playerAWins === 0 && value.playerBWins === 1)),
                    "The four-player BO1 fixture received an unexpected bye, draw or match result")
                for (const participantId of [value.playerAId, value.playerBId]) {
                    if (!expectedRecords[participantId])
                        expectedRecords[participantId] = {wins:0, losses:0}
                }
                const winner = value.playerAWins === 1 ? value.playerAId : value.playerBId
                const loser = value.playerAWins === 1 ? value.playerBId : value.playerAId
                ++expectedRecords[winner].wins
                ++expectedRecords[loser].losses
            }
        }
        require(Object.keys(expectedRecords).length === 4
            && new Set(standings.map(value => value.participantId)).size === 4,
            "The standings do not identify the four confirmed participants uniquely")
        for (const value of standings) {
            const expected = expectedRecords[value.participantId]
            require(expected && value.wins === expected.wins && value.losses === expected.losses,
                "A participant standing differs from its actual confirmed pairings")
        }
        share("standings-" + round + "-" + seat, {rows:standings})
        auditProbe.record("standings-round-" + round, standings)
    }
    function planRound(round) {
        add("Observe round " + round, 0, () => {}, () => tournament.currentRound === round
            && tournament.status === "running" && tournament.pairings.length === 2)
        add("Verify fresh round " + round + " pairings", 0, () => recordRound(round))
        add("Capture round " + round + " pairings", 1, () => capture("pairings-round-" + round))
        for (let actor = 1; actor <= players; ++actor) {
            add("Enter round " + round + " table for player " + actor, actor,
                enterPairingMatch,
                () => ws.inRoom && ws.roomSession.deckFormat === "modern")
            if (round === 1) {
                add("Open round " + round + " deck picker for player " + actor, actor,
                    () => click("waitingRoomSelectDeckButton"), () => !!find("selectMatchDeckButton"))
                add("Select round " + round + " deck for player " + actor, actor,
                    selectDeck, firstRoundDeckSelected)
            } else {
                add("Observe automatic round " + round + " registered deck for player " + actor, actor,
                    () => {}, () => observeAutomaticRegisteredDeck(round))
                add("Verify round " + round + " locked deck controls for player " + actor, actor,
                    () => verifyLockedDeckControls(round))
            }
        }
        if (round === 2) {
            add("Reconnect player two in the locked waiting room", 2, () => {
                waitingResume = detached({roomId:ws.roomSession.roomId, seat:ownSeat(), role:ws.roomSession.role,
                    tournamentId:tournament.tournamentId, participantId:tournament.participantId,
                    currentRound:tournament.currentRound, pairingId:pairing().pairingId,
                    registeredDeckName:ws.roomSession.selectedDeckName})
                waitingSawDisconnect = false; waitingSawSnapshot = false
                waitingConnectionTrace = []; disconnectedAt = Date.now()
                auditProbe.record("before-locked-waiting-resume", waitingResume)
                require(auditProbe.interruptTransport(ws), "Cannot interrupt the isolated locked-room connection")
            }, () => waitingSawDisconnect && waitingSawSnapshot && ws.connected && !ws.reconnecting && ws.inRoom
                && ws.roomSession.roomId === waitingResume.roomId && ownSeat() === waitingResume.seat
                && ws.roomSession.role === waitingResume.role && ws.roomSession.phase === "waiting"
                && ws.roomSession.selectedDeckName === waitingResume.registeredDeckName, 60000)
            add("Verify restored locked waiting-room identity and name", 2, () => {
                require(tournament.tournamentId === waitingResume.tournamentId
                    && tournament.participantId === waitingResume.participantId
                    && tournament.currentRound === waitingResume.currentRound
                    && pairing().pairingId === waitingResume.pairingId,
                    "Locked waiting-room resume changed tournament identity or pairing")
                verifyLockedDeckControls(round)
                auditProbe.record("locked-waiting-resume", {identity:waitingResume,
                    actualDisconnect:true, freshRoomSnapshot:true, connectionTrace:waitingConnectionTrace,
                    restoredOwnName:ws.roomSession.selectedDeckName, deckLocked:ws.roomSession.seats[ownSeat()].deckLocked})
                capture("reconnected-locked-waiting")
                waitingResume = ({})
            })
        }
        for (let actor = 1; actor <= players; ++actor)
            add("Ready round " + round + " player " + actor, actor, () => click("playerReadyButton"))
        add("Verify round " + round + " loaded private hands", 0, () => {}, () => {
            if (!gameTable.hasSnapshot || !find("increaseLifeButton" + ownSeat())) return false
            require(ws.roomSession.rulesMode === "manual" && ws.roomSession.matchMode === "bo1",
                "The pairing room did not inherit manual BO1 rules")
            require(ownHand().count === 7 && gameTable.seatData(ownSeat()).libraryCount === 53,
                "The selected 60-card deck did not load")
            require(gameTable.zoneModel(1 - ownSeat(), "hand").count === 0, "Opponent hand identities leaked")
            capture("loaded-table-round-" + round)
            return true
        }, 90000)
        for (let actor = 1; actor <= players; ++actor)
            add("Draw one card in round " + round + " for player " + actor, actor,
                () => auditProbe.key(Qt.Key_D, Qt.ControlModifier | Qt.AltModifier), () => ownHand().count === 8
                    && gameTable.seatData(ownSeat()).libraryCount === 52)
        for (let actor = 1; actor <= players; ++actor) {
            add("Open round " + round + " explicit concession for player " + actor, actor,
                () => ownSeat() !== 0 || auditProbe.key(Qt.Key_Q, Qt.ControlModifier | Qt.ShiftModifier),
                () => ownSeat() !== 0 || !!find("confirmButton"))
            add("Confirm round " + round + " concession for player " + actor, actor,
                () => ownSeat() !== 0 || click("confirmButton"))
        }
        add("Observe round " + round + " complete table results", 0, () => {},
            () => ws.gameSession.finished && !!find("resultReturnToRoomButton"))
        add("Record round " + round + " real table scores", 0, () => recordTableScore(round))
        for (let actor = 1; actor <= players; ++actor) {
            add("Return round " + round + " table to waiting room for player " + actor, actor,
                returnCompletedTable, returnedFromTable)
            add("Open round " + round + " leave confirmation for player " + actor, actor,
                openTableLeaveConfirmation,
                () => returnedToEvent() || (ws.inRoom && !!find("confirmButton")))
            add("Leave round " + round + " table for player " + actor, actor,
                confirmTableLeave, returnedToEvent)
        }
        planReports(round)
        add("Observe round " + round + " fully confirmed", 0, () => {}, () => tournament.roundComplete
            && Array.from(tournament.pairings).every(value => value.status === "confirmed"))
        add("Verify round " + round + " points and records", 0, () => verifyStandings(round))
        add("Open round " + round + " standings", 1, () => clickText("Standings"),
            () => !!find("tournamentStandingList"))
        add("Capture round " + round + " standings", 1, () => capture("standings-round-" + round))
        if (round === 1) {
            add("Reconnect player two between rounds", 2, () => {
                recoveryState = JSON.stringify({id:tournament.tournamentId, participant:tournament.participantId,
                    pairings:Array.from(tournament.pairings), standings:Array.from(tournament.standings)})
                disconnectedAt = Date.now()
                require(auditProbe.interruptTransport(ws), "Cannot interrupt the isolated event connection")
            }, () => Date.now() - disconnectedAt > 700 && ws.connected && !ws.reconnecting
                && !!find("tournamentPairingList"), 60000)
            add("Verify restored event membership and standings", 2, () => {
                require(JSON.stringify({id:tournament.tournamentId, participant:tournament.participantId,
                    pairings:Array.from(tournament.pairings), standings:Array.from(tournament.standings)}) === recoveryState,
                    "Event reconnect changed pairing identity or confirmed standings")
                capture("reconnected-event")
            })
        }
        if (round < 3) {
            add("Publish round " + (round + 1), 1,
                () => clickText("Publish next round", "tournamentEventDeskScroll"),
                () => tournament.currentRound === round + 1)
            add("Restore current pairings tab", 1, () => clickText("Current pairings"),
                () => !!find("tournamentPairingList"))
        }
    }
    function planReports(round) {
        const attempts = round === 1 ? 2 : 1
        for (let attempt = 0; attempt < attempts; ++attempt) {
            for (let actor = 1; actor <= players; ++actor) {
                add("Open round " + round + " report " + attempt + " for player " + actor, actor,
                    () => !isReporter() || clickText("Report", "tournamentPairingList", pairingRow()),
                    () => !isReporter() || !!find("submitTournamentScoreButton"))
                add("Verify round " + round + " report prefill " + attempt + " for player " + actor, actor,
                    () => { if (isReporter()) verifyScoreEditor(round, attempt) })
                add("Submit round " + round + " report " + attempt + " for player " + actor, actor,
                    () => !isReporter() || click("submitTournamentScoreButton"),
                    () => !isReporter() || pairing().status === "reported")
            }
            if (round === 1 && attempt === 0) {
                for (let actor = 1; actor <= players; ++actor)
                    add("Reject first-round report for player " + actor, actor,
                        () => isReporter() || clickText("Reject", "tournamentPairingList", pairingRow()),
                        () => isReporter() || pairing().status === "open")
                add("Verify rejection reopened both matches", 0, () => {},
                    () => Array.from(tournament.pairings).every(value => value.status === "open"))
            }
        }
        for (let actor = 1; actor <= players; ++actor)
            add("Confirm round " + round + " score for player " + actor, actor,
                () => isReporter() || clickText("Confirm", "tournamentPairingList", pairingRow()),
                () => isReporter() || pairing().status === "confirmed")
    }
    function plan() {
        require(players === 4, "This complete three-round constructed event requires four isolated clients")
        require(auditProbe.environment("HEXPROOF_AUDIT_VARIANT") === "modern", "Use the Modern fixture")
        auditProbe.fixture("saved-modern-decks", {description:"Prepared isolated saved decks and cached art; event creation, registration, every table, concession and result report use native production controls."})
        for (let actor = 1; actor <= players; ++actor) {
            add("Open connection form for player " + actor, actor, () => click("mainMenuConnectButton"),
                () => !!find("connectSubmitButton"))
            add("Connect isolated player " + actor, actor, () => click("connectSubmitButton"), () => ws.connected)
        }
        add("Open Events", 1, () => click("mainMenuEventsButton"), () => !!find("tournamentCreateButton"))
        add("Open constructed tournament form", 1, () => click("tournamentCreateButton"), () => !!find("tournamentNameField"))
        add("Name the complete Swiss event", 1, () => fill("tournamentNameField", "Native complete Swiss"))
        add("Select Modern card pool", 1, () => combo("tournamentFormatSelector", 2, "tournamentCreateBody"))
        add("Select BO1 manual tables", 1, () => clickText("BO 1", "tournamentCreateBody"), () => page().matchMode === "bo1")
        add("Set four-player capacity", 1, () => fill("tournamentPlayerCapField", "4", "tournamentCreateBody"))
        add("Create production Swiss event", 1, () => click("tournamentCreateSubmitButton", "tournamentCreateBody"),
            () => tournament.inTournament && tournament.status === "registration")
        add("Verify organizer is not automatically a player", 1, () => {
            require(tournament.participantId.length === 0 && tournament.registered === 0,
                "Creating an event consumed a player seat")
            require(tournament.format === "Modern" && tournament.matchMode === "bo1" && tournament.rulesMode === "manual",
                "The created event lost the chosen format or rules")
            share("swiss-event", {id:tournament.tournamentId})
        })
        for (let actor = 2; actor <= players; ++actor) {
            add("Open Events for player " + actor, actor, () => click("mainMenuEventsButton"), () => !!find("tournamentCodeField"))
            add("Enter public event code for player " + actor, actor, () => fill("tournamentCodeField", read("swiss-event").id))
            add("Open event view for player " + actor, actor, () => click("tournamentOpenButton"), () => tournament.inTournament)
        }
        for (let actor = 1; actor <= players; ++actor) {
            add("Register player " + actor, actor, () => click("registerLimitedPlayerButton", "tournamentEventDeskScroll"),
                () => tournament.participantId.length > 0)
            add("Check in player " + actor, actor, () => clickText("Check in", "tournamentEventDeskScroll"), () => page().selfCheckedIn)
        }
        add("Observe four checked-in participants", 0, () => {}, () => tournament.registered === 4 && tournament.checkedIn === 4)
        add("Capture checked-in registration", 1, () => capture("registration-four-players"))
        add("Start the complete Swiss event", 1, () => click("startTournamentButton", "tournamentEventDeskScroll"),
            () => tournament.status === "running" && tournament.currentRound === 1 && tournament.plannedRounds === 3)
        for (let round = 1; round <= 3; ++round) planRound(round)
        add("Finish the announced three rounds", 1, () => clickText("Finish tournament", "tournamentEventDeskScroll"),
            () => tournament.status === "completed")
        add("Verify immutable final results on every client", 0, () => {
            verifyStandings(3)
            verifyCompletedRegisteredDeck()
            require(rounds.length === 3 && Object.keys(opponents).length === 6,
                "The complete four-player event did not cover every distinct match")
            require(!find("correctTournamentResultButton") && !find("submitTournamentScoreButton"),
                "A completed event still exposes result editing")
        })
        for (let actor = 1; actor <= players; ++actor) {
            add("Show final standings for player " + actor, actor, () => page().selectedTab === 1 || clickText("Standings"),
                () => !!find("tournamentStandingList"))
            add("Capture final standings for player " + actor, actor, () => capture("completed-final-standings"))
        }
    }
    function finish(error) {
        if (finished) return
        finished = true
        if (error) {
            if (auditProbe.capture(auditWindow, "failure")) screenshots.push("failure.png")
            auditProbe.record("failure-state", auditProbe.observe(auditWindow))
        }
        auditProbe.record("result", {status:error ? "failed" : "passed", scenario:"tournament-swiss", seat:seat,
            evidence:auditProbe.environment("HEXPROOF_AUDIT_OS_INPUT_HELPER") ? "system-input" : "native-qt-input",
            error:error || "", pendingStep:index < steps.length ? steps[index].name : "", assertions:assertions,
            rounds:rounds, registeredDeckName:registeredDeck.name || "",
            finalStandings:detached(tournament.standings), requiredScreenshots:screenshots,
            coverage:"Four-client production constructed registration/check-in, first-round native deck picker and acknowledged name, automatic locked deck/hidden selector plus restored owner-private name in later rounds and actual locked-waiting-room reconnect, exact registered name/list at completed publication, three Swiss rounds, six manual BO1 table results ended by explicit native concession, real score prefill, rejection/report/confirmation, next-round gating, event reconnect and immutable completed standings. No natural Forge gameplay or timer expiry."})
        auditProbe.finish(error ? 1 : 0)
    }
    Component.onCompleted: { try { plan() } catch (error) { finish(String(error)) } }
    Timer {
        interval: 100; repeat: true; running: !driver.finished
        onTriggered: {
            if (driver.dispatching) return
            driver.dispatching = true
            try {
                driver.require(auditProbe.beginInput(), "Cannot acquire desktop input")
                if (driver.index >= driver.steps.length) { driver.finish(""); return }
                const step = driver.steps[driver.index]
                const ownsStep = step.actor === 0 || step.actor === driver.seat
                driver.require(Date.now() - driver.entered < step.timeout + (ownsStep ? 0 : 5000), "Timed out: " + step.name)
                driver.require(!ws.lastError, "Server error: " + ws.lastError)
                if (auditWindow.stack.busy) return
                if (ownsStep && !driver.acknowledged && !auditWindow.active)
                    driver.require(auditProbe.activate(), "Cannot activate the current test client")
                if (!driver.acknowledged) {
                    if (ownsStep) {
                        if (!driver.acted) { if (step.action() === false) return; driver.acted = true }
                        if (!step.check()) return
                    }
                    driver.share("swiss-step-" + driver.index + "-" + driver.seat, {ready:true})
                    driver.acknowledged = true
                }
                for (let actor = 1; actor <= driver.players; ++actor)
                    if (!driver.read("swiss-step-" + driver.index + "-" + actor).ready) return
                driver.assertions.push({step:step.name, actor:step.actor, verifiedLocally:ownsStep, elapsedMs:Date.now() - driver.entered})
                driver.index++; driver.acted = false; driver.acknowledged = false; driver.entered = Date.now()
                auditProbe.record("progress", {index:driver.index, next:driver.index < driver.steps.length ? driver.steps[driver.index].name : "complete"})
            } catch (error) { driver.finish(String(error)) }
            finally { auditProbe.endInput(); driver.dispatching = false }
        }
    }
}
