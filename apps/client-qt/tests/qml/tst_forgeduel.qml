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
    ApplicationWindow {
        id: window
        width: 1600; height: 1000; visible: true
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
            property bool spectatorsSeeHands: false
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
            property string lastError: ""
            property var responses: []
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
        }
        QtObject {
            id: catalog
            property int imageRevision: 0
            property var requested: []
            function tableImageSource(name, set, number) { requested.push(name); return "" }
            function imageSource(name, set, number) { requested.push(name); return "" }
            function cardTypeLine(name) { return name === "Plains" ? "Basic Land — Plains" : "Creature" }
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
    function snapshot(handCount, creatureCount) {
        const hand = [], creatures = []
        for (let i = 0; i < (handCount || 1); ++i) hand.push(card("hand-" + i, 0, "Plains", false))
        for (let i = 0; i < (creatureCount || 1); ++i) creatures.push(card("own-" + i, 0, "Grizzly Bears", true))
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
        match.sideboarding = false; transport.inRoom = true
        transport.responses = []; transport.rulesResponsePending = false
        testRulesPrompt.clear()
        verify(testRulesPrompt.applySnapshot(snapshot()))
        table.showGameLogRail = false
        table.inspector.clear()
        table.priority.setFullControl(false)
        prompt("diceRolled", {options:[{responseId:"$ack", kind:"acknowledge", label:"Continue"}]})
    }
    function cleanup() {
        const popup = item("forgeZonePopup")
        popup.close()
        tryCompare(popup, "visible", false)
        table.inspector.clear(); testRulesPrompt.clear()
        testTranslations.setLanguage("en")
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
        const controls = [item("forgeGameMenu"), item("rulesToggleGameLogButton"), item("rulesFullControl")]
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
        compare(table.combatInteraction.assignments["opaque-source"], "opaque-target")
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
        item("rulesCombatAssignment-opaque-source").forceActiveFocus(); keyClick(Qt.Key_Up)
        compare(table.combatInteraction.links.length, 0)
    }
    function test_combatStateCannotCrossAuthorityOrPromptBoundaries_data() {
        return [{tag:"disconnect"}, {tag:"spectate"}, {tag:"seat-change"}, {tag:"new-prompt"}, {tag:"new-game"}]
    }
    function test_multipleDefendersUseBoardAndPlayerSeat() {
        prompt("chooseAttackers", {combatSources:[{responseId:"source", objectId:"own-0", label:"Bear", name:"Grizzly Bears",
            validTargetIds:["player-choice", "walker-choice"], maxAssignments:1}], combatTargets:[
                {responseId:"player-choice", kind:"player", seat:1, label:"Opponent", minAssignments:0, maxAssignments:1},
                {responseId:"walker-choice", kind:"planeswalker", objectId:"opponent", label:"Walker", minAssignments:0, maxAssignments:1}]})
        mouseClick(item("forgeCard-own-0"))
        verify(!item("rulesPlayerTarget0").actionable)
        verify(item("rulesPlayerTarget1").actionable)
        mouseClick(item("forgeCard-opponent"))
        compare(table.combatInteraction.assignments.source, "walker-choice")
        mouseClick(item("forgeCard-own-0"))
        mouseClick(item("rulesPlayerTarget1"))
        compare(table.combatInteraction.assignments.source, "player-choice")
        compare(table.combatInteraction.links[0].seat, 1)
        mouseClick(item("rulesConfirmCombat-attackers"))
        compare(transport.responses[0].assignments, [{sourceId:"source", targetId:"player-choice"}])
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
        mouseClick(item("rulesConfirmCombat-blockers"))
        compare(transport.responses[0].assignments, [{sourceId:"source", targetId:"a"}, {sourceId:"source", targetId:"b"}])
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
        if (data.tag === "disconnect") transport.inRoom = false
        else if (data.tag === "spectate") room.role = "spectator"
        else if (data.tag === "seat-change") room.seatIndex = 1
        else if (data.tag === "new-prompt") combat("chooseAttackers")
        else { const next = snapshot(); next.gameId = "next-game"; verify(testRulesPrompt.applySnapshot(next)) }
        compare(table.combatInteraction.links.length, 0)
        compare(table.combatInteraction.selectedSource, "")
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
    function test_crowdedLanesAndHandRemainReachable() {
        verify(testRulesPrompt.applySnapshot(snapshot(20, 70)))
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
        mouseClick(item("rulesToggleGameLogButton"))
        const log = item("rulesInspectionHost"), stack = item("forgeStack")
        tryVerify(() => table.gameLogRail.visible && log.x >= dock.x + dock.width)
        verify(log.x >= stack.x + stack.width)
        verify(log.y >= 0 && log.y < 20 * table.presentation.unit)
        verify(log.x + log.width <= table.width && log.y + log.height <= table.height)
        for (const name of ["forgeOwnLands", "forgeOpponentLands", "forgeOwnOther", "forgeOpponentOther",
                           "forgeOwnCreatures", "forgeOpponentCreatures", "forgeHand"]) {
            const lane = item(name)
            verify(lane.width > 0 && lane.x + lane.width <= dock.x)
        }
        table.gameLogRail.chatInput.text = "Preserved draft"
        mouseClick(item("rulesConfirmCombat-attackers"))
        compare(transport.responses.length, 1)
        compare(table.gameLogRail.chatInput.text, "Preserved draft")
        mouseClick(item("rulesToggleGameLogButton"))
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
        tryVerify(() => lane.visibleCards.length === 70 && stack.currentTarget !== null)
        compare(arrow.endPoint.x, 0)
        mouseClick(item("forgeStackTarget-bolt-0"))
        tryVerify(() => lane.scrollArea.contentY > 0 && arrow.visible)
        verify(item("forgeCard-own-69").located)
        verify(!item("forgeCard-own-0").located)
        lane.scrollArea.contentY = 0
        tryCompare(arrow, "visible", false)
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
    function test_hoverPreviewClosesWithoutMovingTheBoard() {
        action("playLand", "hand-0")
        const lane = item("forgeOwnCreatures"), x = lane.x, width = lane.width
        mouseMove(item("forgeHandCard-hand-0"), 20, 40)
        tryCompare(table.inspector, "hasCard", true)
        const preview = item("rulesCardHoverPreview"), source = item("forgeHandCard-hand-0")
        tryCompare(preview, "visible", true)
        const origin = source.mapToItem(table, 0, 0)
        verify(preview.x >= origin.x + source.width || preview.x + preview.width <= origin.x)
        verify(preview.y >= 0 && preview.y + preview.height <= table.height)
        verify(!item("rulesInspectionHost").visible)
        mouseMove(table, 30, 70)
        tryCompare(table.inspector, "hasCard", false)
        compare(item("rulesInspectionHost").visible, false)
        compare(lane.x, x); compare(lane.width, width)
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
        compare(table.combatInteraction.assignments["opaque-source"], "opaque-target")
    }
    function test_floatingPreviewPreservesOpenLogAndChatDraft() {
        action("playLand", "hand-0")
        table.setGameLogVisible(true)
        table.gameLogRail.chatInput.text = "Unsent draft"
        mouseMove(item("forgeHandCard-hand-0"), 20, 40)
        tryCompare(item("rulesCardHoverPreview"), "visible", true)
        verify(item("rulesInspectionHost").visible)
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
        verify(hand.height <= hand.faceHeight * 0.6)
        verify(item("forgeOwnCreatures").height > 280 * table.presentation.unit)
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
            tryVerify(() => lane.visibleCards.length === 8)
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
        const state = snapshot(7, data.count)
        state.zones[5].cards = Array.from({length:data.count}, (_, i) => card("other-" + i, 1, "Grizzly Bears", true))
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
                localized.push(Object.assign({}, data, {tag:data.tag + "-" + language, language:language}))
        }
        return localized
    }
    function test_tableControlsShareDecisionDockAndFreeTopEdge(data) {
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        testTranslations.setLanguage(data.language)
        action("playLand", "hand-0")
        const dock = item("rulesDecisionDock"), opponent = item("rulesPlayerTarget1")
        const top = item("forgeOpponentCreatures"), bottom = item("forgeOwnCreatures")
        verify(top.height + bottom.height > table.height * 0.7)
        verify(opponent.y < 12 * table.presentation.unit)
        for (const name of ["forgeTurnIndicator", "forgeTurnPhase", "forgeGameMenu", "rulesToggleGameLogButton",
                           "rulesPriorityStatus", "rulesFullControl", "rulesYieldMenuButton"]) {
            const control = findChild(dock, name)
            verify(control !== null && control.visible, name + " belongs to the decision dock")
            const point = control.mapToItem(dock, 0, 0)
            verify(point.x >= 0 && point.x + control.width <= dock.width + 1, name + " fits dock width")
            verify(point.y >= 0 && point.y + control.height <= dock.height + 1, name + " fits dock height")
        }
        mouseClick(item("forgeGameMenu"))
        compare(item("forgeGameMenu").text, data.language === "zh" ? "设置" : "Settings")
        tryCompare(table.presentation, "modalOpen", true)
        keyClick(Qt.Key_Escape)
        tryCompare(table.presentation, "modalOpen", false)
        tryCompare(item("forgeGameDrawer"), "visible", false)
    }
    function test_settingsStayAccessibleBetweenGames() {
        match.sideboarding = true
        const dock = item("rulesDecisionDock"), loader = item("rulesSideboardLoader")
        waitForRendering(table)
        verify(dock.visible && !dock.expanded)
        verify(!item("rulesActionBar").visible)
        verify(!item("forgeTurnIndicator").visible)
        verify(loader.visible && loader.y + loader.height <= dock.y)
        mouseClick(item("forgeGameMenu"))
        tryCompare(table.presentation, "modalOpen", true)
        keyClick(Qt.Key_Escape)
        tryCompare(item("forgeGameDrawer"), "visible", false)
        match.sideboarding = false
        tryCompare(item("rulesActionBar"), "visible", true)
        verify(item("forgeTurnIndicator").visible)
    }
    function test_decisionsStayBesideBoardAndInsideWindow(data) {
        window.width = data.w; window.height = data.h
        Theme.uiScale = data.scale || 1
        combat("chooseAttackers")
        const dock = item("rulesDecisionDock"), lane = item("forgeOwnCreatures"), hand = item("forgeHand")
        waitForRendering(table)
        verify(dock.x >= lane.x + lane.width)
        verify(dock.x >= hand.x + hand.width)
        const confirm = item("rulesConfirmCombat-attackers")
        const point = confirm.mapToItem(table, 0, 0)
        verify(point.x >= dock.x && point.x + confirm.width <= table.width)
        verify(point.y >= dock.y && point.y + confirm.height <= table.height)
        mouseClick(confirm)
        compare(transport.responses.length, 1)
    }
}
