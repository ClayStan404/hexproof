// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "RulesBattlefieldLayout"
    when: windowShown
    property var snapshot

    Component {
        id: lateBattlefieldComponent
        RulesBattlefieldView {
            width: 1000
            height: 900
            tableController: controller
        }
    }

    ApplicationWindow {
        id: testWindow
        width: 1000
        height: 900
        visible: true

        QtObject {
            id: catalog
            property int imageRevision: 0
            property var requestedTypes: []
            function tableImageSource() { return "" }
            function cardTypeLine(name, setCode, collectorNumber) {
                requestedTypes.push(name)
                return name === "Plains" ? "Basic Land — Plains" : "Artifact"
            }
        }

        QtObject {
            id: controller
            property var rulesSession: testRulesPrompt.session
            property var cardCatalogModel: catalog
            property url cardBackSource: ""
            property int localSeat: 0
            property int handOwnerSeat: 0
            property bool canViewSpectatorHands: false
            property real battlefieldCardWidth: 80
            property real battlefieldCardHeight: 112
            property string inspected: ""
            property int handDrops: 0
            function zoneCount(seat, zone) { return rulesSession.zoneCount(seat, zone) }
            function zoneLabel(zone) { return zone }
            function cardImage() { return "" }
            function openCardDetails(cardId) { inspected = cardId }
            function playDraggedHandCardSource(source) { handDrops++; return false }
        }

        RulesBattlefieldView {
            id: battlefield
            anchors.fill: parent
            tableController: controller
        }
    }

    function permanent(id, name, seat, power) {
        return {id: id, visible: true, identity: {name: name}, ownerSeat: seat,
                controllerSeat: seat, power: power || "", toughness: power || ""}
    }

    function slot(seat, id) {
        return findChild(battlefield, "rulesBattlefieldPosition-" + seat + "-" + id)
    }

    function surface(seat, id) {
        return findChild(battlefield, "rulesBattlefieldCard-" + seat + "-" + id)
    }

    function apply() {
        verify(testRulesPrompt.applySnapshot(snapshot))
        wait(20)
    }

    function init() {
        Theme.uiScale = 1
        testTranslations.setLanguage("en")
        testWindow.width = 1000
        testWindow.height = 900
        controller.localSeat = 0
        controller.inspected = ""
        controller.handDrops = 0
        catalog.requestedTypes = []
        testRulesPrompt.clear()
        snapshot = {
            roomId: "LAYOUT", gameId: "layout-game", turn: 2, step: "main1",
            activeSeat: 0, prioritySeat: 0,
            players: [
                {seat: 0, name: "Alice", life: 20, status: "playing"},
                {seat: 1, name: "Bob", life: 20, status: "playing"}
            ],
            zones: [
                {zone: "battlefield", ownerSeat: 0, count: 3, cards: [
                    permanent("own-land", "Plains", 0),
                    permanent("own-creature", "Bear", 0, "2"),
                    permanent("own-other", "Relic", 0)
                ]},
                {zone: "battlefield", ownerSeat: 1, count: 2, cards: [
                    permanent("opponent-land", "Plains", 1),
                    permanent("opponent-creature", "Bear", 1, "2")
                ]}
            ], stack: []
        }
        apply()
        tryVerify(() => slot(0, "own-land").y > 0)
    }

    function cleanup() {
        testRulesPrompt.clear()
        Theme.uiScale = 1
    }

    function test_creaturesFaceCombatAndOtherPermanentsHaveTheirOwnGroup() {
        verify(slot(0, "own-creature").y < slot(0, "own-land").y)
        verify(slot(1, "opponent-creature").y > slot(1, "opponent-land").y)
        compare(slot(0, "own-land").y, slot(0, "own-other").y)
        verify(slot(0, "own-other").x > slot(0, "own-land").x)
        verify(findChild(battlefield, "rulesBattlefieldGroup-0-creature"))
        verify(findChild(battlefield, "rulesBattlefieldGroup-0-land"))
        verify(findChild(battlefield, "rulesBattlefieldGroup-0-other"))
        const viewport = findChild(battlefield, "rulesBattlefieldViewport1")
        const dock = findChild(battlefield, "rulesOpponentZoneTile-1-library").parent.parent
        verify(viewport.y + viewport.height <= dock.y,
               "The opponent zone dock has reserved space below the cards")
    }

    function test_populatedModelsArrangeEveryLaneWhenTheViewIsCreated() {
        const lateView = createTemporaryObject(lateBattlefieldComponent, testWindow.contentItem)
        verify(lateView)
        tryVerify(() => {
            const own = findChild(lateView, "rulesBattlefieldLane0")
            const opponent = findChild(lateView, "rulesBattlefieldLane1")
            return own.arrangement.positions["own-land"] !== undefined
                && own.arrangement.positions["own-creature"] !== undefined
                && opponent.arrangement.positions["opponent-land"] !== undefined
                && opponent.arrangement.positions["opponent-creature"] !== undefined
        })
        const own = findChild(lateView, "rulesBattlefieldLane0")
        const opponent = findChild(lateView, "rulesBattlefieldLane1")
        verify(own.arrangement.positions["own-creature"].y < own.arrangement.positions["own-land"].y)
        verify(opponent.arrangement.positions["opponent-creature"].y > opponent.arrangement.positions["opponent-land"].y)
        verify(own.arrangedCards.every(card => card.cardId && card.category))
        verify(opponent.arrangedCards.every(card => card.cardId && card.category))
    }

    function test_dragPersistsAcrossSnapshotsAndResizesWithoutSubmittingRules() {
        let card = surface(0, "own-land")
        const before = slot(0, "own-land").x
        const viewport = findChild(battlefield, "rulesBattlefieldViewport0")
        const beforeViewportHeight = viewport.height
        mouseDrag(card, card.width / 2, card.height / 2, 180, -40)
        tryVerify(() => slot(0, "own-land").x > before + 80)
        verify(battlefield.layoutState.hasCustomPositions)
        compare(controller.inspected, "")
        compare(controller.handDrops, 0)
        // Settle the completed gesture before testing a snapshot-only update.
        waitForRendering(battlefield)
        compare(viewport.height, beforeViewportHeight,
                "Showing Auto arrange must not move the just-placed card")
        const movedX = slot(0, "own-land").x
        const movedY = slot(0, "own-land").y
        snapshot.zones[0].cards[0].tapped = true
        apply()
        compare(slot(0, "own-land").x, movedX)
        compare(slot(0, "own-land").y, movedY)
        compare(surface(0, "own-land").rotation, 90)
        snapshot.prioritySeat = 1
        apply()
        compare(findChild(battlefield, "rulesBattlefieldViewport0").height, beforeViewportHeight)
        compare(slot(0, "own-land").y, movedY)
        const item = slot(0, "own-land")
        testWindow.width = 580
        tryVerify(() => item.x + item.width <= item.parent.width + 1)
        verify(item.y >= 0 && item.y + item.height <= item.parent.height + 1)
        const reset = findChild(battlefield, "rulesAutoArrange0")
        verify(reset.visible)
        mouseClick(reset)
        tryCompare(battlefield.layoutState, "hasCustomPositions", false)
        compare(slot(0, "own-land").x, 0)
        card = surface(0, "own-creature")
        mouseClick(card)
        compare(controller.inspected, "own-creature")
    }

    function test_sparseRearGroupsStayAdjacentOnWideBattlefields() {
        const cards = [
            {cardId: "land-0", category: "land"},
            {cardId: "land-1", category: "land"},
            {cardId: "land-2", category: "land"},
            {cardId: "other-0", category: "other"},
            {cardId: "other-1", category: "other"}
        ]
        const footprint = 112
        const gap = 8
        const wide = battlefield.layoutState.arrange(cards, 1854, 450, footprint, gap, true)
        compare(wide.positions["other-0"].x - wide.positions["land-2"].x,
                footprint + gap)
        compare(wide.positions["other-0"].y, wide.positions["land-2"].y)
        compare(wide.contentHeight, 450)

        const narrow = battlefield.layoutState.arrange(cards, 400, 200, footprint, gap, true)
        verify(narrow.contentHeight > 200)
        compare(narrow.positions["other-0"].x, 2 * (footprint + gap))
        verify(narrow.positions["land-2"].y > narrow.positions["land-0"].y)
        cards.forEach(card => {
            const position = narrow.positions[card.cardId]
            verify(position.x >= 0 && position.x + footprint <= 400)
            verify(position.y >= 0 && position.y + footprint <= narrow.contentHeight)
        })
    }

    function test_releasedOverlappingCardStaysAboveOtherCardsAfterSnapshots() {
        const dragged = surface(0, "own-land")
        const destination = slot(0, "own-other")
        const start = slot(0, "own-land")
        const press = dragged.mapToItem(battlefield, dragged.width / 2, dragged.height / 2)
        mouseDrag(battlefield, press.x, press.y,
                  destination.x - start.x, destination.y - start.y)
        tryVerify(() => slot(0, "own-land").z > slot(0, "own-other").z)
        compare(controller.inspected, "")
        const top = surface(0, "own-land")
        const covered = surface(0, "own-other")
        const overlap = top.mapToItem(covered, top.width / 2, top.height / 2)
        verify(overlap.x > 0 && overlap.x < covered.width
               && overlap.y > 0 && overlap.y < covered.height,
               "The released card covers the other permanent: "
               + JSON.stringify({x: overlap.x, y: overlap.y, width: covered.width,
                                 height: covered.height, movedX: slot(0, "own-land").x,
                                 targetX: slot(0, "own-other").x}))
        mouseClick(top)
        compare(controller.inspected, "own-land")
        const order = slot(0, "own-land").z
        apply()
        compare(slot(0, "own-land").z, order)
        verify(slot(0, "own-land").z > slot(0, "own-other").z)
        controller.inspected = ""
        mouseClick(surface(0, "own-land"))
        compare(controller.inspected, "own-land")

        const creature = surface(0, "own-creature")
        const creatureSlot = slot(0, "own-creature")
        const previousTop = slot(0, "own-land")
        const creaturePress = creature.mapToItem(battlefield, creature.width / 2, creature.height / 2)
        mouseDrag(battlefield, creaturePress.x, creaturePress.y,
                  previousTop.x - creatureSlot.x, previousTop.y - creatureSlot.y)
        tryVerify(() => slot(0, "own-creature").z > slot(0, "own-land").z)
        battlefield.layoutState.reset(0)
        compare(slot(0, "own-creature").z, 1)
        compare(slot(0, "own-land").z, 1)
        snapshot.gameId = "next-game"
        apply()
        compare(battlefield.layoutState.latestOrder, 0)
    }

    function test_shortLanesKeepModestFrontAndRearRowsVisible() {
        testWindow.width = 640
        testWindow.height = 630
        for (let seat = 0; seat < 2; ++seat) {
            snapshot.zones[seat].cards = []
            for (let index = 0; index < 3; ++index) {
                snapshot.zones[seat].cards.push(permanent("land-" + seat + "-" + index,
                    "Plains", seat))
                snapshot.zones[seat].cards.push(permanent("creature-" + seat + "-" + index,
                    "Bear", seat, "2"))
            }
            snapshot.zones[seat].count = 6
        }
        snapshot.players[1].counters = [{name: "ENERGY", value: 3}]
        apply()
        for (let seat = 0; seat < 2; ++seat) {
            const viewport = findChild(battlefield, "rulesBattlefieldViewport" + seat)
            verify(viewport.contentHeight <= viewport.height + 1,
                   "A modest battlefield needs no scrolling in a short lane")
            for (let index = 0; index < 3; ++index) {
                for (const group of ["land", "creature"]) {
                    const card = surface(seat, group + "-" + seat + "-" + index)
                    const point = card.mapToItem(viewport, 0, 0)
                    verify(card.height >= 88 && card.height <= 112)
                    verify(point.x >= 0 && point.x + card.width <= viewport.width + 1)
                    verify(point.y >= 0 && point.y + card.height <= viewport.height + 1,
                           "Both rows are fully visible: seat " + seat + " " + group)
                }
            }
        }
        const dock = findChild(battlefield, "rulesOpponentZoneTile-1-library").parent.parent
        verify(dock.compact)
        const counter = findChild(battlefield, "rulesPlayerCounters1")
        const status = findChild(battlefield, "rulesBattlefieldPlayerStatus1")
        verify(counter.x + counter.width <= dock.x)
        verify(status.x + status.width <= dock.x)
    }

    function test_veryShortOpponentLaneStartsAtCombatRow() {
        testWindow.width = 640
        testWindow.height = 400
        apply()
        const viewport = findChild(battlefield, "rulesBattlefieldViewport1")
        verify(viewport.contentHeight > viewport.height)
        verify(viewport.contentY > 0)
        const card = surface(1, "opponent-creature")
        const point = card.mapToItem(viewport, 0, 0)
        verify(point.y >= 0 && point.y + card.height <= viewport.height + 1)
    }

    function test_departedObjectsControlChangesAndNewGamesForgetCustomPositions() {
        const state = battlefield.layoutState
        state.remember(0, "own-land", 150, 40, 800, 250)
        snapshot.zones[0].cards[0].controllerSeat = 1
        apply()
        compare(state.hasCustomPositions, false)
        state.remember(1, "own-land", 150, 40, 800, 250)
        snapshot.zones[0].cards.shift()
        snapshot.zones[0].count--
        apply()
        compare(state.hasCustomPositions, false)
        state.remember(0, "own-creature", 150, 40, 800, 250)
        snapshot.gameId = "next-game"
        apply()
        compare(state.hasCustomPositions, false)
    }

    function test_faceDownCardsNeverUsePrivateTypeMetadata() {
        const hidden = permanent("hidden", "Secret Plains", 0)
        hidden.visible = false
        hidden.faceDown = true
        snapshot.zones[0].cards.push(hidden)
        snapshot.zones[0].count++
        apply()
        compare(slot(0, "hidden").category, "other")
        verify(!catalog.requestedTypes.includes("Secret Plains"))
        hidden.power = "2"
        hidden.toughness = "2"
        apply()
        compare(slot(0, "hidden").category, "creature")
        verify(!catalog.requestedTypes.includes("Secret Plains"))
        snapshot.zones[0].cards[0].power = "3"
        snapshot.zones[0].cards[0].toughness = "3"
        apply()
        compare(slot(0, "own-land").category, "creature")
    }

    function test_multipleSeatsMirrorRowsAndOverflowRemainsScrollable() {
        snapshot.players.push({seat: 2, name: "Carol", life: 20, status: "playing"})
        snapshot.players.push({seat: 3, name: "Dan", life: 20, status: "playing"})
        snapshot.zones.push({zone: "battlefield", ownerSeat: 3, count: 2, cards: [
            permanent("third-land", "Plains", 3), permanent("third-creature", "Bear", 3, "2")
        ]})
        for (let index = 0; index < 30; ++index)
            snapshot.zones[0].cards.push(permanent("land-" + index, "Plains", 0))
        snapshot.zones[0].count += 30
        apply()
        verify(slot(3, "third-creature").y < slot(3, "third-land").y)
        const viewport = findChild(battlefield, "rulesBattlefieldViewport0")
        verify(viewport.contentHeight > viewport.height)
        mouseWheel(viewport, viewport.width - 20, viewport.height / 2, 0, -480)
        tryVerify(() => viewport.contentY > 0, 1000,
                  "Overflowing permanents remain reachable with the mouse wheel")
        for (let index = 0; index < 30; ++index) {
            const card = slot(0, "land-" + index)
            verify(card.x >= 0 && card.x + card.width <= viewport.width + 1)
            verify(card.y >= 0 && card.y + card.height <= viewport.contentHeight + 1)
        }
    }
}
