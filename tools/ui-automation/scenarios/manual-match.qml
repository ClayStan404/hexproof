// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: driver
    property int seat: Number(auditProbe.environment("HEXPROOF_AUDIT_SEAT"))
    property int players: Number(auditProbe.environment("HEXPROOF_AUDIT_PLAYERS"))
    property string format: auditProbe.environment("HEXPROOF_AUDIT_VARIANT") || "modern"
    property int step: 0
    property double entered: Date.now()
    property var checks: []
    property string movedCard: ""
    property int playStep: 0
    property bool dispatching: false
    property bool formatPopupOpened: false

    function item(name, scope) { return auditProbe.find(scope || auditWindow, name) }
    function click(name) {
        const target = item(name)
        return target && auditProbe.click(target)
    }
    function next(label) {
        checks.push({step: step, label: label, elapsedMs: Date.now() - entered})
        auditProbe.record("progress", {step: step, label: label})
        step++
        entered = Date.now()
    }
    function capture(name) {
        if (!auditProbe.capture(auditWindow, name))
            throw new Error("Failed to capture " + name)
    }
    function fail(message) {
        ticker.stop()
        auditProbe.capture(auditWindow, "failure")
        auditProbe.record("failure-state", auditProbe.observe(auditWindow))
        auditProbe.record("result", {status: "failed", step: step, message: message,
                                    checks: checks, lastError: ws.lastError})
        auditProbe.finish(1)
    }
    function selectFormat() {
        const selector = item("roomFormatSelector")
        if (!formatPopupOpened) {
            const name = item("roomNameField")
            if (!name || !auditProbe.click(name) || !auditProbe.type("Native " + format))
                return false
            if (!selector || !auditProbe.click(selector)) return false
            formatPopupOpened = true
            return false
        }
        // The combo button is covered by its popup; inspect the page's model
        // while keyboard input remains scoped to the active popup focus.
        const options = auditWindow.stack.currentItem.selectableFormatOptions
        let index = -1
        for (let i = 0; i < options.length; ++i)
            if (options[i].value === format) index = i
        if (index < 0) throw new Error("Missing room format " + format)
        auditProbe.key(Qt.Key_Home)
        for (let i = 0; i < index; ++i) auditProbe.key(Qt.Key_Down)
        return auditProbe.key(Qt.Key_Return)
    }
    function myHand() { return gameTable.zoneModel(ws.roomSession.seatIndex, "hand") }
    function allShared(prefix) {
        for (let i = 1; i <= players; ++i)
            if (!(auditProbe.readShared(prefix + i) || {}).ready) return false
        return true
    }
    Component.onCompleted: {
        auditProbe.fixture("local-decks", {
            description: "Explicit preloaded decks/art are setup; all room and gameplay commands use native input.",
            format: format, players: players
        })
        if (players !== (format === "commander" ? 4 : 2))
            fail("This scenario requires two seats, or four for Commander")
    }
    Timer {
        id: ticker
        running: true
        repeat: true
        interval: 250
        onTriggered: {
            if (driver.dispatching) return
            driver.dispatching = true
            try {
                if (Date.now() - driver.entered > 25000) {
                    driver.fail("Timed out waiting for step " + driver.step)
                    return
                }
                const room = ws.roomSession
                const game = ws.gameSession
                if (auditWindow.stack.busy) return
                switch (driver.step) {
                case 0:
                    if (driver.click("mainMenuConnectButton")) driver.next("Open connection form")
                    break
                case 1:
                    if (driver.click("connectSubmitButton")) driver.next("Connect to isolated loopback hub")
                    break
                case 2:
                    if (!ws.connected) break
                    if (driver.click(driver.seat === 1 ? "mainMenuCreateRoomButton" : "mainMenuJoinRoomButton"))
                        driver.next("Open room form")
                    break
                case 3:
                    if (driver.seat === 1) {
                        if (driver.selectFormat()) driver.next("Select " + driver.format)
                    } else {
                        const code = (auditProbe.readShared("room") || {}).code
                        if (code && driver.click("joinRoomCodeField") && auditProbe.type(code))
                            driver.next("Enter shared room code")
                    }
                    break
                case 4:
                    if (driver.click(driver.seat === 1 ? "createRoomSubmitButton" : "joinRoomSubmitButton"))
                        driver.next("Submit room form")
                    else if (driver.seat === 1) {
                        const body = driver.item("createRoomBody")
                        if (body) auditProbe.wheel(body, -360)
                    }
                    break
                case 5:
                    if (!ws.inRoom) break
                    if (room.rulesMode !== "manual" || room.deckFormat !== driver.format)
                        throw new Error("Wrong room mode/format")
                    if (driver.seat === 1) auditProbe.share("room", {code: room.roomId})
                    if (driver.click("waitingRoomSelectDeckButton")) driver.next("Open deck picker")
                    break
                case 6:
                    if (driver.click("selectMatchDeckButton")) driver.next("Select matching cached deck")
                    break
                case 7:
                    if (!room.selectedDeckName) break
                    auditProbe.share("seated" + driver.seat, {ready: true, seatIndex: room.seatIndex})
                    if (!driver.allShared("seated")) break
                    if (driver.click("playerReadyButton")) driver.next("Ready after all seats selected decks")
                    break
                case 8:
                    if (!gameTable.hasSnapshot || !driver.item("increaseLifeButton" + room.seatIndex)) break
                    if (driver.myHand().count !== 7) throw new Error("Opening hand is not seven cards")
                    for (let i = 0; i < driver.players; ++i) {
                        if (gameTable.seatData(i).life !== (driver.format === "commander" ? 40 : 20))
                            throw new Error("Unexpected starting life")
                        if (i !== room.seatIndex && gameTable.zoneModel(i, "hand").count !== 0)
                            throw new Error("Opponent private hand identities exposed")
                    }
                    driver.capture("01-opening-table")
                    auditProbe.share("opened" + driver.seat, {ready: true})
                    driver.next("Opening hand, life totals and private hand projection")
                    break
                case 9:
                    if (!driver.allShared("opened")) break
                    // All seats share this workstation's window manager.
                    // Finish one player's input burst before activating the next.
                    if (driver.seat > 1 && !(auditProbe.readShared("played" + (driver.seat - 1)) || {}).ready) break
                    if (driver.click("increaseLifeButton" + room.seatIndex)) driver.next("Increase life using table control")
                    break
                case 10:
                    if (gameTable.seatData(room.seatIndex).life !== (driver.format === "commander" ? 41 : 21)) break
                    if (auditProbe.key(Qt.Key_D, Qt.ControlModifier | Qt.AltModifier))
                        driver.next("Draw using registered keyboard shortcut")
                    break
                case 11:
                    if (driver.playStep === 0) {
                        if (driver.myHand().count !== 8) break
                        driver.capture("02-after-draw")
                        const source = driver.item("handCard0")
                        const target = driver.item("battlefieldZone" + room.seatIndex)
                        if (!source || !target) break
                        driver.movedCard = source.cardId
                        if (!driver.movedCard) throw new Error("Hand delegate has no physical identity")
                        if (auditProbe.drag(source, target)) driver.playStep = 1
                        break
                    }
                    if (driver.playStep === 1) {
                        if (!gameTable.cardInZone(driver.movedCard, "battlefield", room.seatIndex)) break
                        const permanent = driver.item("battlefieldCard" + driver.movedCard)
                        if (permanent && auditProbe.doubleClick(permanent)) driver.playStep = 2
                        break
                    }
                    if (!gameTable.cardData(driver.movedCard).tapped) break
                    if (driver.myHand().count !== 7) throw new Error("Drag did not remove exactly one hand card")
                    driver.capture("02-permanent-tapped")
                    auditProbe.share("played" + driver.seat, {ready: true})
                    driver.next("Drew to eight, dragged one physical card to battlefield, then tapped it")
                    break
                case 12:
                    if (!driver.allShared("played")) break
                    for (let i = 0; i < driver.players; ++i) {
                        const publicSeat = gameTable.seatData(i)
                        if (publicSeat.life !== (driver.format === "commander" ? 41 : 21)
                                || publicSeat.handCount !== 7
                                || gameTable.zoneModel(i, "battlefield").count !== 1)
                            throw new Error("Peers disagree on final public board state")
                    }
                    // Concede in a fixed order to cover partial EDH elimination and final results.
                    if (driver.seat < driver.players) {
                        if (driver.seat > 1 && !(auditProbe.readShared("conceded" + (driver.seat - 1)) || {}).ready) break
                        if (auditProbe.key(Qt.Key_Q, Qt.ControlModifier | Qt.ShiftModifier))
                            driver.next("Open concede confirmation")
                    } else driver.next("Final seat waits for result")
                    break
                case 13:
                    if (driver.seat === driver.players || driver.click("confirmButton"))
                        driver.next("Confirm current game concession")
                    break
                case 14:
                    if (driver.seat < driver.players) {
                        if (driver.format === "commander" && !gameTable.seatData(room.seatIndex).eliminated && !game.finished) break
                        auditProbe.share("conceded" + driver.seat, {ready: true})
                    }
                    if (!game.finished || !driver.item("gameResultTitle")) break
                    const survivor = auditProbe.readShared("seated" + driver.players)
                    if (!survivor || game.result.winnerSeat !== survivor.seatIndex)
                        throw new Error("Match winner is not the final non-conceding player")
                    driver.capture("03-match-result")
                    auditProbe.share("result" + driver.seat, {ready: true})
                    driver.next("All clients received completed match result")
                    break
                case 15:
                    if (!driver.allShared("result")) break
                    if (driver.seat === driver.players) {
                        if (!driver.click("resultReturnToRoomButton")) break
                    }
                    driver.next("Winner returns group to waiting room")
                    break
                case 16:
                    if (!driver.item("waitingRoomSelectDeckButton")) break
                    driver.capture("04-returned-to-room")
                    auditProbe.share("returned" + driver.seat, {ready: true})
                    driver.next("Waiting room restored")
                    break
                case 17:
                    if (!driver.allShared("returned")) break
                    ticker.stop()
                    auditProbe.record("result", {status: "passed", evidence: "native-qt-input",
                                                format: driver.format, seat: driver.seat,
                                                requiredScreenshots: ["01-opening-table.png", "02-after-draw.png", "02-permanent-tapped.png",
                                                    "03-match-result.png", "04-returned-to-room.png"],
                                                checks: driver.checks})
                    auditProbe.finish(0)
                    break
                }
            } catch (error) { driver.fail(String(error)) }
            finally { driver.dispatching = false }
        }
    }
}
