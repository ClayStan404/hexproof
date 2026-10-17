// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"
import "../../qml/screens"

TestCase {
    id: testCase
    name: "ForgePhaseOverlay"
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


    function item(name) {
        let value = null
        tryVerify(() => { value = findChild(table, name); return value !== null }, 5000, name)
        return value
    }
    function settle() {
        verify(waitForPolish(window))
        waitForRendering(table)
    }
    function apply(state) {
        verify(testRulesPrompt.applySnapshot(state))
        settle()
    }
    function prompt(kind, extra) {
        transport.rulesResponsePending = false
        verify(testRulesPrompt.applyPrompt(Object.assign({roomId:"DUEL01", gameId:"duel-game",
            pending:true, supported:true, promptId:++serial, kind:kind, title:"Choose", detail:"",
            options:[], choices:[], cards:[], targets:[], contextCards:[], contextTargets:[],
            combatSources:[], combatTargets:[], damageTargets:[], scryDestinations:[], totalDamage:0}, extra || {})))
        settle()
    }
    function init() {
        window.width = 1920; window.height = 1011
        window.requestActivate(); tryCompare(window, "active", true)
        Theme.uiScale = 1.25; Theme.motionEnabled = false
        testTranslations.setLanguage("en")
        room.role = "player"; room.seatIndex = 0; room.spectatorsSeeHands = false
        room.format = "modern"; room.deckFormat = "modern"; room.maxSeats = 2
        transport.inRoom = true; transport.responses = []; transport.rulesResponsePending = false
        transport.lastError = ""
        table.inspector.clear(); table.showGameLogRail = false
        testGameTable.applySnapshot({log:[]}); testRulesPrompt.clear()
        table.priority.setFullControl(true)
    }
    function cleanup() {
        item("forgePhaseOverview").close()
        table.inspector.clear(); testRulesPrompt.clear()
        testGameTable.applySnapshot({log:[]}); transport.lastError = ""
        Theme.uiScale = 1; Theme.motionEnabled = false
        testTranslations.setLanguage("en")
    }
    function bounds(target) {
        return target.mapToItem(table.presentation, 0, 0, target.width, target.height)
    }
    function captureCards(ids) {
        return ids.map(id => ({id:id, rect:bounds(item("forgeCard-" + id))}))
    }
    function assertCardsUnchanged(cards, context) {
        for (const row of cards) {
            const current = bounds(item("forgeCard-" + row.id))
            for (const key of ["x", "y", "width", "height"])
                fuzzyCompare(current[key], row.rect[key], 0.1,
                             context + " must not reflow " + row.id + "." + key)
        }
    }
    function assertPublicDuelGeometry() {
        const board = table.presentation
        const midpoint = (board.battlefieldTop + board.battlefieldBottom) / 2
        fuzzyCompare(board.ownBattlefieldTop, midpoint + 6 * board.unit, 0.1,
                     "The own battlefield begins at the public midpoint + 6 units")
        fuzzyCompare(board.laneHeight,
                     (board.battlefieldBottom - board.battlefieldTop - 12 * board.unit) / 2, 0.1,
                     "Phase and status overlays must not remove a band from either battlefield")
    }
    function overlaps(a, b) {
        return a.x < b.x + b.width - 0.1 && a.x + a.width > b.x + 0.1
            && a.y < b.y + b.height - 0.1 && a.y + a.height > b.y + 0.1
    }
    function phaseBounds() {
        const track = item("forgePhaseTrack")
        return bounds(track.compactMode ? item("forgeCurrentPhase") : track)
    }
    function assertStatusOverlaysClear(state) {
        const track = item("forgePhaseTrack"), phaseRect = phaseBounds()
        const strip = item("forgeRecentActions"), stripRect = bounds(strip)
        const deciding = item("forgeOpponentDeciding")
        if (deciding.visible)
            verify(!overlaps(phaseRect, bounds(deciding)), "The current phase and deciding message remain separate")
        if (strip.visible)
            verify(!overlaps(stripRect, phaseRect), "Recent actions stay clear of the phase labels")
        for (const zone of state.zones.filter(zone => zone.zone === "battlefield")) {
            for (const card of zone.cards) {
                const faceRect = bounds(item("forgeCardFace-" + card.id))
                if (strip.visible)
                    verify(!overlaps(stripRect, faceRect), "The public action leaves " + card.id + " clear")
                for (const prefix of ["forgeCardName-", "forgeCardStats-"]) {
                    const label = findChild(table, prefix + card.id)
                    if (deciding.visible && label && label.visible && label.width > 0 && label.height > 0)
                        verify(!overlaps(bounds(deciding), bounds(label)), "The deciding banner leaves " + prefix + card.id + " readable")
                }
            }
        }
    }
    function assertPublicPhaseAnchor() {
        const rect = phaseBounds(), board = table.presentation
        const track = item("forgePhaseTrack"), deciding = item("forgeOpponentDeciding")
        const preferredTop = deciding.visible ? Math.min(bounds(deciding).bottom + 4 * board.unit,
                                                         board.battlefieldBottom - rect.height)
                                             : board.battlefieldMiddle - rect.height / 2
        fuzzyCompare(rect.y, preferredTop, 0.1, "The phase keeps the exact public floating anchor")
        fuzzyCompare(rect.x + rect.width / 2, track.x + track.width / 2, 0.1,
                     "The compact disclosure stays centered on the public strip")
        compare(track.z, 45, "The phase keeps the public overlay stacking order")
        verify(rect.x >= -0.1 && rect.right <= table.width + 0.1)
    }
    function assertPhaseLabelFits(step) {
        const track = item("forgePhaseTrack")
        const label = item(track.compactMode ? "forgeCurrentPhaseLabel" : "forgePhaseLabel-" + step)
        verify(label.visible && !label.truncated)
        compare(label.font.pixelSize, Theme.fontSize(11))
        verify(label.paintedWidth <= label.width + 0.5 && label.paintedHeight <= label.height + 0.5,
               "The complete current phase label fits: " + step)
    }
    function assertPublicPhaseCells(step) {
        const track = item("forgePhaseTrack")
        if (track.compactMode) return
        const steps = ["untap", "upkeep", "draw", "main1", "begin_combat", "declare_attackers",
            "declare_blockers", "combat_damage", "end_combat", "main2", "end", "cleanup"]
        const first = item("forgePhase-untap"), current = steps.indexOf(step)
        let previous = null
        for (let index = 0; index < steps.length; ++index) {
            const cell = item("forgePhase-" + steps[index])
            fuzzyCompare(cell.width, first.width, 0.1, "All twelve public phase cells have equal widths")
            if (previous)
                fuzzyCompare(bounds(cell).x - bounds(previous).right, 2 * table.presentation.unit, 0.1,
                             "Phase cells retain their separate transparent gaps")
            if (index !== current)
                fuzzyCompare(cell.color.a, index < current ? 0.28 : 0.55, 1 / 255 + 0.0001,
                             "Past and future cells retain the public translucent colors")
            previous = cell
        }
    }
    function assertPhaseGapsRevealBattlefield() {
        const track = item("forgePhaseTrack")
        if (track.compactMode) return
        mouseMove(table, 1, 1)
        tryCompare(item("forgeTurnCallout"), "visible", false, 5000)
        verify(waitForPolish(window)); waitForRendering(table)
        const shown = grabImage(table), points = []
        const steps = ["untap", "upkeep", "draw", "main1", "begin_combat", "declare_attackers",
            "declare_blockers", "combat_damage", "end_combat", "main2", "end", "cleanup"]
        for (let index = 1; index < steps.length; ++index) {
            const left = item("forgePhase-" + steps[index - 1]), right = item("forgePhase-" + steps[index])
            const a = left.mapToItem(table, left.width, left.height / 2)
            const b = right.mapToItem(table, 0, right.height / 2)
            points.push(Qt.point((a.x + b.x) / 2, (a.y + b.y) / 2))
        }
        const savedOpacity = track.opacity
        try {
            track.opacity = 0
            verify(waitForRendering(table))
            const hidden = grabImage(table), scale = shown.width / table.width
            for (const point of points) {
                // Use the nearest raster sample to the mapped gap center, not its left edge.
                const x = Math.round(point.x * scale), y = Math.round(point.y * scale)
                compare(shown.red(x, y), hidden.red(x, y), "Phase gaps have no continuous backing plate")
                compare(shown.green(x, y), hidden.green(x, y))
                compare(shown.blue(x, y), hidden.blue(x, y))
            }
        } finally {
            track.opacity = savedOpacity
            waitForRendering(table)
        }
    }
    function assertFullLogReachable(text, cards) {
        mouseClick(item("forgeGameMenu"))
        const drawer = item("forgeGameDrawer")
        tryCompare(drawer, "opened", true)
        mouseClick(item("rulesToggleGameLogButton"))
        keyClick(Qt.Key_Escape)
        tryCompare(drawer, "visible", false)
        const log = item("gameLogRail"), list = item("gameLog")
        tryCompare(log, "visible", true)
        tryCompare(list, "count", 1)
        tryVerify(() => list.itemAtIndex(0) !== null)
        compare(list.itemAtIndex(0).logText, text)
        compare(list.itemAtIndex(0).text, text, "The full log preserves the action hidden by the optional summary")
        assertCardsUnchanged(cards, "Reading the full public log")
        mouseClick(item("closeGameLogButton"))
        tryCompare(log, "visible", false)
        settle()
        assertCardsUnchanged(cards, "Closing the full public log")
    }
    function duelVariants() {
        return [{tag:"maximized-en", width:1920, height:1011, scale:1.25, language:"en"},
            {tag:"maximized-zh", width:1920, height:1011, scale:1.25, language:"zh"},
            {tag:"compact-scaled", width:900, height:620, scale:1.5, language:"de"}]
    }
    function configure(data) {
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        testTranslations.setLanguage(data.language)
    }
    function test_duelPhaseVisibilityPreservesPublicBattlefield_data() { return duelVariants() }
    function test_duelPhaseVisibilityPreservesPublicBattlefield(data) {
        configure(data)
        const state = snapshot(1, 3, true)
        state.turn = 0; state.activeSeat = -1; state.prioritySeat = -1
        apply(state)
        const track = item("forgePhaseTrack")
        verify(!track.visible)
        assertPublicDuelGeometry()
        const before = captureCards(["own-0", "own-1", "own-2", "land", "opponent"])
        state.turn = 3; state.activeSeat = 0; state.prioritySeat = 0
        apply(state)
        verify(track.visible)
        assertPublicDuelGeometry()
        assertCardsUnchanged(before, "Showing the phase overlay")
        state.turn = 0; state.activeSeat = -1; state.prioritySeat = -1
        apply(state)
        verify(!track.visible)
        assertPublicDuelGeometry()
        assertCardsUnchanged(before, "Hiding the phase overlay")
    }
    function test_duelPhaseAndStatusChangesKeepActualCards_data() { return duelVariants() }
    function test_duelPhaseAndStatusChangesKeepActualCards(data) {
        configure(data)
        const state = snapshot(1, 3, true)
        apply(state)
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        assertPublicDuelGeometry()
        const before = captureCards(["own-0", "own-1", "own-2", "land", "opponent"])
        const track = item("forgePhaseTrack")
        assertPhaseGapsRevealBattlefield()
        const steps = ["untap", "upkeep", "draw", "main1", "begin_combat", "declare_attackers",
            "declare_blockers", "combat_damage", "end_combat", "main2", "end", "cleanup"]
        for (const step of steps) {
            state.step = step; apply(state)
            assertPublicDuelGeometry()
            assertCardsUnchanged(before, "Phase " + step)
            assertPhaseLabelFits(step)
            assertPublicPhaseAnchor()
            assertPublicPhaseCells(step)
            assertStatusOverlaysClear(state)
        }
        const shortAction = "Alice plays Plains"
        for (const text of [shortAction, "A very long public action describing a creature entering the battlefield and its public triggered ability while priority remains unchanged"]) {
            testGameTable.applySnapshot({log:[{id:++serial, kind:"cast", text:text, seat:0}]})
            settle()
            if (text === shortAction)
                verify(item("forgeRecentActions").visible, "A short public action uses the available local gap")
            compare(item("forgeRecentActionText").text, text)
            assertStatusOverlaysClear(state)
            assertPublicDuelGeometry()
            assertCardsUnchanged(before, "Public action text")
            if (text !== shortAction)
                assertFullLogReachable(text, before)
        }
        transport.lastError = "A recoverable connection error whose longer message must remain an overlay"
        settle(); verify(item("rulesErrorBanner").visible)
        assertCardsUnchanged(before, "Recoverable error")
        transport.lastError = ""; testGameTable.applySnapshot({log:[]}); settle()
        assertCardsUnchanged(before, "Clearing public messages")
        state.prioritySeat = 1; apply(state)
        prompt("", {pending:false, supported:false})
        const deciding = item("forgeOpponentDeciding")
        tryCompare(deciding, "visible", true)
        fuzzyCompare(deciding.y + deciding.height / 2, table.presentation.battlefieldMiddle, 0.1,
                     "The public opponent-deciding overlay remains centered")
        assertPublicPhaseAnchor()
        assertStatusOverlaysClear(state)
        assertPublicDuelGeometry()
        assertCardsUnchanged(before, "Opponent deciding")
        state.prioritySeat = 0; apply(state)
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        tryCompare(deciding, "visible", false)
        assertPublicPhaseAnchor()
        assertStatusOverlaysClear(state)
        assertCardsUnchanged(before, "Returning priority")
    }
    function test_attackHintClearsPhaseStrip_data() {
        return duelVariants().concat([
            {tag:"match-scale", width:1920, height:1011, scale:1, language:"en"}])
    }
    function test_attackHintClearsPhaseStrip(data) {
        configure(data)
        const state = snapshot(1, 1, true)
        state.step = "declare_attackers"
        const attacker = state.zones.find(zone => zone.ownerSeat === 1 && zone.zone === "battlefield").cards[0]
        attacker.attacking = true
        attacker.attackingPlayer = 0
        apply(state)
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        const hint = item("forgeCardInteractionHint-opponent")
        verify(hint.text.length > 0)
        if (data.language === "en")
            compare(hint.text, "Attacking you")
        const badge = hint.parent
        const faceRect = bounds(item("forgeCard-opponent"))
        const badgeRect = bounds(badge)
        verify(badgeRect.bottom <= faceRect.y + 1,
               "Opponent combat label sits above the face: " + JSON.stringify(badgeRect)
               + " face " + JSON.stringify(faceRect))
        verify(!overlaps(badgeRect, phaseBounds()),
               "Attacking you stays off the phase strip: " + JSON.stringify(badgeRect)
               + " phase " + JSON.stringify(phaseBounds()))
    }
    function edhSnapshot() {
        const state = snapshot()
        state.players = []; state.zones = []
        for (let seat = 0; seat < 4; ++seat) {
            state.players.push({seat:seat, name:"Player " + seat, life:40, status:"playing", manaPool:[]})
            const cards = [card("bear-" + seat, seat, "Grizzly Bears", true),
                card("land-" + seat, seat, "Plains", false)]
            state.zones.push({zone:"battlefield", ownerSeat:seat, count:cards.length, cards:cards},
                {zone:"hand", ownerSeat:seat, count:1, cards:seat === 0 ? [card("my-hand", seat, "Plains", false)] : []},
                {zone:"library", ownerSeat:seat, count:83, cards:[]})
        }
        return state
    }
    function test_edhSeamBudgetsOnlyPhaseAndReclaimsOpening_data() {
        return [{tag:"wide", width:1920, height:1011, scale:1.25, language:"en"},
            {tag:"compact-scaled", width:1100, height:760, scale:1.5, language:"de"}]
    }
    function test_edhSeamBudgetsOnlyPhaseAndReclaimsOpening(data) {
        configure(data); room.format = "edh"; room.maxSeats = 4
        const state = edhSnapshot(); apply(state)
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        const board = table.presentation, multi = item("forgeMultiplayerBattlefield")
        const track = item("forgePhaseTrack")
        fuzzyCompare(multi.seam, Math.max(22 * board.unit, track.height + 4 * board.unit), 0.1,
                     "EDH reserves only the visible phase strip, never a second status row")
        const before = captureCards(["bear-0", "bear-1", "bear-2", "bear-3"])
        const text = "A long public multiplayer action must not allocate another status band"
        testGameTable.applySnapshot({log:[{id:++serial, kind:"cast", text:text, seat:0}]})
        settle(); compare(item("forgeRecentActionText").text, text)
        assertStatusOverlaysClear(state)
        assertCardsUnchanged(before, "EDH public action")
        assertFullLogReachable(text, before)
        transport.lastError = "Recoverable error"; settle()
        assertCardsUnchanged(before, "EDH error")
        state.turn = 0; state.activeSeat = -1; state.prioritySeat = -1; apply(state)
        verify(!track.visible)
        fuzzyCompare(multi.seam, 6 * board.unit, 0.1,
                     "The public EDH opening reclaims phase space and retains only its narrow gutter")
        fuzzyCompare(multi.fieldHeight, (multi.height - 6 * board.unit) / 2, 0.1)
    }
    function test_compactPhaseOverviewRemainsReadOnlyWithoutGeometryChange() {
        configure({width:900, height:620, scale:1.5, language:"de"})
        const state = snapshot(1, 1, false); state.step = "cleanup"; apply(state)
        prompt("chooseAction", {options:[{responseId:"$pass", kind:"pass", label:"Pass"}]})
        const before = captureCards(["own-0", "land", "opponent"])
        const track = item("forgePhaseTrack"), disclosure = item("forgeCurrentPhase")
        verify(track.compactMode)
        const responseCount = transport.responses.length
        disclosure.forceActiveFocus(); tryCompare(disclosure, "activeFocus", true)
        keyClick(Qt.Key_Return)
        const overview = item("forgePhaseOverview")
        tryCompare(overview, "opened", true)
        const list = findChild(overview.contentItem, "forgePhaseOverviewList")
        verify(list !== null); compare(list.count, 12); compare(list.currentIndex, 11)
        const label = findChild(overview.contentItem, "forgePhaseOverviewLabel-cleanup")
        verify(label !== null)
        verify(label.paintedHeight <= label.height + 0.5 && label.paintedWidth <= label.width + 0.5)
        assertCardsUnchanged(before, "Opening the full phase overview")
        keyClick(Qt.Key_Escape); tryCompare(overview, "opened", false)
        compare(transport.responses.length, responseCount, "Reading phases must never answer a native prompt")
        assertCardsUnchanged(before, "Closing the full phase overview")
    }
}
