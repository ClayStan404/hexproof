// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"
import "../../qml/screens"

// Match lifecycle and authority checks use the same native session and Forge
// presentation as production. Layout/action coverage lives in tst_forgeduel_*.
ForgeDuelTestCase {
    name: "RulesTable"

    function visualChild(parent, name) {
        if (parent.objectName === name) return parent
        for (const child of parent.children || []) {
            const found = visualChild(child, name)
            if (found) return found
        }
        return null
    }
    Component {
        id: stackedTableComponent
        StackView {
            anchors.fill: parent
            initialItem: RulesTable {
                objectName: "stackedRulesTable"
                wsModel: transport
                cardCatalogModel: catalog
                gameTableModel: testGameTable
                sideboardTableModel: testSideboardTable
            }
        }
    }
    function test_shownTableTakesKeyFocus() {
        window.contentItem.forceActiveFocus()
        verify(!table.activeFocus)
        const stack = createTemporaryObject(stackedTableComponent, window.contentItem)
        verify(stack)
        const shown = stack.currentItem
        compare(shown.objectName, "stackedRulesTable")
        tryVerify(() => shown.activeFocus, 2000, "A newly activated production table owns keyboard input")
        verify(findChild(shown, "forgeOwnCreatures") !== null)
    }
    function test_publicCardMarkersUseCurrentProjection() {
        const state = snapshot()
        const creature = state.zones[4].cards[0]
        creature.power = "4"; creature.toughness = "4"; creature.damage = 2
        creature.counters = [{name:"P1P1", value:4}]
        verify(testRulesPrompt.applySnapshot(state))
        const face = item("forgeCard-own-0")
        compare(item("forgeCardStats-own-0").text, "4 / 4")
        const marks = item("forgeCardState-own-0")
        verify(marks.text.includes("+1/+1 × 4") && marks.text.includes("2 dmg"))
        mouseClick(face, face.width / 2, face.height / 2, Qt.RightButton)
        tryCompare(table.inspector, "hasCard", true)
        creature.damage = 0; creature.power = "5"; creature.counters[0].value = 5
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(item("forgeCardStats-own-0"), "text", "5 / 4")
        verify(marks.text.includes("+1/+1 × 5") && !marks.text.includes("dmg"))
        verify(table.inspector.stateLines().includes("Damage marked: 0"))
        creature.visible = false; creature.faceDown = true
        creature.identity = {name:"Private identity"}
        verify(testRulesPrompt.applySnapshot(state))
        compare(face.publicFace, false)
        verify(!catalog.requested.includes("Private identity"))
        verify(!catalog.nameRequests.includes("Private identity"))
        verify(!marks.text.includes("Private identity"))
    }
    function publish(values) {
        verify(testRulesPrompt.applySnapshot(Object.assign(snapshot(), values || {})))
    }
    function sideboardProjection(owner) {
        const state = {deadlineUnixMs: Date.now() + 300000,
            seats: [{seat:0, ready:false, mainboardCount:7, sideboardCount:1},
                    {seat:1, ready:false, mainboardCount:7, sideboardCount:1}]}
        if (owner) {
            state.mainboard = [{name:"Plains", count:7, typeLine:"Basic Land"}]
            state.sideboard = [{name:"Private Sideboard Card", count:1, typeLine:"Creature"}]
        }
        return state
    }
    function test_spaceUsesTheFocusedGameControl_data() {
        return [{tag:"table", focusCard:false, response:"$pass"},
                {tag:"card", focusCard:true, response:"opaque-play"}]
    }
    function test_spaceUsesTheFocusedGameControl(data) {
        action("playLand", "hand-0")
        verify(table.priority.canPass)
        waitForRendering(table)
        const target = data.focusCard ? item("forgeHandSurface-hand-0") : table.presentation
        window.contentItem.forceActiveFocus()
        waitForRendering(table)
        target.forceActiveFocus()
        tryCompare(window, "activeFocusItem", target)
        keyClick(Qt.Key_Space)
        compare(transport.responses.length, 1)
        compare(transport.responses[0].response, data.response)
    }
    function test_handManaAbilityCanBeClickedButNeverDraggedAsSpell() {
        prompt("payManaCost", {options:[{responseId:"hand-mana:opaque-response",
            kind:"activateAbility", cardId:"hand-0", label:"Exile this card: Add red mana"}]})
        const hand = item("forgeHandSurface-hand-0")
        tryCompare(hand, "actionable", true)
        verify(!table.canDragHandCard("hand-0"))
        verify(!table.playDraggedHandCard("hand-0", "Plains"))
        mouseDrag(hand, hand.width / 2, hand.height / 2, 0, -180)
        compare(transport.responses.length, 0)
        mouseClick(hand)
        compare(transport.responses, [{id:table.rulesSession.promptId, response:"hand-mana:opaque-response"}])
    }
    function test_actionPickerCannotCrossAuthorityOrPendingResponse_data() {
        return [{tag:"seat"}, {tag:"spectator"}, {tag:"pending"}]
    }
    function test_actionPickerCannotCrossAuthorityOrPendingResponse(data) {
        prompt("chooseAction", {options:[
            {responseId:"action:0", kind:"cast", cardId:"hand-0", label:"Cast one way"},
            {responseId:"action:1", kind:"cast", cardId:"hand-0", label:"Cast another way"}]})
        verify(table.playDraggedHandCard("hand-0", "Plains"))
        const picker = table.cardActionPicker
        tryCompare(picker, "opened", true)
        if (data.tag === "seat") room.seatIndex = 1
        else if (data.tag === "spectator") room.role = "spectator"
        else transport.rulesResponsePending = true
        tryCompare(picker, "opened", false)
        compare(picker.cardId, "")
        compare(picker.actions.length, 0)
        picker.submit("action:1")
        compare(transport.responses.length, 0)
    }
    function test_openingRollIsClearAndActionable() {
        prompt("diceRolled", {title:"Roll for first player", detail:"",
            options:[{responseId:"$ack", kind:"acknowledge", label:"Continue"}]})
        compare(item("rulesPromptTitle").text, "Roll to determine the first player")
        compare(item("rulesPromptDetail").text, "Forge will roll to determine who plays first.")
        const roll = item("rulesPromptOption-$ack")
        compare(roll.text, "Roll dice")
        verify(!table.canDragHandCard("hand-0"))
        mouseClick(roll)
        compare(transport.responses, [{id:table.rulesSession.promptId, response:"$ack"}])
    }
    function test_spaceInChatDoesNotPassPriority() {
        action("playLand", "hand-0")
        table.setGameLogVisible(true)
        const chat = table.gameLogRail.chatInput
        chat.text = "hello"
        chat.forceActiveFocus()
        tryCompare(chat, "activeFocus", true)
        keyClick(Qt.Key_Space)
        compare(chat.text, "hello ")
        compare(transport.responses.length, 0)
        chat.clear()
    }
    function test_escapeCancelsPassingBeforeClosingInspection() {
        prompt("chooseAction", {pending:false})
        table.openCardDetails("own-0")
        verify(table.priority.beginYield("response"))
        table.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(table.priority.yieldMode, "")
        verify(table.inspector.hasCard)
        keyClick(Qt.Key_Escape)
        verify(!table.inspector.hasCard)
        compare(transport.responses.length, 0)
    }
    function test_concedeRequiresConfirmationAndHidesAfterConcession() {
        openSettings()
        const rail = item("rulesActionRail")
        const button = visualChild(rail, "rulesConcedeButton-0")
        const dialog = item("rulesConcedeConfirmation")
        verify(button !== null)
        verify(button.visible)
        mouseClick(button)
        tryCompare(dialog, "opened", true)
        compare(transport.concedeCount, 0)
        mouseClick(findChild(dialog, "confirmButton"))
        tryCompare(dialog, "opened", false)
        compare(transport.concedeCount, 1)
        const state = snapshot()
        state.players[0].status = "conceded"
        verify(testRulesPrompt.applySnapshot(state))
        tryCompare(button, "visible", false)
    }
    function test_bo3SideboardUsesOwnerPartitionAndStartsNextGame() {
        room.matchMode = "bo3"
        publish({gameOver:true})
        match.score = [1, 0]
        match.result = {winnerSeat:0, matchFinished:false, reason:"rules"}
        match.sideboard = sideboardProjection(true)
        match.sideboarding = true
        const loader = item("rulesSideboardLoader")
        tryVerify(() => loader.item !== null)
        const panel = loader.item, ready = findChild(panel, "sideboardReadyButton")
        verify(panel.isPlayer)
        compare(panel.mainboard[0].count, 7)
        compare(panel.sideboard[0].name, "Private Sideboard Card")
        verify(panel.remainingSeconds > 290)
        verify(!item("rulesGameResultPopup").opened)
        verify(!table.canDragHandCard("hand-0"))
        verify(ready.enabled)
        mouseClick(ready)
        compare(transport.readyCount, 1)
        panel.moveSideboardCard(panel.sideboard[0], "sideboard", "mainboard")
        compare(transport.moveCount, 1)
        const incomplete = sideboardProjection(true)
        incomplete.mainboard[0].count = 6
        match.sideboard = incomplete
        tryCompare(ready, "enabled", false)
        match.sideboarding = false; match.sideboard = ({}); match.result = ({})
        match.gameNumber = 2
        publish()
        tryVerify(() => loader.item === null)
        verify(item("forgeOwnCreatures").visible)
        compare(table.matchUi.scoreSummary(), "1–0")
        room.seatIndex = 1
        compare(table.matchUi.scoreSummary(), "0–1")
        verify(!table.matchUi.canReturn)
    }
    function test_spectatorSideboardDoesNotContainPrivateCards() {
        room.role = "spectator"; room.seatIndex = -1; room.host = false
        match.sideboard = sideboardProjection(false); match.sideboarding = true
        const loader = item("rulesSideboardLoader")
        tryVerify(() => loader.item !== null)
        compare(loader.item.mainboard.length, 0)
        compare(loader.item.sideboard.length, 0)
        verify(loader.item.remainingSeconds > 290)
        verify(!findChild(loader.item, "sideboardReadyButton").visible)
        verify(!findChild(loader.item, "sideboardTables").visible)
        verify(table.canChat)
        transport.inRoom = false
        verify(!loader.item.enabled)
        verify(!table.canChat)
    }
    function test_terminalResultStayReviewAndReturnRequireFinishedMatch() {
        publish({gameOver:true})
        verify(!table.matchUi.canReturn)
        match.score = [2, 1]
        match.result = {winnerSeat:0, matchFinished:true, reason:"rules"}
        const result = item("rulesGameResultPopup")
        tryCompare(result, "opened", true)
        compare(result.titleText, "Alice wins the match")
        compare(result.outcome, "win")
        mouseClick(findChild(result, "stayAtTableButton"))
        tryCompare(result, "opened", false)
        table.matchUi.synchronizeResult()
        verify(!result.opened)
        verify(table.canChat)
        openSettings()
        const button = item("rulesReturnToRoomButton")
        verify(button.visible && button.enabled)
        transport.inRoom = false
        verify(!button.enabled)
        table.matchUi.returnToRoom()
        compare(transport.returnCount, 0)
        transport.inRoom = true
        mouseClick(button)
        compare(transport.returnCount, 1)
    }
    function test_restartAndLeaveConfirmAndRevalidateAuthority() {
        openSettings()
        const restart = item("rulesRestartGameButton"), dialog = item("rulesRestartConfirmation")
        verify(restart.visible && restart.enabled)
        mouseClick(restart)
        tryCompare(dialog, "opened", true)
        room.host = false
        dialog.confirmed()
        compare(transport.restartCount, 0)
        dialog.close()
        room.host = true
        table.matchUi.openRestartConfirmation()
        dialog.confirmed()
        compare(transport.restartCount, 1)
        dialog.close()
        const leave = item("rulesLeaveConfirmation")
        table.matchUi.openLeaveConfirmation()
        tryCompare(leave, "opened", true)
        transport.inRoom = false
        tryCompare(leave, "opened", false)
        leave.confirmed()
        compare(transport.leaveCount, 0)
        transport.inRoom = true; room.host = false
        table.matchUi.openLeaveConfirmation()
        compare(leave.message, "Leaving ends the current rules game and returns the other players to the waiting room.")
        leave.close()
        room.role = "spectator"
        table.matchUi.openLeaveConfirmation()
        compare(leave.message, "You will leave this room.")
        leave.close()
    }
    function test_terminalMetadataRestoresWithoutAnEngineSnapshot() {
        testRulesPrompt.clear()
        room.players = ["Alice", "Bob"]
        match.gameNumber = 2; match.score = [2, 0]
        match.result = {winnerSeat:0, matchFinished:true, reason:"rules"}
        const result = item("rulesGameResultPopup")
        tryCompare(result, "opened", true)
        verify(result.titleText.includes("Alice"))
        verify(table.matchUi.canReturn && !table.matchUi.canRestart)
        verify(table.canChat)
        verify(!table.playDraggedHandCard("hand-0", "Plains"))
        result.close()
        match.result = {winnerSeat:0, matchFinished:false, reason:"rules"}
        match.sideboard = sideboardProjection(true); match.sideboarding = true
        const loader = item("rulesSideboardLoader")
        tryVerify(() => loader.item !== null)
        verify(findChild(loader.item, "sideboardReadyButton").enabled)
        verify(!table.matchUi.canReturn)
    }
    function test_destructiveConfirmationsCannotCrossGameOrConnectionBoundaries_data() {
        const rows = []
        for (const action of ["concede", "restart"])
            for (const boundary of ["game", "connection", "inactive"])
                rows.push({tag:action + "-" + boundary, action, boundary})
        return rows
    }
    function test_destructiveConfirmationsCannotCrossGameOrConnectionBoundaries(data) {
        const concede = data.action === "concede"
        const dialog = item(concede ? "rulesConcedeConfirmation" : "rulesRestartConfirmation")
        const open = () => concede ? table.openConcedeConfirmation() : table.matchUi.openRestartConfirmation()
        open(); tryCompare(dialog, "opened", true)
        if (data.boundary === "game") publish({gameId:"replacement-game"})
        else if (data.boundary === "connection") transport.inRoom = false
        else if (concede) publish({gameOver:true})
        else match.sideboarding = true
        tryCompare(dialog, "opened", false)
        transport.inRoom = true; match.sideboarding = false
        publish()
        dialog.confirmed()
        compare(concede ? transport.concedeCount : transport.restartCount, 0)
        open(); tryCompare(dialog, "opened", true)
        mouseClick(findChild(dialog, "confirmButton"))
        tryCompare(dialog, "opened", false)
        compare(concede ? transport.concedeCount : transport.restartCount, 1)
        dialog.confirmed()
        compare(concede ? transport.concedeCount : transport.restartCount, 1)
    }
    function test_authorizedSpectatorHandsAreReadOnlyAndRevocable() {
        const state = snapshot()
        const otherHand = state.zones.find(zone => zone.zone === "hand" && zone.ownerSeat === 1)
        otherHand.cards = [card("authorized-second-hand", 1, "Opt", false)]
        verify(testRulesPrompt.applySnapshot(state))
        room.spectatorsSeeHands = true
        room.role = "spectator"; room.seatIndex = -1
        compare(table.handOwnerSeat, 0)
        const plate = item("rulesPlayerTarget1")
        const viewHand = plate.children.find(child => child.text === "View hand")
        verify(viewHand && viewHand.visible)
        mouseClick(viewHand)
        compare(table.handOwnerSeat, 1)
        tryCompare(item("forgeHandSurface-authorized-second-hand"), "visible", true)
        action("cast", "authorized-second-hand")
        verify(!table.canDragHandCard("authorized-second-hand"))
        verify(!table.playDraggedHandCard("authorized-second-hand", "Opt"))
        compare(transport.responses.length, 0)
        room.spectatorsSeeHands = false
        compare(table.handOwnerSeat, -1)
        tryCompare(item("forgeHand"), "visibleCards", [])
        verify(!viewHand.visible)
        room.spectatorsSeeHands = true
        compare(table.handOwnerSeat, 0)
        transport.inRoom = false
        compare(table.handOwnerSeat, -1)
        tryCompare(item("forgeHand"), "visibleCards", [])
    }
    function test_publicLogChatAndErrorsRemainUsableAfterGameOver() {
        testGameTable.applySnapshot({gameId:"duel-game", seats:[], log:[
            {id:1, kind:"chat", seat:1, text:"Bob: <b>hello</b>"}]})
        table.setGameLogVisible(true)
        const rail = table.gameLogRail, input = rail.chatInput
        const send = findChild(rail, "sendGameChatButton")
        tryCompare(findChild(rail, "gameLog"), "count", 1)
        room.role = "spectator"
        publish({gameOver:true})
        input.text = " Public reply "
        waitForRendering(rail)
        mouseClick(send)
        compare(transport.chatMessages, ["Public reply"])
        compare(input.text, "")
        table.setGameLogVisible(false); verify(!rail.visible)
        table.setGameLogVisible(true); verify(rail.visible)
        transport.lastError = "invalid_rules_response: Try again"
        verify(item("rulesErrorBanner").visible)
        transport.inRoom = false
        input.text = "Do not send"
        verify(!send.enabled)
        verify(!table.cardActions.submitChatMessage())
        compare(transport.chatMessages.length, 1)
        input.clear()
    }
}
