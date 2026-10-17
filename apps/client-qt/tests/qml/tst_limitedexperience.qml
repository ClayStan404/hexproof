// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "LimitedExperience"
    when: windowShown
    TestEvent { id: doubleClickEvents }

    ApplicationWindow { id: window; width: 1200; height: 800; visible: true }
    QtObject {
        id: limitedState
        signal snapshotChanged()
        property string tournamentId: "EXPERIENCE"
        property string eventType: "set_sealed"
        property string stage: "deck_building"
        property bool deckSubmitted: false
        property bool allDecksSubmitted: false
        property var mainboardInstanceIds: []
        property var basicLands: []
        property var participants: []
        property var pool: []
        property var product: ({setCode: "TST", name: "Test booster", cardsPerPack: 15})
    }
    QtObject {
        id: connection
        property string serverUrl: "ws://localhost:57320/ws"
        property bool connected: true
        property var submittedBasics: []
        function submitLimitedDeck(name, ids, lands) { submittedBasics = lands }
    }
    QtObject {
        id: catalog
        property int imageRevision: 0
        function tableImageSource() { return "" }
        function cacheCardsIncrementally() { }
        function printings(name) {
            return [{name: name, displayName: name, setCode: "AAA", collectorNumber: "1", typeLine: "Basic Land"},
                    {name: name, displayName: name, setCode: "TST", collectorNumber: "2", typeLine: "Basic Land"}]
        }
    }
    QtObject {
        id: store
        property var draft: ({})
        property string lastError: ""
        function loadDraft() { return draft }
        function saveDraft(server, event, participant, value) { draft = JSON.parse(JSON.stringify(value)) }
        function removeDraft() { draft = ({}) }
    }
    Component {
        id: builderComponent
        LimitedDeckBuilder {
            width: 1200; height: 800
            limitedModel: limitedState
            wsModel: connection
            cardCatalogModel: catalog
            draftStore: store
            participantId: "p-1"
            animatePackOpenings: false
        }
    }
    function init() {
        store.draft = ({})
        limitedState.stage = "deck_building"
        limitedState.eventType = "set_sealed"
        limitedState.deckSubmitted = false
        limitedState.mainboardInstanceIds = []
        limitedState.basicLands = []
        limitedState.product = ({setCode: "TST", name: "Test booster", cardsPerPack: 15})
        limitedState.pool = Array.from({length: 90}, (_, index) => ({
            instanceId: "card-" + index, name: "Card " + String(index).padStart(3, "0"),
            setCode: "TST", collectorNumber: String(index), typeLine: "Creature", manaCost: "{U}", manaValue: 1
        }))
    }
    function test_poolAndMainDeckKeepTheirScrollAfterCardMoves() {
        const builder = createTemporaryObject(builderComponent, window.contentItem)
        const pool = findChild(builder, "limitedSideboardGrid")
        const main = findChild(builder, "limitedMainDeckGrid")
        verify(waitForRendering(pool))
        pool.contentY = pool.cellHeight * 2
        const before = pool.contentY
        const cardIndex = pool.columns * 2
        const tile = findChild(pool, "limitedCardTile-card-" + cardIndex)
        verify(tile)
        mouseClick(tile, tile.width / 2, tile.height / 2)
        tryVerify(() => builder.cardSelected("card-" + cardIndex))
        tryVerify(() => Math.abs(pool.contentY - before) < 1)
        builder.chooseInitialPool(true)
        wait(0)
        verify(waitForRendering(main))
        main.contentY = 200
        builder.moveToSideboard("card-20")
        wait(0)
        compare(main.contentY, 200)
        compare(builder.selectedPoolCount, 89)
    }
    function test_firstClickAfterReversingPoolWheelSelectsThePhysicalCard() {
        const builder = createTemporaryObject(builderComponent, window.contentItem)
        const pool = findChild(builder, "limitedSideboardGrid")
        verify(waitForRendering(pool))
        for (let index = 0; index < 3; ++index) {
            mouseWheel(pool, pool.width / 2, pool.height / 2, 0, -1440)
            tryVerify(() => !pool.moving)
        }
        const row = Math.floor((pool.contentY - pool.originY) / pool.cellHeight) + 1
        const firstId = pool.cards[row * pool.columns].instanceId
        const secondId = pool.cards[row * pool.columns + 1].instanceId
        const tile = findChild(pool, "limitedCardTile-" + firstId)
        verify(tile)
        verify(waitForRendering(tile))
        compare(tile.card.instanceId, firstId)
        const point = tile.mapToItem(pool, tile.width / 2, tile.height / 2)
        const scrollPosition = pool.contentY
        // QtTest's batched double-click holds one C++ call through both taps.
        // Deliver the same Press/Release/Press/DoubleClick/Release sequence in
        // phases so the first removal's queued scroll/model polish completes
        // before the next physical card receives the second press.
        verify(doubleClickEvents.mousePress(pool, point.x, point.y, Qt.LeftButton, Qt.NoModifier, 30))
        verify(doubleClickEvents.mouseRelease(pool, point.x, point.y, Qt.LeftButton, Qt.NoModifier, 30))
        tryCompare(builder, "selectedPoolCount", 1)
        verify(waitForRendering(pool))
        tryVerify(() => !builder.pendingScrollPositions && Math.abs(pool.contentY - scrollPosition) < 1)
        const secondTile = findChild(pool, "limitedCardTile-" + secondId)
        verify(secondTile)
        verify(waitForRendering(secondTile))
        const secondPoint = secondTile.mapToItem(pool, secondTile.width / 2, secondTile.height / 2)
        verify(Math.abs(secondPoint.x - point.x) < 1 && Math.abs(secondPoint.y - point.y) < 1)
        verify(doubleClickEvents.mousePress(pool, point.x, point.y, Qt.LeftButton, Qt.NoModifier, 30))
        verify(doubleClickEvents.mouseDoubleClick(pool, point.x, point.y, Qt.LeftButton, Qt.NoModifier, 30))
        verify(doubleClickEvents.mouseRelease(pool, point.x, point.y, Qt.LeftButton, Qt.NoModifier, 30))
        tryCompare(builder, "selectedPoolCount", 2)
        verify(builder.cardSelected(firstId))
        verify(builder.cardSelected(secondId))
        wait(220)
        mouseWheel(pool, pool.width / 2, pool.height / 2, 0, 1080)
        // Observe the end of the physical motion independently of moving:
        // Qt can leave that flag set after this direction change.
        wait(1000)
        const stoppedY = pool.contentY
        wait(160)
        compare(pool.contentY, stoppedY)
        verify(!pool.atYBeginning && !pool.atYEnd)
        verify(!pool.dragging && !pool.flicking)
        const nextRow = Math.floor((pool.contentY - pool.originY) / pool.cellHeight) + 1
        const nextId = pool.cards[nextRow * pool.columns].instanceId
        const next = findChild(pool, "limitedCardTile-" + nextId)
        verify(next)
        mouseClick(next, next.width / 2, next.height / 2)
        tryCompare(builder, "selectedPoolCount", 3)
        verify(builder.cardSelected(nextId))
    }
    function test_scrolledPoolClampsAtEndWithoutJumpingToBeginning() {
        const builder = createTemporaryObject(builderComponent, window.contentItem)
        const pool = findChild(builder, "limitedSideboardGrid")
        verify(waitForRendering(pool))
        pool.positionViewAtEnd()
        verify(pool.contentY > 0)
        for (let index = 89; index >= 80; --index) builder.moveToMainDeck("card-" + index)
        wait(0)
        verify(pool.contentY > 0)
        fuzzyCompare(pool.contentY - pool.originY, Math.max(0, pool.contentHeight - pool.height), 1)
    }
    function test_poolGroupingPreservesDeckOrderAndManaPlan() {
        limitedState.pool = [
            {instanceId: "a", name: "Alpha", setCode: "TST", collectorNumber: "1",
             typeLine: "Creature", manaCost: "{U}{U}{U}", manaValue: 3, colors: "U"},
            {instanceId: "b", name: "Beta", setCode: "TST", collectorNumber: "2",
             typeLine: "Creature", manaCost: "{G}", manaValue: 1, colors: "G"},
            {instanceId: "c", name: "Gamma", setCode: "TST", collectorNumber: "3",
             typeLine: "Creature", manaCost: "{U}", manaValue: 1, colors: "U"},
            {instanceId: "d", name: "Delta", setCode: "TST", collectorNumber: "4",
             typeLine: "Creature", manaCost: "{G}{G}{G}", manaValue: 3, colors: "G"}
        ]
        const builder = createTemporaryObject(builderComponent, window.contentItem)
        builder.moveToMainDeck("a")
        builder.moveToMainDeck("b")
        const deck = builder.mainDeckCards
        const plan = builder.basicLandPlan
        const main = findChild(builder, "limitedMainDeckGrid")
        const pool = findChild(builder, "limitedSideboardGrid")
        const rows = main.rows
        compare(pool.cards.map(card => card.instanceId), ["c", "d"])
        builder.groupingModeIndex = 1
        compare(pool.cards.map(card => card.instanceId), ["c", "d"])
        builder.groupingModeIndex = 3
        compare(pool.cards.map(card => card.instanceId), ["d", "c"])
        verify(builder.mainDeckCards === deck, "Gallery grouping must not rebuild the selected deck")
        verify(builder.basicLandPlan === plan, "Gallery grouping must not recalculate the mana plan")
        verify(main.rows === rows, "Gallery grouping must preserve main-deck delegates")
    }
    function test_environmentDefaultsAndExplicitPrintingSurviveReopenAndSubmission() {
        let builder = builderComponent.createObject(window.contentItem)
        for (const name of builder.basicNames) compare(builder.basicPrinting(name).setCode, "TST")
        builder.moveToMainDeck("card-0")
        builder.adjustBasic("Island", 0)
        builder.setBasicPrinting("Island", {setCode: "AAA", collectorNumber: "1"})
        compare(builder.deckListCards.find(card => card.virtualBasic).setCode, "AAA")
        builder.submit()
        compare(connection.submittedBasics, [{name: "Island", count: 39, setCode: "AAA", collectorNumber: "1"}])
        builder.destroy()
        wait(0)
        builder = createTemporaryObject(builderComponent, window.contentItem)
        compare(builder.basicPrinting("Island").setCode, "AAA")
        compare(builder.basicValue("Island"), 39)
        limitedState.mainboardInstanceIds = ["card-0"]
        limitedState.basicLands = connection.submittedBasics
        limitedState.deckSubmitted = true
        limitedState.snapshotChanged()
        verify(!builder.hasUnsubmittedChanges)
        builder.setBasicPrinting("Island", {setCode: "TST", collectorNumber: "2"})
        verify(builder.hasUnsubmittedChanges, "Printing-only edits must be submitted")
        builder.discardUnsubmittedChanges()
        compare(builder.basicPrinting("Island").setCode, "AAA")
        verify(!builder.hasUnsubmittedChanges)
    }
    function test_printingPickerChangesTheSelectedBasic() {
        const builder = createTemporaryObject(builderComponent, window.contentItem)
        verify(waitForRendering(builder))
        mouseClick(findChild(builder, "limitedBasicLandsButton"))
        const popup = findChild(builder, "limitedBasicLandsPopup")
        tryVerify(() => popup.opened)
        tryVerify(() => !!findChild(popup.contentItem, "limitedBasicLandPrinting-Island"))
        const button = findChild(popup.contentItem, "limitedBasicLandPrinting-Island")
        verify(waitForRendering(button))
        mouseClick(button)
        const picker = findChild(builder, "limitedBasicPrintingPicker")
        tryVerify(() => picker.opened)
        compare(picker.cardName, "Island")
        picker.previewPrinting = picker.options.find(card => card.setCode === "AAA")
        mouseClick(findChild(picker, "usePrintingButton"))
        tryCompare(picker, "opened", false)
        compare(builder.basicPrinting("Island").setCode, "AAA")
    }
    function test_missingEnvironmentUsesAConsistentAvailableSet() {
        limitedState.product = ({setCode: "MISSING"})
        const builder = createTemporaryObject(builderComponent, window.contentItem)
        for (const name of builder.basicNames) compare(builder.basicPrinting(name).setCode, "AAA")
    }
    function test_sealedAnimationUsesPrivatePacksOnceAndCanBeReplayed() {
        let builder = builderComponent.createObject(window.contentItem, {animatePackOpenings: true})
        let opening = findChild(builder, "limitedSealedPackOpening")
        opening.cardBackSource = ""
        opening.reducedMotion = true
        tryVerify(() => opening.opened)
        compare(opening.packs.length, 6)
        compare(opening.packs[0].cards.map(card => card.instanceId), limitedState.pool.slice(0, 15).map(card => card.instanceId))
        compare(opening.packs[5].cards.map(card => card.instanceId), limitedState.pool.slice(75).map(card => card.instanceId))
        opening.beginCurrentPack()
        opening.revealAll()
        compare(opening.revealedCount, 15)
        compare(builder.selectedPoolCount, 0)
        compare(limitedState.pool.length, 90)
        opening.close()
        verify(store.draft.sealedOpeningSeen)
        builder.destroy()
        wait(0)
        builder = createTemporaryObject(builderComponent, window.contentItem, {animatePackOpenings: true})
        opening = findChild(builder, "limitedSealedPackOpening")
        opening.cardBackSource = ""
        wait(0)
        verify(!opening.opened, "Reopening construction must not replay automatically")
        mouseClick(findChild(builder, "limitedSealedPacksButton"))
        tryVerify(() => opening.opened)
        builder.visible = false
        tryVerify(() => !opening.opened, 5000, "Leaving the builder closes its animation")
    }
    function test_disabledAnimationStillAllowsExplicitReplay() {
        const builder = createTemporaryObject(builderComponent, window.contentItem)
        const opening = findChild(builder, "limitedSealedPackOpening")
        opening.cardBackSource = ""
        wait(0)
        verify(!opening.opened)
        builder.showSealedPacks()
        tryVerify(() => opening.opened)
        opening.close()
        limitedState.pool = []
        builder.showSealedPacks()
        verify(!opening.opened, "An empty or redacted pool cannot display an opening")
    }
}
