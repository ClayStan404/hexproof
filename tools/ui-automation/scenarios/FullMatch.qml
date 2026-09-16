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
    property string movedCardName: ""
    property var operations: []
    property int operationIndex: 0
    property bool operationDispatched: false
    property string commanderId: ""
    property int initialLibraryCount: 0
    property int phaseStep: 0
    property int startingSeat: -1
    property int expectedNextSeat: -1
    property var shapePlan: []
    property var fixtureManifest: ({})
    property var lastDrag: ({})

    FullMatchShapes {
        id: shapeActions
        driver: driver
        probe: auditProbe
        window: auditWindow
    }

    FullMatchDragEdges {
        id: dragEdges
        driver: driver
        probe: auditProbe
    }

    function require(value, message) {
        if (!value) throw new Error(message + "; " + auditProbe.lastError)
    }
    function ownSeat() { return ws.roomSession.seatIndex }
    function ownData() { return gameTable.seatData(ownSeat()) }
    function zone(name) { return gameTable.zoneModel(ownSeat(), name) }
    function inZone(id, name) { return gameTable.cardInZone(id, name, name === "stack" ? -1 : ownSeat()) }
    function inputKey(key, modifiers) {
        require(auditProbe.key(key, modifiers || 0), "Keyboard input rejected")
        return true
    }
    function checkedClick(name) {
        const target = item(name)
        if (!target) return false
        require(auditProbe.click(target), "Click rejected: " + name)
        return true
    }
    function rightClick(name) {
        const target = item(name)
        if (!target) return false
        require(auditProbe.rightClick(target), "Context input rejected: " + name)
        return true
    }
    function drag(sourceName, targetName) {
        const source = item(sourceName)
        const target = item(targetName)
        if (!source || !target) return false
        return checkedDrag(source, target, sourceName + " -> " + targetName)
    }
    function cardSummary(card) {
        if (!card) return ({})
        const result = ({})
        for (const key of ["id", "name", "setCode", "collectorNumber", "typeLine", "faceName",
                           "faceDown", "tapped", "ownerSeat", "controllerSeat", "counters"])
            if (card[key] !== undefined) result[key] = card[key]
        return result
    }
    function zoneSummary(model) {
        const rows = []
        if (model)
            for (let index = 0; index < model.count; ++index) rows.push(cardSummary(model.get(index)))
        return rows
    }
    function interactionState() {
        const table = auditWindow.stack.currentItem
        const result = {step: step, operationIndex: operationIndex, operationDispatched: operationDispatched,
                        operation: operationIndex < operations.length ? operations[operationIndex].name : "",
                        auditError: auditProbe.lastError, serverError: ws.lastError, lastDrag: lastDrag}
        if (ownSeat() >= 0) {
            result.ownSeat = ownSeat()
            result.hand = zoneSummary(myHand())
            result.battlefield = zoneSummary(zone("battlefield"))
            result.graveyard = zoneSummary(zone("graveyard"))
            result.exile = zoneSummary(zone("exile"))
            result.stack = zoneSummary(gameTable.stackModel)
            result.reveal = zoneSummary(gameTable.revealedModel)
            result.libraryCount = ownData().libraryCount
            result.movedCard = cardSummary(gameTable.cardData(movedCard))
        }
        if (table) {
            for (const key of ["canAct", "tableModalOpen", "activeHandDragCardId", "activeBattlefieldDragCardId",
                               "selectedBattlefieldCardId", "selectedSharedZone", "pendingCardMoves"])
                if (table[key] !== undefined) result[key] = table[key]
            result.selectedHandCard = cardSummary(table.selectedHandCard)
            result.selectedSharedCard = cardSummary(table.selectedSharedCard)
        }
        return result
    }
    function itemSummary(target) {
        const position = target.mapToItem(auditWindow.contentItem, 0, 0)
        return {objectName: target.objectName, cardId: target.cardId || "", card: cardSummary(target.modelData),
                visualIndex: target.visualIndex === undefined ? -1 : target.visualIndex,
                x: position.x, y: position.y, width: target.width, height: target.height,
                activeFocus: target.activeFocus, visible: target.visible, enabled: target.enabled}
    }
    function checkedDrag(source, target, label, sourceX, sourceY) {
        if (!source || !target) return false
        lastDrag = {label: label, source: itemSummary(source), target: itemSummary(target)}
        const edge = sourceX !== undefined && sourceY !== undefined
        if (edge) lastDrag.sourceGrab = {x: sourceX, y: sourceY}
        auditProbe.record("drag-" + operationIndex + "-before", interactionState())
        require(edge ? auditProbe.drag(source, target, sourceX, sourceY)
                     : auditProbe.drag(source, target), "Drag rejected: " + label)
        auditProbe.record("drag-" + operationIndex + "-after", interactionState())
        return true
    }
    function handItem(id) {
        for (let i = 0; i < myHand().count; ++i) {
            const candidate = item("handCard" + i)
            if (candidate && candidate.cardId === id) return candidate
        }
        // Locate the card without clicking clipped delegates. Moving the hand
        // viewport is an actual wheel event, never a ListView position setter.
        const view = item("ownHand")
        if (!view || view.moving) return null
        let direction = view.atXEnd ? 1 : -1
        for (let index = 0; index < view.count; ++index) {
            const candidate = view.itemAtIndex(index)
            if (candidate && candidate.cardId === id) {
                direction = candidate.x + candidate.width / 2 < view.contentX ? 1 : -1
                break
            }
        }
        require(auditProbe.wheel(view, direction * 180), "Cannot scroll the hand to its physical card")
        return null
    }
    function numberCounter() {
        const counters = gameTable.cardData(movedCard).counters || []
        const number = counters.find(counter => counter.kind === "number")
        return number ? Number(number.value) : 0
    }
    function inspectPrivacyRequest() {
        const request = auditProbe.readShared("privacy-request")
        if (!request || !request.cardId) return
        const receipt = "privacy-" + request.sourceSeat + "-" + seat
        if ((auditProbe.readShared(receipt) || {}).ready) return
        const card = gameTable.cardData(request.cardId)
        if (!card.faceDown) return
        if (ownSeat() === request.controllerSeat) {
            require(!!card.name, "Controller lost the identity of its face-down card")
        } else {
            for (const key of ["name", "setCode", "collectorNumber", "typeLine", "faceName"])
                require(!card[key], "Face-down identity leaked to another player: " + key)
        }
        require(card.ownerSeat === request.controllerSeat,
                "Face-down projection unexpectedly changed immutable ownership")
        auditProbe.record("privacy-seat-" + request.sourceSeat, {viewerSeat: ownSeat(),
                          controllerSeat: request.controllerSeat, card: card})
        capture("privacy-seat-" + request.sourceSeat)
        auditProbe.share(receipt, {ready: true})
        checks.push({operation: "Observe face-down privacy for seat " + request.controllerSeat})
    }
    function operation(name, action, check) {
        operations.push({name: name, action: action, check: check || (() => true)})
    }
    function planOperations() {
        initialLibraryCount = ownData().libraryCount
        operation("Open mulligan confirmation", () => inputKey(Qt.Key_M, Qt.ControlModifier),
                  () => !!item("confirmButton"))
        operation("Mulligan returns hand, shuffles and draws seven", () => checkedClick("confirmButton"),
                  () => ownData().mulliganCount === 1 && myHand().count === 7
                        && ownData().libraryCount === initialLibraryCount)
        operation("Increase own life", () => checkedClick("increaseLifeButton" + ownSeat()),
                  () => ownData().life === (format === "commander" ? 41 : 21))
        operation("Show shared stack tray", () => item("sharedCards")
                  ? true : inputKey(Qt.Key_V, Qt.ControlModifier | Qt.ShiftModifier),
                  () => !!item("sharedCards"))
        operation("Cast a physical hand card through stack", () => {
            const deck = fixtureManifest.decks && fixtureManifest.decks[format]
            const shapes = deck && deck.shapeCards || ({})
            const reserved = Object.keys(shapes).filter(tag => ["transform", "modal_dfc", "prepare"].indexOf(tag) >= 0)
                            .map(tag => shapes[tag].name)
            const candidates = []
            for (let index = 0; index < myHand().count; ++index) candidates.push(myHand().get(index))
            function isLand(card) {
                const fixture = deck && deck.mainboard.find(row => shapeActions.exact(card, row))
                const mainType = String(card.typeLine || fixture && fixture.typeLine || "").split("//")[0].split(/[—–~～－]/)[0]
                return /\bLand\b/i.test(mainType) || mainType.indexOf("地") >= 0
            }
            if (deck) candidates.sort((left, right) => Number(isLand(left)) - Number(isLand(right)))
            for (const candidate of candidates) {
                if (reserved.indexOf(candidate.name) >= 0
                        || cardCatalog.cardFaces(candidate.name, candidate.setCode, candidate.collectorNumber).length > 1)
                    continue
                const source = handItem(candidate.id)
                const target = item("sharedCards")
                if (!source || !target) return false
                movedCard = candidate.id
                movedCardName = candidate.name
                require(!!movedCard, "Missing physical hand identity")
                require(source.cardId === movedCard && source.modelData.name === movedCardName,
                        "Visible hand delegate does not match the chosen physical card")
                return checkedDrag(source, target, "Cast " + movedCardName + " (" + movedCard + ") through stack")
            }
            throw new Error("Opening hand has no unreserved single-face card for the shared-zone cycle")
        }, () => inZone(movedCard, "stack") && myHand().count === 6)
        operation("Select own stack spell", () => checkedClick("sharedCard0"),
                  () => !!item("sharedToBattlefieldButton"))
        operation("Resolve stack card to battlefield", () => checkedClick("sharedToBattlefieldButton"),
                  () => inZone(movedCard, "battlefield") && gameTable.stackModel.count === 0)
        operation("Tap resolved permanent", () => {
            const permanent = item("battlefieldCard" + movedCard)
            return permanent && auditProbe.doubleClick(permanent)
        }, () => gameTable.cardData(movedCard).tapped === true)
        operation("Select permanent for graveyard move", () => checkedClick("battlefieldCard" + movedCard))
        operation("Move permanent to graveyard", () => inputKey(Qt.Key_G, Qt.AltModifier),
                  () => inZone(movedCard, "graveyard") && zone("battlefield").count === 0)
        operation("Browse own graveyard", () => checkedClick("graveyardBrowserButton" + ownSeat()),
                  () => !!item("zoneBrowserCard0"))
        operation("Open graveyard card destination menu", () => rightClick("zoneBrowserCard0"),
                  () => !!item("zoneCardToExile"))
        operation("Move graveyard card to exile", () => checkedClick("zoneCardToExile"),
                  () => inZone(movedCard, "exile") && zone("graveyard").count === 0)
        operation("Browse own exile", () => checkedClick("exileBrowserButton" + ownSeat()),
                  () => !!item("zoneBrowserCard0"))
        operation("Open exile card destination menu", () => rightClick("zoneBrowserCard0"),
                  () => !!item("zoneCardToLibrary"))
        operation("Place exact exiled card on library top", () => checkedClick("zoneCardToLibrary"),
                  () => zone("exile").count === 0 && ownData().libraryCount === initialLibraryCount + 1)
        operation("Draw the known top card back", () => inputKey(Qt.Key_D, Qt.ControlModifier | Qt.AltModifier),
                  () => inZone(movedCard, "hand") && myHand().count === 7)
        operation("Replay the same physical card", () => {
            const source = handItem(movedCard)
            const target = item("battlefieldZone" + ownSeat())
            return checkedDrag(source, target, "Replay " + movedCardName + " (" + movedCard + ") to battlefield")
        }, () => inZone(movedCard, "battlefield") && myHand().count === 6)
        operation("Tap replayed permanent", () => {
            const permanent = item("battlefieldCard" + movedCard)
            return permanent && auditProbe.doubleClick(permanent)
        }, () => gameTable.cardData(movedCard).tapped === true)
        operation("Draw another card", () => inputKey(Qt.Key_D, Qt.ControlModifier | Qt.AltModifier),
                  () => myHand().count === 7)
        operation("Reveal current hand", () => inputKey(Qt.Key_H, Qt.ControlModifier),
                  () => myHand().count === 0 && gameTable.revealedModel.count === 7)
        operation("Recall every revealed card", () => inputKey(Qt.Key_H, Qt.ControlModifier),
                  () => myHand().count === 7 && gameTable.revealedModel.count === 0)
        operation("Select permanent for public counters", () => checkedClick("battlefieldCard" + movedCard))
        operation("Add number counter", () => inputKey(Qt.Key_N), () => numberCounter() === 1)
        operation("Increment number counter", () => inputKey(Qt.Key_N), () => numberCounter() === 2)
        operation("Decrement number counter", () => inputKey(Qt.Key_Minus), () => numberCounter() === 1)
        operation("Remove final number counter", () => inputKey(Qt.Key_Minus), () => numberCounter() === 0)
        operation("Turn controlled permanent face down", () => inputKey(Qt.Key_F),
                  () => gameTable.cardData(movedCard).faceDown === true
                        && gameTable.cardData(movedCard).name === movedCardName)
        operation("Every client verifies face-down identity projection", () => {
            auditProbe.share("privacy-request", {sourceSeat: seat, controllerSeat: ownSeat(), cardId: movedCard})
        }, () => {
            for (let viewer = 1; viewer <= players; ++viewer)
                if (!(auditProbe.readShared("privacy-" + seat + "-" + viewer) || {}).ready) return false
            return true
        })
        // Flipping clears the table selection. Select the same physical card
        // again before invoking the face-up shortcut.
        operation("Reselect the same face-down permanent", () => checkedClick("battlefieldCard" + movedCard),
                  () => {
                      const permanent = item("battlefieldCard" + movedCard)
                      const selected = permanent && permanent.tableController.selectedBattlefieldCard
                      return selected && selected.id === movedCard
                  })
        operation("Turn the same permanent face up", () => inputKey(Qt.Key_F),
                  () => gameTable.cardData(movedCard).faceDown !== true
                        && gameTable.cardData(movedCard).name === movedCardName)
        dragEdges.append()
        if (format === "commander" || format === "duel") {
            operation("Open readable commander damage ledger", () => {
                const button = item("commanderDamageButton")
                if (!button) return false
                const label = button.contentItem
                require(label.paintedWidth <= label.width + 1
                        && label.paintedHeight <= label.height + 1,
                        "Commander damage label exceeds its action-rail button")
                capture("commander-damage-action")
                return checkedClick("commanderDamageButton")
            }, () => auditWindow.stack.currentItem.commanderDamagePopup.opened)
            operation("Close commander damage ledger", () => inputKey(Qt.Key_Escape),
                      () => !auditWindow.stack.currentItem.commanderDamagePopup.opened)
            operation("Browse command zone", () => checkedClick("commandZoneButton" + ownSeat()),
                      () => !!item("zoneBrowserCard0"))
            operation("Select physical commander", () => {
                const row = item("zoneBrowserCard0")
                if (!row) return false
                commanderId = row.modelData.id
                require(!!commanderId, "Missing command-zone physical identity")
                return rightClick("zoneBrowserCard0")
            }, () => !!item("zoneCardCastCommander"))
            operation("Cast commander and increment only its tax", () => checkedClick("zoneCardCastCommander"),
                      () => inZone(commanderId, "stack")
                            && ownData().commanderTaxes[commanderId] === 1)
            operation("Select cast commander", () => checkedClick("sharedCard0"),
                      () => !!item("sharedToBattlefieldButton"))
            operation("Resolve commander to battlefield", () => checkedClick("sharedToBattlefieldButton"),
                      () => inZone(commanderId, "battlefield"))
            operation("Return commander by drag without another cast", () => drag(
                          "battlefieldCard" + commanderId, "commandZoneButton" + ownSeat()),
                      () => inZone(commanderId, "command")
                            && ownData().commanderTaxes[commanderId] === 1)
        }
        shapePlan = shapeActions.append(fixtureManifest)
        operation("Record complete per-seat zone cycle", () => {
            require(myHand().count === 7 && zone("battlefield").count === 1,
                    "Zone cycle did not preserve expected physical counts")
            capture("02-full-zone-cycle")
        })
    }
    function runOperations() {
        if (operations.length === 0) { planOperations(); entered = Date.now() }
        if (operationIndex >= operations.length) return true
        const current = operations[operationIndex]
        require(Date.now() - entered < 15000, "Timed out operation: " + current.name)
        if (!operationDispatched) operationDispatched = current.action() !== false
        if (!operationDispatched || !current.check()) return false
        checks.push({operation: current.name, elapsedMs: Date.now() - entered})
        auditProbe.record("gameplay-progress", {operation: operationIndex, name: current.name,
                          hand: myHand().count, library: ownData().libraryCount,
                          state: interactionState(), checks: checks})
        operationIndex++
        operationDispatched = false
        entered = Date.now()
        return operationIndex >= operations.length
    }
    property bool dispatching: false
    property bool formatPopupOpened: false
    property bool wasWaitingForPeer: false

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
        auditProbe.record("failure-gameplay", interactionState())
        auditProbe.record("result", {status: "failed", step: step, operation: operationIndex < operations.length ? operations[operationIndex].name : "", message: message,
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
        fixtureManifest = auditProbe.readShared("fixture") || ({})
        auditProbe.fixture("local-decks", {
            description: "Saved decks/art are prerequisites; bootstrap evidence records their origin. All room and gameplay commands use native input.",
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
                const peerWait = (driver.step === 9 && driver.seat > 1
                    && !(auditProbe.readShared("played" + (driver.seat - 1)) || {}).ready)
                    || (driver.step === 12 && !driver.allShared("played"))
                if (driver.wasWaitingForPeer && !peerWait) driver.entered = Date.now()
                driver.wasWaitingForPeer = peerWait
                if (Date.now() - driver.entered > (peerWait ? driver.players * 90000 : 90000)) {
                    driver.fail("Timed out waiting for step " + driver.step)
                    return
                }
                const room = ws.roomSession
                const game = ws.gameSession
                if (auditWindow.stack.busy) return
                driver.inspectPrivacyRequest()
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
                case 6: {
                    const options = deckLibrary.matchDecks(driver.format)
                    if (Date.now() - driver.entered > 5000
                            && !cardCatalog.busy && !options.some(deck => deck.ready)) {
                        auditProbe.record("deck-selection-blocked", {format: driver.format, decks: options,
                                          catalogError: cardCatalog.lastError})
                        throw new Error("No selectable deck after preparation: " + JSON.stringify(options))
                    }
                    if (driver.click("selectMatchDeckButton")) driver.next("Select matching cached deck")
                    break
                }
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
                    if (driver.seat > 1 && !(auditProbe.readShared("played" + (driver.seat - 1)) || {}).ready) break
                    if (!driver.runOperations()) break
                    driver.capture("02-after-draw")
                    driver.capture("02-permanent-tapped")
                    auditProbe.share("played" + driver.seat, {ready: true, cardId: driver.movedCard})
                    driver.step = 12
                    driver.entered = Date.now()
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
                    if (!(auditProbe.readShared("phase-cycle") || {}).ready) {
                        if (driver.startingSeat < 0) {
                            driver.startingSeat = game.activeSeat
                            const order = game.turnOrder
                            driver.require(order.length === driver.players, "Incomplete authoritative turn order")
                            driver.expectedNextSeat = order[(order.indexOf(game.activeSeat) + 1) % order.length]
                        }
                        if (driver.ownSeat() !== driver.startingSeat) break
                        if (driver.phaseStep === 0) {
                            if (driver.checkedClick("nextPhaseButton")) driver.phaseStep = 1
                            break
                        }
                        if (driver.phaseStep === 1) {
                            if (game.currentPhase !== "upkeep") break
                            for (let seatNumber = 1; seatNumber <= driver.players; ++seatNumber) {
                                const played = auditProbe.readShared("played" + seatNumber)
                                driver.require(gameTable.cardData(played.cardId).tapped === true,
                                               "Phase advancement unexpectedly untapped a card")
                            }
                            if (driver.checkedClick("nextTurnButton")) driver.phaseStep = 2
                            break
                        }
                        if (game.activeSeat !== driver.expectedNextSeat || game.currentPhase !== "untap") break
                        driver.capture("02-turn-advanced")
                        auditProbe.share("phase-cycle", {ready: true, previousSeat: driver.startingSeat,
                                                         nextSeat: game.activeSeat})
                        driver.checks.push({operation: "Advance phase and turn without automatic untap/draw"})
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
                    auditProbe.record("result", {status: "passed", evidence: "native-qt-input", scenario: "full-manual-match",
                                                format: driver.format, seat: driver.seat,
                                                requiredScreenshots: ["01-opening-table.png", "02-after-draw.png", "02-permanent-tapped.png",
                                                    "03-match-result.png", "04-returned-to-room.png", "02-full-zone-cycle.png"]
                                                    .concat(driver.shapePlan.map(card => "shape-" + card.tag + ".png"))
                                                    .concat(dragEdges.requiredScreenshots)
                                                    .concat(driver.format === "commander" || driver.format === "duel"
                                                            ? ["commander-damage-action.png"] : [])
                                                    .concat(Array.from({length: driver.players}, (_, index) => "privacy-seat-" + (index + 1) + ".png")),
                                                specialLayouts: driver.shapePlan,
                                                edgeDragCycle: dragEdges.requested,
                                                checks: driver.checks})
                    auditProbe.finish(0)
                    break
                }
            } catch (error) { driver.fail(String(error)) }
            finally { driver.dispatching = false }
        }
    }
}
