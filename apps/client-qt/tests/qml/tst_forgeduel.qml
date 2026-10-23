// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"
import "../../qml/screens"
import "../../../../tools/ui-automation/scenarios/ForgeNecrodominanceStudy.js" as NecroStudy

TestCase {
    id: testCase
    name: "ForgeDuel"
    when: windowShown
    property int serial: 1000
    QtObject {
        id: soundRecorder
        property var cues: []
        function play(cue) { cues = cues.concat([cue]) }
    }
    ApplicationWindow {
        id: window
        width: 1600; height: 1000; visible: true
        property bool feedbackInteractionOpen: false
        property var openedScreen: ({})
        function pushScreen(url, properties) { openedScreen = {url, properties} }
        QtObject {
            id: room
            property int maxSeats: 2
            property string roomId: "DUEL01"
            property string roomName: "Forge test"
            property string role: "player"
            property int seatIndex: 0
            property bool host: true
            property string phase: "started"
            property string matchMode: "bo1"
            property string format: "modern"
            property string deckFormat: "modern"
            property string hostingMode: "server"
            property bool hostConnected: true
            property var hostStatus: ({migrating:false})
            property string aiSource: ""
            property bool actionClockEnabled: false
            property var actionClockMs: []
            property int actionClockRunning: -1
            property var aiStatus: ({})
            property bool spectatorsSeeHands: false
            property var seats: []
            property var players: []
        }
        QtObject {
            id: match
            property int gameNumber: 1
            property var score: [0, 0]
            property var result: ({})
            property var sideboard: ({})
            property bool sideboarding: false
        }
        QtObject {
            id: transport
            property var rulesSession: testRulesPrompt.session
            property var roomSession: room
            property var gameSession: match
            property bool inRoom: true
            property bool rulesResponsePending: false
            property string peerTransportState: "off"
            property bool peerTransportAvailable: true
            property bool directPeerEnabled: false
            property var peerRequests: []
            function setDirectPeerEnabled(enabled, retry) {
                peerRequests = peerRequests.concat([{enabled:enabled, retry:retry === true}])
                directPeerEnabled = enabled
                peerTransportState = enabled ? "waiting" : "off"
            }
            property string lastError: ""
            property var responses: []
            property int modelRetries: 0
            function retryModelOpponent() { ++modelRetries }
            function respondRulesPrompt(id, response) {
                responses = responses.concat([{id:id, response:response}]); rulesResponsePending = true
            }
            function respondRulesPromptWithTargets(id, response, targets) {
                responses = responses.concat([{id:id, response:response, targets:targets}]); rulesResponsePending = true
            }
            function respondRulesPromptWithCards(id, response, cards) {
                responses = responses.concat([{id:id, response:response, cards:cards}]); rulesResponsePending = true
            }
            function respondRulesPromptWithScry(id, piles) {
                responses = responses.concat([{id:id, piles:piles}]); rulesResponsePending = true
            }
            function respondRulesPromptWithOrder(id, order) {
                responses = responses.concat([{id:id, order:order}]); rulesResponsePending = true
            }
            function respondRulesPromptWithAssignments(id, assignments) {
                responses = responses.concat([{id:id, assignments:assignments}]); rulesResponsePending = true
            }
            function respondRulesPromptWithDamage(id, assignments) {
                responses = responses.concat([{id:id, damage:assignments}]); rulesResponsePending = true
            }
            function respondRulesPromptWithChoices(id, choices) {
                responses = responses.concat([{id:id, choices:choices}]); rulesResponsePending = true
            }
            function respondRulesPromptWithNumber(id, value) {
                responses = responses.concat([{id:id, number:value}]); rulesResponsePending = true
            }
        }
        QtObject {
            id: catalog
            property string language: "en"
            property int imageRevision: 0
            property var names: ({})
            property var requested: []
            property string imageOverride: ""
            property var faceImages: ({})
            property var tableFaceImages: ({})
            property var artFrames: ({})
            property var artFrameRequests: []
            function cardArtFrame(name, set, number) {
                artFrameRequests.push(name)
                return artFrames[name] || "standard"
            }
            signal catalogChanged()
            function tableImageSource(name, set, number) { requested.push(name); return tableFaceImages[name] || "" }
            function imageSource(name, set, number) { requested.push(name); return faceImages[name] || imageOverride }
            property var typeOverrides: ({})
            property var faceOverrides: ({})
            property var faceRequests: []
            function cardFaces(name, setCode, collectorNumber) {
                faceRequests.push(name)
                return faceOverrides[name] || []
            }
            signal cardAvailable(string requestedName, string localizedName, string typeLine,
                                 string imagePath, string setCode, string collectorNumber)
            signal cardCacheFinished(string requestedName, string setCode, string collectorNumber, bool success)
            signal artCacheContentsChanged()
            function cardTypeLine(name) {
                if (typeOverrides[name]) return typeOverrides[name]
                if (name === "Plains" || name === "Ugin's Labyrinth") return "Land"
                if (name === "Test Walker") return "Planeswalker"
                if (name === "Test Battle") return "Battle"
                return "Creature"
            }
            property var nameRequests: []
            function cardDisplayName(name) {
                nameRequests.push(name)
                return language === "zh" ? names[name] || name : name
            }
            property var rules: ({})
            function cardRulesText(name, setCode, collectorNumber, textLanguage) {
                const selected = textLanguage || language
                const table = rules[selected] || {}
                return table[name] || ""
            }
        }
        RulesTable {
            id: table
            anchors.fill: parent
            wsModel: transport
            cardCatalogModel: catalog
            gameTableModel: testGameTable
            sideboardTableModel: testSideboardTable
        }
    }
    function card(id, seat, name, creature) {
        return {id:id, ownerSeat:seat, controllerSeat:seat, visible:true, identity:{name:name},
            power:creature ? "2" : "", toughness:creature ? "2" : ""}
    }
    function token(id, seat, name, creature) {
        const row = card(id, seat, name, creature)
        row.identity.token = true
        return row
    }
    function snapshot(handCount, creatureCount, distinctCreatures) {
        const hand = [], creatures = []
        for (let i = 0; i < (handCount || 1); ++i) hand.push(card("hand-" + i, 0, "Plains", false))
        for (let i = 0; i < (creatureCount || 1); ++i)
            creatures.push(card("own-" + i, 0, distinctCreatures ? ("Bear " + i) : "Grizzly Bears", true))
        return {roomId:"DUEL01", gameId:"duel-game", turn:3, step:"main1", activeSeat:0, prioritySeat:0,
            players:[{seat:0, name:"Alice", life:20}, {seat:1, name:"Bob", life:20}],
            zones:[{zone:"hand", ownerSeat:0, count:hand.length, cards:hand},
                {zone:"hand", ownerSeat:1, count:7, cards:[]},
                {zone:"library", ownerSeat:0, count:50, cards:[]},
                {zone:"library", ownerSeat:1, count:49, cards:[]},
                {zone:"battlefield", ownerSeat:0, count:creatures.length + 1,
                    cards:creatures.concat([card("land", 0, "Plains", false)])},
                {zone:"battlefield", ownerSeat:1, count:1, cards:[card("opponent", 1, "Grizzly Bears", true)]}],
            stack:[]}
    }
    function prompt(kind, extra) {
        transport.rulesResponsePending = false
        const data = Object.assign({roomId:"DUEL01", gameId:"duel-game", pending:true, supported:true,
            promptId:++serial, kind:kind, title:"Choose", detail:"", options:[], choices:[], cards:[],
            targets:[], contextCards:[], contextTargets:[], combatSources:[], combatTargets:[],
            damageTargets:[], scryDestinations:[], totalDamage:0}, extra || {})
        verify(testRulesPrompt.applyPrompt(data))
        waitForRendering(table)
    }
    function item(name) {
        let found = null
        tryVerify(() => {
            const popup = findChild(table, "forgeZonePopup")
            found = findChild(table, name) || (popup ? findChild(popup.contentItem, name) : null)
            return found !== null
        }, 5000, name)
        return found
    }
    function showPile(frontId) {
        const badge = item("forgeCardStackCount-" + frontId)
        if (!badge.parent.fanned)
            mouseClick(badge)
        waitForRendering(table)
    }
    function hidePile(frontId) {
        const badge = item("forgeCardStackCount-" + frontId)
        if (badge.parent.fanned)
            mouseClick(badge)
        waitForRendering(table)
    }
    function openSettings() {
        if (!table.presentation.modalOpen)
            mouseClick(item("forgeGameMenu"))
        tryCompare(table.presentation, "modalOpen", true)
        tryCompare(item("forgeGameDrawer"), "visible", true)
    }
    function closeSettings() {
        if (item("forgeGameDrawer").visible) {
            keyClick(Qt.Key_Escape)
            tryCompare(item("forgeGameDrawer"), "visible", false)
            tryCompare(table.presentation, "modalOpen", false)
        }
    }
    function action(kind, id) {
        prompt("chooseAction", {options:[{responseId:"opaque-play", kind:kind, cardId:id, label:"Play"},
            {responseId:"$pass", kind:"pass", label:"Pass"}]})
    }
    function combat(kind, capacity, aim) {
        const attacking = kind === "chooseAttackers"
        const ids = ["opaque-target"]
        const targets = [{responseId:"opaque-target", kind:attacking ? "player" : "attacker",
            objectId:attacking ? "" : "opponent", seat:attacking ? 1 : -1,
            label:"Opponent", minAssignments:0, maxAssignments:8}]
        // A second destination keeps the aim step. One destination assigns immediately.
        if (aim) {
            ids.push("alternate")
            targets.push({responseId:"alternate", kind:attacking ? "planeswalker" : "attacker",
                objectId:attacking ? "missing-walker" : "missing-attacker",
                label:"Alternative target", minAssignments:0, maxAssignments:1})
        }
        prompt(kind, {combatSources:[{responseId:"opaque-source", objectId:"own-0", label:"Bear", name:"Grizzly Bears",
            validTargetIds:ids, mustAssignIfAble:false, maxAssignments:capacity || 1}],
            combatTargets:targets})
    }
    function init() {
        window.feedbackInteractionOpen = false
        table.replayMode = false
        window.width = 1600; window.height = 1000
        window.requestActivate(); tryCompare(window, "active", true)
        Theme.uiScale = 1
        Theme.motionEnabled = false
        catalog.typeOverrides = ({})
        catalog.faceOverrides = ({})
        catalog.faceImages = ({})
        catalog.tableFaceImages = ({})
        catalog.artFrames = ({})
        catalog.artFrameRequests = []
        catalog.faceRequests = []
        room.role = "player"; room.seatIndex = 0; room.spectatorsSeeHands = false
        room.format = "modern"; room.deckFormat = "modern"; room.maxSeats = 2
        room.hostingMode = "server"
        room.aiSource = ""
        room.actionClockEnabled = false
        room.actionClockMs = []
        room.actionClockRunning = -1
        room.seats = []
        room.players = []
        room.matchMode = "bo1"
        match.gameNumber = 1; match.score = [0, 0]
        match.sideboarding = false; transport.inRoom = true
        transport.responses = []; transport.rulesResponsePending = false
        transport.peerTransportAvailable = true; transport.directPeerEnabled = false
        transport.peerTransportState = "off"; transport.peerRequests = []
        testRulesPrompt.clear()
        verify(testRulesPrompt.applySnapshot(snapshot()))
        table.showGameLogRail = false
        table.inspector.clear()
        if (table.gameLogRail && table.gameLogRail.resetFloatingPosition)
            table.gameLogRail.resetFloatingPosition()
        if (table.presentation && table.presentation.modalOpen)
            closeSettings()
        table.priority.setFullControl(false)
        preferences.forgePhaseStops = ({})
        prompt("diceRolled", {options:[{responseId:"$ack", kind:"acknowledge", label:"Continue"}]})
    }
    function cleanup() {
        window.feedbackInteractionOpen = false
        const popup = item("forgeZonePopup")
        popup.close()
        tryCompare(popup, "visible", false)
        table.inspector.clear(); testRulesPrompt.clear()
        testTranslations.setLanguage("en")
        catalog.language = "en"
        catalog.names = ({})
        catalog.nameRequests = []
        catalog.rules = ({})
        catalog.imageOverride = ""
    }

    function test_actionClockShowsAuthoritativeTimeAndOnlyRunningSeatTicks() {
        room.actionClockEnabled = true
        room.actionClockMs = [60000, 120000]
        compare(table.presentation.actionClockText(0), "1:00")
        compare(table.presentation.actionClockText(1), "2:00")
        verify(item("forgeActionClock-0").visible)
        verify(item("forgeActionClock-1").visible)
        room.actionClockRunning = 0
        table.presentation.actionClockMarked = Date.now() - 1100
        table.presentation.actionClockTick++
        compare(table.presentation.actionClockText(0), "0:59")
        compare(table.presentation.actionClockText(1), "2:00")
        room.actionClockRunning = 1
        compare(table.presentation.actionClockText(1), "2:00",
                "Changing the running seat starts from its own published clock")
        verify(Date.now() - table.presentation.actionClockMarked < 1000)
    }

    function test_actionClockPausesAndResetsFromSnapshots() {
        room.actionClockEnabled = true
        room.actionClockMs = [58900, 120000]
        room.actionClockRunning = 0
        room.actionClockRunning = -1
        table.presentation.actionClockMarked = Date.now() - 10000
        table.presentation.actionClockTick++
        compare(table.presentation.actionClockText(0), "0:59")
        compare(table.presentation.actionClockText(1), "2:00")
        room.actionClockRunning = 0
        room.actionClockMs = [30000, 0]
        compare(table.presentation.actionClockText(0), "0:30")
        compare(table.presentation.actionClockText(1), "0:00")
        compare(table.presentation.actionClockText(-1), "")
        compare(table.presentation.actionClockText(2), "")
        room.actionClockEnabled = false
        compare(table.presentation.actionClockText(0), "")
        verify(!item("forgeActionClock-0").visible)
        verify(!item("forgeActionClock-1").visible)
        room.actionClockMs = []
        room.actionClockEnabled = true
        compare(table.presentation.actionClockText(0), "")
    }

    function test_feedbackBlocksPriorityAndShortcutFallbackUntilClosed() {
        const fullControl = preferences.forgeFullControl
        const phaseStops = JSON.stringify(preferences.forgePhaseStops)
        window.feedbackInteractionOpen = true
        prompt("chooseAction", {autoPassEligible:true, options:[
            {responseId:"action:0", kind:"cast", cardId:"hand-0", label:"Cast"},
            {responseId:"$pass", kind:"pass", label:"Pass"}]})
        verify(table.priorityInputBlocked)
        verify(table.presentation.modalOpen)
        verify(!table.priority.passOnce())
        verify(!table.priority.respondAction("action:0"))
        // Even if a replaced screen receives focus during feedback, its fallback
        // shortcuts must not answer the game or change priority preferences.
        table.forceActiveFocus()
        keyClick(Qt.Key_Space)
        keyClick(Qt.Key_Escape)
        wait(200)
        compare(transport.responses.length, 0)
        compare(preferences.forgeFullControl, fullControl)
        compare(JSON.stringify(preferences.forgePhaseStops), phaseStops)
        window.feedbackInteractionOpen = false
        verify(!table.priorityInputBlocked)
        tryCompare(transport, "responses", [{id:table.rulesSession.promptId, response:"$pass"}])
    }

    function edhSnapshot(seats, localSeat, crowded) {
        const data = snapshot()
        data.players = []; data.zones = []
        data.activeSeat = seats[seats.length - 1]; data.prioritySeat = data.activeSeat
        for (const seat of seats) {
            const commanderId = "cmd-" + seat
            data.players.push({seat:seat, name:"Player " + seat, life:40, status:"playing",
                commanders:[{name:"Isamaru, Hound of Konda", casts:seat, tax:seat * 2,
                    zone:"command", objectId:commanderId}]})
            const permanents = []
            for (let i = 0; i < (typeof crowded === "number" ? crowded : crowded ? 18 : 3); ++i)
                permanents.push(card("creature-" + seat + "-" + i, seat, "Bear " + i, true))
            permanents.push(card("land-" + seat, seat, "Plains", false))
            data.zones.push({zone:"battlefield", ownerSeat:seat, count:permanents.length, cards:permanents},
                {zone:"hand", ownerSeat:seat, count:7, cards:seat === localSeat ? [card("my-hand", seat, "Plains", false)] : []},
                {zone:"library", ownerSeat:seat, count:83, cards:[]},
                {zone:"command", ownerSeat:seat, count:1, cards:[card(commanderId, seat, "Isamaru, Hound of Konda", true)]})
        }
        return data
    }
    function test_edhSeatLayouts_data() {
        return [{tag:"two-in-four-seat-room", seats:[0,1], local:0, width:1600, height:1000},
            {tag:"two-sparse", seats:[1,3], local:3, width:1600, height:1000},
            {tag:"three-sparse", seats:[0,2,3], local:2, width:1600, height:1000},
            {tag:"four", seats:[0,1,2,3], local:0, width:1920, height:1010},
            {tag:"four-other-viewer", seats:[0,1,2,3], local:3, width:1280, height:720}]
    }
    function test_edhSeatLayouts(data) {
        room.format = "edh"; room.deckFormat = "commander"; room.maxSeats = 4; room.seatIndex = data.local
        window.width = data.width; window.height = data.height
        verify(testRulesPrompt.applySnapshot(edhSnapshot(data.seats, data.local)))
        tryCompare(table.presentation, "playerSeats", data.seats)
        compare(table.presentation.bottomSeat, data.local)
        compare(table.presentation.commanderFormat, true)
        compare(findChild(table, "rulesGameLayout"), null)
        compare(item("forgeHand").ownerSeat, data.local)
        for (const seat of data.seats) {
            compare(findChild(table, "forgeCommanders-" + seat), null)
            verify(item("rulesPlayerTarget" + seat).visible)
        }
        if (data.seats.length === 2) {
            compare(table.presentation.multiplayer, false)
            compare(item("forgeOpponentCreatures").ownerSeat, data.seats.find(s => s !== data.local))
            verify(item("forgeOwnZoneStrip").visible)
            return
        }
        compare(table.presentation.multiplayer, true)
        verify(!item("forgeHandCaption").visible)
        const board = item("forgeMultiplayerBattlefield")
        const near = item("forgeField-" + data.local)
        verify(near.y > 0)
        compare(near.x, 0)
        if (data.seats.length === 3) compare(near.width, board.width)
        else verify(Math.abs(near.width * 2 + board.gap - board.width) < 1)
        for (const seat of data.seats) {
            const field = item("forgeField-" + seat)
            verify(field.x >= 0 && field.y >= 0)
            verify(field.x + field.width <= board.width + 1)
            verify(field.y + field.height <= board.height + 1)
            const right = field.mapToItem(table.presentation, field.width, 0).x
            verify(right <= table.presentation.boardRight + 1)
            const lane = item("forgeCreatures-" + seat)
            tryCompare(lane, "stackCount", 3)
            const zones = item("forgeSeatZones-" + seat)
            const command = item("forgeSeatZone-" + seat + "-command")
            const exile = item("forgeSeatZone-" + seat + "-exile")
            verify(command.x > exile.x + exile.width)
            const zoneY = zones.mapToItem(field, 0, 0).y
            if (field.nearSide) verify(lane.y + lane.height <= zoneY)
            else verify(zoneY + zones.height <= lane.y)
            const surface = item("forgeCard-creature-" + seat + "-0")
            const cardPosition = surface.mapToItem(field, 0, 0)
            if (field.nearSide) verify(cardPosition.y < field.height * 0.1)
            else verify(cardPosition.y + surface.height + lane.layoutCellExtra > field.height * 0.9,
                "The far-side card and its reserved combat chrome stay toward the center seam")
            verify(field.headerHeight <= 64 * table.presentation.unit + field.lifeDeltaClearance,
                "Metadata keeps its compact height below the permanent life-change band")
            const lanes = [lane, item("forgeLands-" + seat), item("forgeOther-" + seat)]
            for (const group of lanes.filter(value => value.stackCount > 0)) {
                verify(group.x >= field.inset && group.y >= field.boardTop)
                verify(group.x + group.width <= field.width - field.inset + 1)
                verify(group.y + group.height <= field.boardTop + field.boardHeight + 1)
                verify(group.scrollArea.contentHeight <= group.height + 1)
            }
            verify(table.presentation.pointFor("creature-" + seat + "-0").x > 0)
            if (seat !== data.local) compare(item("forgeSeatZone-" + seat + "-library").showsPublicFace, false)
        }
    }
    function test_edhFieldsAllocateSpaceToPublicPiles_data() {
        return [{tag:"creatures-only", creatures:8, lands:0, others:0},
            {tag:"lands-only", creatures:0, lands:10, others:0},
            {tag:"support-only", creatures:0, lands:8, others:6},
            {tag:"balanced", creatures:8, lands:4, others:3},
            {tag:"support-heavy", creatures:2, lands:12, others:8, allowOverflow:true}]
    }
    function test_edhFieldsAllocateSpaceToPublicPiles(data) {
        room.format = "edh"; room.maxSeats = 4
        const state = edhSnapshot([0,1,2,3], 0, 0)
        for (const zone of state.zones.filter(value => value.zone === "battlefield")) {
            zone.cards = []
            for (let i = 0; i < data.creatures; ++i)
                zone.cards.push(card("front-" + zone.ownerSeat + "-" + i, zone.ownerSeat, "Bear " + i, true))
            for (let i = 0; i < data.lands; ++i) {
                const land = card("land-" + zone.ownerSeat + "-" + i, zone.ownerSeat, "Plains", false)
                land.counters = [{name:"charge", value:i + 1}]
                zone.cards.push(land)
            }
            for (let i = 0; i < data.others; ++i)
                zone.cards.push(card("support-" + zone.ownerSeat + "-" + i, zone.ownerSeat, "Artifact " + i, false))
            zone.count = zone.cards.length
        }
        verify(testRulesPrompt.applySnapshot(state))
        table.priority.setFullControl(true)
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        for (const seat of [0,1,2,3]) {
            const field = item("forgeField-" + seat)
            const lanes = [item("forgeCreatures-" + seat), item("forgeLands-" + seat), item("forgeOther-" + seat)]
            for (let i = 0; i < lanes.length; ++i)
                tryCompare(lanes[i], "stackCount", [data.creatures, data.lands, data.others][i])
            const occupied = lanes.filter(lane => lane.stackCount > 0)
            if (occupied.length === 1) {
                const board = field.mapToItem(table.presentation, field.inset, field.boardTop,
                    field.width - 2 * field.inset, field.boardHeight)
                const obstructed = table.presentation.battlefieldObstacles.some(obstacle =>
                    board.x < obstacle.x + obstacle.width && board.x + board.width > obstacle.x
                    && board.y < obstacle.y + obstacle.height && board.y + board.height > obstacle.y)
                if (!obstructed) {
                    if (occupied[0].category === "creature")
                        compare(occupied[0].height, field.boardHeight)
                    else {
                        verify(occupied[0].height <= field.boardHeight)
                        fuzzyCompare(field.nearSide ? occupied[0].y + occupied[0].height : occupied[0].y,
                            field.nearSide ? field.boardTop + field.boardHeight : field.boardTop, 0.1,
                            "A single support category keeps the rear edge while releasing unused front space")
                    }
                    compare(occupied[0].width, field.width - 2 * field.inset)
                }
                for (const visible of occupied[0].inspectionRects(table.presentation))
                    for (const obstacle of table.presentation.battlefieldObstacles)
                        verify(!(visible.x < obstacle.x + obstacle.width - 0.5
                            && visible.x + visible.width > obstacle.x + 0.5
                            && visible.y < obstacle.y + obstacle.height - 0.5
                            && visible.y + visible.height > obstacle.y + 0.5),
                            "A single category uses free space around the fixed controls")
            }
            for (const lane of occupied) {
                verify(lane.cardWidth >= 80 * table.presentation.unit - 1)
                if (!data.allowOverflow)
                    verify(lane.scrollArea.contentHeight <= lane.height + 1, lane.objectName + " fits its piles")
                for (const peer of occupied.filter(value => value !== lane))
                    verify(lane.x + lane.width <= peer.x || peer.x + peer.width <= lane.x
                        || lane.y + lane.height <= peer.y || peer.y + peer.height <= lane.y)
                for (const slot of lane.visibleCards) {
                    verify(slot.x + slot.width <= lane.width + 1)
                    if (!data.allowOverflow) verify(slot.y + slot.height <= lane.height + 1)
                    verify(table.presentation.reveal(slot.cardId))
                    verify(table.presentation.pointFor(slot.cardId).x > 0)
                }
            }
        }
    }
    function test_edhControlChangesPreserveOtherCardsAndSeparatePriority() {
        room.format = "edh"; room.maxSeats = 4
        const state = edhSnapshot([0,1,2,3], 0)
        state.activeSeat = 2; state.prioritySeat = 3
        verify(testRulesPrompt.applySnapshot(state))
        const own = item("forgeCreatures-0"), other = item("forgeCreatures-1")
        tryCompare(own, "stackCount", 3); tryCompare(other, "stackCount", 3)
        const unchanged = item("forgeCard-creature-0-0")
        const turn = item("forgeField-2"), priority = item("forgeField-3")
        verify(turn.activeTurn && !turn.hasPriority)
        verify(priority.hasPriority && !priority.activeTurn)
        verify(turn.border.color !== priority.border.color)
        verify(item("forgeSeatStatus-2").text.includes("Current turn"))
        verify(item("forgeSeatStatus-3").text.includes("Priority"))
        state.zones.find(zone => zone.zone === "battlefield" && zone.ownerSeat === 1).cards[0].controllerSeat = 0
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(own, "cardCount", 4); tryCompare(other, "cardCount", 2)
        compare(item("forgeCard-creature-0-0"), unchanged)
        verify(own.itemFor("creature-1-0"))
        compare(other.itemFor("creature-1-0"), null)
        const command = item("forgeSeatZone-0-command")
        verify(command.summary)
        compare(String(command.faceSource), "")
        command.forceActiveFocus()
        keyClick(Qt.Key_Return)
        tryCompare(item("forgeZonePopup"), "visible", true)
        compare(item("forgeZonePopup").ownerSeat, 0)
    }
    function test_edhOpeningReclaimsPhaseSpace_data() {
        return [{tag:"three", seats:[0,2,3], local:2, width:1600, height:1000, scale:1},
            {tag:"three-small-controls", seats:[0,2,3], local:2, width:1915, height:1045, scale:0.8},
            {tag:"four", seats:[0,1,2,3], local:0, width:1600, height:1000, scale:1},
            {tag:"four-small-controls", seats:[0,1,2,3], local:2, width:1915, height:1045, scale:0.8}]
    }
    function test_edhOpeningReclaimsPhaseSpace(data) {
        room.format = "edh"; room.maxSeats = 4; room.seatIndex = data.local
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        const state = edhSnapshot(data.seats, data.local)
        for (const zone of state.zones) {
            if (zone.zone === "command") continue
            zone.cards = []; zone.count = zone.zone === "library" ? 99 : 0
        }
        state.turn = 0; state.activeSeat = -1; state.prioritySeat = data.local; state.step = "untap"
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(table.presentation, "playerSeats", data.seats)
        const board = item("forgeMultiplayerBattlefield"), track = item("forgePhaseTrack")
        const initialFields = data.seats.map(seat => item("forgeField-" + seat))
        const openingHeight = board.fieldFor(data.local).height
        const nearWidth = board.fieldFor(data.local).width
        for (const stage of ["starting-player", "mulligan", "first-turn", "next-game"]) {
            state.turn = stage === "first-turn" ? 1 : 0
            state.activeSeat = stage === "starting-player" || stage === "next-game" ? -1 : data.local
            if (stage === "next-game") state.gameId = "next-game"
            verify(testRulesPrompt.applySnapshot(state))
            waitForRendering(table)
            const fields = data.seats.map(seat => item("forgeField-" + seat))
            const near = board.fieldFor(data.local), far = fields.find(field => !field.nearSide)
            compare(track.visible, stage === "first-turn")
            compare(near.width, nearWidth)
            verify(Math.abs(far.y) < 1 && Math.abs(near.y + near.height - board.height) < 1)
            if (stage !== "next-game") {
                for (let index = 0; index < fields.length; ++index)
                    compare(fields[index], initialFields[index])
            }
            if (track.visible) {
                const phaseTop = track.mapToItem(board, 0, 0).y
                verify(phaseTop >= far.y + far.height,
                       "The visible phase track must fit between the player fields")
                verify(phaseTop + track.height <= near.y)
                verify(near.height < openingHeight)
            } else {
                const upper = fields.filter(field => !field.nearSide).sort((a, b) => a.x - b.x)
                const columnGap = upper[1].x - upper[0].x - upper[0].width
                verify(Math.abs(near.y - far.y - far.height - columnGap) < 1,
                       "A hidden phase track must leave only the same narrow gutter as the columns")
                compare(near.height, openingHeight)
            }
        }
    }
    function test_edhTargetsCommandersAndElimination() {
        room.format = "edh"; room.maxSeats = 4
        const data = edhSnapshot([0,1,2,3], 0)
        verify(testRulesPrompt.applySnapshot(data))
        tryCompare(table.presentation, "multiplayer", true)
        prompt("chooseBoardTargets", {minSelections:2, maxSelections:2, targets:[
            {responseId:"opaque-player-3", kind:"player", seat:3, label:"Player 3"},
            {responseId:"opaque-card-2", kind:"card", objectId:"creature-2-0", label:"Bear 0"}]})
        mouseClick(item("rulesPlayerTarget3"))
        mouseClick(item("forgeCard-creature-2-0"))
        compare(table.interaction.selectedCount, 2)
        mouseClick(item("rulesConfirmTargets"))
        compare(transport.responses.length, 1)
        compare(transport.responses[0].targets.slice().sort(), ["opaque-card-2", "opaque-player-3"])
        action("cast", "cmd-0")
        mouseClick(item("forgeSeatZone-0-command"))
        tryCompare(item("forgeZonePopup"), "opened", true)
        tryCompare(item("forgeZoneCards"), "stackCount", 1)
        mouseClick(item("forgeCard-cmd-0"))
        compare(transport.responses.length, 2)
        item("forgeZonePopup").close()
        compare(transport.responses[1].response, "opaque-play")
        const field = item("forgeField-3")
        const location = Qt.point(field.x, field.y)
        data.players[3].status = "conceded"
        data.activeSeat = 2; data.prioritySeat = 2
        verify(testRulesPrompt.applySnapshot(data))
        tryCompare(field, "eliminated", true)
        compare(table.presentation.playerSeats.length, 4)
        compare(Qt.point(field.x, field.y), location)
        compare(item("forgeField-2").activeTurn, true)
    }
    function test_edhCombatAndStackAcrossAllFields() {
        room.format = "edh"; room.maxSeats = 4
        const data = edhSnapshot([0,1,2,3], 0)
        data.activeSeat = 0; data.prioritySeat = 0; data.step = "declare_attackers"
        verify(testRulesPrompt.applySnapshot(data))
        tryCompare(table.presentation, "multiplayer", true)
        prompt("chooseAttackers", {combatSources:[{responseId:"attacker", objectId:"creature-0-0",
            label:"Bear 0", name:"Bear 0", validTargetIds:["defender-1", "defender-2", "defender-3"], maxAssignments:1}],
            combatTargets:[1,2,3].map(seat => ({responseId:"defender-" + seat, kind:"player", seat:seat,
                label:"Player " + seat, minAssignments:0, maxAssignments:8}))})
        mouseClick(item("forgeCard-creature-0-0"))
        mouseClick(item("rulesPlayerTarget3"))
        compare(table.combatInteraction.assignments.attacker, "defender-3")
        const combatArrow = item("forgeCombatArrow-creature-0-0-seat-3")
        compare(combatArrow.endPoint, table.presentation.playerPoint(3))
        verify(combatArrow.startPoint.x > 0 && combatArrow.endPoint.x > 0)
        mouseClick(item("rulesConfirmCombat-attackers"))
        compare(transport.responses[0].assignments, [{sourceId:"attacker", targetId:"defender-3"}])
        data.stack = [{id:"bolt", controllerSeat:2, identity:{name:"Lightning Bolt"}, text:"Deal 3 damage",
            targets:[{kind:"card", objectId:"creature-1-0", label:"Bear 0"}, {kind:"player", seat:3, label:"Player 3"}]}]
        verify(testRulesPrompt.applySnapshot(data))
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        mouseClick(item("forgeStackTarget-bolt-0"))
        const arrow = item("forgeStackTargetArrow")
        tryVerify(() => arrow.visible && arrow.endPoint.x > 0)
        compare(arrow.endPoint, table.presentation.pointFor("creature-1-0"))
        mouseClick(item("forgeStackTarget-bolt-1"))
        compare(arrow.endPoint, table.presentation.playerPoint(3))
        verify(item("forgeField-3").selected)
        transport.inRoom = false
        tryCompare(arrow, "visible", false)
        verify(!item("forgeField-3").selected)
    }

    function test_edhCrowdedBattlefieldAndSpectatorPrivacy() {
        room.format = "edh"; room.maxSeats = 4; room.role = "spectator"; room.seatIndex = -1
        verify(testRulesPrompt.applySnapshot(edhSnapshot([0,1,2,3], -1, 36)))
        tryCompare(table.presentation, "multiplayer", true)
        tryCompare(item("forgeHand"), "visibleCards", [])
        const lane = item("forgeCreatures-2")
        tryCompare(lane, "stackCount", 36)
        verify(lane.scrollArea.contentHeight > lane.scrollArea.height)
        const last = lane.visibleCards[lane.visibleCards.length - 1].cardId
        verify(table.presentation.reveal(last))
        verify(table.presentation.pointFor(last).x > 0)
        compare(item("forgeViewHand-2").visible, false)
        verify(!table.interaction.canRespond)
    }

    function test_floatingStackPreservesBattlefield_data() {
        return [{tag:"modern", format:"modern", seats:2}, {tag:"duel", format:"duel", seats:2},
            {tag:"edh-two", format:"edh", seats:2}, {tag:"edh-three", format:"edh", seats:3},
            {tag:"edh-four", format:"edh", seats:4}]
    }
    function test_floatingStackPreservesBattlefield(data) {
        room.format = data.format; room.maxSeats = data.format === "edh" ? 4 : 2
        const state = data.format === "edh" ? edhSnapshot([0,1,2,3].slice(0, data.seats), 0) : snapshot()
        verify(testRulesPrompt.applySnapshot(state))
        table.priority.setFullControl(true)
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        const board = table.presentation, stack = item("forgeStack"), arrow = item("forgeStackTargetArrow")
        tryCompare(board, "multiplayer", data.seats > 2)
        verify(board.boardRight > board.width * 0.95)
        const lane = item(data.seats > 2 ? "forgeCreatures-1" : "forgeOpponentCreatures")
        tryCompare(lane, "stackCount", data.format === "edh" ? 3 : 1)
        if (data.seats > 2) tryCompare(item("forgeLands-1"), "stackCount", 1)
        const before = Qt.rect(lane.x, lane.y, lane.width, lane.height)
        verify(!stack.visible)
        state.stack = [{id:"bolt", controllerSeat:0, identity:{name:"Lightning Bolt"},
            targets:[{kind:"player", seat:data.seats - 1, label:"Opponent"}]}]
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(stack, "count", 1)
        tryVerify(() => stack.visible && arrow.visible)
        compare(Qt.rect(lane.x, lane.y, lane.width, lane.height), before)
        const startX = stack.x, startY = stack.y, arrowStart = Qt.point(arrow.startPoint.x, arrow.startPoint.y)
        const handle = item("forgeStackDragHandle")
        mouseDrag(handle, handle.width / 2, handle.height / 2, -160, 80)
        tryVerify(() => stack.x < startX - 100 && stack.y > startY + 40)
        tryVerify(() => Math.abs(arrow.startPoint.x - arrowStart.x) > 100)
        compare(arrow.startPoint, stack.pointFor("bolt", board))
        compare(transport.responses.length, 0)
        verify(!table.inspector.pinned)
        compare(Qt.rect(lane.x, lane.y, lane.width, lane.height), before)
        const moved = Qt.point(stack.x, stack.y)
        mouseClick(item("forgeStackToggle"))
        tryCompare(stack, "collapsed", true)
        compare(Qt.point(stack.x, stack.y), moved)
        mouseClick(item("forgeStackToggle"))
        tryCompare(stack, "collapsed", false)
        compare(Qt.point(stack.x, stack.y), moved)
        mouseClick(handle, 10, 10, Qt.RightButton)
        tryCompare(stack, "storedPosition", Qt.point(-1, -1))
        verify(!table.inspector.pinned)
        tryVerify(() => Math.abs(stack.x - startX) < 1 && Math.abs(stack.y - startY) < 1,
            1000, "Restored position " + stack.x + "," + stack.y + "; initial " + startX + "," + startY)
        mouseClick(item("forgeStackToggle"))
        tryCompare(stack, "collapsed", true)
        compare(stack.height, stack.headerHeight)
        verify(!arrow.visible)
        state.turn++
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        verify(stack.collapsed)
        item("forgeStackToggle").forceActiveFocus(); keyClick(Qt.Key_Space)
        tryCompare(stack, "collapsed", false)
        tryVerify(() => arrow.visible)
        if (data.seats > 2) {
            const command = item("forgeSeatZone-" + (data.seats - 1) + "-command")
            const covered = command.mapToItem(board, command.width / 2, command.height / 2)
            const offset = 12 * board.unit
            stack.moveTo(covered.x - offset, covered.y - offset)
            mouseClick(stack, offset, offset)
            verify(!item("forgeZonePopup").visible, "The floating stack covers player controls")
        }
        stack.moveTo(board.width, board.height)
        window.width = 1280; window.height = 720
        tryVerify(() => stack.x + stack.width <= board.boardRight + 1
            && stack.y + stack.height < board.handTop)
        mouseClick(item("forgeStackToggle"))
        tryCompare(stack, "collapsed", true)
        state.stack = []
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(stack, "visible", false)
        tryCompare(stack, "collapsed", false)
        state.stack = [{id:"new-spell", controllerSeat:0, identity:{name:"Opt"}}]
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(stack, "visible", true)
        verify(!stack.collapsed)
        state.gameId = "next-game"
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(stack, "storedPosition", Qt.point(-1, -1))
    }

    function test_edhDecisionOverlayKeepsVisibleTargetsReachable_data() {
        return [{tag:"three", seats:3, target:0}, {tag:"four", seats:4, target:1}]
    }
    function test_edhDecisionOverlayKeepsVisibleTargetsReachable(data) {
        room.format = "edh"; room.maxSeats = 4
        window.width = 1280; window.height = 720
        verify(testRulesPrompt.applySnapshot(edhSnapshot([0,1,2,3].slice(0, data.seats), 0, true)))
        tryCompare(table.presentation, "multiplayer", true)
        const id = "creature-" + data.target + "-17"
        const lane = item("forgeCreatures-" + data.target)
        const geometry = Qt.rect(lane.x, lane.y, lane.width, lane.height)
        prompt("chooseBoardTargets", {minSelections:1, maxSelections:2,
            targets:[{responseId:"target", kind:"card", objectId:id, label:"Bear"},
                {responseId:"player", kind:"player", seat:2, label:"Opponent"}]})
        verify(table.presentation.reveal(id))
        const face = item("forgeCard-" + id), dock = table.presentation.decisionDock
        compare(Qt.rect(lane.x, lane.y, lane.width, lane.height), geometry,
                "Opening the multiplayer dock keeps the lane geometry")
        verify(dock.height <= table.presentation.boardDecisionHeight)
        const center = face.mapToItem(table.presentation, face.width / 2, face.height / 2)
        verify(center.x < dock.x || center.y < dock.y, "The target has an exposed click point")
        mouseClick(face)
        compare(table.interaction.selectedCount, 1)
        compare(transport.responses.length, 0)
    }

    function test_edhOrdinaryDockLeavesHeaderZonesReadable_data() {
        return [
            {tag:"maximized", width:1920, height:1011, scale:1.25, local:0},
            {tag:"maximized-small-controls", width:1920, height:1011, scale:1, local:0},
            {tag:"laptop-other-viewer", width:1280, height:720, scale:1, local:3},
            {tag:"scaled-controls", width:1600, height:1000, scale:1.5, local:2},
            {tag:"compact", width:1024, height:768, scale:1, local:0}
        ]
    }
    function test_edhOrdinaryDockLeavesHeaderZonesReadable(data) {
        room.format = "edh"; room.deckFormat = "commander"; room.maxSeats = 4; room.seatIndex = data.local
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        verify(testRulesPrompt.applySnapshot(edhSnapshot([0,1,2,3], data.local)))
        table.priority.setFullControl(true)
        const seat = (data.local + 1) % 4
        const lane = item("forgeCreatures-" + seat)
        const geometry = Qt.rect(lane.x, lane.y, lane.width, lane.height)
        const face = item("forgeCard-creature-" + seat + "-0")
        const faceBefore = face.mapToItem(table.presentation, 0, 0)
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        const dock = item("rulesDecisionDock"), zones = item("forgeSeatZones-" + seat)
        verify(dock.visible && !table.presentation.decisionCollapsible)
        const origin = zones.mapToItem(table.presentation, 0, 0)
        verify(origin.x + zones.width <= dock.x || origin.y + zones.height <= dock.y,
               "An ordinary priority dock must not paint over a player's zone labels")
        for (const zone of ["library", "graveyard", "exile", "command"]) {
            const button = item("forgeSeatZone-" + seat + "-" + zone)
            verify(button.width >= 40 * table.presentation.unit, "Zone labels keep readable width")
            mouseClick(button)
            tryCompare(item("forgeZonePopup"), "visible", true)
            compare(item("forgeZonePopup").ownerSeat, seat)
            compare(item("forgeZonePopup").zone, zone)
            mouseClick(item("forgeCloseZonePopup"))
            tryCompare(item("forgeZonePopup"), "visible", false)
        }
        const command = item("forgeSeatZone-" + seat + "-command")
        command.forceActiveFocus(); keyClick(Qt.Key_Return)
        tryCompare(item("forgeZonePopup"), "visible", true)
        compare(item("forgeZonePopup").ownerSeat, seat)
        mouseClick(item("forgeCloseZonePopup"))
        tryCompare(item("forgeZonePopup"), "visible", false)
        const zonesBefore = zones.mapToItem(table.presentation, 0, 0)
        prompt("payManaCost", {options:[{responseId:"$cancel", kind:"cancel", label:"Cancel"}]})
        compare(Qt.rect(lane.x, lane.y, lane.width, lane.height), geometry,
                "Making header controls accessible must not move battlefield lanes")
        compare(face.mapToItem(table.presentation, 0, 0), faceBefore)
        compare(zones.mapToItem(table.presentation, 0, 0), zonesBefore,
                "Board-decision changes keep the header stable")
    }

    function test_aiDifficultyRemainsVisibleOnTable() {
        room.seats = [{controller: "", displayName: "Alice"},
                      {controller: "forgeAi", aiDifficulty: "hard", displayName: "Forge AI"}]
        compare(item("forgePlayerName-1").text, "Forge AI · Hard")
        testTranslations.setLanguage("zh")
        tryCompare(item("forgePlayerName-1"), "text", "Forge AI · 困难")
        verify(item("forgePlayerName-1").visible)
    }

    function test_modelThinkingAndRetryStatus() {
        room.aiSource = "online"
        room.aiStatus = {state:"thinking"}
        room.seats = [{controller:"",displayName:"Alice"}, {controller:"modelAi",displayName:"Online model"}]
        compare(item("forgePlayerName-1").text, "Online model")
        compare(item("modelOpponentStatus").text, "Model is thinking…")
        verify(!item("modelOpponentRetry").visible)
        room.aiStatus = {state:"paused",code:"provider_error"}
        verify(item("modelOpponentRetry").visible)
        item("modelOpponentSettings").clicked()
        compare(window.openedScreen.url, "screens/ModelSettings.qml")
        compare(window.openedScreen.properties.source, "online")
        transport.modelRetries = 0
        item("modelOpponentRetry").clicked()
        compare(transport.modelRetries, 1)
        testTranslations.setLanguage("zh")
        tryCompare(item("modelOpponentRetry"), "text", "重试模型决策")
        room.aiSource = ""
        room.aiStatus = ({})
    }

    function test_phaseSnapshotsKeepTableObjects_data() {
        return [{tag:"ordinary", hand:5, creatures:3}, {tag:"crowded", hand:18, creatures:40}]
    }
    function test_phaseSnapshotsKeepTableObjects(data) {
        table.priority.setFullControl(true)
        const state = snapshot(data.hand, data.creatures)
        state.stack = [{id:"spell", controllerSeat:1, ownerSeat:1, identity:{name:"Lightning Bolt"}, text:"Deal 3 damage."}]
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        const names = ["forgeCard-own-0", "forgeCard-land", "forgeCard-opponent",
            "forgeHandSurface-hand-0", "rulesPlayerTarget0", "rulesPlayerTarget1", "forgeStackEntry-spell"]
        const objects = names.map(name => item(name))
        const lane = item("forgeOwnCreatures")
        const hand = item("forgeHand")
        lane.scrollArea.contentY = Math.max(0, lane.scrollArea.contentHeight - lane.scrollArea.height)
        hand.scrollArea.contentX = Math.max(0, hand.scrollArea.contentWidth - hand.scrollArea.width)
        const scrollY = lane.scrollArea.contentY, scrollX = hand.scrollArea.contentX
        objects[2].forceActiveFocus()
        tryVerify(() => objects[2].activeFocus)
        wait(150)
        const positions = objects.map(object => ({x:object.x, y:object.y, width:object.width, height:object.height}))
        const phases = ["begin_combat", "attackers", "blockers", "damage", "end_combat", "main2", "end"]
        for (const phase of phases) {
            state.step = phase
            state.prioritySeat = state.prioritySeat === 0 ? 1 : 0
            verify(testRulesPrompt.applySnapshot(state))
            waitForRendering(table)
            for (let i = 0; i < names.length; ++i) {
                compare(item(names[i]), objects[i], "Preserve " + names[i] + " during " + phase)
                compare(objects[i].x, positions[i].x)
                compare(objects[i].y, positions[i].y)
                compare(objects[i].width, positions[i].width)
                compare(objects[i].height, positions[i].height)
            }
            compare(lane.scrollArea.contentY, scrollY)
            compare(hand.scrollArea.contentX, scrollX)
            verify(objects[2].activeFocus)
            verify(item("forgeTurnPhase").text.includes(table.stepLabel(phase)))
        }
        // Real changes must still update immediately without replacing peers.
        state.zones[4].cards[0].tapped = true
        state.zones[4].cards[0].power = "4"
        state.players[0].life = 17
        state.zones[0].cards.push(card("drawn", 0, "Plains", false))
        state.zones[0].count++
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        for (let i = 0; i < names.length; ++i) compare(item(names[i]), objects[i])
        verify(objects[0].card.tapped)
        compare(objects[0].card.power, "4")
        compare(objects[4].life, 17)
        compare(hand.visibleCards.length, data.hand + 1)
    }

    function test_snapshotReorderingKeepsCardsAndStackTargetsCurrent() {
        const state = snapshot(3, 3)
        state.stack = [{id:"first", controllerSeat:0, identity:{name:"Lightning Bolt"},
            targets:[{kind:"player", seat:1, label:"Bob"}]},
            {id:"second", controllerSeat:1, identity:{name:"Lightning Bolt"},
                targets:[{kind:"player", seat:0, label:"Alice"}]}]
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        const first = item("forgeStackEntry-first"), second = item("forgeStackEntry-second")
        const handCard = item("forgeHandCard-hand-0")
        const stack = item("forgeStack")
        tryCompare(stack.currentTarget, "seat", 1)
        state.stack.reverse()
        state.zones[0].cards.reverse()
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        compare(item("forgeStackEntry-first"), first)
        compare(item("forgeStackEntry-second"), second)
        verify(second.y < first.y)
        compare(stack.activeEntry.objectId, "second")
        compare(stack.currentTarget.seat, 0)
        compare(item("forgeHandCard-hand-0"), handCard)
        compare(handCard.position, 2)
        state.stack.shift()
        state.zones[0].cards.pop()
        state.zones[0].count--
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        compare(item("forgeStackEntry-first"), first)
        compare(stack.currentTarget.seat, 1)
        compare(findChild(table, "forgeStackEntry-second"), null)
        compare(findChild(table, "forgeHandCard-hand-0"), null)
    }

    function test_continuousPassingKeepsDecisionDockStable_data() {
        return ["response", "turn", "stack"].map(mode => ({tag:mode, mode:mode}))
    }
    function test_continuousPassingKeepsDecisionDockStable(data) {
        const state = snapshot()
        state.zones.push({zone:"graveyard", ownerSeat:0, count:1, cards:[card("yard", 0, "Grizzly Bears", true)]})
        state.stack = [{id:"spell", controllerSeat:1, ownerSeat:1, identity:{name:"Lightning Bolt"}}]
        verify(testRulesPrompt.applySnapshot(state))
        const options = [{responseId:"$pass", kind:"pass", label:"Pass"},
            {responseId:"yard-action", kind:"cast", cardId:"yard", label:"Cast from graveyard"},
            {responseId:"other-action", kind:"special", label:"Special action"}]
        prompt("chooseAction", {options:options})
        verify(table.priority.beginYield(data.mode))
        waitForRendering(table)
        const dock = item("rulesDecisionDock"), cancel = item("rulesCancelYield")
        const height = dock.height, y = dock.y
        const cancelPoint = cancel.mapToItem(table, 0, 0)
        const controls = [item("forgeTurnIndicator"), item("rulesCancelYield")]
        const controlPoints = controls.map(control => control.mapToItem(table, 0, 0))
        for (let i = 0; i < 3; ++i) {
            tryCompare(transport, "rulesResponsePending", true)
            prompt("", {pending:false, supported:false})
            state.prioritySeat = 1
            state.step = ["begin_combat", "main2", "end"][i]
            verify(testRulesPrompt.applySnapshot(state))
            waitForRendering(table)
            compare(dock.height, height, "No layout jump between priority windows")
            compare(dock.y, y)
            compare(cancel.mapToItem(table, 0, 0), cancelPoint)
            for (let j = 0; j < controls.length; ++j)
                compare(controls[j].mapToItem(table, 0, 0), controlPoints[j])
            state.prioritySeat = 0
            verify(testRulesPrompt.applySnapshot(state))
            prompt("chooseAction", {options:options})
            compare(dock.height, height)
            compare(cancel.mapToItem(table, 0, 0), cancelPoint)
        }
        // A mandatory decision must end automation and become visible.
        prompt("chooseBoolean", {title:"Confirm decision", detail:"Use triggered ability?",
            minChoiceTotal:1, maxChoiceTotal:1,
            choices:[{responseId:"choice:0", label:"No", weight:1, canRepeat:false},
                {responseId:"choice:1", label:"Yes", weight:1, canRepeat:false}]})
        compare(table.priority.yieldMode, "")
        verify(dock.expanded)
        verify(item("rulesScalarChoice-choice:1").visible)
    }

    function test_publicCardNamesFollowCardLanguage() {
        catalog.names = {"Plains": "平原", "Grizzly Bears": "灰熊", "Lightning Bolt": "闪电击",
            "Commander": "指挥官"}
        verify(testRulesPrompt.applySnapshot(snapshot()))
        waitForRendering(table)
        compare(item("forgeCardName-land").text, "Plains")
        compare(item("forgeCardName-own-0").text, "Grizzly Bears")
        compare(item("forgeCard-land").card.name, "Plains")
        catalog.rules = {
            en: {"Lightning Bolt": "Deal 3 damage to any target."},
            zh: {"Lightning Bolt": "闪电击对任意目标造成3点伤害。"}
        }
        catalog.language = "zh"
        tryCompare(item("forgeCardName-land"), "text", "平原")
        compare(item("forgeCardName-own-0").text, "灰熊")
        compare(item("forgeCard-land").displayName, "平原")
        compare(item("forgeCard-land").card.name, "Plains")
        const state = snapshot()
        state.stack = [{id:"bolt", controllerSeat:0, identity:{name:"Lightning Bolt"}, text:"Deal 3 damage"}]
        state.players[0].commanders = [{name:"Commander", casts:1, tax:2, zone:"command", objectId:"cmd"}]
        room.format = "duel"
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        tryCompare(item("forgeStackName-bolt"), "text", "闪电击")
        compare(item("forgeStackRules-bolt").text, "闪电击对任意目标造成3点伤害。")
        mouseClick(item("forgeZone-command"))
        tryCompare(item("forgeZonePopup"), "visible", true)
        compare(item("forgeCommanderHistory-0-0").commanderName, "指挥官")
        catalog.language = "en"
        tryCompare(item("forgeCardName-land"), "text", "Plains")
        compare(item("forgeStackName-bolt").text, "Lightning Bolt")
        compare(item("forgeCommanderHistory-0-0").commanderName, "Commander")
    }

    function test_actionLabelsFollowCardLanguage() {
        catalog.names = {"Plains": "平原", "Lightning Bolt": "闪电击"}
        catalog.language = "zh"
        testTranslations.setLanguage("zh")
        compare(table.promptOptionLabel("chooseAction", "land", "Plains — play land"), "平原 — 使用地")
        compare(table.promptOptionLabel("chooseAction", "bolt", "Lightning Bolt — cast spell"), "闪电击 — 施放咒语")
        compare(table.promptOptionLabel("chooseFromSelection", "after", "After Lightning Bolt"), "排在 闪电击 之后")
        testTranslations.setLanguage("en")
        catalog.language = "en"
        compare(table.promptOptionLabel("chooseAction", "land", "Plains — play land"), "Plains — Play land")
    }

    function test_tokenActionsUseProjectedNamesOnEveryPrompt() {
        const state = snapshot()
        state.zones[4].cards = [token("spawn-1", 0, "Eldrazi Spawn", true),
            token("spawn-2", 0, "Eldrazi Spawn", true)]
        state.zones[4].count = 2
        verify(testRulesPrompt.applySnapshot(state))
        catalog.names = {"Eldrazi Spawn": "奥札奇裔"}
        catalog.language = "zh"
        testTranslations.setLanguage("zh")
        compare(table.promptOptionLabel("chooseAction", "action:1",
            "Eldrazi Spawn Token — activate ability", "spawn-1"), "奥札奇裔 — 起动异能")
        for (let revision = 0; revision < 3; ++revision) {
            catalog.nameRequests = []
            prompt("chooseAction", {options: [
                {responseId: "action:1", kind: "activateAbility", cardId: "spawn-1",
                    label: "Eldrazi Spawn Token — activate ability"},
                {responseId: "action:2", kind: "activateAbility", cardId: "spawn-2",
                    label: "Eldrazi Spawn Token — activate ability"},
                {responseId: "$pass", kind: "pass", label: "Pass priority"}]})
            verify(!catalog.nameRequests.includes("Eldrazi Spawn Token"),
                "Engine token labels must not trigger missing-name catalog scans: "
                + JSON.stringify(catalog.nameRequests))
        }
        compare(table.promptOptionLabel("chooseAction", "action:1",
            "Eldrazi Spawn Token — activate ability", "spawn-1"), "奥札奇裔 — 起动异能")
        table.cardActionPicker.showFor("spawn-1", "Eldrazi Spawn", [
            {responseId: "token-action", kind: "activateAbility", cardId: "spawn-1",
                label: "Eldrazi Spawn Token — activate ability"}])
        tryCompare(item("rulesCardAction-token-action"), "text", "奥札奇裔 — 起动异能")
        table.cardActionPicker.close()

        // The choice's spell face must not be replaced by the whole printed card.
        state.zones[0].cards = [card("adventure", 0, "Brazen Borrower // Petty Theft", false)]
        state.zones[0].count = 1
        verify(testRulesPrompt.applySnapshot(state))
        catalog.names = {"Petty Theft": "小偷小摸"}
        compare(table.promptOptionLabel("chooseAction", "spell", "Petty Theft — cast spell",
            "adventure"), "小偷小摸 — 施放咒语")
    }

    function test_sparseCreatureRowsStayCenteredInBattlefield_data() {
        const rows = []
        for (const seat of [0, 1]) {
            for (const creatures of [1, 2, 3]) {
                for (const lands of [[], ["Plains", "Plains"], ["Plains", "Ugin's Labyrinth"]]) {
                    rows.push({tag:(seat === 0 ? "own" : "opponent") + "-"
                        + creatures + "-creatures-" + (lands.length === 0 ? "no-lands"
                            : lands[0] === lands[1] ? "same-lands" : "distinct-lands"),
                        seat:seat, creatures:creatures, lands:lands})
                }
            }
        }
        return rows
    }
    function test_sparseCreatureRowsStayCenteredInBattlefield(data) {
        window.width = 1920; window.height = 1011
        const state = snapshot()
        for (const seat of [0, 1]) {
            const cards = []
            for (let i = 0; i < data.creatures; ++i)
                cards.push(card("center-" + seat + "-" + i, seat, "Center Bear " + i, true))
            for (let i = 0; i < data.lands.length; ++i)
                cards.push(card("center-land-" + seat + "-" + i, seat, data.lands[i], false))
            state.zones[4 + seat].cards = cards
            state.zones[4 + seat].count = cards.length
        }
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        verify(waitForPolish(window))
        waitForRendering(table)
        const faces = []
        for (let i = 0; i < data.creatures; ++i) {
            const face = item("forgeCardFace-center-" + data.seat + "-" + i)
            faces.push(face.mapToItem(table.presentation, 0, 0, face.width, face.height))
        }
        const left = Math.min.apply(null, faces.map(face => face.x))
        const right = Math.max.apply(null, faces.map(face => face.x + face.width))
        const center = (left + right) / 2
        const expected = table.presentation.boardLeft + table.presentation.boardWidth / 2
        verify(Math.abs(center - expected) <= 2 * table.presentation.unit,
            "Sparse creature faces center on the battlefield: actual " + center
            + ", expected " + expected + ", face bounds " + JSON.stringify(faces))
        for (const face of faces)
            verify(Math.abs(face.y - faces[0].y) <= table.presentation.unit,
                "A sparse creature row stays on one line")
        const targetId = "center-" + data.seat + "-0"
        prompt("chooseBoardTargets", {minSelections:1, maxSelections:1,
            targets:[{responseId:"center-target", kind:"card", objectId:targetId, label:"Center Bear 0"}]})
        for (let i = 0; i < data.creatures; ++i) {
            const face = item("forgeCardFace-center-" + data.seat + "-" + i)
            compare(face.mapToItem(table.presentation, 0, 0, face.width, face.height), faces[i],
                "The target decision preserves the centered creature row")
        }
        mouseClick(item("forgeCard-" + targetId))
        compare(transport.responses.length, 1)
        compare(transport.responses[0].targets, ["center-target"],
            "The centered face remains directly clickable")
    }

    function test_edhSparseCreatureRowsCenterInTheirOwnFields_data() {
        const rows = []
        for (const creatures of [1, 2, 3]) {
            for (const lands of [[], ["Plains", "Plains"], ["Plains", "Ugin's Labyrinth"]]) {
                rows.push({tag:creatures + "-creatures-" + (lands.length === 0 ? "no-lands"
                    : lands[0] === lands[1] ? "same-lands" : "distinct-lands"),
                    creatures:creatures, lands:lands, spent:false})
            }
            rows.push({tag:creatures + "-creatures-ready-spent-lands", creatures:creatures,
                lands:["Plains", "Plains"], spent:true})
        }
        return rows
    }
    function test_edhSparseCreatureRowsCenterInTheirOwnFields(data) {
        window.width = 1920; window.height = 1011
        room.format = "edh"; room.deckFormat = "commander"; room.maxSeats = 4
        const state = edhSnapshot([0, 1, 2, 3], 0)
        for (const zone of state.zones.filter(zone => zone.zone === "battlefield")) {
            zone.cards = []
            for (let i = 0; i < data.creatures; ++i)
                zone.cards.push(card("edh-center-" + zone.ownerSeat + "-" + i,
                    zone.ownerSeat, "Center Bear " + i, true))
            for (let i = 0; i < data.lands.length; ++i)
                zone.cards.push(Object.assign(card("edh-center-land-" + zone.ownerSeat + "-" + i,
                    zone.ownerSeat, data.lands[i], false), {tapped:data.spent && i === 0}))
            zone.count = zone.cards.length
        }
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        verify(waitForPolish(window))
        waitForRendering(table)
        for (const seat of [0, 1, 2, 3]) {
            const field = item("forgeField-" + seat)
            const faces = []
            for (let i = 0; i < data.creatures; ++i) {
                const face = item("forgeCardFace-edh-center-" + seat + "-" + i)
                faces.push(face.mapToItem(field, 0, 0, face.width, face.height))
            }
            const left = Math.min.apply(null, faces.map(face => face.x))
            const right = Math.max.apply(null, faces.map(face => face.x + face.width))
            verify(Math.abs((left + right) / 2 - field.width / 2) <= 2 * table.presentation.unit,
                "Seat " + seat + " creature faces center in their own field: "
                + JSON.stringify(faces) + ", field width " + field.width)
        }
    }

    function test_edhManaHintsStayInsideLandLane_data() {
        return [{tag:"payment-single", undo:false, lands:1}, {tag:"payment-two", undo:false, lands:2},
            {tag:"payment-three", undo:false, lands:3}, {tag:"undo-single", undo:true, lands:1},
            {tag:"undo-two", undo:true, lands:2}, {tag:"undo-three", undo:true, lands:3}]
    }
    function test_edhManaHintsStayInsideLandLane(data) {
        window.width = 1920; window.height = 1011
        room.format = "edh"; room.deckFormat = "commander"; room.maxSeats = 4
        const state = edhSnapshot([0, 1, 2, 3], 0, 1)
        for (const zone of state.zones.filter(zone => zone.zone === "battlefield")) {
            zone.cards = zone.cards.filter(row => row.power)
            for (let i = 0; i < data.lands; ++i)
                zone.cards.push(Object.assign(card("hint-land-" + zone.ownerSeat + "-" + i,
                    zone.ownerSeat, "Plains", false), {tapped:data.undo}))
            zone.count = zone.cards.length
        }
        verify(testRulesPrompt.applySnapshot(state))
        const options = []
        for (let i = 0; i < data.lands; ++i)
            options.push({responseId:"hint-action-" + i, cardId:"hint-land-0-" + i,
                kind:data.undo ? "undoMana" : "activateAbility", label:data.undo ? "Undo mana" : "Add mana"})
        prompt(data.undo ? "chooseAction" : "payManaCost", {options:options})
        const lane = item("forgeLands-0")
        tryCompare(lane, "stackCount", 1)
        compare(lane.scrollArea.clip, true)
        const front = lane.visibleCards.find(slot => slot.stackFront)
        compare(front.stackSize, data.lands)
        const hint = findChild(front, "forgeCardInteractionHint-" + front.cardId).parent
        verify(hint.visible)
        verify(waitForPolish(window))
        const rect = hint.mapToItem(lane.scrollArea, 0, 0, hint.width, hint.height)
        verify(rect.x >= -0.1 && rect.y >= -0.1
            && rect.x + rect.width <= lane.scrollArea.width + 0.1
            && rect.y + rect.height <= lane.scrollArea.height + 0.1,
            "Complete mana hint must stay in the clipped EDH land lane: " + JSON.stringify(rect)
            + ", viewport " + lane.scrollArea.width + "x" + lane.scrollArea.height)
    }

    function test_landsSitAsLeftTableRow() {
        const state = snapshot()
        state.zones[4].cards.push(card("land-2", 0, "Plains", false))
        state.zones[4].cards.push(card("relic", 0, "Sol Ring", false))
        state.zones[4].count += 2
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        const land = item("forgeCard-land")
        const land2 = item("forgeCard-land-2")
        const creature = item("forgeCard-own-0")
        const lane = item("forgeOwnLands")
        const piles = item("forgeOwnZoneStrip")
        tryCompare(land, "fullFace", false)
        compare(land.fullFace, creature.fullFace)
        verify(land.width <= 112 * table.presentation.unit)
        verify(land2.width <= 112 * table.presentation.unit)
        verify(land.width < creature.width, "Land " + land.width + " must remain smaller than creature " + creature.width)
        const landPoint = land.mapToItem(table, 0, 0)
        const pilePoint = piles.mapToItem(table, 0, 0)
        const hand = item("forgeHand")
        verify(piles.y >= hand.y - 4 * table.presentation.unit)
        verify(landPoint.x <= lane.x + 28 * table.presentation.unit)
        verify(landPoint.y + land.height <= pilePoint.y + 8 * table.presentation.unit)
        verify(lane.y + lane.height >= hand.y - 20 * table.presentation.unit)
        verify(lane.y > item("forgeOwnCreatures").y)
        compare(lane.visibleCards.length, 2)
        compare(lane.stackCount, 1)
        const stacked = land2.mapToItem(lane, 0, 0)
        const first = land.mapToItem(lane, 0, 0)
        verify(Math.abs(stacked.x - first.x) <= 12 * table.presentation.unit)
        verify(item("forgeCardStackCount-land-2").visible)
        compare(item("forgeCardStackCountLabel-land-2").text, "×2")
    }
    function test_playerPlateReservesSupportSpaceAcrossDecisions_data() {
        return [{tag:"maximized", w:1920, h:1011, scale:1, clock:false},
            {tag:"laptop-clock", w:1280, h:720, scale:1, clock:true},
            {tag:"large-controls", w:1600, h:1000, scale:1.35, clock:false}]
    }
    function test_playerPlateReservesSupportSpaceAcrossDecisions(data) {
        window.width = data.w; window.height = data.h; Theme.uiScale = data.scale
        room.actionClockEnabled = data.clock
        room.actionClockMs = data.clock ? [60000, 60000] : []
        const state = snapshot(1, 2, true)
        const supportIds = []
        for (let i = 0; i < 7; ++i) {
            const id = "support-" + i
            supportIds.push(id)
            state.zones[4].cards.push(card(id, 0, "Artifact " + i, false))
        }
        state.zones[4].count = state.zones[4].cards.length
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"pass", kind:"pass", label:"Pass"}]})
        const plate = item("rulesPlayerTarget0")
        const faceIds = ["own-0", "own-1", "land"].concat(supportIds)
        const positions = faceIds.map(id => {
            const face = item("forgeCard-" + id)
            const at = face.mapToItem(table.presentation, 0, 0)
            return Qt.rect(at.x, at.y, face.width, face.height)
        })
        for (const kind of ["chooseBoardTargets", "payManaCost", "chooseAction", ""]) {
            if (kind === "chooseBoardTargets")
                prompt(kind, {minSelections:1, maxSelections:1,
                    targets:supportIds.map(id => ({responseId:"target-" + id, kind:"card", objectId:id, label:id}))})
            else prompt(kind, {pending:kind.length > 0, supported:kind.length > 0,
                options:kind ? [{responseId:"pass", kind:"pass", label:"Pass"}] : []})
            for (let i = 0; i < faceIds.length; ++i) {
                const face = item("forgeCard-" + faceIds[i])
                const at = face.mapToItem(table.presentation, 0, 0)
                compare(Qt.rect(at.x, at.y, face.width, face.height), positions[i],
                    "Decision changes keep battlefield positions and sizes")
                verify(at.x + face.width <= plate.x || at.x >= plate.x + plate.width
                    || at.y + face.height <= plate.y || at.y >= plate.y + plate.height,
                    faceIds[i] + " must not sit under the player identity/life plate")
                verify(face.width >= 80 * table.presentation.unit - 0.1)
            }
        }
        prompt("chooseBoardTargets", {minSelections:1, maxSelections:1,
            targets:supportIds.map(id => ({responseId:"target-" + id, kind:"card", objectId:id, label:id}))})
        mouseClick(item("forgeCard-" + supportIds[0]))
        compare(transport.responses.length, 1)
        compare(transport.responses[0].targets, ["target-" + supportIds[0]])
    }
    function test_combatChromeFitsWithoutMovingOtherCards_data() {
        return [{tag:"opponent-unattached", w:1920, h:1011, seat:1, depth:0},
            {tag:"own-unattached", w:1920, h:1011, seat:0, depth:0},
            {tag:"opponent-attached", w:1920, h:1011, seat:1, depth:1},
            {tag:"own-attached", w:1920, h:1011, seat:0, depth:3},
            {tag:"laptop-opponent", w:1280, h:720, seat:1, depth:2},
            {tag:"laptop-own-blocker", w:1280, h:720, seat:0, depth:2, blocking:true}]
    }
    function test_combatChromeFitsWithoutMovingOtherCards(data) {
        window.width = data.w; window.height = data.h
        const state = snapshot(1, 1, true)
        const hostId = data.seat === 0 ? "own-0" : "opponent"
        const field = state.zones[4 + data.seat]
        for (let i = 0; i < data.depth; ++i)
            field.cards.push(Object.assign(card("aura-" + i, data.seat, "Aura " + i, false), {attachedTo:hostId}))
        field.count = field.cards.length
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"pass", kind:"pass", label:"Pass"}]})
        const lane = item(data.seat === 0 ? "forgeOwnCreatures" : "forgeOpponentCreatures")
        const host = item("forgeCard-" + hostId)
        const geometry = Qt.rect(lane.x, lane.y, lane.width, lane.height)
        const width = host.width
        const atRest = host.mapToItem(table.presentation, 0, 0)
        const land = item("forgeCard-land")
        const landAtRest = land.mapToItem(table.presentation, 0, 0)
        state.step = "declare_blockers"
        if (data.blocking) {
            field.cards[0].blocking = ["opponent"]
            state.zones[5].cards[0].attacking = true
            state.zones[5].cards[0].attackingPlayer = 0
        } else {
            field.cards[0].attacking = true
            field.cards[0].attackingPlayer = 1 - data.seat
        }
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        compare(Qt.rect(lane.x, lane.y, lane.width, lane.height), geometry)
        compare(host.width, width, "Combat keeps the preallocated readable card size")
        compare(land.mapToItem(table.presentation, 0, 0), landAtRest)
        verify(host.width >= 80 * table.presentation.unit - 0.1)
        const moved = host.mapToItem(table.presentation, 0, 0)
        verify(Math.abs(moved.y - atRest.y - (data.blocking ? 0 : lane.combatForward * 14 * lane.unit)) < 0.1)
        const badge = item("forgeCardInteractionHint-" + hostId).parent
        verify(badge.visible)
        const cardAt = host.mapToItem(lane.scrollArea, 0, 0)
        const badgeAt = badge.mapToItem(lane.scrollArea, 0, 0)
        verify(cardAt.y >= -0.1 && cardAt.y + host.height <= lane.scrollArea.height + 0.1,
            "The full attacking face stays inside its clipped lane")
        verify(badgeAt.y >= 0 && badgeAt.y + badge.height <= lane.scrollArea.height + 0.1,
            "The entire combat destination badge stays inside the viewport")
        for (let i = 0; i < data.depth; ++i) {
            const strip = item("forgeAttachmentStrip-aura-" + i)
            const stripAt = strip.mapToItem(lane.scrollArea, 0, 0)
            verify(stripAt.y + strip.height <= badgeAt.y
                || badgeAt.y + badge.height <= stripAt.y,
                "The host badge cannot cover any attachment name strip")
            verify(stripAt.y >= 0 && stripAt.y + strip.height <= lane.scrollArea.height + 0.1)
        }
        const ids = [hostId].concat(Array.from({length:data.depth}, (_, i) => "aura-" + i))
        for (let i = 0; i < ids.length; ++i) {
            prompt("chooseBoardTargets", {minSelections:1, maxSelections:1,
                targets:ids.map(id => ({responseId:"target-" + id, kind:"card", objectId:id, label:id}))})
            const face = item("forgeCard-" + ids[i])
            mouseClick(face, face.width / 2, i === 0 ? face.height / 2 : face.height - 8 * lane.unit)
            compare(transport.responses.length, i + 1)
            compare(transport.responses[i].targets, ["target-" + ids[i]])
        }
    }
    function test_equippedCreaturesUseAvailableBattlefield_data() {
        return [{tag:"laptop", w:1280, h:760, depth:1},
            {tag:"desktop", w:1600, h:1000, depth:2},
            {tag:"many-attachments", w:1920, h:1010, depth:5}]
    }
    function test_equippedCreaturesUseAvailableBattlefield(data) {
        window.width = data.w; window.height = data.h
        const state = snapshot(1, 5, true)
        for (let seat = 0; seat < 2; ++seat) {
            const zone = state.zones[4 + seat]
            zone.cards = Array.from({length:5}, (_, i) => card("creature-" + seat + "-" + i, seat, "Bear " + i, true))
            zone.cards.push(card("land-" + seat, seat, "Plains", false),
                card("land2-" + seat, seat, "Ugin's Labyrinth", false),
                card("drum-" + seat, seat, "Springleaf Drum", false))
            for (let host = 0; host < 2; ++host)
                for (let i = 0; i < data.depth; ++i) {
                    const equipment = card("equipment-" + seat + "-" + host + "-" + i, seat, "Bonesplitter", false)
                    equipment.attachedTo = "creature-" + seat + "-" + host
                    zone.cards.push(equipment)
                }
            zone.count = zone.cards.length
        }
        for (const step of ["main1", "declare_attackers", "main2"]) {
            state.step = step
            verify(testRulesPrompt.applySnapshot(state))
            if (step === "declare_attackers")
                prompt("chooseAttackers", {
                    combatSources:Array.from({length:5}, (_, i) => ({responseId:"source-" + i,
                        objectId:"creature-0-" + i, label:"Bear " + i, validTargetIds:["defender"], maxAssignments:1})),
                    combatTargets:[{responseId:"defender", kind:"player", seat:1, label:"Opponent", maxAssignments:5}]})
            else prompt("chooseAction", {options:[{responseId:"pass", kind:"pass", label:"Pass"}]})
            for (const side of ["Own", "Opponent"]) {
                const lane = item("forge" + side + "Creatures")
                tryCompare(lane, "stackCount", 5)
                compare(lane.attachmentDepth, data.depth)
                // The field contract guarantees an 80-unit readable floor.
                // Attachment strips and the reserved player controls may make
                // a five-creature row narrower than the preferred 180 units.
                verify(lane.cardWidth >= 80 * table.presentation.unit - 0.1,
                    side + " creatures remain readable in " + step + ": " + lane.cardWidth / table.presentation.unit)
                verify(lane.cardWidth <= 200 * table.presentation.unit + 0.1)
                verify(lane.scrollArea.contentHeight <= lane.height + 1, "An ordinary board needs no scrolling")
                for (const group of ["Lands", "Other"]) {
                    const support = item("forge" + side + group)
                    compare(support.attachmentDepth, 0)
                    compare(support.structuralBadge, false, "Unrelated support cards reserve no structural badges")
                    verify(support.scrollArea.contentHeight <= support.height + 1)
                    verify(lane.x + lane.width <= support.x || support.x + support.width <= lane.x
                        || lane.y + lane.height <= support.y || support.y + support.height <= lane.y)
                }
                const seat = side === "Own" ? 0 : 1
                for (let i = 0; i < 5; ++i) {
                    const face = item("forgeCard-creature-" + seat + "-" + i)
                    verify(table.presentation.pointFor(face.objectId).x > 0)
                    if (i < 2) {
                        const attachment = item("forgeCard-equipment-" + seat + "-" + i + "-" + (data.depth - 1))
                        compare(attachment.width, face.width)
                        const point = attachment.mapToItem(lane.scrollArea, 0, 0)
                        verify(point.y + attachment.height <= lane.scrollArea.height + 1)
                    }
                }
            }
            if (step === "declare_attackers")
                for (let i = 0; i < 5; ++i) {
                    mouseClick(item("forgeCard-creature-0-" + i))
                    mouseClick(item("rulesPlayerTarget1"))
                    compare(table.combatInteraction.assignments["source-" + i], "defender")
                }
        }
    }
    Component {
        id: shortLane
        ForgeCardLane {
            tableController: table
            ownerSeat: 0
            width: 400; height: 70
            showCaption: false
        }
    }
    Component {
        id: pileObstacleField
        Item {
            id: field
            width: 900; height: 400
            property real obstacleTop: height
            readonly property real obstacleLeft: 300
            property alias creatures: creatures
            ForgeFieldLayout {
                id: layout
                width: field.width; height: field.height; unit: 1; nearSide: true
                creatureLane: creatures; landLane: lands; otherLane: others
                widthForBand: (top, extent) => top + extent > field.obstacleTop
                    ? field.obstacleLeft : field.width
            }
            ForgeCardLane {
                id: creatures
                tableController: table; ownerSeat: 0; category: "creature"
                showCaption: false; combatForward: -1
                x: layout.placement.creatures.x; y: layout.placement.creatures.y
                width: layout.placement.creatures.width; height: layout.placement.creatures.height
            }
            ForgeCardLane {
                id: lands
                tableController: table; ownerSeat: 0; category: "land"
                showCaption: false
            }
            ForgeCardLane {
                id: others
                tableController: table; ownerSeat: 0; category: "other"
                showCaption: false
            }
        }
    }
    function test_sparsePileReadoutClearsObstacleAtItsBottomEdge_data() {
        return [{tag:"mana-payment", payment:true}, {tag:"combat-label", payment:false}]
    }
    function test_sparsePileReadoutClearsObstacleAtItsBottomEdge(data) {
        const state = snapshot(1, 3)
        state.zones[4].cards = state.zones[4].cards.filter(card => card.power)
        state.zones[4].count = 3
        if (!data.payment) {
            state.step = "declare_blockers"
            state.zones[4].cards.forEach(card => card.blocking = ["opponent"])
            state.zones[5].cards[0].attacking = true
            state.zones[5].cards[0].attackingPlayer = 0
        }
        verify(testRulesPrompt.applySnapshot(state))
        prompt(data.payment ? "payManaCost" : "chooseAction", {options:data.payment
            ? state.zones[4].cards.map(card => ({responseId:"pay-" + card.id,
                cardId:card.id, kind:"activateAbility", label:"Add mana"}))
            : [{responseId:"$pass", kind:"pass", label:"Pass"}]})
        const field = createTemporaryObject(pileObstacleField, window.contentItem)
        verify(field !== null)
        const lane = field.creatures
        tryCompare(lane, "stackCount", 1)
        const front = lane.visibleCards.find(slot => slot.stackFront)
        compare(front.stackSize, 3)
        const hint = findChild(front, "forgeCardInteractionHint-" + front.cardId).parent
        verify(hint.visible, "The edge probe needs a painted interaction/combat label")
        verify(waitForPolish(window))
        waitForRendering(field)
        const before = hint.mapToItem(field, 0, 0, hint.width, hint.height)
        verify(before.x + before.width > field.obstacleLeft,
            "The initial centered label reaches the future obstacle's horizontal range")
        field.obstacleTop = before.y + before.height - 1
        verify(waitForPolish(window))
        waitForRendering(field)
        const after = hint.mapToItem(field, 0, 0, hint.width, hint.height)
        verify(after.x + after.width <= field.obstacleLeft + 0.1
            || after.y + after.height <= field.obstacleTop + 0.1,
            "The complete painted label must clear the obstacle, including its bottom edge: "
            + JSON.stringify(after) + ", obstacle " + field.obstacleLeft + "," + field.obstacleTop)
        for (const rect of lane.readoutRects(field))
            verify(rect.x + rect.width <= field.obstacleLeft + 0.1
                || rect.y + rect.height <= field.obstacleTop + 0.1,
                "No visible public readout may remain under the obstacle")
    }
    function test_shortCreatureLaneScrollsAtReadableSize() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, 12, true)))
        const lane = createTemporaryObject(shortLane, window.contentItem)
        verify(lane !== null)
        tryCompare(lane, "stackCount", 12)
        verify(lane.cardWidth >= 80)
        verify(lane.scrollArea.contentHeight > lane.scrollArea.height)
        verify(lane.reveal("own-9"))
        verify(lane.scrollArea.contentY > 0)
    }
    function test_shortCombatLaneKeepsReadableScrolling_data() {
        return [{tag:"near-side", direction:-1}, {tag:"far-side", direction:1}]
    }
    function test_shortCombatLaneKeepsReadableScrolling(data) {
        const state = snapshot(1, 12, true)
        state.step = "declare_blockers"
        state.zones[4].cards.forEach(row => {
            if (row.power) { row.attacking = true; row.attackingPlayer = 1 }
        })
        verify(testRulesPrompt.applySnapshot(state))
        const lane = createTemporaryObject(shortLane, window.contentItem,
            {combatForward:data.direction, height:110})
        verify(lane !== null)
        tryCompare(lane, "stackCount", 12)
        verify(lane.cardWidth >= 80, "Combat margins cannot reduce the readable floor")
        verify(lane.scrollArea.contentHeight > lane.scrollArea.height)
        const finalCard = lane.itemFor("own-11")
        verify(finalCard !== null)
        verify(lane.reveal("own-11"))
        verify(lane.scrollArea.contentY > 0)
        const at = finalCard.mapToItem(lane.scrollArea, 0, 0)
        verify(at.y >= -0.1 && at.y + finalCard.height <= lane.scrollArea.height + 0.1,
            "Revealing the final exact card keeps its face visible")
    }
    function test_pileFrontsAndBadgesStayInsideTheirLane() {
        const state = snapshot(1, 0)
        const marked = (id, name, creature, fields) => Object.assign(card(id, 0, name, creature), fields)
        state.zones[4].cards = [
            marked("land-a", "Plains", false, {tapped:true}),
            card("land-b", 0, "Plains", false),
            card("land-c", 0, "Plains", false),
            marked("land-d", "Plains", false, {enteredThisTurn:true}),
            card("bear-a", 0, "Grizzly Bears", true),
            marked("bear-b", "Grizzly Bears", true, {tapped:true}),
            card("bear-c", 0, "Grizzly Bears", true)
        ]
        state.zones[4].count = state.zones[4].cards.length
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        const unit = table.presentation.unit
        for (const name of ["forgeOwnLands", "forgeOwnCreatures"]) {
            const lane = item(name)
            tryVerify(() => lane.stackCount === 2 && lane.pileLead > 0, 3000, name)
            const front = lane.visibleCards.find(slot => slot.stackFront && slot.stackSize > 1)
            verify(front && !front.tapped, name)
            const face = item("forgeCard-" + front.cardId)
            const at = face.mapToItem(lane.scrollArea, 0, 0)
            verify(at.x >= -0.5 && at.y >= -0.5, name + " front leaves its lane at " + at.x + "," + at.y)
            const badge = item("forgeCardStackCount-" + front.cardId)
            const label = item("forgeCardStackCountLabel-" + front.cardId)
            const on = badge.mapToItem(face, 0, 0)
            verify(on.x >= 0 && on.x + badge.width <= face.width + 0.5, name + " badge leaves its card")
            verify(label.contentWidth <= badge.width, name + " badge text overflows")
        }
        compare(item("forgeCardStackCountLabel-" + item("forgeOwnLands").visibleCards
            .find(slot => slot.stackFront && slot.stackSize > 1).cardId).text, "×3 · 1 new")
        const lands = item("forgeOwnLands")
        const lead = lands.pileLead, width = lands.cardWidth
        state.zones[4].cards[1].tapped = true
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        compare(lands.pileLead, lead, "Tapping keeps the reserved lead")
        compare(lands.cardWidth, width)
        verify(lead <= 9 * unit + 0.01)

        // The final two-copy pile can disappear entirely into ready/spent
        // singletons. Neither its lead nor its right-hand trail becomes room
        // for larger faces in a narrow lane.
        for (const alignRight of [false, true]) {
            const pair = snapshot(1, 0)
            pair.zones[4].cards = [card("pair-a", 0, "Plains", false),
                card("pair-b", 0, "Plains", false)]
            pair.zones[4].count = 2
            verify(testRulesPrompt.applySnapshot(pair))
            const probe = createTemporaryObject(shortLane, window.contentItem,
                {category:"land", width:105, height:250, alignRight:alignRight})
            verify(probe !== null); verify(waitForPolish(window))
            compare(probe.stackCount, 1)
            const faceWidth = probe.cardWidth
            verify(faceWidth >= 80)
            pair.zones[4].cards[0].tapped = true
            verify(testRulesPrompt.applySnapshot(pair)); verify(waitForPolish(window))
            compare(probe.stackCount, 2)
            compare(probe.cardWidth, faceWidth, "Ready/spent singletons keep their fitted face size")
            for (const slot of probe.hostCards) {
                const at = slot.mapToItem(probe.scrollArea, 0, 0)
                verify(at.x >= -0.01 && at.x + slot.width <= probe.scrollArea.width + 0.01,
                    "Both singletons stay inside the narrow lane")
            }
        }
    }
    function test_closedPileShowsOnlyTheFrontHint() {
        const state = snapshot(1, 0)
        const spent = card("land-a", 0, "Plains", false)
        spent.tapped = true
        state.zones[4].cards = [spent, card("land-b", 0, "Plains", false), card("land-c", 0, "Plains", false)]
        state.zones[4].count = 3
        verify(testRulesPrompt.applySnapshot(state))
        prompt("payManaCost", {title:"Pay Mana Cost: {W}",
            options:[{responseId:"action:0", cardId:"land-b", kind:"activateAbility", label:"Plains"},
                     {responseId:"action:1", cardId:"land-c", kind:"activateAbility", label:"Plains"},
                     {responseId:"undo-a", cardId:"land-a", kind:"undoMana", label:"Undo"}]})
        const lane = item("forgeOwnLands")
        const unit = table.presentation.unit
        tryVerify(() => lane.stackCount === 2)
        const ready = item("forgeCard-land-b").mapToItem(lane, 0, 0)
        const copy = item("forgeCard-land-c").mapToItem(lane, 0, 0)
        verify(Math.abs(ready.x - copy.x) <= 16 * unit + 1)
        const spentAt = item("forgeCard-land-a").mapToItem(lane, 0, 0)
        verify(Math.abs(spentAt.x - copy.x) > 20 * unit || Math.abs(spentAt.y - copy.y) > 20 * unit)
        verify(!item("forgeCardInteractionHint-land-b").visible, "A buried ready copy stays unlabeled")
        mouseClick(item("forgeCard-land-a"))
        compare(transport.responses[0].response, "undo-a")
    }
    function test_identicalPermanentsAndTokensStackTogether() {
        const state = snapshot(1, 0)
        const tappedLand = card("land-tapped", 0, "Plains", false)
        tappedLand.tapped = true
        const tappedBear = card("bear-tapped", 0, "Grizzly Bears", true)
        tappedBear.tapped = true
        state.zones[4].cards = [
            card("land-a", 0, "Plains", false),
            card("land-b", 0, "Plains", false),
            tappedLand,
            card("treasure-a", 0, "Treasure", false),
            card("treasure-b", 0, "Treasure", false),
            token("goblin-a", 0, "Goblin Token", true),
            token("goblin-b", 0, "Goblin Token", true),
            card("bear-real", 0, "Grizzly Bears", true),
            token("bear-token", 0, "Grizzly Bears", true),
            tappedBear
        ]
        state.zones[4].count = state.zones[4].cards.length
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        const lands = item("forgeOwnLands")
        const other = item("forgeOwnOther")
        const creatures = item("forgeOwnCreatures")
        const unit = table.presentation.unit
        tryVerify(() => lands.visibleCards.length === 3 && lands.stackCount === 2)
        tryVerify(() => other.visibleCards.length === 2 && other.stackCount === 1)
        tryVerify(() => creatures.visibleCards.length === 5 && creatures.stackCount === 4)
        const stackedLand = item("forgeCard-land-b").mapToItem(lands, 0, 0)
        const firstLand = item("forgeCard-land-a").mapToItem(lands, 0, 0)
        verify(Math.abs(stackedLand.x - firstLand.x) <= 16 * unit + 1)
        verify(Math.abs(stackedLand.y - firstLand.y) <= 16 * unit + 1)
        const splitLand = item("forgeCard-land-tapped").mapToItem(lands, 0, 0)
        verify(Math.abs(splitLand.x - firstLand.x) > 20 * unit
               || Math.abs(splitLand.y - firstLand.y) > 20 * unit,
               "A tapped copy leaves the ready pile")
        compare(item("forgeCardStackCountLabel-land-b").text, "×2")
        compare(item("forgeCardStackCountLabel-treasure-b").text, "×2")
        compare(item("forgeCardStackCountLabel-goblin-b").text, "×2")
        const printed = item("forgeCard-bear-real").mapToItem(creatures, 0, 0)
        const copied = item("forgeCard-bear-token").mapToItem(creatures, 0, 0)
        verify(Math.abs(printed.x - copied.x) > 20 * unit
               || Math.abs(printed.y - copied.y) > 20 * unit)
    }
    function zonedSnapshot(seats, localSeat) {
        const state = seats.length > 2 ? edhSnapshot(seats, localSeat, 1) : snapshot()
        const types = {"Eldrazi Temple":"Land", "Ugin's Labyrinth":"Land", "Urza's Mine":"Land",
            "Urza's Power Plant":"Land", "Urza's Tower":"Land",
            "Karn, the Great Creator":"Legendary Planeswalker — Karn", "Ugin, the Spirit Dragon":"Legendary Planeswalker — Ugin",
            "Liquimetal Coating":"Artifact", "Relic of Progenitus":"Artifact", "Trinisphere":"Artifact",
            "Testing Enchantment":"Enchantment"}
        catalog.typeOverrides = types
        for (const zone of state.zones.filter(zone => zone.zone === "battlefield")) {
            const seat = zone.ownerSeat
            zone.cards = [card("z-creature-" + seat, seat, "Grizzly Bears", true)]
            for (const name of Object.keys(types)) {
                const row = card("z-" + seat + "-" + name, seat, name, false)
                if (types[name].includes("Planeswalker")) row.counters = [{name:"LOYALTY", value:4}]
                zone.cards.push(row)
            }
            zone.cards.push(card("z-temple-copy-" + seat, seat, "Eldrazi Temple", false))
            zone.count = zone.cards.length
        }
        return state
    }
    function test_permanentZonesKeepTheirSidesAndReachablePlaneswalkers_data() {
        return [{tag:"duel", seats:[0,1], local:0, width:1920, height:1011, scale:1},
            {tag:"duel-native-normal-controls", seats:[0,1], local:0, width:1920, height:1011,
                scale:1.2, otherCount:3},
            {tag:"duel-compact", seats:[0,1], local:0, width:1280, height:720, scale:1},
            {tag:"duel-large-controls", seats:[0,1], local:1, width:1920, height:1011, scale:1.5},
            {tag:"duel-spectator", seats:[0,1], local:-1, width:1280, height:720, scale:1},
            {tag:"three", seats:[0,1,2], local:0, width:1920, height:1011, scale:1},
            {tag:"four", seats:[0,1,2,3], local:0, width:1920, height:1011, scale:1},
            {tag:"four-compact", seats:[0,1,2,3], local:3, width:1280, height:720, scale:1},
            {tag:"four-large-controls", seats:[0,1,2,3], local:0, width:1920, height:1011, scale:1.5},
            {tag:"four-native-large-controls", seats:[0,1,2,3], local:0, width:1920, height:1011,
                scale:1.8, otherCount:3}]
    }
    function test_permanentZonesKeepTheirSidesAndReachablePlaneswalkers(data) {
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        room.seatIndex = data.local; room.role = data.local < 0 ? "spectator" : "player"
        if (data.seats.length > 2) { room.format = "edh"; room.deckFormat = "commander"; room.maxSeats = data.seats.length }
        const state = zonedSnapshot(data.seats, Math.max(0, data.local))
        if (data.otherCount === 3)
            for (const zone of state.zones.filter(zone => zone.zone === "battlefield")) {
                zone.cards = zone.cards.filter(card => card.identity.name !== "Testing Enchantment")
                zone.count = zone.cards.length
            }
        verify(testRulesPrompt.applySnapshot(state)); verify(waitForPolish(window)); verify(waitForRendering(table))
        const presentation = table.presentation, stable = []
        function bounds(target) { return target.mapToItem(presentation, 0, 0, target.width, target.height) }
        for (const seat of data.seats) {
            const near = data.seats.length > 2 ? item("forgeField-" + seat).nearSide : seat === presentation.bottomSeat
            const prefix = data.seats.length > 2 ? "" : near ? "Own" : "Opponent"
            function lane(kind) { return item("forge" + prefix + kind + (prefix ? "" : "-" + seat)) }
            const creatures = lane("Creatures"), lands = lane("Lands"), walkers = lane("Planeswalkers"), others = lane("Other")
            compare(creatures.stackCount, 1); compare(lands.stackCount, 5)
            compare(walkers.stackCount, 2); compare(others.stackCount, data.otherCount || 4)
            const l = bounds(lands), w = bounds(walkers), o = bounds(others)
            const landFaces = lands.hostCards.filter(slot => slot.stackFront)
                .sort((a, b) => a.stackIndex - b.stackIndex).map(slot => bounds(slot.faceItem))
            // The duplicate Temple may offset its pile front by four units.
            fuzzyCompare(landFaces[0].y, landFaces[1].y, 5 * presentation.unit,
                "Land piles progress along a horizontal row on either side of the table")
            verify(landFaces[1].x >= landFaces[0].x + landFaces[0].width - presentation.unit,
                "The second distinct land is to the right of the first")
            const creatureFace = bounds(item("forgeCardFace-z-creature-" + seat))
            const field = data.seats.length > 2 ? bounds(item("forgeField-" + seat))
                : Qt.rect(presentation.boardLeft, 0, presentation.boardWidth, 0)
            fuzzyCompare(creatureFace.x + creatureFace.width / 2, field.x + field.width / 2,
                2 * presentation.unit, "A lone creature centers on its whole field with both right-side categories occupied")
            const rightmostOther = Math.max.apply(null, others.hostCards.filter(slot => slot.stackFront)
                .map(slot => { const face = bounds(slot.faceItem); return face.x + face.width }))
            const rightInset = data.seats.length > 2 ? item("forgeField-" + seat).inset : 0
            fuzzyCompare(rightmostOther, field.x + field.width - rightInset,
                4 * presentation.unit, "Other permanents reach their field's right edge")
            verify(l.x + l.width / 2 < w.x + w.width / 2, "Planeswalkers stay to the right of lands")
            verify(l.x + l.width / 2 < o.x + o.width / 2, "Other permanents stay to the right of lands")
            verify(near ? w.y < o.y : w.y > o.y, "Planeswalkers keep the front of the right side")
            const groups = [creatures, lands, walkers, others]
            for (let index = 0; index < groups.length; ++index) {
                const group = groups[index]
                verify(group.cardWidth >= 80 * presentation.unit - 0.1, "Every group retains readable card sizes")
                for (const other of groups.slice(index + 1))
                    verify(!rectsOverlap(group, other), "Permanent categories have separate allocations")
                const first = group.hostCards.find(slot => slot.stackFront)
                verify(first !== undefined)
                verify(presentation.reveal(first.cardId))
                verify(waitForPolish(window))
                const face = first.faceItem, faceBody = findChild(face, "forgeCardFace-" + first.cardId)
                fuzzyCompare(faceBody.width, face.width, 0.01)
                fuzzyCompare(faceBody.height, face.height, 0.01)
                const point = presentation.pointFor(first.cardId)
                verify(point.x > 0 && point.y > 0, "Every category participates in exact-card targeting: "
                    + JSON.stringify({group:group.objectName, card:first.cardId, point:point,
                        face:bounds(faceBody), viewport:bounds(group.scrollArea), allocation:bounds(group)}))
                const body = bounds(faceBody), viewport = bounds(group.scrollArea)
                const left = Math.max(body.x, viewport.x), top = Math.max(body.y, viewport.y)
                const right = Math.min(body.x + body.width, viewport.x + viewport.width)
                const bottom = Math.min(body.y + body.height, viewport.y + viewport.height)
                const visible = Qt.rect(left, top, Math.max(0, right - left), Math.max(0, bottom - top))
                verify(visible.width > 0 && visible.height > 0, "Revealing a card exposes its face")
                fuzzyCompare(visible.width, body.width, 0.1, group.objectName + " exposes the full card width")
                fuzzyCompare(visible.height, body.height, 0.1, group.objectName + " exposes the full card height")
                for (const obstacle of presentation.battlefieldObstacles)
                    verify(!(visible.x < obstacle.x + obstacle.width - 0.5 && visible.x + visible.width > obstacle.x + 0.5
                        && visible.y < obstacle.y + obstacle.height - 0.5 && visible.y + visible.height > obstacle.y + 0.5),
                        "Visible cards avoid the reserved player and decision areas: " + JSON.stringify({
                            group:group.objectName, card:first.cardId, face:visible,
                            viewport:bounds(group.scrollArea), obstacle:obstacle, allocation:bounds(group)}))
                const last = group.hostCards.filter(slot => slot.stackFront).slice(-1)[0]
                verify(presentation.reveal(last.cardId))
                verify(waitForPolish(window))
                const lastPoint = presentation.pointFor(last.cardId)
                verify(lastPoint.x > 0 && lastPoint.y > 0,
                    "The last card in a scrolling category remains exactly targetable: "
                    + JSON.stringify({group:group.objectName, card:last.cardId, point:lastPoint,
                        face:bounds(last.faceItem), viewport:bounds(group.scrollArea)}))
                const lastBody = bounds(last.faceItem), lastViewport = bounds(group.scrollArea)
                verify(lastBody.x >= lastViewport.x - 0.1 && lastBody.y >= lastViewport.y - 0.1
                    && lastBody.x + lastBody.width <= lastViewport.x + lastViewport.width + 0.1
                    && lastBody.y + lastBody.height <= lastViewport.y + lastViewport.height + 0.1,
                    "The last exact card is fully revealable: " + JSON.stringify({group:group.objectName,
                        card:last.cardId, body:lastBody, viewport:lastViewport}))
            }
            const walkerId = "z-" + seat + "-Karn, the Great Creator"
            verify(presentation.reveal(walkerId))
            const walker = item("forgeCard-" + walkerId)
            const walkerBounds = bounds(walker)
            compare(item("forgeCardLoyaltyValue-" + walkerId).text, "4")
            verify(walkers.inspectionRects(presentation).some(rect => rect.x <= walkerBounds.x + 0.1
                && rect.x + rect.width >= walkerBounds.x + walkerBounds.width - 0.1))
            stable.push({items:groups, rects:groups.map(group => bounds(group))})
        }
        // Loyalty and ordinary target prompts cannot send walkers back into
        // another category or move any of the four permanent regions.
        for (const zone of state.zones.filter(zone => zone.zone === "battlefield"))
            for (const row of zone.cards)
                if (row.identity.name === "Karn, the Great Creator") row.counters = [{name:"LOYALTY", value:7}]
        verify(testRulesPrompt.applySnapshot(state)); verify(waitForPolish(window))
        for (const before of stable)
            before.items.forEach((group, index) => compare(bounds(group), before.rects[index]))
        for (const seat of data.seats)
            compare(item("forgeCardLoyaltyValue-z-" + seat + "-Karn, the Great Creator").text, "7")
        if (data.local >= 0) {
            const targetSeat = data.seats.find(seat => seat !== data.local)
            const targetId = "z-" + targetSeat + "-Karn, the Great Creator"
            prompt("chooseBoardTargets", {minSelections:1, maxSelections:1,
                targets:[{responseId:"walker-target", kind:"card", objectId:targetId, label:"Karn"}]})
            verify(presentation.reveal(targetId)); verify(waitForPolish(window)); verify(waitForRendering(table))
            mouseClick(item("forgeCard-" + targetId))
            compare(transport.responses.length, 1)
            compare(transport.responses[0].targets, ["walker-target"])
        }
    }
    function setupNativePermanentRegions(seats, size) {
        seats = seats || [0, 1]
        size = size || {width:1920, height:1011, scale:1.2}
        // The owner's maximized screenshot uses a normal UI preference on a
        // desktop whose effective scale is 1.2, including three artifacts.
        window.width = size.width; window.height = size.height; Theme.uiScale = size.scale
        if (seats.length > 2) { room.format = "edh"; room.deckFormat = "commander"; room.maxSeats = seats.length }
        const state = zonedSnapshot(seats, 0)
        for (const zone of state.zones.filter(zone => zone.zone === "battlefield")) {
            zone.cards = zone.cards.filter(row => row.identity.name !== "Testing Enchantment")
            zone.count = zone.cards.length
        }
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        verify(waitForPolish(window)); verify(waitForRendering(table))
    }
    function test_equalLandRowsMirrorVerticallyWithoutChangingDirection() {
        setupNativePermanentRegions()
        const board = table.presentation, rows = []
        for (const prefix of ["Own", "Opponent"]) {
            const lane = item("forge" + prefix + "Lands")
            const faces = lane.hostCards.filter(slot => slot.stackFront)
                .map(slot => slot.faceItem.mapToItem(board, 0, 0, slot.width, slot.height))
            compare(faces.length, 5)
            faces.sort((a, b) => a.x - b.x)
            for (let index = 1; index < faces.length; ++index) {
                fuzzyCompare(faces[index].y, faces[0].y, 5 * board.unit,
                    prefix + " lands form a horizontal rear row: " + JSON.stringify(faces))
                verify(faces[index].x >= faces[index - 1].x + faces[index - 1].width - board.unit,
                    "Distinct land piles progress horizontally without overlap")
            }
            rows.push(faces)
        }
        // Each field fits its own reserved controls. Mirroring preserves the
        // category directions, while face sizes adapt to the available space.
        for (const row of rows) {
            verify(row[0].width >= 80 * board.unit - 0.1)
            verify(row[0].width <= 108 * board.unit + 0.1)
        }
        for (const category of ["Planeswalkers", "Other"]) {
            const own = item("forgeOwn" + category), opponent = item("forgeOpponent" + category)
            for (const lane of [own, opponent]) {
                verify(lane.cardWidth >= 80 * board.unit - 0.1)
                verify(lane.cardWidth <= 108 * board.unit + 0.1)
            }
        }
    }
    function test_planeswalkerFlankDoesNotShiftCreatureCenter() {
        setupNativePermanentRegions()
        const board = table.presentation
        for (const seat of [0, 1]) {
            const face = item("forgeCardFace-z-creature-" + seat)
            const center = face.mapToItem(board, face.width / 2, face.height / 2)
            fuzzyCompare(center.x, board.boardLeft + board.boardWidth / 2, board.unit,
                "A lone creature remains on the battlefield axis with planeswalkers and artifacts present")
        }
    }
    function test_otherPermanentsReachRightRearAboveDecisionDock() {
        setupNativePermanentRegions()
        const board = table.presentation, dock = item("rulesDecisionDock")
        for (const prefix of ["Own", "Opponent"]) {
            const lane = item("forge" + prefix + "Other")
            const faces = lane.hostCards.filter(slot => slot.stackFront)
                .map(slot => slot.faceItem.mapToItem(board, 0, 0, slot.width, slot.height))
            compare(faces.length, 3)
            const right = Math.max.apply(null, faces.map(face => face.x + face.width))
            fuzzyCompare(right, board.boardRight, 4 * board.unit,
                "The right flank uses the field edge instead of stopping beside a phantom dock column")
            if (prefix === "Own") {
                const bottom = Math.max.apply(null, faces.map(face => face.y + face.height))
                const availableBottom = Math.min(board.battlefieldBottom, board.dockReservation.y - 12 * board.unit)
                verify(bottom <= dock.y - 12 * board.unit + board.unit,
                    "The rear artifact row stays above the visible decision controls")
                verify(availableBottom - bottom <= 24 * board.unit,
                    "The rear row aligns with the stable decision reservation without a second unused band: "
                    + JSON.stringify({bottom:bottom, availableBottom:availableBottom, dockY:dock.y}))
            }
        }
    }
    function test_exactRevealHidesExpandedDecisionWithoutLosingTargetDraft_data() {
        return [{tag:"duel", seats:[0, 1], targetSeat:0},
            {tag:"four", seats:[0, 1, 2, 3], targetSeat:1}]
    }
    function test_exactRevealHidesExpandedDecisionWithoutLosingTargetDraft(data) {
        setupNativePermanentRegions(data.seats)
        const names = ["Liquimetal Coating", "Relic of Progenitus", "Trinisphere"]
        const ids = names.map(name => "z-" + data.targetSeat + "-" + name)
        const baseline = boardGeometry(ids.concat(["z-creature-" + data.targetSeat]))
        prompt("chooseBoardTargets", {title:"Choose two or three target permanents", minSelections:2, maxSelections:3,
            targets:ids.map((id, index) => ({responseId:"support-target-" + index, kind:"card",
                objectId:id, label:names[index]}))})
        const board = table.presentation, dock = item("rulesDecisionDock"), toggle = item("forgeDecisionCollapse")
        verify(dock.height > board.dockReservedHeight, "The fixture exercises an expanded board decision")
        verify(toggle.visible && !dock.collapsed)
        verify(board.reveal("z-creature-" + data.targetSeat)); verify(waitForPolish(window))
        verify(!dock.collapsed, "Revealing an uncovered creature leaves the decision visible")
        const source = item("forgeCard-" + ids[0])
        const sourceBounds = source.mapToItem(board, 0, 0, source.width, source.height)
        verify(sourceBounds.x < dock.x + dock.width && sourceBounds.x + sourceBounds.width > dock.x
            && sourceBounds.y < dock.y + dock.height && sourceBounds.y + sourceBounds.height > dock.y,
            "The expanded choice initially covers the exact right-rear target")
        verify(board.reveal(ids[0])); verify(waitForPolish(window)); verify(waitForRendering(table))
        verify(dock.collapsed, "Exact-object reveal exposes a card covered by the expanded decision")
        mouseClick(source)
        compare(table.interaction.selectedCount, 1)
        compare(transport.responses.length, 0)
        mouseClick(toggle); verify(waitForRendering(table))
        verify(!dock.collapsed)
        compare(table.interaction.selectedCount, 1, "Showing the choice retains the first selected target")
        verify(board.reveal(ids[1])); verify(waitForPolish(window)); verify(waitForRendering(table))
        verify(dock.collapsed)
        mouseClick(item("forgeCard-" + ids[1]))
        compare(table.interaction.selectedCount, 2)
        compare(transport.responses.length, 0, "Hiding a decision never submits the draft")
        compare(boardGeometry(ids.concat(["z-creature-" + data.targetSeat])), baseline,
            "Hiding and restoring a choice never moves the permanent regions")
        mouseClick(toggle); verify(waitForRendering(table))
        const confirm = item("rulesConfirmTargets")
        verify(confirm.visible && confirm.enabled)
        const confirmAt = confirm.mapToItem(dock, 0, 0, confirm.width, confirm.height)
        verify(confirmAt.x >= -0.5 && confirmAt.y >= -0.5
            && confirmAt.x + confirmAt.width <= dock.width + 0.5
            && confirmAt.y + confirmAt.height <= dock.height + 0.5,
            "Restoring the choice exposes the complete confirmation action")
        mouseClick(confirm)
        compare(transport.responses.length, 1)
        compare(transport.responses[0].targets, ["support-target-0", "support-target-1"])
    }
    function test_compactMultiplayerOverlayKeepsFieldAndHeaderStill() {
        setupNativePermanentRegions([0, 1, 2, 3], {width:900, height:620, scale:1.35})
        const inspected = item("forgeCard-z-creature-0")
        mouseClick(inspected, inspected.width / 2, inspected.height / 2, Qt.RightButton)
        tryCompare(table.inspector, "pinnedCardId", "z-creature-0")
        verify(waitForPolish(window)); verify(waitForRendering(table))
        const field = item("forgeField-1"), dock = item("rulesDecisionDock")
        verify(field.headerAboveDock, "The narrow lower-right field exercises metadata above the dock: "
            + JSON.stringify({near:field.nearSide, x:field.x, y:field.y, width:field.width,
                height:field.height, header:field.headerTop, sideWidth:field.sideHeaderWidth,
                minimum:field.minimumHeaderWidth, dock:table.presentation.dockReservation}))
        const ids = ["z-creature-0", "z-creature-1", "z-creature-2", "z-creature-3",
            "z-1-Eldrazi Temple", "z-1-Karn, the Great Creator", "z-1-Trinisphere"]
        const baseline = boardGeometry(ids)
        const fieldBounds = Qt.rect(field.x, field.y, field.width, field.height)
        const boardBounds = Qt.rect(field.inset, field.boardTop, field.width - 2 * field.inset, field.boardHeight)
        const zones = item("forgeSeatZones-1")
        const headerBounds = zones.mapToItem(table.presentation, 0, 0, zones.width, zones.height)
        function remainsStill(stage) {
            verify(waitForPolish(window)); verify(waitForRendering(table))
            compare(boardGeometry(ids), baseline, stage + " preserves every permanent")
            compare(Qt.rect(field.x, field.y, field.width, field.height), fieldBounds)
            compare(Qt.rect(field.inset, field.boardTop, field.width - 2 * field.inset, field.boardHeight),
                boardBounds, stage + " preserves the lower-right battlefield height")
            compare(zones.mapToItem(table.presentation, 0, 0, zones.width, zones.height), headerBounds,
                stage + " preserves the metadata above the stable reservation")
        }
        prompt("chooseBoardTargets", {title:"Choose two target permanents", minSelections:2, maxSelections:3,
            targets:["z-1-Liquimetal Coating", "z-1-Relic of Progenitus", "z-1-Trinisphere"]
                .map((id, index) => ({responseId:"compact-target-" + index, kind:"card", objectId:id, label:id}))})
        remainsStill("Expanded targeting")
        verify(item("forgeDecisionCollapse").visible)
        mouseClick(item("forgeDecisionCollapse"))
        verify(dock.collapsed); remainsStill("Hidden targeting")
        mouseClick(item("forgeDecisionCollapse"))
        verify(!dock.collapsed); remainsStill("Restored targeting")
        prompt("chooseAttackers", {title:"Choose attackers for the defending player",
            detail:"Select an attacker, then its defending player. ".repeat(12),
            combatSources:[{responseId:"compact-attacker", objectId:"z-creature-0", label:"Grizzly Bears",
                validTargetIds:["compact-defender"], maxAssignments:1}],
            combatTargets:[{responseId:"compact-defender", kind:"player", seat:1, label:"Player 1", maxAssignments:1}]})
        remainsStill("Expanded combat")
        verify(item("forgeDecisionCollapse").visible)
        mouseClick(item("forgeDecisionCollapse"))
        verify(dock.collapsed); remainsStill("Hidden combat")
        mouseClick(item("forgeDecisionCollapse"))
        verify(!dock.collapsed); remainsStill("Restored combat")
        compare(transport.responses.length, 0)
    }
    function test_tappingDoesNotMoveAnotherPermanent() {
        const state = snapshot(1, 0)
        const bear = card("bear", 0, "Grizzly Bears", true)
        state.zones[4].cards = [card("land-a", 0, "Plains", false), card("land-b", 0, "Plains", false), bear]
        state.zones[4].count = 3
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        const bearFace = item("forgeCard-bear")
        const before = bearFace.mapToItem(table.presentation, 0, 0)
        const sizeBefore = Qt.size(bearFace.width, bearFace.height)
        const tapped = snapshot(1, 0)
        const tappedLand = card("land-b", 0, "Plains", false)
        tappedLand.tapped = true
        tapped.zones[4].cards = [card("land-a", 0, "Plains", false), tappedLand, card("bear", 0, "Grizzly Bears", true)]
        tapped.zones[4].count = 3
        verify(testRulesPrompt.applySnapshot(tapped))
        waitForRendering(table)
        tryVerify(() => item("forgeOwnLands").stackCount === 2)
        const after = item("forgeCard-bear").mapToItem(table.presentation, 0, 0)
        compare(Math.round(after.x), Math.round(before.x))
        compare(Math.round(after.y), Math.round(before.y))
        fuzzyCompare(bearFace.width, sizeBefore.width, 0.1,
            "Tapping a land cannot resize another permanent")
        fuzzyCompare(bearFace.height, sizeBefore.height, 0.1)
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        const restored = bearFace.mapToItem(table.presentation, 0, 0)
        compare(Math.round(restored.x), Math.round(before.x))
        compare(Math.round(restored.y), Math.round(before.y))
        fuzzyCompare(bearFace.width, sizeBefore.width, 0.1)
        fuzzyCompare(bearFace.height, sizeBefore.height, 0.1)
    }
    Component {
        id: mixedSupportField
        Item {
            id: field
            width: 300; height: 340
            property bool nearSide: true
            property alias creatures: creatures
            property alias lands: lands
            property alias others: others
            ForgeFieldLayout {
                id: layout
                width: field.width; height: field.height; unit: 1
                nearSide: field.nearSide; preferCenteredRows: true
                creatureLane: creatures; landLane: lands; otherLane: others
            }
            ForgeCardLane {
                id: creatures
                tableController: table; ownerSeat: 0; category: "creature"
                showCaption: false; combatForward: field.nearSide ? -1 : 1
                alignBottom: !field.nearSide
                x: layout.placement.creatures.x; y: layout.placement.creatures.y
                width: layout.placement.creatures.width; height: layout.placement.creatures.height
            }
            ForgeCardLane {
                id: lands
                tableController: table; ownerSeat: 0; category: "land"
                showCaption: false; alignBottom: !field.nearSide
                x: layout.placement.lands.x; y: layout.placement.lands.y
                width: layout.placement.lands.width; height: layout.placement.lands.height
            }
            ForgeCardLane {
                id: others
                tableController: table; ownerSeat: 0; category: "other"
                showCaption: false; alignBottom: !field.nearSide
                x: layout.placement.others.x; y: layout.placement.others.y
                width: layout.placement.others.width; height: layout.placement.others.height
            }
        }
    }
    function test_mixedSupportTapKeepsCreatureBodyStill_data() {
        return [{tag:"near-side", nearSide:true}, {tag:"far-side", nearSide:false}]
    }
    function test_mixedSupportTapKeepsCreatureBodyStill(data) {
        catalog.typeOverrides = {"Sol Ring":"Artifact"}
        const state = snapshot(1, 1)
        state.zones[4].cards = [card("mixed-bear", 0, "Grizzly Bears", true),
            card("mixed-land-a", 0, "Plains", false), card("mixed-land-b", 0, "Plains", false),
            card("mixed-relic", 0, "Sol Ring", false)]
        state.zones[4].count = state.zones[4].cards.length
        verify(testRulesPrompt.applySnapshot(state))
        const field = createTemporaryObject(mixedSupportField, window.contentItem,
            {nearSide:data.nearSide})
        verify(field !== null)
        tryCompare(field.lands, "stackCount", 1)
        tryCompare(field.others, "stackCount", 1)
        verify(waitForPolish(window))
        const body = findChild(field.creatures.itemFor("mixed-bear"), "forgeCardFace-mixed-bear")
        verify(body !== null)
        const before = body.mapToItem(field, 0, 0, body.width, body.height)
        verify(before.width >= 80, "The compact mixed-support probe starts with a readable creature")
        for (const tapped of [true, false]) {
            const next = JSON.parse(JSON.stringify(state))
            next.zones[4].cards.find(card => card.id === "mixed-land-b").tapped = tapped
            verify(testRulesPrompt.applySnapshot(next))
            tryCompare(field.lands, "stackCount", tapped ? 2 : 1)
            verify(waitForPolish(window))
            const after = body.mapToItem(field, 0, 0, body.width, body.height)
            for (const key of ["x", "y", "width", "height"])
                fuzzyCompare(after[key], before[key], 0.1,
                    "Changing a support pile cannot change the unrelated creature body "
                    + key + ": " + JSON.stringify(before) + " -> " + JSON.stringify(after))
        }
    }
    function test_targetsAndCombatKeepIdenticalCreaturesInOneSlot() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, 2)))
        const land = item("forgeCard-land")
        const before = land.mapToItem(table.presentation, 0, 0)
        const creatures = item("forgeOwnCreatures")
        prompt("chooseAttackers", {
            combatSources:[0, 1].map(i => ({responseId:"source-" + i, objectId:"own-" + i,
                label:"Bear", name:"Grizzly Bears", validTargetIds:["defender"], maxAssignments:1})),
            combatTargets:[{responseId:"defender", kind:"player", seat:1, label:"Opponent", maxAssignments:2}]
        })
        tryCompare(creatures, "stackCount", 1)
        const duringCombat = land.mapToItem(table.presentation, 0, 0)
        compare(Math.round(duringCombat.x), Math.round(before.x))
        compare(Math.round(duringCombat.y), Math.round(before.y))
        prompt("chooseBoardTargets", {minSelections:1, maxSelections:1,
            targets:[0, 1].map(i => ({responseId:"target-" + i, kind:"card",
                objectId:"own-" + i, label:"Bear", name:"Grizzly Bears"}))})
        tryCompare(creatures, "stackCount", 1)
        const duringTargets = land.mapToItem(table.presentation, 0, 0)
        compare(Math.round(duringTargets.x), Math.round(before.x))
        compare(Math.round(duringTargets.y), Math.round(before.y))
        mouseClick(item("forgeCard-own-1"))
        compare(table.interaction.selectedTargetIds["target-0"], true)
    }
    function test_nativeModelsPopulateBothSidesAndHand() {
        tryVerify(() => item("forgeOwnCreatures").visibleCards.length === 1)
        compare(item("forgeOpponentCreatures").visibleCards.length, 1)
        compare(item("forgeOwnLands").visibleCards.length, 1)
        compare(item("forgeHand").visibleCards.length, 1)
        verify(item("forgeOwnCreatures").y > item("forgeOpponentCreatures").y)
        mouseClick(item("rulesPromptOption-$ack"))
        compare(transport.responses[0].response, "$ack")
    }
    function test_localizedForgeDecision_data() {
        const opening = "Alice, you have won the coin toss.\n\nWould you like to play or draw?"
        return [
            {tag:"play", detail:opening, title:"选择先手或后手", translatedDetail:"Alice，你赢得了先手掷币。\n\n你要选择先手还是后手？",
                choices:["Draw", "Play"], labels:["后手", "先手"], selected:1},
            {tag:"draw", detail:opening, title:"选择先手或后手", translatedDetail:"Alice，你赢得了先手掷币。\n\n你要选择先手还是后手？",
                choices:["Draw", "Play"], labels:["后手", "先手"], selected:0},
            {tag:"trigger", detail:"Use triggered ability of Guide of Souls (42)?", title:"确认选择",
                translatedDetail:"是否使用 Guide of Souls (42) 的触发式异能？", choices:["No", "Yes"], labels:["否", "是"], selected:1},
            {tag:"payment", detail:"Do you want to pay 2 life?", title:"确认选择",
                translatedDetail:"是否支付 2 点生命？", choices:["Cancel", "OK"], labels:["取消", "确定"], selected:0},
            {tag:"surveil", detail:"Put Troll of Khazad-dûm (38) on the top of library or graveyard?", title:"确认选择",
                translatedDetail:"将 Troll of Khazad-dûm (38) 留在牌库顶，还是置入墓地？",
                choices:["Graveyard", "Library"], labels:["墓地", "牌库"], selected:0}
        ]
    }
    function test_aiDeckAdvisoryContinuesSilently_data() {
        return [{tag:"en", language:"en", width:1600, height:1000, scale:1},
            {tag:"zh", language:"zh", width:1600, height:1000, scale:1},
            {tag:"compact", language:"zh", width:900, height:620, scale:1},
            {tag:"scaled", language:"zh", width:1280, height:800, scale:1.35}]
    }
    function test_aiDeckAdvisoryContinuesSilently(data) {
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        const warning = "AI can't play these cards well from Forge AI's Deck\n=== Main Deck ===\nPrismatic Ending\n=== Sideboard ===\nWrath of the Skies\nYou can continue this game. These cards will remain in the deck."
        prompt("acknowledge", {title:"AI deck advisory", detail:warning,
            options:[{responseId:"$ack", kind:"acknowledge", label:"Continue"}]})
        testTranslations.setLanguage(data.language)
        tryVerify(() => transport.responses.length === 1)
        compare(transport.responses[0].response, "$ack")
        compare(transport.responses[0].id, table.rulesSession.promptId)
        verify(!item("rulesDecisionDock").expanded)
        verify(!item("rulesPromptTitle").visible)
        verify(!item("rulesPromptDetail").visible)
        verify(!item("rulesPromptOption-$ack").visible)
        const id = table.rulesSession.promptId
        prompt("acknowledge", {promptId:id, title:"AI deck advisory", detail:warning,
            options:[{responseId:"$ack", kind:"acknowledge", label:"Continue"}]})
        wait(20)
        compare(transport.responses.length, 1, "Repeated publications must not resubmit a notice")
    }
    function test_aiDeckAdvisoryDoesNotRespondForSpectator() {
        room.role = "spectator"; room.seatIndex = -1
        prompt("acknowledge", {title:"AI deck advisory",
            options:[{responseId:"$ack", kind:"acknowledge", label:"Continue"}]})
        wait(20)
        compare(transport.responses.length, 0)
    }
    function test_gameNoticeStillRequiresAcknowledgement() {
        prompt("acknowledge", {title:"Game notice", detail:"A real game notice",
            options:[{responseId:"$ack", kind:"acknowledge", label:"Continue"}]})
        wait(20)
        compare(transport.responses.length, 0)
        verify(item("rulesPromptDetail").visible)
        mouseClick(item("rulesPromptOption-$ack"))
        compare(transport.responses.length, 1)
    }
    function test_equalBooleanLabelsRemainDistinctDecisions() {
        prompt("chooseBoolean", {title:"Confirm decision", detail:"A native boolean decision",
            minChoiceTotal:1, maxChoiceTotal:1,
            choices:[{responseId:"choice:0", label:"Continue", weight:1, canRepeat:false},
                {responseId:"choice:1", label:"Continue", weight:1, canRepeat:false}]})
        compare(item("rulesScalarCandidates").count, 2)
        verify(item("rulesScalarChoice-choice:0").visible)
        verify(item("rulesScalarChoice-choice:1").visible)
        mouseClick(item("rulesScalarChoice-choice:1"))
        compare(transport.responses.length, 1)
        compare(transport.responses[0].choices, ["choice:1"])
    }
    function test_localizedForgeDecision(data) {
        prompt("chooseBoolean", {title:"Confirm decision", detail:data.detail,
            minChoiceTotal:1, maxChoiceTotal:1,
            choices:data.choices.map((label, index) => ({responseId:"choice:" + index, label:label, weight:1, canRepeat:false}))})
        const title = item("rulesPromptTitle"), detail = item("rulesPromptDetail")
        testTranslations.setLanguage("zh")
        tryCompare(title, "text", data.title)
        compare(detail.text, data.translatedDetail)
        for (let i = 0; i < data.labels.length; ++i)
            compare(item("rulesScalarChoice-choice:" + i).text, data.labels[i])
        testTranslations.setLanguage("en")
        tryCompare(item("rulesScalarChoice-choice:0"), "text", data.choices[0] === "Draw" ? "Draw first" : data.choices[0])
        testTranslations.setLanguage("zh")
        tryCompare(title, "text", data.title)
        compare(table.rulesSession.promptTitle, "Confirm decision")
        compare(table.rulesSession.promptDetail, data.detail)
        mouseClick(item("rulesScalarChoice-choice:" + data.selected))
        compare(transport.responses.length, 1)
        compare(transport.responses[0].choices, ["choice:" + data.selected])
        compare(transport.responses[0].id, table.rulesSession.promptId)
    }
    function test_modalChoiceAndTargetNameTheCurrentEffect() {
        const english = "Choose two —\n"
                + "• Target player creates X 0/1 colorless Eldrazi Spawn creature tokens.\n"
                + "• Target player scries X, then draws a card."
        const chinese = "选择两项～\n"
                + "• 目标牌手派出衍生生物。\n"
                + "• 目标牌手占卜 X，然后抓一张牌。"
        catalog.language = "zh"
        catalog.names = {"Kozilek's Command": "寇基雷的指令"}
        catalog.rules = {en: {"Kozilek's Command": english}, zh: {"Kozilek's Command": chinese}}
        testTranslations.setLanguage("zh")
        prompt("chooseFromSelection", {
            title: "claystan activated Kozilek's Command - Choose a mode",
            minChoiceTotal: 2, maxChoiceTotal: 2,
            choices: [
                {responseId: "choice:0", label: "Target player creates X 0/1 colorless Eldrazi Spawn creature tokens.", weight: 1, canRepeat: false},
                {responseId: "choice:1", label: "Target player scries X, then draws a card.", weight: 1, canRepeat: false}
            ]
        })
        compare(item("rulesPromptTitle").text, "claystan 起动了 寇基雷的指令 — 选择模式")
        compare(item("rulesScalarChoice-choice:0").text, "目标牌手派出衍生生物。")
        compare(item("rulesScalarChoice-choice:1").text, "目标牌手占卜 X，然后抓一张牌。")
        prompt("chooseBoardTargets", {
            title: "Choose a card or player",
            detail: "Kozilek's Command (5) - Target player creates X 0/1 colorless Eldrazi Spawn creature tokens. "
                    + "Target player scries X, then draws a card.\nSelect target player",
            contextText: english,
            contextCards: [{id: "context-card:0", name: "Kozilek's Command", setCode: "MH3", collectorNumber: "11"}],
            minSelections: 1, maxSelections: 1,
            targets: [{responseId: "player:0", kind: "player", label: "You"}]
        })
        compare(item("rulesPromptTitle").text, "当前效果：目标牌手派出衍生生物。")
        compare(item("rulesPromptDetail").text, "选择目标牌手")
        compare(item("rulesPromptContextText").text, english)
        verify(!item("rulesPromptContextText").visible,
            "The full context remains available for inspection without repeating it in the initial dock")
        prompt("chooseBoardTargets", {
            title: "Choose a card or player",
            detail: "Kozilek's Command (5) - Target player scries X, then draws a card.\nSelect target player",
            contextText: english,
            contextCards: [{id: "context-card:0", name: "Kozilek's Command", setCode: "MH3", collectorNumber: "11"}],
            minSelections: 1, maxSelections: 1,
            targets: [{responseId: "player:0", kind: "player", label: "You"}]
        })
        compare(item("rulesPromptTitle").text, "当前效果：目标牌手占卜 X，然后抓一张牌。")
        compare(item("rulesPromptDetail").text, "选择目标牌手")
    }
    function test_singleOpeningAbilityAsksInsteadOfOrdering() {
        catalog.language = "zh"
        catalog.names = {"Devourer of Destiny": "命运吞噬者"}
        testTranslations.setLanguage("zh")
        prompt("chooseCards", {
            title: "Choose cards to activate from opening hand and their order",
            minCardSelections: 0, maxCardSelections: 1,
            cards: [{id: "card-devourer", name: "Devourer of Destiny", setCode: "MH3", collectorNumber: "1"}]
        })
        const popup = item("rulesCardChoiceDialog")
        tryCompare(popup, "visible", true)
        tryVerify(() => findChild(popup.contentItem, "rulesOpeningAbilityUse") !== null)
        compare(findChild(popup.contentItem, "rulesChoiceTitle").text, "是否使用命运吞噬者的开局异能？")
        verify(findChild(popup.contentItem, "rulesCardSelectionPrompt") === null)
        mouseClick(findChild(popup.contentItem, "rulesOpeningAbilityUse"))
        compare(transport.responses.length, 1)
        compare(transport.responses[0].cards, ["card-devourer"])
        prompt("chooseCards", {
            title: "Choose cards to activate from opening hand and their order",
            minCardSelections: 0, maxCardSelections: 2,
            cards: [{id: "card-a", name: "Leyline of the Void"},
                    {id: "card-b", name: "Leyline of Sanctity"}]
        })
        tryCompare(popup, "visible", true)
        verify(findChild(popup.contentItem, "rulesCardSelectionPrompt") !== null)
        verify(findChild(popup.contentItem, "rulesOpeningAbilityUse") === null)
    }
    function previewFaces() {
        const faces = [
            {name:"Delver of Secrets", faceName:"", displayName:"Delver of Secrets", setCode:"ISD", collectorNumber:"51"},
            {name:"Insectile Aberration", faceName:"Insectile Aberration", displayName:"Insectile Aberration", setCode:"ISD", collectorNumber:"51"}]
        catalog.faceOverrides = ({"Delver of Secrets":faces, "Insectile Aberration":faces})
        const image = color => "data:image/svg+xml," + encodeURIComponent(
            '<svg xmlns="http://www.w3.org/2000/svg" width="63" height="88"><rect width="63" height="88" fill="' + color + '"/></svg>')
        catalog.faceImages = ({"Delver of Secrets":image("red"), "Insectile Aberration":image("blue")})
    }
    function verifyFaceGallery(preview, artName, names) {
        const expected = names || ["Delver of Secrets", "Insectile Aberration"]
        const controller = preview.facePreview || preview.controller || preview.inspector.facePreview
        compare(controller.displayFaces.map(face => face.name), expected)
        compare(findChild(preview, "viewOtherFaceButton"), null)
        for (let index = 0; index < expected.length; ++index) {
            const art = findChild(preview, artName + (index ? "-" + index : ""))
            verify(art !== null)
            tryCompare(art, "visible", true)
            tryCompare(art, "status", Image.Ready)
            compare(decodeURIComponent(String(art.source)), decodeURIComponent(catalog.faceImages[expected[index]]))
        }
    }
    Component {
        id: previewInputTargetComponent
        MouseArea {
            acceptedButtons: Qt.AllButtons
            property int clicks: 0
            onClicked: clicks++
        }
    }
    Component {
        id: otherWindowComponent
        ApplicationWindow { width:320; height:200; visible:true; transientParent:null }
    }
    function test_modalCandidateBothFacesKeepNativeDecision_data() {
        return ["chooseCards", "revealCards", "scry", "reorder"].map(kind => ({tag:kind, kind:kind}))
    }
    function test_modalCandidateBothFacesKeepNativeDecision(data) {
        previewFaces()
        const candidate = {id:data.kind === "scry" ? "scry:0" : "physical-dfc", name:"Delver of Secrets", setCode:"ISD", collectorNumber:"51"}
        prompt(data.kind, {cards:[candidate], minCardSelections:1, maxCardSelections:1,
            scryDestinations:data.kind === "scry" ? ["libraryTop", "libraryBottom"] : [],
            orderItems:data.kind === "reorder" ? [{responseId:"order:0", name:candidate.name, setCode:"ISD", collectorNumber:"51"}] : []})
        const popup = item("rulesCardChoiceDialog")
        tryCompare(popup, "opened", true)
        const content = findChild(popup.contentItem, "rulesChoiceContent").item
        const list = findChild(content, data.kind === "chooseCards" ? "rulesCardCandidates"
            : data.kind === "revealCards" ? "revealCardList"
            : data.kind === "scry" ? "rulesScryCards-libraryTop" : "rulesOrderCandidates")
        tryCompare(list, "count", 1)
        waitForRendering(list)
        const tile = list.itemAtIndex(0)
        verify(tile !== null)
        mouseMove(tile, tile.width / 2, 40)
        const preview = findChild(content, data.kind === "chooseCards" || data.kind === "revealCards"
            ? "rulesBrowserCardPreview" : data.kind === "scry" ? "rulesScryCardPreview" : "rulesOrderCardPreview")
        tryCompare(preview, "visible", true)
        const artName = data.kind === "chooseCards" || data.kind === "revealCards"
            ? "rulesBrowserCardPreviewArt" : "cardHoverPreviewArt"
        verifyFaceGallery(preview, artName)
        mouseMove(findChild(preview, artName + "-1"))
        wait(380)
        verify(preview.visible, "Both faces remain reachable from the modal candidate")
        compare(transport.responses.length, 0)
        if (data.kind !== "reorder") compare(table.rulesSession.promptCards.items()[0].name, candidate.name)
        if (data.kind === "chooseCards") compare(content.selectedCount, 0)
        preview.hide()
        if (data.kind === "chooseCards") {
            mouseClick(tile)
            mouseClick(findChild(content, "rulesConfirmCards"))
            compare(transport.responses[0].cards, [candidate.id])
        } else if (data.kind === "revealCards") {
            mouseClick(findChild(content, "acknowledgeRevealButton"))
            compare(transport.responses[0].response, "$ack")
        } else if (data.kind === "scry") {
            compare(content.cardsForPile(0)[0].cardId, candidate.id)
            mouseClick(findChild(content, "confirmScryButton"))
            compare(transport.responses[0].piles[0].cardIds, [candidate.id])
        } else {
            mouseClick(findChild(content, "rulesConfirmOrder"))
            compare(transport.responses[0].order, ["order:0"])
        }
    }
    function test_openingAbilityBothFacesDoNotUseAbility() {
        previewFaces()
        prompt("chooseCards", {title:"Choose cards to activate from opening hand and their order",
            minCardSelections:0, maxCardSelections:1,
            cards:[{id:"opening-dfc", name:"Delver of Secrets", setCode:"ISD", collectorNumber:"51"}]})
        const popup = item("rulesCardChoiceDialog")
        tryCompare(popup, "opened", true)
        const content = findChild(popup.contentItem, "rulesChoiceContent").item
        const gallery = findChild(content, "rulesOpeningAbilityGallery")
        verify(gallery !== null)
        verifyFaceGallery(gallery, "rulesOpeningAbilityArt")
        compare(table.rulesSession.promptCards.items()[0].name, "Delver of Secrets")
        compare(transport.responses.length, 0)
        mouseClick(findChild(content, "rulesOpeningAbilityUse"))
        compare(transport.responses[0].cards, ["opening-dfc"])
    }
    function test_modalContextBothFacesAreReachableWithoutResponding() {
        previewFaces()
        prompt("chooseCards", {cards:[{id:"candidate", name:"Plains"}], minCardSelections:1, maxCardSelections:1,
            contextCards:[{id:"context-card:0", name:"Delver of Secrets", setCode:"ISD", collectorNumber:"51"}]})
        const popup = item("rulesCardChoiceDialog")
        tryCompare(popup, "opened", true)
        const context = findChild(popup.contentItem, "rulesPromptContext")
        const source = findChild(context, "rulesPromptSourceCard")
        mouseMove(source, source.width / 2, source.height / 2)
        const preview = findChild(context, "rulesPromptCardPreview")
        tryCompare(preview, "visible", true)
        verifyFaceGallery(preview, "rulesPromptCardPreviewArt")
        waitForRendering(preview)
        tryVerify(() => preview.visible && preview.x >= 0 && preview.y >= 0
            && preview.x + preview.width <= preview.parent.width
            && preview.y + preview.height <= preview.parent.height)
        const promptId = table.rulesSession.promptId
        const contextCards = JSON.stringify(table.rulesSession.promptContextCards.items())
        mouseMove(findChild(preview, "rulesPromptCardPreviewArt-1"))
        tryCompare(preview, "previewHeld", true)
        wait(380)
        verify(preview.visible)
        compare(table.rulesSession.promptId, promptId)
        compare(JSON.stringify(table.rulesSession.promptContextCards.items()), contextCards)
        compare(transport.responses.length, 0)
        mouseClick(findChild(popup.contentItem, "rulesChoiceViewBattlefield"))
        tryCompare(popup, "visible", false)
        compare(preview.visible, false)
    }
    function test_unusedManaUndoesFromTheLand_data() {
        return [{tag:"floating-before-cast", kind:"chooseAction"},
            {tag:"unfinished-payment", kind:"payManaCost"}]
    }
    function test_unusedManaUndoesFromTheLand(data) {
        testTranslations.setLanguage("zh")
        const state = landBoard(["land-a", "land-b"], ["land-a"])
        state.players[0].manaPool = [{name:"W", value:1}]
        verify(testRulesPrompt.applySnapshot(state))
        prompt(data.kind, {title:"Choose",
            options:[{responseId:"action:0", cardId:"land-b", kind:"activateAbility", label:"Plains — Tap for mana"},
                     {responseId:"action:1", cardId:"land-a", kind:"undoMana", label:"Undo mana"}]})
        const source = item("forgeCard-land-a")
        compare(item("forgeCardInteractionHint-land-a").text, "撤回法术力")
        verify(source.undoingMana && source.offeredUndo)
        compare(findChild(source, "forgeCardStateOutline-" + source.objectId).border.color, "#7ebcca")
        compare(findChild(table, "rulesPromptOption-action:1"), null, "An option on the table gets no dock button")
        mouseClick(source)
        compare(transport.responses.length, 1)
        compare(transport.responses[0].response, "action:1")
        verify(source.card.tapped, "A response never locally untaps the source")
        compare(item("forgeMana-0-W").modelData.amount, 1, "Only the engine snapshot can refund mana")
        verify(source.waiting && !source.undoingMana && source.offeredUndo)
        compare(findChild(source, "forgeCardStateOutline-" + source.objectId).border.color, Theme.withAlpha("#7ebcca", 0.5))
        mouseClick(source)
        compare(transport.responses.length, 1, "A pending undo cannot be submitted twice")
    }
    function test_floatingManaPressCannotAnswerTheNextUndoPrompt() {
        landBoard(["land-a"])
        prompt("chooseAction", {options:[
            {responseId:"activate-a", kind:"activateAbility", cardId:"land-a", label:"Add {W}"}]})
        const source = item("forgeCard-land-a")
        mouseClick(source)
        compare(transport.responses.length, 1)
        mousePress(source)
        const state = landBoard(["land-a"], ["land-a"])
        state.players[0].manaPool = [{name:"W", value:1}]
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[
            {responseId:"undo-a", kind:"undoMana", cardId:"land-a", label:"Undo mana"}]})
        mouseRelease(source)
        compare(transport.responses.length, 1, "An in-flight activation gesture cannot turn into an undo")
        compare(table.interaction.paymentQueue, [], "Priority undo never enters the payment click queue")
        mouseClick(source)
        compare(transport.responses.length, 2)
        compare(transport.responses[1].response, "undo-a")
    }
    function test_priorityManaClickDoesNotQueueAnotherSource() {
        prompt("chooseAction", {options:[
            {responseId:"activate-land", kind:"activateAbility", cardId:"land", label:"Add {W}"},
            {responseId:"activate-creature", kind:"activateAbility", cardId:"own-0", label:"Add {G}"}]})
        mouseClick(item("forgeCard-land"))
        compare(transport.responses.length, 1)
        mouseClick(item("forgeCard-own-0"))
        compare(transport.responses.length, 1, "Priority has no queued mana activations")
        compare(table.interaction.paymentQueue, [])
        verify(item("forgeWaitingCue").visible)
    }
    function test_floatingManaUndoWithAnotherAbilityNeedsAChoice() {
        landBoard(["land-a"], ["land-a"])
        prompt("chooseAction", {options:[
            {responseId:"other-a", kind:"activateAbility", cardId:"land-a", label:"Another ability"},
            {responseId:"undo-a", kind:"undoMana", cardId:"land-a", label:"Undo mana"}]})
        mouseClick(item("forgeCard-land-a"))
        compare(transport.responses.length, 0, "Undo must not silently replace another legal action")
        tryCompare(table.cardActionPicker, "opened", true)
        mouseClick(item("rulesCardAction-undo-a"))
        compare(transport.responses.length, 1)
        compare(transport.responses[0].response, "undo-a")
    }
    function test_floatingManaUndoDisappearsWithItsDecision() {
        landBoard(["land-a"], ["land-a"])
        const options = [{responseId:"undo-a", kind:"undoMana", cardId:"land-a", label:"Undo mana"}]
        prompt("chooseAction", {options:options})
        const source = item("forgeCard-land-a")
        verify(source.undoingMana)
        prompt("chooseAction", {options:[]})
        verify(!source.undoingMana && !source.offeredUndo)
        mouseClick(source)
        compare(transport.responses.length, 0, "A revoked source cannot submit its previous undo")
        room.role = "spectator"; room.seatIndex = -1
        prompt("chooseAction", {options:options})
        verify(!source.undoingMana && !source.offeredUndo && !source.actionable)
        mouseClick(source)
        compare(transport.responses.length, 0, "Spectators cannot undo another player's source")
    }
    function test_landClickAndPendingResponseProtection() {
        action("playLand", "hand-0")
        const hand = item("forgeHandSurface-hand-0")
        tryCompare(hand, "actionable", true)
        mouseClick(item("forgeHandCard-hand-0"))
        compare(transport.responses.length, 1)
        compare(transport.responses[0].response, "opaque-play")
        mouseClick(item("forgeHandCard-hand-0"))
        compare(transport.responses.length, 1)
        verify(hand.offered && hand.waiting && hand.submitted)
        verify(item("forgeWaitingCue").visible, "A blocked click explains why nothing happened")
    }
    function test_londonMulliganKeepsHandBeforeChoosingBottomCards_data() {
        return [{tag:"one-mulligan", count:1}, {tag:"two-mulligans", count:2}]
    }
    function test_mulliganHandAbilitiesUseOnlyCurrentOfferedResponses() {
        const state = snapshot(3)
        state.zones[0].cards[0].identity.name = "Serum Powder"
        state.zones[0].cards[1].identity.name = "Serum Powder"
        verify(testRulesPrompt.applySnapshot(state))
        const fixed = [{responseId:"$keep", kind:"keep", label:"Keep hand"},
            {responseId:"$mulligan", kind:"mulligan", label:"Take a mulligan"}]
        prompt("mulligan", {title:"Opening hand", options:fixed.concat([
            {responseId:"opaque-powder-a", kind:"activateAbility", cardId:"hand-0", label:"Exile hand and redraw"},
            {responseId:"opaque-powder-b", kind:"activateAbility", cardId:"hand-1", label:"Exile hand and redraw"}])})
        verify(item("forgeHandSurface-hand-0").actionable)
        verify(item("forgeHandSurface-hand-1").actionable)
        verify(!item("forgeHandSurface-hand-2").actionable)
        verify(!table.canDragHandCard("hand-0"))
        compare(findChild(table, "rulesPromptOption-opaque-powder-a"), null)
        verify(item("rulesPromptOption-$keep").visible)
        verify(item("rulesPromptOption-$mulligan").visible)
        mouseClick(item("forgeHandCard-hand-1"))
        compare(transport.responses, [{id:table.rulesSession.promptId, response:"opaque-powder-b"}])
        verify(item("forgeHandSurface-hand-1").waiting)
        mouseClick(item("forgeHandCard-hand-0"))
        compare(transport.responses.length, 1)
        prompt("mulligan", {title:"Opening hand", options:fixed.concat([
            {responseId:"opaque-powder-redraw", kind:"activateAbility", cardId:"hand-0", label:"Exile hand and redraw"}])})
        verify(!item("forgeHandSurface-hand-1").offered)
        verify(!table.interaction.submitCardAction("hand-0", "opaque-powder-a"))
        mouseClick(item("forgeHandCard-hand-0"))
        compare(transport.responses[1], {id:table.rulesSession.promptId, response:"opaque-powder-redraw"})
    }
    function test_necroNativeHelperReadsLifeFromRenderedPlayerRoles_data() {
        return [{tag:"duel", seats:2}, {tag:"multiplayer field", seats:4}]
    }
    function test_necroNativeHelperReadsLifeFromRenderedPlayerRoles(data) {
        const state = data.seats === 2 ? snapshot() : edhSnapshot([0,1,2,3], 0)
        if (data.seats === 4) { room.format = "edh"; room.maxSeats = 4 }
        state.players[0].life = 13
        state.players[1].life = 17
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(table.presentation, "multiplayer", data.seats > 2)
        const driver = {table:table, session:table.rulesSession,
            require:(ok, message) => verify(ok, message)}
        compare(NecroStudy.counts(driver, 0).life, 13)
        compare(NecroStudy.counts(driver, 1).life, 17)
    }
    function test_necroNativeHelperMatchesSourceLessLifePayment() {
        const state = snapshot()
        state.step = "end"
        state.zones[4].cards[0].identity.name = "Necrodominance"
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseNumber", {title:"Choose X for Necrodominance", minNumber:0, maxNumber:20})
        compare(table.rulesSession.promptContextCards.items().length, 0)
        verify(NecroStudy.lifePaymentPromptMatches(table.rulesSession, "wait-trigger", "own-0"))
        verify(NecroStudy.lifePaymentPromptMatches(table.rulesSession, "number-input", "own-0"))
        verify(!NecroStudy.lifePaymentPromptMatches(table.rulesSession, "play-necro", "own-0"))
        verify(!NecroStudy.lifePaymentPromptMatches(table.rulesSession, "wait-trigger", "hand-0"))
        prompt("chooseNumber", {title:"Choose X for another spell", minNumber:0, maxNumber:20})
        verify(!NecroStudy.lifePaymentPromptMatches(table.rulesSession, "wait-trigger", "own-0"))
    }
    function test_necroNativeHelperConfirmsSourceLessLifePayment() {
        const state = snapshot()
        state.step = "end"
        state.zones[4].cards[0].identity.name = "Necrodominance"
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseBoolean", {title:"Confirm decision", detail:"Do you want to pay 10 life?",
            minChoiceTotal:1, maxChoiceTotal:1,
            choices:[{responseId:"choice:0", label:"No", weight:1, canRepeat:false},
                {responseId:"choice:1", label:"Yes", weight:1, canRepeat:false}]})
        compare(table.rulesSession.promptContextCards.items().length, 0)
        verify(NecroStudy.lifePaymentConfirmationMatches(table.rulesSession, "wait-draw", "own-0", 10))
        verify(!NecroStudy.lifePaymentConfirmationMatches(table.rulesSession, "wait-trigger", "own-0", 10))
        verify(!NecroStudy.lifePaymentConfirmationMatches(table.rulesSession, "wait-draw", "hand-0", 10))
        verify(!NecroStudy.lifePaymentConfirmationMatches(table.rulesSession, "wait-draw", "own-0", 5))
        const driver = {table:table, session:table.rulesSession,
            require:(ok, message) => verify(ok, message), item:name => findChild(table, name),
            click:name => { mouseClick(item(name)); return true }}
        NecroStudy.confirmLifePayment(driver, "wait-draw", "own-0", 10)
        compare(transport.responses, [{id:table.rulesSession.promptId, choices:["choice:1"]}])
    }
    function test_necroNativeHelperWaitsForCurrentPromptLayout() {
        action("cast", "hand-0")
        const driver = {table:table, session:table.rulesSession,
            item:name => findChild(table, name)}
        NecroStudy.resetInputLayout()
        verify(!NecroStudy.inputLayoutReady(driver, 1000, false))
        verify(!NecroStudy.inputLayoutReady(driver, 1499, false))
        verify(NecroStudy.inputLayoutReady(driver, 1500, false))
        action("cast", "hand-0")
        verify(!NecroStudy.inputLayoutReady(driver, 1501, false))
        verify(NecroStudy.inputLayoutReady(driver, 2001, false))
        verify(!NecroStudy.inputLayoutReady(driver, 2002, true))
        verify(!NecroStudy.inputLayoutReady(driver, 3000, false))
        verify(NecroStudy.inputLayoutReady(driver, 3500, false))
        window.width = 1200
        waitForRendering(table)
        verify(!NecroStudy.inputLayoutReady(driver, 3501, false))
        verify(NecroStudy.inputLayoutReady(driver, 4001, false))
    }
    function test_necroNativeHelperDismissesMenuWithoutYielding() {
        action("cast", "hand-0")
        mouseClick(item("rulesYieldMenuButton"))
        tryCompare(table.priority, "passMenuOpen", true)
        verify(!table.priority.canPass)
        const driver = {table:table, require:(ok, message) => verify(ok, message)}
        verify(NecroStudy.recoverPassMenu(driver, () => { keyClick(Qt.Key_Escape); return true }))
        tryCompare(table.priority, "passMenuOpen", false)
        compare(table.priority.yieldMode, "")
        verify(!table.priority.holdNextPriority && !table.priority.heldPrompt && !table.priority.fullControl)
        compare(transport.responses.length, 0)
        verify(!NecroStudy.recoverPassMenu(driver, () => { fail("Unopened menu must not send Escape"); return false }))
        wait(500)
        tryCompare(table.priority, "canPass", true)
        const pass = findChild(item("rulesActionBar"), "rulesPromptOption-$pass")
        verify(pass.visible && pass.enabled)
        mouseClick(pass)
        compare(transport.responses, [{id:table.rulesSession.promptId, response:"$pass"}])
    }
    function test_londonMulliganKeepsHandBeforeChoosingBottomCards(data) {
        const popup = item("rulesCardChoiceDialog")
        let currentHand = []
        for (let round = 0; round <= data.count; ++round) {
            const state = snapshot(7)
            currentHand = state.zones[0].cards.map((entry, index) =>
                Object.assign({}, entry, {id:"opening-" + round + "-" + index}))
            state.zones[0].cards = currentHand
            verify(testRulesPrompt.applySnapshot(state))
            prompt("mulligan", {title:"Opening hand", detail:"Mulligans taken: " + round,
                options:[{responseId:"$keep", kind:"keep", label:"Keep hand"},
                    {responseId:"$mulligan", kind:"mulligan", label:"Take a mulligan"}]})
            tryCompare(popup, "visible", false)
            verify(findChild(popup.contentItem, "rulesCardSelectionPrompt") === null)
            verify(item("rulesPromptOption-$keep").visible)
            verify(item("rulesPromptOption-$mulligan").visible)
            mouseClick(item("forgeHandCard-" + currentHand[0].id))
            compare(transport.responses.length, round)
            const response = round < data.count ? "$mulligan" : "$keep"
            mouseClick(item("rulesPromptOption-" + response))
            compare(transport.responses.length, round + 1)
            compare(transport.responses[round], {id:table.rulesSession.promptId, response:response})
            verify(!popup.visible, "Keeping the hand must wait for Forge's separate put-back prompt")
        }
        prompt("mulliganPutBack", {title:"Put cards on the bottom of your library",
            cards:currentHand.map(entry => ({id:entry.id, name:entry.identity.name})),
            minCardSelections:data.count, maxCardSelections:data.count})
        tryCompare(popup, "visible", true)
        const list = findChild(popup.contentItem, "rulesCardCandidates")
        const confirm = findChild(popup.contentItem, "rulesConfirmCards")
        tryCompare(list, "count", 7)
        compare(confirm.text, "Put on library bottom")
        verify(!confirm.enabled)
        verify(!findChild(popup.contentItem, "rulesCancelCards").visible)
        const selected = []
        waitForRendering(list)
        for (let index = 0; index < data.count; ++index) {
            const cardIndex = 1 + index * 2
            mouseClick(list.itemAtIndex(cardIndex))
            selected.push(currentHand[cardIndex].id)
            compare(confirm.enabled, selected.length === data.count)
            compare(transport.responses.length, data.count + 1)
        }
        mouseClick(confirm)
        compare(transport.responses.length, data.count + 2)
        compare(transport.responses[data.count + 1],
            {id:table.rulesSession.promptId, response:"$submit", cards:selected})
        verify(!confirm.enabled)
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        tryCompare(popup, "visible", false)
    }
    function test_cardChoiceDialogUsesCurrentPrivateCandidates_data() {
        return [{tag:"desktop", width:1600, height:1000, scale:1},
            {tag:"laptop", width:1280, height:800, scale:1},
            {tag:"scaled", width:1180, height:740, scale:1.35}]
    }
    function test_cardChoiceDialogUsesCurrentPrivateCandidates(data) {
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        prompt("chooseCards", {cards:Array.from({length:45}, (_, i) => ({id:"candidate-" + i, name:"Plains " + i})),
            minCardSelections:1, maxCardSelections:1})
        const popup = item("rulesCardChoiceDialog")
        tryCompare(popup, "visible", true)
        verify(table.priorityInputBlocked)
        verify(!table.presentation.decisionDock.expanded)
        const search = findChild(popup.contentItem, "rulesCardFilter")
        const list = findChild(popup.contentItem, "rulesCardCandidates")
        verify(search !== null && list !== null)
        tryCompare(list, "count", 45)
        verify(popup.width > table.presentation.decisionDock.width * 2)
        verify(popup.x >= 0 && popup.y >= 0 && popup.x + popup.width <= window.width + 1
            && popup.y + popup.height <= window.height + 1)
        search.text = "Plains 44"
        tryCompare(list, "count", 1)
        waitForRendering(list)
        mouseClick(list.itemAtIndex(0))
        const confirm = findChild(popup.contentItem, "rulesConfirmCards")
        verify(confirm.enabled)
        verify(confirm.mapToItem(popup.contentItem, 0, confirm.height).y <= popup.contentItem.height + 1)
        mouseClick(confirm)
        compare(transport.responses.length, 1)
        compare(transport.responses[0].cards, ["candidate-44"])
        verify(!confirm.enabled)
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        tryCompare(popup, "visible", false)
        verify(!table.priorityInputBlocked)
    }
    function test_decisionInspectionRetainsDraft_data() {
        return ["chooseCards", "mulliganPutBack", "revealCards", "scry", "reorder",
                "chooseDamageAssignmentOrder", "chooseCombatDamageAssignment"].map(kind => ({tag:kind, kind:kind}))
    }
    function test_decisionInspectionRetainsDraft(data) {
        const state = snapshot()
        state.zones.push({zone:"graveyard", ownerSeat:0, count:1,
            cards:[card("grave-card", 0, "Graveyard creature", true)]})
        state.zones.push({zone:"exile", ownerSeat:1, count:1,
            cards:[card("exile-card", 1, "Exiled creature", true)]})
        verify(testRulesPrompt.applySnapshot(state))
        const isDamage = data.kind === "chooseCombatDamageAssignment"
        const hasDamage = isDamage || data.kind === "chooseDamageAssignmentOrder"
        prompt(data.kind, {cards:[{id:"scry:0", name:"First card"}, {id:"scry:1", name:"Second card"}],
            minCardSelections:1, maxCardSelections:1,
            scryDestinations:data.kind === "scry" ? ["libraryTop", "libraryBottom"] : [],
            orderItems:[{responseId:"order:0", name:"First trigger"}, {responseId:"order:1", name:"Second trigger"}],
            damageSource:hasDamage ? {objectId:"own-0", name:"Trampler", label:"Trampler"} : undefined,
            totalDamage:hasDamage ? 4 : 0, damageAssignmentMode:"unordered",
            damageTargets:hasDamage ? [{responseId:"damage-target:0", kind:"card", label:"First blocker", lethalDamage:2},
                {responseId:"damage-target:1", kind:"card", label:"Second blocker", lethalDamage:2}] : []})
        const popup = item(isDamage ? "rulesDamageDialog" : "rulesCardChoiceDialog")
        tryCompare(popup, "opened", true)
        const loader = findChild(popup.contentItem, isDamage ? "rulesDamageContent" : "rulesChoiceContent")
        const content = loader.item
        verify(content !== null)
        const filter = findChild(popup.contentItem, "rulesCardFilter")
        if (filter) {
            filter.text = "Second"
            const list = findChild(popup.contentItem, data.kind === "revealCards" ? "revealCardList" : "rulesCardCandidates")
            tryCompare(list, "count", 1)
            if (data.kind !== "revealCards") {
                waitForRendering(list)
                mouseClick(list.itemAtIndex(0))
                compare(content.selectedCount, 1)
            }
        } else if (data.kind === "scry") {
            verify(content.moveCard("scry:1", 0, 1))
        } else if (isDamage) {
            mouseClick(findChild(popup.contentItem, "rulesAutoAssignDamage"))
            verify(content.validAssignment)
        } else {
            content.moveItem(0, 1)
            compare(findChild(content, "rulesOrderCandidates").model.get(0).responseId,
                data.kind === "reorder" ? "order:1" : "damage-target:1")
        }
        const draft = JSON.stringify(isDamage ? content.assignments : data.kind === "scry"
            ? content.piles : content.selectedIds || {})
        const promptId = table.rulesSession.promptId
        mouseClick(findChild(popup.contentItem, isDamage ? "rulesDamageViewBattlefield" : "rulesChoiceViewBattlefield"))
        tryCompare(popup, "visible", false)
        verify(popup.requested && popup.inspectingBattlefield)
        verify(item("rulesResumeDecision").visible)
        verify(!table.priorityInputBlocked)
        compare(transport.responses.length, 0)
        mouseMove(item("forgeCard-own-0"), 20, 20)
        verify(testRulesPrompt.applySnapshot(state))
        verify(popup.inspectingBattlefield, "Ordinary snapshots must not reopen or reset the draft")
        mouseClick(item("forgeZone-graveyard"))
        const zone = item("forgeZonePopup")
        tryCompare(zone, "opened", true)
        compare(zone.zone, "graveyard")
        compare(table.zoneCount(0, "graveyard"), 1)
        mouseClick(item("forgeCloseZonePopup"))
        tryCompare(zone, "opened", false)
        mouseClick(item("forgeOpponentZone-exile"))
        tryCompare(zone, "opened", true)
        compare(zone.ownerSeat, 1)
        compare(zone.zone, "exile")
        waitForRendering(zone.contentItem)
        const restore = findChild(zone.contentItem, "rulesResumeDecisionFromZone")
        verify(restore.mapToItem(zone.contentItem, 0, 0).y >= 0)
        const tabs = findChild(zone.contentItem, "forgeZoneTabs")
        verify(item("forgeZoneCards").y >= tabs.y + tabs.height)
        mouseClick(restore)
        tryCompare(zone, "opened", false)
        tryCompare(popup, "opened", true)
        verify(!item("rulesResumeDecision").visible)
        compare(loader.item, content, "Inspection must keep the same prompt instance alive")
        compare(table.rulesSession.promptId, promptId)
        compare(JSON.stringify(isDamage ? content.assignments : data.kind === "scry"
            ? content.piles : content.selectedIds || {}), draft)
        if (filter) compare(filter.text, "Second")
        if (["reorder", "chooseDamageAssignmentOrder"].includes(data.kind))
            compare(findChild(content, "rulesOrderCandidates").model.get(0).responseId,
                data.kind === "reorder" ? "order:1" : "damage-target:1")
        compare(transport.responses.length, 0, "Inspecting and resuming never responds to Forge")
        if (data.kind === "chooseCards" || data.kind === "mulliganPutBack") {
            mouseClick(findChild(popup.contentItem, "rulesConfirmCards"))
            compare(transport.responses[0].cards, ["scry:1"])
        } else if (data.kind === "revealCards") {
            mouseClick(findChild(popup.contentItem, "acknowledgeRevealButton"))
            compare(transport.responses[0].response, "$ack")
        }
    }
    function test_suspendedDecisionCannotSurviveNewContext_data() {
        return ["disconnect", "spectate", "seat-change", "new-game", "sideboard", "new-prompt", "republish"]
            .map(change => ({tag:change, change:change}))
    }
    function test_suspendedDecisionCannotSurviveNewContext(data) {
        prompt("chooseCards", {cards:[{id:"private", name:"Private card"}], minCardSelections:1, maxCardSelections:1})
        const popup = item("rulesCardChoiceDialog")
        tryCompare(popup, "opened", true)
        findChild(popup.contentItem, "rulesCardFilter").text = "Private"
        mouseClick(findChild(popup.contentItem, "rulesChoiceViewBattlefield"))
        tryCompare(popup, "visible", false)
        verify(popup.inspectingBattlefield)
        if (data.change === "disconnect") transport.inRoom = false
        else if (data.change === "spectate") room.role = "spectator"
        else if (data.change === "seat-change") room.seatIndex = 1
        else if (data.change === "sideboard") match.sideboarding = true
        else if (data.change === "new-game") {
            const next = snapshot(); next.gameId = "another-game"
            verify(testRulesPrompt.applySnapshot(next))
        } else {
            if (data.change === "republish") --serial
            prompt("chooseCards", {cards:[{id:"replacement", name:"Replacement card"}], minCardSelections:1, maxCardSelections:1})
            tryCompare(popup, "opened", true)
            compare(findChild(popup.contentItem, "rulesCardFilter").text, "")
        }
        verify(!popup.inspectingBattlefield)
        verify(!item("rulesResumeDecision").visible)
        if (!["new-prompt", "republish"].includes(data.change)) {
            tryVerify(() => findChild(popup.contentItem, "rulesCardFilter") === null)
            verify(!item("rulesDecisionDock").expanded)
        }
        compare(transport.responses.length, 0)
    }
    function test_resumeDecisionFromDockKeepsAcknowledgementExplicit() {
        prompt("revealCards", {cards:[]})
        const popup = item("rulesCardChoiceDialog")
        tryCompare(popup, "opened", true)
        mouseClick(findChild(popup.contentItem, "rulesChoiceViewBattlefield"))
        tryCompare(popup, "visible", false)
        mouseClick(item("rulesResumeDecision"))
        tryCompare(popup, "opened", true)
        compare(transport.responses.length, 0)
        mouseClick(findChild(popup.contentItem, "acknowledgeRevealButton"))
        compare(transport.responses[0].response, "$ack")
    }
    function test_privateChoiceClosesOnAuthorityChange_data() {
        return [{tag:"disconnect"}, {tag:"spectate"}, {tag:"seat-change"}, {tag:"new-game"}]
    }
    function test_privateChoiceClosesOnAuthorityChange(data) {
        prompt("chooseCards", {cards:[{id:"candidate", name:"Private library card"}], minCardSelections:1, maxCardSelections:1})
        const popup = item("rulesCardChoiceDialog")
        tryCompare(popup, "visible", true)
        findChild(popup.contentItem, "rulesCardFilter").text = "Private"
        keyClick(Qt.Key_Escape)
        verify(popup.visible, "A mandatory choice must not be dismissed as an implicit response")
        if (data.tag === "disconnect") transport.inRoom = false
        else if (data.tag === "spectate") room.role = "spectator"
        else if (data.tag === "seat-change") room.seatIndex = 1
        else { const next = snapshot(); next.gameId = "another-game"; verify(testRulesPrompt.applySnapshot(next)) }
        tryCompare(popup, "visible", false)
        tryVerify(() => findChild(popup.contentItem, "rulesCardFilter") === null)
        verify(!item("rulesDecisionDock").expanded,
               "Revoked private cards must not reappear through the fallback dock")
        compare(transport.responses.length, 0)
    }
    function test_exileActionStaysVisibleAndUsesCurrentResponse() {
        const state = snapshot()
        state.zones.push({zone:"exile", ownerSeat:1, count:2, cards:[card("exile-one", 1, "Grizzly Bears", true),
            card("exile-two", 1, "Grizzly Bears", true)]})
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"exile-cast", cardId:"exile-two", kind:"cast", label:"Cast Grizzly Bears"},
            {responseId:"$pass", kind:"pass", label:"Pass"}]})
        const list = item("rulesZoneActions")
        tryCompare(list, "count", 1)
        const button = item("rulesZoneAction-exile-cast")
        tryVerify(() => list.height >= button.height)
        waitForRendering(button)
        verify(button.visible && button.enabled)
        verify(button.text.includes("Exile"))
        verify(button.mapToItem(table, 0, 0).y >= 0
            && button.mapToItem(table, button.width, button.height).y <= table.height)
        verify(!item("rulesPriorityFallbackActions").visible, "The old fallback must not duplicate the action")
        mouseClick(button)
        compare(transport.responses.length, 1)
        compare(transport.responses[0].response, "exile-cast")
        verify(!button.enabled)
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        tryCompare(list, "count", 0)
        verify(!table.interaction.submitCardAction("exile-two", "exile-cast"))
        compare(transport.responses.length, 1)
    }
    function test_handDragUsesCurrentForgeAction() {
        action("playLand", "hand-0")
        const hand = item("forgeHandCard-hand-0"), target = item("forgeHandDropArea")
        const start = hand.mapToItem(table, hand.width / 2, hand.height / 2)
        const end = target.mapToItem(table, target.width / 2, target.height / 2)
        mouseDrag(table, start.x, start.y, end.x - start.x, end.y - start.y, Qt.LeftButton)
        tryCompare(transport, "rulesResponsePending", true)
        compare(transport.responses.length, 1)
        compare(transport.responses[0].response, "opaque-play")
    }
    function test_boardAndDockShareOpaqueCombatChoices() {
        combat("chooseAttackers")
        const source = item("forgeCard-own-0")
        tryCompare(source, "actionable", true)
        mouseClick(source)
        compare(table.combatInteraction.selectedSource, "")
        compare(table.combatInteraction.assignments["opaque-source"], "opaque-target")
        verify(item("rulesConfirmCombat-attackers").enabled)
        verify(!item("rulesCombatCandidates-attackers").visible)
        waitForRendering(table)
        mouseClick(item("rulesCombatDetails-attackers"))
        tryVerify(() => findChild(table, "rulesCombatAssignment-opaque-source") !== null)
        const combo = item("rulesCombatAssignment-opaque-source")
        compare(combo.currentIndex, 1)
        compare(table.combatInteraction.links.length, 1)
        mouseClick(item("rulesConfirmCombat-attackers"))
        compare(transport.responses[0].assignments, [{sourceId:"opaque-source", targetId:"opaque-target"}])
        combat("chooseBlockers")
        compare(table.combatInteraction.links.length, 0)
        mouseClick(source)
        tryCompare(item("forgeCard-opponent"), "actionable", true)
        mouseClick(item("forgeCard-opponent"))
        compare(table.combatInteraction.links[0].to, "opponent")
        waitForRendering(table)
        mouseClick(item("rulesCombatDetails-blockers"))
        tryVerify(() => findChild(table, "rulesCombatAssignment-opaque-source") !== null)
        item("rulesCombatAssignment-opaque-source").forceActiveFocus(); keyClick(Qt.Key_Up)
        compare(table.combatInteraction.links.length, 0)
    }
    function test_creatureClickUsesCurrentAbilityWindow_data() {
        return [{tag:"before-attack", step:"begin_combat", attacking:false, kind:"chooseAction"},
                {tag:"after-attack", step:"declare_attackers", attacking:true, kind:"chooseAction"},
                {tag:"after-block", step:"declare_blockers", attacking:true, kind:"chooseAction"},
                {tag:"mana-payment", step:"declare_attackers", attacking:true, kind:"payManaCost"}]
    }
    function test_creatureClickUsesCurrentAbilityWindow(data) {
        testTranslations.setLanguage("zh")
        const state = snapshot()
        state.step = data.step
        state.zones[4].cards[0].attacking = data.attacking
        verify(testRulesPrompt.applySnapshot(state))
        prompt(data.kind, {options:[{responseId:"ability", cardId:"own-0", kind:"activateAbility", label:"Activate"}]})
        const source = item("forgeCard-own-0")
        mouseMove(source, source.width / 2, source.height / 2)
        if (data.kind !== "payManaCost")
            tryCompare(source, "showAbilityHint", true)
        tryCompare(findChild(source, "forgeCardInteractionHint-own-0"), "text",
                   data.kind === "payManaCost" ? "横置支付费用" : "起动异能")
        verify(!table.combatInteraction.active)
        mouseClick(source)
        compare(transport.responses[0].response, "ability")
        compare(table.combatInteraction.selectedSource, "")
        compare(table.combatInteraction.links.length, 0)
        compare(source.card.attacking, data.attacking)
        verify(!source.abilityActionable)
        mouseClick(source)
        compare(transport.responses.length, 1)

        combat("chooseAttackers", 1, true)
        mouseClick(source)
        tryCompare(findChild(source, "forgeCardInteractionHint-own-0"), "text", "选择攻击目标")
        compare(table.combatInteraction.selectedSource, "opaque-source")
        verify(!source.abilityActionable)
        compare(transport.responses.length, 1)
        mouseClick(item("rulesPlayerTarget1"))
        compare(table.combatInteraction.links.length, 1)

        combat("chooseBlockers", 1, true)
        mouseClick(source)
        tryCompare(findChild(source, "forgeCardInteractionHint-own-0"), "text", "选择要阻挡的生物")
        verify(!source.abilityActionable)
        compare(transport.responses.length, 1)

        prompt("chooseAction", {options:[{responseId:"next-ability", cardId:"own-0", kind:"activateAbility", label:"Activate"}]})
        source.forceActiveFocus()
        tryCompare(source, "showAbilityHint", true)
        compare(table.combatInteraction.selectedSource, "")
        compare(table.combatInteraction.links.length, 0)
        keyClick(Qt.Key_Return)
        compare(transport.responses[1].response, "next-ability")
    }
    function test_creatureMultipleAbilitiesKeepExplicitChoices() {
        const state = snapshot()
        state.step = "declare_attackers"
        state.zones[4].cards[0].attacking = true
        state.zones[4].cards[0].identity.name = "Psychic Frog"
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[
            {responseId:"discard", cardId:"own-0", kind:"activateAbility", label:"Discard a card: put a +1/+1 counter on Psychic Frog."},
            {responseId:"flying", cardId:"own-0", kind:"activateAbility", label:"Exile three cards from your graveyard: Psychic Frog gains flying."}]})
        const source = item("forgeCard-own-0")
        mouseClick(source)
        tryCompare(table.cardActionPicker, "opened", true)
        compare(transport.responses.length, 0)
        compare(table.combatInteraction.selectedSource, "")
        mouseClick(item("rulesCardAction-flying"))
        compare(transport.responses[0].response, "flying")

        // Native Forge may first select the card, then publish its ability menu.
        prompt("chooseAction", {options:[{responseId:"frog", cardId:"own-0", kind:"activateAbility", label:"Activate Psychic Frog"}]})
        mouseClick(source)
        compare(transport.responses[1].response, "frog")
        prompt("chooseFromSelection", {title:"Choose an ability", minChoiceTotal:1, maxChoiceTotal:1,
            choices:[{responseId:"choice:discard", label:"Discard a card", weight:1, canRepeat:false},
                     {responseId:"choice:flying", label:"Gain flying", weight:1, canRepeat:false}]})
        verify(!source.abilityActionable)
        verify(!source.actionable)
        mouseClick(source)
        compare(transport.responses.length, 2)
        mouseClick(item("rulesScalarChoice-choice:flying"))
        compare(transport.responses[2].choices, ["choice:flying"])
        compare(table.combatInteraction.links.length, 0)
    }
    function test_optionalCastingAbilitySubmitsOnFirstClick_data() {
        return [{tag:"normal-cast", selected:"choice:normal"},
                {tag:"impending", selected:"choice:impending"}]
    }
    function test_optionalCastingAbilitySubmitsOnFirstClick(data) {
        const state = snapshot()
        state.zones[0].cards[0].identity.name = "Overlord of the Balemurk"
        verify(testRulesPrompt.applySnapshot(state))
        const impending = "Impending 5— {1}{B} (If you cast this spell for its impending cost, it enters with five time counters and isn't a creature until the last is removed. At the beginning of your end step, remove a time counter from it.)"
        prompt("chooseFromSelection", {title:"Choose an ability", minChoiceTotal:0, maxChoiceTotal:1,
            choices:[{responseId:"choice:normal", label:"Overlord of the Balemurk - Creature 5 / 5", weight:1, canRepeat:false},
                     {responseId:"choice:impending", label:impending, weight:1, canRepeat:false}]})
        const promptId = table.rulesSession.promptId
        const choice = item("rulesScalarChoice-" + data.selected)
        verify(choice.visible)
        verify(choice.enabled)
        verify(!item("rulesConfirmChoices").visible)
        verify(!item("rulesScalarQuantity-" + data.selected).visible)
        compare(item("rulesSkipChoice").text, "Cancel")
        verify(item("rulesSkipChoice").visible)
        compare(item("rulesScalarChoice-choice:impending").text, impending)
        choice.forceActiveFocus()
        waitForRendering(choice)
        mouseClick(choice)
        compare(transport.responses.length, 1)
        compare(transport.responses[0].id, promptId)
        compare(transport.responses[0].choices, [data.selected])
        verify(transport.rulesResponsePending)
        verify(!item("rulesScalarQuantity-" + data.selected).visible)
        mouseClick(choice)
        mouseClick(item("rulesSkipChoice"))
        compare(transport.responses.length, 1)
    }
    function test_optionalChoiceCancellationClearsPreviousSelection_data() {
        return [{tag:"ability", title:"Choose an ability", skip:"Cancel"},
                {tag:"other-selection", title:"Choose an effect", skip:"Choose none"}]
    }
    function test_optionalChoiceCancellationClearsPreviousSelection(data) {
        prompt("chooseFromSelection", {title:"Choose effects", minChoiceTotal:1, maxChoiceTotal:2,
            choices:[{responseId:"choice:old", label:"Previous effect", weight:1, canRepeat:false},
                     {responseId:"choice:other", label:"Other effect", weight:1, canRepeat:false}]})
        mouseClick(item("rulesScalarChoice-choice:old"))
        compare(transport.responses.length, 0)
        verify(item("rulesConfirmChoices").visible)
        verify(item("rulesConfirmChoices").enabled)

        prompt("chooseFromSelection", {title:data.title, minChoiceTotal:0, maxChoiceTotal:1,
            choices:[{responseId:"choice:new", label:"Current effect", weight:1, canRepeat:false}]})
        const optionalId = table.rulesSession.promptId
        verify(!item("rulesConfirmChoices").visible)
        const skip = item("rulesSkipChoice")
        verify(skip.visible)
        compare(skip.text, data.skip)
        mouseClick(skip)
        compare(transport.responses.length, 1)
        compare(transport.responses[0].id, optionalId)
        compare(transport.responses[0].choices, [])
        mouseClick(skip)
        mouseClick(item("rulesScalarChoice-choice:new"))
        compare(transport.responses.length, 1)

        prompt("chooseFromSelection", {title:"Choose an ability", minChoiceTotal:1, maxChoiceTotal:1,
            choices:[{responseId:"choice:required", label:"Required effect", weight:1, canRepeat:false}]})
        verify(!skip.visible)
        verify(!item("rulesConfirmChoices").visible)
        mouseClick(item("rulesScalarChoice-choice:required"))
        compare(transport.responses.length, 2)
        compare(transport.responses[1].id, table.rulesSession.promptId)
        compare(transport.responses[1].choices, ["choice:required"])
    }
    function test_combatStateCannotCrossAuthorityOrPromptBoundaries_data() {
        return [{tag:"disconnect"}, {tag:"spectate"}, {tag:"seat-change"}, {tag:"new-prompt"}, {tag:"new-game"}]
    }
    function test_combatAimFollowsPointerAndLocksOnClick_data() {
        return [{tag:"attackers", kind:"chooseAttackers", target:"rulesPlayerTarget1", suffix:"seat-1",
                    invalid:"forgeCard-opponent"},
                {tag:"blockers", kind:"chooseBlockers", target:"forgeCard-opponent", suffix:"opponent",
                    invalid:"rulesPlayerTarget1"}]
    }
    function test_combatSoundsFollowSelectionAndAssignmentOnly_data() {
        return [{tag:"attack", kind:"chooseAttackers", target:"rulesPlayerTarget1"},
                {tag:"block", kind:"chooseBlockers", target:"forgeCard-opponent"}]
    }
    function test_combatSoundsFollowSelectionAndAssignmentOnly(data) {
        const previousBackend = SoundEffects.backend
        SoundEffects.backend = soundRecorder
        soundRecorder.cues = []
        try {
            combat(data.kind, 1, true)
            const source = item("forgeCard-own-0"), target = item(data.target)
            mouseMove(source)
            compare(soundRecorder.cues, [])
            mouseClick(source)
            compare(soundRecorder.cues, ["select"])
            mouseMove(table.presentation, table.presentation.width / 2, table.presentation.height / 2)
            mouseMove(target)
            compare(soundRecorder.cues, ["select"])
            mouseClick(target)
            compare(soundRecorder.cues, ["select", data.tag])
            mouseClick(source)
            mouseClick(target)
            compare(soundRecorder.cues, ["select", data.tag, "select", "cancel"])
            mouseClick(source)
            source.forceActiveFocus()
            keyClick(Qt.Key_Escape)
            compare(soundRecorder.cues, ["select", data.tag, "select", "cancel", "select", "cancel"])
            mouseClick(source)
            const beforeReset = soundRecorder.cues.slice()
            combat(data.kind, 1, true)
            transport.inRoom = false
            compare(soundRecorder.cues, beforeReset)
        } finally {
            SoundEffects.backend = previousBackend
        }
    }
    function test_combatAimFollowsPointerAndLocksOnClick(data) {
        combat(data.kind, 1, true)
        const source = item("forgeCard-own-0"), aim = item("forgeCombatAimArrow")
        verify(!aim.visible)
        mouseClick(source)
        compare(table.combatInteraction.selectedSource, "opaque-source")
        tryCompare(aim, "visible", true)
        verify(Math.hypot(aim.endPoint.x - aim.startPoint.x, aim.endPoint.y - aim.startPoint.y) > 8)
        compare(aim.startPoint, table.presentation.pointFor("own-0"))
        for (const delta of [0, 60, 120]) {
            const x = Math.round(table.presentation.width - 50 - delta)
            const y = Math.round(table.presentation.height / 2 - delta / 2)
            mouseMove(table.presentation, x, y)
            tryCompare(aim, "snapped", false)
            tryVerify(() => Math.abs(aim.endPoint.x - x) < 1 && Math.abs(aim.endPoint.y - y) < 1)
            compare(table.combatInteraction.links.length, 0)
            compare(transport.responses.length, 0)
        }
        mouseMove(item(data.invalid))
        tryCompare(aim, "snapped", false)
        compare(table.combatInteraction.hoveredTarget, null)
        const target = item(data.target)
        mouseMove(target, target.width / 2, target.height / 2)
        tryCompare(aim, "snapped", true)
        const endpoint = data.tag === "attackers" ? table.presentation.playerPoint(1)
            : table.presentation.pointFor("opponent")
        compare(aim.endPoint, endpoint)
        compare(table.combatInteraction.links.length, 0)
        compare(transport.responses.length, 0)
        mouseClick(target)
        tryCompare(aim, "visible", false)
        compare(table.combatInteraction.selectedSource, "")
        compare(table.combatInteraction.assignments["opaque-source"], "opaque-target")
        const fixed = item("forgeCombatArrow-own-0-" + data.suffix)
        compare(fixed.endPoint, endpoint)
        verify(fixed.visible)
        mouseMove(table.presentation, table.presentation.width - 40, table.presentation.height / 2)
        compare(fixed.endPoint, endpoint)
        verify(!aim.visible)
        compare(table.combatInteraction.links.length, 1)
        compare(transport.responses.length, 0)
    }
    function test_combatAimHidesPendingAndOffscreen() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, 70, true)))
        combat("chooseAttackers", 1, true)
        const source = item("forgeCard-own-0"), aim = item("forgeCombatAimArrow")
        const lane = item("forgeOwnCreatures")
        lane.scrollArea.contentY = 0
        mouseClick(source)
        tryCompare(aim, "visible", true)
        transport.rulesResponsePending = true
        tryCompare(aim, "visible", false)
        compare(table.combatInteraction.links.length, 0)
        transport.rulesResponsePending = false
        mouseMove(source, source.width / 2, source.height / 2)
        tryCompare(aim, "visible", true)
        lane.scrollArea.contentY = lane.scrollArea.contentHeight - lane.scrollArea.height
        tryCompare(aim, "startPoint", Qt.point(0, 0))
        tryCompare(aim, "visible", false)
        compare(table.combatInteraction.selectedSource, "opaque-source")
        compare(table.combatInteraction.links.length, 0)
        lane.scrollArea.contentY = 0
        mouseMove(source, source.width / 2, source.height / 2)
        tryCompare(aim, "visible", true)
        compare(aim.startPoint, table.presentation.pointFor("own-0"))
        compare(transport.responses.length, 0)
    }
    function test_focusingHoveredCombatSourceKeepsPreviewSuppressed() {
        combat("chooseAttackers", 1, true)
        const source = item("forgeCard-own-0")
        mouseClick(source)
        compare(table.combatInteraction.selectedSource, "opaque-source")
        source.forceActiveFocus()
        verify(source.activeFocus)
        verify(!source.previewActive)
        compare(table.inspector.previewCardId, "")
        verify(!item("rulesCardHoverPreview").visible)
        compare(transport.responses.length, 0)
    }
    function test_combatAimDoesNotSnapToScrolledTarget() {
        const state = snapshot()
        state.zones[5].cards = Array.from({length:70}, (_, i) => card("opponent-" + i, 1, "Attacker " + i, true))
        state.zones[5].count = state.zones[5].cards.length
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseBlockers", {
            combatSources:[{responseId:"source", objectId:"own-0", label:"Bear", name:"Grizzly Bears",
                validTargetIds:["target", "alternate"], maxAssignments:1}],
            combatTargets:[{responseId:"target", kind:"attacker", objectId:"opponent-0", label:"Attacker",
                minAssignments:0, maxAssignments:8},
                {responseId:"alternate", kind:"attacker", objectId:"opponent-69", label:"Other attacker",
                    minAssignments:0, maxAssignments:8}]
        })
        const lane = item("forgeOpponentCreatures"), target = item("forgeCard-opponent-0")
        const aim = item("forgeCombatAimArrow")
        lane.scrollArea.contentY = 0
        mouseClick(item("forgeCard-own-0"))
        mouseMove(target, target.width / 2, target.height / 2)
        tryCompare(aim, "snapped", true)
        compare(aim.endPoint, table.presentation.pointFor("opponent-0"))
        lane.scrollArea.contentY = lane.scrollArea.contentHeight - lane.scrollArea.height
        tryCompare(aim, "snapped", false)
        verify(aim.visible)
        verify(aim.endPoint.x > 0 && aim.endPoint.y > 0)
        compare(table.combatInteraction.selectedSource, "source")
        compare(table.combatInteraction.links.length, 0)
        compare(transport.responses.length, 0)
    }
    function test_multipleDefendersUseBoardAndPlayerSeat_data() {
        return [{tag:"planeswalker", kind:"planeswalker", name:"Test Walker", seat:1},
                {tag:"battle", kind:"battle", name:"Test Battle", seat:0}]
    }
    function test_multipleDefendersUseBoardAndPlayerSeat(data) {
        const state = snapshot()
        state.zones[4 + data.seat].cards.push(card("defender", data.seat, data.name, false))
        state.zones[4 + data.seat].count++
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAttackers", {combatSources:[{responseId:"source", objectId:"own-0", label:"Bear", name:"Grizzly Bears",
            validTargetIds:["player-choice", "permanent-choice"], maxAssignments:1}], combatTargets:[
                {responseId:"player-choice", kind:"player", seat:1, label:"Opponent", minAssignments:0, maxAssignments:1},
                {responseId:"permanent-choice", kind:data.kind, objectId:"defender", label:data.name, minAssignments:0, maxAssignments:1}]})
        verify(!item("forgeCard-defender").actionable)
        mouseClick(item("forgeCard-own-0"))
        verify(!item("rulesPlayerTarget0").actionable)
        verify(item("rulesPlayerTarget1").actionable)
        verify(item("forgeCard-defender").combatDestination)
        verify(!item("forgeCard-opponent").actionable)
        const aim = item("forgeCombatAimArrow")
        mouseClick(item("forgeCard-opponent"))
        compare(table.combatInteraction.selectedSource, "source")
        compare(table.combatInteraction.links.length, 0)
        // Longer decisions are hideable overlays over the stable resting
        // reservation. Exact-object navigation exposes a covered battle.
        verify(table.presentation.reveal("defender"))
        mouseMove(item("forgeCard-defender"))
        tryCompare(aim, "snapped", true)
        compare(aim.endPoint, table.presentation.pointFor("defender"))
        compare(table.combatInteraction.links.length, 0)
        mouseClick(item("forgeCard-defender"))
        tryCompare(aim, "visible", false)
        compare(table.combatInteraction.assignments.source, "permanent-choice")
        compare(table.combatInteraction.links[0].to, "defender")
        const fixed = item("forgeCombatArrow-own-0-defender")
        compare(fixed.endPoint, table.presentation.pointFor("defender"))
        mouseClick(item("forgeCard-own-0"))
        mouseClick(item("rulesPlayerTarget1"))
        compare(table.combatInteraction.assignments.source, "player-choice")
        compare(table.combatInteraction.links[0].seat, 1)
        if (item("rulesDecisionDock").collapsed)
            mouseClick(item("forgeDecisionCollapse"))
        tryVerify(() => item("rulesConfirmCombat-attackers").visible)
        mouseClick(item("rulesConfirmCombat-attackers"))
        compare(transport.responses[0].assignments, [{sourceId:"source", targetId:"player-choice"}])
    }
    function test_combatSelectionCanBeCancelledRemovedAndCleared_data() {
        return [{tag:"attackers", kind:"chooseAttackers", target:"rulesPlayerTarget1"},
                {tag:"blockers", kind:"chooseBlockers", target:"forgeCard-opponent"}]
    }
    function test_combatSelectionCanBeCancelledRemovedAndCleared(data) {
        combat(data.kind, 1, true)
        const source = item("forgeCard-own-0"), target = item(data.target), aim = item("forgeCombatAimArrow")
        mouseClick(source)
        tryCompare(aim, "visible", true)
        source.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        verify(!aim.visible)
        compare(table.combatInteraction.selectedSource, "")
        verify(item("rulesConfirmCombat-" + data.tag).enabled)
        mouseClick(source); mouseClick(source)
        verify(!aim.visible)
        compare(table.combatInteraction.selectedSource, "")
        mouseClick(source); mouseClick(target)
        compare(table.combatInteraction.links.length, 1)
        const fixed = item("forgeCombatArrow-own-0-" + (data.tag === "attackers" ? "seat-1" : "opponent"))
        const endpoint = fixed.endPoint
        mouseClick(source)
        tryCompare(aim, "visible", true)
        source.forceActiveFocus(); keyClick(Qt.Key_Escape)
        verify(!aim.visible)
        compare(fixed.endPoint, endpoint)
        compare(table.combatInteraction.links.length, 1)
        mouseClick(source)
        waitForRendering(table)
        mouseClick(item("rulesCombatCancelSelection-" + data.tag))
        verify(!aim.visible)
        compare(table.combatInteraction.selectedSource, "")
        compare(table.combatInteraction.links.length, 1)
        mouseClick(source)
        mouseClick(item("rulesCombatRemoveAssignment-" + data.tag))
        compare(table.combatInteraction.links.length, 0)
        mouseClick(source); mouseClick(target)
        mouseClick(source); mouseClick(target)
        compare(table.combatInteraction.links.length, 0)
        source.forceActiveFocus(); keyClick(Qt.Key_Space)
        target.forceActiveFocus(); keyClick(Qt.Key_Return)
        compare(table.combatInteraction.links.length, 1)
        waitForRendering(table)
        mouseClick(item("rulesCombatClear-" + data.tag))
        compare(table.combatInteraction.links.length, 0)
        mouseClick(item("rulesConfirmCombat-" + data.tag))
        compare(transport.responses[0].assignments, [])
    }
    function test_combatLegacyPlayerMappingRetainsExplicitListFallback() {
        prompt("chooseAttackers", {combatSources:[{responseId:"source", objectId:"own-0", label:"Bear", name:"Grizzly Bears",
            validTargetIds:["defender"], maxAssignments:1}], combatTargets:[
                {responseId:"defender", kind:"player", label:"Bob", minAssignments:0, maxAssignments:1}]})
        mouseClick(item("forgeCard-own-0"))
        compare(table.combatInteraction.assignments.source, "defender")
        verify(!item("rulesPlayerTarget0").actionable)
        verify(!item("rulesPlayerTarget1").actionable)
        waitForRendering(table)
        mouseClick(item("rulesCombatDetails-attackers"))
        tryVerify(() => findChild(table, "rulesCombatAssignment-source") !== null)
        compare(table.combatInteraction.selectedSource, "")
        mouseClick(item("rulesConfirmCombat-attackers"))
        compare(transport.responses[0].assignments, [{sourceId:"source", targetId:"defender"}])
    }
    function test_blockerLegalityAndMinimumsRemainAuthoritative() {
        const state = snapshot(1, 4)
        state.zones[5].cards.push(card("opponent-2", 1, "Other Attacker", true))
        state.zones[5].count++
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseBlockers", {
            combatSources:[0, 1, 2, 3].map(i => ({responseId:"source-" + i, objectId:"own-" + i,
                label:"Bear", name:"Grizzly Bears", maxAssignments:i === 3 ? 0 : 1,
                validTargetIds:i === 2 ? ["menace", "other"] : ["menace"]})),
            combatTargets:[{responseId:"menace", kind:"attacker", objectId:"opponent", label:"Menace",
                minAssignments:2, maxAssignments:2, mustReceiveIfAble:true},
                {responseId:"other", kind:"attacker", objectId:"opponent-2", label:"Other", minAssignments:0, maxAssignments:1}]
        })
        tryCompare(item("forgeOwnCreatures"), "stackCount", 1)
        verify(!table.combatInteraction.actionable("own-3"))
        showPile("own-3")
        mouseClick(item("forgeCard-own-0"))
        compare(table.combatInteraction.assignments["source-0"], "menace")
        compare(table.combatInteraction.selectedSource, "")
        verify(item("forgeCard-opponent-2").actionable, "Attacker-first selection remains available")
        verify(!item("rulesConfirmCombat-blockers").enabled, "One blocker does not meet menace")
        mouseClick(item("forgeCard-own-1"))
        verify(item("rulesConfirmCombat-blockers").enabled)
        mouseClick(item("forgeCard-own-2"))
        verify(!item("forgeCard-opponent").actionable)
        mouseClick(item("forgeCard-opponent"))
        compare(table.combatInteraction.selectedSource, "source-2")
        verify(item("forgeCard-opponent-2").actionable)
        mouseClick(item("forgeCard-opponent-2"))
        mouseClick(item("rulesConfirmCombat-blockers"))
        compare(transport.responses[0].assignments, [
            {sourceId:"source-0", targetId:"menace"}, {sourceId:"source-1", targetId:"menace"},
            {sourceId:"source-2", targetId:"other"}])
        verify(!item("forgeCard-own-0").actionable)
        mouseClick(item("forgeCard-own-0"))
        compare(table.combatInteraction.selectedSource, "")
        compare(transport.responses.length, 1)
    }
    function test_commanderHistoryAndActionFollowNativeSnapshot_data() {
        return [{tag:"duel", seats:2}, {tag:"edh-three", seats:3}, {tag:"edh-four", seats:4}]
    }
    function test_commanderHistoryAndActionFollowNativeSnapshot(data) {
        room.format = data.seats > 2 ? "edh" : "duel"; room.maxSeats = data.seats
        const state = data.seats > 2 ? edhSnapshot([0,1,2,3].slice(0, data.seats), 0) : snapshot()
        const commanderId = data.seats > 2 ? "creature-0-0" : "own-0"
        state.players[0].commanders = [{name:"Commander", casts:2, tax:4, zone:"battlefield", objectId:commanderId},
            {name:"Partner", casts:0, tax:0, zone:"hidden"}]
        verify(testRulesPrompt.applySnapshot(state))
        compare(findChild(table, "forgeCommanders-0"), null)
        const pile = item(data.seats > 2 ? "forgeSeatZone-0-command" : "forgeZone-command")
        pile.forceActiveFocus()
        keyClick(Qt.Key_Return)
        tryCompare(item("forgeZonePopup"), "opened", true)
        const commander = item("forgeCommanderHistory-0-0"), partner = item("forgeCommanderHistory-0-1")
        verify(commander.summary.includes("Tax +4"))
        verify(partner.summary.includes("Hidden zone"))
        compare(table.presentation.commandersFor(0)[1].objectId || "", "")
        const lane = item("forgeZoneCards")
        verify(lane.y >= partner.mapToItem(lane.parent, 0, partner.height).y)
        state.players[0].commanders[0].casts = 3
        state.players[0].commanders[0].tax = 6
        verify(testRulesPrompt.applySnapshot(state))
        tryVerify(() => item("forgeCommanderHistory-0-0").summary.includes("Tax +6"))
        item("forgeZonePopup").close()
        action("activateAbility", commanderId)
        mouseClick(item("forgeCard-" + commanderId))
        compare(transport.responses[0].response, "opaque-play")
        const next = snapshot(); next.gameId = "next-game"
        verify(testRulesPrompt.applySnapshot(next))
        tryCompare(table.presentation, "playerSeats", [0,1])
        mouseClick(item("forgeZone-command"))
        tryCompare(item("forgeZonePopup"), "visible", true)
        compare(findChild(item("forgeZonePopup").contentItem, "forgeCommanderHistory-0-0"), null)
    }
    function test_boardMultipleBlocksRespectNativeCapacity() {
        const state = snapshot()
        state.zones[5].cards.push(card("opponent-2", 1, "Grizzly Bears", true), card("opponent-3", 1, "Grizzly Bears", true))
        state.zones[5].count = 3
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseBlockers", {combatSources:[{responseId:"source", objectId:"own-0", label:"Guard", name:"Guard",
            validTargetIds:["a", "b", "c"], maxAssignments:2}], combatTargets:[
                {responseId:"a", kind:"attacker", objectId:"opponent", label:"A", minAssignments:0, maxAssignments:1},
                {responseId:"b", kind:"attacker", objectId:"opponent-2", label:"B", minAssignments:0, maxAssignments:1},
                {responseId:"c", kind:"attacker", objectId:"opponent-3", label:"C", minAssignments:0, maxAssignments:1}]})
        showPile("opponent-3")
        for (const id of ["opponent", "opponent-2", "opponent-3"]) {
            mouseClick(item("forgeCard-own-0")); mouseClick(item("forgeCard-" + id))
        }
        compare(table.combatInteraction.selectedTargets("source"), ["a", "b"])
        verify(!item("forgeCard-opponent-3").actionable)
        verify(item("forgeCard-opponent").actionable)
        mouseClick(item("forgeCard-opponent"))
        compare(table.combatInteraction.selectedTargets("source"), ["b"])
        mouseClick(item("forgeCard-own-0")); mouseClick(item("forgeCard-opponent"))
        mouseClick(item("rulesConfirmCombat-blockers"))
        compare(transport.responses[0].assignments, [{sourceId:"source", targetId:"b"}, {sourceId:"source", targetId:"a"}])
    }
    function test_attackerFirstMultipleBlocksPreserveOtherAssignments() {
        const state = snapshot(1, 1)
        state.zones[5].cards.push(card("opponent-2", 1, "Goblin", true))
        state.zones[5].count = 2
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseBlockers", {combatSources:[{responseId:"source", objectId:"own-0",
            label:"Palace Guard", name:"Palace Guard", validTargetIds:["a", "b"], maxAssignments:2}],
            combatTargets:[
                {responseId:"a", kind:"attacker", objectId:"opponent", label:"Bear", maxAssignments:1},
                {responseId:"b", kind:"attacker", objectId:"opponent-2", label:"Goblin", maxAssignments:1}]})
        for (const id of ["opponent", "opponent-2"]) {
            mouseClick(item("forgeCard-" + id))
            compare(table.combatInteraction.pendingAttacker, id)
            mouseClick(item("forgeCard-own-0"))
        }
        compare(table.combatInteraction.selectedTargets("source"), ["a", "b"])
        mouseClick(item("forgeCard-opponent"))
        mouseClick(item("forgeCard-own-0"))
        compare(table.combatInteraction.selectedTargets("source"), ["b"],
                "Removing one pair must preserve the blocker's other assignments")
        mouseClick(item("rulesConfirmCombat-blockers"))
        compare(transport.responses[0].assignments, [{sourceId:"source", targetId:"b"}])
    }
    function test_damageDialogShowsTargetsAndFitsWindow_data() {
        return [{tag:"ordered", mode:"ordered", width:1600, height:1000},
            {tag:"unordered", mode:"unordered", width:1280, height:800},
            {tag:"scaled", mode:"ordered", width:1280, height:800, scale:1.35},
            {tag:"divide-freely-compact", mode:"divideFreely", width:900, height:620}]
    }
    function test_damageDialogShowsTargetsAndFitsWindow(data) {
        window.width = data.width; window.height = data.height
        Theme.uiScale = data.scale || 1
        prompt("chooseCombatDamageAssignment", {damageSource:{objectId:"own-0", name:"Trampler", label:"Trampler"},
            damageTargets:[{responseId:"damage-target:0", kind:"card", label:"Blocker A", name:"Bear", lethalDamage:2},
                {responseId:"damage-target:1", kind:"card", label:"Blocker B", name:"Bear", lethalDamage:2},
                {responseId:"damage-target:2", kind:"player", label:"Opponent", lethalDamage:-1}], totalDamage:6,
            damageAssignmentMode:data.mode})
        const dialog = item("rulesDamageDialog")
        tryCompare(dialog, "opened", true)
        const auto = findChild(dialog, "rulesAutoAssignDamage"), confirm = findChild(dialog, "rulesConfirmDamage")
        verify(auto !== null && confirm !== null)
        compare(findChild(dialog, "rulesDamageSourceName").text, "Trampler")
        verify(!confirm.enabled)
        const candidates = findChild(dialog, "rulesDamageCandidates")
        if (data.width >= 1280) {
            tryCompare(candidates, "count", 3)
            verify(candidates.contentWidth <= candidates.width,
                   "Both blockers and the defending player must fit without scrolling")
        }
        mouseClick(auto)
        verify(confirm.enabled)
        const point = confirm.mapToItem(table, confirm.width / 2, confirm.height / 2)
        verify(point.x > 0 && point.x < table.width && point.y > 0 && point.y < table.height)
        mouseClick(confirm)
        compare(transport.responses[0].damage, [{targetId:"damage-target:0", damage:2}, {targetId:"damage-target:1", damage:2}, {targetId:"damage-target:2", damage:2}])
        verify(!confirm.enabled, "A pending response must disable repeated submission")
        transport.inRoom = false
        tryCompare(dialog, "visible", false)
        verify(!item("rulesDecisionDock").expanded, "Revoked damage must not reopen the fallback dock")
        transport.inRoom = true
        room.seatIndex = 1
        tryCompare(dialog, "visible", false)
    }
    function test_combatStateCannotCrossAuthorityOrPromptBoundaries(data) {
        combat("chooseAttackers")
        mouseClick(item("forgeCard-own-0"))
        compare(table.combatInteraction.links.length, 1)
        compare(table.combatInteraction.selectedSource, "")
        verify(!item("forgeCombatAimArrow").visible)
        if (data.tag === "disconnect") transport.inRoom = false
        else if (data.tag === "spectate") room.role = "spectator"
        else if (data.tag === "seat-change") room.seatIndex = 1
        else if (data.tag === "new-prompt") combat("chooseAttackers")
        else { const next = snapshot(); next.gameId = "next-game"; verify(testRulesPrompt.applySnapshot(next)) }
        compare(table.combatInteraction.links.length, 0)
        compare(table.combatInteraction.selectedSource, "")
        verify(!item("forgeCombatAimArrow").visible)
        compare(transport.responses.length, 0)
    }
    function test_privateHandsAndHiddenIdentityStayRedacted() {
        const state = snapshot()
        state.zones[4].cards.push({id:"hidden", ownerSeat:1, controllerSeat:1, visible:false, faceDown:true, power:"2", toughness:"2"})
        state.zones[4].count++
        verify(testRulesPrompt.applySnapshot(state))
        const hidden = item("forgeCard-hidden")
        compare(hidden.publicFace, false)
        compare(hidden.card.name, "")
        room.role = "spectator"
        tryVerify(() => item("forgeHand").visibleCards.length === 0)
        room.spectatorsSeeHands = true
        tryVerify(() => item("forgeHand").visibleCards.length === 1)
        verify(!item("forgeHandSurface-hand-0").actionable)
        room.spectatorsSeeHands = false
        tryVerify(() => item("forgeHand").visibleCards.length === 0)
    }
    function test_handWheelReachesLastCardAndReturnsToFirst() {
        verify(testRulesPrompt.applySnapshot(snapshot(35)))
        const hand = item("forgeHand")
        tryCompare(hand, "crowded", true)
        const viewport = hand.scrollArea
        tryVerify(() => hand.visibleCards.length === 35)
        for (let i = 0; i < 30 && !viewport.atXEnd; ++i)
            mouseWheel(viewport, viewport.width / 2, 70, 0, -240)
        tryCompare(viewport, "atXEnd", true)
        const last = item("forgeHandSurface-hand-34")
        const point = last.mapToItem(viewport, 0, 0)
        verify(point.x >= 0 && point.x + last.width <= viewport.width + 1)
        verify(item("forgeHandScrollBar").visible)
        for (let i = 0; i < 30 && !viewport.atXBeginning; ++i)
            mouseWheel(viewport, viewport.width / 2, 70, 0, 240)
        tryCompare(viewport, "atXBeginning", true)
    }
    function test_unspentManaUsesDedicatedColoredReadout() {
        const state = snapshot()
        state.players[0].manaPool = [{name:"U", value:2}, {name:"R", value:1}, {name:"C", value:3}]
        verify(testRulesPrompt.applySnapshot(state))
        const pool = item("forgeManaPool-0")
        tryCompare(pool, "visible", true)
        compare(pool.manaPool.length, 3)
        compare(item("forgeMana-0-U").modelData.amount, 2)
        compare(item("forgeMana-0-C").modelData.amount, 3)
        compare(pool.parent, item("forgeDuelTable"))
        verify(pool.z > item("forgeHand").z)
        verify(pool.z > item("rulesCardHoverPreview").z)
        tryVerify(() => pool.width > item("forgeMana-0-C").width)
        state.players[0].manaPool[0].value = 1
        verify(testRulesPrompt.applySnapshot(state))
        compare(item("forgeMana-0-U").modelData.amount, 1)
        state.players[0].manaPool = []
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(pool, "visible", false)
    }
    function test_confirmedBlocksAndAttachmentsRemainVisible() {
        const state = snapshot(1, 3)
        state.step = "declare_blockers"
        state.zones[4].cards[0].blocking = ["opponent"]
        state.zones[4].cards[1].attachedTo = "own-2"
        state.zones[5].cards[0].attacking = true
        state.zones[5].cards[0].attackingPlayer = 0
        state.zones[5].cards.push(card("walker-hit", 1, "Goblin Guide", true))
        state.zones[5].cards[1].attacking = true
        state.zones[5].cards[1].attackingTarget = "own-2"
        state.zones[5].count = 2
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"pass", kind:"pass", label:"Pass"}]})
        tryCompare(item("forgeOwnCreatures"), "stackCount", 2)
        compare(table.rulesSession.battlefieldRelationships.length, 4)
        tryCompare(item("forgeCardInteractionHint-own-0"), "text", "Blocking")
        compare(item("forgeCardInteractionHint-opponent").text, "Attacking you · Blocked")
        compare(item("forgeCardInteractionHint-own-1").text, "")
        compare(item("forgeCardInteractionHint-own-2").text, "Attacked")
        compare(item("forgeCardInteractionHint-walker-hit").text, "Attacking Grizzly Bears")
        const host = item("forgeCard-own-2")
        const aura = item("forgeCard-own-1")
        verify(aura.parent === host.parent)
        verify(aura.y > host.y)
        verify(aura.z < host.z)
        const block = item("forgeRelationship-block-own-0-opponent")
        const playerAttack = item("forgeRelationship-attack-opponent-")
        const permanentAttack = item("forgeRelationship-attack-walker-hit-own-2")
        tryCompare(block, "validAnchors", true)
        tryCompare(playerAttack, "validAnchors", true)
        tryCompare(permanentAttack, "validAnchors", true)
        verify(!item("forgeRelationship-attachment-own-1-own-2").visible)
        verify(item("rulesPlayerTarget0").underAttack)
        verify(!item("rulesPlayerTarget1").underAttack)
        table.openCardDetails("own-2")
        verify(item("forgeDuelTable").inspectionDock.inspector.persistentSummary.includes("Attachment: Grizzly Bears"))

        state.zones[4].cards[1].attachedTo = "hand-0"
        state.zones[4].cards[0].blocking = ["hand-0", "missing"]
        verify(testRulesPrompt.applySnapshot(state))
        compare(table.rulesSession.battlefieldRelationships.length, 2)
        tryCompare(item("forgeOwnCreatures"), "stackCount", 2)
        compare(item("forgeCardInteractionHint-own-0").text, "")
    }
    function test_reviewArtworkCannotCollapseGrid_data() {
        return [{tag:"portrait-desktop", width:1600, height:1000, image:"card-back.jpg"},
                {tag:"large-raster-compact", width:900, height:620, image:"playmat-dusk.png"}]
    }
    function test_reviewArtworkCannotCollapseGrid(data) {
        window.width = data.width
        window.height = data.height
        catalog.imageOverride = Qt.resolvedUrl("../../qml/assets/" + data.image)
        match.sideboarding = true
        mouseClick(item("sideboardReviewButton"))
        const review = item("sideboardBoardReview")
        tryCompare(review, "opened", true)
        const grid = findChild(review.contentItem, "sideboardReviewCards")
        const preview = findChild(review.contentItem, "sideboardReviewPreview")
        const art = findChild(review.contentItem, "sideboardReviewPreviewImage")
        tryCompare(art, "status", Image.Ready)
        verify(waitForRendering(review.contentItem))
        verify(grid.width >= review.availableWidth * 0.6, "Card grid must keep most of the width")
        verify(grid.height > 150)
        verify(preview.width <= review.availableWidth * 0.3 + 1, "Artwork cannot widen the preview column")
        verify(grid.x + grid.width <= preview.x + 1, "Card grid and preview must not overlap")
        const last = preview.mapToItem(review.contentItem, preview.width, preview.height)
        verify(last.x <= review.availableWidth + 1 && last.y <= review.availableHeight + 1)
        verify(art.width > 0 && art.height > 0)
        review.close()
    }
    function test_sideboardReviewUsesOnlyVisiblePublicZonesAndRefreshesOnReconnect() {
        const state = snapshot(3)
        state.zones.push({zone:"graveyard", ownerSeat:1, count:1,
                         cards:[card("grave", 1, "Known spell", false)]})
        const hidden = card("hidden-review", 1, "Secret morph", true)
        hidden.faceDown = true
        state.zones[5].cards.push(hidden)
        verify(testRulesPrompt.applySnapshot(state))
        match.sideboarding = true
        const panel = item("rulesSideboardPanel")
        mouseClick(item("sideboardReviewButton"))
        const review = findChild(panel, "sideboardBoardReview")
        tryCompare(review, "opened", true)
        verify(review.reviewCards.some(card => card.name === "Known spell"))
        verify(!review.reviewCards.some(card => card.name === "Secret morph" || card.zone === "hand"))
        testRulesPrompt.clear()
        tryCompare(review, "reviewCards", [])
        verify(testRulesPrompt.applySnapshot(state))
        tryVerify(() => review.reviewCards.some(card => card.name === "Known spell"))
        panel.visible = false
        tryCompare(review, "opened", false)
    }
    function test_crowdedLanesAndHandRemainReachable() {
        verify(testRulesPrompt.applySnapshot(snapshot(20, 70, true)))
        const lane = item("forgeOwnCreatures"), hand = item("forgeHand")
        tryVerify(() => lane.visibleCards.length === 70 && hand.visibleCards.length === 20)
        verify(lane.scrollArea.contentHeight > lane.scrollArea.height)
        verify(hand.scrollArea.contentWidth > hand.scrollArea.width)
        item("forgeCard-own-69").forceActiveFocus()
        verify(lane.scrollArea.contentY > 0)
        item("forgeHandSurface-hand-19").forceActiveFocus()
        verify(hand.scrollArea.contentX > 0)
        const point = item("forgeHandSurface-hand-19").mapToItem(hand.scrollArea, 0, 0)
        verify(point.x >= 0 && point.x + hand.cardWidth <= hand.width + 1)
    }
    function test_combatSeparatesSelectedFromIdleCopies_data() {
        return [{tag:"front-ineligible", cards:2, eligible:1},
                {tag:"two-eligible", cards:2, eligible:2},
                {tag:"three-eligible", cards:3, eligible:3}]
    }
    function test_combatSeparatesSelectedFromIdleCopies(data) {
        verify(testRulesPrompt.applySnapshot(snapshot(3, data.cards)))
        prompt("chooseAttackers", {
            combatSources:Array.from({length:data.eligible}, (_, i) => ({
                responseId:"source-" + i, objectId:"own-" + i, label:"Bear", name:"Grizzly Bears",
                validTargetIds:["defender"], mustAssignIfAble:false, maxAssignments:1})),
            combatTargets:[{responseId:"defender", kind:"player", seat:1, label:"Opponent",
                minAssignments:0, maxAssignments:8}]
        })
        tryCompare(item("forgeOwnCreatures"), "stackCount", 1)
        verify(table.combatInteraction.canAct)
        const front = item("forgeCard-own-" + (data.cards - 1))
        compare(front.card.stackSize, data.cards)
        const expected = []
        for (let i = 0; i < data.eligible; ++i) {
            const source = item("forgeCard-own-" + i)
            verify(source.actionable)
            mouseClick(front)
            expected.push({sourceId:"source-" + i, targetId:"defender"})
            compare(Object.keys(table.combatInteraction.assignments).length, expected.length)
            compare(table.combatInteraction.assignments["source-" + i], "defender")
            compare(source.card.stackSize, i + 1)
            compare(item("forgeOwnCreatures").stackCount, i + 1 === data.cards ? 1 : 2)
            verify(waitForPolish(window))
        }
        const confirm = item("rulesConfirmCombat-attackers")
        const dock = item("rulesDecisionDock")
        const center = confirm.mapToItem(dock, confirm.width / 2, confirm.height / 2)
        verify(center.x >= 0 && center.y >= 0 && center.x <= dock.width && center.y <= dock.height)
        verify(confirm.enabled)
        mouseClick(confirm)
        compare(transport.responses[0].assignments, expected)
        action("playLand", "hand-0")
        tryCompare(item("forgeOwnCreatures"), "stackCount", 1)
    }
    function test_blockingRepeatedAttackersKeepsEveryCreatureReachable() {
        const state = snapshot(1, 3)
        state.zones[5].cards = [0, 1, 2].map(i => card("attacker-" + i, 1, "Cat", true))
        state.zones[5].count = 3
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseBlockers", {
            combatSources:[0, 1, 2].map(i => ({responseId:"blocker-" + i, objectId:"own-" + i,
                label:"Bear", name:"Grizzly Bears", maxAssignments:1,
                validTargetIds:["target-0", "target-1", "target-2"]})),
            combatTargets:[0, 1, 2].map(i => ({responseId:"target-" + i, objectId:"attacker-" + i,
                kind:"attacker", label:"Cat", minAssignments:1, maxAssignments:3}))
        })
        tryCompare(item("forgeOwnCreatures"), "stackCount", 1)
        tryCompare(item("forgeOpponentCreatures"), "stackCount", 1)
        for (let i = 0; i < 3; ++i) {
            mouseClick(item("forgeCard-own-" + i))
            compare(table.combatInteraction.selectedSource, "blocker-" + i)
            mouseClick(item("forgeCard-attacker-" + i))
            compare(table.combatInteraction.assignments["blocker-" + i], "target-" + i)
            verify(waitForPolish(window))
        }
        const back = item("forgeCard-own-0"), pileFront = item("forgeCard-own-2")
        compare(item("forgeOwnCreatures").stackCount, 3)
        compare(item("forgeOpponentCreatures").stackCount, 3)
        compare(back.card.stackSize, 1)
        verify(Math.abs(back.mapToItem(table, 0, 0).x - pileFront.mapToItem(table, 0, 0).x) > 20)
        mouseClick(back)
        compare(table.combatInteraction.selectedSource, "blocker-0")
        mouseClick(item("forgeCard-attacker-2"))
        compare(table.combatInteraction.assignments["blocker-0"], "target-2")
        compare(table.combatInteraction.links.filter(link => link.to === "attacker-2").length, 2)
        compare(item("forgeOwnCreatures").stackCount, 2)
        compare(item("forgeCard-own-2").card.stackSize, 2)
        mouseClick(item("rulesConfirmCombat-blockers"))
        compare(transport.responses[0].assignments.length, 3)
    }
    function test_combatParticipantsSplitFromIdleTokens_data() {
        const rows = []
        for (const seats of [2, 4])
            for (const kind of ["chooseAttackers", "chooseBlockers"])
                rows.push({tag:seats + "-players-" + kind, seats:seats, kind:kind})
        return rows
    }
    function test_combatParticipantsSplitFromIdleTokens(data) {
        const attacking = data.kind === "chooseAttackers"
        room.maxSeats = data.seats
        room.format = data.seats === 4 ? "edh" : "modern"
        const state = snapshot(1, 1)
        state.step = attacking ? "declare_attackers" : "declare_blockers"
        state.activeSeat = attacking ? 0 : 1
        for (let seat = 2; seat < data.seats; ++seat)
            state.players.push({seat:seat, name:"Player " + seat, life:40})
        const copies = Array.from({length:10}, (_, i) => token("spawn-" + i, 0, "Eldrazi Spawn", true))
        state.zones[4].cards = copies
        state.zones[4].count = copies.length
        if (!attacking) {
            state.zones[5].cards[0].attacking = true
            state.zones[5].cards[0].attackingPlayer = 0
        }
        verify(testRulesPrompt.applySnapshot(state))
        prompt(data.kind, {
            combatSources:copies.map(copy => ({responseId:"source-" + copy.id, objectId:copy.id,
                label:"Spawn", validTargetIds:["destination"], maxAssignments:1})),
            combatTargets:[{responseId:"destination", kind:attacking ? "player" : "attacker",
                objectId:attacking ? "" : "opponent", seat:1, label:"Opponent", maxAssignments:10}]
        })
        const lane = item(data.seats === 4 ? "forgeCreatures-0" : "forgeOwnCreatures")
        tryCompare(lane, "stackCount", 1)
        const front = item("forgeCard-spawn-9")
        mouseClick(front)
        tryCompare(lane, "stackCount", 2)
        const first = item("forgeCard-spawn-0")
        compare(first.card.stackSize, 1)
        compare(front.card.stackSize, 9)
        verify(first.pointerEnabled)
        verify(waitForPolish(window))
        const firstRect = first.mapToItem(lane, 0, 0, first.width, first.height)
        const idleRect = front.mapToItem(lane, 0, 0, front.width, front.height)
        verify(firstRect.x + firstRect.width <= idleRect.x || idleRect.x + idleRect.width <= firstRect.x
            || firstRect.y + firstRect.height <= idleRect.y || idleRect.y + idleRect.height <= firstRect.y,
            "A combat participant must have a separate visible card face")
        mouseClick(first)
        tryCompare(lane, "stackCount", 1)
        compare(table.combatInteraction.links.length, 0)
        compare(front.card.stackSize, 10)
        verify(waitForPolish(window))
        mouseClick(front)
        verify(waitForPolish(window))
        mouseClick(front)
        tryCompare(lane, "stackCount", 2)
        compare(front.card.stackSize, 8)
        compare(item("forgeCard-spawn-1").card.stackSize, 2)
        mouseClick(item("rulesConfirmCombat-" + (attacking ? "attackers" : "blockers")))
        compare(transport.responses[0].assignments.length, 2)

        for (let i = 0; i < 2; ++i) {
            if (attacking) {
                copies[i].attacking = true
                copies[i].attackingPlayer = 1
            } else copies[i].blocking = ["opponent"]
        }
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"pass", kind:"pass", label:"Pass"}]})
        tryCompare(lane, "stackCount", 2)
        compare(table.combatInteraction.links.length, 0)
        compare(first.card.stackSize, 2)
        compare(item("forgeCard-spawn-1").card.stackSize, 2)
        compare(front.card.stackSize, 8)
        if (attacking) {
            copies[0].tapped = true
            copies[1].tapped = true
            verify(testRulesPrompt.applySnapshot(state))
            verify(waitForPolish(window))
            verify(!rectsOverlap(item("forgeCard-spawn-1"), front),
                   "A spent attacking pile must not cover the idle pile's face or count badge")
        }
        room.role = "spectator"
        tryCompare(lane, "stackCount", 2)
        state.step = "main2"
        for (const copy of copies) {
            copy.attacking = false
            copy.tapped = false
            delete copy.attackingPlayer
            copy.blocking = []
        }
        state.zones[5].cards[0].attacking = false
        delete state.zones[5].cards[0].attackingPlayer
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(lane, "stackCount", 1)
        compare(front.card.stackSize, 10)
    }
    function test_blockedAttackersSeparateFromUnblockedCopies() {
        const state = snapshot(1, 3)
        state.step = "combat_damage"
        for (const creature of state.zones[4].cards.filter(row => row.power)) {
            creature.attacking = true
            creature.attackingPlayer = 1
        }
        state.zones[5].cards[0].blocking = ["own-0"]
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"pass", kind:"pass", label:"Pass"}]})
        const lane = item("forgeOwnCreatures")
        tryCompare(lane, "stackCount", 2)
        compare(item("forgeCard-own-0").card.stackSize, 1)
        compare(item("forgeCard-own-2").card.stackSize, 2)
        verify(item("forgeCardInteractionHint-own-0").text.includes("Blocked"))
        verify(!item("forgeCardInteractionHint-own-2").text.includes("Blocked"))
        // A blocker allowed to block several creatures gives both the same
        // public relationship, so those two copies can share a combat pile.
        state.zones[5].cards[0].blocking = ["own-0", "own-1"]
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(lane, "stackCount", 2)
        compare(item("forgeCard-own-1").card.stackSize, 2)
        compare(item("forgeCard-own-2").card.stackSize, 1)
        state.zones[5].cards[0].blocking = []
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(lane, "stackCount", 1)
        compare(item("forgeCard-own-2").card.stackSize, 3)
    }
    function test_combatPileReadoutsClearStatusPhase_data() {
        return [{tag:"single-attacker", width:1920, height:1011, scale:1, attackers:1},
            {tag:"attacking-pile", width:1920, height:1011, scale:1, attackers:2},
            {tag:"scaled-pile", width:1920, height:1011, scale:1.5, attackers:2},
            {tag:"compact-pile", width:900, height:620, scale:1.5, attackers:2}]
    }
    function test_combatPileReadoutsClearStatusPhase(data) {
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        const state = snapshot(1, 3)
        state.step = "declare_blockers"; state.prioritySeat = 1
        for (let index = 0; index < data.attackers; ++index) {
            state.zones[4].cards[index].attacking = true
            state.zones[4].cards[index].attackingPlayer = 1
            state.zones[4].cards[index].tapped = true
        }
        verify(testRulesPrompt.applySnapshot(state))
        prompt("", {pending:false, supported:false})
        verify(waitForPolish(window)); verify(waitForRendering(table))
        const lane = item("forgeOwnCreatures"), track = item("forgePhaseTrack")
        const phase = track.compactMode ? item("forgeCurrentPhase") : track
        const banner = item("forgeOpponentDeciding")
        verify(banner.visible)
        for (const slot of lane.visibleCards.filter(card => card.stackFront)) {
            const prefixes = slot.stackSize > 1
                ? ["forgeCardName-", "forgeCardStackCount-"] : ["forgeCardName-"]
            for (const prefix of prefixes) {
                const label = item(prefix + slot.cardId)
                if (!label.visible) continue
                verify(!rectsOverlap(label, banner), "The deciding banner must leave " + label.objectName + " visible")
                verify(!rectsOverlap(label, phase), "The phase strip must leave " + label.objectName + " visible")
            }
        }
        const before = boardGeometry(["own-0", "own-1", "own-2"])
        state.prioritySeat = 0
        verify(testRulesPrompt.applySnapshot(state))
        verify(waitForPolish(window)); verify(waitForRendering(table))
        compare(boardGeometry(["own-0", "own-1", "own-2"]), before,
                "Changing priority cannot move or resize the combat piles")
    }
    function test_expandedCombatKeepsRightmostPileClickable_data() {
        return ["chooseAttackers", "chooseBlockers"].map(kind => ({tag:kind, kind:kind}))
    }
    function test_expandedCombatKeepsRightmostPileClickable(data) {
        window.width = 1920; window.height = 1011
        const state = snapshot(7, 7, true)
        // The last pile reproduced the covered White Orchid Phantom in the
        // live Legacy game. Include another physical copy in that pile.
        state.zones[4].cards.push(card("own-7", 0, "Bear 6", true))
        state.zones[4].count++
        verify(testRulesPrompt.applySnapshot(state))
        prompt(data.kind, {
            combatSources:Array.from({length:8}, (_, i) => ({
                responseId:"source-" + i, objectId:"own-" + i, label:"Bear " + Math.min(i, 6),
                name:"Bear " + Math.min(i, 6), validTargetIds:["defender"], maxAssignments:1})),
            combatTargets:[{responseId:"defender", kind:data.kind === "chooseAttackers" ? "player" : "attacker",
                objectId:data.kind === "chooseAttackers" ? "" : "opponent", seat:1,
                label:"Opponent", minAssignments:0, maxAssignments:8}]
        })
        const front = item("forgeCard-own-7"), dock = item("rulesDecisionDock")
        tryCompare(item("forgeOwnCreatures"), "stackCount", 7)
        tryVerify(() => front.card.stackFront)
        const point = front.mapToItem(table, 0, 0)
        verify(point.x + front.width <= dock.x || point.y + front.height <= dock.y,
               "An expanded combat decision must not cover its battlefield sources")
        mouseClick(item("forgeCard-own-6"))
        mouseClick(item(data.kind === "chooseBlockers" ? "forgeCard-opponent" : "rulesPlayerTarget1"))
        compare(table.combatInteraction.assignments["source-6"], "defender")
        mouseClick(front)
        mouseClick(item(data.kind === "chooseBlockers" ? "forgeCard-opponent" : "rulesPlayerTarget1"))
        compare(table.combatInteraction.assignments["source-7"], "defender")
        mouseClick(item("rulesConfirmCombat-" + (data.kind === "chooseAttackers" ? "attackers" : "blockers")))
        compare(transport.responses[0].assignments.length, 2)
    }
    function test_repeatedOpponentTargetsAcceptDistinctClicks() {
        const state = snapshot()
        state.zones[5].cards = [0, 1].map(i => card("opponent-" + i, 1, "Grizzly Bears", true))
        state.zones[5].count = 2
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(item("forgeOpponentCreatures"), "stackCount", 1)
        prompt("chooseBoardTargets", {minSelections:2, maxSelections:2,
            targets:[0, 1].map(i => ({responseId:"target-" + i, kind:"card",
                objectId:"opponent-" + i, label:"Bear", name:"Grizzly Bears"}))})
        mouseClick(item("forgeCard-opponent-1"))
        compare(table.interaction.selectedCount, 1)
        mouseClick(item("forgeCard-opponent-0"))
        compare(table.interaction.selectedCount, 2)
        mouseClick(item("rulesConfirmTargets"))
        compare(transport.responses.length, 1)
        compare(transport.responses[0].targets, ["target-0", "target-1"])
    }
    function test_targetCandidatesRemainIndividuallyReachable_data() {
        return [{tag:"own-creatures", seat:0, name:"Grizzly Bears", category:"Creatures", count:2, eligible:2},
                {tag:"opponent-tokens", seat:1, name:"Cat", category:"Creatures", count:3, eligible:3, token:true},
                {tag:"opponent-lands", seat:1, name:"Plains", category:"Lands", count:4, eligible:2},
                {tag:"opponent-planeswalkers", seat:1, name:"Test Walker", category:"Planeswalkers", count:2, eligible:2},
                {tag:"opponent-other", seat:1, name:"Test Battle", category:"Other", count:2, eligible:2},
                {tag:"front-ineligible", seat:1, name:"Grizzly Bears", category:"Creatures", count:2, eligible:1}]
    }
    function test_targetCandidatesRemainIndividuallyReachable(data) {
        const state = snapshot(), zone = state.zones[data.seat === 0 ? 4 : 5]
        zone.cards = Array.from({length:data.count}, (_, i) =>
            (data.token ? token : card)("copy-" + i, data.seat, data.name, data.category === "Creatures"))
        zone.count = data.count
        verify(testRulesPrompt.applySnapshot(state))
        const lane = item("forge" + (data.seat === 0 ? "Own" : "Opponent") + data.category)
        tryCompare(lane, "stackCount", 1)
        const targets = Array.from({length:data.eligible}, (_, i) => ({responseId:"target-" + i,
            kind:"card", objectId:"copy-" + i, label:data.name, name:data.name}))
        prompt("chooseBoardTargets", {minSelections:data.eligible, maxSelections:data.eligible, targets:targets})
        tryCompare(lane, "stackCount", 1)
        const front = item("forgeCard-copy-" + (data.count - 1))
        verify(front.pointerEnabled)
        const expected = []
        for (let i = 0; i < data.eligible; ++i) {
            const face = item("forgeCard-copy-" + i)
            verify(face.actionable)
            mouseClick(front)
            expected.push("target-" + i)
            compare(table.interaction.selectedCount, expected.length)
        }
        if (data.eligible > 1) {
            compare(transport.responses.length, 0)
            showPile("copy-" + (data.count - 1))
            const first = item("forgeCard-copy-0")
            mouseClick(first)
            verify(!first.selected)
            compare(table.interaction.selectedCount, data.eligible - 1)
            mouseClick(first)
            verify(first.selected)
            mouseClick(item("rulesConfirmTargets"))
        }
        compare(transport.responses.length, 1)
        compare(transport.responses[0].targets.slice().sort(), expected.slice().sort())
        verify(transport.rulesResponsePending)
        waitForRendering(table)
        compare(lane.stackCount, 1)

        // A new publication of the same prompt id can change eligibility without a snapshot.
        prompt("chooseBoardTargets", {promptId:serial, minSelections:1, maxSelections:1,
            targets:[{responseId:"replacement", kind:"card", objectId:"copy-" + (data.count - 1),
                label:data.name, name:data.name}]})
        tryCompare(lane, "stackCount", 1)
        compare(table.interaction.selectedCount, 0)
        const replacement = item("forgeCard-copy-" + (data.count - 1))
        verify(replacement.pointerEnabled && replacement.actionable)
        mouseClick(replacement)
        compare(transport.responses[1].targets, ["replacement"])
        action("playLand", "hand-0")
        tryCompare(lane, "stackCount", 1)
    }
    function test_nativeCostSelectionsKeepExactCopiesWithoutResubmittingReservations() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, 3)))
        const lane = item("forgeOwnCreatures")
        function costPrompt(selected) {
            prompt("chooseBoardTargets", {minSelections:0, maxSelections:1, cancellable:true,
                targets:[0, 1, 2].map(i => ({responseId:"target-" + i, kind:"card",
                    objectId:"own-" + i, label:"Bear", name:"Grizzly Bears",
                    selected:selected.includes(i)}))})
        }
        costPrompt([])
        tryCompare(lane, "visibleStackIds", [["own-0", "own-1", "own-2"]])
        showPile("own-2")
        mouseClick(item("forgeCard-own-2"))
        compare(transport.responses[0].targets, ["target-2"])

        costPrompt([2])
        tryCompare(lane, "visibleStackIds", [["own-0", "own-1", "own-2"]])
        verify(findChild(item("forgeCard-own-2"), "forgeCardNativeSelection-own-2").visible)
        const selectedCard = item("forgeCard-own-2")
        const marker = findChild(selectedCard, "forgeCardNativeSelection-own-2")
        const name = findChild(selectedCard, "forgeCardName-own-2")
        verify(name.mapToItem(selectedCard, 0, 0).x >= marker.x + marker.width)
        verify(item("forgeCard-own-2").selected)
        compare(table.interaction.nativeSelectedCount, 1)
        compare(table.interaction.selectedCount, 0)
        verify(!item("forgeCard-own-1").selected)
        showPile("own-2")
        mouseClick(item("forgeCard-own-1"))
        compare(transport.responses[1].targets, ["target-1"])

        costPrompt([1, 2])
        tryCompare(lane, "visibleStackIds", [["own-0", "own-1", "own-2"]])
        compare(table.interaction.nativeSelectedCount, 2)
        compare(table.interaction.selectedCount, 0)
        showPile("own-2")
        mouseClick(item("forgeCard-own-2"))
        compare(transport.responses[2].targets, ["target-2"])

        costPrompt([1])
        tryCompare(lane, "visibleStackIds", [["own-0", "own-1", "own-2"]])
        verify(!findChild(item("forgeCard-own-2"), "forgeCardNativeSelection-own-2").visible)
        verify(findChild(item("forgeCard-own-1"), "forgeCardNativeSelection-own-1").visible)
        verify(table.interaction.submitTargets("$submit"))
        compare(transport.responses[3].targets, [])

        prompt("payManaCost", {options:[{responseId:"$cancel", label:"Cancel", kind:"cancel"}]})
        tryCompare(lane, "visibleStackIds", [["own-0", "own-1", "own-2"]])
        compare(table.interaction.nativeSelectedCount, 0)
        verify(!findChild(item("forgeCard-own-1"), "forgeCardNativeSelection-own-1").visible)
    }
    function test_ownPlayerTargetAboveHoveredHand_data() {
        return [{tag:"seven-cards", hand:7, width:1600, height:1000},
                {tag:"crowded-desktop", hand:12, width:1920, height:1011}]
    }
    function test_ownPlayerTargetAboveHoveredHand(data) {
        window.width = data.width; window.height = data.height
        verify(testRulesPrompt.applySnapshot(snapshot(data.hand, 1)))
        prompt("chooseBoardTargets", {minSelections:1, maxSelections:2,
            targets:[{responseId:"self", kind:"player", seat:0, label:"Alice"},
                     {responseId:"opponent", kind:"player", seat:1, label:"Bob"}]})
        const plate = item("rulesPlayerTarget0")
        const hand = item("forgeHand")
        const nearest = hand.visibleCards.reduce((best, card) => {
            const point = card.mapToItem(plate, card.width / 2, 0)
            const previous = best.mapToItem(plate, best.width / 2, 0)
            return Math.abs(point.x - plate.width / 2) < Math.abs(previous.x - plate.width / 2) ? card : best
        })
        mouseMove(nearest, nearest.width / 2, nearest.height / 2)
        tryCompare(item("forgeHandSurface-" + nearest.cardId), "y", -18 * table.presentation.unit)
        mouseClick(plate, plate.width / 2, plate.lifeCenterY)
        compare(Object.keys(table.interaction.selectedTargetIds), ["self"])
        compare(transport.responses.length, 0)
    }
    function test_stackOrderPrivacyAndTargetsUseNativeIds() {
        const state = snapshot()
        state.stack = [{id:"bolt", controllerSeat:0, identity:{name:"Lightning Bolt"}, text:"Deal 3 damage"},
            {id:"hidden-spell", controllerSeat:1, text:"Face-down spell"}]
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseBoardTargets", {minSelections:1, maxSelections:2, targets:[
            {responseId:"target-spell", kind:"spell", objectId:"bolt", label:"Bolt"},
            {responseId:"target-player", kind:"player", seat:1, label:"Bob"}]})
        const stack = item("forgeStack")
        compare(stack.count, 2)
        verify(item("forgeStackEntry-bolt").y < item("forgeStackEntry-hidden-spell").y)
        compare(item("forgeStackCard-hidden-spell").publicFace, false)
        mouseClick(item("forgeStackCard-bolt"))
        verify(item("forgeStackCard-bolt").selected)
        mouseClick(item("rulesPlayerTarget1"))
        compare(Object.keys(table.interaction.selectedTargetIds), ["target-spell", "target-player"])
        compare(transport.responses.length, 0)
        prompt("chooseBoardTargets", {minSelections:1, maxSelections:1, targets:[
            {responseId:"new-target", kind:"spell", objectId:"bolt", label:"Bolt"}]})
        mouseClick(item("forgeStackCard-bolt"))
        compare(transport.responses[0].targets, ["new-target"])
        const pictured = snapshot()
        pictured.stack = [{id:"effect", sourceId:"own-0", controllerSeat:0,
            identity:{name:"Grizzly Bears (1)'s Effect"}, text:"At the beginning of your upkeep, draw a card."}]
        verify(testRulesPrompt.applySnapshot(pictured))
        compare(item("forgeStackCard-effect").card.name, "Grizzly Bears")
        compare(item("forgeStackName-effect").text, "Grizzly Bears (1)'s Effect")
        const track = item("forgePhaseTrack")
        verify(track.x + track.width <= table.presentation.boardRight + 1)
        verify(waitForPolish(window)); waitForRendering(table)
        assertDuelPublicFieldAllocation()
        assertPublicPhaseAnchor()
    }
    function test_controlledTurnUsesPermittedHandAndRestoresOwnHand() {
        const state = snapshot()
        state.activeSeat = 1; state.prioritySeat = 1
        state.players[1].controllingSeat = 0
        state.zones[1].cards = [card("controlled-land", 1, "Plains", false)]
        verify(testRulesPrompt.applySnapshot(state))
        action("playLand", "controlled-land")
        tryCompare(table, "handOwnerSeat", 1)
        tryVerify(() => item("forgeHand").visibleCards[0].cardId === "controlled-land")
        compare(item("forgePlayerControlStatus").text, "You control " + table.matchUi.playerName(1) + "'s turn")
        verify(item("forgePlayerControlStatus").visible)
        verify(table.priority.canPass)
        wait(150)
        compare(transport.responses.length, 0, "Smart priority skipped the controlled player's main phase")
        mouseClick(item("forgeHandCard-controlled-land"))
        compare(transport.responses[0].response, "opaque-play")
        action("playLand", "controlled-land")
        verify(table.priority.passOnce())
        compare(transport.responses[1].response, "$pass")

        // The compensatory extra turn belongs to Bob without Alice's control.
        delete state.players[1].controllingSeat
        state.zones[1].cards = []
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {pending:false})
        tryCompare(table, "handOwnerSeat", 0)
        tryVerify(() => item("forgeHand").visibleCards[0].cardId === "hand-0")
        verify(!item("forgePlayerControlStatus").visible)
        compare(testRulesPrompt.session.cardForInspection("controlled-land"), {})
    }

    function test_permittedLibraryTopCanBePlayedAndVisibilityRevoked() {
        table.priority.setFullControl(true)
        const state = snapshot()
        state.zones[2].cards = [card("top-land", 0, "Plains", false)]
        verify(testRulesPrompt.applySnapshot(state))
        action("playLand", "top-land")
        const pile = item("forgeZone-library")
        tryCompare(pile, "cardId", "top-land")
        verify(pile.showsPublicFace)
        mouseClick(pile)
        tryCompare(item("forgeZonePopup"), "opened", true)
        tryCompare(item("forgeZoneCards"), "stackCount", 1)
        verify(!item("forgeZoneCardsHiddenNotice").visible)
        mouseClick(item("forgeCard-top-land"))
        compare(transport.responses[0].response, "opaque-play")

        state.zones[2].cards = []
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        tryCompare(pile, "cardId", "")
        verify(!pile.showsPublicFace)
        compare(testRulesPrompt.session.cardForInspection("top-land"), {})
        tryCompare(item("forgeZoneCards"), "stackCount", 0)
        mouseClick(pile)
        tryCompare(item("forgeZonePopup"), "opened", true)
        verify(item("forgeZoneCardsHiddenNotice").visible)
    }

    function test_newPermanentsShareASlotWhileStateLabelsRemain_data() {
        return [{tag:"english", chinese:false}, {tag:"chinese", chinese:true}]
    }
    function test_newPermanentsShareASlotWhileStateLabelsRemain(data) {
        if (data.chinese) testTranslations.setLanguage("zh")
        const state = snapshot(1, 2)
        const fresh = state.zones[4].cards[1]
        fresh.enteredThisTurn = true; fresh.summoningSick = true
        verify(testRulesPrompt.applySnapshot(state))
        const lane = item("forgeOwnCreatures")
        tryCompare(lane, "visibleStackIds", [["own-0", "own-1"]])
        const label = findChild(item("forgeCard-own-1"), "forgeCardState-own-1")
        verify(label.visible)
        compare(label.text, data.chinese ? "本回合进场 · 召唤失调" : "Entered this turn · Summoning sickness")
        compare(findChild(item("forgeCard-own-0"), "forgeCardState-own-0").text, "")
        fresh.enteredThisTurn = false
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(lane, "stackCount", 1)
        fresh.summoningSick = false
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(lane, "visibleStackIds", [["own-0", "own-1"]])
    }

    function test_zonePopupClosesWhenConnectionEnds() {
        mouseClick(item("forgeZone-library"))
        const popup = item("forgeZonePopup")
        tryCompare(popup, "opened", true)
        transport.inRoom = false
        tryCompare(popup, "opened", false)
    }
    function test_hiddenLibraryUsesLiveZoneCounts_data() {
        return [{tag:"own", opponent:false, seat:0, count:50},
            {tag:"opponent", opponent:true, seat:1, count:49}]
    }
    function test_hiddenLibraryUsesLiveZoneCounts(data) {
        mouseClick(item(data.opponent ? "forgeOpponentZones" : "forgeZone-library"))
        tryCompare(item("forgeZonePopup"), "opened", true)
        waitForRendering(item("forgeZonePopup").contentItem)
        if (data.opponent) mouseClick(item("forgeZoneTab-library"))
        const lane = item("forgeZoneCards"), label = item("forgeZoneCardsCount")
        compare(lane.ownerSeat, data.seat)
        compare(lane.zone, "library")
        tryCompare(lane, "cardCount", data.count)
        compare(label.text, "Library  /  " + data.count)
        compare(lane.visibleCards.length, 0)
        verify(item("forgeZoneCardsHiddenNotice").visible)
        const state = snapshot()
        const library = state.zones.find(zone => zone.ownerSeat === data.seat && zone.zone === "library")
        const hand = state.zones.find(zone => zone.ownerSeat === data.seat && zone.zone === "hand")
        library.count--; hand.count++
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(lane, "cardCount", data.count - 1)
        compare(label.text, "Library  /  " + (data.count - 1))
        compare(item("forgePlayerZones-" + data.seat).text,
                "Hand · " + hand.count + " · Library · " + library.count)
        compare(lane.visibleCards.length, 0)
        compare(transport.responses.length, 0)
        library.count = 0
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(label, "text", "Library  /  0")
        verify(!item("forgeZoneCardsHiddenNotice").visible)
        mouseClick(item("forgeCloseZonePopup"))
        tryCompare(item("forgeZonePopup"), "visible", false)
    }
    function test_zoneCountIncludesUnidentifiedCards() {
        const state = snapshot()
        state.zones.push({zone:"exile", ownerSeat:1, count:3,
            cards:[card("known-exile", 1, "Plains", false)]})
        verify(testRulesPrompt.applySnapshot(state))
        mouseClick(item("forgeOpponentZones"))
        tryCompare(item("forgeZonePopup"), "opened", true)
        waitForRendering(item("forgeZonePopup").contentItem)
        mouseClick(item("forgeZoneTab-exile"))
        tryVerify(() => item("forgeZoneCards").visibleCards.length === 1)
        compare(item("forgeZoneCardsCount").text, "Exile  /  3")
        mouseClick(item("forgeCloseZonePopup"))
        tryCompare(item("forgeZonePopup"), "visible", false)
    }
    function test_commandZoneOnlyInDuel_data() {
        return ["standard", "pioneer", "modern", "legacy", "vintage", "pauper", "duel"].map(
            format => ({tag:format, format:format, commander:format === "duel"}))
    }
    function test_commandZoneOnlyInDuel(data) {
        room.format = data.commander ? "duel" : "modern"
        room.deckFormat = data.format
        waitForRendering(table)
        compare(findChild(table, "forgeZone-command") !== null, data.commander)
        for (const opener of ["forgeZone-library", "forgeOpponentZones"]) {
            mouseClick(item(opener))
            tryCompare(item("forgeZonePopup"), "opened", true)
            waitForRendering(item("forgeZonePopup").contentItem)
            compare(findChild(item("forgeZonePopup").contentItem, "forgeZoneTab-command") !== null, data.commander)
            if (data.commander) {
                mouseClick(item("forgeZoneTab-command"))
                compare(item("forgeZoneCards").zone, "command")
            }
            mouseClick(item("forgeCloseZonePopup"))
            tryCompare(item("forgeZonePopup"), "visible", false)
        }
    }
    function test_zonePilesOpenMatchingBrowser() {
        const own = item("forgeZone-graveyard")
        compare(own.width, Math.round(own.width))
        compare(own.height, Math.round(own.height))
        compare(own.zone, "graveyard")
        mouseClick(own)
        tryCompare(item("forgeZonePopup"), "opened", true)
        compare(item("forgeZonePopup").zone, "graveyard")
        compare(item("forgeZonePopup").ownerSeat, 0)
        mouseClick(item("forgeCloseZonePopup"))
        tryCompare(item("forgeZonePopup"), "visible", false)
        mouseClick(item("forgeOpponentZone-exile"))
        tryCompare(item("forgeZonePopup"), "opened", true)
        compare(item("forgeZonePopup").zone, "exile")
        compare(item("forgeZonePopup").ownerSeat, 1)
        mouseClick(item("forgeCloseZonePopup"))
        tryCompare(item("forgeZonePopup"), "visible", false)
    }
    function test_zonePilesShowPublicTopAndStayOffPermanentLanes() {
        const state = snapshot()
        state.zones.push({zone:"exile", ownerSeat:1, count:3,
            cards:[card("known-exile", 1, "Plains", false)]})
        state.zones.push({zone:"graveyard", ownerSeat:0, count:2,
            cards:[card("known-yard", 0, "Grizzly Bears", true)]})
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        const exile = item("forgeOpponentZone-exile")
        const yard = item("forgeZone-graveyard")
        compare(exile.count, 3)
        verify(exile.showsPublicFace)
        compare(yard.count, 2)
        verify(yard.showsPublicFace)
        verify(item("forgeZone-library").count === 50)
        verify(!item("forgeZone-library").showsPublicFace)
        const ownLand = item("forgeCard-land")
        const exilePoint = exile.mapToItem(table, 0, 0)
        const yardPoint = yard.mapToItem(table, 0, 0)
        const landPoint = ownLand.mapToItem(table, 0, 0)
        const hand = item("forgeHand")
        verify(yard.width >= 96 * table.presentation.unit)
        verify(yard.height >= 110 * table.presentation.unit)
        const yardFace = findChild(yard, "forgeZonePileFace")
        const yardArt = findChild(yard, "forgeZonePileArt")
        verify(yardFace !== null && yardArt !== null)
        compare(yardArt.fillMode, Image.PreserveAspectFit)
        verify(Math.abs(yardFace.width / yardFace.height - 63 / 88) < 0.03)
        verify(yardFace.height <= yard.height)
        verify(yardFace.width <= yard.width)
        verify(yardPoint.y >= hand.y - 4 * table.presentation.unit)
        verify(yardPoint.y + yard.height <= table.height + 1)
        verify(landPoint.y + ownLand.height <= yardPoint.y + 8 * table.presentation.unit)
        verify(exilePoint.y < table.height * 0.22)
        verify(exilePoint.x < table.width * 0.28)
    }
    function test_logPanelKeepsZonesAndDecisionsAccessible_data() {
        return test_decisionsStayBesideBoardAndInsideWindow_data()
    }
    function test_logPanelKeepsZonesAndDecisionsAccessible(data) {
        window.width = data.w; window.height = data.h; Theme.uiScale = data.scale || 1
        const state = snapshot()
        state.stack = [{id:"bolt", controllerSeat:0, identity:{name:"Lightning Bolt"}}]
        verify(testRulesPrompt.applySnapshot(state))
        combat("chooseAttackers")
        const dock = item("rulesDecisionDock"), originalX = dock.x
        openSettings()
        mouseClick(item("rulesToggleGameLogButton"))
        closeSettings()
        const log = item("gameLogRail")
        tryVerify(() => log.visible && log.floating)
        compare(dock.x, originalX)
        verify(!item("rulesInspectionHost").visible)
        verify(item("forgeStack").visible)
        const settings = item("forgeGameMenu")
        const handle = item("gameLogDragHandle")
        const close = item("closeGameLogButton")
        verify(log.y >= settings.y + settings.height)
        verify(log.height >= table.height * 0.7)
        verify(log.x + log.width <= table.width && log.y + log.height <= table.height)
        verify(handle.mapToItem(log, 0, 0).y < Theme.size(20))
        verify(close.mapToItem(log, 0, 0).y < Theme.size(24))
        verify(item("gameLog").mapToItem(log, 0, 0).y
               >= handle.mapToItem(log, 0, 0).y + 20)
        for (const name of ["forgeOwnLands", "forgeOpponentLands", "forgeOwnOther", "forgeOpponentOther",
                           "forgeOwnPlaneswalkers", "forgeOpponentPlaneswalkers",
                           "forgeOwnCreatures", "forgeOpponentCreatures"]) {
            const lane = item(name)
            if (!lane.stackCount) continue
            verify(lane.width > 0)
            verifyBattlefieldClearOfOverlay([name],
                dock.mapToItem(table.presentation, 0, 0, dock.width, dock.height), "the decision dock")
            verify(lane.x + lane.width <= table.width)
        }
        verify(item("forgeHand").x + item("forgeHand").width <= dock.x)
        table.gameLogRail.chatInput.text = "Preserved draft"
        mouseClick(item("rulesConfirmCombat-attackers"))
        compare(transport.responses.length, 1)
        compare(table.gameLogRail.chatInput.text, "Preserved draft")
        const startX = log.x, startY = log.y, startW = log.width
        log.storedNX = 0.18
        log.storedNW = 0.32
        tryVerify(() => log.x < startX - 40 && log.width !== startW)
        mouseClick(handle, 8, 8, Qt.RightButton)
        tryCompare(log, "storedNX", -1)
        verify(!table.inspector.pinned)
        tryVerify(() => Math.abs(log.x - startX) < 3
                         && Math.abs(log.y - startY) < 3
                         && Math.abs(log.width - startW) < 3)
        openSettings()
        mouseClick(item("rulesToggleGameLogButton"))
        closeSettings()
        tryCompare(log, "visible", false)
        compare(dock.x, originalX)
        table.gameLogRail.chatInput.text = ""
    }
    function test_stackRelationshipsLocateExactCopiesAndFollowClipping() {
        const state = snapshot(1, 70)
        state.stack = [{id:"bolt", controllerSeat:1, identity:{name:"Lightning Bolt"}, text:"Deal 3 damage", targets:[
            {kind:"card", objectId:"own-69", label:"Grizzly Bears"}, {kind:"player", seat:1, label:"Bob"}]}]
        verify(testRulesPrompt.applySnapshot(state))
        const lane = item("forgeOwnCreatures"), stack = item("forgeStack"), arrow = item("forgeStackTargetArrow")
        tryVerify(() => lane.visibleCards.length === 70 && lane.stackCount === 1 && stack.currentTarget !== null)
        mouseClick(item("forgeStackTarget-bolt-0"))
        tryVerify(() => item("forgeCard-own-69").located && arrow.visible && arrow.endPoint.x !== 0)
        verify(!item("forgeCard-own-0").located)
        verify(item("forgeCardStackCount-own-69").visible)
        compare(item("forgeCardStackCountLabel-own-69").text, "×70")
        mouseClick(item("forgeStackTarget-bolt-1"))
        tryCompare(item("rulesPlayerTarget1"), "selected", true)
        tryCompare(arrow, "visible", true)
        compare(transport.responses.length, 0)
        transport.inRoom = false
        tryCompare(arrow, "visible", false)
        verify(!item("rulesPlayerTarget1").selected)
    }
    function test_stackTargetUsesExactSpellAndClearsOnNewGame() {
        const state = snapshot()
        state.stack = [{id:"counter", controllerSeat:1, identity:{name:"Counterspell"}, targets:[{kind:"spell", objectId:"bolt-2", label:"Lightning Bolt"}]},
            {id:"bolt-1", controllerSeat:0, identity:{name:"Lightning Bolt"}},
            {id:"bolt-2", controllerSeat:0, identity:{name:"Lightning Bolt"}}]
        verify(testRulesPrompt.applySnapshot(state))
        const stack = item("forgeStack"), arrow = item("forgeStackTargetArrow")
        tryVerify(() => stack.currentTarget !== null)
        tryVerify(() => item("forgeStackEntry-counter").y < item("forgeStackEntry-bolt-1").y)
        mouseClick(item("forgeStackTarget-counter-0"))
        tryVerify(() => stack.scrollArea.contentY > 0)
        verify(item("forgeStackCard-bolt-2").located)
        verify(!item("forgeStackCard-bolt-1").located)
        tryCompare(arrow, "visible", false)
        const next = snapshot(); next.gameId = "next-game"
        verify(testRulesPrompt.applySnapshot(next))
        tryCompare(stack, "currentTarget", null)
        compare(arrow.visible, false)
        compare(transport.responses.length, 0)
    }
    function test_stackTargetControlsScrollAndKeepHiddenLabelsPrivate() {
        const state = snapshot()
        state.stack = [{id:"many-targets", controllerSeat:0, identity:{name:"Spell"}, targets:[]}]
        for (let i = 0; i < 16; ++i) state.stack[0].targets.push({kind:"card", objectId:"own-0", label:i === 15 ? "" : "Grizzly Bears"})
        verify(testRulesPrompt.applySnapshot(state))
        const last = item("forgeStackTarget-many-targets-15"), stack = item("forgeStack")
        last.forceActiveFocus()
        tryVerify(() => stack.scrollArea.contentY > 0)
        const point = last.mapToItem(stack.scrollArea, 0, 0)
        verify(point.y >= 0 && point.y + last.height <= stack.scrollArea.height + 1,
            "Target y=" + point.y + " height=" + last.height + " viewport=" + stack.scrollArea.height)
        compare(last.text, "Target: Hidden card")
        keyClick(Qt.Key_Space)
        tryCompare(stack, "activeTargetIndex", 15)
        compare(transport.responses.length, 0)
    }
    function test_persistentChoicesAreVisibleAndCopiesStaySeparate_data() {
        return [{tag:"desktop", w:1920, h:1011}, {tag:"laptop", w:1280, h:800},
            {tag:"chinese", w:1600, h:1000, chinese:true}]
    }
    function test_persistentChoicesAreVisibleAndCopiesStaySeparate(data) {
        function label(id) { return findChild(item("forgeCard-" + id), "forgeCardState-" + id) }
        function inspectSummary(id) {
            waitForRendering(table)
            mouseMove(item("forgeCard-" + id), 20, 30)
            tryCompare(table.inspector, "previewCardId", id)
            const preview = item("rulesCardHoverPreview")
            waitForRendering(table)
            tryCompare(preview, "visible", true, 5000, id)
            if (preview.inspectionRequired) {
                const button = item("rulesCardHoverInspect")
                mouseMove(button)
                wait(400)
                verify(button.visible)
                mouseClick(button)
            } else {
                const gallery = item("rulesCardHoverPreviewGallery")
                compare(preview.height, gallery.height, "Hover shows only the complete card faces")
                compare(findChild(preview, "rulesCardHoverLinkedCards"), null)
                mouseClick(item("forgeCard-" + id), 20, 30, Qt.RightButton)
            }
            tryCompare(table.inspector, "pinnedCardId", id)
            tryCompare(table.inspector, "visible", true)
            compare(table.inspector.cardId, id)
            const summary = item("rulesCardInspectorState").text
            mouseClick(item("clearRulesCardInspectorButton"))
            tryCompare(table.inspector, "pinnedCardId", "")
            mouseMove(table, 30, 70)
            table.forceActiveFocus()
            return summary
        }
        window.width = data.w; window.height = data.h
        if (data.chinese) {
            testTranslations.setLanguage("zh"); catalog.language = "zh"
            catalog.names = ({"Lightning Bolt":"闪电击", "Counterspell":"反击咒语",
                "Ulamog, the Ceaseless Hunger":"无尽轮回乌拉莫"})
        }
        const bolt = data.chinese ? "闪电击" : "Lightning Bolt"
        const counter = data.chinese ? "反击咒语" : "Counterspell"
        const ulamog = data.chinese ? "无尽轮回乌拉莫" : "Ulamog, the Ceaseless Hunger"
        const state = snapshot()
        const needleA = card("needle-a", 0, "Pithing Needle", false)
        const needleB = card("needle-b", 0, "Pithing Needle", false)
        needleA.annotations = [{kind:"namedCard", value:"Lightning Bolt"}]
        needleB.annotations = [{kind:"namedCard", value:"Counterspell"}]
        const mazeA = card("maze-a", 0, "Ugin's Labyrinth", false)
        const mazeB = card("maze-b", 0, "Ugin's Labyrinth", false)
        mazeA.exiledCardCount = 1; mazeA.exiledCardIds = ["ulamog"]
        mazeA.counters = [{name:"LOYALTY", value:7}, {name:"P1P1", value:2}]
        mazeB.exiledCardCount = 1; mazeB.exiledCardIds = ["hidden-exile"]
        state.zones[4].cards = [needleA, needleB, mazeA, mazeB]; state.zones[4].count = 4
        state.zones.push({zone:"exile", ownerSeat:0, count:2, cards:[
            card("ulamog", 0, "Ulamog, the Ceaseless Hunger", true),
            {id:"hidden-exile", visible:false, faceDown:true, identity:{name:"SECRET"}}]})
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(item("forgeOwnOther"), "stackCount", 2)
        tryCompare(item("forgeOwnLands"), "stackCount", 2)
        for (const id of ["needle-a", "needle-b", "maze-a", "maze-b"]) {
            const tile = item("forgeCard-" + id), stateLabel = label(id)
            verify(tile.card.stackFront)
            compare(tile.card.stackSize, 1)
            verify(stateLabel.visible && stateLabel.height >= stateLabel.font.pixelSize)
            const title = findChild(tile, "forgeCardName-" + id)
            verify(stateLabel.y >= title.y + title.height)
        }
        verify(label("needle-a").text.includes(bolt))
        verify(label("needle-b").text.includes(counter))
        verify(label("maze-a").text.includes(ulamog))
        verify(label("maze-a").text.includes("+1/+1 × 2"))
        verify(!label("maze-a").text.includes(data.chinese ? "忠诚" : "Loyalty"))
        const loyalty = findChild(item("forgeCard-maze-a"), "forgeCardLoyalty-maze-a")
        verify(loyalty.visible)
        compare(findChild(loyalty, "forgeCardLoyaltyValue-maze-a").text, "7")
        verify(label("maze-a").y + label("maze-a").height <= loyalty.y + 1)
        verify(label("maze-b").text.includes(data.chinese ? "隐藏牌" : "hidden card"))
        verify(!label("maze-b").text.includes("SECRET"))
        const mazeSummary = inspectSummary("maze-a")
        verify(mazeSummary.includes(ulamog))
        verify(!mazeSummary.includes("SECRET"))
        const firstNeedleSummary = inspectSummary("needle-a")
        verify(firstNeedleSummary.includes(bolt))
        verify(!firstNeedleSummary.includes(counter))
        const secondNeedleSummary = inspectSummary("needle-b")
        verify(secondNeedleSummary.includes(counter))
        verify(!secondNeedleSummary.includes(bolt))
        mouseClick(item("forgeCard-needle-a"), 20, 30, Qt.RightButton)
        tryCompare(table.inspector, "pinnedCardId", "needle-a")
        verify(item("rulesCardInspectorState").text.includes(bolt))
        needleA.annotations = [{kind:"namedCard", value:"Counterspell"}]
        mazeA.exiledCardCount = 0; mazeA.exiledCardIds = []; mazeA.counters = []
        state.zones[0].cards.push(state.zones[6].cards.shift()); state.zones[0].count++
        state.zones[6].count--
        verify(testRulesPrompt.applySnapshot(state))
        tryVerify(() => label("needle-a").text.includes(counter))
        verify(!item("rulesCardInspectorState").text.includes(bolt))
        compare(label("maze-a").text, "")
        compare(transport.responses.length, 0)
    }
    function test_chosenCreaturesRemainVisibleWithoutRevealingHiddenObjects_data() {
        return [{tag:"desktop", w:1920, h:1011}, {tag:"laptop", w:1280, h:800},
            {tag:"chinese", w:1600, h:1000, chinese:true}]
    }
    function test_chosenCreaturesRemainVisibleWithoutRevealingHiddenObjects(data) {
        window.width = data.w; window.height = data.h
        if (data.chinese) {
            testTranslations.setLanguage("zh"); catalog.language = "zh"
            catalog.names = ({"Grizzly Bears":"灰棕熊"})
        }
        const expected = data.chinese ? "已选择：灰棕熊" : "Chosen: Grizzly Bears"
        const state = snapshot()
        const first = card("guard-a", 0, "Dauntless Bodyguard", true)
        const second = card("guard-b", 0, "Dauntless Bodyguard", true)
        first.chosenCardIds = ["own-0", "secret", "missing", "own-0"]
        second.chosenCardIds = ["own-0"]
        state.zones[4].cards.push(first, second)
        state.zones[4].count += 2
        state.zones[1].cards = [{id:"secret", visible:false, identity:{name:"SECRET"}}]
        verify(testRulesPrompt.applySnapshot(state))
        const tile = item("forgeCard-guard-a"), other = item("forgeCard-guard-b")
        tryCompare(item("forgeOwnCreatures"), "stackCount", 3)
        waitForRendering(tile)
        tryCompare(tile, "persistentSummary", expected)
        compare(other.persistentSummary, expected)
        compare(tile.card.stackSize, 1)
        compare(other.card.stackSize, 1)
        mouseMove(tile, 20, 30)
        tryCompare(table.inspector, "previewCardId", "guard-a")
        compare(findChild(item("rulesCardHoverPreview"), "rulesCardHoverLinkedCards"), null)
        mouseClick(tile, 20, 30, Qt.RightButton)
        tryCompare(table.inspector, "pinnedCardId", "guard-a")
        verify(item("rulesCardInspectorState").text.includes(expected))

        first.chosenCardIds = []
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(tile, "persistentSummary", "")
        verify(!item("rulesCardInspectorState").text.includes(expected))
        compare(other.persistentSummary, expected)
        // Even a stale/malformed link cannot display an identity that is no
        // longer present in this viewer's snapshot.
        state.zones[4].cards[0].visible = false
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(other, "persistentSummary", "")
        state.zones[4].cards[0].visible = true
        second.faceDown = true
        verify(testRulesPrompt.applySnapshot(state))
        compare(testRulesPrompt.session.cardForInspection("guard-b").chosenCardIds.length, 0)
        compare(transport.responses.length, 0)
    }
    function test_dungeonAndClassProgressRemainInspectable() {
        const state = snapshot()
        const talent = card("talent", 0, "Artist's Talent", false)
        talent.annotations = [{kind:"classLevel", value:"2"}]
        const dungeon = card("dungeon", 0, "Lost Mine of Phandelver", false)
        dungeon.annotations = [{kind:"dungeonRoom", value:"Cave Entrance"}, {kind:"classLevel", value:"9"}]
        state.zones[4].cards.push(talent); state.zones[4].count++
        state.zones.push({zone:"command", ownerSeat:0, count:1, cards:[dungeon]})
        verify(testRulesPrompt.applySnapshot(state))
        tryVerify(() => findChild(table, "forgeZone-command") !== null)
        const tile = item("forgeCard-talent")
        compare(findChild(tile, "forgeCardState-talent").text, "Class level: 2")
        mouseClick(item("forgeZone-command"))
        tryCompare(item("forgeZonePopup"), "opened", true)
        tryCompare(item("forgeZoneCards"), "zone", "command")
        tryVerify(() => findChild(item("forgeZonePopup").contentItem, "forgeCard-dungeon") !== null)
        const dungeonTile = findChild(item("forgeZonePopup").contentItem, "forgeCard-dungeon")
        waitForRendering(dungeonTile)
        compare(findChild(dungeonTile, "forgeCardState-dungeon").text, "Room: Cave Entrance")
        verify(findChild(dungeonTile, "forgeCardState-dungeon").visible,
            "The current room must be visible on the full-face command-zone card")
        mouseClick(dungeonTile, 20, 30, Qt.RightButton)
        tryCompare(table.inspector, "pinnedCardId", "dungeon")
        compare(table.inspector.persistentSummary, "Room: Cave Entrance")
        dungeon.annotations = [{kind:"dungeonRoom", value:"Goblin Lair"}]
        verify(testRulesPrompt.applySnapshot(state))
        compare(table.inspector.persistentSummary, "Room: Goblin Lair")
        state.zones.pop()
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(table.inspector, "hasCard", false)
        tryCompare(item("forgeZoneCards"), "zone", "graveyard")
        compare(findChild(table, "forgeZone-command"), null)
    }

    function test_newPermanentFadesInWhenMotionIsOn() {
        Theme.motionEnabled = true
        const state = snapshot(1, 0)
        state.zones[4].cards.push(card("newcomer", 0, "Grizzly Bears", true))
        state.zones[4].count = state.zones[4].cards.length
        verify(testRulesPrompt.applySnapshot(state))
        let sawFade = false
        tryVerify(() => {
            const face = findChild(table, "forgeCard-newcomer")
            if (!face)
                return false
            if (face.arrivalOpacity < 1)
                sawFade = true
            return sawFade && face.arrivalOpacity === 1
        })
        Theme.motionEnabled = false
    }
    function test_hoverAvoidsPublicBoardContent() {
        window.width=1920; window.height=1011
        const state=snapshot(5,4,true)
        state.players[0].manaPool=[{name:"U",value:2}]
        verify(testRulesPrompt.applySnapshot(state))
        table.forceActiveFocus()
        mouseMove(table,30,70)
        waitForRendering(table)
        const source=item("forgeHandCard-hand-2")
        mouseMove(source,source.width/2,source.height/3)
        tryCompare(table.inspector,"previewCardId","hand-2")
        const preview=item("rulesCardHoverPreview")
        tryCompare(preview,"visible",true)
        compare(preview.inspectionRequired,false)
        for (const name of ["forgeCard-own-0","forgeCard-own-1","forgeCard-own-2",
            "forgeCard-own-3","forgeCard-land","forgeCard-opponent","forgePhaseTrack",
            "rulesPlayerTarget0","rulesPlayerTarget1","forgeManaPool-0",
            "forgeOpponentZoneStrip","forgeOwnZoneStrip","rulesDecisionDock"])
            verify(!rectsOverlap(preview,item(name)),"Preview obscures "+name)
        verify(preview.placement.faceWidth>=Theme.size(180))
    }
    function test_contextKeysInspectWithoutActivating_data() {
        const rows=[]
        for (const zone of ["battlefield","hand","attachment"])
            for (const key of ["menu","shift-f10"])
                rows.push({tag:zone+"-"+key,zone:zone,key:key})
        return rows
    }
    function test_crowdedInspectionHintKeepsExactIdentityAndExpires() {
        window.width=900; window.height=620; Theme.uiScale=1.5
        room.format="edh"; room.deckFormat="commander"; room.maxSeats=4
        previewFaces()
        const state=edhSnapshot([0,1,2,3],0,2)
        state.turn=8; state.step="declare_blockers"; state.activeSeat=0; state.prioritySeat=0
        for(const player of state.players) player.name="Preview Player "+(player.seat+1)
        for(const zone of state.zones) {
            if(zone.zone==="battlefield") {
                zone.cards[0].identity={name:"Delver of Secrets"}
                zone.cards[1].identity={name:"Isamaru, Hound of Konda"}
                for(let index=0;index<2;++index) {
                    zone.cards[index].attacking=true
                    zone.cards[index].attackingPlayer=(zone.ownerSeat+index+1)%4
                }
            } else if(zone.zone==="command") {zone.cards=[];zone.count=0}
            else if(zone.zone==="hand" && zone.ownerSeat===0)
                zone.cards=Array.from({length:7},(_,index)=>card("icon-hand-"+index,0,"Plains",false))
        }
        verify(testRulesPrompt.applySnapshot(state))
        table.priority.setFullControl(true)
        prompt("chooseAction",{options:[{responseId:"$pass",kind:"pass",label:"Pass"}]})
        table.forceActiveFocus()
        mouseMove(item("forgeGameMenu"))
        waitForRendering(table)
        const source=item("forgeCard-creature-0-0"), preview=item("rulesCardHoverPreview")
        const sourceBefore=source.mapToItem(table,0,0)
        mouseMove(source,source.width/2,source.height/2)
        tryCompare(table.inspector,"previewCardId","creature-0-0")
        waitForRendering(table)
        tryCompare(preview,"visible",true)
        verify(preview.inspectionRequired,"The crowded production fixture must expose an inspection control: "
            +JSON.stringify({inspectionRequired:preview.inspectionRequired, width:preview.width, height:preview.height,
                faceWidth:preview.placement.faceWidth, x:preview.x, y:preview.y}))
        compare(source.mapToItem(table,0,0),sourceBefore)
        const button=item("rulesCardHoverInspect")
        mouseMove(button)
        wait(450)
        verify(button.visible)
        compare(table.inspector.previewCardId,"creature-0-0")
        mouseClick(button)
        tryCompare(table.inspector,"pinnedCardId","creature-0-0")
        compare(item("rulesCardInspectorGallery").faceCount,2)
        compare(transport.responses.length,0)
        mouseClick(item("clearRulesCardInspectorButton"))
        tryCompare(source,"activeFocus",true)
        mouseMove(item("forgeGameMenu"))
        item("forgeGameMenu").forceActiveFocus()
        tryCompare(table.inspector,"previewCardId","")
        mouseMove(source,source.width/2,source.height/2)
        tryCompare(preview,"visible",true)
        mouseMove(item("forgeGameMenu"))
        tryCompare(table.inspector,"previewCardId","",1000)
        verify(!preview.visible)
        const hidden=state.zones.find(zone=>zone.zone==="battlefield" && zone.ownerSeat===0).cards[0]
        hidden.faceDown=true; hidden.identity={name:"SECRET"}
        catalog.faceRequests=[]
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        mouseMove(source,source.width/2,source.height/2)
        tryCompare(preview,"visible",true)
        verify(!table.inspector.hasIdentity)
        verify(!item("rulesCardHoverPreviewGallery").visible)
        mouseMove(button)
        wait(450)
        mouseClick(button)
        tryCompare(table.inspector,"pinnedCardId","creature-0-0")
        verify(!table.inspector.hasIdentity)
        verify(!item("rulesCardInspectorGallery").visible)
        verify(!item("rulesCardInspectorTitle").text.includes("SECRET"))
        verify(!catalog.faceRequests.includes("SECRET"))
        compare(transport.responses.length,0)
    }
    function test_contextKeysInspectWithoutActivating(data) {
        const state=snapshot(1,2,true)
        if (data.zone==="attachment") state.zones[4].cards[1].attachedTo="own-0"
        verify(testRulesPrompt.applySnapshot(state))
        const id=data.zone==="hand"?"hand-0":data.zone==="attachment"?"own-1":"own-0"
        action(data.zone==="hand"?"playLand":"activateAbility",id)
        mouseMove(table,30,70)
        const source=item(data.zone==="hand"?"forgeHandSurface-hand-0":"forgeCard-"+id)
        source.forceActiveFocus()
        tryCompare(source,"activeFocus",true)
        keyClick(data.key==="menu"?Qt.Key_Menu:Qt.Key_F10,
            data.key==="menu"?Qt.NoModifier:Qt.ShiftModifier)
        tryCompare(table.inspector,"pinnedCardId",id)
        tryCompare(table.inspector,"previewCardId","")
        verify(item("rulesInspectionHost").visible)
        compare(transport.responses.length,0)
    }
    function test_inspectionBoundsIncludeUnclippedFanAndMergePiles() {
        verify(testRulesPrompt.applySnapshot(snapshot(1,40,false)))
        const lane=item("forgeOwnCreatures"), board=item("forgeDuelTable")
        tryCompare(lane,"stackCount",1)
        compare(lane.inspectionRects(board).length,1)
        lane.openFan(0)
        tryCompare(lane.scrollArea,"clip",true)
        // The isolated fan remains visible above the lane while unrelated
        // rows keep their viewport clipping and the scroll position changes.
        lane.scrollArea.contentY=lane.slotY(0)+20*lane.unit
        waitForRendering(lane)
        const rects=lane.inspectionRects(board)
        compare(rects.length,40)
        const viewport=lane.scrollArea.mapToItem(board,0,0,lane.scrollArea.width,lane.scrollArea.height)
        verify(rects.some(rect=>rect.y<viewport.y-5))
        lane.scrollArea.contentY=0
    }
    function test_hoverPreviewWaitsThenFades() {
        Theme.motionEnabled = true
        mouseMove(table, 30, 70)
        const source = item("forgeHandCard-hand-0")
        mouseMove(source, Math.round(source.width * 0.75), Math.round(source.height * 0.4))
        tryCompare(table.inspector, "previewCardId", "hand-0")
        const preview = item("rulesCardHoverPreview")
        tryCompare(preview, "visible", true)
        verify(preview.opacity < 1)
        tryCompare(preview, "opacity", 1)
        mouseMove(table, 30, 70)
        tryCompare(preview, "visible", false)
        Theme.motionEnabled = false
    }
    function keyboardPreviewLane(opponent) {
        const state = snapshot(1, 70, true)
        if (opponent) {
            const own = state.zones.find(zone => zone.zone === "battlefield" && zone.ownerSeat === 0)
            const other = state.zones.find(zone => zone.zone === "battlefield" && zone.ownerSeat === 1)
            other.cards = own.cards.filter(card => card.id !== "land").map(card =>
                Object.assign({}, card, {ownerSeat:1, controllerSeat:1}))
            other.count = other.cards.length
            own.cards = own.cards.filter(card => card.id === "land"); own.count = 1
        }
        verify(testRulesPrompt.applySnapshot(state))
        const lane = item(opponent ? "forgeOpponentCreatures" : "forgeOwnCreatures")
        tryCompare(lane, "stackCount", 70)
        verify(lane.scrollArea.contentHeight > lane.scrollArea.height)
        mouseMove(table, 30, 70)
        const source = item("forgeCard-own-0")
        source.forceActiveFocus()
        tryCompare(source, "activeFocus", true)
        tryCompare(table.inspector, "previewCardId", "own-0")
        tryCompare(item("rulesCardHoverPreview"), "visible", true)
        return lane
    }
    function test_keyboardPreviewFollowsLaneWheel() {
        const lane = keyboardPreviewLane(true), viewport = lane.scrollArea
        const source = item("forgeCard-own-0"), preview = item("rulesCardHoverPreview")
        const sourceBefore = source.mapToItem(preview.parent, 0, 0)
        const scrollBefore = viewport.contentY
        // Wheel the unused edge of the lane so pointer hover cannot replace
        // the keyboard-selected card's inspection.
        mouseWheel(viewport, viewport.width - 2, viewport.height / 2, 0, -60)
        tryVerify(() => viewport.contentY > scrollBefore + 5)
        tryCompare(viewport, "moving", false)
        verify(source.activeFocus)
        compare(table.inspector.previewCardId, "own-0")
        const sourceAfter = source.mapToItem(preview.parent, 0, 0)
        verify(sourceAfter.y < sourceBefore.y - 5)
        const inLane = source.mapToItem(viewport, 0, 0)
        verify(inLane.y < 0 && inLane.y + source.height > 0, "Part of the card remains visible")
        verify(preview.visible)
        tryVerify(() => Math.abs(preview.sourceGeometry.origin.y-sourceAfter.y)<0.5,
                  1000, "Focused card geometry follows its lane even when the same free area stays best")
        verify(!rectsOverlap(preview,source))
        verify(preview.x >= 0 && preview.y >= 0
            && preview.x + preview.width <= preview.parent.width
            && preview.y + preview.height <= preview.parent.height)
    }
    function test_keyboardPreviewHidesOutsideLaneAndReturns() {
        const lane = keyboardPreviewLane(), viewport = lane.scrollArea
        const source = item("forgeCard-own-0"), preview = item("rulesCardHoverPreview")
        mouseWheel(viewport, viewport.width - 2, viewport.height / 2, 0, -1200)
        tryVerify(() => source.mapToItem(viewport, 0, source.height).y <= 0)
        verify(source.activeFocus)
        tryCompare(preview, "visible", false)
        mouseWheel(viewport, viewport.width - 2, viewport.height / 2, 0, 1200)
        tryCompare(viewport, "contentY", 0)
        verify(source.activeFocus)
        tryCompare(preview, "visible", true)
        compare(table.inspector.previewCardId, "own-0")
        keyClick(Qt.Key_Tab)
        tryCompare(item("forgeCard-own-1"), "activeFocus", true)
        tryCompare(table.inspector, "previewCardId", "own-1")
        tryCompare(preview, "visible", true)
        item("forgeGameMenu").forceActiveFocus()
        tryCompare(item("forgeCard-own-1"), "activeFocus", false)
        tryCompare(preview, "visible", false)
    }
    function test_keyboardPreviewChangesFocusWhileOldCardIsClipped() {
        const lane = keyboardPreviewLane(), viewport = lane.scrollArea
        const source = item("forgeCard-own-0"), preview = item("rulesCardHoverPreview")
        mouseWheel(viewport, viewport.width - 2, viewport.height / 2, 0, -1200)
        tryVerify(() => source.mapToItem(viewport, 0, source.height).y <= 0)
        tryCompare(preview, "visible", false)
        keyClick(Qt.Key_Tab)
        const next = item("forgeCard-own-1")
        tryCompare(next, "activeFocus", true)
        tryCompare(table.inspector, "previewCardId", "own-1")
        tryCompare(preview, "visible", true)
        const point = next.mapToItem(viewport, 0, 0)
        verify(point.y >= 0 && point.y + next.height <= viewport.height)
    }
    function test_keyboardPilePreviewFollowsFanAndCollapseGlides_data() {
        return [{tag:"expanded", collapse:false}, {tag:"collapsed", collapse:true}]
    }
    function test_keyboardPilePreviewFollowsFanAndCollapseGlides(data) {
        window.width = 1920; window.height = 1011
        landBoard(["ready", "spent-a", "spent-b"], ["spent-a", "spent-b"])
        table.priority.setFullControl(true)
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        const lane = item("forgeOwnLands"), source = item("forgeCard-spent-b")
        const slot = source.parent, preview = item("rulesCardHoverPreview")
        tryCompare(lane, "stackCount", 2)
        verify(source.card.stackFront && source.card.stackSize === 2 && source.card.tapped)
        // Let resize suppression expire, then exercise the real CardSlot
        // Translate animation without snapping it to its destination.
        wait(300)
        Theme.motionEnabled = true
        mouseMove(item("forgeGameMenu"))
        source.forceActiveFocus()
        tryCompare(source, "activeFocus", true)
        tryCompare(table.inspector, "previewCardId", "spent-b")
        tryCompare(preview, "visible", true)
        tryCompare(preview, "opacity", 1)
        const closed = source.mapToItem(preview.parent, 0, 0, source.width, source.height)
        function distanceToSource(bounds) {
            return Math.max(0, preview.x - bounds.x - bounds.width, bounds.x - preview.x - preview.width)
                + Math.max(0, preview.y - bounds.y - bounds.height, bounds.y - preview.y - preview.height)
        }
        verify(preview.placement.faceWidth >= Theme.size(180), "The closed pile has a readable art pocket")
        const closedDistance = distanceToSource(closed)
        verify(closedDistance <= Theme.size(60), "The initial readable pocket is near the pile")
        keyClick(Qt.Key_Return)
        compare(lane.fannedStack, source.card.stackIndex)
        verify(Math.abs(slot.visualDx) + Math.abs(slot.visualDy) > 1,
            "Opening must exercise a painted glide, not an instantaneous layout")
        tryCompare(slot, "visualDx", 0)
        tryCompare(slot, "visualDy", 0)
        const expanded = source.mapToItem(preview.parent, 0, 0, source.width, source.height)
        verify(Math.abs(expanded.x - closed.x) > source.width / 2, "The focused member actually moves in the fan")
        if (data.collapse) {
            keyClick(Qt.Key_Escape)
            compare(lane.fannedStack, -1)
            verify(Math.abs(slot.visualDx) + Math.abs(slot.visualDy) > 1,
                "Closing must also exercise the production glide")
            tryCompare(slot, "visualDx", 0)
            tryCompare(slot, "visualDy", 0)
        }
        verify(source.activeFocus)
        compare(table.inspector.previewCardId, "spent-b")
        const origin = source.mapToItem(preview.parent, 0, 0)
        const bounds = source.mapToItem(preview.parent, 0, 0, source.width, source.height)
        tryVerify(() => Math.abs(preview.sourceGeometry.origin.x - origin.x) < 0.5
            && Math.abs(preview.sourceGeometry.origin.y - origin.y) < 0.5
            && Math.abs(preview.sourceGeometry.bounds.x - bounds.x) < 0.5
            && Math.abs(preview.sourceGeometry.bounds.y - bounds.y) < 0.5
            && Math.abs(preview.sourceGeometry.bounds.width - bounds.width) < 0.5
            && Math.abs(preview.sourceGeometry.bounds.height - bounds.height) < 0.5,
            1000, "Preview geometry must match the settled painted source after " + data.tag
                + "; painted=" + JSON.stringify(bounds) + "; cached=" + JSON.stringify(preview.sourceGeometry.bounds))
        if (data.collapse) {
            verify(Math.abs(bounds.x - closed.x) < 0.5 && Math.abs(bounds.y - closed.y) < 0.5)
            tryVerify(() => preview.placement.faceWidth >= Theme.size(180)
                && distanceToSource(bounds) <= closedDistance + Theme.size(1), 1000,
                "Collapsing restores the same nearby readable preview pocket")
        }
        compare(transport.responses.length, 0, "Inspecting a pile must never answer the Forge prompt")
    }
    function test_decisionDockExpansionKeepsBothAnswersVisible_data() {
        return [{tag:"desktop", width:1920, height:1011, scale:1},
            {tag:"scaled", width:1920, height:1011, scale:1.5},
            {tag:"compact", width:900, height:620, scale:1}]
    }
    function test_decisionDockExpansionKeepsBothAnswersVisible(data) {
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        wait(300) // Leave the initial window-resize suppression interval.
        Theme.motionEnabled = true
        prompt("chooseBoolean", {title:"Confirm decision",
            detail:"Isamaru, Hound of Konda: If a commander is in a graveyard or in exile and that card was put into that zone since the last time state-based actions were checked, its owner may put it into the command zone.",
            minChoiceTotal:1, maxChoiceTotal:1,
            choices:[{responseId:"choice:0", label:"No", weight:1, canRepeat:false},
                {responseId:"choice:1", label:"Yes", weight:1, canRepeat:false}]})
        waitForRendering(table)
        const dock = item("rulesDecisionDock"), scroll = item("rulesPromptScroll")
        const viewport = scroll.mapToItem(table, 0, 0)
        for (const id of ["choice:0", "choice:1"]) {
            const button = item("rulesScalarChoice-" + id), point = button.mapToItem(table, 0, 0)
            verify(button.enabled)
            verify(point.y >= viewport.y && point.y + button.height <= viewport.y + scroll.height + 1,
                   "An enabled answer must be fully visible on expansion, without waiting for the height animation")
        }
        compare(dock.height, dock.targetHeight)
    }
    function test_decisionDockContractionEasesWhenMotionIsOn() {
        wait(300)
        Theme.motionEnabled = true
        verify(testRulesPrompt.applySnapshot(snapshot()))
        const dock = item("rulesDecisionDock")
        prompt("chooseFromSelection", {title:"Choose a mode", detail:"A taller choice",
            minChoiceTotal:1, maxChoiceTotal:1,
            choices:[0, 1, 2, 3, 4, 5].map(i => ({responseId:"choice:" + i, label:"Mode " + i,
                weight:1, canRepeat:false}))})
        tryVerify(() => Math.abs(dock.height - dock.targetHeight) < 1)
        const before = dock.height
        action("playLand", "hand-0")
        const cap = table.presentation.boardDecision && table.presentation.reservesDock
            ? table.presentation.boardDecisionHeight : table.height - 24 * table.presentation.unit
        const target = Math.min(dock.implicitHeight, cap)
        verify(before - target > 8,
               "expected the dock to shrink, before " + before + " target " + target)
        verify(Math.abs(dock.height - before) + 1 < Math.abs(target - before),
               "Dock height eases from " + before + " toward " + target + ", now " + dock.height)
        tryVerify(() => Math.abs(dock.height - Math.min(dock.implicitHeight, cap)) < 1)
        Theme.motionEnabled = false
    }
    function test_hoverPreviewClosesWithoutMovingTheBoard() {
        action("playLand", "hand-0")
        const lane = item("forgeOwnCreatures"), x = lane.x, width = lane.width
        mouseMove(table, 30, 70)
        tryCompare(table.inspector, "hasCard", false)
        const source = item("forgeHandCard-hand-0")
        mouseMove(source, Math.round(source.width * 0.75), Math.round(source.height * 0.4))
        tryCompare(table.inspector, "previewCardId", "hand-0")
        const preview = item("rulesCardHoverPreview")
        tryCompare(preview, "visible", true)
        const origin = source.mapToItem(table, 0, 0)
        const previewPoint = preview.mapToItem(table, 0, 0)
        verify(previewPoint.x >= origin.x + source.width || previewPoint.x + preview.width <= origin.x
               || previewPoint.y + preview.height <= origin.y)
        verify(preview.y >= 0 && preview.y + preview.height <= table.height)
        compare(findChild(preview, "rulesCardHoverLinkedCards"), null)
        compare(preview.height, preview.width * 88 / 63)
        verify(!item("rulesInspectionHost").visible)
        mouseMove(table, 30, 70)
        tryCompare(table.inspector, "hasCard", false)
        compare(item("rulesInspectionHost").visible, false)
        compare(lane.x, x); compare(lane.width, width)
    }
    function test_multifaceHoverBothFacesAreReachableAndReadOnly_data() {
        return [{tag:"duel", seats:2}, {tag:"multiplayer", seats:4}]
    }
    function test_multifaceHoverClosesOnModalOrAuthorityLoss_data() {
        return ["zone", "disconnect", "sideboard"].map(change => ({tag:change, change:change}))
    }
    function test_multifaceHoverClosesOnModalOrAuthorityLoss(data) {
        previewFaces()
        const state = snapshot()
        state.zones[4].cards[0].identity = {name:"Delver of Secrets", setCode:"ISD", collectorNumber:"51"}
        verify(testRulesPrompt.applySnapshot(state))
        mouseMove(item("forgeCard-own-0"), 20, 20)
        const preview = item("rulesCardHoverPreview")
        tryCompare(preview, "visible", true)
        if (data.change === "zone") table.presentation.openZone(0, "graveyard")
        else if (data.change === "disconnect") transport.inRoom = false
        else match.sideboarding = true
        compare(preview.visible, false)
        tryCompare(table.inspector, "previewCardId", "")
        mouseMove(table, 30, 70)
        if (data.change === "zone") item("forgeZonePopup").close()
        else if (data.change === "disconnect") transport.inRoom = true
        else match.sideboarding = false
        verify(!preview.visible, "Restoring authority must not restore the old preview")
    }
    function test_multifaceHoverBothFacesAreReachableAndReadOnly(data) {
        previewFaces()
        const state = data.seats === 2 ? snapshot() : edhSnapshot([0,1,2,3], 0)
        if (data.seats === 4) { room.format = "edh"; room.maxSeats = 4 }
        const permanent = state.zones.find(zone => zone.zone === "battlefield" && zone.ownerSeat === 0).cards[0]
        permanent.identity = {name:"Delver of Secrets", setCode:"ISD", collectorNumber:"51"}
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(table.presentation, "multiplayer", data.seats > 2)
        action("activateAbility", permanent.id)
        const authority = JSON.stringify(table.rulesSession.cardForInspection(permanent.id))
        const source = item("forgeCard-" + permanent.id)
        mouseMove(source, source.width / 2, source.height / 2)
        tryCompare(table.inspector, "previewCardId", permanent.id)
        const preview = item("rulesCardHoverPreview")
        waitForRendering(table)
        tryCompare(preview, "visible", true)
        if (preview.inspectionRequired) {
            const button=item("rulesCardHoverInspect")
            mouseMove(button)
            wait(400)
            verify(button.visible)
            mouseClick(button)
            tryCompare(table.inspector,"pinnedCardId",permanent.id)
            verifyFaceGallery(table.inspector,"rulesCardInspectorArt")
            mouseClick(item("clearRulesCardInspectorButton"))
            tryCompare(source, "activeFocus", true)
            // End keyboard inspection before checking pointer departure below.
            item("forgeGameMenu").forceActiveFocus()
        } else {
            verifyFaceGallery(preview, "rulesCardHoverPreviewArt")
            mouseMove(item("rulesCardHoverPreviewArt-1"))
            wait(400)
            verify(preview.visible)
            verify(item("rulesCardHoverPreviewArt").width >= Theme.size(180))
        }
        compare(JSON.stringify(table.rulesSession.cardForInspection(permanent.id)), authority)
        compare(transport.responses.length, 0)
        mouseMove(table, 30, 70)
        tryCompare(preview, "visible", false, 1000)
        mouseClick(source)
        compare(transport.responses, [{id:table.rulesSession.promptId, response:"opaque-play"}])
    }
    function test_multifaceHoverBothArtBodiesPassInput() {
        previewFaces()
        const state = snapshot()
        state.zones[4].cards[0].identity = {name:"Delver of Secrets", setCode:"ISD", collectorNumber:"51"}
        verify(testRulesPrompt.applySnapshot(state))
        action("activateAbility", "own-0")
        const source = item("forgeCard-own-0")
        mouseMove(source, source.width / 2, source.height / 2)
        tryCompare(table.inspector, "previewCardId", "own-0")
        const preview = item("rulesCardHoverPreview")
        verifyFaceGallery(preview, "rulesCardHoverPreviewArt")
        const target = createTemporaryObject(previewInputTargetComponent, preview.parent,
            {x:preview.x, y:preview.y, width:preview.width, height:preview.height, z:preview.z - 1})
        verify(target !== null)
        const back = item("rulesCardHoverPreviewArt-1")
        mouseMove(back)
        wait(400)
        verify(preview.visible)
        const front = item("rulesCardHoverPreviewArt")
        mouseClick(front, front.width / 2, front.height / 2, Qt.RightButton)
        mouseClick(back, back.width / 2, back.height / 2, Qt.RightButton)
        compare(target.clicks, 2)
        compare(transport.responses.length, 0)
        compare(table.inspector.card.name, "Delver of Secrets")
        table.inspector.hidePreview()
        verify(!preview.visible)
    }
    function test_multifaceHandHoverShowsBothFacesWithoutPlayingOrSelecting() {
        previewFaces()
        const state = snapshot()
        state.zones[0].cards[0].identity = {name:"Delver of Secrets", setCode:"ISD", collectorNumber:"51"}
        verify(testRulesPrompt.applySnapshot(state))
        action("cast", "hand-0")
        const slot = item("forgeHandCard-hand-0")
        const face = item("forgeHandSurface-hand-0")
        tryCompare(face, "actionable", true)
        const authority = JSON.stringify(table.rulesSession.cardForInspection("hand-0"))
        const revision = table.rulesSession.snapshotRevision
        const promptId = table.rulesSession.promptId
        mouseMove(table, 30, 70)
        mouseMove(slot, slot.width / 2, slot.height / 2)
        tryCompare(table.inspector, "previewCardId", "hand-0")
        const preview = item("rulesCardHoverPreview")
        verifyFaceGallery(preview, "rulesCardHoverPreviewArt")
        mouseMove(item("rulesCardHoverPreviewArt-1"))
        wait(400)
        verify(preview.visible)
        compare(JSON.stringify(table.rulesSession.cardForInspection("hand-0")), authority)
        compare(table.rulesSession.snapshotRevision, revision)
        compare(table.rulesSession.promptId, promptId)
        compare(slot.name, "Delver of Secrets")
        verify(!slot.faceDown)
        compare(table.inspector.pinnedCardId, "")
        compare(transport.responses.length, 0)
        verify(!transport.rulesResponsePending)
        compare(table.interaction.selectedCount, 0)
        compare(table.interaction.nativeSelectedCount, 0)
        verify(!face.selected)
        compare(slot.ghost, null)
        mouseMove(table, 30, 70)
        tryCompare(preview, "visible", false, 1000)
        compare(table.inspector.previewCardId, "")
        compare(JSON.stringify(table.rulesSession.cardForInspection("hand-0")), authority)
        compare(transport.responses.length, 0)
    }
    function test_multifaceHandReusedPreviewExpiresAfterWindowReactivation() {
        previewFaces()
        const state = snapshot()
        state.zones[4].cards[0].identity = {name:"Delver of Secrets", setCode:"ISD", collectorNumber:"51"}
        verify(testRulesPrompt.applySnapshot(state))
        action("activateAbility", "own-0")
        mouseMove(item("forgeCard-own-0"))
        tryCompare(table.inspector, "previewCardId", "own-0")
        const preview = item("rulesCardHoverPreview")
        verifyFaceGallery(preview, "rulesCardHoverPreviewArt")
        mouseMove(item("rulesCardHoverPreviewArt-1"))
        state.zones[4].cards[0].identity.name = "Insectile Aberration"
        verify(testRulesPrompt.applySnapshot(state))
        verifyFaceGallery(preview, "rulesCardHoverPreviewArt", ["Insectile Aberration", "Delver of Secrets"])
        state.zones[4].cards[0].faceDown = true
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(preview, "visible", false)
        state.zones[4].cards[0].visible = false
        verify(testRulesPrompt.applySnapshot(state))
        const handCard = state.zones[4].cards.shift()
        state.zones[4].count--
        handCard.faceDown = false
        handCard.visible = true
        handCard.identity.name = "Delver of Secrets"
        state.zones[0].cards = [handCard]
        state.zones[0].count = 1
        verify(testRulesPrompt.applySnapshot(state))
        action("cast", "own-0")
        const authority = JSON.stringify(table.rulesSession.cardForInspection("own-0"))
        mouseMove(item("forgeHandCard-own-0"))
        tryCompare(table.inspector, "previewCardId", "own-0")
        verifyFaceGallery(preview, "rulesCardHoverPreviewArt")
        mouseMove(item("rulesCardHoverPreviewArt-1"))
        wait(400)
        verify(preview.visible)
        const otherWindow = createTemporaryObject(otherWindowComponent, testCase)
        otherWindow.requestActivate()
        tryCompare(otherWindow, "active", true)
        tryCompare(window, "active", false)
        window.requestActivate()
        tryCompare(window, "active", true)
        otherWindow.close()
        mouseMove(item("rulesPlayerTarget1"))
        tryCompare(preview, "visible", false, 1000)
        compare(table.inspector.previewCardId, "")
        compare(JSON.stringify(table.rulesSession.cardForInspection("own-0")), authority)
        compare(transport.responses.length, 0)
        compare(table.interaction.selectedCount, 0)
    }
    function test_pinKeepsInspectionDuringHandReflow_data() {
        return [{tag:"right-click",method:"right-click"},
            {tag:"menu",method:"menu"},{tag:"shift-f10",method:"shift-f10"}]
    }
    function test_closeInspectionReturnsFocusToSource_data() {
        return [{tag:"hand-close",hand:true,escape:false},
            {tag:"battlefield-close",hand:false,escape:false},
            {tag:"hand-escape",hand:true,escape:true}]
    }
    function test_pinnedInspectionKeepsReadableContentAndActions_data() {
        return [{tag:"compact-scaled", width:900, height:620, scale:1.5, language:"en"},
            {tag:"compact-scaled-chinese", width:900, height:620, scale:1.5, language:"zh"},
            {tag:"laptop", width:1280, height:800, scale:1, language:"en"},
            {tag:"desktop", width:1920, height:1011, scale:1, language:"en"}]
    }
    function test_pinnedInspectionKeepsReadableContentAndActions(data) {
        window.width=data.width; window.height=data.height; Theme.uiScale=data.scale
        testTranslations.setLanguage(data.language)
        catalog.language=data.language
        catalog.names=({"Isamaru, Hound of Konda":"今田家猎犬勇丸"})
        const state=snapshot(7,2,true)
        state.zones[0].cards[0].identity={name:"Isamaru, Hound of Konda"}
        verify(testRulesPrompt.applySnapshot(state))
        table.priority.setFullControl(true)
        action("activate", "own-0")
        table.forceActiveFocus()
        mouseMove(table,30,70)
        waitForRendering(table)
        const source=item("forgeHandCard-hand-0")
        mouseMove(source,source.width*0.3,source.height*0.5)
        tryCompare(table.inspector,"previewCardId","hand-0")
        waitForRendering(table)
        const preview=item("rulesCardHoverPreview")
        tryCompare(preview,"visible",true)
        if (data.width===900) verify(preview.inspectionRequired)
        if (preview.inspectionRequired) {
            const hint=item("rulesCardHoverInspect")
            mouseMove(hint)
            wait(450)
            verify(hint.visible)
            mouseClick(hint)
        } else mouseClick(source,source.width*0.3,source.height*0.5,Qt.RightButton)
        tryCompare(table.inspector,"pinnedCardId","hand-0")
        const host=item("rulesInspectionHost")
        tryCompare(host,"visible",true)
        waitForRendering(table)
        wait(450)
        compare(table.inspector.previewCardId,"")
        verify(host.width>=Theme.size(200),"Fixed details must retain a readable column")
        const title=item("rulesCardInspectorTitle")
        const close=item("clearRulesCardInspectorButton")
        verify(title.width>=Theme.size(140),"Close must not squeeze the card name into single-character lines")
        verify(close.width>=close.implicitWidth-1)
        verify(!rectsOverlap(title,close))
        verify(title.mapToItem(host,0,0).x>=0 && close.mapToItem(host,close.width,0).x<=host.width)
        const heading=item("rulesCardInspectorStateHeading")
        verify(heading.paintedWidth<=heading.width+1,"The state heading must wrap within its column")
        verify(item("rulesCardInspectorScroll").height>=Theme.size(60))
        const dock=item("rulesDecisionDock")
        verify(!rectsOverlap(host,dock),"The readable inspector must leave decisions accessible")
        for (const name of ["rulesPlayerTarget0","forgePlayerName-0","forgePlayerZones-0"])
            verify(!rectsOverlap(item(name),dock),"Fixed inspection must not hide the player's identity or life")
        const own=item("forgeCard-own-0")
        verify(!rectsOverlap(host,own))
        verify(table.presentation.pointFor("own-0").x>0)
        compare(transport.responses.length,0)
        const pass=findChild(item("rulesActionBar"),"rulesPromptOption-$pass")
        verify(pass.visible && pass.enabled)
        verify(!rectsOverlap(host,pass))
        state.zones[0].cards[0].faceDown=true
        state.zones[0].cards[0].identity={name:"SECRET"}
        catalog.faceRequests=[]
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        verify(!table.inspector.hasIdentity)
        verify(!item("rulesCardInspectorGallery").visible)
        verify(!item("rulesCardInspectorState").text.includes("SECRET"))
        verify(!title.text.includes("SECRET"))
        verify(!catalog.faceRequests.includes("SECRET"))
        mouseClick(pass)
        compare(transport.responses.length,1)
        compare(transport.responses[0].response,"$pass")
    }
    function test_closeInspectionReturnsFocusToSource(data) {
        window.width = 1920; window.height = 1011
        verify(testRulesPrompt.applySnapshot(snapshot(7, 2, true)))
        table.forceActiveFocus()
        mouseMove(table, 30, 70)
        waitForRendering(table)
        const source = item(data.hand ? "forgeHandCard-hand-0" : "forgeCard-own-0")
        const focusItem = data.hand ? item("forgeHandSurface-hand-0") : source
        const id = data.hand ? "hand-0" : "own-0"
        mouseClick(source, source.width * 0.6, source.height * 0.3, Qt.RightButton)
        tryCompare(table.inspector, "pinnedCardId", id)
        tryCompare(item("rulesInspectionHost"), "visible", true)
        if (data.escape) keyClick(Qt.Key_Escape)
        else mouseClick(item("clearRulesCardInspectorButton"))
        tryCompare(table.inspector, "pinnedCardId", "")
        tryCompare(focusItem, "activeFocus", true)
        verify(window.activeFocusItem.visible)
        keyClick(Qt.Key_Tab)
        verify(window.activeFocusItem !== focusItem)
        verify(window.activeFocusItem.visible && window.activeFocusItem.enabled,
            "Closing details must leave a usable keyboard focus chain")
        compare(transport.responses.length, 0)
    }
    function test_compactPinnedPlayerTargetAndAttackAnchorRemainAccessible() {
        window.width=900; window.height=620; Theme.uiScale=1.5
        const state=snapshot(7,2,true)
        state.zones[5].cards[0].attacking=true
        state.zones[5].cards[0].attackingPlayer=0
        verify(testRulesPrompt.applySnapshot(state))
        table.priority.setFullControl(true)
        action("activate","own-0")
        mouseMove(table,30,70)
        waitForRendering(table)
        const source=item("forgeCard-land")
        mouseClick(source,source.width/2,source.height/2,Qt.RightButton)
        tryCompare(table.inspector,"pinnedCardId","land")
        const plate=item("rulesPlayerTarget0"), dock=item("rulesDecisionDock")
        const arrow=item("forgeRelationship-attack-opponent-")
        function assertPlayerReachable() {
            waitForRendering(table)
            verify(!rectsOverlap(plate,dock))
            for(const id of ["own-0","own-1","land"])
                verify(!rectsOverlap(plate,item("forgeCard-"+id)),"Moving the plate must not cover public cards")
            const point=plate.mapToItem(table.presentation,plate.width/2,plate.lifeCenterY)
            compare(table.presentation.playerPoint(0),point)
            tryCompare(arrow,"endPoint",point)
            verify(arrow.validAnchors)
        }
        assertPlayerReachable()
        prompt("chooseBoardTargets",{minSelections:1,maxSelections:1,
            targets:[{responseId:"self",kind:"player",seat:0,label:"Alice"}]})
        assertPlayerReachable()
        mouseClick(plate,plate.width/2,plate.lifeCenterY)
        compare(transport.responses.length,1)
        compare(transport.responses[0].targets,["self"])
    }
    function test_inspectionAuthorityClearDoesNotRestoreSourceFocus() {
        const source = item("forgeHandSurface-hand-0")
        source.forceActiveFocus()
        keyClick(Qt.Key_Menu)
        tryCompare(table.inspector, "pinnedCardId", "hand-0")
        const focusTarget = item("forgeGameMenu")
        focusTarget.forceActiveFocus()
        verify(focusTarget.activeFocus)
        transport.inRoom = false
        tryCompare(table.inspector, "pinnedCardId", "")
        waitForRendering(table)
        verify(focusTarget.activeFocus)
        verify(!source.activeFocus)
    }
    function test_closeInspectionWithoutSourceReturnsFocusToTable() {
        mouseMove(table, 30, 70)
        table.endCardPreview()
        table.openCardDetails("land")
        compare(table.inspector.pinnedSource, null)
        mouseClick(item("clearRulesCardInspectorButton"))
        tryCompare(table.inspector, "pinnedCardId", "")
        tryVerify(() => table.activeFocus && window.activeFocusItem
            && window.activeFocusItem.visible && window.activeFocusItem.enabled)
        keyClick(Qt.Key_Tab)
        verify(window.activeFocusItem.visible && window.activeFocusItem.enabled)
        compare(transport.responses.length, 0)
    }
    function test_pinKeepsInspectionDuringHandReflow(data) {
        window.width=1920; window.height=1011
        const state=snapshot(7,2,true)
        state.zones[0].cards[0].identity={name:"Isamaru, Hound of Konda"}
        verify(testRulesPrompt.applySnapshot(state))
        table.forceActiveFocus()
        mouseMove(table,30,70)
        waitForRendering(table)
        const source=item("forgeHandCard-hand-0")
        const pointer=source.mapToItem(table,source.width*0.65,source.height*0.3)
        mouseMove(table,pointer.x,pointer.y)
        tryCompare(table.inspector,"previewCardId","hand-0")
        if (data.method==="right-click") mouseClick(table,pointer.x,pointer.y,Qt.RightButton)
        else {
            item("forgeHandSurface-hand-0").forceActiveFocus()
            keyClick(data.method==="menu"?Qt.Key_Menu:Qt.Key_F10,
                data.method==="menu"?Qt.NoModifier:Qt.ShiftModifier)
        }
        waitForRendering(table)
        wait(450)
        compare(table.inspector.pinnedCardId,"hand-0")
        compare(table.inspector.previewCardId,"")
        verify(item("rulesInspectionHost").visible)
        verify(table.presentation.pinnedHoverGuard)
        const deferred=table.presentation.deferredHover
        verify(deferred!==null && deferred.cardId!=="hand-0",
            "The changed layout must actually enter a different card under the still pointer")
        const nextId=deferred.cardId
        mouseMove(table,pointer.x+3,pointer.y)
        tryCompare(table.inspector,"previewCardId",nextId)
        compare(table.inspector.pinnedCardId,"hand-0")
        mouseMove(table,30,70)
        tryCompare(table.inspector,"previewCardId","")
        verify(item("rulesInspectionHost").visible)
        compare(table.inspector.cardId,"hand-0")
        compare(transport.responses.length,0)
    }
    function test_pinnedPointerGuardAllowsKeyboardAndResetsOnAuthorityLoss() {
        table.openCardDetails("missing-card")
        compare(table.presentation.pinnedHoverGuard,false)
        table.openCardDetails("land")
        verify(table.presentation.pinnedHoverGuard)
        item("forgeHandSurface-hand-0").forceActiveFocus()
        tryCompare(table.inspector,"previewCardId","hand-0")
        compare(table.inspector.pinnedCardId,"land")
        transport.inRoom=false
        tryCompare(table.inspector,"pinnedCardId","")
        compare(table.presentation.pinnedHoverGuard,false)
        compare(table.presentation.deferredHover,null)
        transport.inRoom=true
        item("forgeCard-own-0").forceActiveFocus()
        tryCompare(table.inspector,"previewCardId","own-0")
    }
    function test_leftClickDoesNotPinInspectionAndRightClickDoes() {
        const land = item("forgeCard-land")
        const dock = item("rulesInspectionHost")
        verify(!land.actionable)
        mouseClick(land)
        compare(table.inspector.pinnedCardId, "")
        compare(dock.visible, false)
        mouseClick(land, land.width / 2, land.height / 2, Qt.RightButton)
        tryCompare(table.inspector, "pinnedCardId", "land")
        tryCompare(dock, "visible", true)
        verify(dock.inspectionOpened)
    }
    function test_hoverAtRightEdgeAndDuringCombatRemainsReadOnly() {
        const state = snapshot()
        state.stack = [{id:"bolt", controllerSeat:1, identity:{name:"Lightning Bolt"}}]
        verify(testRulesPrompt.applySnapshot(state))
        combat("chooseAttackers")
        const source = item("forgeStackCard-bolt"), preview = item("rulesCardHoverPreview")
        mouseMove(source, 25, 40)
        tryCompare(preview, "visible", true)
        const origin = source.mapToItem(table, 0, 0)
        verify(preview.x + preview.width <= origin.x)
        verify(preview.x >= 0 && preview.y >= 0 && preview.y + preview.height <= table.height)
        compare(transport.responses.length, 0)
        mouseMove(item("forgeCard-own-0"), 20, 30)
        tryCompare(table.inspector, "previewCardId", "own-0")
        mouseClick(item("forgeCard-own-0"))
        mouseClick(item("rulesPlayerTarget1"))
        compare(table.combatInteraction.assignments["opaque-source"], "opaque-target")
    }
    function test_floatingPreviewPreservesOpenLogAndChatDraft() {
        action("playLand", "hand-0")
        table.setGameLogVisible(true)
        table.gameLogRail.chatInput.text = "Unsent draft"
        mouseMove(item("forgeHandCard-hand-0"), 20, 40)
        tryCompare(item("rulesCardHoverPreview"), "visible", true)
        verify(!item("rulesInspectionHost").visible)
        verify(table.gameLogRail.visible)
        verify(!table.inspector.visible)
        compare(table.gameLogRail.chatInput.text, "Unsent draft")
        mouseMove(table, 30, 70)
        tryCompare(item("rulesCardHoverPreview"), "visible", false)
        verify(table.gameLogRail.visible)
        table.gameLogRail.chatInput.text = ""
    }
    function test_hoverClearsOnAuthorityLossAndHidesFaceDownIdentity() {
        action("playLand", "hand-0")
        mouseMove(item("forgeHandCard-hand-0"), 20, 40)
        tryCompare(item("rulesCardHoverPreview"), "visible", true)
        room.role = "spectator"
        tryCompare(item("rulesCardHoverPreview"), "visible", false)
        compare(table.inspector.previewCardId, "")
        const state = snapshot()
        state.zones[4].cards[0] = {id:"own-0", ownerSeat:0, controllerSeat:0, visible:false, faceDown:true,
            power:"2", toughness:"2"}
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        mouseMove(item("forgeCard-own-0"), 20, 30)
        tryCompare(table.inspector, "previewCardId", "own-0")
        tryCompare(item("rulesCardHoverPreview"), "visible", true)
        verify(!table.inspector.hasIdentity)
        compare(item("rulesCardHoverPreviewArt").source, table.cardBackSource)
        transport.inRoom = false
        tryCompare(item("rulesCardHoverPreview"), "visible", false)
    }
    function test_compactHandReturnsSpaceToBattlefield() {
        verify(testRulesPrompt.applySnapshot(snapshot(7, 4)))
        const hand = item("forgeHand")
        tryVerify(() => hand.visibleCards.length === 7)
        verify(hand.height <= hand.faceHeight * 0.7)
        const creatures = item("forgeOwnCreatures"), lands = item("forgeOwnLands")
        fuzzyCompare(Math.min(creatures.y, lands.y), table.presentation.ownBattlefieldTop, 1)
        fuzzyCompare(Math.max(creatures.y + creatures.height, lands.y + lands.height),
                     table.presentation.battlefieldBottom, 1)
        verify(creatures.cardWidth >= 80 * table.presentation.unit)
        for (const slot of hand.visibleCards) {
            const center = slot.mapToItem(table, slot.width / 2, slot.height / 2)
            verify(center.y >= hand.y && center.y < table.height)
        }
        // Finish the new snapshot's hover hit testing before beginning the
        // separate keyboard inspection intent.
        verify(waitForPolish(window))
        mouseMove(table, table.width - 2, 2)
        verify(waitForPolish(window))
        grabImage(table)
        const focused = item("forgeHandSurface-hand-6")
        focused.forceActiveFocus()
        tryCompare(focused, "activeFocus", true)
        tryCompare(table.inspector, "previewCardId", "hand-6")
        tryCompare(item("rulesCardHoverPreview"), "visible", true)
        compare(table.inspector.previewCardId, "hand-6")
    }
    function test_permanentsFitWithoutScrolling_data() {
        return [{tag:"desktop", w:1600, h:1000}, {tag:"laptop", w:1280, h:800},
            {tag:"wide", w:1920, h:1011}, {tag:"duel", w:1600, h:1000, duel:true}]
    }
    function test_permanentsFitWithoutScrolling(data) {
        window.width = data.w; window.height = data.h
        room.format = data.duel ? "duel" : "modern"
        const state = snapshot(7, 20)
        for (let seat = 0; seat < 2; ++seat) {
            const zone = state.zones[4 + seat]
            zone.cards = zone.cards.filter(value => value.identity.name !== "Plains")
            for (let i = 0; i < 8; ++i) {
                zone.cards.push(card("land-" + seat + "-" + i, seat, "Plains", false))
                zone.cards.push(card("artifact-" + seat + "-" + i, seat, "Treasure", false))
            }
            zone.count = zone.cards.length
        }
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        for (const name of ["forgeOwnLands", "forgeOpponentLands", "forgeOwnOther", "forgeOpponentOther"]) {
            const lane = item(name)
            tryVerify(() => lane.visibleCards.length === 8 && lane.stackCount === 1)
            tryVerify(() => lane.scrollArea.contentHeight <= lane.scrollArea.height + 1,
                      5000, name + " should fit all eight exact permanents")
            for (const slot of lane.visibleCards)
                verify(slot.y + slot.height <= lane.scrollArea.height + 1)
        }
    }
    function test_creatureGridUsesExactFittedColumns_data() {
        return [20, 22, 26].map(count => ({tag:String(count), count:count}))
    }
    function test_creatureGridUsesExactFittedColumns(data) {
        window.width = 1920; window.height = 1011
        const state = snapshot(7, data.count, true)
        state.zones[5].cards = Array.from({length:data.count}, (_, i) => card("other-" + i, 1, "Bear " + i, true))
        state.zones[5].count = data.count
        verify(testRulesPrompt.applySnapshot(state))
        verify(waitForPolish(window)); verify(waitForRendering(table))
        for (const name of ["forgeOwnCreatures", "forgeOpponentCreatures"]) {
            const lane = item(name)
            tryVerify(() => lane.visibleCards.length === data.count)
            // Crowded rows retain full combat/readout reservations and may
            // scroll at the readable floor instead of squeezing 22 faces in.
            if (data.count <= 20)
                verify(lane.scrollArea.contentHeight <= lane.scrollArea.height + 1,
                    "The fitted grid should show this count without scrolling: " + JSON.stringify({
                        lane:name, count:data.count, width:lane.width, height:lane.height,
                        face:lane.cardWidth, columns:lane.columns, contentHeight:lane.scrollArea.contentHeight,
                        viewportHeight:lane.scrollArea.height, obstacles:table.presentation.battlefieldObstacles}))
            else verify(lane.cardWidth >= 80 * table.presentation.unit - 0.1,
                "A very crowded grid scrolls instead of shrinking below the readable floor")
            for (const slot of lane.visibleCards) {
                verify(slot.x + slot.width <= lane.scrollArea.width + 1)
                verify(slot.y + slot.height <= lane.scrollArea.contentHeight + 1)
                verify(lane.reveal(slot.cardId))
                const at = slot.mapToItem(lane.scrollArea, 0, 0)
                verify(at.y >= -0.1 && at.y + slot.height <= lane.scrollArea.height + 1,
                    "Every exact crowded-grid object remains fully revealable")
            }
        }
    }
    function test_turnOwnerIsIndependentOfPriority() {
        const indicator = item("forgeTurnIndicator")
        compare(indicator.text, "Your turn")
        const highlight = item("forgeActiveBattlefield")
        const callout = item("forgeTurnCallout")
        verify(highlight.visible)
        verify(highlight.y <= item("forgeOwnCreatures").y)
        verify(highlight.y + highlight.height > item("forgeOwnCreatures").y)
        compare(callout.message, "My turn")
        verify(callout.opacity > 0)
        const state = snapshot()
        state.prioritySeat = 1
        verify(testRulesPrompt.applySnapshot(state))
        compare(indicator.text, "Your turn")
        compare(callout.message, "My turn")
        verify(item("rulesPlayerTarget0").activeTurn)
        verify(!item("rulesPlayerTarget1").activeTurn)
        state.activeSeat = 1; state.prioritySeat = 0
        verify(testRulesPrompt.applySnapshot(state))
        compare(indicator.text, table.matchUi.playerName(1) + "'s turn")
        verify(highlight.y + highlight.height <= item("forgeOwnCreatures").y + 1)
        tryCompare(callout, "message", "Opponent's turn")
        verify(callout.opacity > 0)
        verify(item("rulesPlayerTarget1").activeTurn)
        room.role = "spectator"
        compare(indicator.text, table.matchUi.playerName(1) + "'s turn")
        state.turn = 0
        verify(testRulesPrompt.applySnapshot(state))
        compare(indicator.text, "Preparing game")
        tryCompare(highlight, "visible", false)
        tryCompare(callout, "opacity", 0)
        verify(!item("rulesPlayerTarget1").activeTurn)
    }
    function test_priorityPhaseCombatAndManaStayReadable() {
        const state = snapshot(1, 2)
        state.step = "declare_attackers"
        state.prioritySeat = 1
        state.zones[4].cards[1].attacking = true
        state.zones[4].cards[1].attackingPlayer = 1
        verify(testRulesPrompt.applySnapshot(state))
        prompt("", {pending:false, supported:false})
        const banner = item("forgeOpponentDeciding")
        tryCompare(banner, "visible", true)
        compare(item("forgeOpponentDecidingText").text, "Opponent is deciding")
        const track = item("forgePhaseTrack")
        verify(waitForPolish(window)); waitForRendering(table)
        fuzzyCompare(banner.y + banner.height / 2, table.presentation.battlefieldMiddle, 0.1,
                     "The public deciding banner remains on the central seam")
        const phasePaint = track.compactMode ? item("forgeCurrentPhase") : track
        verify(!rectsOverlap(banner, phasePaint), "The phase moves independently of the deciding banner")
        assertDuelPublicFieldAllocation()
        verifyOverlayReadoutsClear(state, banner, "The deciding banner")
        verifyOverlayReadoutsClear(state, phasePaint, "The phase strip below the deciding banner")
        assertPublicPhaseAnchor()
        const exposed = battlefieldReadoutRects(state)
        for (const id of ["own-0", "own-1"]) {
            verify(exposed.some(row => row.label.objectName === "forgeCardName-" + id),
                   "The attacking and idle copies each expose their title")
            verify(exposed.some(row => row.label.objectName === "forgeCardStats-" + id),
                   "Both separate P/T readouts remain part of the clearance check")
        }
        verify(!item("forgeRecentActions").visible)
        verify(track.y + track.height <= item("forgeHand").y)
        const attack = item("forgePhase-declare_attackers")
        const draw = item("forgePhase-draw")
        compare(attack.current, true)
        compare(draw.past, true)
        compare(item("forgePhase-end").past, false)
        const mover = item("forgeCard-own-1").parent
        const stayed = item("forgeCard-own-0").parent
        verify(mover.y < stayed.y)

        state.prioritySeat = 0
        state.step = "main1"
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        tryCompare(banner, "visible", false)
        compare(item("forgeHand").y, table.presentation.handTop)
        compare(item("forgeHandPriorityGlow").opacity, 1)
        compare(item("rulesYieldMenuButton").compact, false)
        compare(findChild(item("rulesActionBar"), "rulesPromptOption-$pass").compact, false)

        prompt("payManaCost", {title:"Pay Mana Cost: {G}",
            detail:"Forest — {T}: Add {G}.",
            contextText:"Forest — {T}: Add {G}.",
            contextCards:[{id:"context-card:0", name:"Forest"}],
            options:[{responseId:"ability", cardId:"own-0", kind:"activateAbility", label:"Forest"}]})
        compare(item("rulesPromptTitle").text, "Pay Mana Cost: {G}")
        compare(item("rulesPromptDetail").visible, false)
        compare(item("rulesPromptContext").visible, false)
        compare(item("rulesYieldMenuButton").visible, false)
        compare(item("forgeCardInteractionHint-own-0").text, "Tap for mana")
    }
    function test_decisionsStayBesideBoardAndInsideWindow_data() {
        return [{tag:"desktop", w:1600, h:1000}, {tag:"laptop", w:1280, h:800},
            {tag:"compact", w:900, h:620}, {tag:"scaled", w:1280, h:800, scale:1.35}]
    }
    function surveilPrompt() {
        prompt("chooseBoolean", {title:"Confirm decision", detail:"Put Troll of Khazad-dûm on the top of library or graveyard?",
            contextCards:[{id:"context-card:0", name:"Troll of Khazad-dûm"}],
            contextText:"Troll of Khazad-dûm can't be blocked except by three or more creatures.\nSwampcycling {1}",
            minChoiceTotal:1, maxChoiceTotal:1,
            choices:[{responseId:"choice:0", label:"Graveyard", weight:1, canRepeat:false},
                {responseId:"choice:1", label:"Library", weight:1, canRepeat:false}]})
    }
    function test_surveilShowsCardBesideBothChoices_data() {
        return test_cardChoiceDialogUsesCurrentPrivateCandidates_data()
    }
    function test_surveilShowsCardBesideBothChoices(data) {
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        surveilPrompt()
        const dock = item("rulesDecisionDock"), context = findChild(dock, "rulesPromptContext")
        const source = findChild(context, "rulesPromptSourceCard")
        verify(source !== null && source.visible)
        verify(source.height > Theme.size(140))
        verify(findChild(source, "rulesPromptSourceFallback").text.includes("Swampcycling"))
        verify(catalog.requested.includes("Troll of Khazad-dûm"))
        mouseMove(source, source.width / 2, source.height / 2)
        const preview = findChild(context, "rulesPromptCardPreview")
        tryCompare(preview, "visible", true)
        compare(preview.card.name, "Troll of Khazad-dûm")
        verify(!preview.enabled)
        tryVerify(() => preview.x >= 0 && preview.y >= 0 && preview.x + preview.width <= window.width + 1
               && preview.y + preview.height <= window.height + 1)
        verify(preview.x + preview.width <= source.mapToItem(preview.parent, 0, 0).x)
        verify(preview.x + preview.width <= dock.mapToItem(preview.parent, 0, 0).x,
               "The enlarged card must leave the decision buttons unobscured")
        mouseMove(source, -20, -20)
        tryCompare(preview, "visible", false)
        for (const id of ["choice:0", "choice:1"]) {
            const button = item("rulesScalarChoice-" + id), point = button.mapToItem(table, 0, 0)
            const scroll = findChild(dock, "rulesPromptScroll"), bottom = scroll.mapToItem(table, 0, scroll.height).y
            verify(point.y >= dock.y && point.y + button.height <= bottom + 1,
                   "Both decisions must remain visible without scrolling past the card")
        }
        source.forceActiveFocus()
        tryCompare(preview, "visible", true)
        mouseClick(item("rulesScalarChoice-choice:0"))
        compare(transport.responses.length, 1)
        compare(transport.responses[0].choices, ["choice:0"])
    }
    function test_privateDecisionPreviewClearsWithAuthority_data() {
        return [{tag:"disconnect"}, {tag:"spectator"}, {tag:"seat"}, {tag:"prompt"}, {tag:"game"}]
    }
    function test_privateDecisionPreviewClearsWithAuthority(data) {
        surveilPrompt()
        const context = findChild(item("rulesDecisionDock"), "rulesPromptContext")
        const source = findChild(context, "rulesPromptSourceCard")
        const preview = findChild(context, "rulesPromptCardPreview")
        mouseMove(source, 20, 30)
        tryCompare(preview, "visible", true)
        if (data.tag === "disconnect") transport.inRoom = false
        else if (data.tag === "spectator") room.role = "spectator"
        else if (data.tag === "seat") room.seatIndex = 1
        else if (data.tag === "prompt") prompt("chooseBoolean", {choices:[], minChoiceTotal:0, maxChoiceTotal:0})
        else { const state = snapshot(); state.gameId = "next-game"; verify(testRulesPrompt.applySnapshot(state)) }
        tryCompare(preview, "visible", false)
        verify(!context.visible)
    }
    function test_tableControlsShareDecisionDockAndFreeTopEdge_data() {
        const cases = test_cardChoiceDialogUsesCurrentPrivateCandidates_data()
            .concat([{tag:"compact", width:900, height:620, scale:1}])
        const localized = []
        for (const data of cases) {
            for (const language of ["en", "zh"])
                for (const hosting of ["server", "player"])
                    localized.push(Object.assign({}, data, {tag:data.tag + "-" + language + "-" + hosting,
                        language:language, hosting:hosting}))
        }
        return localized
    }
    function test_tableControlsShareDecisionDockAndFreeTopEdge(data) {
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        room.hostingMode = data.hosting
        testTranslations.setLanguage(data.language)
        action("playLand", "hand-0")
        const dock = item("rulesDecisionDock"), opponent = item("rulesPlayerTarget1")
        verify(table.presentation.battlefieldBottom - table.presentation.battlefieldTop > table.height * 0.65,
            "The battlefield keeps most of the table height without a top control toolbar")
        verify(opponent.y < 12 * table.presentation.unit)
        verify(item("forgeOwnZoneStrip").y >= item("forgeHand").y - 4 * table.presentation.unit)
        verify(dock.x + dock.width <= table.width + 1)
        verify(dock.y + dock.height <= table.height + 1)
        verify(dock.y + dock.height >= table.height - 20 * table.presentation.unit)
        const reservation = table.presentation.dockReservation, creatures = item("forgeOwnCreatures")
        verifyBattlefieldClearOfOverlay(["forgeOwnCreatures"], reservation, "the decision reservation")
        if (data.tag.startsWith("desktop"))
            verify(creatures.cardWidth >= 180 * table.presentation.unit,
                   "Desktop creatures stay readable beside the decision reservation")
        verify(!item("rulesPriorityStatus").visible)
        const dockControls = ["forgeTurnIndicator", "forgeTurnPhase", "rulesYieldMenuButton"]
        for (const name of dockControls) {
            const control = findChild(dock, name)
            verify(control !== null && control.visible, name + " belongs to the decision dock")
            const point = control.mapToItem(dock, 0, 0)
            verify(point.x >= 0 && point.x + control.width <= dock.width + 1, name + " fits dock width")
            verify(point.y >= 0 && point.y + control.height <= dock.height + 1, name + " fits dock height")
        }
        const settingsOnly = ["forgeGameMenu", "rulesToggleGameLogButton", "rulesPriorityMode"]
            .concat(data.hosting === "player" ? ["forgeHostingOptions", "forgePeerStatus",
                "forgePeerEnable", "forgePeerConsentNotice"] : [])
        for (const name of settingsOnly)
            verify(findChild(dock, name) === null, name + " stays out of the decision dock")
        const settings = item("forgeGameMenu")
        verify(settings.visible)
        compare(settings.text, data.language === "zh" ? "设置" : "Settings")
        verify(settings.y < 48)
        verify(settings.x + settings.width >= table.width - 24 * table.presentation.unit)
        openSettings()
        verify(item("rulesPriorityMode").visible)
        verify(item("rulesToggleGameLogButton").visible)
        if (data.hosting === "player") {
            verify(item("forgeHostingOptions").visible)
            verify(item("forgeTablePeerConnection").visible)
        }
        verify(!table.priority.fullControl)
        mouseClick(item("rulesPriorityMode"), item("rulesPriorityMode").width * 0.75, item("rulesPriorityMode").height / 2)
        verify(table.priority.fullControl)
        verify(!item("rulesPriorityStatus").visible)
        table.priority.setFullControl(false)
        closeSettings()
    }
    function test_audioSettingsOpenFromMatchAndCloseDrawer_data() {
        return [{tag:"default-preferences", injected:false, width:1600, height:1000},
                {tag:"table-preferences", injected:true, width:1600, height:1000},
                {tag:"compact", injected:false, width:900, height:620}]
    }
    function test_audioSettingsOpenFromMatchAndCloseDrawer(data) {
        const previous = table.preferencesModel
        window.width = data.width
        window.height = data.height
        table.preferencesModel = data.injected ? preferences : null
        window.openedScreen = ({})
        try {
            openSettings()
            const audio = item("rulesAudioButton")
            verify(audio.visible && audio.enabled)
            const rail = item("rulesActionRail"), phases = item("rulesPhaseScrollView")
            verify(phases.height > 0)
            const point = audio.mapToItem(rail, 0, 0)
            verify(point.y >= 0 && point.y + audio.height <= rail.height)
            mouseClick(audio)
            tryCompare(item("forgeGameDrawer"), "visible", false)
            compare(window.openedScreen.url, "screens/AudioSettings.qml")
            compare(window.openedScreen.properties.settings, data.injected ? preferences : undefined)
            verify(transport.inRoom)
        } finally {
            table.preferencesModel = previous
        }
    }
    function test_settingsStayAccessibleBetweenGames() {
        match.sideboarding = true
        const dock = item("rulesDecisionDock"), loader = item("rulesSideboardLoader")
        waitForRendering(table)
        tryVerify(() => loader.item !== null)
        verify(!dock.visible)
        verify(item("forgeGameMenu").visible)
        compare(loader.x, 0)
        compare(loader.y, 0)
        compare(loader.width, table.width)
        compare(loader.height, table.height)
        const workspace = findChild(loader.item, "sideboardWorkspace")
        verify(workspace)
        compare(workspace.width, loader.width)
        compare(workspace.height, loader.height)
        const countdown = findChild(loader.item, "sideboardCountdown")
        const settings = item("forgeGameMenu")
        const countdownRight = countdown.mapToItem(table, countdown.width, 0).x
        const settingsLeft = settings.mapToItem(table, 0, 0).x
        verify(countdownRight <= settingsLeft)
        openSettings()
        closeSettings()
        match.sideboarding = false
        tryCompare(dock, "visible", true)
        tryCompare(item("rulesActionBar"), "visible", true)
        verify(dock.showsBody)
        verify(!item("forgeTurnIndicator").visible, "An open decision uses the turn rows' space")
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        tryCompare(item("forgeTurnIndicator"), "visible", true)
    }
    function test_peerControlsOnTableAndBetweenGames_data() {
        return [{tag:"host", seat:0, sideboarding:false}, {tag:"opponent", seat:1, sideboarding:false},
            {tag:"between-games", seat:0, sideboarding:true}]
    }
    function test_peerControlsOnTableAndBetweenGames(data) {
        room.hostingMode = "player"; room.seatIndex = data.seat
        match.sideboarding = data.sideboarding
        openSettings()
        const panel = item("forgeTablePeerConnection")
        waitForRendering(table)
        const enable = findChild(panel, "forgePeerEnable")
        verify(panel.visible && enable.visible && enable.enabled)
        verify(table.presentation.modalOpen)
        compare(transport.peerRequests.length, 0)
        mouseClick(enable)
        compare(transport.peerRequests, [{enabled:true, retry:false}])
        verify(preferences.directPeerEnabled)
        verify(table.presentation.modalOpen)
        verify(!item("forgeHostingDialog").opened)
        transport.peerTransportState = "direct"
        verify(findChild(panel, "forgePeerStatus").text.includes("Direct connection active"))
        transport.peerTransportState = "relay"
        waitForRendering(table)
        const retry = findChild(panel, "forgePeerRetry")
        verify(retry.visible)
        mouseClick(retry)
        compare(transport.peerRequests[1], {enabled:true, retry:true})
        waitForRendering(table)
        mouseClick(enable)
        compare(transport.peerRequests[2], {enabled:false, retry:false})
        verify(!preferences.directPeerEnabled)
        room.role = "spectator"
        verify(!panel.visible)
        closeSettings()
    }
    function test_onlyTheActivePromptFamilyIsCreated() {
        prompt("chooseNumber", {minNumber: 0, maxNumber: 3})
        item("rulesNumberInput")
        verify(findChild(table, "rulesScalarCandidates") === null)
        verify(findChild(table, "rulesCombatCandidates-attackers") === null)
        prompt("chooseBoolean", {title:"Confirm decision", detail:"Use triggered ability?",
            minChoiceTotal:1, maxChoiceTotal:1,
            choices:[{responseId:"choice:0", label:"No", weight:1, canRepeat:false},
                {responseId:"choice:1", label:"Yes", weight:1, canRepeat:false}]})
        item("rulesScalarCandidates")
        verify(findChild(table, "rulesNumberInput") === null)
    }
    function test_numberDecisionRemainsInteractive_data() {
        const rows = []
        for (const hosting of ["server", "player"])
            for (const maximum of [999, 2147483647])
                rows.push({tag:hosting + "-" + maximum, hosting:hosting, maximum:maximum})
        return rows
    }
    function test_numberDecisionRemainsInteractive(data) {
        window.width = 1280; window.height = 729
        room.hostingMode = data.hosting
        action("cast", "hand-0")
        mouseClick(item("forgeHandCard-hand-0"))
        compare(transport.rulesResponsePending, true)
        prompt("chooseNumber", {title:"Choose X for Walking Ballista", minNumber:0, maxNumber:data.maximum})
        const input = item("rulesNumberInput")
        for (let ancestor = input; ancestor; ancestor = ancestor.parent) {
            verify(ancestor.visible && ancestor.enabled && ancestor.opacity > 0,
                "Number input ancestor prevents native interaction: " + ancestor.objectName)
        }
        verify(input.width > 0 && input.height > 0)
        const dock = item("rulesDecisionDock"), point = input.mapToItem(dock, 0, 0)
        verify(point.x >= 0 && point.x + input.width <= dock.width + 1)
        verify(point.y >= 0 && point.y + input.height <= dock.height + 1)
        mouseClick(input.up.indicator)
        compare(input.value, 1)
        mouseClick(item("rulesConfirmNumber"))
        compare(transport.responses.length, 2)
        compare(transport.responses[1].number, 1)
    }
    function test_decisionsStayBesideBoardAndInsideWindow(data) {
        window.width = data.w; window.height = data.h
        Theme.uiScale = data.scale || 1
        combat("chooseAttackers")
        const dock = item("rulesDecisionDock"), hand = item("forgeHand")
        waitForRendering(table)
        verifyBattlefieldClearOfOverlay(["forgeOwnCreatures"],
            dock.mapToItem(table.presentation, 0, 0, dock.width, dock.height), "the decision dock")
        verify(dock.x >= hand.x + hand.width)
        verify(dock.x + dock.width <= table.width + 1)
        verify(dock.y + dock.height <= table.height + 1)
        const confirm = item("rulesConfirmCombat-attackers")
        const point = confirm.mapToItem(table, 0, 0)
        verify(point.x >= dock.x && point.x + confirm.width <= table.width)
        verify(point.y >= dock.y && point.y + confirm.height <= table.height)
        mouseClick(confirm)
        compare(transport.responses.length, 1)
    }
    function test_playmatShowsThroughBattlefield() {
        const board = item("forgeDuelTable")
        compare(board.color.a, 0)
        const veil = findChild(board, "forgePlaymatVeil")
        verify(veil !== null)
        compare(veil.width, board.width)
        const library = item("forgeZone-library")
        compare(library.width, Math.round(library.width))
        compare(library.height, Math.round(library.height))
        const prompt = item("rulesPromptPanel")
        compare(prompt.color.a, 0)
        compare(prompt.border.width, 0)
        const picker = item("rulesCardActionPicker")
        compare(picker.color.a, 0)
        compare(picker.border.width, 0)
    }

    function test_handCaptionStaysReadableAcrossBattlefieldBorder_data() {
        return [{tag:"maximized", width:1920, height:1011},
            {tag:"compact-scaled", width:900, height:620, scale:1.5},
            {tag:"spectator-hidden", width:1920, height:1011, spectator:true},
            {tag:"spectator-read-only", width:1920, height:1011, spectator:true, hands:true}]
    }
    function test_handCaptionStaysReadableAcrossBattlefieldBorder(data) {
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale || 1
        if (data.spectator) {
            room.role = "spectator"; room.seatIndex = -1
            room.spectatorsSeeHands = data.hands === true
        }
        verify(testRulesPrompt.applySnapshot(snapshot(2, 1)))
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        mouseMove(table, 1, 1)
        verify(waitForPolish(window)); verify(waitForRendering(table))
        const hand = item("forgeHand"), caption = item("forgeHandCaption")
        const battlefield = item("forgeActiveBattlefield")
        verify(caption.visible && battlefield.visible)
        compare(hand.y, table.presentation.handTop)
        compare(caption.y, -16 * hand.unit, "Readout protection must not move the hand or its caption")
        if (!data.spectator) compare(caption.text, "Hand · 2")
        else if (data.hands) compare(caption.text, table.matchUi.playerName(0) + " — hand (read only)")
        else {
            compare(caption.text, "Hands are hidden from spectators in this room")
            compare(hand.visibleCards.length, 0)
        }
        const withBorder = grabImage(table)
        const color = String(battlefield.border.color)
        battlefield.border.color = "transparent"
        const withoutBorder = grabImage(table)
        battlefield.border.color = color
        verify(!withBorder.equals(withoutBorder), "The actual battlefield border must be visible")
        compare(textRegionChangedPixels(withBorder, withoutBorder, caption), 0,
            "The battlefield edge must not run through the hand count or spectator wording")
        compare(transport.responses.length, 0)
    }

    function test_handHoverFollowsMotionSwitch() {
        const slot = item("forgeHandCard-hand-0"), face = item("forgeHandSurface-hand-0")
        const lift = -18 * table.presentation.unit
        mouseMove(slot, slot.width / 2, slot.height / 2)
        compare(face.y, lift, "Disabled motion applies the hover lift immediately")
        mouseMove(slot, -10, -10)
        compare(face.y, 0)
        Theme.motionEnabled = true
        mouseMove(slot, slot.width / 2, slot.height / 2)
        verify(face.y > lift, "Enabled motion animates the hover lift")
        tryCompare(face, "y", lift)
    }

    function stillBoard() {
        const state = snapshot(3, 6, true)
        const own = state.zones[4]
        own.cards.push(card("land-1", 0, "Plains", false), card("land-2", 0, "Plains", false),
            card("labyrinth", 0, "Ugin's Labyrinth", false), card("walker", 0, "Test Walker", false))
        own.count = own.cards.length
        return state
    }
    function boardGeometry(ids) {
        const lanes = ["forgeOwnCreatures", "forgeOwnLands", "forgeOwnPlaneswalkers", "forgeOwnOther",
            "forgeOpponentCreatures", "forgeOpponentLands", "forgeOpponentPlaneswalkers", "forgeOpponentOther"].map(name => {
                const lane = item(name)
                return name + ":" + [lane.x, lane.y, lane.width, lane.height].map(Math.round).join(",")
            })
        return lanes.concat(ids.map(id => {
            const face = findChild(table, "forgeCard-" + id)
            if (!face || !face.visible) return id + ":hidden"
            const point = face.mapToItem(table.presentation, 0, 0)
            return id + ":" + Math.round(point.x) + "," + Math.round(point.y)
        }))
    }
    function verifyBattlefieldClearOfOverlay(laneNames, overlay, label) {
        function clear(rect) {
            return rect.x + rect.width <= overlay.x + 0.5
                || rect.x >= overlay.x + overlay.width - 0.5
                || rect.y + rect.height <= overlay.y + 0.5
                || rect.y >= overlay.y + overlay.height - 0.5
        }
        for (const name of laneNames) {
            const lane = item(name)
            const clip = lane.scrollArea.clip
                ? lane.scrollArea.mapToItem(table.presentation, 0, 0,
                    lane.scrollArea.width, lane.scrollArea.height)
                : Qt.rect(0, 0, table.presentation.width, table.presentation.height)
            for (const slot of lane.visibleCards) {
                const face = item("forgeCardFace-" + slot.cardId)
                const rect = face.mapToItem(table.presentation, 0, 0, face.width, face.height)
                const left = Math.max(rect.x, clip.x), top = Math.max(rect.y, clip.y)
                const right = Math.min(rect.x + rect.width, clip.x + clip.width)
                const bottom = Math.min(rect.y + rect.height, clip.y + clip.height)
                if (right > left && bottom > top)
                    verify(clear(Qt.rect(left, top, right - left, bottom - top)),
                        slot.cardId + " visible face stays clear of " + label)
            }
            for (const rect of lane.readoutRects(table.presentation))
                verify(clear(rect), name + " public readouts stay clear of " + label)
        }
    }
    function test_decisionReservationKeepsTwoSeatCardsStill_data() {
        return [{tag:"desktop", w:1600, h:1000, scale:1}, {tag:"wide", w:1920, h:1010, scale:1},
            {tag:"laptop", w:1280, h:800, scale:1}, {tag:"scaled", w:1180, h:740, scale:1.35},
            {tag:"compact", w:900, h:620, scale:1}]
    }
    function test_decisionReservationKeepsTwoSeatCardsStill(data) {
        window.width = data.w; window.height = data.h; Theme.uiScale = data.scale
        verify(testRulesPrompt.applySnapshot(stillBoard()))
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        const ids = ["own-0", "own-5", "land", "land-2", "labyrinth", "walker", "opponent"]
        const baseline = boardGeometry(ids)
        const reservation = table.presentation.dockReservation
        const ownLanes = ["forgeOwnCreatures", "forgeOwnLands", "forgeOwnPlaneswalkers", "forgeOwnOther"]
        verifyBattlefieldClearOfOverlay(ownLanes, reservation, "the decision reservation")
        const plate = item("rulesPlayerTarget0")
        const plateRect = plate.mapToItem(table.presentation, 0, 0, plate.width, plate.height)
        verifyBattlefieldClearOfOverlay(ownLanes, plateRect, "the player plate")
        const decisions = [
            ["chooseAction", {options:[{responseId:"cast", kind:"cast", cardId:"hand-0", label:"Cast"},
                {responseId:"mana", kind:"activateAbility", cardId:"land", label:"Plains"},
                {responseId:"$pass", kind:"pass", label:"Pass"}]}],
            ["payManaCost", {title:"Pay Mana Cost: {2}{W}{W}", detail:"Spell {2}{W}{W}",
                options:[{responseId:"pay-0", kind:"activateAbility", cardId:"land", label:"Plains"},
                    {responseId:"pay-1", kind:"activateAbility", cardId:"labyrinth", label:"Ugin's Labyrinth"},
                    {responseId:"$auto-pay", kind:"pay", label:"Auto-pay"},
                    {responseId:"$cancel", kind:"cancel", label:"Cancel"}]}],
            ["chooseBoardTargets", {minSelections:1, maxSelections:1,
                targets:[{responseId:"target", kind:"card", objectId:"own-0", label:"Bear 0"},
                    {responseId:"player", kind:"player", seat:1, label:"Bob"}]}],
            ["chooseNumber", {title:"Choose X", minNumber:0, maxNumber:5}],
            ["chooseFromSelection", {title:"Choose a mode", minChoiceTotal:1, maxChoiceTotal:1,
                choices:[0, 1, 2, 3].map(i => ({responseId:"choice:" + i, label:"Mode " + i,
                    weight:1, canRepeat:false}))}],
            ["chooseAttackers", {
                combatSources:[0, 1, 2, 3, 4, 5].map(i => ({responseId:"source-" + i, objectId:"own-" + i,
                    label:"Bear " + i, validTargetIds:["defender"], maxAssignments:1})),
                combatTargets:[{responseId:"defender", kind:"player", seat:1, label:"Bob", maxAssignments:6}]}]
        ]
        for (const [kind, extra] of decisions) {
            prompt(kind, extra)
            waitForRendering(table)
            compare(boardGeometry(ids), baseline, kind + " must not move battlefield cards")
            verifyBattlefieldClearOfOverlay(ownLanes, reservation, "the decision reservation during " + kind)
            verifyBattlefieldClearOfOverlay(ownLanes, plateRect, "the player plate during " + kind)
        }
        surveilPrompt()
        waitForRendering(table)
        compare(boardGeometry(ids), baseline, "Overlay decisions must not move battlefield cards")
    }
    function test_declaredAttackKeepsTheRestOfTheBoardStill() {
        window.width = 1920; window.height = 1010
        const state = stillBoard()
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        const ids = ["own-1", "own-5", "land", "land-2", "labyrinth", "walker", "opponent"]
        const baseline = boardGeometry(ids)
        const attacker = state.zones[4].cards.find(card => card.id === "own-0")
        attacker.attacking = true
        attacker.attackingPlayer = 1
        state.step = "declare_attackers"
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        compare(boardGeometry(ids), baseline, "One attacker must not reflow the other cards")
        verify(item("forgeCardInteractionHint-own-0").text.indexOf("Attacking") === 0)
    }

    function test_offboardTargetsKeepCandidatesAndActionsVisible_data() {
        return [{tag:"maximized", w:1920, h:1011, scale:1, fullCard:true},
            {tag:"scaled", w:1280, h:800, scale:1.35, fullCard:true},
            {tag:"short", w:900, h:400, scale:1.35, fullCard:false}]
    }
    function test_offboardTargetsKeepCandidatesAndActionsVisible(data) {
        window.width = data.w; window.height = data.h; Theme.uiScale = data.scale
        verify(testRulesPrompt.applySnapshot(stillBoard()))
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        const baseline = boardGeometry(["own-0", "land", "opponent"])
        prompt("chooseBoardTargets", {
            title:"Choose target instant card in a graveyard", minSelections:1, maxSelections:2,
            targets:[{responseId:"opaque-graveyard-target", kind:"card", objectId:"graveyard-opt",
                label:"Opt", name:"Opt", setCode:"XLN", collectorNumber:"65"},
                {responseId:"opaque-board-target", kind:"card", objectId:"own-0", label:"Bear 0"}]})
        verify(waitForPolish(window))
        waitForRendering(table)
        const scroll = item("rulesPromptScroll"), panel = item("rulesPromptPanel")
        const candidate = item("rulesTarget-opaque-graveyard-target")
        const label = item("rulesTargetLabel-opaque-graveyard-target")
        const confirm = item("rulesConfirmTargets"), footer = item("rulesTargetSelectionFooter")
        const initialAction = confirm.mapToItem(panel, 0, 0)
        const candidateTop = candidate.mapToItem(scroll, 0, 0)
        console.info("Offboard target geometry", data.tag, JSON.stringify({
            dockHeight:item("rulesDecisionDock").height, scrollHeight:scroll.height,
            candidateY:candidateTop.y, candidateHeight:candidate.height, footerHeight:footer.height}))
        if (data.fullCard) {
            verify(candidateTop.y >= 0 && candidateTop.y + candidate.height <= scroll.height + 0.5,
                   "The whole first offboard candidate must fit before any scrolling")
            const labelTop = label.mapToItem(scroll, 0, 0)
            verify(labelTop.y >= 0 && labelTop.y + label.height <= scroll.height + 0.5)
            compare(label.text, "Opt")
            verify(!label.truncated, "The target name must be readable before hovering")
        } else {
            verify(scroll.contentHeight > scroll.height, "A short window must retain a scrollable body")
            scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height)
            waitForRendering(table)
        }
        compare(boardGeometry(["own-0", "land", "opponent"]), baseline,
                "A mixed board/offboard decision must not move the battlefield")
        compare(confirm.mapToItem(panel, 0, 0), initialAction,
                "Scrolling candidates must leave the confirmation action fixed")
        const footerTop = footer.mapToItem(panel, 0, 0)
        verify(footerTop.y >= 0 && footerTop.y + footer.height <= panel.height + 0.5)
        const toggle = item("forgeDecisionCollapse"), dock = item("rulesDecisionDock")
        verify(toggle.visible, "An expanded target list must let players reveal the board underneath")
        mouseClick(toggle)
        verify(dock.collapsed)
        compare(boardGeometry(["own-0", "land", "opponent"]), baseline)
        mouseClick(toggle)
        verify(!dock.collapsed)
        verify(waitForPolish(window))
        waitForRendering(table)
        const visibleTop = Math.max(0, -candidate.mapToItem(scroll, 0, 0).y)
        const visibleBottom = Math.min(candidate.height, scroll.height - candidate.mapToItem(scroll, 0, 0).y)
        verify(visibleBottom > visibleTop, "The offboard target must retain a visible click area")
        mouseClick(candidate, candidate.width / 2, (visibleTop + visibleBottom) / 2)
        compare(table.interaction.selectedTargetIds, {"opaque-graveyard-target":true})
        verify(confirm.enabled)
        mouseClick(confirm)
        compare(transport.responses, [{id:table.rulesSession.promptId, response:"$submit",
            targets:["opaque-graveyard-target"]}])
    }

    function test_boardDecisionsFitReservation_data() {
        const sizes = [{tag:"desktop", w:1600, h:1000, scale:1}, {tag:"wide", w:1920, h:1010, scale:1},
            {tag:"laptop", w:1280, h:800, scale:1}, {tag:"compact", w:900, h:620, scale:1},
            {tag:"scaled", w:1280, h:800, scale:1.35}]
        const rows = []
        for (const size of sizes)
            for (const kind of ["priority", "payment", "targets", "attackers", "blockers"])
                rows.push(Object.assign({}, size, {tag:size.tag + "-" + kind, kind:kind}))
        return rows
    }
    function test_boardDecisionsFitReservation(data) {
        window.width = data.w; window.height = data.h; Theme.uiScale = data.scale
        verify(testRulesPrompt.applySnapshot(snapshot(3, 6, true)))
        if (data.kind === "priority") {
            prompt("chooseAction", {options:[{responseId:"cast", kind:"cast", cardId:"hand-0", label:"Cast"},
                {responseId:"$pass", kind:"pass", label:"Pass"}]})
        } else if (data.kind === "payment") {
            prompt("payManaCost", {title:"Pay Mana Cost: {2}{W}{W}", detail:"Spell {2}{W}{W}",
                options:[{responseId:"pay-0", kind:"activateAbility", cardId:"land", label:"Plains"},
                    {responseId:"$pay", kind:"pay", label:"Confirm payment"},
                    {responseId:"$auto-pay", kind:"pay", label:"Auto-pay"},
                    {responseId:"$cancel", kind:"cancel", label:"Cancel"}]})
        } else if (data.kind === "targets") {
            prompt("chooseBoardTargets", {minSelections:1, maxSelections:2,
                targets:[{responseId:"target", kind:"card", objectId:"own-0", label:"Bear 0"},
                    {responseId:"player", kind:"player", seat:1, label:"Bob"}]})
        } else {
            const attackers = data.kind === "attackers"
            prompt(attackers ? "chooseAttackers" : "chooseBlockers", {
                combatSources:[0, 1, 2, 3, 4, 5].map(i => ({responseId:"source-" + i, objectId:"own-" + i,
                    label:"Bear " + i, name:"Bear " + i, validTargetIds:["defender"], maxAssignments:1})),
                combatTargets:[{responseId:"defender", kind:attackers ? "player" : "attacker",
                    objectId:attackers ? "" : "opponent", seat:attackers ? 1 : -1, label:"Bob",
                    minAssignments:0, maxAssignments:8}]})
        }
        waitForRendering(table)
        const dock = item("rulesDecisionDock"), cap = table.presentation.boardDecisionHeight
        verify(dock.height <= cap + 0.5,
               data.kind + " occupies " + dock.height + " of " + cap)
        compare(dock.height, Math.min(dock.implicitHeight, cap))
        if (["attackers", "blockers"].includes(data.kind)) {
            const scroll = item("rulesPromptScroll"), confirm = item("rulesConfirmCombat-" + data.kind)
            const footer = item("rulesCombatSelectionFooter"), panel = item("rulesPromptPanel")
            const initial = confirm.mapToItem(panel, 0, 0)
            const top = footer.mapToItem(panel, 0, 0), bottom = footer.mapToItem(panel, footer.width, footer.height)
            verify(top.x >= 0 && top.y >= 0 && bottom.x <= panel.width + 0.5 && bottom.y <= panel.height + 0.5,
                   "The whole combat footer must fit the capped decision panel")
            const actionTop = confirm.mapToItem(footer, 0, 0), actionBottom = confirm.mapToItem(footer, confirm.width, confirm.height)
            verify(actionTop.x >= 0 && actionTop.y >= 0 && actionBottom.x <= footer.width + 0.5 && actionBottom.y <= footer.height + 0.5)
            scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height)
            waitForRendering(table)
            compare(confirm.mapToItem(panel, 0, 0), initial, "Scrolling cannot move the declaration")
            verify(confirm.enabled)
            mouseClick(confirm)
            compare(transport.responses.length, 1)
            compare(transport.responses[0].assignments, [])
        }
        verify(dock.y >= table.presentation.height - 12 * table.presentation.unit - cap - 0.5)
        compare(item("forgeDecisionCollapse").visible,
            data.kind !== "priority" && dock.targetHeight > table.presentation.dockReservedHeight)
        compare(item("forgeTurnIndicator").visible, data.kind === "priority")
        compare(item("rulesActionBar").visible, data.kind !== "payment")
    }
    function test_partialBlockRecoveryFitsRealDock_data() {
        const rows = []
        for (const language of ["en", "zh", "zh_TW", "ja", "fr", "de", "es", "it", "pt_BR"])
            for (const size of [{tag:"compact", w:900, h:620, scale:1},
                               {tag:"scaled", w:1280, h:800, scale:1.35},
                               {tag:"compact-scaled", w:900, h:620, scale:1.35}])
                rows.push(Object.assign({}, size, {tag: language + "-" + size.tag, language: language}))
        return rows
    }
    function test_partialBlockRecoveryFitsRealDock(data) {
        window.width = data.w; window.height = data.h; Theme.uiScale = data.scale
        testTranslations.setLanguage(data.language)
        const state = snapshot(0, 2, true)
        state.step = "declare_blockers"
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseBlockers", {
            title:"Declare blockers", detail:"Assign each blocker to the attackers it can legally block.",
            combatSources:[0, 1].map(i => ({responseId:"source-" + i, objectId:"own-" + i,
                label:"Bear " + i, name:"Grizzly Bears", validTargetIds:["defender"], maxAssignments:1})),
            combatTargets:[{responseId:"defender", kind:"attacker", objectId:"opponent", label:"Rust Harvester",
                minAssignments:2, maxAssignments:2}]})
        verify(table.combatInteraction.activate("own-0"))
        verify(waitForPolish(window))
        waitForRendering(table)
        const scroll = item("rulesPromptScroll"), panel = item("rulesPromptPanel")
        const footer = item("rulesCombatSelectionFooter"), confirm = item("rulesConfirmCombat-blockers")
        function wholeControl(control, boundary) {
            const point = control.mapToItem(boundary, 0, 0)
            verify(point.x >= -0.5 && point.y >= -0.5
                   && point.x + control.width <= boundary.width + 0.5
                   && point.y + control.height <= boundary.height + 0.5,
                   control.objectName + " " + JSON.stringify(point) + " " + control.width + "x" + control.height
                   + " does not fit " + boundary.width + "x" + boundary.height)
        }
        wholeControl(footer, panel)
        wholeControl(confirm, footer)
        const count = item("rulesCombatSelectionCount")
        wholeControl(count, footer)
        verify(count.paintedWidth <= count.width + 1, "The complete translated count must fit")
        wholeControl(item("rulesBlockWithAll"), footer)
        const reason = item("rulesCombatMinimumReason"), clear = item("rulesCombatClear-blockers")
        verify(reason.visible && reason.text.includes("Rust Harvester"))
        wholeControl(reason, scroll)
        wholeControl(clear, scroll)
        verify(!confirm.enabled && clear.enabled)
        const initial = confirm.mapToItem(panel, 0, 0)
        mouseClick(clear)
        compare(Object.keys(table.combatInteraction.assignments).length, 0)
        verify(confirm.enabled)
        mouseClick(item("rulesBlockWithAll"))
        compare(Object.keys(table.combatInteraction.assignments).length, 2)
        verify(confirm.enabled)
        compare(confirm.mapToItem(panel, 0, 0), initial)
        mouseClick(confirm)
        compare(transport.responses.length, 1)
        compare(transport.responses[0].assignments, [
            {sourceId:"source-0", targetId:"defender"}, {sourceId:"source-1", targetId:"defender"}])
    }

    function test_modelStatusYieldsToOpenDecision() {
        room.aiSource = "online"; room.aiStatus = {state:"thinking"}
        const status = item("modelOpponentStatus")
        verify(item("rulesDecisionDock").showsBody)
        verify(!status.visible)
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        verify(status.visible)
        room.aiStatus = {state:"paused", code:"provider_error"}
        surveilPrompt()
        verify(status.visible, "A paused model stays visible during decisions")
        verify(item("modelOpponentRetry").visible)
        room.aiSource = ""; room.aiStatus = ({})
    }

    function test_overlayDecisionCanBeHiddenWithoutMovingCards() {
        verify(testRulesPrompt.applySnapshot(stillBoard()))
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        const ids = ["own-0", "own-5", "land", "labyrinth", "walker", "opponent"]
        const baseline = boardGeometry(ids)
        const dock = item("rulesDecisionDock"), reservation = table.presentation.dockReservation
        const toggle = item("forgeDecisionCollapse")
        verify(!toggle.visible)
        surveilPrompt()
        verify(dock.y < reservation.y, "A tall non-board decision overlays the battlefield")
        compare(boardGeometry(ids), baseline)
        verify(toggle.visible)
        compare(toggle.text, "Hide choice")
        mouseClick(toggle)
        waitForRendering(table)
        verify(dock.collapsed)
        verify(!item("rulesDecisionBody").visible)
        verify(dock.height <= reservation.height + 0.5)
        verify(item("forgeTurnIndicator").visible)
        compare(toggle.text, "Show choice")
        compare(boardGeometry(ids), baseline)
        mouseClick(toggle)
        waitForRendering(table)
        verify(!dock.collapsed)
        verify(item("rulesScalarChoice-choice:1").visible)
        mouseClick(toggle)
        waitForRendering(table)
        verify(dock.collapsed)
        surveilPrompt()
        verify(!dock.collapsed, "A new decision is shown again")
        compare(transport.responses.length, 0)
    }
    function test_choiceToggleKeepsMultiplayerZonesReachable_data() {
        return [{tag:"four-normal", seats:[0,1,2,3], width:1920, height:1011, scale:1.2},
            {tag:"four-scaled", seats:[0,1,2,3], width:1920, height:1011, scale:1.8},
            {tag:"four-compact", seats:[0,1,2,3], width:900, height:620, scale:1.35},
            {tag:"three-scaled", seats:[0,1,2], width:1280, height:800, scale:1.35}]
    }
    function test_choiceToggleKeepsMultiplayerZonesReachable(data) {
        setupNativePermanentRegions(data.seats, data)
        const ids = data.seats.map(seat => "z-creature-" + seat)
        const baseline = boardGeometry(ids)
        surveilPrompt()
        const dock = item("rulesDecisionDock"), toggle = item("forgeDecisionCollapse")
        verify(toggle.visible)
        function checkControls() {
            verify(waitForPolish(window)); verify(waitForRendering(table))
            verify(toggle.x >= 0 && toggle.y >= 0
                && toggle.x + toggle.width <= table.presentation.width
                && toggle.y + toggle.height <= table.presentation.height)
            for (const seat of data.seats)
                for (const zone of ["graveyard", "exile", "command"])
                    verify(!rectsOverlap(toggle, item("forgeSeatZone-" + seat + "-" + zone)),
                        "The choice toggle must not cover seat " + seat + " " + zone)
            compare(boardGeometry(ids), baseline, "Moving the toggle must not reflow permanents")
        }
        checkControls()
        mouseClick(toggle)
        verify(dock.collapsed)
        checkControls()
        const seat = data.seats.length === 4 ? 1 : 0
        const popup = item("forgeZonePopup")
        for (const zone of ["graveyard", "exile", "command"]) {
            mouseClick(item("forgeSeatZone-" + seat + "-" + zone))
            tryCompare(popup, "visible", true)
            compare(popup.zone, zone)
            compare(popup.ownerSeat, seat)
            verify(dock.collapsed, "Browsing a public zone does not restore the choice")
            popup.close()
            tryCompare(popup, "visible", false)
        }
        mouseClick(toggle)
        verify(!dock.collapsed)
        checkControls()
        compare(transport.responses.length, 0)
    }
    function test_combatListMayOverlayTheBattlefield() {
        verify(testRulesPrompt.applySnapshot(stillBoard()))
        combat("chooseAttackers")
        const ids = ["own-0", "own-5", "land", "labyrinth", "walker", "opponent"]
        const baseline = boardGeometry(ids)
        const dock = item("rulesDecisionDock"), reservation = table.presentation.dockReservation
        verify(dock.height <= table.presentation.boardDecisionHeight + 0.5)
        mouseClick(item("rulesCombatDetails-attackers"))
        tryVerify(() => dock.listChoiceShown)
        waitForRendering(table)
        verify(dock.y < reservation.y, "The explicit assignment list may extend above the reservation")
        compare(dock.height, dock.implicitHeight)
        compare(boardGeometry(ids), baseline)
        const confirm = item("rulesConfirmCombat-attackers"), point = confirm.mapToItem(table, 0, 0)
        verify(point.y >= dock.y && point.y + confirm.height <= dock.y + dock.height + 1)
    }
    function test_hiddenChoiceSurvivesBoardUpdatesAndResize() {
        verify(testRulesPrompt.applySnapshot(stillBoard()))
        surveilPrompt()
        const dock = item("rulesDecisionDock"), toggle = item("forgeDecisionCollapse")
        mouseClick(toggle)
        waitForRendering(table)
        verify(dock.collapsed)
        const state = stillBoard()
        state.players[1].life = 17
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        verify(dock.collapsed, "A board update keeps the choice hidden")
        window.width = 1280; window.height = 800
        waitForRendering(table)
        verify(dock.collapsed, "Resizing keeps the choice hidden")
        verify(toggle.visible)
        verify(toggle.x + toggle.width <= dock.x)
        verify(dock.height <= table.presentation.dockReservation.height + 0.5)
        compare(transport.responses.length, 0)
    }
    function test_gameOverShowsHiddenChoice() {
        verify(testRulesPrompt.applySnapshot(stillBoard()))
        surveilPrompt()
        const dock = item("rulesDecisionDock")
        mouseClick(item("forgeDecisionCollapse"))
        waitForRendering(table)
        verify(dock.collapsed)
        const state = stillBoard()
        state.gameOver = true; state.winnerSeat = 1
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        verify(!dock.collapsed && dock.showsBody, "The result is never hidden behind Show choice")
    }
    function test_multiplayerDecisionsCoverWithoutMovingCards() {
        room.format = "edh"; room.deckFormat = "commander"; room.maxSeats = 4
        verify(testRulesPrompt.applySnapshot(edhSnapshot([0, 1, 2], 0)))
        tryCompare(table.presentation, "multiplayer", true)
        const lane = item("forgeCreatures-0")
        const width = lane.width
        surveilPrompt()
        const dock = item("rulesDecisionDock")
        compare(lane.width, width, "A multiplayer decision does not narrow a lane")
        verify(!table.presentation.reservesDock)
        verify(item("forgeDecisionCollapse").visible)
        mouseClick(item("forgeDecisionCollapse"))
        waitForRendering(table)
        verify(dock.collapsed)
        compare(lane.width, width)
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        verify(dock.height <= table.presentation.dockReservedHeight + 0.5)
        compare(lane.width, width)
    }
    function test_recentActionsStayVisibleWithoutTheLog() {
        verify(testRulesPrompt.applySnapshot(snapshot()))
        verify(!findChild(table, "forgeRecentActions").visible)
        testGameTable.applySnapshot({log:[
            {id:1, kind:"play", text:"Alice plays a Forest", seat:0},
            {id:2, kind:"cast", text:"Alice casts Grizzly Bears", seat:0}]})
        const strip = item("forgeRecentActions")
        verify(strip.visible)
        verify(item("forgeRecentActionText").text.includes("Forest"))
        verify(item("forgeRecentActionText").text.includes("Grizzly Bears"))
        testGameTable.applySnapshot({log:[
            {id:1, kind:"rules_phase", text:"Turn 5: Audit Player 1 (begin_combat).", seat:0},
            {id:2, kind:"rules_tap", text:"Audit Player 1: Forest tapped.", seat:0}]})
        const phase = I18n.gameLog("rules_phase", "Turn 5: Audit Player 1 (begin_combat).", name => name, "")
        const tapped = I18n.gameLog("rules_tap", "Audit Player 1: Forest tapped.", name => name, "")
        compare(item("forgeRecentActionText").text, phase + "   ·   " + tapped)
        verify(!item("forgeRecentActionText").text.includes("begin_combat"))
        mouseClick(strip)
        verify(table.showGameLogRail)
        verify(!findChild(table, "forgeRecentActions").visible)
        table.setGameLogVisible(false)
        verify(item("forgeRecentActions").visible)
        testGameTable.applySnapshot({log:[]})
    }
    function test_recentActionsDoNotCoverBattlefield_data() {
        return [
            {tag:"duel-maximized", seats:2, width:1920, height:1011, scale:1.25},
            {tag:"duel-compact", seats:2, width:1100, height:760, scale:1.35},
            {tag:"three-player", seats:3, width:1280, height:720, scale:1},
            {tag:"four-player", seats:4, width:1920, height:1011, scale:1.25}
        ]
    }
    function test_recentActionsDoNotCoverBattlefield(data) {
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        room.format = data.seats > 2 ? "edh" : "modern"; room.maxSeats = data.seats
        testGameTable.applySnapshot({log:[]})
        const state = data.seats > 2 ? edhSnapshot([0,1,2,3].slice(0, data.seats), 0) : snapshot(1, 3, true)
        state.prioritySeat = 0
        verify(testRulesPrompt.applySnapshot(state))
        table.priority.setFullControl(true)
        const id = data.seats > 2 ? "creature-0-0" : "own-0"
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        const face = item("forgeCard-" + id), strip = item("forgeRecentActions")
        const before = face.mapToItem(table.presentation, 0, 0)
        const size = Qt.size(face.width, face.height)
        testGameTable.applySnapshot({log:[{id:1, kind:"cast", text:"A creature enters the battlefield", seat:0}]})
        tryCompare(strip, "visible", true)
        compare(face.mapToItem(table.presentation, 0, 0), before)
        compare(Qt.size(face.width, face.height), size)
        // The recent-action summary clears painted faces. The translucent
        // phase strip keeps its public anchor rather than reserving a row.
        const stripRect = strip.mapToItem(table.presentation, 0, 0, strip.width, strip.height)
        assertPublicPhaseAnchor()
        function overlaps(a, b) {
            return a.x < b.x + b.width - 0.1 && a.x + a.width > b.x + 0.1
                && a.y < b.y + b.height - 0.1 && a.y + a.height > b.y + 0.1
        }
        for (const zone of state.zones.filter(zone => zone.zone === "battlefield")) {
            for (const card of zone.cards) {
                const art = item("forgeCardFace-" + card.id)
                const artRect = art.mapToItem(table.presentation, 0, 0, art.width, art.height)
                verify(!overlaps(stripRect, artRect), "Recent actions must leave " + card.id + " clear")
            }
        }
        testGameTable.applySnapshot({log:[{id:2, kind:"move", text:"Another public action", seat:0}]})
        compare(face.mapToItem(table.presentation, 0, 0), before)
        mouseClick(strip)
        verify(table.showGameLogRail)
        compare(face.mapToItem(table.presentation, 0, 0), before)
        table.setGameLogVisible(false)
        compare(face.mapToItem(table.presentation, 0, 0), before)
        prompt("chooseBoardTargets", {minSelections:1, maxSelections:1,
            targets:[{responseId:"target-creature", kind:"card", objectId:id, label:"Creature"}]})
        mouseClick(face, face.width / 2, 5)
        compare(transport.responses.length, 1, "Clicking the card title must select the card, not open the log")
        compare(transport.responses[0].targets, ["target-creature"])
        if (data.seats === 2) {
            state.prioritySeat = 1
            verify(testRulesPrompt.applySnapshot(state))
            prompt("", {pending:false, supported:false})
            verify(item("forgeOpponentDeciding").visible)
            verify(!strip.visible, "Opponent status temporarily shares the fixed public-status row")
            compare(face.mapToItem(table.presentation, 0, 0), before)
            state.prioritySeat = 0
            verify(testRulesPrompt.applySnapshot(state))
            prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
            verify(strip.visible)
            compare(face.mapToItem(table.presentation, 0, 0), before)
        }
        testGameTable.applySnapshot({log:[]})
    }

    function test_priorityGlowReplacesHandRise() {
        const hand = item("forgeHand"), glow = item("forgeHandPriorityGlow")
        const top = table.presentation.handTop
        compare(hand.y, top)
        compare(glow.opacity, 0)
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        compare(hand.y, top)
        compare(glow.opacity, 1)
        verify(glow.visible)
        prompt("payManaCost", {title:"Pay Mana Cost: {W}", options:[{responseId:"pay", kind:"activateAbility",
            cardId:"land", label:"Plains"}, {responseId:"$cancel", kind:"cancel", label:"Cancel"}]})
        compare(hand.y, top)
        compare(glow.opacity, 0)
        verify(!glow.visible)
    }

    function test_pendingResponseKeepsDimmedHighlights() {
        prompt("chooseAction", {options:[{responseId:"play", kind:"playLand", cardId:"hand-0", label:"Play"},
            {responseId:"mana", kind:"activateAbility", cardId:"land", label:"Plains"},
            {responseId:"$pass", kind:"pass", label:"Pass"}]})
        const land = item("forgeCard-land"), hand = item("forgeHandSurface-hand-0"), cue = item("forgeWaitingCue")
        verify(land.offered && land.actionable && !land.waiting)
        const outline = findChild(land, "forgeCardStateOutline-land")
        verify(outline.visible && outline.border.color.a > 0)
        const readyAlpha = outline.border.color.a
        mouseClick(land)
        compare(transport.responses.length, 1)
        compare(transport.responses[0].response, "mana")
        verify(land.submitted)
        verify(findChild(land, "forgeCardSubmitted-land").visible)
        verify(!findChild(hand, "forgeCardSubmitted-hand-0").visible)
        verify(land.waiting && !land.actionable)
        verify(hand.offered && hand.waiting && !hand.actionable)
        verify(outline.visible && outline.border.color.a > 0 && outline.border.color.a < readyAlpha,
               "Pending outlines dim instead of disappearing")
        verify(!cue.visible)
        mouseClick(item("forgeHandCard-hand-0"))
        compare(transport.responses.length, 1, "Blocked clicks are never sent")
        verify(cue.visible)
        compare(item("forgeWaitingCueText").text, "Waiting for the game")
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        verify(!land.submitted && !land.offered)
        verify(!findChild(land, "forgeCardSubmitted-land").visible)
        verify(!cue.visible)
    }

    function test_blockedCombatAndSeatClicksShowWaitingCue() {
        combat("chooseAttackers")
        const source = item("forgeCard-own-0"), cue = item("forgeWaitingCue")
        mouseClick(item("rulesConfirmCombat-attackers"))
        compare(transport.responses.length, 1)
        verify(source.offered && source.waiting && !source.actionable)
        mouseClick(source)
        compare(table.combatInteraction.selectedSource, "")
        verify(cue.visible)
        prompt("chooseBoardTargets", {minSelections:1, maxSelections:1,
            targets:[{responseId:"player", kind:"player", seat:1, label:"Bob"}]})
        verify(!cue.visible)
        const plate = item("rulesPlayerTarget1")
        verify(plate.actionable)
        mouseClick(plate)
        compare(transport.responses.length, 2)
        verify(plate.offered && plate.waiting && !plate.actionable)
        mouseClick(plate)
        compare(transport.responses.length, 2)
        verify(cue.visible)
    }
    function test_keyboardActivationWhilePendingShowsWaitingCue() {
        prompt("chooseAction", {options:[{responseId:"mana", kind:"activateAbility", cardId:"land", label:"Plains"},
            {responseId:"$pass", kind:"pass", label:"Pass"}]})
        const land = item("forgeCard-land"), cue = item("forgeWaitingCue")
        land.forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(transport.responses.length, 1)
        verify(land.waiting && !cue.visible)
        keyClick(Qt.Key_Return)
        compare(transport.responses.length, 1, "Blocked keyboard activation is never sent")
        verify(cue.visible)
    }

    function test_hiddenCombatListCanBeShownAgain() {
        verify(testRulesPrompt.applySnapshot(stillBoard()))
        combat("chooseAttackers")
        const dock = item("rulesDecisionDock"), toggle = item("forgeDecisionCollapse")
        mouseClick(item("rulesCombatDetails-attackers"))
        tryVerify(() => dock.listChoiceShown)
        waitForRendering(table)
        verify(toggle.visible)
        mouseClick(toggle)
        waitForRendering(table)
        verify(dock.collapsed)
        verify(toggle.visible, "Show choice stays after hiding an open combat list")
        compare(toggle.text, "Show choice")
        mouseClick(toggle)
        waitForRendering(table)
        verify(!dock.collapsed)
        verify(item("rulesConfirmCombat-attackers").visible)
        compare(transport.responses.length, 0)
    }
    function test_pendingPaymentKeepsManaColor() {
        prompt("payManaCost", {title:"Pay Mana Cost: {W}",
            options:[{responseId:"pay", kind:"activateAbility", cardId:"land", label:"Plains"},
                {responseId:"$cancel", kind:"cancel", label:"Cancel"}]})
        const land = item("forgeCard-land")
        const outline = findChild(land, "forgeCardStateOutline-land")
        compare(outline.border.color, "#e1bd7f")
        mouseClick(land)
        compare(transport.responses.length, 1)
        compare(outline.border.color, Theme.withAlpha("#e1bd7f", 0.5))
    }
    function test_tappedCardDimsTheArtAndShowsAMark() {
        const state = snapshot(1, 0)
        const bear = card("land", 0, "Grizzly Bears", true)
        bear.tapped = true
        state.zones[4].cards = [bear]
        state.zones[4].count = 1
        verify(testRulesPrompt.applySnapshot(state))
        const tapped = item("forgeCard-land")
        compare(tapped.rotation, 0)
        compare(item("forgeCardTappedShade-land").opacity, tapped.tappedShade)
        const mark = item("forgeCardTappedMark-land")
        verify(mark.visible)
        const face = item("forgeCardFace-land")
        verify(mark.width >= Math.min(face.width, face.height) * 0.5)
        verify(item("forgeCardStats-land").visible)
        bear.tapped = false
        verify(testRulesPrompt.applySnapshot(state))
        verify(!item("forgeCardTappedShade-land").visible)
        verify(!item("forgeCardTappedMark-land").visible)
    }
    function test_tappedPileUndoesTheSpentLand_data() {
        return [{tag:"floating-before-cast", kind:"chooseAction"},
            {tag:"unfinished-payment", kind:"payManaCost"}]
    }
    function test_tappedPileUndoesTheSpentLand(data) {
        const state = snapshot(1, 0)
        const spent = card("land-a", 0, "Plains", false)
        spent.tapped = true
        state.zones[4].cards = [spent, card("land-b", 0, "Plains", false)]
        state.zones[4].count = 2
        verify(testRulesPrompt.applySnapshot(state))
        prompt(data.kind, {title:"Choose", options:[
            {responseId:"pay-b", kind:"activateAbility", cardId:"land-b", label:"Plains"},
            {responseId:"undo-a", kind:"undoMana", cardId:"land-a", label:"Undo"}]})
        tryCompare(item("forgeOwnLands"), "stackCount", 2)
        const ready = item("forgeCard-land-b"), tapped = item("forgeCard-land-a")
        verify(tapped.card.stackIndex > ready.card.stackIndex, "Spent copies follow the ready pile")
        compare(tapped.card.stackSize, 1)
        mouseClick(tapped)
        compare(transport.responses[0].response, "undo-a")
    }
    function test_closedTappedPileShowsItsBuriedManaUndo_data() {
        return [{tag:"floating-before-cast", kind:"chooseAction"},
            {tag:"unfinished-payment", kind:"payManaCost"}]
    }
    function test_closedTappedPileShowsItsBuriedManaUndo(data) {
        landBoard(["land-a", "land-b"], ["land-a", "land-b"])
        prompt(data.kind, {options:[
            {responseId:"undo-a", kind:"undoMana", cardId:"land-a", label:"Undo mana"}]})
        const lane = item("forgeOwnLands"), front = item("forgeCard-land-b")
        tryCompare(lane, "stackCount", 1)
        verify(front.card.stackFront && !item("forgeCard-land-a").card.stackFront)
        const position = front.mapToItem(lane, 0, 0)
        verify(front.undoingMana && front.actionable, "A buried legal source remains discoverable on the closed pile")
        compare(item("forgeCardInteractionHint-land-b").text, "Undo mana")
        verify(!item("forgeCardInteractionHint-land-a").visible, "The pile has only one visible hint")
        mouseClick(front)
        compare(transport.responses, [{id:serial, response:"undo-a"}])
        verify(front.waiting && front.submitted)
        compare(front.mapToItem(lane, 0, 0), position, "An undo offer/response never moves the pile")
    }
    function test_pileEnterFansAndArrowsMoveFocus() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, 2)))
        const lane = item("forgeOwnCreatures")
        const front = item("forgeCard-own-1")
        tryVerify(() => lane.visibleCards.length === 2 && lane.stackCount === 1
                  && front.card.stackSize === 2)
        front.forceActiveFocus()
        verify(front.activeFocus)
        keyClick(Qt.Key_Return)
        compare(item("forgeOwnCreatures").fannedStack, 0)
        keyClick(Qt.Key_Left)
        verify(item("forgeCard-own-0").activeFocus)
    }
    function test_singleDestinationAttackAssignsInOneClick() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, 1)))
        prompt("chooseAttackers", {
            combatSources:[{responseId:"source-0", objectId:"own-0", label:"Bear", name:"Grizzly Bears",
                validTargetIds:["defender"], maxAssignments:1}],
            combatTargets:[{responseId:"defender", kind:"player", seat:1, label:"Opponent", maxAssignments:1}]
        })
        mouseClick(item("forgeCard-own-0"))
        compare(table.combatInteraction.assignments["source-0"], "defender")
        compare(table.combatInteraction.selectedSource, "")
        mouseClick(item("forgeCard-own-0"))
        compare(table.combatInteraction.assignments["source-0"], undefined)
    }
    function test_eitherAttackerCanBeBlockedFromTheBoard() {
        const state = snapshot(1, 2)
        state.zones[5].cards = [card("opponent", 1, "Grizzly Bears", true), card("opponent-b", 1, "Goblin", true)]
        state.zones[5].count = 2
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseBlockers", {
            combatSources:[0, 1].map(i => ({responseId:"block-" + i, objectId:"own-" + i,
                label:"Bear", name:"Grizzly Bears", validTargetIds:["atk-a", "atk-b"], maxAssignments:1})),
            combatTargets:[
                {responseId:"atk-a", kind:"attacker", objectId:"opponent", label:"Attacker",
                    name:"Grizzly Bears", maxAssignments:2},
                {responseId:"atk-b", kind:"attacker", objectId:"opponent-b", label:"Goblin",
                    name:"Goblin", maxAssignments:2}]
        })
        verify(table.combatInteraction.offered("opponent"))
        verify(table.combatInteraction.offered("opponent-b"))
        mouseClick(item("forgeCard-opponent-b"))
        compare(table.combatInteraction.pendingAttacker, "opponent-b")
        mouseClick(item("forgeCard-own-0"))
        compare(table.combatInteraction.assignments["block-0"], "atk-b")
        mouseClick(item("forgeCard-own-1"))
        mouseClick(item("forgeCard-opponent"))
        compare(table.combatInteraction.assignments["block-1"], "atk-a")
    }
    function test_escapeCancelsAttackerFirstSelectionWithoutClearingBlocks() {
        const state = snapshot(1, 2)
        state.zones[5].cards = [card("opponent", 1, "Grizzly Bears", true), card("opponent-b", 1, "Goblin", true)]
        state.zones[5].count = 2
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseBlockers", {
            combatSources:[0, 1].map(i => ({responseId:"block-" + i, objectId:"own-" + i,
                label:"Bear", name:"Grizzly Bears", validTargetIds:["atk-a", "atk-b"], maxAssignments:1})),
            combatTargets:[
                {responseId:"atk-a", kind:"attacker", objectId:"opponent", label:"Bear", maxAssignments:2},
                {responseId:"atk-b", kind:"attacker", objectId:"opponent-b", label:"Goblin", maxAssignments:2}]
        })
        table.forceActiveFocus()
        mouseClick(item("forgeCard-opponent"))
        mouseClick(item("forgeCard-own-0"))
        compare(table.combatInteraction.assignments["block-0"], "atk-a")
        mouseClick(item("forgeCard-opponent-b"))
        compare(table.combatInteraction.pendingAttacker, "opponent-b")
        keyClick(Qt.Key_Escape)
        compare(table.combatInteraction.pendingAttacker, "")
        compare(table.combatInteraction.assignments["block-0"], "atk-a")
        mouseClick(item("forgeCard-own-1"))
        compare(table.combatInteraction.selectedSource, "block-1")
        compare(table.combatInteraction.selectedTargets("block-1"), [])
        compare(transport.responses.length, 0)
    }
    function test_singleAttackerBlockAssignsInOneClick() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, 1)))
        prompt("chooseBlockers", {
            combatSources:[{responseId:"block-0", objectId:"own-0", label:"Bear", name:"Grizzly Bears",
                validTargetIds:["atk"], maxAssignments:1}],
            combatTargets:[{responseId:"atk", kind:"card", objectId:"opponent", label:"Attacker",
                name:"Grizzly Bears", maxAssignments:1}]
        })
        mouseClick(item("forgeCard-own-0"))
        compare(table.combatInteraction.assignments["block-0"], "atk")
        compare(table.combatInteraction.selectedSource, "")
        mouseClick(item("forgeCard-own-0"))
        compare(table.combatInteraction.assignments["block-0"], undefined)
    }
    function test_blockWithAllAssignsSingleAttackerBlockers() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, 2)))
        prompt("chooseBlockers", {
            combatSources:[0, 1].map(i => ({responseId:"block-" + i, objectId:"own-" + i,
                label:"Bear", name:"Grizzly Bears", validTargetIds:["atk"], maxAssignments:1})),
            combatTargets:[{responseId:"atk", kind:"card", objectId:"opponent", label:"Attacker",
                name:"Grizzly Bears", maxAssignments:2}]
        })
        mouseClick(item("rulesBlockWithAll"))
        compare(table.combatInteraction.assignments["block-0"], "atk")
        compare(table.combatInteraction.assignments["block-1"], "atk")
    }
    function test_blockWithAllLeavesChoicesWithSeveralAttackers() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, 2)))
        prompt("chooseBlockers", {
            combatSources:[
                {responseId:"block-0", objectId:"own-0", label:"Bear", name:"Grizzly Bears",
                    validTargetIds:["atk"], maxAssignments:1},
                {responseId:"block-1", objectId:"own-1", label:"Bear", name:"Grizzly Bears",
                    validTargetIds:["atk", "atk-b"], maxAssignments:1}],
            combatTargets:[
                {responseId:"atk", kind:"card", objectId:"opponent", label:"Attacker",
                    name:"Grizzly Bears", maxAssignments:1},
                {responseId:"atk-b", kind:"card", objectId:"other-attacker", label:"Other",
                    name:"Other", maxAssignments:1}]
        })
        mouseClick(item("rulesBlockWithAll"))
        compare(table.combatInteraction.assignments["block-0"], "atk")
        compare(table.combatInteraction.assignments["block-1"], undefined)
    }
    function test_blockWithAllStopsWhenTheAttackerIsFull() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, 2)))
        prompt("chooseBlockers", {
            combatSources:[0, 1].map(i => ({responseId:"block-" + i, objectId:"own-" + i,
                label:"Bear", name:"Grizzly Bears", validTargetIds:["atk"], maxAssignments:1})),
            combatTargets:[{responseId:"atk", kind:"card", objectId:"opponent", label:"Attacker",
                name:"Grizzly Bears", maxAssignments:1}]
        })
        mouseClick(item("rulesBlockWithAll"))
        compare(Object.keys(table.combatInteraction.assignments).length, 1)
    }
    function test_attackWithAllAssignsEveryCreature() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, 2)))
        prompt("chooseAttackers", {
            combatSources:[0, 1].map(i => ({responseId:"source-" + i, objectId:"own-" + i,
                label:"Bear", name:"Grizzly Bears", validTargetIds:["defender"], maxAssignments:1})),
            combatTargets:[{responseId:"defender", kind:"player", seat:1, label:"Opponent", maxAssignments:2}]
        })
        mouseClick(item("rulesAttackWithAll"))
        compare(table.combatInteraction.assignments["source-0"], "defender")
        compare(table.combatInteraction.assignments["source-1"], "defender")
    }
    function test_attackWithAllStopsAtTheDefenderCapacity() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, 3)))
        prompt("chooseAttackers", {
            combatSources:[0, 1, 2].map(i => ({responseId:"source-" + i, objectId:"own-" + i,
                label:"Bear", name:"Grizzly Bears", validTargetIds:["defender"], maxAssignments:1})),
            combatTargets:[{responseId:"defender", kind:"player", seat:1, label:"Opponent", maxAssignments:2}]
        })
        mouseClick(item("rulesAttackWithAll"))
        compare(Object.keys(table.combatInteraction.assignments).length, 2)
        compare(table.combatInteraction.assignments["source-2"], undefined)
    }
    function manaPrompt(paymentId, options) {
        prompt("payManaCost", {title:"Pay Mana Cost: {G}", paymentId:paymentId || "",
            options:options})
    }
    function test_pendingManaPressDoesNotBecomeTheNextPromptsUndo() {
        landBoard(["land-a"])
        manaPrompt("sa:10", [
            {responseId:"pay-a", kind:"activateAbility", cardId:"land-a", label:"Plains"}])
        const source = item("forgeCard-land-a")
        mouseClick(source)
        compare(transport.responses.length, 1)
        for (let i = 0; i < 12; ++i)
            mouseClick(source)
        compare(transport.responses.length, 1, "Repeating an in-flight source never sends or queues it")
        compare(table.interaction.paymentQueue, [])
        mousePress(source)
        manaPrompt("sa:10", [
            {responseId:"undo-a", kind:"undoMana", cardId:"land-a", label:"Undo mana"}])
        mouseRelease(source)
        compare(transport.responses.length, 1, "A press during the previous decision cannot answer the new one")
        mouseClick(source)
        compare(transport.responses.length, 2, "An intentional click on the new undo offer remains available")
        compare(transport.responses[1].response, "undo-a")
    }
    function test_sameDecisionManaPressStillQueuesAndRemovesTheSource() {
        const options = forestAndIsland()
        manaPrompt("sa:10", options)
        mouseClick(item("forgeCard-land-a"))
        const queued = item("forgeCard-land-b")
        mousePress(queued)
        republish("payManaCost", {title:"Pay Mana Cost: {G}", paymentId:"sa:10", options:options})
        mouseRelease(queued)
        compare(table.interaction.paymentQueue, ["land-b"], "An identical prompt republication preserves a waiting gesture")
        compare(transport.responses.length, 1)
        mouseClick(queued)
        compare(table.interaction.paymentQueue, [], "A fresh second click still removes the queued source")
        compare(transport.responses.length, 1)
    }
    function test_pendingQueuedManaPressCannotAnswerAChangedPayment() {
        const options = forestAndIsland()
        manaPrompt("sa:10", options)
        mouseClick(item("forgeCard-land-a"))
        const queued = item("forgeCard-land-b")
        mousePress(queued)
        manaPrompt("sa:11", [{responseId:"new-pay-b", kind:"activateAbility", cardId:"land-b", label:"Island"}])
        mouseRelease(queued)
        compare(table.interaction.paymentQueue, [])
        compare(transport.responses.length, 1, "A pending press cannot silently activate a different payment")
        mouseClick(queued)
        compare(transport.responses.length, 2)
        compare(transport.responses[1].response, "new-pay-b")
    }
    function test_paymentQueueSubmitsTheNextStepOfTheSameSpell() {
        const state = snapshot(1, 0)
        state.zones[4].cards = [card("land-a", 0, "Forest", false), card("land-b", 0, "Island", false)]
        state.zones[4].count = 2
        verify(testRulesPrompt.applySnapshot(state))
        manaPrompt("sa:10", [
            {responseId:"pay-a", kind:"activateAbility", cardId:"land-a", label:"Forest"},
            {responseId:"pay-b", kind:"activateAbility", cardId:"land-b", label:"Island"}])
        mouseClick(item("forgeCard-land-a"))
        compare(transport.responses.length, 1)
        compare(transport.responses[0].response, "pay-a")
        mouseClick(item("forgeCard-land-b"))
        compare(transport.responses.length, 1, "A queued land is not sent yet")
        compare(item("forgeCardPaymentQueue-land-b").text, "1")
        mouseClick(item("forgeCard-land-b"))
        verify(findChild(table, "forgeCardPaymentQueue-land-b") === null)
        mouseClick(item("forgeCard-land-b"))
        compare(item("forgeCardPaymentQueue-land-b").text, "1")
        manaPrompt("sa:10", [
            {responseId:"pay-b2", kind:"activateAbility", cardId:"land-b", label:"Island"}])
        compare(transport.responses.length, 2)
        compare(transport.responses[1].response, "pay-b2")
        compare(table.rulesSession.promptPaymentId, "sa:10")
    }
    function test_paymentQueueClearsWhenTheSpellChanges() {
        const state = snapshot(1, 0)
        state.zones[4].cards = [card("land-a", 0, "Forest", false), card("land-b", 0, "Island", false)]
        state.zones[4].count = 2
        verify(testRulesPrompt.applySnapshot(state))
        manaPrompt("sa:10", [
            {responseId:"pay-a", kind:"activateAbility", cardId:"land-a", label:"Forest"},
            {responseId:"pay-b", kind:"activateAbility", cardId:"land-b", label:"Island"}])
        mouseClick(item("forgeCard-land-a"))
        mouseClick(item("forgeCard-land-b"))
        manaPrompt("sa:11", [
            {responseId:"pay-b2", kind:"activateAbility", cardId:"land-b", label:"Island"}])
        compare(transport.responses.length, 1)
        compare(item("forgeWaitingCueText").text, "Queued mana was cleared")
        verify(item("forgeWaitingCue").visible)
    }
    function test_sacrificialManaColorChoiceInterruptsQueuedPayment_data() {
        return [{tag:"english", language:"en", label:"Blue"},
                {tag:"chinese", language:"zh", label:"蓝色"}]
    }
    function test_sacrificialManaColorChoiceInterruptsQueuedPayment(data) {
        testTranslations.setLanguage(data.language)
        catalog.typeOverrides = ({"Lotus Bloom":"Artifact"})
        const state = snapshot(1, 0)
        const lotus = card("lotus", 0, "Lotus Bloom", false)
        state.zones[4].cards = [lotus, card("land", 0, "Plains", false)]
        state.zones[4].count = 2
        verify(testRulesPrompt.applySnapshot(state))
        manaPrompt("sa:50", [
            {responseId:"activate-lotus", kind:"activateAbility", cardId:"lotus", label:"Lotus Bloom"},
            {responseId:"activate-plains", kind:"activateAbility", cardId:"land", label:"Plains"}])
        mouseClick(item("forgeCard-lotus"))
        const initialId = table.rulesSession.promptId
        compare(transport.responses, [{id:initialId, response:"activate-lotus"}])
        verify(transport.rulesResponsePending)
        mouseClick(item("forgeCard-land"))
        compare(table.interaction.paymentQueue, ["land"])

        const dock = item("rulesDecisionDock")
        dock.collapsed = true
        prompt("chooseBoolean", {title:"Confirm decision", detail:"Sacrifice Lotus Bloom?",
            minChoiceTotal:1, maxChoiceTotal:1,
            choices:[{responseId:"choice:0", label:"No", weight:1, canRepeat:false},
                     {responseId:"choice:1", label:"Yes", weight:1, canRepeat:false}]})
        verify(!dock.collapsed && dock.showsBody, "The nested choice reopens the decision dock")
        compare(table.interaction.paymentQueue, [], "A queued source cannot answer a sacrifice decision")
        verify(!transport.rulesResponsePending)
        mouseClick(item("rulesScalarChoice-choice:1"))
        compare(transport.responses[1], {id:table.rulesSession.promptId, choices:["choice:1"]})

        // Forge has paid the sacrifice before asking for its enum color. The
        // source's visible identity remains in the graveyard and prompt context.
        state.zones[4].cards = [state.zones[4].cards[1]]
        state.zones[4].count = 1
        state.zones.push({zone:"graveyard", ownerSeat:0, count:1, cards:[lotus]})
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseFromSelection", {title:"Select Mana to Produce",
            minChoiceTotal:1, maxChoiceTotal:1,
            choices:["WHITE", "BLUE", "BLACK", "RED", "GREEN"].map((color, index) =>
                ({responseId:"choice:" + index, label:color, weight:1, canRepeat:false})),
            contextCards:[{id:"context-card:0", name:"Lotus Bloom"}]})
        const colorId = table.rulesSession.promptId
        verify(dock.showsBody && !dock.collapsed)
        verify(!transport.rulesResponsePending)
        verify(!table.interaction.objectActionable("card", "lotus"))
        verify(!table.interaction.objectActionable("card", "land"))
        const blue = item("rulesScalarChoice-choice:1")
        verify(blue.visible && blue.enabled)
        compare(blue.text, data.label)
        const scalarList = item("rulesScalarCandidates")
        scalarList.positionViewAtIndex(1, ListView.Contain)
        const scroll = item("rulesPromptScroll")
        const blueTop = blue.mapToItem(scroll.contentItem, 0, 0).y
        scroll.contentY = Math.max(0, Math.min(blueTop, scroll.contentHeight - scroll.height))
        waitForRendering(table)
        const position = blue.mapToItem(scroll, 0, 0)
        verify(position.y >= 0 && position.y + blue.height <= scroll.height,
               "A sacrificed source's color button stays reachable in the decision dock")
        verify(!item("rulesConfirmChoices").visible)
        verify(!item("rulesSkipChoice").visible)
        mouseClick(blue)
        compare(transport.responses[2], {id:colorId, choices:["choice:1"]})
        verify(transport.rulesResponsePending)
        mouseClick(blue)
        compare(transport.responses.length, 3, "A color click is sent once while the response is pending")

        manaPrompt("sa:50", [
            {responseId:"activate-plains-current", kind:"activateAbility", cardId:"land", label:"Plains"},
            {responseId:"$pay", kind:"pay", label:"Confirm payment"}])
        compare(table.rulesSession.promptPaymentId, "sa:50")
        compare(table.interaction.paymentQueue, [], "Interrupted click-ahead never resumes after the color choice")
        verify(!transport.rulesResponsePending)
        compare(transport.responses.length, 3)
        verify(!table.interaction.objectActionable("card", "lotus"))
        verify(table.interaction.objectActionable("card", "land"))
        mouseClick(item("rulesPromptOption-$pay"))
        compare(transport.responses[3], {id:table.rulesSession.promptId, response:"$pay"})
    }
    function test_paymentWithoutAnIdKeepsTheWaitingCue() {
        const state = snapshot(1, 0)
        state.zones[4].cards = [card("land-a", 0, "Forest", false), card("land-b", 0, "Island", false)]
        state.zones[4].count = 2
        verify(testRulesPrompt.applySnapshot(state))
        manaPrompt("", [
            {responseId:"pay-a", kind:"activateAbility", cardId:"land-a", label:"Forest"},
            {responseId:"pay-b", kind:"activateAbility", cardId:"land-b", label:"Island"}])
        mouseClick(item("forgeCard-land-a"))
        mouseClick(item("forgeCard-land-b"))
        compare(transport.responses.length, 1)
        compare(item("forgeWaitingCueText").text, "Waiting for the game")
        verify(findChild(table, "forgeCardPaymentQueue-land-b") === null)
    }
    function test_paymentQueueStopsAtEightAndEscapeRemovesTheLast() {
        const state = snapshot(1, 0)
        const lands = []
        for (let i = 0; i < 9; ++i)
            lands.push(card("land-" + i, 0, "Forest " + i, false))
        state.zones[4].cards = lands
        state.zones[4].count = lands.length
        verify(testRulesPrompt.applySnapshot(state))
        manaPrompt("sa:10", lands.map((land, i) => ({
            responseId:"pay-" + i, kind:"activateAbility", cardId:land.id, label:land.identity.name})))
        transport.rulesResponsePending = true
        for (let i = 0; i < 8; ++i)
            verify(table.interaction.tryQueuePayment("card", "land-" + i))
        verify(!table.interaction.tryQueuePayment("card", "land-8"))
        compare(table.interaction.paymentQueue.length, 8)
        table.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(table.interaction.paymentQueue.length, 7)
        compare(table.interaction.paymentQueue[6], "land-6")
    }
    function test_oneCardArtArrivalDoesNotRefreshTheWholeTable() {
        const state = snapshot(1, 0)
        const spell = card("spell", 0, "Shock", false)
        state.zones[4].cards = [spell]
        state.zones[4].count = 1
        verify(testRulesPrompt.applySnapshot(state))
        tryVerify(() => item("forgeOwnOther").visibleCards.some(card => card.cardId === "spell"))
        const before = catalog.requested.length
        catalog.imageRevision++
        waitForRendering(table)
        compare(catalog.requested.length, before)
        verify(item("forgeOwnOther").visibleCards.some(card => card.cardId === "spell"))
        catalog.typeOverrides = Object.assign({}, catalog.typeOverrides, {Shock: "Land"})
        catalog.cardAvailable("Shock", "Shock", "Land", "", "", "")
        tryVerify(() => item("forgeOwnLands").visibleCards.some(card => card.cardId === "spell"))
        verify(catalog.requested.length > before)
    }
    function test_damageMarkPulsesAndThenRests() {
        Theme.motionEnabled = true
        const state = snapshot(1, 1)
        verify(testRulesPrompt.applySnapshot(state))
        const face = item("forgeCard-own-0")
        compare(face.markPulse, 1)
        state.zones[4].cards[0].damage = 3
        verify(testRulesPrompt.applySnapshot(state))
        tryVerify(() => item("forgeCard-own-0").markPulse > 1)
        tryCompare(item("forgeCard-own-0"), "markPulse", 1)
        Theme.motionEnabled = false
    }
    function test_stackEntryArrivesAndLeaves() {
        Theme.motionEnabled = true
        const state = snapshot()
        state.stack = [{id:"bolt", controllerSeat:0, identity:{name:"Lightning Bolt"}, text:"Deal 3 damage"}]
        verify(testRulesPrompt.applySnapshot(state))
        const entry = item("forgeStackEntry-bolt")
        tryCompare(entry, "opacity", 1)
        state.stack = []
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(item("forgeStack"), "count", 0)
        Theme.motionEnabled = false
    }
    function test_lifeLossFloatsARedDelta() {
        Theme.motionEnabled = true
        const state = snapshot()
        state.players[0].life = 17
        verify(testRulesPrompt.applySnapshot(state))
        const delta = item("forgeLifeDelta-0")
        const value = item("forgeLifeValue-0")
        compare(delta.text, "-3")
        verify(delta.opacity > 0)
        tryVerify(() => delta.implicitWidth > 0 && value.implicitWidth > 0)
        const deltaRect = delta.mapToItem(table, 0, 0, delta.width, delta.height)
        const valueRect = value.mapToItem(table, 0, 0, value.width, value.height)
        verify(deltaRect.y + deltaRect.height <= valueRect.y + 0.5,
               "The life change stays above the current total")
        tryCompare(value, "text", "17")
    }
    function test_lifeDeltasStayInsideTheirReservedSpace_data() {
        return [
            {tag:"duel-player", seats:2, seat:0, scale:1, resize:true},
            {tag:"duel-opponent-compact", seats:2, seat:1, scale:1.8, compact:true, chinese:true},
            {tag:"duel-spectator", seats:2, seat:-1, scale:1.8},
            {tag:"duel-replay", seats:2, seat:-1, scale:1.8, replay:true},
            {tag:"three-player", seats:3, seat:0, scale:1},
            {tag:"three-spectator", seats:3, seat:-1, scale:1.8},
            {tag:"four-player", seats:4, seat:0, scale:1.8, resize:true},
            {tag:"four-opponent-compact", seats:4, seat:3, scale:1.8, compact:true, chinese:true},
            {tag:"four-spectator", seats:4, seat:-1, scale:1},
            {tag:"four-replay", seats:4, seat:-1, scale:1.8, replay:true},
            {tag:"duel-wide-delta", seats:2, seat:0, scale:1.8, wide:true},
            {tag:"four-wide-delta", seats:4, seat:0, scale:1.8, wide:true}
        ]
    }
    function test_lifeDeltasStayInsideTheirReservedSpace(data) {
        window.width = data.compact ? 900 : 1920
        window.height = data.compact ? 620 : 1011
        Theme.uiScale = data.scale
        testTranslations.setLanguage(data.chinese ? "zh" : "en")
        room.role = data.seat < 0 ? "spectator" : "player"
        room.seatIndex = data.seat
        room.spectatorsSeeHands = data.seat < 0
        table.replayMode = data.replay === true
        room.actionClockEnabled = true
        room.actionClockMs = [180000, 165000, 150000, 145000]
        const seats = Array.from({length:data.seats}, (_, index) => index)
        if (data.seats > 2) {
            room.format = "edh"; room.deckFormat = "commander"; room.maxSeats = data.seats
        }
        const state = data.seats > 2 ? edhSnapshot(seats, Math.max(0, data.seat), 1) : snapshot()
        if (data.chinese)
            for (const player of state.players) player.name = "中文玩家 " + player.seat
        room.players = state.players.map(player => player.name)
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(table.presentation, "multiplayer", data.seats > 2)
        verify(waitForPolish(window)); verify(waitForRendering(table))
        function bounds(target) {
            return target.mapToItem(table, 0, 0, target.width, target.height)
        }
        const fixedItems = []
        for (const seat of seats) {
            fixedItems.push(item("rulesPlayerTarget" + seat), item("forgePlayerName-" + seat))
            if (data.seats > 2)
                fixedItems.push(item("forgeField-" + seat), item("forgeCard-creature-" + seat + "-0"))
        }
        if (data.seats === 2)
            fixedItems.push(item("forgeCard-own-0"), item("forgeCard-opponent"))
        const initial = fixedItems.map(target => bounds(target))
        const readouts = seats.map(seat => {
            const target = item("rulesPlayerTarget" + seat)
            const names = ["forgePlayerName-", "forgePlayerZones-"]
                .concat(data.seats > 2 ? ["forgeSeatStatus-", "forgeSeatZones-"] : ["forgeActionClock-"])
            return {seat:seat, delta:item("forgeLifeDelta-" + seat), value:item("forgeLifeValue-" + seat),
                envelope:data.seats > 2 ? target.parent : target, labels:names.map(name => item(name + seat))}
        })
        function check(stage, requiresVisible) {
            for (const readout of readouts) {
                const seat = readout.seat, delta = readout.delta, value = readout.value
                if (requiresVisible)
                    verify(delta.opacity > 0, stage + ": the change is still visible")
                const rect = bounds(delta)
                verify(rect.x >= -0.5 && rect.y >= -0.5
                    && rect.x + rect.width <= table.width + 0.5
                    && rect.y + rect.height <= table.height + 0.5,
                    stage + ": delta stays in the viewport for seat " + seat + ": " + JSON.stringify(rect))
                const envelope = bounds(readout.envelope)
                verify(rect.x >= envelope.x - 0.5 && rect.y >= envelope.y - 0.5
                    && rect.x + rect.width <= envelope.x + envelope.width + 0.5
                    && rect.y + rect.height <= envelope.y + envelope.height + 0.5,
                    stage + ": the whole delta stays inside its reserved player area")
                verify(rect.y + rect.height <= bounds(value.parent).y - 1 * table.presentation.unit,
                    stage + ": the signed change stays above the life disc")
                for (const label of readout.labels) {
                    if (label.visible)
                        verify(!rectsOverlap(delta, label), stage + ": delta overlaps " + label.objectName)
                }
                verify(!rectsOverlap(delta, value), stage + ": delta overlaps the current total")
            }
            for (let index = 0; index < fixedItems.length; ++index)
                compare(bounds(fixedItems[index]), initial[index], stage + ": life motion must not move the board")
        }
        Theme.motionEnabled = true
        const values = data.wide ? [2000000000, -2000000000, 2000000000] : [17, 23, 19]
        for (const life of values) {
            for (const player of state.players) player.life = life
            verify(testRulesPrompt.applySnapshot(state))
            verify(waitForPolish(window))
            check("start " + life, true)
            wait(180)
            check("rising " + life, true)
            if (data.resize && life === values[values.length - 1]) {
                window.width = 1280; window.height = 720
                tryCompare(table, "width", 1280); tryCompare(table, "height", 720)
                verify(waitForPolish(window)); verify(waitForRendering(table))
                for (let index = 0; index < fixedItems.length; ++index)
                    initial[index] = bounds(fixedItems[index])
                // Processing a native resize can outlast the remaining fade.
                // Its resulting position must fit the new band at any progress.
                check("resized animation position", false)
            }
        }
        for (const readout of readouts) tryCompare(readout.delta, "opacity", 0)
        check("final animation position", false)
        Theme.finishMotion()
        for (const readout of readouts) compare(readout.delta.opacity, 0)
        for (let index = 0; index < fixedItems.length; ++index)
            compare(bounds(fixedItems[index]), initial[index], "Finishing motion keeps the same reserved geometry")
    }
    function test_handCardBecomesOneBattlefieldMove() {
        const before = snapshot(1, 1)
        const after = snapshot(1, 1)
        const played = after.zones[0].cards.pop()
        after.zones[0].count = after.zones[0].cards.length
        after.zones[4].cards.push(played)
        after.zones[4].count = after.zones[4].cards.length
        verify(testRulesPrompt.applySnapshot(before))
        verify(testRulesPrompt.applySnapshot(after))
        const move = table.rulesSession.transitions.find(event => event.id === "hand-0")
        verify(move)
        compare(move.kind, "move")
        compare(move.fromZone, "hand")
        compare(move.toZone, "battlefield")
        compare(table.rulesSession.transitions.filter(event =>
            event.kind === "move" || event.kind === "enter" || event.kind === "leave").length, 1)
    }
    function test_enabledMotionRotatesATap() {
        Theme.motionEnabled = true
        const state = snapshot(1, 0)
        const plains = card("land", 0, "Plains", false)
        state.zones[4].cards = [plains]
        state.zones[4].count = 1
        verify(testRulesPrompt.applySnapshot(state))
        const land = item("forgeCard-land")
        plains.tapped = true
        verify(testRulesPrompt.applySnapshot(state))
        verify(land.tapShade < 1)
        tryCompare(land, "tapShade", 1)
        compare(item("forgeCardTappedShade-land").opacity, land.tappedShade)
    }
    function test_slotGlideKeepsTheHitTargetAndAClickFinishesIt() {
        const state = snapshot(1, 0)
        state.zones[4].cards = [card("land-a", 0, "Plains", false), card("land-b", 0, "Plains", false)]
        state.zones[4].count = 2
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(item("forgeOwnLands"), "stackCount", 1)
        const front = item("forgeCard-land-b")
        const slot = front.parent
        compare(slot.visualDx, 0)
        compare(slot.visualDy, 0)
        Theme.motionEnabled = true
        mouseClick(item("forgeCardStackCount-land-b"))
        verify(Math.abs(slot.visualDx) + Math.abs(slot.visualDy) > 1)
        mouseClick(front)
        compare(slot.visualDx, 0)
        compare(slot.visualDy, 0)
    }

    // Publishes the pending prompt again under the same id, as Forge does when
    // it re-sends a decision.
    function republish(kind, extra) {
        const data = Object.assign({roomId:"DUEL01", gameId:"duel-game", pending:true, supported:true,
            promptId:serial, kind:kind, title:"Choose", detail:"", options:[], choices:[], cards:[],
            targets:[], contextCards:[], contextTargets:[], combatSources:[], combatTargets:[],
            damageTargets:[], scryDestinations:[], totalDamage:0}, extra || {})
        verify(testRulesPrompt.applyPrompt(data))
        waitForRendering(table)
    }
    function landBoard(ids, tapped) {
        const state = snapshot(1, 0)
        state.zones[4].cards = ids.map(id => {
            const land = card(id, 0, "Plains", false)
            land.tapped = (tapped || []).includes(id)
            return land
        })
        state.zones[4].count = ids.length
        verify(testRulesPrompt.applySnapshot(state))
        return state
    }
    function forestAndIsland() {
        const state = snapshot(1, 0)
        state.zones[4].cards = [card("land-a", 0, "Forest", false), card("land-b", 0, "Island", false)]
        state.zones[4].count = 2
        verify(testRulesPrompt.applySnapshot(state))
        return [{responseId:"pay-a", kind:"activateAbility", cardId:"land-a", label:"Forest"},
            {responseId:"pay-b", kind:"activateAbility", cardId:"land-b", label:"Island"}]
    }
    function test_pileFrontWithDifferentActionsOpensTheFan() {
        landBoard(["land-a", "land-b"])
        prompt("chooseAction", {options:[
            {responseId:"mana-b", kind:"activateAbility", cardId:"land-b", label:"Add {W}"},
            {responseId:"animate-a", kind:"activateAbility", cardId:"land-a", label:"Animate"},
            {responseId:"$pass", kind:"pass", label:"Pass"}]})
        const lane = item("forgeOwnLands")
        tryCompare(lane, "stackCount", 1)
        mouseClick(item("forgeCard-land-b"))
        compare(transport.responses.length, 0, "Members that differ are never chosen for the player")
        compare(lane.fannedStack, 0)
        mouseClick(item("forgeCard-land-a"))
        compare(transport.responses.length, 1)
        compare(transport.responses[0].response, "animate-a")
    }
    function test_interchangeablePileFrontActsOnItself() {
        landBoard(["land-a", "land-b"])
        prompt("chooseAction", {options:[
            {responseId:"mana-a", kind:"activateAbility", cardId:"land-a", label:"Plains"},
            {responseId:"mana-b", kind:"activateAbility", cardId:"land-b", label:"Plains"},
            {responseId:"$pass", kind:"pass", label:"Pass"}]})
        tryCompare(item("forgeOwnLands"), "stackCount", 1)
        mouseClick(item("forgeCard-land-b"))
        compare(transport.responses.length, 1)
        compare(transport.responses[0].response, "mana-b")
        verify(item("forgeCard-land-b").submitted)
    }
    function test_separateBlockerCanBeTargetedDirectly() {
        const state = snapshot(1, 1)
        state.step = "declare_blockers"
        state.zones[4].cards[0].attacking = true
        state.zones[4].cards[0].attackingPlayer = 1
        const blocker = card("opp-b", 1, "Grizzly Bears", true)
        blocker.blocking = ["own-0"]
        state.zones[5].cards = [card("opp-a", 1, "Grizzly Bears", true), blocker]
        state.zones[5].count = 2
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseBoardTargets", {minSelections:1, maxSelections:1, targets:[
            {responseId:"t-a", kind:"card", objectId:"opp-a", label:"Grizzly Bears", name:"Grizzly Bears"},
            {responseId:"t-b", kind:"card", objectId:"opp-b", label:"Grizzly Bears", name:"Grizzly Bears"}]})
        const lane = item("forgeOpponentCreatures")
        tryCompare(lane, "stackCount", 2)
        compare(item("forgeCard-opp-b").card.stackSize, 1)
        mouseClick(item("forgeCard-opp-b"))
        compare(transport.responses.length, 1)
        compare(transport.responses[0].targets, ["t-b"])
    }
    function test_tappedSiblingWithAnActionDoesNotAnswerAFrontClick() {
        landBoard(["land-a", "land-b"], ["land-a"])
        prompt("chooseAction", {options:[
            {responseId:"animate-a", kind:"activateAbility", cardId:"land-a", label:"Animate"},
            {responseId:"mana-b", kind:"activateAbility", cardId:"land-b", label:"Add {W}"},
            {responseId:"animate-b", kind:"activateAbility", cardId:"land-b", label:"Animate"},
            {responseId:"$pass", kind:"pass", label:"Pass"}]})
        tryCompare(item("forgeOwnLands"), "stackCount", 2)
        mouseClick(item("forgeCard-land-b"))
        compare(transport.responses.length, 0, "Only the clicked card answers")
        verify(table.cardActionPicker.opened)
        verify(!item("forgeWaitingCue").visible)
        mouseClick(item("rulesCardAction-animate-b"))
        compare(transport.responses.length, 1)
        compare(transport.responses[0].response, "animate-b")
    }
    function test_auraOnAPiledCopyStaysVisible() {
        const state = snapshot(1, 2)
        const aura = card("aura", 0, "Pacifism", true)
        aura.attachedTo = "own-1"
        state.zones[4].cards.push(aura)
        state.zones[4].count = state.zones[4].cards.length
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(item("forgeOwnCreatures"), "stackCount", 2)
        const host = item("forgeCard-own-1")
        const attached = item("forgeCard-aura")
        verify(attached.visible)
        verify(attached.parent === host.parent)
    }
    function attachmentBoard(depth, seat) {
        const state = snapshot(1, 1)
        const field = state.zones[seat === 1 ? 5 : 4]
        const hostId = seat === 1 ? "opponent" : "own-0"
        for (let i = 0; i < depth; ++i) {
            const attached = card("attached-" + i, seat, i % 2 ? "Rancor" : "Bonesplitter", false)
            attached.attachedTo = hostId
            field.cards.push(attached)
        }
        field.count = field.cards.length
        verify(testRulesPrompt.applySnapshot(state))
        return hostId
    }
    function test_eachStackedAttachmentRemainsSelectable_data() {
        return [{tag:"own-three", w:1920, h:1010, depth:3, seat:0},
            {tag:"opponent-three", w:1920, h:1010, depth:3, seat:1},
            {tag:"laptop-three", w:1280, h:729, depth:3, seat:0},
            {tag:"deep-stack", w:1920, h:1010, depth:12, seat:0}]
    }
    function test_eachStackedAttachmentRemainsSelectable(data) {
        window.width = data.w; window.height = data.h
        const hostId = attachmentBoard(data.depth, data.seat)
        const options = [{responseId:"host-action", kind:"activateAbility", cardId:hostId, label:"Host ability"}]
        for (let i = 0; i < data.depth; ++i)
            options.push({responseId:"attachment-action-" + i, kind:"activateAbility",
                cardId:"attached-" + i, label:"Attachment ability " + i})
        const lane = item(data.seat === 1 ? "forgeOpponentCreatures" : "forgeOwnCreatures")
        const viewport = lane.scrollArea
        for (let i = 0; i < data.depth; ++i) {
            prompt("chooseAction", {options:options})
            const attached = item("forgeCard-attached-" + i)
            const clickY = attached.height - 8 * attached.unit
            const point = attached.mapToItem(viewport, attached.width / 2, clickY)
            // Deep attachment stacks scroll at readable size. Bring each
            // exposed strip into view before testing its actual hit target.
            viewport.contentY = Math.max(0, Math.min(viewport.contentHeight - viewport.height,
                viewport.contentY + point.y - viewport.height / 2))
            waitForRendering(table)
            const visiblePoint = attached.mapToItem(viewport, attached.width / 2, clickY)
            verify(visiblePoint.y >= 8 * attached.unit
                && visiblePoint.y <= viewport.height - 8 * attached.unit,
                "The attachment strip must be visible before its click")
            mouseClick(attached, attached.width / 2, clickY)
            compare(transport.responses.length, i + 1, "Only one card responds to an attachment strip click")
            compare(transport.responses[i].response, "attachment-action-" + i,
                "Each exposed strip selects its own attachment, including the covered copies")
        }
        prompt("chooseAction", {options:options})
        verify(lane.reveal(hostId))
        waitForRendering(table)
        mouseClick(item("forgeCard-" + hostId))
        compare(transport.responses.length, data.depth + 1)
        compare(transport.responses[data.depth].response, "host-action", "Attachments do not answer a host click")
    }
    function test_attachmentTargetUsesTheClickedObject() {
        const hostId = attachmentBoard(3, 0)
        const ids = [hostId, "attached-0", "attached-1", "attached-2"]
        for (let i = 0; i < ids.length; ++i) {
            prompt("chooseBoardTargets", {minSelections:1, maxSelections:1,
                targets:ids.map(id => ({responseId:"target-" + id, kind:"card", objectId:id, label:id}))})
            const selected = item("forgeCard-" + ids[i])
            mouseClick(selected, selected.width / 2,
                i === 0 ? selected.height / 2 : selected.height - 8 * selected.unit)
            compare(transport.responses.length, i + 1)
            compare(transport.responses[i].targets, ["target-" + ids[i]])
        }
    }
    function test_attachmentStripsInspectTheHoveredAndClickedObject() {
        const hostId = attachmentBoard(3, 0)
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        const ids = [hostId, "attached-0", "attached-1", "attached-2"]
        for (let i = 0; i < ids.length; ++i) {
            const selected = item("forgeCard-" + ids[i])
            const y = i === 0 ? selected.height / 2 : selected.height - 8 * selected.unit
            if (i > 0)
                compare(item("forgeAttachmentName-" + ids[i]).text, selected.displayName)
            mouseMove(selected, selected.width / 2, y)
            tryCompare(table.inspector, "previewCardId", ids[i])
            mouseClick(selected, selected.width / 2, y, Qt.RightButton)
            tryCompare(table.inspector, "pinnedCardId", ids[i])
            compare(transport.responses.length, 0, "Inspecting an attachment never submits a decision")
            table.inspector.clear()
        }
    }
    function test_pileClickAheadQueuesSeveralLands() {
        landBoard(["land-a", "land-b", "land-c"])
        manaPrompt("sa:10", ["a", "b", "c"].map(x => ({responseId:"pay-" + x, kind:"activateAbility",
            cardId:"land-" + x, label:"Plains"})))
        tryCompare(item("forgeOwnLands"), "stackCount", 1)
        const front = item("forgeCard-land-c")
        mouseClick(front)
        compare(transport.responses.length, 1)
        compare(transport.responses[0].response, "pay-c")
        mouseClick(front)
        mouseClick(front)
        compare(table.interaction.paymentQueue, ["land-a", "land-b"])
        compare(item("forgeCardPaymentQueue-land-c").text, "1 2")
        mouseClick(front)
        compare(table.interaction.paymentQueue.length, 2, "A further click never unqueues a land")
        manaPrompt("sa:10", ["a", "b"].map(x => ({responseId:"pay2-" + x, kind:"activateAbility",
            cardId:"land-" + x, label:"Plains"})))
        compare(transport.responses.length, 2)
        compare(transport.responses[1].response, "pay2-a")
        compare(table.interaction.paymentQueue, ["land-b"])
    }
    function test_handSourcesAreNeverQueued() {
        const state = snapshot(1, 0)
        state.zones[0].cards = [card("spirit", 0, "Simian Spirit Guide", true)]
        state.zones[4].cards = [card("land-a", 0, "Forest", false)]
        state.zones[4].count = 1
        verify(testRulesPrompt.applySnapshot(state))
        manaPrompt("sa:10", [
            {responseId:"pay-a", kind:"activateAbility", cardId:"land-a", label:"Forest"},
            {responseId:"pay-s", kind:"activateAbility", cardId:"spirit", label:"Exile"}])
        mouseClick(item("forgeCard-land-a"))
        compare(transport.responses.length, 1)
        verify(!table.interaction.tryQueuePayment("card", "spirit"))
        verify(!table.interaction.tryQueuePayment("card", "land-a"), "The land in flight is not queued again")
        compare(table.interaction.paymentQueue.length, 0)
    }
    function test_errorReleaseDropsQueuedMana() {
        const options = forestAndIsland()
        manaPrompt("sa:10", options)
        mouseClick(item("forgeCard-land-a"))
        mouseClick(item("forgeCard-land-b"))
        compare(table.interaction.paymentQueue, ["land-b"])
        transport.rulesResponsePending = false
        tryVerify(() => table.interaction.paymentQueue.length === 0)
        compare(item("forgeWaitingCueText").text, "Queued mana was cleared")
        verify(findChild(table, "forgeCardPaymentQueue-land-b") === null)
        mouseClick(item("forgeCard-land-b"))
        compare(transport.responses.length, 2)
        compare(transport.responses[1].response, "pay-b")
    }
    function test_sameIdRepublicationKeepsTheQueueAndRing() {
        const options = forestAndIsland()
        manaPrompt("sa:10", options)
        mouseClick(item("forgeCard-land-a"))
        mouseClick(item("forgeCard-land-b"))
        republish("payManaCost", {title:"Pay Mana Cost: {G}", paymentId:"sa:10", options:options})
        compare(table.interaction.paymentQueue, ["land-b"])
        verify(item("forgeCard-land-a").submitted)
        verify(!item("forgeWaitingCue").visible)
        compare(transport.responses.length, 1)
    }
    function test_sameIdRepublicationKeepsAHiddenChoiceHidden() {
        verify(testRulesPrompt.applySnapshot(stillBoard()))
        const data = {combatSources:[{responseId:"opaque-source", objectId:"own-0", label:"Bear",
                name:"Grizzly Bears", validTargetIds:["opaque-target"], mustAssignIfAble:false, maxAssignments:1}],
            combatTargets:[{responseId:"opaque-target", kind:"player", objectId:"", seat:1,
                label:"Opponent", minAssignments:0, maxAssignments:8}]}
        prompt("chooseAttackers", data)
        const dock = item("rulesDecisionDock")
        mouseClick(item("rulesCombatDetails-attackers"))
        tryVerify(() => dock.listChoiceShown)
        waitForRendering(table)
        mouseClick(item("forgeDecisionCollapse"))
        verify(dock.collapsed)
        republish("chooseAttackers", data)
        verify(dock.collapsed, "The same decision stays hidden")
        prompt("chooseAttackers", data)
        verify(!dock.collapsed, "A new decision is shown")
    }
    function test_attackWithAllNeedsAPlayerDestination() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, 1)))
        prompt("chooseAttackers", {
            combatSources:[{responseId:"source-0", objectId:"own-0", label:"Bear", name:"Grizzly Bears",
                validTargetIds:["walker"], maxAssignments:1}],
            combatTargets:[{responseId:"walker", kind:"planeswalker", objectId:"missing-walker",
                label:"Walker", maxAssignments:1}]
        })
        const button = item("rulesAttackWithAll")
        verify(button.visible)
        verify(!button.enabled)
        mouseClick(button)
        compare(Object.keys(table.combatInteraction.assignments).length, 0)
        compare(table.combatInteraction.attackAllPlayers.length, 0)
    }
    function test_combatListFlagClearsWhenTheDecisionChanges() {
        verify(testRulesPrompt.applySnapshot(stillBoard()))
        combat("chooseAttackers")
        const dock = item("rulesDecisionDock")
        mouseClick(item("rulesCombatDetails-attackers"))
        tryVerify(() => dock.listChoiceShown)
        prompt("chooseBoardTargets", {minSelections:1, maxSelections:1,
            targets:[{responseId:"player", kind:"player", seat:1, label:"Bob"}]})
        tryVerify(() => !dock.listChoiceShown)
        verify(table.presentation.boardDecision)
    }
    function test_largeFanStaysInTheWindowAndEscapeClosesIt() {
        window.width = 1280; window.height = 800
        const ids = []
        for (let i = 0; i < 14; ++i)
            ids.push("land-" + String(i).padStart(2, "0"))
        landBoard(ids)
        const lane = item("forgeOwnLands")
        tryCompare(lane, "stackCount", 1)
        const front = ids[ids.length - 1]
        showPile(front)
        compare(lane.fannedStack, 0)
        for (const id of ids) {
            const member = item("forgeCard-" + id)
            const left = member.mapToItem(table, 0, 0).x
            verify(left >= 0 && left + member.width <= table.width + 1, id)
        }
        table.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(lane.fannedStack, -1)
        showPile(front)
        compare(lane.fannedStack, 0)
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        compare(lane.fannedStack, -1, "A new decision closes the fan")
    }
    function test_lifeReadoutSettlesOnRapidChanges() {
        Theme.motionEnabled = true
        const state = snapshot()
        state.players[0].life = 17
        verify(testRulesPrompt.applySnapshot(state))
        state.players[0].life = 15
        verify(testRulesPrompt.applySnapshot(state))
        compare(item("forgeLifeDelta-0").text, "-2")
        tryCompare(item("forgeLifeValue-0"), "text", "15")
        wait(Theme.motionNormal + 60)
        compare(item("forgeLifeValue-0").text, "15")
        state.players[0].life = 12
        verify(testRulesPrompt.applySnapshot(state))
        Theme.finishMotion()
        compare(item("forgeLifeValue-0").text, "12")
        state.players[0].life = 18
        verify(testRulesPrompt.applySnapshot(state))
        Theme.motionEnabled = false
        state.players[0].life = 10
        verify(testRulesPrompt.applySnapshot(state))
        compare(item("forgeLifeValue-0").text, "10")
        wait(Theme.motionNormal + 60)
        compare(item("forgeLifeValue-0").text, "10")
    }
    function test_stackEntriesFinishArrivingWhenInterrupted() {
        Theme.motionEnabled = true
        const state = snapshot()
        const first = {id:"spell-a", controllerSeat:0, identity:{name:"Lightning Bolt"}, text:"Deal 3 damage"}
        const second = {id:"spell-b", controllerSeat:1, identity:{name:"Shock"}, text:"Deal 2 damage"}
        state.stack = [first]
        verify(testRulesPrompt.applySnapshot(state))
        const entry = item("forgeStackEntry-spell-a")
        verify(entry.opacity < 1, "A new entry fades in")
        state.stack = [second, first]
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(entry, "opacity", 1)
        compare(entry.scale, 1)
        tryCompare(item("forgeStackEntry-spell-b"), "opacity", 1)
        state.stack = [first]
        verify(testRulesPrompt.applySnapshot(state))
        Theme.finishMotion()
        compare(entry.opacity, 1)
        compare(entry.glideY, 0)
    }
    function test_localUpdateFliesToTheNewPlaceWithoutHoldingPasses() {
        Theme.motionEnabled = true
        const overlay = item("forgeMotionOverlay"), flights = item("forgeMotionFlights")
        const after = snapshot()
        after.zones[4].cards = after.zones[4].cards.filter(row => row.id !== "land")
        after.zones[4].count = after.zones[4].cards.length
        after.zones.push({zone:"graveyard", ownerSeat:0, count:1, cards:[card("land", 0, "Plains", false)]})
        verify(testRulesPrompt.applySnapshot(after))
        tryVerify(() => flights.children.some(proxy => proxy.opacity === 1))
        const proxy = flights.children.find(proxy => proxy.opacity === 1)
        verify(Math.hypot(proxy.toX - proxy.fromX, proxy.toY - proxy.fromY) > 40 * table.presentation.unit,
            "The flight leaves the battlefield for the graveyard pile")
        verify(!overlay.staging)
        Theme.finishMotion()
        compare(overlay.flights, 0)
    }
    function test_otherPlayersUpdateIsStagedAndReleased() {
        const base = snapshot()
        base.activeSeat = 1; base.prioritySeat = 1
        verify(testRulesPrompt.applySnapshot(base))
        waitForRendering(table)
        Theme.motionEnabled = true
        const overlay = item("forgeMotionOverlay"), flights = item("forgeMotionFlights")
        const died = snapshot()
        died.activeSeat = 1; died.prioritySeat = 1
        died.zones[5].cards = []; died.zones[5].count = 0
        died.zones[1].count = 8; died.zones[3].count = 48
        died.zones.push({zone:"graveyard", ownerSeat:1, count:1, cards:[card("opponent", 1, "Grizzly Bears", true)]})
        verify(testRulesPrompt.applySnapshot(died))
        tryVerify(() => overlay.staging)
        tryVerify(() => flights.children.some(proxy => proxy.label === "" && proxy.opacity === 1))
        const draw = flights.children.find(proxy => proxy.label === "" && proxy.opacity === 1)
        verify(Math.hypot(draw.toX - draw.fromX, draw.toY - draw.fromY) > 20 * table.presentation.unit,
            "A hidden draw travels from the library to the hand count")
        verify(overlay.changedIds.includes("opponent"))
        const tapped = JSON.parse(JSON.stringify(died))
        tapped.zones[4].cards[1].tapped = true
        verify(testRulesPrompt.applySnapshot(tapped))
        tryVerify(() => !overlay.staging, 300, "An update without flights releases the hold")
        compare(overlay.stagedFlights, 0)
    }
    function test_opponentCastFromAHiddenHandFliesToTheStack() {
        const base = snapshot()
        base.activeSeat = 1
        base.prioritySeat = 1
        verify(testRulesPrompt.applySnapshot(base))
        waitForRendering(table)
        Theme.motionEnabled = true
        const cast = JSON.parse(JSON.stringify(base))
        cast.zones[1].count = 6
        cast.stack = [{id:"their-bolt", controllerSeat:1, ownerSeat:1,
            identity:{name:"Lightning Bolt", setCode:"M11", collectorNumber:"149"},
            text:"Lightning Bolt deals 3 damage to any target."}]
        verify(testRulesPrompt.applySnapshot(cast))
        const flights = item("forgeMotionFlights")
        tryVerify(() => flights.children.some(proxy => proxy.label === "Lightning Bolt" && proxy.opacity === 1))
        const proxy = flights.children.find(proxy => proxy.label === "Lightning Bolt")
        verify(Math.hypot(proxy.toX - proxy.fromX, proxy.toY - proxy.fromY) > 40 * table.presentation.unit,
            "An opponent spell travels from the hand count to the stack")
        Theme.finishMotion()
    }
    function test_ownAnswerIsNotStaged() {
        const base = snapshot()
        base.activeSeat = 1; base.prioritySeat = 0
        verify(testRulesPrompt.applySnapshot(base))
        prompt("chooseAction", {options:[{responseId:"mana", kind:"activateAbility", cardId:"land", label:"Plains"},
            {responseId:"$pass", kind:"pass", label:"Pass"}]})
        Theme.motionEnabled = true
        mouseClick(item("forgeCard-land"))
        compare(transport.responses.length, 1)
        const overlay = item("forgeMotionOverlay")
        const after = JSON.parse(JSON.stringify(base))
        const played = after.zones[0].cards.pop()
        after.zones[0].count = after.zones[0].cards.length
        after.zones[4].cards.push(played)
        after.zones[4].count = after.zones[4].cards.length
        verify(testRulesPrompt.applySnapshot(after))
        tryVerify(() => overlay.flights > 0)
        verify(!overlay.staging, "The update that answers your own action is not held")
    }
    function test_inputFinishesRunningMotion() {
        Theme.motionEnabled = true
        const state = snapshot(1, 0)
        const plains = card("tap-land", 0, "Plains", false)
        state.zones[4].cards = [plains]
        state.zones[4].count = 1
        verify(testRulesPrompt.applySnapshot(state))
        const land = item("forgeCard-tap-land")
        plains.tapped = true
        verify(testRulesPrompt.applySnapshot(state))
        verify(land.tapShade < 1)
        const hand = item("forgeHand")
        mousePress(hand, 2, 2)
        compare(land.tapShade, 1, "A press anywhere on the table finishes the dim")
        mouseRelease(hand, 2, 2)
        plains.tapped = false
        verify(testRulesPrompt.applySnapshot(state))
        verify(land.tapShade > 0)
        table.forceActiveFocus()
        keyClick(Qt.Key_A)
        compare(land.tapShade, 0, "A key finishes it too")

        const dock = item("rulesDecisionDock")
        prompt("chooseFromSelection", {title:"Choose one", minChoiceTotal:1, maxChoiceTotal:1,
            choices:[0, 1, 2, 3, 4, 5].map(i => ({responseId:"choice:" + i, label:"Option " + i,
                weight:1, canRepeat:false}))})
        Theme.finishMotion()
        // Expansion exposes choices immediately; contraction still animates
        // and must finish on input after the resize hold has expired.
        wait(300)
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        tryVerify(() => dock.height > dock.targetHeight, 1000)
        mousePress(hand, 2, 2)
        compare(dock.height, dock.targetHeight, "A press finishes the dock resize")
        mouseRelease(hand, 2, 2)
    }
    function test_closingTheZoneBrowserDoesNotSwallowTheNextClick() {
        const state = snapshot()
        state.zones.push({zone:"graveyard", ownerSeat:0, count:1, cards:[card("buried", 0, "Grizzly Bears", true)]})
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"mana", kind:"activateAbility", cardId:"land", label:"Plains"},
            {responseId:"$pass", kind:"pass", label:"Pass"}]})
        Theme.motionEnabled = true
        table.presentation.openZone(0, "graveyard")
        const popup = item("forgeZonePopup")
        tryCompare(popup, "opened", true)
        compare(item("forgeCard-buried").arrivalOpacity, 1, "Opening a zone does not fade its cards in")
        popup.close()
        verify(!popup.visible, "A closing modal popup leaves at once")
        mouseClick(item("forgeCard-land"))
        compare(transport.responses.length, 1)
        compare(transport.responses[0].response, "mana")
    }
    function rectsOverlap(a, b) {
        const ap = a.mapToItem(table, 0, 0)
        const bp = b.mapToItem(table, 0, 0)
        return ap.x < bp.x + b.width - 0.5 && ap.x + a.width > bp.x + 0.5
            && ap.y < bp.y + b.height - 0.5 && ap.y + a.height > bp.y + 0.5
    }
    function mappedRectsOverlap(a, b) {
        return a.x < b.x + b.width - 0.5 && a.x + a.width > b.x + 0.5
            && a.y < b.y + b.height - 0.5 && a.y + a.height > b.y + 0.5
    }
    function assertDuelPublicFieldAllocation() {
        const board = table.presentation
        const midpoint = (board.battlefieldTop + board.battlefieldBottom) / 2
        fuzzyCompare(board.ownBattlefieldTop, midpoint + 6 * board.unit, 0.1,
                     "The public duel battlefield keeps its fixed 12-unit seam")
        fuzzyCompare(board.laneHeight,
                     (board.battlefieldBottom - board.battlefieldTop - 12 * board.unit) / 2, 0.1,
                     "Overlay text must not reserve another battlefield band")
    }
    function assertPublicPhaseAnchor() {
        const board = table.presentation, track = item("forgePhaseTrack")
        const paint = track.compactMode ? item("forgeCurrentPhase") : track
        const rect = paint.mapToItem(board, 0, 0, paint.width, paint.height)
        const banner = item("forgeOpponentDeciding")
        const expectedY = banner.visible
            ? Math.min(banner.y + banner.height + 4 * board.unit, board.battlefieldBottom - paint.height)
            : board.battlefieldMiddle - paint.height / 2
        fuzzyCompare(rect.y, expectedY, 0.1, "The phase retains the exact public floating anchor")
        fuzzyCompare(rect.x + rect.width / 2, track.x + track.width / 2, 0.1,
                     "The compact phase stays centered on the strip")
        compare(track.z, 45)
    }
    function battlefieldReadoutItems(state) {
        const labels = []
        for (const zone of state.zones.filter(zone => zone.zone === "battlefield")) {
            for (const card of zone.cards) {
                for (const prefix of ["forgeCardName-", "forgeCardStats-"]) {
                    const label = findChild(table, prefix + card.id)
                    if (label && label.visible && label.width > 0 && label.height > 0)
                        labels.push(label)
                }
            }
        }
        return labels
    }
    function verifyOverlayReadoutsClear(state, overlay, description) {
        const rect = overlay.mapToItem(table, 0, 0, overlay.width, overlay.height)
        for (const row of battlefieldReadoutRects(state))
            verify(!mappedRectsOverlap(rect, row.rect), description + " leaves " + row.label.objectName + " readable")
    }
    function battlefieldReadoutRects(state) {
        const cards = []
        for (const zone of state.zones.filter(zone => zone.zone === "battlefield")) {
            for (const card of zone.cards) {
                const root = item("forgeCard-" + card.id), face = item("forgeCardFace-" + card.id)
                // These fixtures use an opaque image placeholder. Do not
                // assume that an arbitrary loaded/custom image is opaque.
                const opaque = root.opacity === 1 && face.opacity === 1 && face.children.some(child =>
                    child.visible && child.opacity === 1 && child.color !== undefined && child.color.a === 1
                    && child.x <= 0 && child.y <= 0 && child.width >= face.width && child.height >= face.height)
                cards.push({root:root, slot:root.parent, opaque:opaque,
                    rect:face.mapToItem(table, 0, 0, face.width, face.height)})
            }
        }
        function subtract(rect, cover) {
            const left = Math.max(rect.x, cover.x), top = Math.max(rect.y, cover.y)
            const right = Math.min(rect.right, cover.right), bottom = Math.min(rect.bottom, cover.bottom)
            if (left >= right || top >= bottom) return [rect]
            return [Qt.rect(rect.x, rect.y, rect.width, top - rect.y),
                Qt.rect(rect.x, bottom, rect.width, rect.bottom - bottom),
                Qt.rect(rect.x, top, left - rect.x, bottom - top),
                Qt.rect(right, top, rect.right - right, bottom - top)]
                .filter(piece => piece.width > 0 && piece.height > 0)
        }
        const result = []
        for (const label of battlefieldReadoutItems(state)) {
            let owner = label.parent
            while (owner && !cards.some(card => card.root === owner)) owner = owner.parent
            const card = cards.find(candidate => candidate.root === owner)
            let pieces = [label.mapToItem(table, 0, 0, label.width, label.height)]
            if (card) {
                for (const front of cards) {
                    if (!front.opaque || !front.root.visible || front.slot.opacity !== 1
                        || front.slot.parent !== card.slot.parent || front.slot.stackIndex !== card.slot.stackIndex
                        || front.slot.z <= card.slot.z) continue
                    // Subtract only the actual opaque area above this label;
                    // a rear card's exposed title or P/T remains protected.
                    const uncovered = []
                    for (const piece of pieces)
                        for (const fragment of subtract(piece, front.rect)) uncovered.push(fragment)
                    pieces = uncovered
                }
            }
            for (const rect of pieces) result.push({label:label, rect:rect})
        }
        return result
    }
    function test_turnCalloutDoesNotReflowCardsOrInterceptInput() {
        window.width = 1920; window.height = 1011
        const state = snapshot()
        verify(testRulesPrompt.applySnapshot(state))
        action("activateAbility", "own-0")
        const callout = item("forgeTurnCallout")
        tryCompare(table.presentation, "width", window.width)
        verify(waitForPolish(window))
        function geometry(card) {
            const point = card.mapToItem(table, 0, 0)
            return [point.x, point.y, card.width, card.height]
        }
        const own = item("forgeCard-own-0"), opponent = item("forgeCard-opponent")
        const ownBefore = geometry(own), opponentBefore = geometry(opponent)
        state.activeSeat = 1; state.prioritySeat = 1
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(callout, "message", "Opponent's turn")
        verify(callout.visible && callout.opacity > 0)
        verify(!callout.enabled)
        compare(geometry(own), ownBefore)
        compare(geometry(opponent), opponentBefore)
        mouseClick(own)
        compare(transport.responses.length, 1)
        compare(transport.responses[0].response, "opaque-play")
    }
    function test_turnCalloutRetainsCentralComposition_data() {
        return [{tag:"own", activeSeat:0, seats:2}, {tag:"opponent", activeSeat:1, seats:2},
            {tag:"three-own", activeSeat:0, seats:3}, {tag:"three-opponent", activeSeat:2, seats:3},
            {tag:"four-own", activeSeat:0, seats:4}, {tag:"four-opponent", activeSeat:3, seats:4}]
    }
    function test_turnCalloutRetainsCentralComposition(data) {
        window.width = 1920; window.height = 1011
        const seats = Array.from({length:data.seats}, (_, index) => index)
        const state = data.seats > 2 ? edhSnapshot(seats, 0, 1) : snapshot()
        if (data.seats > 2) { room.format = "edh"; room.maxSeats = 4 }
        state.activeSeat = data.activeSeat; state.prioritySeat = data.activeSeat
        verify(testRulesPrompt.applySnapshot(state))
        const board = table.presentation, callout = item("forgeTurnCallout")
        tryCompare(board, "width", window.width)
        tryVerify(() => callout.visible && callout.opacity > 0)
        verify(waitForPolish(window))
        const centerY = data.seats === 3 ? board.battlefieldMiddle : board.height / 2
        fuzzyCompare(callout.x + callout.width / 2, board.width / 2, 1,
                     "The public turn announcement is centered on the table")
        const label = item("forgeTurnCalloutText")
        compare(label.font.pixelSize, Math.round(44 * board.unit))
        fuzzyCompare(callout.width, Math.min(board.width * 0.72, label.implicitWidth + 72 * board.unit), 0.1,
                     "Local vertical clearance preserves the public horizontal styling")
        const fullHeight = Math.min(label.implicitHeight + 36 * board.unit, board.height - 24 * board.unit)
        const originalCenter = board.mapToItem(table, board.width / 2, centerY)
        const originalRect = Qt.rect(originalCenter.x - callout.width / 2,
            originalCenter.y - fullHeight / 2, callout.width, fullHeight)
        const originalOverlaps = battlefieldReadoutRects(state).some(readout =>
            mappedRectsOverlap(originalRect, readout.rect))
        if (!originalOverlaps) {
            fuzzyCompare(callout.y + callout.height / 2, centerY, 1,
                         "An unobstructed announcement retains the original center")
            fuzzyCompare(callout.height, fullHeight, 0.1,
                         "An unobstructed announcement retains the full 36-unit vertical padding")
        } else {
            fuzzyCompare(callout.height, label.implicitHeight + 4 * board.unit, 0.1,
                         "Only colliding announcements reduce their vertical padding")
            verify(Math.abs(callout.y + callout.height / 2 - centerY) <= 12 * board.unit + 1,
                   "Local clearance stays within 12 units of the public center")
        }
        if (data.seats === 4) {
            verify(!originalOverlaps, "The original four-seat center already has room")
            fuzzyCompare(callout.y + callout.height / 2, centerY, 1)
            fuzzyCompare(callout.height, fullHeight, 0.1)
        }
        // The public 12-unit seam can leave less art-to-art space than the
        // unchanged 44-unit text plus minimum padding. A transient backdrop
        // may touch art; actual names and P/T must remain completely clear.
        verifyOverlayReadoutsClear(state, callout, "The turn announcement")
        verify(!callout.enabled, "The transient announcement never intercepts input")
    }
    function test_turnCalloutReadoutCacheFollowsGeometryAndVisibility() {
        window.width = 1920; window.height = 1011
        verify(testRulesPrompt.applySnapshot(snapshot()))
        const board = table.presentation, callout = item("forgeTurnCallout")
        tryCompare(board, "width", window.width)
        function verifyPublishedReadouts() {
            verify(waitForPolish(window))
            const expected = board.collectOverlayReadouts()
            const actual = board.overlayCardReadoutRects
            compare(actual.length, expected.length)
            for (let i = 0; i < expected.length; ++i) {
                fuzzyCompare(actual[i].x, expected[i].x, 0.01)
                fuzzyCompare(actual[i].y, expected[i].y, 0.01)
                fuzzyCompare(actual[i].width, expected[i].width, 0.01)
                fuzzyCompare(actual[i].height, expected[i].height, 0.01)
            }
        }
        callout.present("Readout cache")
        verifyPublishedReadouts()
        verify(board.overlayCardReadoutRects.length > 0)
        const before = board.overlayCardReadoutRects
        window.width = 1700; window.height = 950
        window.width = 1600; window.height = 900
        tryCompare(board, "width", window.width)
        verifyPublishedReadouts()
        verify(board.overlayCardReadoutRects.some((rect, i) =>
            rect.x !== before[i].x || rect.y !== before[i].y
            || rect.width !== before[i].width || rect.height !== before[i].height))

        callout.opacity = 0
        verifyPublishedReadouts()
        compare(board.overlayCardReadoutRects.length, 0)
        // Hidden callouts stop observing card geometry. Showing one again must
        // collect the current geometry and reconnect those dependencies.
        window.width = 1800; window.height = 980
        tryCompare(board, "width", window.width)
        callout.present("Readout cache refreshed")
        verifyPublishedReadouts()
        verify(board.overlayCardReadoutRects.length > 0)
    }
    function test_publicPhaseStripKeepsSingleLineDensity_data() {
        return [{tag:"english", language:"en"}, {tag:"chinese", language:"zh"}]
    }
    function test_publicPhaseStripKeepsSingleLineDensity(data) {
        window.width = 1920; window.height = 1011
        testTranslations.setLanguage(data.language)
        verify(testRulesPrompt.applySnapshot(snapshot()))
        const track = item("forgePhaseTrack"), label = item("forgePhaseLabel-main1")
        tryCompare(table.presentation, "width", window.width)
        verify(waitForPolish(window))
        verify(!track.compactMode)
        verify(track.height <= Math.max(18 * table.presentation.unit,
                Math.ceil(label.implicitHeight) + Theme.size(6)),
               "A single-line phase strip must not reserve a second text row: " + track.height)
        verify(label.paintedHeight <= label.height + 0.1)
    }
    function test_hoverPreviewAvoidsDecisionDock() {
        window.width = 1920; window.height = 1011
        verify(testRulesPrompt.applySnapshot(snapshot(1, 8, true)))
        combat("chooseAttackers", 1, true)
        const dock = item("rulesDecisionDock")
        verify(dock.visible && dock.width > 100)
        let rightmost = item("forgeCard-own-0")
        let rightX = rightmost.mapToItem(table, 0, 0).x
        for (let i = 1; i < 8; ++i) {
            const card = item("forgeCard-own-" + i)
            const x = card.mapToItem(table, 0, 0).x
            if (x > rightX) { rightmost = card; rightX = x }
        }
        mouseMove(table, 30, 70)
        mouseMove(rightmost, rightmost.width / 2, rightmost.height / 2)
        tryCompare(table.inspector, "previewCardId", "own-" + rightmost.objectId.split("-").pop())
        const preview = item("rulesCardHoverPreview")
        tryCompare(preview, "visible", true)
        verify(!rectsOverlap(preview, dock),
               "preview " + preview.x + "," + preview.y + " " + preview.width + "x" + preview.height
               + " overlaps dock " + dock.x + "," + dock.y + " " + dock.width + "x" + dock.height)
        const origin = rightmost.mapToItem(preview.parent, 0, 0)
        verify(preview.x >= origin.x + rightmost.width - 1
               || preview.x + preview.width <= origin.x + 1
               || preview.y + preview.height <= origin.y + 1)
        verify(preview.x >= -1 && preview.y >= -1)
        verify(preview.x + preview.width <= preview.parent.width + 1)
        verify(preview.y + preview.height <= preview.parent.height + 1)
    }
    function test_stackTextStartsBesideTheCard() {
        const state = snapshot()
        state.stack = [{id:"bolt", controllerSeat:1, identity:{name:"Lightning Bolt"},
            text:"Deal 3 damage to any target."}]
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        const entry = item("forgeStackEntry-bolt")
        const card = item("forgeStackCard-bolt")
        const name = item("forgeStackName-bolt")
        verify(Math.abs(card.width - 86 * table.presentation.unit) <= 1,
               "Stack face width is " + card.width + " at unit " + table.presentation.unit)
        const nameAt = name.mapToItem(entry, 0, 0)
        const cardAt = card.mapToItem(entry, 0, 0)
        verify(nameAt.x >= cardAt.x + card.width - 1,
               "Name x " + nameAt.x + " starts inside the face ending at " + (cardAt.x + card.width))
        verify(nameAt.x + name.width <= entry.width + 1)
        compare(name.text, "Lightning Bolt")
    }
    function test_liveBo3Summary_data() {
        return [{tag:"host", role:"player", seat:0, expected:"Game 2 · 1–0"},
            {tag:"opponent", role:"player", seat:1, expected:"Game 2 · 0–1"},
            {tag:"spectator", role:"spectator", seat:-1, expected:"Game 2 · 1–0"}]
    }
    function test_liveBo3Summary(data) {
        room.role = data.role; room.seatIndex = data.seat
        room.matchMode = "bo3"; match.gameNumber = 2; match.score = [1, 0]
        waitForRendering(table)
        const summary = item("forgeMatchSummary")
        verify(summary.visible)
        compare(item("forgeMatchSummaryText").text, data.expected)
        const settings = item("forgeGameMenu")
        verify(summary.y >= settings.y + settings.height)
        verify(summary.x + summary.width <= table.width)
        const plate = item("rulesPlayerTarget1")
        verify(summary.x >= plate.x + plate.width,
               "Match score must not cover opponent identity, life or action clock")
        match.gameNumber = 3; match.score = [1, 1]
        tryCompare(item("forgeMatchSummaryText"), "text", "Game 3 · 1–1")
        match.sideboarding = true
        tryCompare(summary, "visible", false)
        match.sideboarding = false
        tryCompare(summary, "visible", true)
        room.matchMode = "bo1"
        tryCompare(summary, "visible", false)
    }
    function test_liveBo3SummaryDoesNotReserveMultiplayerFields() {
        room.matchMode = "bo3"
        room.format = "edh"; room.deckFormat = "commander"; room.maxSeats = 4
        verify(testRulesPrompt.applySnapshot(edhSnapshot([0, 1, 2, 3], 0)))
        tryCompare(table.presentation, "multiplayer", true)
        verify(!item("forgeMatchSummary").visible)
    }
    function test_liveBo3SummaryKeepsClockAndDefaultStackClear_data() {
        return [{tag:"maximized-scale-100", width:1920, height:1011, scale:1},
            {tag:"maximized-scale-150", width:1920, height:1011, scale:1.5},
            {tag:"compact", width:1024, height:768, scale:1}]
    }
    function test_liveBo3SummaryKeepsClockAndDefaultStackClear(data) {
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        room.matchMode = "bo3"; room.actionClockEnabled = true
        room.actionClockMs = [60000, 60000]; room.actionClockRunning = 0
        const state = snapshot()
        state.stack = [{id:"bo3-stack", controllerSeat:1, identity:{name:"Lightning Bolt"},
            text:"Deal 3 damage to any target."}]
        verify(testRulesPrompt.applySnapshot(state))
        waitForRendering(table)
        const summary = item("forgeMatchSummary")
        const opponent = item("rulesPlayerTarget1")
        const stack = item("forgeStack")
        verify(summary.visible)
        verify(summary.x >= opponent.x + opponent.width)
        verify(summary.y + summary.height <= stack.y,
               "Default floating stack must not cover the BO3 score")
        verify(summary.y + summary.height <= table.height)
    }
    function test_playerIdentityStaysAboveLifeDisc_data() {
        const rows = []
        for (const role of [{role:"player", seat:0}, {role:"player", seat:1},
                            {role:"spectator", seat:-1}])
            for (const clock of [false, true])
                for (const scale of [1, 1.5])
                    rows.push({tag:role.role + "-" + role.seat + "-clock-" + clock + "-scale-" + scale,
                        role:role.role, seat:role.seat, clock:clock, scale:scale})
        return rows
    }
    function test_farLifePlateStaysClearOfDenseSupportRows_data() {
        return [{tag:"maximized", width:1920, height:1011, scale:1},
            {tag:"maximized-large-controls", width:1920, height:1011, scale:1.8},
            {tag:"compact-large-controls", width:900, height:620, scale:1.8}]
    }
    function test_farLifePlateStaysClearOfDenseSupportRows(data) {
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        testTranslations.setLanguage("zh")
        room.actionClockEnabled = true
        room.actionClockMs = [180000, 165000]
        const state = snapshot()
        state.players[1].name = "中文名字较长的远端玩家"
        const permanents = [], types = {}
        for (let index = 0; index < 64; ++index)
            permanents.push(card("far-creature-" + index, 1, "Creature " + index, true))
        for (const type of ["Land", "Artifact"])
            for (let index = 0; index < 12; ++index) {
                const name = type + " " + index
                types[name] = type
                permanents.push(card("far-" + type + "-" + index, 1, name, false))
            }
        catalog.typeOverrides = types
        state.zones[5].cards = permanents
        state.zones[5].count = permanents.length
        verify(testRulesPrompt.applySnapshot(state))
        verify(waitForPolish(window)); verify(waitForRendering(table))
        const plate = item("rulesPlayerTarget1")
        const faces = item("forgeOpponentCreatures").visibleCards.concat(
            item("forgeOpponentLands").visibleCards, item("forgeOpponentOther").visibleCards)
        compare(faces.length, permanents.length)
        for (const face of faces)
            verify(!rectsOverlap(plate, face),
                "The far identity, reserved life-change area and disc must stay clear of " + face.cardId)
    }
    function test_playerIdentityStaysAboveLifeDisc(data) {
        window.width = 1920; window.height = 1011; Theme.uiScale = data.scale
        room.role = data.role; room.seatIndex = data.seat
        room.actionClockEnabled = data.clock
        room.actionClockMs = [180000, 165000]; room.actionClockRunning = -1
        waitForRendering(table)
        function checkPlates(clockVisible) {
            for (const seat of [0, 1]) {
                const plate = item("rulesPlayerTarget" + seat)
                const disc = item("forgeLifeDisc-" + seat)
                const clock = item("forgeActionClock-" + seat)
                compare(clock.visible, clockVisible)
                for (const name of ["forgePlayerName-", "forgeActionClock-", "forgePlayerZones-"]) {
                    const row = item(name + seat)
                    if (!row.visible) continue
                    verify(!rectsOverlap(row, disc), name + seat + " overlaps the life disc")
                    const at = row.mapToItem(plate, 0, 0)
                    verify(at.y >= 0 && at.y + row.height <= disc.y,
                           "Every visible identity row must end above the life disc")
                }
                const at = disc.mapToItem(plate, 0, 0)
                verify(at.x >= 0 && at.y >= 0)
                verify(at.x + disc.width <= plate.width + 0.5)
                verify(at.y + disc.height <= plate.height + 0.5,
                       "The player target must contain its entire life disc")
                compare(plate.lifeCenterY, at.y + disc.height / 2)
                const absolute = plate.mapToItem(table, 0, 0)
                verify(absolute.x >= 0 && absolute.y >= 0)
                verify(absolute.x + plate.width <= table.width + 0.5)
                verify(absolute.y + plate.height <= table.height + 0.5)
            }
        }
        checkPlates(data.clock)
        // A room projection can turn public clocks on or off in the same
        // presentation. Both identities must reflow with the changed row.
        room.actionClockEnabled = !data.clock
        waitForRendering(table)
        checkPlates(!data.clock)
        if (data.role === "player") {
            const far = item("rulesPlayerTarget" + table.presentation.topSeat)
            prompt("chooseBoardTargets", {minSelections:1, maxSelections:1,
                targets:[{responseId:"far-player", kind:"player", seat:far.seat, label:far.name}]})
            mouseClick(far, far.width / 2, far.lifeCenterY)
            compare(transport.responses.length, 1)
            compare(transport.responses[0].targets, ["far-player"])
        }
    }
    function test_ownNameSitsAboveTheHand() {
        verify(testRulesPrompt.applySnapshot(snapshot()))
        waitForRendering(table)
        const zones = item("forgePlayerZones-0")
        const hand = item("forgeHand")
        const zonesBottom = zones.mapToItem(table, 0, zones.height).y
        verify(zonesBottom <= hand.y + 1,
               "Own identity ends at " + zonesBottom + " inside the hand at " + hand.y)
        const plate = item("rulesPlayerTarget0")
        verify(plate.y + plate.height > hand.y + 1, "Life disc should still meet the hand")
        verify(plate.y + plate.height <= hand.y + 26 * table.presentation.unit + 1,
               "Life disc covers the hand faces")
        const track = item("forgePhaseTrack")
        verify(item("forgePlayerName-1").mapToItem(table, 0, 0).y + item("forgePlayerName-1").height
               <= track.y + 1)
    }
    function test_phaseLabelsStayReadableAtScaledSizes_data() {
        return [{tag:"compact-pin", width:900, height:620, scale:1.5, seats:2, pin:true, language:"en"},
            {tag:"compact-pin-chinese", width:900, height:620, scale:1.5, seats:2, pin:true, language:"zh"},
            {tag:"compact-pin-german", width:900, height:620, scale:1.5, seats:2, pin:true, language:"de"},
            {tag:"four-normal", width:1920, height:1011, scale:1, seats:4, pin:false, language:"en"},
            {tag:"four-scaled-pin", width:1920, height:1011, scale:1.9, seats:4, pin:true, language:"en"}]
    }
    function test_phaseLabelsStayReadableAtScaledSizes(data) {
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        testTranslations.setLanguage(data.language)
        const state = data.seats === 4 ? edhSnapshot([0,1,2,3], 0, 1) : snapshot(1, 1)
        if (data.seats === 4) { room.format = "edh"; room.maxSeats = 4 }
        state.activeSeat = 0; state.prioritySeat = 0
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        if (data.pin) table.openCardDetails(data.seats === 4 ? "creature-0-0" : "own-0")
        verify(waitForPolish(window)); waitForRendering(table)
        const track = item("forgePhaseTrack")
        const steps = ["untap", "upkeep", "draw", "main1", "begin_combat", "declare_attackers",
            "declare_blockers", "combat_damage", "end_combat", "main2", "end", "cleanup"]
        const phaseHeight = track.height
        const bandHeight = table.presentation.centerBandHeight
        verify(track.width > 0)
        verify(bandHeight < table.height * 0.25, "Phase information must not consume the battlefield")
        function assertLabel(label) {
            verify(label.font.pixelSize >= Theme.fontSize(11), "Phase text must keep a readable scaled font")
            verify(!label.truncated, "The phase name must not be elided")
            verify(label.paintedWidth <= label.width + 0.5 && label.paintedHeight <= label.height + 0.5,
                   "The complete phase name must fit: " + label.text + " painted " + label.paintedWidth + "×"
                   + label.paintedHeight + " in " + label.width + "×" + label.height)
        }
        for (let index = 0; index < steps.length; ++index) {
            state.step = steps[index]
            verify(testRulesPrompt.applySnapshot(state))
            verify(waitForPolish(window)); waitForRendering(table)
            compare(track.height, phaseHeight, "Changing phases must not move the battlefield")
            compare(table.presentation.centerBandHeight, bandHeight)
            if (track.compactMode) {
                const current = item("forgeCurrentPhaseLabel")
                compare(current.text, I18n.gamePhaseLabel(steps[index]))
                assertLabel(current)
            } else {
                for (const step of steps) {
                    const cell = item("forgePhase-" + step)
                    const label = cell.children.find(child => typeof child.text === "string")
                    assertLabel(label)
                    compare(label.text, I18n.gamePhaseLabel(step))
                    compare(cell.current, step === steps[index])
                    verify(cell.x >= 0 && cell.x + cell.width <= track.width + 0.5)
                }
            }
        }
        if (track.compactMode) {
            // Advancing the fixture through priority steps may run its
            // existing automatic pass policy before the overview opens.
            const responseCount = transport.responses.length
            const disclosure = item("forgeCurrentPhase")
            const overview = item("forgePhaseOverview")
            disclosure.forceActiveFocus(); keyClick(Qt.Key_Return)
            tryCompare(overview, "opened", true)
            tryCompare(table.presentation, "modalOpen", true)
            compare(transport.responses.length, responseCount)
            verify(!item("rulesCardHoverPreview").visible)
            const list = findChild(overview.contentItem, "forgePhaseOverviewList")
            verify(list !== null)
            compare(list.count, steps.length)
            try {
                for (let index = 0; index < steps.length; ++index) {
                    state.step = steps[index]
                    verify(testRulesPrompt.applySnapshot(state))
                    tryCompare(list, "currentIndex", index)
                    verify(waitForPolish(window)); waitForRendering(table)
                    const label = findChild(list, "forgePhaseOverviewLabel-" + steps[index])
                    verify(label !== null)
                    compare(label.text, table.stepLabel(steps[index]))
                    assertLabel(label)
                    const at = label.mapToItem(list, 0, 0)
                    verify(at.y >= -0.5 && at.y + label.height <= list.height + 0.5,
                           "The current phase must remain visible in the read-only overview")
                    mouseClick(label)
                    compare(transport.responses.length, responseCount, "Viewing phases must not submit a game response")
                }
                keyClick(Qt.Key_Escape)
                tryCompare(overview, "visible", false)
                compare(table.rulesSession.step, "cleanup")
                compare(transport.responses.length, responseCount)
            } finally { overview.close() }
        }
    }
    function test_phaseOverviewClosesWithItsTableContext_data() {
        return [{tag:"disconnect"}, {tag:"viewer"}, {tag:"new-game"}, {tag:"opening"}, {tag:"sideboarding"}]
    }
    function test_phaseOverviewClosesWithItsTableContext(data) {
        window.width = 900; window.height = 620; Theme.uiScale = 1.5
        const state = snapshot(1, 1)
        verify(testRulesPrompt.applySnapshot(state))
        table.openCardDetails("own-0")
        waitForRendering(table)
        verify(item("forgePhaseTrack").compactMode)
        const overview = item("forgePhaseOverview")
        mouseClick(item("forgeCurrentPhase"))
        tryCompare(overview, "opened", true)
        try {
            if (data.tag === "disconnect") transport.inRoom = false
            else if (data.tag === "viewer") room.seatIndex = 1
            else if (data.tag === "sideboarding") match.sideboarding = true
            else {
                if (data.tag === "new-game") state.gameId = "phase-overview-next-game"
                else { state.turn = 0; state.activeSeat = -1 }
                verify(testRulesPrompt.applySnapshot(state))
            }
            tryCompare(overview, "visible", false)
            compare(table.presentation.modalOpen, false)
        } finally { overview.close() }
    }
    function test_combatLinesKeepPhaseAndPlayerTextReadable_data() {
        return [{tag:"normal", width:1920, height:1011, scale:1, seats:2, pin:false},
            {tag:"compact-pin", width:900, height:620, scale:1.5, seats:2, pin:true},
            {tag:"four-scaled", width:1920, height:1011, scale:1.9, seats:4, pin:false},
            {tag:"opponent-deciding", width:1920, height:1011, scale:1, seats:2, pin:false, deciding:true}]
    }
    function textRegionChangedPixels(withArrow, withoutArrow, region) {
        const bounds = region.mapToItem(table, 0, 0, region.width, region.height)
        const scale = withArrow.width / table.width
        let changed = 0
        for (let y = Math.ceil((bounds.y + 2) * scale); y < Math.floor((bounds.y + bounds.height - 2) * scale); ++y) {
            for (let x = Math.ceil((bounds.x + 2) * scale); x < Math.floor((bounds.x + bounds.width - 2) * scale); ++x) {
                if (withArrow.red(x,y) !== withoutArrow.red(x,y)
                    || withArrow.green(x,y) !== withoutArrow.green(x,y)
                    || withArrow.blue(x,y) !== withoutArrow.blue(x,y)) ++changed
            }
        }
        return changed
    }
    function test_combatLinesKeepPhaseAndPlayerTextReadable(data) {
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        const state = data.seats === 4 ? edhSnapshot([0,1,2,3], 0, 1) : snapshot(1, 1)
        if (data.seats === 4) { room.format = "edh"; room.maxSeats = 4 }
        const attackingSeat = data.seats === 4 ? 2 : 1
        const attacker = state.zones.find(zone => zone.ownerSeat === attackingSeat && zone.zone === "battlefield").cards[0]
        attacker.attacking = true; attacker.attackingPlayer = 0
        state.activeSeat = 0; state.prioritySeat = data.deciding ? 1 : 0; state.step = "declare_blockers"
        verify(testRulesPrompt.applySnapshot(state))
        if (data.deciding) prompt("", {pending:false, supported:false})
        else prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        testGameTable.applySnapshot({log:[{id:1, kind:"cast", text:"Plains tapped", seat:1}]})
        if (data.pin) table.openCardDetails("own-0")
        mouseMove(table, 1, 1)
        verify(waitForPolish(window)); verify(waitForRendering(table))
        const arrow = item("forgeRelationship-attack-" + attacker.id + "-")
        verify(arrow.visible && arrow.validAnchors)
        const endpoint = arrow.endPoint
        compare(endpoint, table.presentation.playerPoint(0))
        // Compare the arrow only after the independent transient announcement
        // has finished; its fade is not a change in arrow/text layering.
        tryCompare(item("forgeTurnCallout"), "visible", false, 5000)
        verify(waitForPolish(window)); waitForRendering(table)
        const withArrow = grabImage(table)
        arrow.visible = false
        verify(waitForRendering(table))
        const withoutArrow = grabImage(table)
        verify(!withArrow.equals(withoutArrow), "The complete-table capture must contain the real attack line")
        const phaseTrack = item("forgePhaseTrack")
        const phasePaint = phaseTrack.compactMode ? item("forgeCurrentPhase") : phaseTrack
        const phaseChanges = textRegionChangedPixels(withArrow, withoutArrow, phasePaint)
        const identityChanges = data.seats === 2 ? textRegionChangedPixels(withArrow, withoutArrow, item("forgePlayerName-0").parent) : 0
        const status = item(data.deciding ? "forgeOpponentDecidingText" : "forgeRecentActionText")
        verify(status.visible)
        const statusChanges = textRegionChangedPixels(withArrow, withoutArrow, status)
        compare(phaseChanges + identityChanges + statusChanges, 0,
                "Attack lines must stay behind text surfaces; changed phase pixels=" + phaseChanges
                + ", player identity pixels=" + identityChanges + ", public status pixels=" + statusChanges)
        arrow.visible = true
        compare(arrow.endPoint, endpoint, "Text protection must not change the attack target")
    }
    function test_aimLinesKeepStatusTextReadable_data() {
        return [{tag:"recent-blocking", target:"forgeRecentActionText", kind:"chooseBlockers"},
            {tag:"match-summary", target:"forgeMatchSummaryText", kind:"chooseAttackers"},
            {tag:"recoverable-error", target:"rulesErrorBanner", kind:"chooseAttackers"}]
    }
    function test_aimLinesKeepStatusTextReadable(data) {
        window.width = 1920; window.height = 1011
        room.matchMode = "bo3"
        combat(data.kind, 1, true)
        testGameTable.applySnapshot({log:[{id:1, kind:"rules_tap",
            text:"Audit Player 1: Colossal Dreadmaw tapped.", seat:1}]})
        if (data.tag === "recoverable-error") transport.lastError = "rules_action_rejected"
        try {
            const source = item("forgeCard-own-0"), aim = item("forgeCombatAimArrow")
            mouseClick(source)
            const target = item(data.target)
            verify(target.visible)
            mouseMove(target, target.width / 2, target.height / 2)
            tryCompare(aim, "visible", true)
            tryCompare(aim, "snapped", false)
            const endpoint = aim.endPoint
            const center = target.mapToItem(table.presentation, target.width / 2, target.height / 2)
            verify(Math.abs(endpoint.x - center.x) <= 1 && Math.abs(endpoint.y - center.y) <= 1)
            verify(waitForRendering(table))
            const withArrow = grabImage(table)
            aim.visible = false
            verify(waitForRendering(table))
            const withoutArrow = grabImage(table)
            aim.visible = Qt.binding(() => table.presentation.combatAiming && aim.startPoint.x !== 0)
            verify(!withArrow.equals(withoutArrow), "The pointer-driven combat arrow must actually render")
            compare(textRegionChangedPixels(withArrow, withoutArrow, target), 0,
                "Aiming must not paint over public status text")
            compare(aim.endPoint, endpoint)
            compare(transport.responses.length, 0)
        } finally { transport.lastError = "" }
    }
    function test_combatCurvesAvoidPublicCardReadouts_data() {
        return [{tag:"two-seat", seats:2}, {tag:"four-seat-pinned", seats:4}]
    }
    function test_combatCurvesAvoidPublicCardReadouts(data) {
        window.width = 1920; window.height = 1011
        const state = data.seats === 4 ? edhSnapshot([0,1,2,3], 0, 1) : snapshot(1,1)
        if (data.seats === 4) { room.format="edh"; room.maxSeats=4; Theme.uiScale=1.5 }
        const own = state.zones.find(zone => zone.zone === "battlefield" && zone.ownerSeat === 0)
        const other = state.zones.find(zone => zone.zone === "battlefield" && zone.ownerSeat === 1)
        const source = own.cards[0], target = other.cards[0]
        source.blocking = [target.id]; source.damage = 1
        source.enteredThisTurn = true; source.summoningSick = true
        target.attacking = true; target.attackingPlayer = 0
        const attached = card("readout-attachment", 0, "Rancor", false)
        attached.attachedTo = source.id; own.cards.push(attached); own.count++
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"$pass",kind:"pass",label:"Pass"}]})
        if (data.seats === 4) table.openCardDetails(source.id)
        mouseMove(table,1,1); verify(waitForPolish(window)); verify(waitForRendering(table))
        const arrow = item("forgeRelationship-block-" + source.id + "-" + target.id)
        verify(arrow.visible && arrow.validAnchors)
        verify(arrow.excludedRects.length > 0)
        const regions = [item("forgeCardName-"+source.id), item("forgeCardStats-"+source.id),
            item("forgeCardInteractionHint-"+source.id), item("forgeAttachmentName-readout-attachment")]
        const stateText = item("forgeCardState-"+source.id)
        verify(stateText.text.includes("Summoning sickness"))
        // Exercise the actual visible lines, not the unused area of a
        // bottom-aligned state label's allocated rectangle.
        const stateRegion = createTemporaryObject(readoutRegion, stateText, {
            y:stateText.height-Math.min(stateText.height,stateText.implicitHeight),
            width:stateText.width,height:Math.min(stateText.height,stateText.implicitHeight)})
        regions.push(stateRegion)
        for (const region of regions) {
            verify(region.visible && region.width > 0 && region.height > 0)
            const rect=region.mapToItem(table.presentation,0,0,region.width,region.height)
            // Use the real relationship renderer to probe a curve crossing
            // each public readout. These positions never submit a game action.
            arrow.startPoint=Qt.point(rect.x-35,rect.y+rect.height/2)
            arrow.endPoint=Qt.point(rect.x+rect.width+35,rect.y+rect.height/2)
            const start=arrow.startPoint,end=arrow.endPoint
            arrow.excludedRects=[]
            verify(waitForRendering(table)); const uncovered=grabImage(table)
            arrow.visible=false
            verify(waitForRendering(table)); const without=grabImage(table)
            verify(textRegionChangedPixels(uncovered,without,region)>0,
                "The probe must reproduce the reported text crossing")
            arrow.excludedRects=Qt.binding(()=>table.presentation.arrowTextRects)
            arrow.visible=true
            verify(waitForRendering(table)); const protectedImage=grabImage(table)
            compare(textRegionChangedPixels(protectedImage,without,region),0,
                "Curves must leave public card text unchanged: "+region.objectName)
            compare(arrow.startPoint,start); compare(arrow.endPoint,end)
        }
        compare(transport.responses.length,0)
    }
    Component { id: readoutRegion; Item {} }
    function test_arrowReadoutsTrackVisibleCardsAndStayIdleWithoutLines() {
        const board=table.presentation
        compare(board.hasVisibleArrows,false); compare(board.arrowTextRects.length,0)
        const state=snapshot(1,70,true)
        state.zones[5].cards[0].attacking=true; state.zones[5].cards[0].attackingPlayer=0
        verify(testRulesPrompt.applySnapshot(state)); waitForRendering(table)
        const lane=item("forgeOwnCreatures"), viewport=lane.scrollArea
        tryCompare(board,"hasVisibleArrows",true)
        verify(viewport.contentHeight>viewport.height)
        function covers(point) {
            return board.arrowTextRects.some(rect=>point.x>=rect.x && point.x<=rect.x+rect.width
                && point.y>=rect.y && point.y<=rect.y+rect.height)
        }
        const first=item("forgeCardName-own-0")
        verify(covers(first.mapToItem(board,first.width/2,first.height/2)))
        verify(lane.reveal("own-69")); waitForRendering(table)
        const last=item("forgeCardName-own-69")
        verify(covers(last.mapToItem(board,last.width/2,last.height/2)))
        const clip=viewport.mapToItem(board,0,0,viewport.width,viewport.height)
        for (const rect of lane.readoutRects(board)) {
            verify(rect.x>=clip.x-0.1 && rect.y>=clip.y-0.1)
            verify(rect.x+rect.width<=clip.x+clip.width+0.1 && rect.y+rect.height<=clip.y+clip.height+0.1)
        }
        const slot=lane.itemFor("own-69"), before=last.mapToItem(board,last.width/2,last.height/2)
        slot.visualDx=12; slot.visualDy=-5
        waitForRendering(table)
        const moved=last.mapToItem(board,last.width/2,last.height/2)
        compare(moved.x,before.x+12); compare(moved.y,before.y-5); verify(covers(moved))
        slot.visualDx=0; slot.visualDy=0
        const requests=catalog.faceRequests.length
        state.zones[4].cards[69].visible=false; state.zones[4].cards[69].identity={name:"SECRET"}
        verify(testRulesPrompt.applySnapshot(state)); waitForRendering(table)
        verify(!catalog.faceRequests.includes("SECRET")); verify(!catalog.nameRequests.includes("SECRET"))
        compare(catalog.faceRequests.length,requests)
        compare(item("forgeCardName-own-69").text,"Hidden card")
        compare(transport.responses.length,0)
    }
    function test_arrowReadoutsMergeClosedPilesAndPreserveExpandedStrips() {
        const state=snapshot(1,40,false)
        state.zones[5].cards[0].attacking=true; state.zones[5].cards[0].attackingPlayer=0
        verify(testRulesPrompt.applySnapshot(state)); waitForRendering(table)
        const board=table.presentation,lane=item("forgeOwnCreatures")
        tryCompare(lane,"stackCount",1)
        verify(lane.readoutRects(board).length<=4,"Closed copies must not generate per-copy text obstacles")
        lane.openFan(0); tryCompare(lane.scrollArea,"clip",true)
        lane.scrollArea.contentY=lane.slotY(0)+20*lane.unit; waitForRendering(table)
        const clip=lane.scrollArea.mapToItem(board,0,0,lane.scrollArea.width,lane.scrollArea.height)
        verify(lane.readoutRects(board).some(rect=>rect.y<clip.y-5),
            "An unclipped fan must retain visible text beyond its original lane")
        lane.closeFan(); lane.scrollArea.contentY=0
    }

    Component { id: readoutChanges; SignalSpy { signalName: "arrowTextRectsChanged" } }
    function test_newBlockerHintIsProtectedOnItsFirstFrame() {
        window.width = 1920; window.height = 1011
        const state = snapshot(1, 3, true), opponents = state.zones[5]
        opponents.cards = ["Centaur Courser", "Colossal Dreadmaw", "Duskdale Wurm", "Rumbling Baloth"]
            .map((name, index) => card("attacker-" + index, 1, name, true))
        opponents.count = opponents.cards.length
        state.activeSeat = 1; state.prioritySeat = 0; state.step = "declare_attackers"
        opponents.cards[0].attacking = true; opponents.cards[0].attackingPlayer = 0
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        mouseMove(table, 1, 1)
        verify(waitForRendering(table))
        const board = table.presentation
        verify(board.hasVisibleArrows, "The first attack line must already be active")
        Theme.motionEnabled = true
        opponents.cards[1].attacking = true; opponents.cards[1].attackingPlayer = 0
        opponents.cards[1].tapped = true
        state.step = "declare_blockers"
        verify(testRulesPrompt.applySnapshot(state))
        // Do not use prompt(), which deliberately waits for a rendered frame.
        // Forge may publish the combat snapshot and its decision together.
        verify(testRulesPrompt.applyPrompt({roomId:"DUEL01", gameId:"duel-game", promptId:++serial,
            pending:true, supported:true, kind:"chooseBlockers", title:"Declare blockers", detail:"",
            options:[], choices:[], cards:[], targets:[], contextCards:[], contextTargets:[],
            damageTargets:[], scryDestinations:[], totalDamage:0,
            combatSources:[{responseId:"blocker", objectId:"own-0", label:"Bear", name:"Bear 0",
                validTargetIds:["attacker"], maxAssignments:1}],
            combatTargets:[{responseId:"attacker", kind:"attacker", objectId:"attacker-1",
                label:"Colossal Dreadmaw", minAssignments:0, maxAssignments:8}]}))
        const hint = item("forgeCardInteractionHint-attacker-1")
        const arrow = item("forgeRelationship-attack-attacker-1-")
        const slot = item("forgeOpponentCreatures").itemFor("attacker-1")
        compare(hint.text, "Block this creature")
        verify(arrow.visible && arrow.validAnchors)
        // An immediate capture takes the same polish/render path as the
        // native audit. It must not need an event-loop wait to protect text.
        const firstFrame = grabImage(table)
        const position = hint.mapToItem(board, 0, 0)
        arrow.visible = false
        const withoutArrow = grabImage(table)
        compare(hint.mapToItem(board, 0, 0), position,
            "The pixel comparison must use the same animation pose")
        verify(!firstFrame.equals(withoutArrow), "The real attack curve must be present")
        compare(textRegionChangedPixels(firstFrame, withoutArrow, hint), 0,
            "The newly visible blocker hint must be protected in the first frame")
        arrow.visible = true
        let movingFrames = 0
        for (let frame = 0; frame < 18; ++frame) {
            wait(16)
            grabImage(table)
            const center = slot.mapToItem(board, slot.width / 2, slot.height / 2)
            verify(Math.abs(arrow.startPoint.x - center.x) < 0.001
                && Math.abs(arrow.startPoint.y - center.y) < 0.001,
                "The attack curve must remain attached to the painted card during its glide")
            if (Math.abs(slot.visualDy) > 0.1) ++movingFrames
            const rect = hint.mapToItem(board, 0, 0, hint.width, hint.height)
            for (const interval of arrow.geometry.intervals) {
                for (let sample = 0; sample <= 300; ++sample) {
                    const t = interval[0] + (interval[1] - interval[0]) * sample / 300, u = 1 - t
                    const x = u*u*arrow.startPoint.x + 2*u*t*arrow.controlPoint.x + t*t*arrow.endPoint.x
                    const y = u*u*arrow.startPoint.y + 2*u*t*arrow.controlPoint.y + t*t*arrow.endPoint.y
                    verify(x <= rect.x + 1 || x >= rect.x + rect.width - 1
                        || y <= rect.y + 1 || y >= rect.y + rect.height - 1,
                        "A rendered attack segment must not cross the moving blocker hint")
                }
            }
        }
        verify(movingFrames > 0, "The regression must exercise real card animation")
        tryCompare(slot, "visualDy", 0)
        compare(transport.responses.length, 0)
    }
    function test_specialFramesCropOnlyArtwork_data() {
        return [
            {tag:"saga", frame:"saga", x:250, y:150, w:190, h:350},
            {tag:"class", frame:"class", x:55, y:90, w:175, h:430},
            {tag:"planeswalker", frame:"planeswalker", x:39, y:95, w:410, h:238},
            {tag:"battle", frame:"battle", x:70, y:80, w:195, h:570},
            {tag:"flip-front", frame:"flip", x:45, y:218, w:395, h:220},
            {tag:"flip-back", frame:"flip-back", x:45, y:218, w:395, h:220}]
    }
    function test_specialFramesCropOnlyArtwork(data) {
        const name = "Frame reference " + data.tag
        catalog.artFrames = ({[name]:data.frame})
        catalog.tableFaceImages = ({[name]:"data:image/svg+xml," + encodeURIComponent(
            '<svg xmlns="http://www.w3.org/2000/svg" width="488" height="680">'
            + '<rect width="488" height="680" fill="red"/>'
            + '<rect x="' + data.x + '" y="' + data.y + '" width="' + data.w
            + '" height="' + data.h + '" fill="lime"/></svg>')})
        const state = snapshot()
        state.zones.find(zone => zone.zone === "battlefield" && zone.ownerSeat === 0)
            .cards[0].identity = {name:name, setCode:"TST", collectorNumber:"1"}
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        verify(waitForRendering(table))
        const tile = item("forgeCard-own-0"), art = item("forgeCardArt-own-0")
        compare(tile.displayName, name)
        tryCompare(art, "status", Image.Ready)
        tryCompare(tile, "artFrame", data.frame)
        mouseMove(table, table.width - 2, 2)
        table.inspector.clear()
        // The centered row can be underneath the brief new-turn callout.
        // Sample the card artwork after that independent overlay has left.
        tryCompare(item("forgeTurnCallout"), "visible", false, 3000)
        verify(waitForPolish(window))
        const pixels = grabImage(table)
        for (const x of [0.3, 0.5, 0.7]) {
            for (const y of (data.frame === "planeswalker" ? [0.35,0.65,0.9] : [0.35,0.5,0.65])) {
                const point = tile.mapToItem(table, tile.width*x, tile.height*y)
                const px = Math.round(point.x), py = Math.round(point.y)
                verify(pixels.green(px, py) > pixels.red(px, py) * 2,
                       "Printed text outside the art region must not enter the cropped tile: "
                       + [data.frame, tile.width, tile.height, px, py, pixels.red(px, py), pixels.green(px, py),
                          art.width, art.height, art.rotation, art.implicitWidth, art.implicitHeight].join(","))
            }
        }
        const calls = catalog.artFrameRequests.length
        window.width -= 40
        verify(waitForRendering(tile))
        compare(catalog.artFrameRequests.length, calls, "Resizing must not repeat metadata lookups")
    }
    function test_hiddenFacesNeverRequestArtFrameMetadata() {
        const state = snapshot()
        const hidden = state.zones.find(zone => zone.zone === "battlefield" && zone.ownerSeat === 0).cards[0]
        hidden.identity = {name:"Secret face"}
        hidden.faceDown = true
        verify(testRulesPrompt.applySnapshot(state))
        verify(waitForRendering(table))
        const tile = item("forgeCard-own-0")
        verify(!tile.publicFace)
        compare(tile.artFrame, "full")
        verify(catalog.artFrameRequests.indexOf("Secret face") < 0)
        catalog.language = "zh"
        catalog.artCacheContentsChanged()
        verify(waitForRendering(tile))
        verify(catalog.artFrameRequests.indexOf("Secret face") < 0)
    }
    function test_animatedCombatResizePublishesCompleteReadouts() {
        Theme.motionEnabled=true
        window.width=1920;window.height=1011;Theme.uiScale=1.5
        room.format="edh";room.maxSeats=4
        const state=edhSnapshot([0,1,2,3],0,2)
        for (const zone of state.zones.filter(zone=>zone.zone==="battlefield")) {
            zone.cards.filter(card=>card.power).forEach((card,index)=>{
                card.attacking=true;card.attackingPlayer=(zone.ownerSeat+index+1)%4
            })
        }
        state.step="declare_blockers"
        verify(testRulesPrompt.applySnapshot(state)); wait(Theme.motionNormal+100)
        table.openCardDetails("creature-0-0")
        tryCompare(table.presentation,"sidePanelOpen",true)
        wait(Theme.motionNormal+100)
        mouseClick(item("clearRulesCardInspectorButton"))
        tryCompare(table.presentation,"sidePanelOpen",false)
        wait(Theme.motionNormal+100)
        const board=table.presentation
        const changes=createTemporaryObject(readoutChanges,table,{target:board})
        verify(changes.valid)
        window.width=900;window.height=620
        compare(changes.count,0,"Resize must finish its related geometry changes before publishing arrow readouts")
        verify(waitForPolish(window));verify(waitForRendering(table))
        tryVerify(()=>changes.count>0)
        verify(changes.count<=8,"One rendered resize must not publish thousands of intermediate readouts")
        wait(Theme.motionNormal+100)
        for (const seat of [0,1,2,3]) {
            const label=item("forgeCardName-creature-"+seat+"-0")
            const point=label.mapToItem(board,label.width/2,label.height/2)
            verify(board.arrowTextRects.some(rect=>point.x>=rect.x && point.x<=rect.x+rect.width
                && point.y>=rect.y && point.y<=rect.y+rect.height),
                "The final compact card name must remain protected")
            const arrow=item("forgeRelationship-attack-creature-"+seat+"-0-")
            verify(arrow.visible && arrow.validAnchors && arrow.geometry.path.length>0)
            compare(arrow.endPoint,board.playerPoint((seat+1)%4))
        }
        room.format="modern";room.maxSeats=2
        verify(testRulesPrompt.applySnapshot(snapshot(7,2,true)))
        wait(Theme.motionNormal+100)
        compare(board.hasVisibleArrows,false);tryCompare(board,"arrowTextRects",[])
        compare(transport.responses.length,0)
    }

}
