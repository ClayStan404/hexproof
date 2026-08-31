// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"
import "../../qml/screens"

TestCase {
    name: "RulesTable"
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

        ListModel { id: emptyModel }

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
            signal promptChanged()

            property bool active: true
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
            property int promptMinCardSelections: 0
            property int promptMaxCardSelections: 0
            property int promptMinSelections: 0
            property int promptMaxSelections: 0
            property bool promptCancellable: false
            property int promptMinChoiceTotal: 0
            property int promptMaxChoiceTotal: 0
            property int promptMinNumber: 0
            property int promptMaxNumber: 0

            function zoneCount(ownerSeat, zone) {
                for (let index = 0; index < zones.count; ++index) {
                    const item = zones.get(index)
                    if (item.ownerSeat === ownerSeat && item.zone === zone)
                        return item.count
                }
                return 0
            }

            function castActionsForCard(cardId) {
                if (!promptPending || !promptSupported
                        || promptKind !== "chooseAction") {
                    return []
                }
                const actions = []
                for (let index = 0; index < promptOptions.count; ++index) {
                    const option = promptOptions.get(index)
                    if (option.kind === "cast" && option.cardId === cardId) {
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
            property string roomName: "Friday Forge"
            property string roomId: "ABCDEF"
            property string role: "player"
            property int seatIndex: 0
        }

        QtObject {
            id: fakeWs
            property var rulesSession: rulesSession
            property var roomSession: roomSession
            property int responseCount: 0
            property int concedeCount: 0
            property int lastPromptId: 0
            property string lastResponseId: ""

            function leaveRoom() {}
            function concede() { concedeCount++ }
            function respondRulesPrompt(promptId, responseId) {
                responseCount++
                lastPromptId = promptId
                lastResponseId = responseId
            }
            function respondRulesPromptWithScry(promptId, piles) {}
            function returnToRoom() {}
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
        }
    }

    function initTestCase() {
        Theme.uiScale = 1.0
    }

    function init() {
        const picker = findChild(table, "rulesCardActionPicker")
        if (picker !== null)
            picker.close()
        const concedeDialog = findChild(table, "rulesConcedeConfirmation")
        if (concedeDialog !== null)
            concedeDialog.close()
        testWindow.width = 1280
        testWindow.height = 800
        Theme.uiScale = 1.0
        rulesSession.active = true
        rulesSession.gameOver = false
        rulesSession.promptPending = true
        rulesSession.promptSupported = true
        rulesSession.promptId = 1
        rulesSession.promptKind = "diceRolled"
        rulesSession.promptTitle = "Roll for first player"
        rulesSession.promptDetail = ""
        rulesSession.promptOptions = rollPromptOptions
        players.setProperty(0, "status", "playing")
        players.setProperty(1, "status", "playing")
        fakeWs.concedeCount = 0
    }

    function test_primaryPlayAreaDoesNotCollapse() {
        const layout = findChild(table, "rulesGameLayout")
        const playArea = findChild(table, "rulesPlayArea")
        const actionRail = findChild(table, "rulesActionRail")
        const sharedRail = findChild(table, "rulesSharedZoneRail")
        const stateRail = findChild(table, "rulesStateRail")
        const battlefield = findChild(table, "rulesBattlefieldPanel")
        const handArea = findChild(table, "rulesHandArea")
        verify(layout !== null)
        verify(playArea !== null)
        verify(actionRail !== null)
        verify(sharedRail !== null)
        verify(stateRail !== null)
        verify(battlefield !== null)
        verify(handArea !== null)
        tryVerify(() => layout.width > 0)
        compare(actionRail.width, 144)
        compare(sharedRail.width, 92)
        compare(stateRail.width, 176)
        verify(playArea.width >= layout.width * 0.6,
               "play area " + playArea.width + " / layout " + layout.width)
        verify(battlefield.width >= playArea.width - 1,
               "battlefield " + battlefield.width + " / play area "
               + playArea.width)
        compare(handArea.width, playArea.width)
        verify(handArea.y > battlefield.y)
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

    function test_compactLayoutReturnsRailsToBattlefield() {
        const actionRail = findChild(table, "rulesActionRail")
        const sharedRail = findChild(table, "rulesSharedZoneRail")
        const stateRail = findChild(table, "rulesStateRail")
        const playArea = findChild(table, "rulesPlayArea")
        testWindow.width = 1000
        tryCompare(actionRail, "width", 120)
        compare(sharedRail.visible, false)
        compare(stateRail.visible, false)
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
        const title = findChild(table, "rulesPromptTitle")
        const detail = findChild(table, "rulesPromptDetail")
        const options = findChild(table, "rulesPromptOptions")
        verify(panel !== null)
        verify(title !== null)
        verify(detail !== null)
        verify(options !== null)
        tryCompare(panel, "visible", true)
        compare(title.text, "Waiting for another player")
        compare(detail.visible, true)
        compare(detail.text,
                "Forge is waiting for another player to respond.")
        compare(options.visible, false)
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

        let backFace = null
        const children = picker.contentItem.children
        for (let index = 0; index < children.length; ++index) {
            if (children[index].objectName === "rulesCardAction-action:1") {
                backFace = children[index]
                break
            }
        }
        verify(backFace !== null)
        mouseClick(backFace, backFace.width / 2, backFace.height / 2)
        compare(fakeWs.responseCount, 1)
        compare(fakeWs.lastPromptId, 10)
        compare(fakeWs.lastResponseId, "action:1")
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
}
