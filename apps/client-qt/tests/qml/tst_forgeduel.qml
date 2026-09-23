// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"
import "../../qml/screens"

TestCase {
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
            signal catalogChanged()
            function tableImageSource(name, set, number) { requested.push(name); return "" }
            function imageSource(name, set, number) { requested.push(name); return imageOverride }
            function cardTypeLine(name) {
                if (name === "Plains" || name === "Ugin's Labyrinth") return "Land"
                if (name === "Test Walker") return "Planeswalker"
                if (name === "Test Battle") return "Battle"
                return "Creature"
            }
            function cardDisplayName(name) { return language === "zh" ? names[name] || name : name }
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
        const popup = findChild(table, "forgeZonePopup")
        const found = findChild(table, name) || (popup ? findChild(popup.contentItem, name) : null)
        verify(found !== null, name)
        return found
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
    function combat(kind, capacity) {
        prompt(kind, {combatSources:[{responseId:"opaque-source", objectId:"own-0", label:"Bear", name:"Grizzly Bears",
            validTargetIds:["opaque-target"], mustAssignIfAble:false, maxAssignments:capacity || 1}],
            combatTargets:[{responseId:"opaque-target", kind:kind === "chooseAttackers" ? "player" : "attacker",
                objectId:kind === "chooseAttackers" ? "" : "opponent", seat:kind === "chooseAttackers" ? 1 : -1,
                label:"Opponent", minAssignments:0, maxAssignments:8}]})
    }
    function init() {
        window.width = 1600; window.height = 1000
        window.requestActivate(); tryCompare(window, "active", true)
        Theme.uiScale = 1
        room.role = "player"; room.seatIndex = 0; room.spectatorsSeeHands = false
        room.format = "modern"; room.deckFormat = "modern"
        room.hostingMode = "server"
        room.aiSource = ""
        room.seats = []
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
        const popup = item("forgeZonePopup")
        popup.close()
        tryCompare(popup, "visible", false)
        table.inspector.clear(); testRulesPrompt.clear()
        testTranslations.setLanguage("en")
        catalog.language = "en"
        catalog.names = ({})
        catalog.imageOverride = ""
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
        compare(item("forgeCommanderName-0-0").text, "指挥官")
        catalog.language = "en"
        tryCompare(item("forgeCardName-land"), "text", "Plains")
        compare(item("forgeStackName-bolt").text, "Lightning Bolt")
        compare(item("forgeCommanderName-0-0").text, "Commander")
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
        verify(land.width < creature.width)
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
        verify(Math.abs(stackedLand.x - firstLand.x) <= 12 * unit)
        verify(Math.abs(stackedLand.y - firstLand.y) <= 12 * unit)
        const splitLand = item("forgeCard-land-tapped").mapToItem(lands, 0, 0)
        verify(Math.abs(splitLand.x - firstLand.x) > 20 * unit
               || Math.abs(splitLand.y - firstLand.y) > 20 * unit)
        compare(item("forgeCardStackCountLabel-land-b").text, "×2")
        compare(item("forgeCardStackCountLabel-treasure-b").text, "×2")
        compare(item("forgeCardStackCountLabel-goblin-b").text, "×2")
        const printed = item("forgeCard-bear-real").mapToItem(creatures, 0, 0)
        const copied = item("forgeCard-bear-token").mapToItem(creatures, 0, 0)
        verify(Math.abs(printed.x - copied.x) > 20 * unit
               || Math.abs(printed.y - copied.y) > 20 * unit)
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
    function test_landClickAndPendingResponseProtection() {
        action("playLand", "hand-0")
        const hand = item("forgeHandSurface-hand-0")
        tryCompare(hand, "actionable", true)
        mouseClick(item("forgeHandCard-hand-0"))
        compare(transport.responses.length, 1)
        compare(transport.responses[0].response, "opaque-play")
        mouseClick(item("forgeHandCard-hand-0"))
        compare(transport.responses.length, 1)
    }
    function test_londonMulliganKeepsHandBeforeChoosingBottomCards_data() {
        return [{tag:"one-mulligan", count:1}, {tag:"two-mulligans", count:2}]
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
        compare(table.combatInteraction.selectedSource, "opaque-source")
        compare(Object.keys(table.combatInteraction.assignments).length, 0)
        verify(!item("rulesConfirmCombat-attackers").enabled)
        verify(item("rulesPlayerTarget1").actionable)
        verify(!item("rulesCombatCandidates-attackers").visible)
        mouseClick(item("rulesPlayerTarget1"))
        compare(table.combatInteraction.assignments["opaque-source"], "opaque-target")
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
        tryCompare(source, "showAbilityHint", true)
        tryCompare(findChild(source, "forgeCardInteractionHint-own-0"), "text", "起动异能")
        verify(!table.combatInteraction.active)
        mouseClick(source)
        compare(transport.responses[0].response, "ability")
        compare(table.combatInteraction.selectedSource, "")
        compare(table.combatInteraction.links.length, 0)
        compare(source.card.attacking, data.attacking)
        verify(!source.abilityActionable)
        mouseClick(source)
        compare(transport.responses.length, 1)

        combat("chooseAttackers")
        mouseClick(source)
        tryCompare(findChild(source, "forgeCardInteractionHint-own-0"), "text", "选择攻击目标")
        compare(table.combatInteraction.selectedSource, "opaque-source")
        verify(!source.abilityActionable)
        compare(transport.responses.length, 1)
        mouseClick(item("rulesPlayerTarget1"))
        compare(table.combatInteraction.links.length, 1)

        combat("chooseBlockers")
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
            combat(data.kind)
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
            combat(data.kind)
            transport.inRoom = false
            compare(soundRecorder.cues, beforeReset)
        } finally {
            SoundEffects.backend = previousBackend
        }
    }
    function test_combatAimFollowsPointerAndLocksOnClick(data) {
        combat(data.kind)
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
        combat("chooseAttackers")
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
    function test_combatAimDoesNotSnapToScrolledTarget() {
        const state = snapshot()
        state.zones[5].cards = Array.from({length:70}, (_, i) => card("opponent-" + i, 1, "Attacker " + i, true))
        state.zones[5].count = state.zones[5].cards.length
        verify(testRulesPrompt.applySnapshot(state))
        prompt("chooseBlockers", {
            combatSources:[{responseId:"source", objectId:"own-0", label:"Bear", name:"Grizzly Bears",
                validTargetIds:["target"], maxAssignments:1}],
            combatTargets:[{responseId:"target", kind:"attacker", objectId:"opponent-0", label:"Attacker",
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
        mouseClick(item("rulesConfirmCombat-attackers"))
        compare(transport.responses[0].assignments, [{sourceId:"source", targetId:"player-choice"}])
    }
    function test_combatSelectionCanBeCancelledRemovedAndCleared_data() {
        return [{tag:"attackers", kind:"chooseAttackers", target:"rulesPlayerTarget1"},
                {tag:"blockers", kind:"chooseBlockers", target:"forgeCard-opponent"}]
    }
    function test_combatSelectionCanBeCancelledRemovedAndCleared(data) {
        combat(data.kind)
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
        verify(!item("rulesPlayerTarget0").actionable)
        verify(!item("rulesPlayerTarget1").actionable)
        waitForRendering(table)
        mouseClick(item("rulesCombatDetails-attackers"))
        tryVerify(() => findChild(table, "rulesCombatAssignment-source") !== null)
        compare(table.combatInteraction.selectedSource, "")
        item("rulesCombatAssignment-source").forceActiveFocus(); keyClick(Qt.Key_Down)
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
        tryCompare(item("forgeOwnCreatures"), "stackCount", 4)
        verify(!item("forgeCard-own-3").actionable)
        mouseClick(item("forgeCard-own-0"))
        verify(!item("forgeCard-opponent-2").actionable)
        mouseClick(item("forgeCard-opponent"))
        verify(!item("rulesConfirmCombat-blockers").enabled)
        mouseClick(item("forgeCard-own-1")); mouseClick(item("forgeCard-opponent"))
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
    function test_commanderHistoryAndActionFollowNativeSnapshot() {
        room.format = "duel"
        const state = snapshot()
        state.players[0].commanders = [{name:"Commander", casts:2, tax:4, zone:"battlefield", objectId:"own-0"},
            {name:"Partner", casts:0, tax:0, zone:"hidden"}]
        verify(testRulesPrompt.applySnapshot(state))
        const commander = item("forgeCommander-0-0"), partner = item("forgeCommander-0-1")
        verify(commander.summary.includes("Tax +4"))
        verify(partner.summary.includes("Hidden zone"))
        compare(partner.objectId, "")
        action("activateAbility", "own-0")
        verify(commander.actionable)
        mouseClick(commander)
        compare(transport.responses[0].response, "opaque-play")
        const next = snapshot(); next.gameId = "next-game"
        verify(testRulesPrompt.applySnapshot(next))
        compare(findChild(table, "forgeCommander-0-0"), null)
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
        mouseClick(item("rulesPlayerTarget1"))
        compare(table.combatInteraction.links.length, 1)
        mouseClick(item("forgeCard-own-0"))
        compare(table.combatInteraction.selectedSource, "opaque-source")
        tryCompare(item("forgeCombatAimArrow"), "visible", true)
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
        state.players[0].manaPool[0].value = 1
        verify(testRulesPrompt.applySnapshot(state))
        compare(item("forgeMana-0-U").modelData.amount, 1)
        state.players[0].manaPool = []
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(pool, "visible", false)
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
    function test_combatUnstacksEachEligibleCreature_data() {
        return [{tag:"front-ineligible", cards:2, eligible:1},
                {tag:"two-eligible", cards:2, eligible:2},
                {tag:"three-eligible", cards:3, eligible:3}]
    }
    function test_combatUnstacksEachEligibleCreature(data) {
        verify(testRulesPrompt.applySnapshot(snapshot(3, data.cards)))
        prompt("chooseAttackers", {
            combatSources:Array.from({length:data.eligible}, (_, i) => ({
                responseId:"source-" + i, objectId:"own-" + i, label:"Bear", name:"Grizzly Bears",
                validTargetIds:["defender"], mustAssignIfAble:false, maxAssignments:1})),
            combatTargets:[{responseId:"defender", kind:"player", seat:1, label:"Opponent",
                minAssignments:0, maxAssignments:8}]
        })
        tryCompare(item("forgeOwnCreatures"), "stackCount", data.cards)
        verify(table.combatInteraction.canAct)
        const expected = []
        for (let i = 0; i < data.eligible; ++i) {
            const source = item("forgeCard-own-" + i)
            verify(source.actionable)
            compare(source.card.stackSize, 1)
            mouseClick(source)
            compare(table.combatInteraction.selectedSource, "source-" + i)
            mouseClick(item("rulesPlayerTarget1"))
            expected.push({sourceId:"source-" + i, targetId:"defender"})
            compare(Object.keys(table.combatInteraction.assignments).length, expected.length)
            compare(table.combatInteraction.assignments["source-" + i], "defender")
        }
        mouseClick(item("rulesConfirmCombat-attackers"))
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
        tryCompare(item("forgeOwnCreatures"), "stackCount", 3)
        tryCompare(item("forgeOpponentCreatures"), "stackCount", 3)
        for (let i = 0; i < 3; ++i) {
            mouseClick(item("forgeCard-own-" + i))
            compare(table.combatInteraction.selectedSource, "blocker-" + i)
            mouseClick(item("forgeCard-attacker-" + i))
            compare(table.combatInteraction.assignments["blocker-" + i], "target-" + i)
        }
        mouseClick(item("forgeCard-own-0")); mouseClick(item("forgeCard-attacker-2"))
        compare(table.combatInteraction.assignments["blocker-0"], "target-2")
        compare(table.combatInteraction.links.filter(link => link.to === "attacker-2").length, 2)
        mouseClick(item("rulesConfirmCombat-blockers"))
        compare(transport.responses[0].assignments.length, 3)
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
        tryCompare(item("forgeOwnCreatures"), "stackCount", 8)
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
    function test_nativeCostSelectionsSplitPilesWithoutResubmittingReservations() {
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
        mouseClick(item("forgeCard-own-2"))
        compare(transport.responses[0].targets, ["target-2"])

        costPrompt([2])
        tryCompare(lane, "visibleStackIds", [["own-0", "own-1"], ["own-2"]])
        verify(findChild(item("forgeCard-own-2"), "forgeCardNativeSelection-own-2").visible)
        const selectedCard = item("forgeCard-own-2")
        const marker = findChild(selectedCard, "forgeCardNativeSelection-own-2")
        const name = findChild(selectedCard, "forgeCardName-own-2")
        verify(name.mapToItem(selectedCard, 0, 0).x >= marker.x + marker.width)
        verify(item("forgeCard-own-2").selected)
        compare(table.interaction.nativeSelectedCount, 1)
        compare(table.interaction.selectedCount, 0)
        verify(!item("forgeCard-own-1").selected)
        mouseClick(item("forgeCard-own-1"))
        compare(transport.responses[1].targets, ["target-1"])

        costPrompt([1, 2])
        tryCompare(lane, "visibleStackIds", [["own-0"], ["own-1", "own-2"]])
        compare(table.interaction.nativeSelectedCount, 2)
        compare(table.interaction.selectedCount, 0)
        mouseClick(item("forgeCard-own-2"))
        compare(transport.responses[2].targets, ["target-2"])

        costPrompt([1])
        tryCompare(lane, "visibleStackIds", [["own-0", "own-2"], ["own-1"]])
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

    function test_newPermanentsStaySeparateUntilTheirStateMatches_data() {
        return [{tag:"english", chinese:false}, {tag:"chinese", chinese:true}]
    }
    function test_newPermanentsStaySeparateUntilTheirStateMatches(data) {
        if (data.chinese) testTranslations.setLanguage("zh")
        const state = snapshot(1, 2)
        const fresh = state.zones[4].cards[1]
        fresh.enteredThisTurn = true; fresh.summoningSick = true
        verify(testRulesPrompt.applySnapshot(state))
        const lane = item("forgeOwnCreatures")
        tryCompare(lane, "visibleStackIds", [["own-0"], ["own-1"]])
        const label = findChild(item("forgeCard-own-1"), "forgeCardState-own-1")
        verify(label.visible)
        compare(label.text, data.chinese ? "本回合进场 · 召唤失调" : "Entered this turn · Summoning sickness")
        compare(findChild(item("forgeCard-own-0"), "forgeCardState-own-0").text, "")
        fresh.enteredThisTurn = false
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(lane, "stackCount", 2)
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
                           "forgeOwnCreatures", "forgeOpponentCreatures"]) {
            const lane = item(name)
            verify(lane.width > 0)
            verify(lane.x + lane.width <= dock.x || lane.y + lane.height <= dock.y)
            const stack = item("forgeStack")
            verify(lane.x + lane.width <= stack.x || lane.y >= stack.y + stack.height)
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
        verify(point.y >= 0 && point.y + last.height <= stack.scrollArea.height + 1)
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
        verify(label("maze-b").text.includes(data.chinese ? "隐藏牌" : "hidden card"))
        verify(!label("maze-b").text.includes("SECRET"))
        mouseMove(item("forgeCard-maze-a"), 20, 30)
        tryCompare(table.inspector, "previewCardId", "maze-a")
        tryCompare(item("rulesCardHoverLinkedCards"), "visible", true)
        verify(item("rulesCardHoverLinkedCards").text.includes(ulamog))
        mouseMove(item("forgeCard-needle-a"), 20, 30)
        tryCompare(table.inspector, "previewCardId", "needle-a")
        verify(item("rulesCardHoverLinkedCards").text.includes(bolt))
        mouseClick(item("forgeCard-needle-a"), 20, 30, Qt.RightButton)
        tryCompare(table.inspector, "pinnedCardId", "needle-a")
        verify(item("rulesCardInspectorState").text.includes(bolt))
        needleA.annotations = [{kind:"namedCard", value:"Counterspell"}]
        mazeA.exiledCardCount = 0; mazeA.exiledCardIds = []
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
        compare(item("rulesCardHoverLinkedCards").text, expected)
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
        verify(!item("rulesCardHoverLinkedCards").visible)
        compare(preview.height, preview.width * 88 / 63)
        verify(!item("rulesInspectionHost").visible)
        mouseMove(table, 30, 70)
        tryCompare(table.inspector, "hasCard", false)
        compare(item("rulesInspectionHost").visible, false)
        compare(lane.x, x); compare(lane.width, width)
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
        verify(item("forgeOwnCreatures").height + item("forgeOwnLands").height
               > 360 * table.presentation.unit)
        for (const slot of hand.visibleCards) {
            const center = slot.mapToItem(table, slot.width / 2, slot.height / 2)
            verify(center.y >= hand.y && center.y < table.height)
        }
        item("forgeHandSurface-hand-6").forceActiveFocus()
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
        for (const name of ["forgeOwnCreatures", "forgeOpponentCreatures"]) {
            const lane = item(name)
            tryVerify(() => lane.visibleCards.length === data.count)
            verify(lane.scrollArea.contentHeight <= lane.scrollArea.height + 1)
            for (const slot of lane.visibleCards) {
                verify(slot.x + slot.width <= lane.scrollArea.width + 1)
                verify(slot.y + slot.height <= lane.scrollArea.height + 1)
            }
        }
    }
    function test_turnOwnerIsIndependentOfPriority() {
        const indicator = item("forgeTurnIndicator")
        compare(indicator.text, "Your turn")
        const state = snapshot()
        state.prioritySeat = 1
        verify(testRulesPrompt.applySnapshot(state))
        compare(indicator.text, "Your turn")
        verify(item("rulesPlayerTarget0").activeTurn)
        verify(!item("rulesPlayerTarget1").activeTurn)
        state.activeSeat = 1; state.prioritySeat = 0
        verify(testRulesPrompt.applySnapshot(state))
        compare(indicator.text, table.matchUi.playerName(1) + "'s turn")
        verify(item("rulesPlayerTarget1").activeTurn)
        room.role = "spectator"
        compare(indicator.text, table.matchUi.playerName(1) + "'s turn")
        state.turn = 0
        verify(testRulesPrompt.applySnapshot(state))
        compare(indicator.text, "Preparing game")
        verify(!item("rulesPlayerTarget1").activeTurn)
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
        const top = item("forgeOpponentCreatures"), bottom = item("forgeOwnCreatures")
        verify(top.height + bottom.height + item("forgeOwnLands").height
               + item("forgeOpponentLands").height > table.height * 0.65)
        verify(opponent.y < 12 * table.presentation.unit)
        verify(item("forgeOwnZoneStrip").y >= item("forgeHand").y - 4 * table.presentation.unit)
        verify(dock.x + dock.width <= table.width + 1)
        verify(dock.y + dock.height <= table.height + 1)
        verify(dock.y + dock.height >= table.height - 20 * table.presentation.unit)
        verify(item("forgeOwnCreatures").x + item("forgeOwnCreatures").width > dock.x)
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
        verify(item("forgeTurnIndicator").visible)
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
        const dock = item("rulesDecisionDock"), lane = item("forgeOwnCreatures"), hand = item("forgeHand")
        waitForRendering(table)
        verify(lane.x + lane.width <= dock.x || lane.y + lane.height <= dock.y)
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
}
