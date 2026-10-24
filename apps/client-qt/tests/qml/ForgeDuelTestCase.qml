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
    when: windowShown

    // Each discovered suite owns its own model state, window and temporary objects.
    readonly property alias soundRecorder: fixtureSoundRecorder
    readonly property alias window: fixtureWindow
    readonly property alias room: fixtureRoom
    readonly property alias match: fixtureMatch
    readonly property alias transport: fixtureTransport
    readonly property alias catalog: fixtureCatalog
    readonly property alias table: fixtureTable
    readonly property alias shortLane: fixtureShortLane
    readonly property alias pileObstacleField: fixturePileObstacleField
    readonly property alias mixedSupportField: fixtureMixedSupportField
    readonly property alias previewInputTargetComponent: fixturePreviewInputTargetComponent
    readonly property alias otherWindowComponent: fixtureOtherWindowComponent
    readonly property alias readoutRegion: fixtureReadoutRegion
    readonly property alias readoutChanges: fixtureReadoutChanges

    property int serial: 1000
    QtObject {
        id: fixtureSoundRecorder
        property var cues: []
        function play(cue) { cues = cues.concat([cue]) }
    }
    ApplicationWindow {
        id: fixtureWindow
        width: 1600; height: 1000; visible: true
        property bool feedbackInteractionOpen: false
        property var openedScreen: ({})
        function pushScreen(url, properties) { openedScreen = {url, properties} }
        QtObject {
            id: fixtureRoom
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
            id: fixtureMatch
            property int gameNumber: 1
            property var score: [0, 0]
            property var result: ({})
            property var sideboard: ({})
            property bool sideboarding: false
        }
        QtObject {
            id: fixtureTransport
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
            id: fixtureCatalog
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
            id: fixtureTable
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
    Component {
        id: fixtureShortLane
        ForgeCardLane {
            tableController: table
            ownerSeat: 0
            width: 400; height: 70
            showCaption: false
        }
    }
    Component {
        id: fixturePileObstacleField
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
    Component {
        id: fixtureMixedSupportField
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
        id: fixturePreviewInputTargetComponent
        MouseArea {
            acceptedButtons: Qt.AllButtons
            property int clicks: 0
            onClicked: clicks++
        }
    }
    Component {
        id: fixtureOtherWindowComponent
        ApplicationWindow { width:320; height:200; visible:true; transientParent:null }
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
    function surveilPrompt() {
        prompt("chooseBoolean", {title:"Confirm decision", detail:"Put Troll of Khazad-dûm on the top of library or graveyard?",
            contextCards:[{id:"context-card:0", name:"Troll of Khazad-dûm"}],
            contextText:"Troll of Khazad-dûm can't be blocked except by three or more creatures.\nSwampcycling {1}",
            minChoiceTotal:1, maxChoiceTotal:1,
            choices:[{responseId:"choice:0", label:"Graveyard", weight:1, canRepeat:false},
                {responseId:"choice:1", label:"Library", weight:1, canRepeat:false}]})
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
    function manaPrompt(paymentId, options) {
        prompt("payManaCost", {title:"Pay Mana Cost: {G}", paymentId:paymentId || "",
            options:options})
    }
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
    function battlefieldReadoutRects(state, includeBadges) {
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
            // Composition protects the painted P/T badge as well as its text.
            const readout = includeBadges && label.objectName.indexOf("forgeCardStats-") === 0
                ? label.parent : label
            let pieces = [readout.mapToItem(table, 0, 0, readout.width, readout.height)]
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
    Component { id: fixtureReadoutRegion; Item {} }
    Component { id: fixtureReadoutChanges; SignalSpy { signalName: "arrowTextRectsChanged" } }
}
