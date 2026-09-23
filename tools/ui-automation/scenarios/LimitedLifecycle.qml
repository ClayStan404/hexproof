// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import "NativeMotion.js" as Motion

Item {
    id: driver
    readonly property int seat: Number(auditProbe.environment("AUDIT_SEAT"))
    readonly property int players: Number(auditProbe.environment("AUDIT_PLAYERS"))
    readonly property bool forge: /-forge(?:-bo3)?$/.test(auditProbe.environment("AUDIT_VARIANT"))
    readonly property bool bo3: auditProbe.environment("AUDIT_VARIANT").endsWith("-bo3")
    readonly property string mode: auditProbe.environment("AUDIT_VARIANT").replace(/-forge(?:-bo3)?$/, "")
    readonly property bool cube: mode === "cube_draft"
    property int packSize: 15
    property var steps: []
    property var assertions: []
    property var screenshots: []
    property int index: 0
    property bool acted: false
    property bool acknowledged: false
    property bool dispatching: false
    property bool finished: false
    property bool assignedMatch: false
    property double started: Date.now()
    property double disconnectedAt: 0
    property string chosenId: ""
    property string movedId: ""
    property string deckFingerprint: ""
    property var expectedMain: []
    property var expectedBasics: []
    property var recoveryPack: []
    property var recoveryPool: []
    property int beforeBasics: 0
    property real poolScrollBeforePick: 0
    property double lastObservation: 0
    property var observedCards: []
    property var cardInputEvents: []

    function require(value, message) { if (!value) throw new Error(message + "; " + auditProbe.lastError) }
    function find(name, scope) { return auditProbe.find(scope || auditWindow, name) }
    function walk(root, predicate) {
        if (!root || !root.visible || !root.enabled) return null
        if (predicate(root)) return root
        for (const child of root.children || []) {
            const result = walk(child, predicate)
            if (result) return result
        }
        return null
    }
    // Viewport geometry is observable even when its center is not an input target.
    function view(name) { return walk(auditWindow.contentItem, item => item.objectName === name) }
    function builder() { return walk(auditWindow.contentItem, item => typeof item.selectionFingerprint === "function") }
    function sealedOpening() {
        const owner = builder()
        return owner ? Array.from(owner.data).find(item => item.objectName === "limitedSealedPackOpening") : null
    }
    function click(name, scrollName, scope) {
        const scroll = scrollName ? view(scrollName) : null
        if (!Motion.settled(scroll)) return false
        if (Motion.stopNeeded(scroll)) {
            require(auditProbe.click(scroll, 1, 1), "Cannot stop native wheel scrolling")
            auditProbe.record("stopped-scroll-" + index, {view:scrollName, cardSelection:false})
            return false
        }
        const target = find(name, scope)
        const position = target && scroll ? target.mapToItem(scroll, 0, 0) : null
        const fullyShown = !position || !scroll.cards || (position.y >= 0
            && position.y + Math.min(target.height, scroll.height) <= scroll.height)
        if (target && fullyShown) { require(auditProbe.click(target), "Cannot click " + name); return true }
        if (scroll) {
            const cards = scroll.cards || []
            const prefix = scroll.cardObjectPrefix || ""
            const index = cards.findIndex(card => prefix + (card.instanceId || card.name) === name)
            let top = Infinity
            if (index >= 0 && scroll.cellHeight > 0)
                top = Math.floor(index / Math.max(1, Math.floor(scroll.width / scroll.cellWidth))) * scroll.cellHeight
            else if (scroll.rows) {
                const row = scroll.rows.findIndex(value => prefix + (value.card.instanceId || value.card.name) === name)
                top = Math.max(0, row) * scroll.contentHeight / Math.max(1, scroll.count)
            }
            // Estimate several physical wheel notches for a distant row, then
            // observe again. Do not write contentY or click a thin clipped edge.
            const distance = top - scroll.contentY
            const delta = Number.isFinite(distance) ? Math.min(1440, Math.max(120,
                Math.round(Math.abs(distance) / 72) * 120)) : 720
            Motion.scrolled(scroll)
            require(auditProbe.wheel(scroll, distance < 0 ? delta : -delta), "Cannot scroll " + scrollName)
        }
        return false
    }
    function clickText(text, scrollName) {
        const scroll = scrollName ? view(scrollName) : null
        if (!Motion.settled(scroll)) return false
        if (Motion.stopNeeded(scroll)) {
            require(auditProbe.click(scroll, 1, 1), "Cannot stop form scrolling")
            return false
        }
        const target = walk(auditWindow.contentItem, item => item.text === text
            && typeof item.clicked === "function" && auditProbe.canInteract(item))
        if (target) { require(auditProbe.click(target), "Cannot click " + text); return true }
        if (scrollName) {
            Motion.scrolled(scroll)
            if (scroll) require(auditProbe.wheel(scroll, -260), "Cannot scroll to " + text)
        }
        return false
    }
    function typeField(name, value, scrollName, scope) {
        if (!click(name, scrollName, scope)) return false
        require(auditProbe.key(Qt.Key_A, Qt.ControlModifier), "Cannot select field")
        require(auditProbe.type(value), "Cannot type field")
        return true
    }
    function selectPhysicalCard(name, scrollName, selected) {
        const scroll = view(scrollName)
        const wasMoving = scroll && scroll.moving
        const tile = find(name)
        if (scroll && !observedCards.includes(scroll)) {
            observedCards.push(scroll)
            scroll.movingChanged.connect(() => {
                cardInputEvents.push({event:"moving=" + scroll.moving, at:Date.now(), view:scroll.objectName, y:scroll.contentY})
                cardInputEvents = cardInputEvents.slice(-100)
                auditProbe.record("card-input-events", cardInputEvents)
            })
        }
        if (tile && !observedCards.includes(tile)) {
            observedCards.push(tile)
            const save = event => {
                cardInputEvents.push({event:event, at:Date.now(), cardId:tile.card.instanceId, expectedId:chosenId,
                    moving:scroll.moving, y:scroll.contentY})
                cardInputEvents = cardInputEvents.slice(-100)
                auditProbe.record("card-input-events", cardInputEvents)
            }
            tile.activated.connect(() => save("activated"))
            for (const child of tile.children) {
                if (!child.clicked || !child.canceled || !child.pressedChanged) continue
                child.clicked.connect(() => save("clicked"))
                child.canceled.connect(() => save("canceled"))
                child.pressedChanged.connect(() => save("pressed=" + child.pressed))
            }
        }
        if (!click(name, scrollName)) return false
        if (selected()) return true
        require(wasMoving && scroll && !scroll.moving, "Card click did not select its physical card (moving before=" + wasMoving + ", after=" + (scroll && scroll.moving) + ")")
        auditProbe.record("card-click-stopped-scroll-" + index, {cardId:chosenId, selected:false,
            beforeMoving:wasMoving, afterMoving:scroll.moving})
        return false
    }
    function choose(name, choiceIndex, scrollName) {
        if (!click(name, scrollName)) return false
        require(auditProbe.key(Qt.Key_Home), "Cannot select first choice")
        for (let i = 0; i < choiceIndex; ++i) require(auditProbe.key(Qt.Key_Down), "Cannot choose option")
        require(auditProbe.key(Qt.Key_Return), "Cannot confirm option")
        return true
    }
    function add(name, actor, action, check, timeout) {
        steps.push({name:name, actor:actor, action:action, check:check || (() => true), timeout:timeout || 30000})
    }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        screenshots.push(name + ".png")
    }
    function share(name, value) { require(auditProbe.share(name, value), "Cannot share " + name) }
    function read(name) { return auditProbe.readShared(name) || ({}) }
    function screen() { return auditWindow.stack.currentItem }
    function ids(cards) { return Array.from(cards).map(card => card.instanceId).sort() }
    function same(left, right) { return JSON.stringify(Array.from(left).sort()) === JSON.stringify(Array.from(right).sort()) }
    function pairing() {
        return Array.from(tournament.pairings).find(p => p.playerAId === tournament.participantId || p.playerBId === tournament.participantId)
    }
    function playing() { return assignedMatch }
    function lockedDeckReady() {
        const room = ws.roomSession
        return ws.inRoom && room.seatIndex >= 0 && room.seats[room.seatIndex]
            && room.seats[room.seatIndex].deckSelected && room.deckFormat === "limited"
    }
    function ownHand() { return gameTable.zoneModel(ws.roomSession.seatIndex, "hand") }
    function verifyPool() {
        const expected = packSize * (mode === "set_sealed" ? 6 : 3)
        require(limited.pool.length === expected, "Wrong physical pool size")
        require(new Set(ids(limited.pool)).size === expected, "Duplicate pool instances")
        require(Array.from(limited.pool).every(card => card.name && card.setCode && card.collectorNumber), "Pool printing missing")
        for (const progress of limited.participants)
            for (const key of ["pool", "currentPack", "currentPacks", "mainboardInstanceIds", "basicLands"])
                require(progress[key] === undefined, "Private identities in public progress: " + key)
        share("pool-" + seat, {participantId:tournament.participantId, cards:Array.from(limited.pool)})
    }
    function pickScore(card, colors) {
        const offColor = String(card.cardColors || card.colors || "").split("").filter(c => !colors.includes(c)).length
        return offColor * 30 + (/Creature/.test(card.typeLine || "") ? 0 : 10)
            + (/Land/.test(card.typeLine || "") ? 50 : 0) + Math.abs(Number(card.manaValue || 0) - 3)
    }
    function preferredCards(cards) {
        const colors = ["WU", "RG", "BR"][seat - 1]
        return Array.from(cardCatalog.enrichLimitedCards(cards)).sort((a, b) => pickScore(a, colors) - pickScore(b, colors))
    }
    function planDraft() {
        for (let round = 1; round <= 3; ++round) {
            add("Observe draft round " + round, 0, () => {}, () => limited.packRound === round && limited.currentPack.length === packSize)
            add("Record private pack and public seat order " + round, 0, () => {
                require(limited.direction === (round === 2 ? -1 : 1), "Incorrect draft direction")
                share("pack-" + round + "-" + seat, {participantId:tournament.participantId, ids:ids(limited.currentPack)})
                capture("draft-round-" + round)
            })
            for (let pick = 0; pick < packSize; ++pick) {
                for (let actor = 1; actor <= players; ++actor) {
                    add("Select round " + round + " pick " + (pick + 1) + " seat " + actor, actor, () => {
                        if (!limited.currentPack.length) return false
                        chosenId = (forge ? preferredCards(limited.currentPack)[0] : limited.currentPack[0]).instanceId
                        return selectPhysicalCard("limitedDraftPackCard-" + chosenId, "limitedCurrentPackGrid", () => {
                            const view = walk(auditWindow.contentItem, item => typeof item.selectCard === "function"
                                && item.selectedInstanceId !== undefined)
                            return view && view.selection.includes(chosenId)
                        })
                    }, () => !!find("limitedConfirmPickButton"))
                    if (pick === packSize - 1) add("Inspect final card before confirmation " + round + "/" + actor, actor, () => {
                        require(limited.currentPack.length === 1 && limited.currentPack[0].instanceId === chosenId,
                            "The final card disappeared before confirmation")
                        require(!ids(limited.pool).includes(chosenId), "The final card was automatically added to the pool")
                        capture("draft-final-card-" + round)
                    })
                    add("Confirm physical pick " + round + "/" + (pick + 1) + "/" + actor, actor,
                        () => click("limitedConfirmPickButton"), () => ids(limited.pool).includes(chosenId))
                    if (pick === 0) add("Record first chosen instance " + round + "/" + actor, actor,
                        () => share("pick-" + round + "-" + seat, {id:chosenId}))
                }
                if (pick === 0) add("Verify actual pack passing in round " + round, 0, () => {}, () => {
                    if (limited.currentPack.length !== packSize - 1) return false
                    const order = Array.from(limited.participants).map(p => p.participantId)
                    const position = order.indexOf(tournament.participantId)
                    const source = order[(position - limited.direction + players) % players]
                    let sourceSeat = 0
                    for (let s = 1; s <= players; ++s) if (read("pack-" + round + "-" + s).participantId === source) sourceSeat = s
                    require(sourceSeat > 0, "Missing sending seat")
                    const expected = read("pack-" + round + "-" + sourceSeat).ids.filter(id => id !== read("pick-" + round + "-" + sourceSeat).id)
                    require(same(ids(limited.currentPack), expected), "Wrong physical pack passed")
                    return true
                })
                if (round === 2 && pick === 0) {
                    add("Interrupt transport with an unpicked second-round pack", 2, () => {
                        recoveryPack = ids(limited.currentPack); recoveryPool = ids(limited.pool)
                        disconnectedAt = Date.now()
                        require(auditProbe.interruptTransport(ws), "Cannot interrupt isolated draft transport")
                    }, () => Date.now() - disconnectedAt > 600 && ws.connected && limited.stage === "draft"
                        && limited.currentPack.length === recoveryPack.length, 60000)
                    add("Verify recovered pack and prior picks", 2, () => {
                        require(same(ids(limited.currentPack), recoveryPack) && same(ids(limited.pool), recoveryPool),
                            "Draft reconnect changed private cards")
                        capture("recovered-draft")
                    })
                }
            }
        }
    }
    function plan() {
        require(players === 3, "This lifecycle requires three isolated clients")
        require(["set_sealed", "set_draft", "cube_draft"].includes(mode), "Unsupported lifecycle mode")
        if (cube) {
            const cubes = deckLibrary.matchDecks("cube", true)
            require(cubes.length === 1 && cubes[0].exactPrintings && cubes[0].mainCount === 135,
                "Expected a valid saved 135-card exact-printing Cube fixture")
        }
        if (!cube) {
            const set = cardCatalog.limitedSets().find(value => value.id === "EOE")
            require(!!set, "Installed EOE product required")
            packSize = cardCatalog.limitedProduct(set.productId).cardsPerPack
        }
        auditProbe.fixture("limited-lifecycle", {mode:mode, players:players, cardsPerPack:packSize,
            description:"Native UI creates the event, makes every draft pick and submits pool-contained 40-card decks. Only catalog/cache and a saved 135-card Cube are seeded; no event or pack state is injected."})
        for (let actor = 1; actor <= players; ++actor) {
            add("Connect form " + actor, actor, () => click("mainMenuConnectButton"), () => !!find("connectSubmitButton"))
            add("Connect isolated player " + actor, actor, () => click("connectSubmitButton"), () => ws.connected)
        }
        if (cube) {
            add("Open Cube creation", 1, () => click("mainMenuCreateRoomButton"), () => !!find("roomNameField"))
            add("Name Cube room", 1, () => typeField("roomNameField", "Native Cube lifecycle"))
            add("Select regular Cube", 1, () => choose("roomFormatSelector", screen().selectableFormatOptions.findIndex(v => v.value === "cube")),
                () => screen().isCubeFormat && !screen().commanderCube)
            add("Set three Cube seats", 1, () => typeField("cubePlayerCapField", "3", "createRoomBody"))
            if (forge) add("Choose Forge Cube rules", 1, () => clickText("Forge rules", "createRoomBody"), () => screen().rulesMode === "forge")
            add("Create Cube", 1, () => click("createRoomSubmitButton", "createRoomBody"), () => tournament.inTournament)
        } else {
            add("Open Events", 1, () => click("mainMenuEventsButton"), () => !!find("tournamentCreateButton"))
            add("Open tournament form", 1, () => click("tournamentCreateButton"), () => !!find("tournamentNameField"))
            add("Name Limited event", 1, () => typeField("tournamentNameField", "Native " + mode))
            add("Select Limited mode", 1, () => choose("tournamentEventTypeSelector", mode === "set_sealed" ? 1 : 2))
            add("Find installed EOE", 1, () => typeField("limitedSetSearchField", "EOE", "tournamentCreateBody"),
                () => find("limitedSetSelector") && find("limitedSetSelector").currentValue === "EOE")
            add("Choose match length", 1, () => clickText(bo3 ? "BO 3" : "BO 1", "tournamentCreateBody"),
                () => screen().matchMode === (bo3 ? "bo3" : "bo1"))
            add("Set three event seats", 1, () => typeField("tournamentPlayerCapField", "3", "tournamentCreateBody"))
            if (forge) add("Choose Forge event rules", 1, () => clickText("Forge rules", "tournamentCreateBody"), () => screen().rulesMode === "forge")
            add("Create Limited tournament", 1, () => click("tournamentCreateSubmitButton", "tournamentCreateBody"), () => tournament.inTournament)
        }
        if (forge) add("Verify immutable Forge event mode", 1, () => {
            require(tournament.rulesMode === "forge", "Event lost Forge selection")
            capture("forge-event-mode")
        })
        add("Share public event code", 1, () => share("event", {id:tournament.tournamentId}))
        for (let actor = 2; actor <= players; ++actor) {
            add("Open event join " + actor, actor, () => click(cube ? "mainMenuJoinRoomButton" : "mainMenuEventsButton"),
                () => !!find(cube ? "joinRoomCodeField" : "tournamentCodeField"))
            add("Enter public event code " + actor, actor,
                () => typeField(cube ? "joinRoomCodeField" : "tournamentCodeField", read("event").id))
            add("Join event view " + actor, actor, () => click(cube ? "joinRoomSubmitButton" : "tournamentOpenButton"),
                () => tournament.inTournament && tournament.tournamentId === read("event").id)
        }
        for (let actor = 1; actor <= players; ++actor) {
            if (!cube) add("Register player " + actor, actor, () => click("registerLimitedPlayerButton", "tournamentEventDeskScroll"),
                () => tournament.participantId.length > 0)
            add("Share participant identity " + actor, actor, () => share("seat-" + seat, {id:tournament.participantId}))
            add("Ready player " + actor, actor, () => cube ? click("cubeReadyButton") : clickText("Check in", "tournamentEventDeskScroll"),
                () => cube ? screen().selfReady : screen().selfCheckedIn)
        }
        add("Start distribution", 1, () => click(cube ? "cubeStartDraftButton" : "startTournamentButton", cube ? "" : "tournamentEventDeskScroll"),
            () => tournament.stage === (mode === "set_sealed" ? "deck_building" : "draft"))
        if (mode !== "set_sealed") planDraft()
        add("Observe complete private pools", 0, () => {}, () => limited.stage === "deck_building" && !!builder())
        add("Record physical pools", 0, verifyPool)
        add("Verify cross-seat physical conservation", 0, () => {
            const all = []
            for (let s = 1; s <= players; ++s) all.push(...read("pool-" + s).cards)
            require(new Set(ids(all)).size === all.length, "Physical cards duplicated across seats")
            if (cube) {
                const cubes = deckLibrary.matchDecks("cube", true)
                require(cubes.length === 1 && cubes[0].exactPrintings, "Expected the isolated exact-printing Cube")
                const source = deckLibrary.cubeProduct(cubes[0].deckId).sheets[0].cards
                const actual = ({})
                for (const card of all) { const key = card.name + "|" + card.setCode + "|" + card.collectorNumber; actual[key] = (actual[key] || 0) + 1 }
                for (const card of source) require(actual[card.name + "|" + card.setCode + "|" + card.collectorNumber] === card.weight, "Cube stock changed")
                require(all.length === 135, "Cube did not exhaust exact stock")
            }
        })
        for (let actor = 1; actor <= players; ++actor) {
            if (mode === "set_sealed") {
                add("Show the six server-generated boosters " + actor, actor, () => {
                    const opening = sealedOpening()
                    if (opening && opening.opened) return true
                    return click("limitedSealedPacksButton")
                }, () => !!find("packOpeningBooster"))
                add("Inspect Sealed booster wrapper " + actor, actor, () => capture("sealed-booster"))
                add("Open the first Sealed booster " + actor, actor, () => click("packOpeningBooster"),
                    () => sealedOpening().stage === 1)
                add("Reveal the first Sealed booster " + actor, actor, () => click("packOpeningRevealAllButton"),
                    () => sealedOpening().currentPackRevealed)
                add("Check exact opened identities " + actor, actor, () => {
                    const opening = sealedOpening()
                    require(opening.packs.length === 6, "Sealed opening lost booster boundaries")
                    require(same(ids(opening.packs[0].cards), ids(Array.from(limited.pool).slice(0, packSize))),
                        "Animation changed the server-generated first booster")
                    capture("sealed-first-booster")
                })
                add("Skip the remaining Sealed animation " + actor, actor, () => click("packOpeningSkipButton"),
                    () => !find("packOpeningSkipButton"))
            }
            if (mode !== "set_sealed") add("Start an empty main deck " + actor, actor, () => click("rebuildFromPoolButton"),
                () => !find("rebuildFromPoolButton"))
            for (let cardIndex = 0; cardIndex < 23; ++cardIndex) {
                add("Choose pool card " + (cardIndex + 1) + " for seat " + actor, actor, () => {
                    const pool = view("limitedSideboardGrid")
                    if (!pool) return false
                    const cards = forge ? preferredCards(pool.cards) : pool.cards
                    const card = cards.find(value => !/\bLand\b/i.test(value.typeLine || "")) || cards[0]
                    require(!!card, "No available pool card")
                    chosenId = card.instanceId
                    return selectPhysicalCard("limitedCardTile-" + chosenId, "limitedSideboardGrid",
                        () => builder().cardSelected(chosenId))
                }, () => builder().cardSelected(chosenId))
            }
            add("Select a card below the first pool rows " + actor, actor, () => {
                const pool = view("limitedSideboardGrid")
                const selected = builder().mainDeckCards
                const cards = Array.from(pool.cards).filter(card => !selected.some(value =>
                    value.name === card.name && value.setCode === card.setCode && value.collectorNumber === card.collectorNumber))
                require(cards.length > 0, "No distinct remaining printing for the scroll probe")
                chosenId = cards[cards.length - 1].instanceId
                poolScrollBeforePick = pool.contentY - pool.originY
                return selectPhysicalCard("limitedCardTile-" + chosenId, "limitedSideboardGrid",
                    () => builder().cardSelected(chosenId))
            }, () => builder().cardSelected(chosenId))
            add("Verify the pool keeps its browsing position " + actor, actor, () => {
                const pool = view("limitedSideboardGrid")
                const expected = Math.max(0, Math.min(poolScrollBeforePick, pool.contentHeight - pool.height))
                auditProbe.record("construction-scroll", {before:poolScrollBeforePick, after:pool.contentY - pool.originY,
                    expected:expected, contentHeight:pool.contentHeight, height:pool.height, cardId:chosenId})
                require(poolScrollBeforePick > 0 && Math.abs(pool.contentY - pool.originY - expected) < 1,
                    "Selecting a card reset the pool scroll")
                capture("construction-scroll-preserved")
            })
            add("Return that exact card to the pool " + actor, actor, () => click("compactCard-" + chosenId, "limitedMainDeckGrid"),
                () => !builder().cardSelected(chosenId) && builder().selectedPoolCount === 23)
            add("Check automatic basics and deck workspace " + actor, actor, () => {
                require(builder().selectedPoolCount === 23 && builder().selectedCount === 40, "Automatic basics did not complete 40 cards")
                if (!cube) {
                    for (const name of builder().basicNames) {
                        const options = cardCatalog.printings(name)
                        if (options.some(card => card.setCode === "EOE"))
                            require(builder().basicPrinting(name).setCode === "EOE", "Basic land does not match the event set")
                    }
                }
                capture("construction")
            })
            add("Drag one exact selected card back to the pool " + actor, actor, () => {
                const list = view("limitedMainDeckGrid")
                if (!list || !list.rows.length) return false
                if (!Motion.settled(list)) return false
                movedId = list.rows.find(row => row.card.instanceId).card.instanceId
                const source = find("compactCard-" + movedId)
                const target = find("limitedSideboardGrid")
                if (!source) {
                    Motion.scrolled(list)
                    require(auditProbe.wheel(list, 260), "Cannot scroll to the main-deck drag source")
                    return false
                }
                if (!target) return false
                require(auditProbe.drag(source, target), "Cannot drag the selected physical card")
                return true
            }, () => !builder().cardSelected(movedId) && builder().selectedPoolCount === 22)
            add("Restore the same card " + actor, actor, () => click("limitedCardTile-" + movedId, "limitedSideboardGrid"),
                () => builder().cardSelected(movedId) && builder().selectedCount === 40)
            add("Open ordinary basics " + actor, actor, () => click("limitedBasicLandsButton"), () => !!find("limitedBasicLandsDone"))
            add("Add a virtual Plains " + actor, actor, () => { beforeBasics = builder().basicValue("Plains"); return click("limitedBasicLandAdd-Plains", "limitedBasicLandScroll") },
                () => builder().basicValue("Plains") === beforeBasics + 1 && builder().selectedCount === 41 && !builder().autoBasicLands)
            add("Remove the virtual Plains " + actor, actor, () => click("limitedBasicLandRemove-Plains", "limitedBasicLandScroll"),
                () => builder().selectedCount === 40)
            add("Close ordinary basics " + actor, actor, () => click("limitedBasicLandsDone"), () => !find("limitedBasicLandsDone"))
            add("Record local construction " + actor, actor, () => {
                deckFingerprint = builder().selectionFingerprint()
                expectedMain = Object.keys(builder().selectedCards).sort()
                expectedBasics = builder().basicNames.map(name => Object.assign({name:name, count:builder().basicValue(name)}, builder().basicPrinting(name))).filter(v => v.count > 0)
            })
            if (actor === 2) {
                add("Interrupt test transport during local building", actor, () => {
                    disconnectedAt = Date.now()
                    require(auditProbe.interruptTransport(ws), "Cannot interrupt isolated transport")
                }, () => Date.now() - disconnectedAt > 600 && ws.connected && limited.tournamentId === read("event").id && !!builder(), 60000)
                add("Verify recovered private pool and pending deck", actor, () => {
                    require(same(ids(limited.pool), ids(read("pool-" + seat).cards)), "Reconnect changed own physical pool")
                    require(builder().selectionFingerprint() === deckFingerprint, "Reconnect discarded pending construction")
                    capture("recovered-construction")
                })
            }
            add("Submit the physical deck " + actor, actor, () => click("limitedSubmitDeckButton"),
                () => limited.deckSubmitted && same(limited.mainboardInstanceIds, expectedMain))
            add("Verify accepted partition " + actor, actor, () => {
                require(same(Array.from(limited.basicLands).map(value => value.name + ":" + value.count),
                    expectedBasics.map(value => value.name + ":" + value.count)), "Server changed ordinary basics")
                for (const expected of expectedBasics) {
                    const actual = Array.from(limited.basicLands).find(card => card.name === expected.name)
                    require(actual && actual.setCode === expected.setCode && actual.collectorNumber === expected.collectorNumber,
                        "Server changed chosen basic land printing")
                }
                require(same(ids(limited.pool), ids(read("pool-" + seat).cards)), "Submitting changed the pool")
                auditProbe.record("accepted-deck", {mainboard:Array.from(limited.mainboardInstanceIds), basics:Array.from(limited.basicLands), pool:ids(limited.pool)})
            })
        }
        if (cube) {
            add("Observe unpaired free play", 0, () => {}, () => tournament.stage === "competition" && tournament.pairings.length === 0)
            add("Open the opponent list", 1, () => !screen().editingDeck || click("cubeDeckModeButton"),
                () => !screen().editingDeck && !!find("cubeOpponentList"))
            add("Invite another player", 1, () => click("cubeInvite-" + read("seat-2").id, "cubeOpponentList"), () => !!pairing())
            add("Accept invitation", 2, () => click("cubeAcceptInviteButton"), () => !!pairing() && pairing().status !== "invited")
        } else {
            add("Open event desk after deck building", 1, () => click("limitedEventDeskButton"), () => !!find("openLimitedCompetitionButton"))
            add("Publish round one", 1, () => click("openLimitedCompetitionButton", "tournamentEventDeskScroll"), () => tournament.stage === "competition")
        }
        add("Observe published pairings", 0, () => {}, () => tournament.stage === "competition" && tournament.pairings.length > 0)
        add("Record the assigned match or bye", 0, () => { const p = pairing(); assignedMatch = !!p && !p.bye })
        for (let actor = 1; actor <= players; ++actor) {
            add("Enter assigned table " + actor, actor, () => !playing() || ws.inRoom
                || (cube ? click("cubeOpenMatchButton") : clickText(pairing().roomId ? "Return to match" : "Open match")),
                () => !playing() || lockedDeckReady())
        }
        for (let actor = 1; actor <= players; ++actor) {
            add("Ready with the locked pool deck " + actor, actor, () => !playing() || click("playerReadyButton"))
        }
        if (forge) {
            add("Verify Forge Limited handoff", 0, () => {}, () => {
                if (!playing()) return true
                if (!ws.rulesSession.active || !find("forgeDuelTable")) return false
                require(ws.roomSession.rulesMode === "forge", "Pairing lost Forge mode")
                require(ws.roomSession.deckFormat === "limited", "Pairing lost Limited format")
                require(ws.rulesSession.zoneCount(ws.roomSession.seatIndex, "hand")
                    + ws.rulesSession.zoneCount(ws.roomSession.seatIndex, "library") === 40,
                    "Wrong initial 40-card deck before opening decisions")
                capture("limited-forge-table")
                return true
            }, 60000)
            return
        }
        add("Verify table handoff and private hands", 0, () => {}, () => {
            if (!playing()) return true
            if (!gameTable.hasSnapshot || !find("increaseLifeButton" + ws.roomSession.seatIndex)) return false
            require(ws.roomSession.rulesMode === "manual", "Limited entered an unsupported rules mode")
            require(ownHand().count === 7 && gameTable.seatData(ws.roomSession.seatIndex).libraryCount === 33, "Locked 40-card deck did not load")
            require(gameTable.zoneModel(1 - ws.roomSession.seatIndex, "hand").count === 0, "Opponent hand identities exposed")
            capture("limited-table")
            share("playing-" + seat, {seatIndex:ws.roomSession.seatIndex, roomId:ws.roomSession.roomId})
            return true
        })
        for (let actor = 1; actor <= players; ++actor)
            add("Draw from the loaded deck " + actor, actor, () => !playing() || auditProbe.key(Qt.Key_D, Qt.ControlModifier | Qt.AltModifier),
                () => !playing() || ownHand().count === 8 && gameTable.seatData(ws.roomSession.seatIndex).libraryCount === 32)
        for (let actor = 1; actor <= players; ++actor) {
            add("Open concession on table seat zero " + actor, actor, () => !playing() || ws.roomSession.seatIndex !== 0
                || auditProbe.key(Qt.Key_Q, Qt.ControlModifier | Qt.ShiftModifier),
                () => !playing() || ws.roomSession.seatIndex !== 0 || !!find("confirmButton"))
            add("Confirm bounded match result " + actor, actor, () => !playing() || ws.roomSession.seatIndex !== 0 || click("confirmButton"))
        }
        add("Observe match result", 0, () => {}, () => {
            if (!playing()) { capture("limited-bye-or-free-seat"); return true }
            const game = ws.gameSession
            if (!game.finished || !find("resultReturnToRoomButton")) return false
            require(game.result.winnerSeat === 1 && game.result.matchFinished, "Concession result disagrees between clients")
            capture("limited-match-result")
            return true
        })
    }
    Loader {
        id: forgeDriver
        active: false
        sourceComponent: Component { ForgeDuelMatch { existingLimitedMatch: true } }
    }
    Timer {
        interval: 250; repeat: true; running: driver.finished && driver.forge && !driver.assignedMatch
        onTriggered: if (driver.read("forge-host-finished").done) {
            driver.capture("limited-unpaired-result")
            auditProbe.record("result", {status:"passed", scenario:"limited-forge-bye", seat:driver.seat,
                mode:driver.mode, assertions:driver.assertions, requiredScreenshots:driver.screenshots})
            stop(); auditProbe.finish(0)
        }
    }
    function finish(error) {
        if (finished) return
        finished = true
        if (error) {
            if (auditProbe.capture(auditWindow, "failure")) screenshots.push("failure.png")
            auditProbe.record("failure-state", auditProbe.observe(auditWindow))
            auditProbe.record("failure-private-state", {stage:limited.stage, serverError:ws.lastError,
                pool:ids(limited.pool), mainboard:Array.from(limited.mainboardInstanceIds), basics:Array.from(limited.basicLands),
                expectedMain:expectedMain, expectedBasics:expectedBasics, room:{inRoom:ws.inRoom,
                    seatIndex:ws.roomSession.seatIndex, seats:ws.roomSession.seats, deckFormat:ws.roomSession.deckFormat}})
        }
        if (!error && forge) {
            auditProbe.record("limited-lifecycle-setup", {mode:mode, seat:seat, assertions:assertions,
                requiredScreenshots:screenshots, deck:limited.mainboardInstanceIds, basics:limited.basicLands})
            if (playing()) forgeDriver.active = true
            return
        }
        auditProbe.record("result", {status:error ? "failed" : "passed",
            evidence:auditProbe.environment("AUDIT_OS_INPUT_HELPER") ? "system-input" : "native-qt-input", scenario:"limited-lifecycle",
            mode:mode, seat:seat, error:error || "", pendingStep:index < steps.length ? steps[index].name : "",
            assertions:assertions, requiredScreenshots:screenshots,
            coverage:forge ? "Three-client Forge Limited setup; completed assertions are listed individually. A setup failure is not a completed game."
                : "Three-client registration, physical distribution, every draft pick, pass direction, pool conservation, 40-card construction, local-edit recovery, locked-deck table handoff and one BO1 concession result. No full Swiss-event completion or automatic Oracle resolution."})
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
                if (step.actor === driver.seat && !driver.acknowledged && !auditWindow.active)
                    driver.require(auditProbe.activate(), "Cannot focus the acting player")
                if (ownsStep && Date.now() - driver.lastObservation > 2000) {
                    const scrolls = ["limitedSideboardGrid", "limitedMainDeckGrid", "limitedCurrentPackGrid", "tournamentCreateBody"].map(name => {
                        const view = driver.walk(auditWindow.contentItem, item => item.objectName === name)
                        return view ? {name:name, moving:view.moving, flicking:view.flicking, dragging:view.dragging,
                            y:view.contentY, originY:view.originY, contentHeight:view.contentHeight, height:view.height,
                            atYEnd:view.atYEnd, atYBeginning:view.atYBeginning} : null
                    }).filter(value => value !== null)
                    auditProbe.record("limited-live-ui", {step:step.name, acted:driver.acted, selectedId:driver.chosenId,
                        selected:driver.builder() ? driver.builder().selectedPoolCount : 0, scrolls:scrolls})
                    driver.lastObservation = Date.now()
                }
                driver.require(Date.now() - driver.started < step.timeout + (ownsStep ? 0 : 5000), "Timed out: " + step.name)
                if (auditWindow.stack.busy) return
                if (!driver.acknowledged) {
                    if (step.actor === 0 || step.actor === driver.seat) {
                        if (!driver.acted) { if (step.action() === false) return; driver.acted = true }
                        if (!step.check()) return
                    }
                    driver.share("phase-" + driver.index + "-seat-" + driver.seat, {ready:true})
                    driver.acknowledged = true
                }
                for (let actor = 1; actor <= driver.players; ++actor)
                    if (!driver.read("phase-" + driver.index + "-seat-" + actor).ready) return
                driver.assertions.push({step:step.name, actor:step.actor, verifiedLocally:step.actor === 0 || step.actor === driver.seat,
                    elapsedMs:Date.now() - driver.started})
                driver.index++; driver.acted = false; driver.acknowledged = false; driver.started = Date.now()
                auditProbe.record("progress", {index:driver.index, next:driver.index < driver.steps.length ? driver.steps[driver.index].name : "complete"})
            } catch (error) { driver.finish(String(error)) }
            finally { auditProbe.endInput(); driver.dispatching = false }
        }
    }
}
