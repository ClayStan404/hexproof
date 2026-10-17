// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"
import "../../qml/screens"

TestCase {
    id: testCase
    name: "ForgeFieldRegressions"
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
    function init() {
        window.width = 1920; window.height = 1011
        window.requestActivate(); tryCompare(window, "active", true)
        Theme.uiScale = 1.25; Theme.motionEnabled = false
        room.role = "player"; room.seatIndex = 0; room.spectatorsSeeHands = false
        room.format = "modern"; room.deckFormat = "modern"; room.maxSeats = 2
        transport.inRoom = true; transport.responses = []; transport.rulesResponsePending = false
        table.inspector.clear(); table.showGameLogRail = false
        testRulesPrompt.clear()
        table.priority.setFullControl(true)
    }
    function cleanup() {
        laneCardsSpy.target = null
        table.inspector.clear(); testRulesPrompt.clear()
        Theme.uiScale = 1; Theme.motionEnabled = false
    }
    SignalSpy { id: laneCardsSpy; signalName: "visibleCardsChanged" }
    function test_batchedLaneChangesPublishTogetherBeforeRendering() {
        const state = snapshot(1, 1, true)
        verify(testRulesPrompt.applySnapshot(state)); verify(waitForPolish(window))
        const lane = item("forgeOwnCreatures"), survivor = lane.itemFor("own-0")
        verify(survivor !== null)
        laneCardsSpy.target = lane
        verify(laneCardsSpy.valid)
        laneCardsSpy.clear()

        const field = state.zones[4]
        for (let i = 1; i < 48; ++i)
            field.cards.push(card("own-" + i, 0, "Bear " + i, true))
        field.count = field.cards.length
        verify(testRulesPrompt.applySnapshot(state))
        compare(lane.visibleCards.length, 48, "Membership is complete when the snapshot returns")
        compare(laneCardsSpy.count, 1, "One snapshot publishes the complete added batch once")
        verify(lane.itemFor("own-47") !== null, "New card lookups are immediate")
        // The fallback polish must not republish an already completed batch.
        grabImage(table)
        compare(lane.visibleCards.length, 48)
        compare(laneCardsSpy.count, 1, "One snapshot publishes the complete added batch once")
        compare(lane.itemFor("own-0"), survivor, "Unchanged card delegates survive a batch")
        verify(lane.itemFor("own-47") !== null)

        laneCardsSpy.clear()
        field.cards = field.cards.filter(row => row.id === "land" || row.id === "own-0")
        for (let i = 0; i < 8; ++i)
            field.cards.push(card("replacement-" + i, 0, "Replacement " + i, true))
        field.count = field.cards.length
        verify(testRulesPrompt.applySnapshot(state))
        compare(lane.visibleCards.length, 9)
        compare(laneCardsSpy.count, 1, "Mixed changes finish before the snapshot returns")
        compare(lane.itemFor("own-47"), null, "Removed cards cannot remain queryable before polish")
        verify(lane.itemFor("replacement-7") !== null)
        grabImage(table)
        compare(laneCardsSpy.count, 1, "Mixed removals and insertions publish one final batch")
        compare(lane.visibleCards.length, 9)
        compare(lane.itemFor("own-0"), survivor)
        compare(lane.itemFor("own-47"), null)
        verify(lane.visibleCards.every(slot => slot && slot.width > 0 && slot.height > 0))
        verify(lane.inspectionRects(table).length > 0)

        laneCardsSpy.clear()
        verify(testRulesPrompt.applySnapshot(state))
        grabImage(table)
        compare(laneCardsSpy.count, 0, "An unchanged snapshot does not republish membership")

        laneCardsSpy.clear()
        field.cards = []; field.count = 0
        verify(testRulesPrompt.applySnapshot(state))
        compare(lane.visibleCards.length, 0, "Revoked contents disappear synchronously")
        compare(laneCardsSpy.count, 1)
        grabImage(table)
        compare(laneCardsSpy.count, 1, "Clearing the lane publishes one empty batch")
        compare(lane.visibleCards.length, 0)
        compare(lane.itemFor("own-0"), null)
        compare(lane.inspectionRects(table).length, 0)
        compare(lane.readoutRects(table).length, 0)
    }
    function test_attachmentOnlyBatchesPublishWithoutStackChanges() {
        const state = snapshot(1, 1, true)
        verify(testRulesPrompt.applySnapshot(state))
        const lane = item("forgeOwnCreatures"), host = lane.itemFor("own-0")
        const stacks = JSON.stringify(lane.visibleStackIds)
        laneCardsSpy.target = lane
        verify(laneCardsSpy.valid)
        laneCardsSpy.clear()

        const field = state.zones[4]
        for (let i = 0; i < 2; ++i) {
            const aura = card("aura-" + i, 0, "Aura " + i, true)
            aura.attachedTo = "own-0"
            field.cards.push(aura)
        }
        field.count = field.cards.length
        verify(testRulesPrompt.applySnapshot(state))
        compare(JSON.stringify(lane.visibleStackIds), stacks, "Attached rows do not change public piles")
        compare(lane.visibleCards.length, 3, "Attachment rows publish before the snapshot returns")
        compare(laneCardsSpy.count, 1)
        compare(lane.itemFor("own-0"), host)
        compare(host.hostedAttachments.length, 2)
        compare(lane.attachmentDepth, 2)
        grabImage(table)
        compare(laneCardsSpy.count, 1, "Polish does not repeat the attachment publication")

        laneCardsSpy.clear()
        field.cards = field.cards.filter(row => !row.attachedTo)
        field.count = field.cards.length
        verify(testRulesPrompt.applySnapshot(state))
        compare(JSON.stringify(lane.visibleStackIds), stacks)
        compare(lane.visibleCards.length, 1, "Detached rows disappear synchronously")
        compare(laneCardsSpy.count, 1)
        compare(lane.itemFor("aura-0"), null)
        compare(lane.itemFor("aura-1"), null)
        compare(host.hostedAttachments.length, 0)
        compare(lane.attachmentDepth, 0)
        grabImage(table)
        compare(laneCardsSpy.count, 1)
    }
    function test_catalogMovesAttachmentRowsBeforeTheirNextFrame() {
        const state = snapshot(1, 1, true)
        const aura = card("typed-aura", 0, "Shifting Attachment", false)
        aura.attachedTo = "own-0"
        state.zones[4].cards.push(aura)
        state.zones[4].count = state.zones[4].cards.length
        verify(testRulesPrompt.applySnapshot(state))
        const others = item("forgeOwnOther"), lands = item("forgeOwnLands")
        const otherStacks = JSON.stringify(others.visibleStackIds)
        const landStacks = JSON.stringify(lands.visibleStackIds)
        compare(others.visibleCards.length, 1)
        compare(lands.visibleCards.length, 1)
        laneCardsSpy.target = others
        laneCardsSpy.clear()
        try {
            // Catalog discoveries are outside snapshot batches. An attached
            // row can change category without changing either public pile.
            catalog.typeOverrides = {"Shifting Attachment":"Land"}
            catalog.cardAvailable("Shifting Attachment", "Shifting Attachment", "Land", "", "", "")
            compare(JSON.stringify(others.visibleStackIds), otherStacks)
            compare(JSON.stringify(lands.visibleStackIds), landStacks)
            grabImage(table)
            compare(others.visibleCards.length, 0)
            compare(lands.visibleCards.length, 2)
            compare(others.itemFor("typed-aura"), null)
            verify(lands.itemFor("typed-aura") !== null)
            compare(laneCardsSpy.count, 1, "Catalog-only membership settles by its first frame")
        } finally {
            catalog.typeOverrides = {}
            catalog.cardAvailable("Shifting Attachment", "Shifting Attachment", "Creature", "", "", "")
        }
    }
    Component {
        id: laneProbe
        ForgeCardLane {
            tableController: table
            ownerSeat: 0
            width: 500; height: 300
            showCaption: false
        }
    }
    function test_rightAlignedPilesReserveRearFaces_data() {
        return [{tag:"walker", category:"planeswalker", groups:1, scale:1},
            {tag:"walker-scaled", category:"planeswalker", groups:1, scale:1.5},
            {tag:"artifacts", category:"other", groups:2, scale:1},
            {tag:"artifacts-scaled", category:"other", groups:2, scale:1.5}]
    }
    function test_rightAlignedPilesReserveRearFaces(data) {
        const state = snapshot(1, 1), rows = [], types = {}
        for (let group = 0; group < data.groups; ++group) {
            const name = data.tag + " Right Pile " + group
            types[name] = data.category === "planeswalker" ? "Planeswalker" : "Artifact"
            for (let copy = 0; copy < 3; ++copy)
                rows.push(card("right-pile-" + group + "-" + copy, 0, name, false))
        }
        const oldTypes = catalog.typeOverrides
        catalog.typeOverrides = types
        try {
            state.zones[4].cards = rows; state.zones[4].count = rows.length
            verify(testRulesPrompt.applySnapshot(state))
            const lane = createTemporaryObject(laneProbe, window.contentItem, {
                category:data.category, alignRight:true, unit:data.scale,
                width:(103 + (data.groups - 1) * 88) * data.scale,
                height:150 * data.scale, maxFaceWidth:108 * data.scale})
            verify(lane !== null); verify(waitForPolish(window))
            compare(lane.stackCount, data.groups)
            fuzzyCompare(lane.layoutMinimumWidth(), 103 * data.scale, 0.01)
            verify(!Number.isFinite(lane.layoutMinimumHeight(96 * data.scale)),
                "A 96-unit region cannot promise an 80-unit face plus all pile offsets")
            verify(Number.isFinite(lane.layoutMinimumHeight(lane.layoutMinimumWidth())))
            fuzzyCompare(lane.cardWidth, 80 * data.scale, 0.01)
            compare(lane.columns, data.groups)
            const faceWidth = lane.cardWidth
            function checkBounds() {
                for (const slot of lane.hostCards) {
                    const rect = slot.mapToItem(lane.scrollArea, 0, 0, slot.width, slot.height)
                    verify(rect.x >= -0.01 && rect.x + rect.width <= lane.scrollArea.width + 0.01,
                        "The ready front and every rear face stay inside the right-aligned region")
                }
            }
            checkBounds()
            lane.openFan(0); verify(waitForPolish(window))
            fuzzyCompare(lane.cardWidth, faceWidth, 0.01); checkBounds()
            lane.closeFan(); verify(waitForPolish(window)); checkBounds()
            rows[0].tapped = true
            verify(testRulesPrompt.applySnapshot(state)); verify(waitForPolish(window)); checkBounds()
            lane.width = 96 * data.scale
            verify(waitForPolish(window)); checkBounds()
        } finally {
            catalog.typeOverrides = oldTypes
        }
    }
    function test_directionalHintsReserveRowsAndReveal_data() {
        return [{tag:"near", direction:-1, scale:1}, {tag:"far", direction:1, scale:1},
            {tag:"near-scaled", direction:-1, scale:1.5}, {tag:"far-scaled", direction:1, scale:1.5}]
    }
    function test_directionalHintsReserveRowsAndReveal(data) {
        const state = snapshot(1, 12, true)
        verify(testRulesPrompt.applySnapshot(state))
        const lane = createTemporaryObject(laneProbe, window.contentItem, {
            unit:data.scale, width:400 * data.scale, height:110 * data.scale,
            combatForward:data.direction, alignBottom:data.direction > 0})
        verify(lane !== null)
        verify(lane.scrollArea.contentHeight > lane.scrollArea.height)
        const grid = Qt.rect(lane.cardWidth, lane.cardHeight, lane.cellHeight, lane.gridHeight)
        const resting = lane.hostCards.map(slot => ({id:slot.cardId, x:slot.x, y:slot.y}))
        state.step = "declare_blockers"
        state.zones[4].cards.forEach(row => {
            if (row.power) { row.attacking = true; row.attackingPlayer = 1 }
        })
        verify(testRulesPrompt.applySnapshot(state)); verify(waitForPolish(window))
        compare(Qt.rect(lane.cardWidth, lane.cardHeight, lane.cellHeight, lane.gridHeight), grid,
            "Combat changes do not refit the structurally reserved rows")
        for (const before of resting) {
            const slot = lane.itemFor(before.id)
            fuzzyCompare(slot.x, before.x, 0.01)
            fuzzyCompare(slot.y, before.y + data.direction * 14 * data.scale, 0.01)
            const badge = findChild(slot.faceItem, "forgeCardInteractionHint-" + slot.cardId).parent
            verify(badge.visible)
            const badgeRect = badge.mapToItem(lane.scrollArea.contentItem, 0, 0, badge.width, badge.height)
            for (const other of lane.hostCards) {
                if (other === slot) continue
                verify(!overlaps(badgeRect, Qt.rect(other.x, other.y, other.width, other.height)),
                    "A destination label must not cover a preceding or following row's card")
            }
        }
        const first = lane.itemFor("own-0")
        const firstBadge = findChild(first.faceItem, "forgeCardInteractionHint-own-0").parent
        const firstAt = firstBadge.mapToItem(lane.scrollArea, 0, 0)
        verify(firstAt.y >= -0.01 && firstAt.y + firstBadge.height <= lane.scrollArea.height + 0.01,
            "The first row's entire destination label is inside the clipped viewport")
        for (const id of ["own-5", "own-11", "own-0"]) {
            verify(lane.reveal(id))
            const slot = lane.itemFor(id), badge = findChild(slot.faceItem, "forgeCardInteractionHint-" + id).parent
            const faceAt = slot.mapToItem(lane.scrollArea, 0, 0)
            const badgeAt = badge.mapToItem(lane.scrollArea, 0, 0)
            verify(faceAt.y >= -0.01 && faceAt.y + slot.height <= lane.scrollArea.height + 0.01,
                "Exact-object reveal retains the whole readable card")
            verify(badgeAt.y >= -0.01 && badgeAt.y + badge.height <= lane.scrollArea.height + 0.01,
                "Exact-object reveal also retains its complete destination label")
            verify(lane.inspectionRects(lane.scrollArea).some(rect =>
                rect.x <= badgeAt.x + 0.01 && rect.y <= badgeAt.y + 0.01
                && rect.x + rect.width >= badgeAt.x + badge.width - 0.01
                && rect.y + rect.height >= badgeAt.y + badge.height - 0.01),
                "Hover and status overlays reserve the visible destination label")
        }
        state.step = "main2"
        state.zones[4].cards.forEach(row => { row.attacking = false; delete row.attackingPlayer })
        verify(testRulesPrompt.applySnapshot(state)); verify(waitForPolish(window))
        compare(Qt.rect(lane.cardWidth, lane.cardHeight, lane.cellHeight, lane.gridHeight), grid)
        for (const before of resting) {
            const slot = lane.itemFor(before.id)
            fuzzyCompare(slot.x, before.x, 0.01)
            fuzzyCompare(slot.y, before.y, 0.01)
        }
    }
    function test_directionalHintsKeepPileAndAttachmentSpace_data() {
        return test_directionalHintsReserveRowsAndReveal_data()
    }
    function test_directionalHintsKeepPileAndAttachmentSpace(data) {
        const state = snapshot(1, 5)
        const host = card("equipped", 0, "Equipped creature", true)
        const attachments = [0, 1].map(index => Object.assign(card("aura-" + index, 0,
            "Aura " + index, true), {attachedTo:"equipped"}))
        state.zones[4].cards.push(host, ...attachments)
        state.zones[4].count = state.zones[4].cards.length
        state.step = "declare_blockers"
        state.zones[4].cards.forEach(row => {
            if (row.power && !row.attachedTo) { row.attacking = true; row.attackingPlayer = 1 }
        })
        state.zones[4].cards[3].tapped = true
        state.zones[4].cards[4].tapped = true
        verify(testRulesPrompt.applySnapshot(state))
        const lane = createTemporaryObject(laneProbe, window.contentItem, {
            unit:data.scale, width:160 * data.scale, height:600 * data.scale,
            combatForward:data.direction, alignBottom:data.direction > 0})
        verify(lane !== null); verify(waitForPolish(window))
        compare(lane.attachmentDepth, 2)
        const front = lane.hostCards.find(slot => slot.stackSize === 3 && slot.stackFront)
        verify(front !== undefined && !front.tapped, "The lane contains both ready and spent piles")
        verify(lane.hostCards.some(slot => slot.stackSize === 2 && slot.stackFront && slot.tapped))
        const grid = Qt.rect(lane.cardWidth, lane.cardHeight, lane.cellHeight, lane.gridHeight)
        function checkHints() {
            for (const slot of lane.hostCards) {
                if (!slot.stackFront && !slot.fanned) continue
                const badge = findChild(slot.faceItem, "forgeCardInteractionHint-" + slot.cardId).parent
                verify(badge.visible)
                const rect = badge.mapToItem(lane.scrollArea, 0, 0, badge.width, badge.height)
                verify(rect.y >= -0.01 && rect.y + rect.height <= lane.scrollArea.height + 0.01,
                    "Ready fronts, expanded members and equipped hosts keep complete labels")
                const equipped = lane.itemFor("equipped")
                for (const index of [0, 1]) {
                    const strip = findChild(equipped, "forgeAttachmentStrip-aura-" + index)
                    verify(strip !== null)
                    verify(!overlaps(rect, strip.mapToItem(lane.scrollArea, 0, 0, strip.width, strip.height)),
                        "Destination labels stay clear of every attachment name strip")
                }
            }
        }
        checkHints()
        lane.openFan(front.stackIndex); verify(waitForPolish(window))
        compare(lane.hostCards.filter(slot => slot.fanned).length, 3)
        compare(Qt.rect(lane.cardWidth, lane.cardHeight, lane.cellHeight, lane.gridHeight), grid,
            "Opening a pile does not refit its reserved row")
        checkHints()
        lane.closeFan(); verify(waitForPolish(window)); checkHints()
        state.zones[4].cards[0].tapped = true
        state.zones[4].cards[3].tapped = false
        verify(testRulesPrompt.applySnapshot(state)); verify(waitForPolish(window))
        compare(Qt.rect(lane.cardWidth, lane.cardHeight, lane.cellHeight, lane.gridHeight), grid,
            "Ready/spent transitions do not refit the label space")
        checkHints()
    }
    function test_laneModelChangesDropPreviousLookupsBeforePolish() {
        verify(testRulesPrompt.applySnapshot(snapshot(1, 8, true)))
        const lane = createTemporaryObject(laneProbe, window.contentItem)
        verify(lane !== null)
        compare(lane.visibleCards.length, 8, "An existing model is collected before construction returns")
        verify(lane.itemFor("own-7") !== null, "A newly opened lane can locate cards before its first frame")
        lane.ownerSeat = 1
        compare(lane.visibleCards.length, 1, "Changing models publishes the complete replacement immediately")
        compare(lane.itemFor("own-7"), null)
        verify(lane.itemFor("opponent") !== null)
        lane.ownerSeat = -1
        compare(lane.visibleCards.length, 0)
        compare(lane.itemFor("opponent"), null)
        grabImage(table)
        compare(lane.visibleCards.length, 0)
        compare(lane.hostCards.length, 0)
    }
    function bounds(target) { return target.mapToItem(table.presentation, 0, 0, target.width, target.height) }
    function overlaps(a, b) {
        return a.x < b.x + b.width - 0.5 && a.x + a.width > b.x + 0.5
            && a.y < b.y + b.height - 0.5 && a.y + a.height > b.y + 0.5
    }
    function edhState() {
        const state = snapshot()
        state.players = []; state.zones = []
        for (let seat = 0; seat < 4; ++seat) {
            state.players.push({seat:seat, name:"Player "+seat, life:40, status:"playing", manaPool:[]})
            const cards = [card("bear-"+seat,seat,"Grizzly Bears",true),
                card("land-a-"+seat,seat,"Plains",false),card("land-b-"+seat,seat,"Plains",false)]
            state.zones.push({zone:"battlefield",ownerSeat:seat,count:cards.length,cards:cards})
        }
        return state
    }
    function assertFieldControls(seat) {
        const controls = [item("rulesPlayerTarget"+seat), item("forgeSeatZones-"+seat),
            item("forgeManaPool-"+seat)]
        const dock = item("rulesDecisionDock")
        for (let i=0;i<controls.length;++i) {
            const rect=bounds(controls[i])
            verify(rect.x>=0 && rect.y>=0 && rect.x+rect.width<=table.width+0.5
                && rect.y+rect.height<=table.height+0.5, "Complete public control remains on table")
            verify(!overlaps(rect,bounds(dock)), "Public control stays clear of the dock")
            for (let j=i+1;j<controls.length;++j)
                verify(!overlaps(rect,bounds(controls[j])), "Mana, player target and zones do not overlap")
        }
        for (const color of ["W","U","B","R","G","C"]) {
            const entry=item("forgeMana-"+seat+"-"+color)
            const rect=bounds(entry), pool=bounds(controls[2])
            verify(rect.x>=pool.x-0.5 && rect.y>=pool.y-0.5
                && rect.x+rect.width<=pool.x+pool.width+0.5
                && rect.y+rect.height<=pool.y+pool.height+0.5, "Every mana entry is visible")
        }
    }
    function test_manaPoolDoesNotReallocateBattlefield_data() {
        return [{tag:"maximized",width:1920,height:1011,scale:1.25},
            {tag:"compact",width:1280,height:720,scale:1},
            {tag:"scaled",width:1024,height:768,scale:1.3}]
    }
    function test_manaPoolDoesNotReallocateBattlefield(data) {
        window.width=data.width; window.height=data.height; Theme.uiScale=data.scale
        room.format="edh"; room.deckFormat="commander"; room.maxSeats=4
        const state=edhState()
        verify(testRulesPrompt.applySnapshot(state)); verify(waitForPolish(window))
        const field=item("forgeField-1"), face=item("forgeCard-bear-1")
        if (data.tag === "maximized") verify(!field.stackedHeader, "The wide table retains the public single-row header")
        const before=bounds(face), height=field.boardHeight
        state.players[1].manaPool=["W","U","B","R","G","C"].map(name=>({name:name,value:1}))
        verify(testRulesPrompt.applySnapshot(state)); verify(waitForPolish(window))
        compare(field.boardHeight,height,"Floating mana must not change battlefield height")
        const after=bounds(face)
        for (const key of ["x","y","width","height"])
            fuzzyCompare(after[key],before[key],0.1,"Untouched creature "+key+" stays fixed while floating mana appears")
        assertFieldControls(1)
        state.players[1].manaPool.forEach(entry=>entry.value=99)
        verify(testRulesPrompt.applySnapshot(state)); verify(waitForPolish(window))
        compare(field.boardHeight,height,"Changing mana amounts must not change battlefield height")
        assertFieldControls(1)
        state.players[1].manaPool=[]
        verify(testRulesPrompt.applySnapshot(state)); verify(waitForPolish(window))
        compare(field.boardHeight,height)
        const restored=bounds(face)
        for (const key of ["x","y","width","height"]) fuzzyCompare(restored[key],before[key],0.1)
    }
    function test_compactOtherViewerKeepsOriginalHeader() {
        window.width=1280; window.height=720; Theme.uiScale=1
        room.format="edh"; room.deckFormat="commander"; room.maxSeats=4; room.seatIndex=3
        const state=snapshot()
        state.players=[]; state.zones=[]; state.activeSeat=3; state.prioritySeat=3
        for (let seat=0;seat<4;++seat) {
            const commanderId="cmd-"+seat
            state.players.push({seat:seat,name:"Player "+seat,life:40,status:"playing",manaPool:[],
                commanders:[{name:"Isamaru, Hound of Konda",casts:seat,tax:seat*2,zone:"command",objectId:commanderId}]})
            const permanents=[]
            for (let i=0;i<3;++i) permanents.push(card("compact-bear-"+seat+"-"+i,seat,"Bear "+i,true))
            permanents.push(card("compact-land-"+seat,seat,"Plains",false))
            state.zones.push({zone:"battlefield",ownerSeat:seat,count:permanents.length,cards:permanents},
                {zone:"hand",ownerSeat:seat,count:7,cards:seat===3 ? [card("my-hand",seat,"Plains",false)] : []},
                {zone:"library",ownerSeat:seat,count:83,cards:[]},
                {zone:"command",ownerSeat:seat,count:1,cards:[card(commanderId,seat,"Isamaru, Hound of Konda",true)]})
        }
        verify(testRulesPrompt.applySnapshot(state)); verify(waitForPolish(window))
        const fields=[],before=[]
        for (let seat=0;seat<4;++seat) {
            const field=item("forgeField-"+seat)
            verify(field.headerHeight-field.lifeDeltaClearance<=64*table.presentation.unit,
                "Compact metadata stays single-row below the permanent life-change band")
            verify(!field.stackedHeader)
            fields.push(field)
            before.push({height:field.boardHeight,body:bounds(item("forgeCard-compact-bear-"+seat+"-0"))})
        }
        for (const amount of [1,99]) {
            for (const player of state.players)
                player.manaPool=["W","U","B","R","G","C"].map(name=>({name:name,value:amount}))
            verify(testRulesPrompt.applySnapshot(state)); verify(waitForPolish(window))
            for (let seat=0;seat<4;++seat) {
                const field=fields[seat],mana=item("forgeManaPool-"+seat),name=item("forgePlayerName-"+seat)
                compare(field.boardHeight,before[seat].height)
                verify(field.headerHeight-field.lifeDeltaClearance<=64*table.presentation.unit)
                verify(mana.height<=field.headerHeight-field.lifeDeltaClearance,
                    "All colors fit within the original identity band")
                verify(name.width>=24*field.unit,"A visible identity label remains beside the full mana pool")
                const body=bounds(item("forgeCard-compact-bear-"+seat+"-0"))
                for (const key of ["x","y","width","height"]) fuzzyCompare(body[key],before[seat].body[key],0.1)
                assertFieldControls(seat)
            }
        }
        verify(item("forgeManaPool-0").maximumColumns===3,"The actual dock-constrained inline header wraps only mana")
        state.players.forEach(player=>player.manaPool=[])
        verify(testRulesPrompt.applySnapshot(state)); verify(waitForPolish(window))
        for (let seat=0;seat<4;++seat) {
            compare(fields[seat].boardHeight,before[seat].height)
            verify(!fields[seat].stackedHeader)
        }
    }
    Component { id: redProbe; Rectangle { color:"#ff0000"; z:100; anchors.fill:parent } }
    Component { id: blueProbe; Rectangle { color:"#0000ff"; z:100; anchors.fill:parent } }
    function test_expandingOnePileKeepsOtherScrolledRowsClipped() {
        const state=snapshot(1,120,true)
        state.zones[4].cards[0].identity.name="A pair"
        state.zones[4].cards[1].identity.name="A pair"
        verify(testRulesPrompt.applySnapshot(state)); verify(waitForPolish(window))
        const lane=item("forgeOwnCreatures"), viewport=lane.scrollArea
        verify(viewport.contentHeight>viewport.height)
        viewport.contentY=lane.cellHeight+20*lane.unit
        verify(waitForPolish(window))
        const other=lane.visibleCards.find(slot=>slot.stackIndex===5)
        verify(other !== undefined && other.stackSize===1)
        const marker=createTemporaryObject(redProbe,other.faceItem)
        verify(marker !== null)
        table.inspector.clear(); tryCompare(item("forgeTurnCallout"),"visible",false,3000)
        mouseMove(table,table.width-2,2)
        verify(waitForPolish(window))
        const point=marker.mapToItem(table,marker.width/2,marker.height/2)
        const clip=viewport.mapToItem(table,0,0,viewport.width,viewport.height)
        verify(point.y<clip.y && point.y>0,"Probe is an unrelated row outside the scroll viewport but inside the window")
        const before=grabImage(table), px=Math.round(point.x),py=Math.round(point.y)
        verify(before.red(px,py)<220 || before.green(px,py)>40,"The unrelated row starts clipped")
        const pair=lane.visibleCards.find(slot=>slot.stackSize===2)
        lane.openFan(pair.stackIndex)
        verify(waitForRendering(table))
        const after=grabImage(table)
        verify(after.red(px,py)<220 || after.green(px,py)>40,
            "Opening another pile must not paint an unrelated clipped row outside its lane")
        const selected=lane.visibleCards.filter(slot=>slot.fanned)
        compare(selected.length,2)
        verify(selected.every(slot=>slot.faceItem.visible))
        const fanMarker=createTemporaryObject(blueProbe,selected[0].faceItem)
        verify(fanMarker !== null)
        verify(waitForRendering(table))
        const fanPoint=fanMarker.mapToItem(table,fanMarker.width/2,fanMarker.height/2)
        verify(fanPoint.y<clip.y)
        const fannedPixels=grabImage(table), fx=Math.round(fanPoint.x),fy=Math.round(fanPoint.y)
        verify(fannedPixels.blue(fx,fy)>220 && fannedPixels.red(fx,fy)<40,
            "The chosen fan itself may remain visible outside its scroll viewport")
        const rects=lane.inspectionRects(table)
        verify(rects.some(rect=>fanPoint.x>=rect.x && fanPoint.x<=rect.x+rect.width
            && fanPoint.y>=rect.y && fanPoint.y<=rect.y+rect.height),"Inspection preserves the visible fan")
        lane.closeFan(); viewport.contentY=0
    }
    function test_fanKeepsTheSameCardAndKeyboardFocus() {
        const state=snapshot(1,4,false)
        verify(testRulesPrompt.applySnapshot(state)); verify(waitForPolish(window))
        const lane=item("forgeOwnCreatures"), front=lane.visibleCards.find(slot=>slot.stackFront)
        const face=front.faceItem, id=front.cardId
        mouseMove(table,table.width-2,2)
        face.forceActiveFocus(); tryCompare(face,"activeFocus",true)
        keyClick(Qt.Key_Return); tryCompare(front,"fanned",true)
        compare(item("forgeCard-"+id),face,"Fan expansion keeps the actual card delegate")
        tryCompare(face,"activeFocus",true)
        keyClick(Qt.Key_Right)
        const next=lane.visibleCards.find(slot=>slot.faceItem.activeFocus)
        verify(next !== undefined && next.cardId !== id)
        keyClick(Qt.Key_Escape); tryCompare(lane,"fannedStack",-1)
        compare(item("forgeCard-"+next.cardId),next.faceItem)
        tryCompare(next.faceItem,"activeFocus",true)
    }
}
