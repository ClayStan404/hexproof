// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"
import "../../qml/screens"

TestCase {
    // The historical layout remains available to existing multiplayer rooms.
    // Ordinary 1v1 integration is exercised with real models in tst_forgeduel.qml.
    name: "RulesLegacyTable"
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 1280
        height: 800
        visible: true

        ListModel {
            id: players
            ListElement {
                seat: 0
                name: "Alice"
                status: "playing"
                life: 20
                countersSummary: ""
                manaSummary: ""
            }
            ListElement {
                seat: 1
                name: "Bob"
                status: "playing"
                life: 20
                countersSummary: ""
                manaSummary: ""
            }
        }

        ListModel {
            id: zones
            ListElement { zone: "hand"; ownerSeat: 0; count: 1 }
            ListElement { zone: "library"; ownerSeat: 0; count: 60 }
            ListElement { zone: "hand"; ownerSeat: 1; count: 0 }
            ListElement { zone: "library"; ownerSeat: 1; count: 60 }
            ListElement { zone: "graveyard"; ownerSeat: 1; count: 1 }
        }

        ListModel {
            id: battlefieldCards
            ListElement {
                cardId: "own-permanent"
                zone: "battlefield"
                zoneOwnerSeat: 0
                visibleIdentity: true
                name: "Plains"
                setCode: "M21"
                collectorNumber: "309"
                token: false
                ownerSeat: 0
                controllerSeat: 0
                tapped: false
                faceDown: false
                attacking: false
                power: ""
                toughness: ""
                damage: 0
                attachedTo: ""
                countersSummary: ""
            }
            ListElement {
                cardId: "opponent-permanent"
                zone: "battlefield"
                zoneOwnerSeat: 1
                visibleIdentity: true
                name: "Island"
                setCode: "M21"
                collectorNumber: "310"
                token: false
                ownerSeat: 1
                controllerSeat: 1
                tapped: false
                faceDown: false
                attacking: false
                power: ""
                toughness: ""
                damage: 0
                attachedTo: ""
                countersSummary: ""
            }
        }

        ListModel {
            id: zoneCards
            ListElement {
                cardId: "hand-card"
                zone: "hand"
                zoneOwnerSeat: 0
                visibleIdentity: true
                name: "Lightning Bolt"
                setCode: "M11"
                collectorNumber: "149"
                token: false
                ownerSeat: 0
                controllerSeat: 0
                tapped: false
                faceDown: false
                attacking: false
                power: ""
                toughness: ""
                damage: 0
                attachedTo: ""
                countersSummary: ""
            }
            ListElement {
                cardId: "opponent-grave"
                zone: "graveyard"
                zoneOwnerSeat: 1
                visibleIdentity: true
                name: "Opt"
                setCode: "M21"
                collectorNumber: "59"
                token: false
                ownerSeat: 1
                controllerSeat: 1
                tapped: false
                faceDown: false
                attacking: false
                power: ""
                toughness: ""
                damage: 0
                attachedTo: ""
                countersSummary: ""
            }
        }

        ListModel {
            id: emptyModel
            function validAssignments() { return true }
        }
        ListModel { id: manyPromptOptions }

        ListModel {
            id: rollPromptOptions
            ListElement {
                responseId: "$ack"
                kind: "acknowledge"
                label: "Continue"
            }
        }

        ListModel {
            id: castPromptOptions
            ListElement {
                responseId: "action:0"
                kind: "cast"
                label: "Play Lightning Bolt"
                cardId: "hand-card"
            }
            ListElement {
                responseId: "$pass"
                kind: "pass"
                label: "Pass priority"
                cardId: ""
            }
        }

        ListModel {
            id: modalCastPromptOptions
            ListElement {
                responseId: "action:0"
                kind: "cast"
                label: "Cast front face"
                cardId: "hand-card"
            }
            ListElement {
                responseId: "action:1"
                kind: "cast"
                label: "Cast back face"
                cardId: "hand-card"
            }
        }

        QtObject {
            id: rulesSession
            property string gameId: "rules-match"
            signal promptChanged()
            signal snapshotChanged()
            function cardForInspection(id) {
                for (const model of [battlefieldCards, zoneCards, stack]) {
                    for (let index = 0; index < model.count; ++index) {
                        const card = model.get(index)
                        if (card.cardId !== id)
                            continue
                        // The C++ invokable returns a value map. Explicit role
                        // reads preserve that contract without Object.assign's
                        // binding reentry on live ListModel.get() wrappers.
                        return {
                            cardId: card.cardId, zone: card.zone,
                            zoneOwnerSeat: card.zoneOwnerSeat,
                            visibleIdentity: card.visibleIdentity,
                            name: card.name, setCode: card.setCode,
                            collectorNumber: card.collectorNumber, token: card.token,
                            ownerSeat: card.ownerSeat, controllerSeat: card.controllerSeat,
                            tapped: card.tapped, faceDown: card.faceDown,
                            attacking: card.attacking, power: card.power,
                            toughness: card.toughness, damage: card.damage,
                            attachedTo: card.attachedTo, countersSummary: card.countersSummary
                        }
                    }
                }
                return ({})
            }

            property bool active: true
            property int snapshotRevision: 0
            property var zoneCountSnapshot: ({})
            property int turn: 0
            property string step: "reset"
            property int activeSeat: 0
            property int prioritySeat: 0
            property var players: players
            property int battlefieldCardCount: 2
            property var battlefieldCards: battlefieldCards
            property int visibleZoneCardCount: 2
            property var zoneCards: zoneCards
            property var zones: zones
            property var stack: emptyModel
            property bool gameOver: false
            property bool hasWinner: false
            property int winnerSeat: -1
            property bool promptPending: true
            property bool promptSupported: true
            property bool promptAutoPassEligible: false
            property int promptId: 1
            property string promptKind: "diceRolled"
            property string promptTitle: "Roll for first player"
            property string promptDetail: ""
            property var promptOptions: rollPromptOptions
            property var promptCards: emptyModel
            property var promptScryDestinations: []
            property var promptOrderItems: emptyModel
            property var promptTargets: emptyModel
            property var promptCombat: emptyModel
            property var promptChoices: emptyModel
            property var promptContextCards: emptyModel
            property var promptContextTargets: emptyModel
            property string promptContextText: ""
            property var promptDamageTargets: emptyModel
            property var promptDamageSource: ({})
            property int promptTotalDamage: 0
            property bool promptDamageDeathtouch: false
            property int promptMinCardSelections: 0
            property int promptMaxCardSelections: 0
            property int promptMinSelections: 0
            property int promptMaxSelections: 0
            property bool promptCancellable: false
            property int promptMinChoiceTotal: 0
            property int promptMaxChoiceTotal: 0
            property int promptMinNumber: 0
            property int promptMaxNumber: 0
            property var boardTargets: []

            function promptOptionItems() {
                const result = []
                for (let index = 0; index < promptOptions.count; ++index) {
                    const option = promptOptions.get(index)
                    result.push({responseId: option.responseId, kind: option.kind,
                                 label: option.label, cardId: option.cardId || ""})
                }
                return result
            }

            function stackObjectIds() {
                const result = []
                for (let index = 0; index < stack.count; ++index)
                    result.push(stack.get(index).cardId)
                return result
            }

            function boardTargetCandidates() {
                return boardTargets.map(target => Object.assign({label: "", objectId: "",
                    name: "", setCode: "", collectorNumber: "", token: false, seat: -1}, target))
            }
            function targetResponseIdsForObject(kind, id) {
                return boardTargets.filter(target => target.kind === kind && target.objectId === id)
                    .map(target => target.responseId)
            }
            function targetResponseIdsForSeat(seat) {
                return boardTargets.filter(target => target.kind === "player" && target.seat === seat)
                    .map(target => target.responseId)
            }

            function zoneCount(ownerSeat, zone) {
                // Mutating this plain object has no QML property notification,
                // just like data accessed behind the real C++ invokable.
                return zoneCountSnapshot[ownerSeat + ":" + zone] || 0
            }

            function cardActionsForCard(cardId) {
                if (!promptPending || !promptSupported
                        || (promptKind !== "chooseAction" && promptKind !== "payManaCost")) {
                    return []
                }
                const actions = []
                for (let index = 0; index < promptOptions.count; ++index) {
                    const option = promptOptions.get(index)
                    if (["cast", "playLand", "activateAbility"].includes(option.kind)
                            && option.cardId === cardId) {
                        actions.push({
                            "responseId": option.responseId,
                            "kind": option.kind,
                            "label": option.label
                        })
                    }
                }
                return actions
            }
        }

        QtObject {
            id: roomSession
            property int maxSeats: 4
            property string roomName: "Friday Forge"
            property string roomId: "ABCDEF"
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
            id: gameSession
            property int gameNumber: 1
            property var score: [0, 0]
            property var result: ({})
            property var sideboard: ({})
            property bool sideboarding: false
        }

        QtObject {
            id: fakeWs
            property var rulesSession: rulesSession
            property var roomSession: roomSession
            property var gameSession: gameSession
            property bool inRoom: true
            property string lastError: ""
            property bool rulesResponsePending: false
            property int responseCount: 0
            property int concedeCount: 0
            property int lastPromptId: 0
            property string lastResponseId: ""
            property var lastSelectedTargets: []
            property int restartCount: 0
            property int leaveCount: 0
            property int returnCount: 0
            property int chatCount: 0
            property string lastChat: ""
            property int readyCount: 0
            property int moveCount: 0

            function leaveRoom() { leaveCount++ }
            function restartGame() { restartCount++ }
            function sayGameMessage(message) { chatCount++; lastChat = message }
            function setSideboardReady(ready) { readyCount++ }
            function moveSideboardCard(card, from, to) { moveCount++ }
            function setSideboardCommander(name, designated) {}
            function concede() { concedeCount++ }
            function respondRulesPrompt(promptId, responseId) {
                rulesResponsePending = true
                responseCount++
                lastPromptId = promptId
                lastResponseId = responseId
            }
            function respondRulesPromptWithTargets(promptId, responseId, targets) {
                lastSelectedTargets = targets
                respondRulesPrompt(promptId, responseId)
            }
            function respondRulesPromptWithScry(promptId, piles) {}
            function returnToRoom() { returnCount++ }
        }

        QtObject {
            id: fakeCatalog
            property int imageRevision: 0

            function tableImageSource(name, setCode, collectorNumber) {
                return ""
            }
        }

        RulesTable {
            id: table
            anchors.fill: parent
            wsModel: fakeWs
            cardCatalogModel: fakeCatalog
            gameTableModel: testGameTable
            sideboardTableModel: testSideboardTable
        }
    }

    function resetMatchState() {
        Theme.uiScale = 1.0
        for (const name of ["rulesGameResultPopup", "rulesRestartConfirmation",
                             "rulesLeaveConfirmation"]) {
            const dialog = findChild(table, name)
            if (dialog) dialog.close()
        }
        roomSession.host = true
        roomSession.role = "player"
        roomSession.seatIndex = 0
        roomSession.matchMode = "bo1"
        roomSession.format = "modern"
        roomSession.spectatorsSeeHands = false
        gameSession.sideboarding = false
        gameSession.sideboard = ({})
        gameSession.result = ({})
        gameSession.score = [0, 0]
        gameSession.gameNumber = 1
        fakeWs.inRoom = true
        fakeWs.lastError = ""
        fakeWs.restartCount = 0
        fakeWs.leaveCount = 0
        fakeWs.returnCount = 0
        fakeWs.chatCount = 0
        fakeWs.lastChat = ""
        fakeWs.readyCount = 0
        fakeWs.moveCount = 0
        table.showGameLogRail = true
        testGameTable.applySnapshot({gameId: "rules-match", log: [], seats: [
            {seat: 0, displayName: "Alice"}, {seat: 1, displayName: "Bob"}
        ]})
    }

    function init() {
        testWindow.requestActivate()
        tryCompare(testWindow, "active", true)
        findChild(table, "rulesCardInspector").clear()
        Theme.uiTheme = "classic"
        TableBackgrounds.currentId = "default"
        const picker = findChild(table, "rulesCardActionPicker")
        if (picker !== null)
            picker.close()
        const concedeDialog = findChild(table, "rulesConcedeConfirmation")
        if (concedeDialog !== null)
            concedeDialog.close()
        testWindow.width = 1280
        testWindow.height = 800
        Theme.uiScale = 1.0
        resetMatchState()
        rulesSession.active = true
        rulesSession.gameId = "rules-match"
        rulesSession.zoneCountSnapshot = {
            "0:hand": 1, "0:library": 60, "0:battlefield": 1,
            "1:hand": 0, "1:library": 60, "1:graveyard": 1, "1:battlefield": 1
        }
        rulesSession.snapshotRevision++
        rulesSession.gameOver = false
        rulesSession.promptPending = true
        rulesSession.promptSupported = true
        rulesSession.promptAutoPassEligible = false
        table.priority.phaseStops = ({})
        table.priority.setFullControl(false)
        table.priority.resetTransient()
        rulesSession.promptId = 1
        rulesSession.promptKind = "diceRolled"
        rulesSession.promptTitle = "Roll for first player"
        rulesSession.promptDetail = ""
        rulesSession.promptOptions = rollPromptOptions
        rulesSession.promptContextText = ""
        rulesSession.boardTargets = []
        rulesSession.stack = emptyModel
        players.setProperty(0, "status", "playing")
        players.setProperty(1, "status", "playing")
        fakeWs.concedeCount = 0
        fakeWs.responseCount = 0
        fakeWs.lastSelectedTargets = []
        fakeWs.rulesResponsePending = false
        manyPromptOptions.clear()
        waitForRendering(table)
    }

    function test_defaultRestoresOpaqueClassicBattlefield() {
        const ownLane = findChild(table, "rulesBattlefieldLane0")
        const opponentLane = findChild(table, "rulesBattlefieldLane1")
        for (const background of ["default", "ink", "default"]) {
            TableBackgrounds.currentId = background
            for (const lane of [ownLane, opponentLane]) {
                verify(lane !== null)
                if (background === "default")
                    compare(lane.color, lane.isOwn ? Theme.primaryMuted : Theme.surfaceHover)
                else
                    verify(lane.color.a > 0 && lane.color.a < 1)
            }
        }
    }

    function test_zoneOnlySnapshotRefreshesCountsAndEmptyLabels() {
        const ownLibrary = findChild(table, "rulesOwnZoneTile-library")
        const opponentLibrary = findChild(table, "rulesOpponentZoneTile-1-library")
        const opponentGraveyard = findChild(table, "rulesOpponentZoneTile-1-graveyard")
        const ownSummary = findChild(table, "rulesBattlefieldSummary0")
        const opponentSummary = findChild(table, "rulesBattlefieldSummary1")
        const emptyHand = findChild(table, "rulesHandEmptyMessage")
        const emptyBattlefield = findChild(table, "rulesBattlefieldEmpty0")
        verify(ownLibrary && opponentLibrary && opponentGraveyard)
        verify(ownSummary && opponentSummary && emptyHand && emptyBattlefield)
        compare(ownLibrary.cardCount, 60)
        compare(opponentLibrary.cardCount, 60)
        compare(emptyHand.visible, false)
        compare(emptyBattlefield.visible, false)
        const turn = rulesSession.turn
        const ownLife = players.get(0).life
        const opponentLife = players.get(1).life

        rulesSession.zoneCountSnapshot["0:hand"] = 0
        rulesSession.zoneCountSnapshot["0:library"] = 53
        rulesSession.zoneCountSnapshot["0:battlefield"] = 0
        rulesSession.zoneCountSnapshot["1:hand"] = 4
        rulesSession.zoneCountSnapshot["1:library"] = 56
        rulesSession.zoneCountSnapshot["1:graveyard"] = 3
        rulesSession.snapshotRevision++

        tryCompare(ownLibrary, "cardCount", 53)
        tryCompare(opponentLibrary, "cardCount", 56)
        tryCompare(opponentGraveyard, "cardCount", 3)
        verify(ownSummary.text.indexOf("0H / 53D") >= 0)
        verify(opponentSummary.text.indexOf("4H / 56D") >= 0)
        compare(emptyHand.visible, true)
        compare(emptyBattlefield.visible, true)

        rulesSession.zoneCountSnapshot["0:hand"] = 2
        rulesSession.zoneCountSnapshot["0:battlefield"] = 2
        rulesSession.snapshotRevision++
        tryCompare(emptyHand, "visible", false)
        tryCompare(emptyBattlefield, "visible", false)
        compare(rulesSession.turn, turn)
        compare(players.get(0).life, ownLife)
        compare(players.get(1).life, opponentLife)
    }

    function test_zoneDockDelegatesDetachWithoutNullParentWarnings() {
        failOnWarning(/Cannot read property .* of null/)
        const saved = []
        for (let index = 0; index < players.count; ++index) {
            const row = players.get(index)
            saved.push({ seat: row.seat, name: row.name, status: row.status,
                         life: row.life, countersSummary: row.countersSummary,
                         manaSummary: row.manaSummary })
        }
        players.clear()
        wait(0)
        fakeCatalog.imageRevision++
        wait(0)
        for (const row of saved)
            players.append(row)
        wait(0)
        const tile = findChild(table, "rulesOpponentZoneTile-1-library")
        verify(tile)
        compare(tile.cardCount, 60)
        tryVerify(() => tile.width > 0 && tile.height > 0)
    }

    function test_primaryPlayAreaDoesNotCollapse() {
        const layout = findChild(table, "rulesGameLayout")
        const playArea = findChild(table, "rulesPlayArea")
        const actionRail = findChild(table, "rulesActionRail")
        const sharedRail = findChild(table, "rulesSharedZoneRail")
        const battlefield = findChild(table, "rulesBattlefieldPanel")
        const handArea = findChild(table, "rulesHandArea")
        verify(layout !== null)
        verify(playArea !== null)
        verify(actionRail !== null)
        verify(sharedRail !== null)
        verify(battlefield !== null)
        verify(handArea !== null)
        tryVerify(() => layout.width > 0)
        compare(actionRail.width, 144)
        compare(sharedRail.width, 92)
        compare(findChild(table, "gameLogRail").width, table.gameLogRailWidth)
        verify(playArea.width >= layout.width * 0.48,
               "play area " + playArea.width + " / layout " + layout.width)
        const inspectionHost = findChild(table, "rulesInspectionHost")
        verify(battlefield.width + inspectionHost.width >= playArea.width - 1,
               "Battlefield and the independent inspector fill the workspace")
        compare(handArea.width, playArea.width)
        verify(handArea.y > battlefield.y)
    }

    function test_decisionsAndInspectionNeverOverlapBattlefield_data() {
        return [
            {tag: "desktop", width: 1600, height: 1000, scale: 1},
            {tag: "laptop", width: 1280, height: 800, scale: 1},
            {tag: "compact", width: 900, height: 620, scale: 1},
            {tag: "scaled", width: 1280, height: 800, scale: 1.35}
        ]
    }

    function test_decisionsAndInspectionNeverOverlapBattlefield(data) {
        testWindow.width = data.width
        testWindow.height = data.height
        Theme.uiScale = data.scale
        const dock = findChild(table, "rulesDecisionDock")
        const field = findChild(table, "rulesBattlefieldHost")
        const hand = findChild(table, "rulesHandArea")
        const inspector = findChild(table, "rulesCardInspector")
        waitForRendering(table)
        const fieldRect = field.mapToItem(table, 0, 0, field.width, field.height)
        const dockRect = dock.mapToItem(table, 0, 0, dock.width, dock.height)
        verify(dockRect.y >= fieldRect.y + fieldRect.height - 1,
               "Decisions stay below the battlefield at every width")
        const handRect = hand.mapToItem(table, 0, 0, hand.width, hand.height)
        verify(dockRect.y + dockRect.height <= handRect.y + 1,
               "Decisions sit directly above the player's hand")
        compare(dock.width, hand.width)
        verify(field.height >= Theme.size(110), "Battlefield remains visible")
        table.openCardDetails("own-permanent")
        tryCompare(inspector, "hasCard", true)
        verify(inspector.pinned)
        waitForRendering(inspector)
        const inspectRect = inspector.mapToItem(table, 0, 0, inspector.width, inspector.height)
        const inspectedFieldRect = field.mapToItem(table, 0, 0, field.width, field.height)
        verify(inspectRect.x >= inspectedFieldRect.x + inspectedFieldRect.width - 1,
               "Card inspection has its own side area")
        const inspectedDockRect = dock.mapToItem(table, 0, 0, dock.width, dock.height)
        compare(inspectedDockRect.y, dockRect.y)
        compare(inspectedDockRect.width, dockRect.width)
        verify(findChild(table, "rulesPromptPanel").visible,
               "Opening card inspection never replaces the current decision")
        verify(hand.visible)
        mouseClick(findChild(inspector, "clearRulesCardInspectorButton"))
        tryCompare(inspector, "hasCard", false)
        verify(findChild(table, "rulesPromptPanel").visible)
        table.openCardDetails("own-permanent")
        table.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        tryCompare(inspector, "hasCard", false)
    }

    function test_localBattlefieldIsBelowOpponent() {
        const ownLane = findChild(table, "rulesBattlefieldLane0")
        const opponentLane = findChild(table, "rulesBattlefieldLane1")
        verify(ownLane !== null)
        verify(opponentLane !== null)
        tryVerify(() => ownLane.height > 0 && opponentLane.height > 0)
        verify(ownLane.y > opponentLane.y,
               "own lane " + ownLane.y + " / opponent lane "
               + opponentLane.y)
    }

    function test_priorityControlsStayBesideHandWithoutResizingForInspection_data() {
        return [
            {tag: "desktop", width: 1600, height: 1000},
            {tag: "compact", width: 900, height: 620}
        ]
    }

    function test_priorityControlsStayBesideHandWithoutResizingForInspection(data) {
        testWindow.width = data.width
        testWindow.height = data.height
        rulesSession.promptKind = "chooseAction"
        rulesSession.promptOptions = castPromptOptions
        const dock = findChild(table, "rulesDecisionDock")
        const field = findChild(table, "rulesBattlefieldHost")
        const hand = findChild(table, "rulesHandArea")
        waitForRendering(table)
        verify(!dock.expanded)
        verify(dock.height <= Theme.size(116),
               "Routine priority uses a compact action strip")
        verify(field.height >= testWindow.height * 0.5,
               "The battlefield keeps most of the vertical space")
        const initialDock = dock.mapToItem(table, 0, 0, dock.width, dock.height)
        const initialHand = hand.mapToItem(table, 0, 0, hand.width, hand.height)
        verify(initialDock.y + initialDock.height <= initialHand.y + 1)
        table.openCardDetails("own-permanent")
        waitForRendering(table)
        const inspectedDock = dock.mapToItem(table, 0, 0, dock.width, dock.height)
        compare(inspectedDock, initialDock)
        verify(!dock.expanded)
        verify(!findChild(table, "rulesPromptPanel").visible,
               "Routine priority does not repeat the large decision form")
    }

    function test_compactHoverKeepsInspectionSpaceUntilDismissed() {
        testWindow.width = 900
        table.setGameLogVisible(false)
        const dock = findChild(table, "rulesInspectionHost")
        const inspector = findChild(table, "rulesCardInspector")
        const field = findChild(table, "rulesBattlefieldHost")
        inspector.clear()
        waitForRendering(table)
        const fullWidth = field.width
        table.previewCard("own-permanent", table)
        tryCompare(dock, "visible", true)
        waitForRendering(table)
        const inspectedWidth = field.width
        verify(inspectedWidth < fullWidth)
        table.endCardPreview(table)
        tryCompare(inspector, "hasCard", false)
        waitForRendering(table)
        verify(dock.visible, "Leaving a hover must not move cards back under the pointer")
        compare(field.width, inspectedWidth)
        const close = findChild(inspector, "clearRulesCardInspectorButton")
        verify(close.visible)
        mouseClick(close)
        tryCompare(dock, "visible", false)
        tryCompare(field, "width", fullWidth)
    }

    function test_fourPlayerHeaderRemainsClickableBesideNarrowDecisionDock() {
        testWindow.width = 1180
        players.append({seat: 2, name: "Carol", status: "playing", life: 20,
                        countersSummary: "", manaSummary: ""})
        players.append({seat: 3, name: "Dave", status: "playing", life: 20,
                        countersSummary: "", manaSummary: ""})
        const battlefield = findChild(table, "rulesBattlefieldPanel")
        try {
            rulesSession.activeSeat = 0
            rulesSession.prioritySeat = 0
            const lane = findChild(table, "rulesBattlefieldLane0")
            const header = findChild(table, "rulesPlayerTarget0")
            const arrange = findChild(table, "rulesAutoArrange0")
            const viewport = findChild(table, "rulesBattlefieldViewport0")
            waitForRendering(table)
            const initialHeaderHeight = lane.headerHeight
            const initialViewportHeight = viewport.height
            battlefield.layoutState.remember(0, "own-permanent", 10, 10, 100, 100)
            rulesSession.promptId = 25
            rulesSession.promptKind = "chooseBoardTargets"
            rulesSession.promptOptions = emptyModel
            rulesSession.promptMinSelections = 1
            rulesSession.promptMaxSelections = 1
            rulesSession.boardTargets = [{responseId: "target:self", kind: "player", seat: 0}]
            verify(table.persistentInspectionDock)
            tryCompare(lane, "targetActionable", true)
            tryVerify(() => arrange.visible)
            waitForRendering(table)
            compare(lane.headerHeight, initialHeaderHeight)
            compare(viewport.height, initialViewportHeight)
            rulesSession.prioritySeat = 1
            waitForRendering(table)
            compare(lane.headerHeight, initialHeaderHeight)
            compare(viewport.height, initialViewportHeight)
            rulesSession.prioritySeat = 0
            verify(header.width >= Theme.size(144), "Player selection keeps a usable hit area")
            verify(header.x >= 0 && header.x + header.width <= lane.width)
            verify(viewport.y >= arrange.mapToItem(lane, 0, arrange.height).y,
                   "The badge row has reserved space above the cards")
            compare(table.interaction.fallbackTargets.length, 0)
            mouseClick(header, header.width / 2, header.height / 2)
            compare(fakeWs.responseCount, 1)
            compare(fakeWs.lastPromptId, 25)
            compare(fakeWs.lastResponseId, "$submit")
            compare(fakeWs.lastSelectedTargets, ["target:self"])
        } finally {
            battlefield.layoutState.reset(0)
            players.remove(2, players.count - 2)
            rulesSession.boardTargets = []
        }
    }

    function test_compactLayoutReturnsRailsToBattlefield() {
        const actionRail = findChild(table, "rulesActionRail")
        const sharedRail = findChild(table, "rulesSharedZoneRail")
        const playArea = findChild(table, "rulesPlayArea")
        testWindow.width = 1000
        tryCompare(actionRail, "width", 120)
        compare(sharedRail.visible, false)
        verify(playArea.width >= 875,
               "compact play area " + playArea.width)
    }

    function test_cardsFollowTabletopGeometry() {
        const ownCard = findChild(
                    table, "rulesBattlefieldCard-0-own-permanent")
        const opponentCard = findChild(
                    table, "rulesBattlefieldCard-1-opponent-permanent")
        const handCard = findChild(table, "rulesHandCard-hand-card")
        verify(ownCard !== null)
        verify(opponentCard !== null)
        verify(handCard !== null)
        verify(ownCard.visible)
        verify(opponentCard.visible)
        verify(handCard.visible)

        const ownPoint = ownCard.mapToItem(table, 0, 0)
        const opponentPoint = opponentCard.mapToItem(table, 0, 0)
        const handPoint = handCard.mapToItem(table, 0, 0)
        verify(ownPoint.y > opponentPoint.y)
        verify(handPoint.y > ownPoint.y)
    }

    function test_opponentPublicCardsRemainVisible() {
        const graveCard = findChild(
                    table,
                    "rulesOpponentZoneCard-1-graveyard-opponent-grave")
        verify(graveCard !== null)
        verify(graveCard.visible)
    }

    function test_openingRollIsClearAndActionable() {
        fakeWs.responseCount = 0
        fakeWs.lastPromptId = 0
        fakeWs.lastResponseId = ""

        const title = findChild(table, "rulesPromptTitle")
        const detail = findChild(table, "rulesPromptDetail")
        const rollButton = findChild(table, "rulesPromptOption-$ack")
        const handDrag = findChild(table, "rulesHandCardDrag-hand-card")
        verify(title !== null)
        verify(detail !== null)
        verify(rollButton !== null)
        verify(handDrag !== null)
        compare(title.text, "Roll to determine the first player")
        compare(detail.text, "Forge will roll to determine who plays first.")
        compare(rollButton.text, "Roll dice")
        compare(handDrag.enabled, false)

        mouseClick(rollButton, rollButton.width / 2, rollButton.height / 2)
        compare(fakeWs.responseCount, 1)
        compare(fakeWs.lastPromptId, 1)
        compare(fakeWs.lastResponseId, "$ack")
    }

    function test_nonDecidingPlayerSeesWaitingState() {
        rulesSession.promptPending = false

        const panel = findChild(table, "rulesPromptPanel")
        const status = findChild(table, "rulesPriorityStatus")
        const next = findChild(table, "rulesActionBar")
        verify(panel !== null)
        verify(status !== null)
        verify(next !== null)
        tryCompare(panel, "visible", false)
        compare(status.text, "Waiting for another player")
        verify(status.visible)
        verify(!findChild(next, "rulesPromptOption-$pass").visible)
    }

    function test_spaceUsesTheFocusedGameControl_data() {
        return [{tag: "table", focusCard: false, response: "$pass"},
                {tag: "card", focusCard: true, response: "action:0"}]
    }

    function test_spaceUsesTheFocusedGameControl(data) {
        rulesSession.promptKind = "chooseAction"
        rulesSession.promptOptions = castPromptOptions
        const target = data.focusCard
                ? findChild(table, "rulesHandCardSurface-hand-card")
                : findChild(table, "rulesBattlefieldHost")
        if (!data.focusCard)
            verify(table.priority.canPass, "The table has a current legal pass action")
        target.forceActiveFocus()
        tryCompare(target, "activeFocus", true)
        keyClick(Qt.Key_Space)
        compare(fakeWs.responseCount, 1)
        compare(fakeWs.lastResponseId, data.response)
    }

    function test_spaceInChatDoesNotPassPriority() {
        rulesSession.promptKind = "chooseAction"
        rulesSession.promptOptions = castPromptOptions
        table.setGameLogVisible(true)
        const chat = table.gameLogRail.chatInput
        chat.text = "hello"
        chat.forceActiveFocus()
        tryCompare(chat, "activeFocus", true)
        keyClick(Qt.Key_Space)
        compare(chat.text, "hello ")
        compare(fakeWs.responseCount, 0)
        chat.clear()
    }

    function test_escapeCancelsPassingBeforeClosingInspection() {
        rulesSession.promptPending = false
        table.openCardDetails("own-permanent")
        const inspector = findChild(table, "rulesCardInspector")
        verify(table.priority.beginYield("response"))
        table.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(table.priority.yieldMode, "")
        verify(inspector.hasCard)
        keyClick(Qt.Key_Escape)
        verify(!inspector.hasCard)
        compare(fakeWs.responseCount, 0)
    }

    function test_legalHandCardCanBeDraggedToBattlefield() {
        rulesSession.promptId = 9
        rulesSession.promptKind = "chooseAction"
        rulesSession.promptTitle = "Choose an action"
        rulesSession.promptDetail = "You have priority."
        rulesSession.promptOptions = castPromptOptions
        fakeWs.responseCount = 0
        fakeWs.lastPromptId = 0
        fakeWs.lastResponseId = ""

        const handCard = findChild(table, "rulesHandCard-hand-card")
        const handDrag = findChild(table, "rulesHandCardDrag-hand-card")
        const dropArea = findChild(table, "rulesBattlefieldDropArea0")
        verify(handCard !== null)
        verify(handDrag !== null)
        verify(dropArea !== null)
        tryCompare(handDrag, "enabled", true)

        const dropPoint = dropArea.mapToItem(
                            handDrag, dropArea.width / 2,
                            dropArea.height / 2)
        let dragChanges = 0
        handDrag.drag.activeChanged.connect(() => dragChanges++)
        mouseDrag(handDrag, handDrag.width / 2, handDrag.height / 2,
                  dropPoint.x - handDrag.width / 2,
                  dropPoint.y - handDrag.height / 2,
                  Qt.LeftButton, Qt.NoModifier, 30)

        compare(dragChanges, 2)
        tryCompare(fakeWs, "responseCount", 1)
        compare(fakeWs.lastPromptId, 9)
        compare(fakeWs.lastResponseId, "action:0")
    }

    function test_landIsPlayedByClickingItsHandCard() {
        rulesSession.promptId = 21
        rulesSession.promptKind = "chooseAction"
        manyPromptOptions.append({responseId: "land:opaque-response", kind: "playLand",
                                  label: "Play Plains", cardId: "hand-card"})
        rulesSession.promptOptions = manyPromptOptions
        const originalName = zoneCards.get(0).name
        zoneCards.setProperty(0, "name", "Plains")
        try {
            const card = findChild(table, "rulesHandCardSurface-hand-card")
            const drag = findChild(table, "rulesHandCardDrag-hand-card")
            tryCompare(card, "actionable", true)
            compare(drag.enabled, true)
            mouseClick(drag, drag.width / 2, drag.height / 2)
            compare(fakeWs.responseCount, 1)
            compare(fakeWs.lastPromptId, 21)
            compare(fakeWs.lastResponseId, "land:opaque-response")
            compare(card.actionable, false)
        } finally {
            zoneCards.setProperty(0, "name", originalName)
        }
    }

    function test_manaAbilityUsesPermanentPrimaryActionAndSecondaryInspection() {
        rulesSession.promptId = 22
        rulesSession.promptKind = "payManaCost"
        manyPromptOptions.append({responseId: "mana:opaque-response", kind: "activateAbility",
                                  label: "Add white mana", cardId: "own-permanent"})
        rulesSession.promptOptions = manyPromptOptions
        const card = findChild(table, "rulesBattlefieldCard-0-own-permanent")
        const inspector = findChild(table, "rulesCardInspector")
        tryCompare(card, "actionable", true)
        mouseClick(card, card.width / 2, card.height / 2, Qt.RightButton)
        compare(fakeWs.responseCount, 0)
        tryCompare(inspector, "pinnedCardId", "own-permanent")
        mouseClick(card, card.width / 2, card.height / 2, Qt.LeftButton)
        compare(fakeWs.responseCount, 1)
        compare(fakeWs.lastPromptId, 22)
        compare(fakeWs.lastResponseId, "mana:opaque-response")
    }

    function test_handManaAbilityCanBeClickedButNeverDraggedAsSpell() {
        rulesSession.promptId = 24
        rulesSession.promptKind = "payManaCost"
        manyPromptOptions.append({responseId: "hand-mana:opaque-response", kind: "activateAbility",
                                  label: "Exile Simian Spirit Guide: Add red mana", cardId: "hand-card"})
        rulesSession.promptOptions = manyPromptOptions
        const originalName = zoneCards.get(0).name
        zoneCards.setProperty(0, "name", "Simian Spirit Guide")
        try {
            const card = findChild(table, "rulesHandCardSurface-hand-card")
            const drag = findChild(table, "rulesHandCardDrag-hand-card")
            tryCompare(card, "actionable", true)
            compare(drag.enabled, false)
            verify(!table.canDragHandCard("hand-card"))
            verify(!table.playDraggedHandCard("hand-card", "Simian Spirit Guide"))
            mouseDrag(card, card.width / 2, card.height / 2, 0, -180)
            compare(fakeWs.responseCount, 0)
            compare(card.actionable, true)
            mouseClick(card, card.width / 2, card.height / 2)
            compare(fakeWs.responseCount, 1)
            compare(fakeWs.lastPromptId, 24)
            compare(fakeWs.lastResponseId, "hand-mana:opaque-response")
        } finally {
            zoneCards.setProperty(0, "name", originalName)
        }
    }

    function test_draggingActionablePermanentOnlyChangesItsPosition() {
        rulesSession.promptId = 23
        rulesSession.promptKind = "chooseAction"
        manyPromptOptions.append({responseId: "activation:opaque-response", kind: "activateAbility",
                                  label: "Add white mana", cardId: "own-permanent"})
        rulesSession.promptOptions = manyPromptOptions
        const card = findChild(table, "rulesBattlefieldCard-0-own-permanent")
        const slot = findChild(table, "rulesBattlefieldPosition-0-own-permanent")
        const field = findChild(table, "rulesBattlefieldPanel")
        tryCompare(card, "actionable", true)
        const beforeX = slot.x
        try {
            mouseDrag(card, card.width / 2, card.height / 2, 150, 0)
            tryVerify(() => slot.x > beforeX + 50)
            compare(fakeWs.responseCount, 0)
            compare(card.actionable, true)
        } finally {
            field.layoutState.reset(0)
        }
    }

    function test_overflowingHandScrollsWithoutStealingPlayableCardDrag() {
        const viewport = findChild(table, "rulesHandViewport")
        const scrollbar = findChild(table, "rulesHandScrollBar")
        verify(viewport && scrollbar)
        compare(scrollbar.policy, ScrollBar.AlwaysOff)
        const originalCount = zoneCards.count
        const template = JSON.parse(JSON.stringify(zoneCards.get(0)))
        rulesSession.promptKind = "chooseAction"
        manyPromptOptions.append({ responseId: "action:first", kind: "cast",
                                   label: "Cast first card", cardId: "hand-card" })
        rulesSession.promptOptions = manyPromptOptions
        try {
            for (let index = 0; index < 20; ++index) {
                const card = JSON.parse(JSON.stringify(template))
                card.cardId = "overflow-hand-" + index
                zoneCards.append(card)
                manyPromptOptions.append({ responseId: "action:overflow-" + index,
                                           kind: "cast", label: "Cast card " + index,
                                           cardId: card.cardId })
            }
            waitForRendering(table)
            tryVerify(() => viewport.contentWidth > viewport.width)
            compare(scrollbar.policy, ScrollBar.AlwaysOn)
            verify(scrollbar.visible && scrollbar.interactive)
            const firstDrag = findChild(table, "rulesHandCardDrag-hand-card")
            verify(firstDrag.enabled)
            mouseWheel(firstDrag, firstDrag.width / 2, firstDrag.height / 2, 0, -120)
            tryVerify(() => viewport.contentX > 0)
            compare(fakeWs.responseCount, 0)

            viewport.contentX = 0
            mouseDrag(scrollbar, scrollbar.width * scrollbar.size / 2,
                      scrollbar.height / 2, scrollbar.width, 0,
                      Qt.LeftButton, Qt.NoModifier, 30)
            tryVerify(() => viewport.atXEnd)
            const lastCard = findChild(table, "rulesHandCard-overflow-hand-19")
            const lastDrag = findChild(table, "rulesHandCardDrag-overflow-hand-19")
            verify(lastCard && lastDrag && lastDrag.enabled)
            const lastPosition = lastCard.mapToItem(viewport, 0, 0)
            verify(lastPosition.x >= -1)
            verify(lastPosition.x + lastCard.width <= viewport.width + 1)
            const barPosition = scrollbar.mapToItem(viewport, 0, 0)
            verify(lastPosition.y + lastCard.height <= barPosition.y)

            const dropArea = findChild(table, "rulesBattlefieldDropArea0")
            const dropPoint = dropArea.mapToItem(lastDrag, dropArea.width / 2,
                                               dropArea.height / 2)
            mouseDrag(lastDrag, lastDrag.width / 2, lastDrag.height / 2,
                      dropPoint.x - lastDrag.width / 2,
                      dropPoint.y - lastDrag.height / 2,
                      Qt.LeftButton, Qt.NoModifier, 30)
            tryCompare(fakeWs, "responseCount", 1)
            compare(fakeWs.lastResponseId, "action:overflow-19")
        } finally {
            zoneCards.remove(originalCount, zoneCards.count - originalCount)
            rulesSession.promptOptions = rollPromptOptions
            viewport.contentX = 0
        }
        tryCompare(scrollbar, "policy", ScrollBar.AlwaysOff)
    }

    function test_multipleCardActionsRequireExplicitChoice() {
        rulesSession.promptId = 10
        rulesSession.promptKind = "chooseAction"
        rulesSession.promptTitle = "Choose an action"
        rulesSession.promptDetail = "You have priority."
        rulesSession.promptOptions = modalCastPromptOptions
        fakeWs.responseCount = 0

        verify(table.playDraggedHandCard("hand-card", "Lightning Bolt"))
        const picker = findChild(table, "rulesCardActionPicker")
        verify(picker !== null)
        tryCompare(picker, "opened", true)
        compare(fakeWs.responseCount, 0)

        const backFace = findChild(picker, "rulesCardAction-action:1")
        verify(backFace !== null)
        mouseClick(backFace, backFace.width / 2, backFace.height / 2)
        compare(fakeWs.responseCount, 1)
        compare(fakeWs.lastPromptId, 10)
        compare(fakeWs.lastResponseId, "action:1")
    }

    function test_compactCastChoiceRemainsSeparateFromPinnedInspection() {
        testWindow.width = 700
        rulesSession.promptKind = "chooseAction"
        rulesSession.promptOptions = modalCastPromptOptions
        table.openCardDetails("own-permanent")
        const inspector = findChild(table, "rulesCardInspector")
        tryCompare(inspector, "hasCard", true)
        verify(table.playDraggedHandCard("hand-card", "Lightning Bolt"))
        const picker = findChild(table, "rulesCardActionPicker")
        waitForRendering(picker)
        verify(picker.visible)
        verify(inspector.visible, "Pinned inspection remains available beside the battlefield")
        const pickerRect = picker.mapToItem(table, 0, 0, picker.width, picker.height)
        const inspectionRect = inspector.mapToItem(table, 0, 0, inspector.width, inspector.height)
        verify(inspectionRect.y + inspectionRect.height <= pickerRect.y + 1,
               "Inspection cannot cover a cast-mode choice")
        const backFace = findChild(picker, "rulesCardAction-action:1")
        mouseClick(backFace)
        compare(fakeWs.responseCount, 1)
        compare(fakeWs.lastResponseId, "action:1")
    }

    function test_cardActionPickerClosesWhenViewerAuthorityChanges_data() {
        return [{tag: "seat", role: "player", seat: 1},
                {tag: "spectator", role: "spectator", seat: 0}]
    }

    function test_cardActionPickerClosesWhenViewerAuthorityChanges(data) {
        rulesSession.promptId = 24
        rulesSession.promptKind = "chooseAction"
        rulesSession.promptOptions = modalCastPromptOptions
        verify(table.playDraggedHandCard("hand-card", "Lightning Bolt"))
        const picker = findChild(table, "rulesCardActionPicker")
        tryCompare(picker, "opened", true)
        roomSession.role = data.role
        roomSession.seatIndex = data.seat
        tryCompare(picker, "opened", false)
        compare(picker.cardId, "")
        compare(picker.actions.length, 0)
        picker.submit("action:1")
        compare(fakeWs.responseCount, 0)
    }

    function test_tallDecisionReservesSpaceOutsideBattlefieldAndScrolls() {
        testWindow.width = 900
        testWindow.height = 620
        Theme.uiScale = 1.35
        rulesSession.promptKind = "chooseBoardTargets"
        rulesSession.promptTitle = "Choose a target for Lightning Bolt"
        rulesSession.promptDetail = "Choose exactly one target."
        rulesSession.promptContextText = "Lightning Bolt targets one creature or player."
        const panel = findChild(table, "rulesPromptPanel")
        const host = findChild(table, "rulesBattlefieldHost")
        waitForRendering(table)
        verify(panel.mapToItem(host, 0, 0).y >= host.height,
               "The entire decision must stay below the battlefield")
        const body = findChild(table, "rulesPromptScroll")
        verify(body !== null)
        verify(body.contentHeight > body.height)
        mouseWheel(body, body.width / 2, body.height / 2, 0, -480)
        tryVerify(() => body.contentY > 0)
        const confirmation = findChild(table, "rulesConfirmTargets")
        tryVerify(() => confirmation.mapToItem(body, 0, confirmation.height).y <= body.height + 1,
                  1000, "Confirmation remains reachable by scrolling")
    }

    function test_publicPlayerAndCardCountersAreVisibleOnBattlefield() {
        const card = findChild(table, "rulesBattlefieldCard-0-own-permanent")
        verify(card !== null)
        players.setProperty(0, "countersSummary", "Energy 3")
        battlefieldCards.setProperty(0, "damage", 2)
        battlefieldCards.setProperty(0, "power", "4")
        battlefieldCards.setProperty(0, "toughness", "4")
        battlefieldCards.setProperty(0, "countersSummary", "+1/+1 4")
        battlefieldCards.setProperty(0, "attachedTo", "opponent-permanent")
        try {
            const energy = findChild(table, "rulesPlayerCounters0")
            tryVerify(() => energy.visible)
            compare(energy.text, "Energy 3")
            compare(card.damageMarked, 2)
            compare(card.attachmentId, "opponent-permanent")
            compare(findChild(card, "rulesCardCounters").text, "+1/+1 4")
            verify(findChild(card, "rulesCardCounters").visible)
            verify(findChild(card, "rulesCardDamage").visible)
            verify(findChild(card, "rulesCardAttachment").visible)
            verify(card.inspectable)
        } finally {
            players.setProperty(0, "countersSummary", "")
            battlefieldCards.setProperty(0, "damage", 0)
            battlefieldCards.setProperty(0, "power", "")
            battlefieldCards.setProperty(0, "toughness", "")
            battlefieldCards.setProperty(0, "countersSummary", "")
            battlefieldCards.setProperty(0, "attachedTo", "")
        }
    }

    function test_manyActionsRemainDiscoverableAtNarrowWidth_data() {
        return [
            { tag: "compact", width: 900, scale: 1.0 },
            { tag: "narrow", width: 700, scale: 1.0 },
            { tag: "scaled", width: 900, scale: 1.25 }
        ]
    }

    function test_manyActionsRemainDiscoverableAtNarrowWidth(data) {
        testWindow.width = data.width
        testWindow.height = 620
        Theme.uiScale = data.scale
        rulesSession.promptKind = "chooseAction"
        rulesSession.promptTitle = "Choose an action while Lightning Bolt waits on the stack"
        rulesSession.promptDetail = "Choose a spell or activated ability, or pass priority to let the next player respond. This deliberately long instruction must remain readable at narrow widths."
        for (let index = 0; index < 20; ++index) {
            manyPromptOptions.append({ responseId: "action:" + index,
                                       kind: "activate", label: "Activate ability " + index })
        }
        manyPromptOptions.append({responseId: "$pass", kind: "pass", label: "Pass priority"})
        rulesSession.promptOptions = manyPromptOptions
        const panel = findChild(table, "rulesPromptPanel")
        const status = findChild(table, "rulesPriorityStatus")
        const options = findChild(table, "rulesPriorityFallbackActions")
        const scrollbar = findChild(table, "rulesPriorityFallbackActionsScrollBar")
        waitForRendering(table)
        tryVerify(() => options.contentWidth > options.width)
        compare(scrollbar.policy, ScrollBar.AlwaysOn)
        verify(scrollbar.visible)
        verify(!panel.visible)
        verify(status.visible)
        compare(status.textFormat, Text.PlainText)

        const initialX = options.contentX
        mouseWheel(options, options.width / 2, 15, 0, -120)
        tryVerify(() => options.contentX > initialX)
        for (let index = 0; index < 30; ++index)
            scrollbar.increase()
        tryVerify(() => options.atXEnd)
        const last = findChild(options, "rulesPromptOption-action:19")
        verify(last !== null)
        const position = last.mapToItem(options, last.width / 2, last.height / 2)
        verify(position.x > 0 && position.x < options.width)
        mouseClick(options, position.x, position.y)
        compare(fakeWs.responseCount, 1)
        compare(fakeWs.lastResponseId, "action:19")
    }

    function test_responsePendingBlocksClicksAndHandActions() {
        rulesSession.promptKind = "chooseAction"
        rulesSession.promptOptions = castPromptOptions
        const card = findChild(table, "rulesHandCardSurface-hand-card")
        verify(card !== null)
        tryCompare(card, "actionable", true)
        verify(table.canDragHandCard("hand-card"))
        waitForRendering(table)
        mouseClick(card, card.width / 2, card.height / 2)
        compare(fakeWs.responseCount, 1)
        verify(!card.actionable)
        verify(!table.canDragHandCard("hand-card"))
        verify(!table.playDraggedHandCard("hand-card", "Lightning Bolt"))
        mouseClick(card, card.width / 2, card.height / 2)
        compare(fakeWs.responseCount, 1)
        fakeWs.rulesResponsePending = false
        tryCompare(card, "actionable", true)
        verify(table.canDragHandCard("hand-card"))
    }

    function test_pendingResponseInvalidatesOpenCardActionPicker() {
        rulesSession.promptKind = "chooseAction"
        rulesSession.promptOptions = modalCastPromptOptions
        verify(table.playDraggedHandCard("hand-card", "Lightning Bolt"))
        const picker = findChild(table, "rulesCardActionPicker")
        tryCompare(picker, "opened", true)
        fakeWs.rulesResponsePending = true
        picker.submit("action:1")
        compare(fakeWs.responseCount, 0)
        tryCompare(picker, "opened", false)
    }

    function test_concedeRequiresConfirmationAndHidesAfterConcession() {
        const button = findChild(table, "rulesConcedeButton-0")
        const dialog = findChild(table, "rulesConcedeConfirmation")
        verify(button !== null)
        verify(dialog !== null)
        verify(button.visible)

        mouseClick(button, button.width / 2, button.height / 2)
        tryCompare(dialog, "opened", true)
        compare(fakeWs.concedeCount, 0)
        const confirm = findChild(dialog, "confirmButton")
        verify(confirm !== null)
        mouseClick(confirm, confirm.width / 2, confirm.height / 2)
        tryCompare(dialog, "opened", false)
        compare(fakeWs.concedeCount, 1)

        players.setProperty(0, "status", "conceded")
        tryCompare(button, "visible", false)
    }

    function sideboardProjection(owner) {
        const state = {
            deadlineUnixMs: Date.now() + 300000,
            seats: [{seat: 0, ready: false, mainboardCount: 7, sideboardCount: 1},
                    {seat: 1, ready: false, mainboardCount: 7, sideboardCount: 1}]
        }
        if (owner) {
            state.mainboard = [{name: "Plains", count: 7, typeLine: "Basic Land"}]
            state.sideboard = [{name: "Private Sideboard Card", count: 1, typeLine: "Creature"}]
        }
        return state
    }

    function test_faceDownStackUsesCardBackAndPublicLabel() {
        rulesSession.stack = testRulesSnapshot.stack
        const list = findChild(table, "rulesStackCards")
        tryCompare(list, "count", 2)
        const card = findChild(list, "rulesStackCard-0")
        verify(card !== null)
        verify(!card.visibleIdentity)
        verify(card.faceDown)
        compare(card.name, "")
        compare(card.hiddenLabel, "Face-down spell")
        compare(String(card.imageSource()), String(table.cardBackSource))
        compare(findChild(card, "rulesCardTooltipText").textFormat, Text.PlainText)
        const visibleCard = findChild(list, "rulesStackCard-1")
        verify(visibleCard !== null)
        verify(visibleCard.visibleIdentity && !visibleCard.faceDown)
        compare(visibleCard.name, "Lightning Bolt")
    }

    function test_selectedStackMarkerDoesNotOverlapItsControllerBadge() {
        rulesSession.stack = testRulesSnapshot.stack
        const list = findChild(table, "rulesStackCards")
        tryCompare(list, "count", 2)
        const card = findChild(list, "rulesStackCard-1")
        rulesSession.promptKind = "chooseBoardTargets"
        rulesSession.promptOptions = emptyModel
        rulesSession.promptMinSelections = 1
        rulesSession.promptMaxSelections = 2
        rulesSession.boardTargets = [{responseId: "target:stack", kind: "spell",
                                     objectId: card.objectId}]
        tryCompare(card, "actionable", true)
        mouseClick(card, card.width / 2, card.height / 2)
        tryCompare(card, "selected", true)
        const marker = findChild(card, "rulesCardSelectedTarget")
        const badge = findChild(card, "rulesStackController-1")
        verify(marker.visible)
        verify(badge.y >= marker.y + marker.height,
               "The seat badge must not cover the selected target checkmark")
        compare(fakeWs.responseCount, 0)
    }

    function test_bo3SideboardUsesOwnerPartitionAndStartsNextGame() {
        roomSession.matchMode = "bo3"
        rulesSession.gameOver = true
        gameSession.score = [1, 0]
        gameSession.result = {winnerSeat: 0, matchFinished: false, reason: "rules"}
        gameSession.sideboard = sideboardProjection(true)
        gameSession.sideboarding = true
        const loader = findChild(table, "rulesSideboardLoader")
        tryVerify(() => loader.item !== null)
        const panel = loader.item
        verify(panel.isPlayer)
        compare(panel.mainboard[0].count, 7)
        compare(panel.sideboard[0].name, "Private Sideboard Card")
        verify(panel.remainingSeconds > 290)
        verify(!findChild(table, "rulesReturnToRoomButton").visible)
        verify(!findChild(table, "rulesGameResultPopup").opened)
        verify(!table.canDragHandCard("hand-card"))
        const ready = findChild(panel, "sideboardReadyButton")
        verify(ready.enabled)
        mouseClick(ready, ready.width / 2, ready.height / 2)
        compare(fakeWs.readyCount, 1)
        panel.moveSideboardCard(panel.sideboard[0], "sideboard", "mainboard")
        compare(fakeWs.moveCount, 1)
        const incomplete = sideboardProjection(true)
        incomplete.mainboard[0].count = 6
        gameSession.sideboard = incomplete
        tryCompare(ready, "enabled", false)

        gameSession.sideboarding = false
        gameSession.sideboard = ({})
        gameSession.result = ({})
        gameSession.gameNumber = 2
        rulesSession.gameOver = false
        tryVerify(() => loader.item === null)
        verify(findChild(table, "rulesBattlefieldHost").visible)
        compare(table.matchUi.scoreSummary(), "1–0")
        roomSession.seatIndex = 1
        compare(table.matchUi.scoreSummary(), "0–1")
        verify(!findChild(table, "rulesReturnToRoomButton").visible)
    }

    function test_spectatorSideboardDoesNotContainPrivateCards() {
        roomSession.role = "spectator"
        roomSession.seatIndex = -1
        roomSession.host = false
        gameSession.sideboard = sideboardProjection(false)
        gameSession.sideboarding = true
        const loader = findChild(table, "rulesSideboardLoader")
        tryVerify(() => loader.item !== null)
        compare(loader.item.mainboard.length, 0)
        compare(loader.item.sideboard.length, 0)
        verify(loader.item.remainingSeconds > 290)
        verify(!findChild(loader.item, "sideboardReadyButton").visible)
        verify(!findChild(loader.item, "sideboardTables").visible)
        verify(table.canChat)
        fakeWs.inRoom = false
        verify(!loader.item.enabled)
        verify(!table.canChat)
    }

    function test_terminalResultStayReviewAndReturnRequireFinishedMatch() {
        rulesSession.gameOver = true
        verify(!findChild(table, "rulesReturnToRoomButton").visible)
        gameSession.score = [2, 1]
        gameSession.result = {winnerSeat: 0, matchFinished: true, reason: "rules"}
        const result = findChild(table, "rulesGameResultPopup")
        tryCompare(result, "opened", true)
        compare(result.titleText, "Alice wins the match")
        compare(result.outcome, "win")
        const stay = findChild(result, "stayAtTableButton")
        mouseClick(stay, stay.width / 2, stay.height / 2)
        tryCompare(result, "opened", false)
        table.matchUi.synchronizeResult()
        verify(!result.opened)
        verify(table.canChat)
        const button = findChild(table, "rulesReturnToRoomButton")
        verify(button.visible && button.enabled)
        fakeWs.inRoom = false
        verify(!button.enabled)
        table.matchUi.returnToRoom()
        compare(fakeWs.returnCount, 0)
        fakeWs.inRoom = true
        mouseClick(button, button.width / 2, button.height / 2)
        compare(fakeWs.returnCount, 1)
    }

    function test_restartAndLeaveConfirmAndRevalidateAuthority() {
        const restart = findChild(table, "rulesRestartGameButton")
        const dialog = findChild(table, "rulesRestartConfirmation")
        verify(restart.visible && restart.enabled)
        mouseClick(restart, restart.width / 2, restart.height / 2)
        tryCompare(dialog, "opened", true)
        compare(fakeWs.restartCount, 0)
        roomSession.host = false
        dialog.confirmed()
        compare(fakeWs.restartCount, 0)
        dialog.close()
        roomSession.host = true
        table.matchUi.openRestartConfirmation()
        dialog.confirmed()
        compare(fakeWs.restartCount, 1)
        dialog.close()
        const leave = findChild(table, "rulesLeaveConfirmation")
        table.matchUi.openLeaveConfirmation()
        tryCompare(leave, "opened", true)
        fakeWs.inRoom = false
        tryCompare(leave, "opened", false)
        leave.confirmed()
        compare(fakeWs.leaveCount, 0)
        fakeWs.inRoom = true
        roomSession.host = false
        table.matchUi.openLeaveConfirmation()
        compare(leave.message,
                "Leaving ends the current rules game and returns the other players to the waiting room.")
        leave.close()
        roomSession.role = "spectator"
        table.matchUi.openLeaveConfirmation()
        compare(leave.message, "You will leave this room.")
        leave.close()
    }

    function test_terminalMetadataRestoresWithoutAnEngineSnapshot() {
        rulesSession.active = false
        rulesSession.gameOver = false
        rulesSession.promptPending = false
        gameSession.gameNumber = 2
        gameSession.score = [2, 0]
        gameSession.result = {winnerSeat: 0, matchFinished: true, reason: "rules"}
        const result = findChild(table, "rulesGameResultPopup")
        tryCompare(result, "opened", true)
        verify(result.titleText.indexOf("Alice") >= 0)
        verify(findChild(table, "rulesReturnToRoomButton").visible)
        verify(!findChild(table, "rulesRestartGameButton").visible)
        verify(!findChild(table, "rulesTurnSummary").visible)
        verify(!findChild(table, "rulesActiveSeatSummary").visible)
        verify(!findChild(table, "rulesPhaseScrollView").visible)
        compare(findChild(table, "rulesSnapshotStatus").text,
                "The match is complete. Review the public log or return to the room.")
        verify(table.canChat)
        verify(!table.matchUi.canRestart)
        verify(!table.playDraggedHandCard("hand-card", "Lightning Bolt"))
        result.close()

        gameSession.result = {winnerSeat: 0, matchFinished: false, reason: "rules"}
        gameSession.sideboard = sideboardProjection(true)
        gameSession.sideboarding = true
        const loader = findChild(table, "rulesSideboardLoader")
        tryVerify(() => loader.item !== null)
        verify(findChild(loader.item, "sideboardReadyButton").enabled)
        verify(!findChild(table, "rulesReturnToRoomButton").visible)
        verify(!findChild(table, "rulesBattlefieldHost").visible)
    }

    function test_destructiveConfirmationsCannotCrossGameOrConnectionBoundaries() {
        failOnWarning(/Binding loop/)
        const concede = findChild(table, "rulesConcedeConfirmation")
        const restart = findChild(table, "rulesRestartConfirmation")
        table.openConcedeConfirmation()
        tryCompare(concede, "opened", true)
        rulesSession.gameOver = true
        tryCompare(concede, "opened", false)
        rulesSession.gameId = "rules-match-2"
        rulesSession.gameOver = false
        concede.confirmed()
        compare(fakeWs.concedeCount, 0)

        table.openConcedeConfirmation()
        tryCompare(concede, "opened", true)
        rulesSession.gameId = "rules-match-2-restarted"
        tryCompare(concede, "opened", false)
        concede.confirmed()
        compare(fakeWs.concedeCount, 0)

        table.openConcedeConfirmation()
        tryCompare(concede, "opened", true)
        fakeWs.inRoom = false
        tryCompare(concede, "opened", false)
        fakeWs.inRoom = true
        concede.confirmed()
        compare(fakeWs.concedeCount, 0)

        table.matchUi.openRestartConfirmation()
        tryCompare(restart, "opened", true)
        gameSession.sideboarding = true
        tryCompare(restart, "opened", false)
        gameSession.sideboarding = false
        rulesSession.gameId = "rules-match-3"
        restart.confirmed()
        compare(fakeWs.restartCount, 0)

        table.matchUi.openRestartConfirmation()
        tryCompare(restart, "opened", true)
        rulesSession.gameId = "rules-match-4"
        tryCompare(restart, "opened", false)
        restart.confirmed()
        compare(fakeWs.restartCount, 0)

        table.matchUi.openRestartConfirmation()
        tryCompare(restart, "opened", true)
        fakeWs.inRoom = false
        tryCompare(restart, "opened", false)
        fakeWs.inRoom = true
        restart.confirmed()
        compare(fakeWs.restartCount, 0)

        table.openConcedeConfirmation()
        tryCompare(concede, "opened", true)
        const concedeButton = findChild(concede, "confirmButton")
        mouseClick(concedeButton, concedeButton.width / 2, concedeButton.height / 2)
        tryCompare(concede, "opened", false)
        compare(fakeWs.concedeCount, 1)
        concede.confirmed()
        compare(fakeWs.concedeCount, 1)
        table.matchUi.openRestartConfirmation()
        tryCompare(restart, "opened", true)
        const restartButton = findChild(restart, "confirmButton")
        mouseClick(restartButton, restartButton.width / 2, restartButton.height / 2)
        tryCompare(restart, "opened", false)
        compare(fakeWs.restartCount, 1)
        restart.confirmed()
        compare(fakeWs.restartCount, 1)
    }

    function test_authorizedSpectatorHandsAreReadOnlyAndRevocable() {
        const first = findChild(table, "rulesHandCard-hand-card")
        const viewFirst = findChild(table, "rulesViewHandButton0")
        const viewSecond = findChild(table, "rulesViewHandButton1")
        const message = findChild(table, "rulesSpectatorHandMessage")
        const owner = findChild(table, "rulesSpectatorHandOwner")
        const card = Object.assign({}, zoneCards.get(0), {
            cardId: "authorized-second-hand", zoneOwnerSeat: 1,
            ownerSeat: 1, controllerSeat: 1, name: "Opt"
        })
        zoneCards.append(card)
        try {
            const second = findChild(table, "rulesHandCard-authorized-second-hand")
            verify(first.visible && !second.visible)
            roomSession.spectatorsSeeHands = true
            verify(!viewFirst.visible && !viewSecond.visible)
            compare(table.handOwnerSeat, 0)
            roomSession.role = "spectator"
            roomSession.seatIndex = -1
            tryCompare(viewFirst, "visible", true)
            verify(!message.visible && owner.visible && first.visible)
            waitForRendering(table)
            mouseClick(viewSecond, viewSecond.width / 2, viewSecond.height / 2)
            compare(table.handOwnerSeat, 1)
            verify(!first.visible && second.visible)
            verify(owner.text.indexOf("Bob") >= 0)
            testGameTable.applySnapshot({gameId: "rules-match", seats: [
                {seat: 0, displayName: "Alice"}, {seat: 1, displayName: "Renamed Bob"}
            ]})
            tryVerify(() => owner.text.indexOf("Renamed Bob") >= 0)
            rulesSession.promptKind = "chooseAction"
            rulesSession.promptOptions = castPromptOptions
            verify(!table.canDragHandCard("hand-card"))
            verify(!table.playDraggedHandCard("hand-card", "Lightning Bolt"))
            compare(fakeWs.responseCount, 0)
            roomSession.spectatorsSeeHands = false
            compare(table.handOwnerSeat, -1)
            verify(message.visible && !first.visible && !second.visible)
            verify(!viewFirst.visible && !viewSecond.visible)
            roomSession.spectatorsSeeHands = true
            compare(table.handOwnerSeat, 0)
            fakeWs.inRoom = false
            compare(table.handOwnerSeat, -1)
            verify(!first.visible && !second.visible)
        } finally {
            zoneCards.remove(zoneCards.count - 1)
        }
    }

    function test_publicLogChatAndErrorsRemainUsableAfterGameOver() {
        const rail = findChild(table, "gameLogRail")
        const input = findChild(rail, "gameChatInput")
        const send = findChild(rail, "sendGameChatButton")
        const toggle = findChild(table, "rulesToggleGameLogButton")
        testGameTable.applySnapshot({gameId: "rules-match", seats: [], log: [
            {id: 1, kind: "chat", seat: 1, text: "Bob: <b>hello</b>"}
        ]})
        const log = findChild(rail, "gameLog")
        tryCompare(log, "count", 1)
        roomSession.role = "spectator"
        rulesSession.gameOver = true
        input.text = " Public reply "
        mouseClick(send, send.width / 2, send.height / 2)
        compare(fakeWs.chatCount, 1)
        compare(fakeWs.lastChat, "Public reply")
        compare(input.text, "")
        mouseClick(toggle, toggle.width / 2, toggle.height / 2)
        verify(!rail.visible)
        mouseClick(toggle, toggle.width / 2, toggle.height / 2)
        verify(rail.visible)
        fakeWs.lastError = "invalid_rules_response: Try again"
        verify(findChild(table, "rulesErrorBanner").visible)
        fakeWs.inRoom = false
        input.text = "Do not send"
        verify(!send.enabled)
        verify(!table.cardActions.submitChatMessage())
        compare(fakeWs.chatCount, 1)
    }
}
