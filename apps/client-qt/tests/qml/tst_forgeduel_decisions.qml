// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"
import "../../qml/screens"
import "../../../../tools/ui-automation/scenarios/ForgeNecrodominanceStudy.js" as NecroStudy

// Native decisions, authority changes and match controls.
ForgeDuelTestCase {
    id: testCase
    name: "ForgeDuelDecisions"

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
        compare(Object.keys(item("forgeOwnCreatures").slotModel.combatGroupingKeys).length, 0,
            "Inactive combat cannot retain a retired lane's draft grouping")
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
    function test_decisionsStayBesideBoardAndInsideWindow_data() {
        return [{tag:"desktop", w:1600, h:1000}, {tag:"laptop", w:1280, h:800},
            {tag:"compact", w:900, h:620}, {tag:"scaled", w:1280, h:800, scale:1.35}]
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
    function test_priorityZoneActionsCanBeHiddenAndRevealed_data() {
        return [{tag:"duel", seats:[0,1], targetSeat:0, width:1920, height:1011, scale:1.2},
            {tag:"screenshot-chinese", seats:[0,1], targetSeat:0, width:1413, height:812, scale:1.2, language:"zh"},
            {tag:"compact-chinese", seats:[0,1], targetSeat:0, width:900, height:620, scale:1.2, language:"zh"},
            {tag:"three", seats:[0,1,2], targetSeat:0, width:1920, height:1011, scale:1.2},
            {tag:"four", seats:[0,1,2,3], targetSeat:1, width:1920, height:1011, scale:1.2}]
    }
    function test_priorityZoneActionsCanBeHiddenAndRevealed(data) {
        testTranslations.setLanguage(data.language || "en")
        setupNativePermanentRegions(data.seats, data)
        const state = zonedSnapshot(data.seats, 0)
        state.zones.push({zone:"graveyard", ownerSeat:0, count:2,
            cards:[card("yard-a",0,"Grizzly Bears",true), card("yard-b",0,"Grizzly Bears",true)]})
        verify(testRulesPrompt.applySnapshot(state))
        const options = [{responseId:"$pass",kind:"pass",label:"Pass"},
            {responseId:"yard-a-cast",kind:"cast",cardId:"yard-a",label:"Cast from graveyard"},
            {responseId:"yard-b-cast",kind:"cast",cardId:"yard-b",label:"Cast from graveyard"}]
        prompt("chooseAction", {options:options})
        const board = table.presentation, dock = item("rulesDecisionDock"), toggle = item("forgeDecisionCollapse")
        verify(table.priority.isPriorityPrompt && !dock.expanded && !dock.showsBody)
        const list = item("rulesZoneActions")
        compare(list.count, 2)
        verify(waitForPolish(window)); verify(waitForRendering(table))
        verify(dock.height > board.dockReservedHeight)
        verify(toggle.visible, "Ordinary priority with off-zone actions exposes Hide choice")
        const id = "z-" + data.targetSeat + "-Trinisphere", source = item("forgeCard-" + id)
        const bounds = () => source.mapToItem(board, 0, 0, source.width, source.height)
        const overlaps = () => {
            const face = bounds()
            return face.x < dock.x + dock.width && face.x + face.width > dock.x
                && face.y < dock.y + dock.height && face.y + face.height > dock.y
        }
        const before = bounds(), wasCovered = overlaps()
        const baseline = boardGeometry([id])
        mouseClick(toggle); verify(waitForPolish(window)); verify(waitForRendering(table))
        verify(dock.collapsed && !list.visible)
        verify(!overlaps(), "Hiding the zone actions exposes the complete permanent")
        compare(boardGeometry([id]), baseline, "The battlefield stays still")
        compare(bounds(), before)
        compare(transport.responses.length, 0, "Hide does not submit any game action")
        verify(item("forgeTurnIndicator").visible)
        verify(findChild(item("rulesActionBar"), "rulesPromptOption-$pass").visible)
        republish("chooseAction", {options:options})
        verify(dock.collapsed, "The same priority decision stays hidden")
        window.width += 10; verify(waitForPolish(window))
        verify(dock.collapsed, "Resizing does not restore hidden zone actions")
        window.width -= 10; verify(waitForPolish(window))
        mouseClick(toggle); verify(waitForPolish(window)); verify(waitForRendering(table))
        verify(!dock.collapsed && list.visible)
        if (wasCovered) {
            verify(board.reveal(id)); verify(waitForPolish(window)); verify(waitForRendering(table))
            verify(dock.collapsed, "Exact-object reveal hides off-zone actions even without a decision body")
            verify(!overlaps())
        }
        if (!dock.collapsed) mouseClick(toggle)
        prompt("chooseAction", {options:options})
        verify(!dock.collapsed && list.visible, "The next decision restores every zone action")
        compare(transport.responses.length, 0)
        mouseClick(item("rulesZoneAction-yard-b-cast"))
        compare(transport.responses.length, 1)
        compare(transport.responses[0].response, "yard-b-cast", "Restored zone actions retain exact identity")
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
            verify(waitForPolish(window))
            // Polish can consume the dirty frame before the render wait starts.
            window.update()
            verify(waitForRendering(table))
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
}
