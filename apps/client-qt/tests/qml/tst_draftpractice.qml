// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"
import "../../qml/components"

TestCase {
    name: "DraftPractice"
    when: windowShown
    ApplicationWindow {
        id: window
        width: 1280
        height: 800
        visible: true
        function popScreen() { }
    }
    QtObject {
        id: testCatalog
        signal catalogChanged()
        property int imageRevision: 0
        property var sets: [{id:"TST", name:"Test set", productId:"test", authentic:false}]
        function limitedSets() { return sets }
        function limitedProduct(id) { return ({name:"Test set", cardsPerPack:14, productType:"approximate"}) }
        function enrichLimitedCards(cards) { return cards }
        function cacheCardsIncrementally(cards) { }
        function tableImageSource() { return "" }
    }
    QtObject {
        id: testLibrary
        signal countChanged()
        property var cubes: [{deckId:"cube", deckName:"Small Cube", mainCount:90}]
        function matchDecks(format, allowMissingArt) { return cubes }
        function cubeProduct(id) { return ({name:"Small Cube", productType:"cube"}) }
    }
    Component {
        id: pageComponent
        DraftPractice {
            simulator: testDraftSimulator
            catalog: testCatalog
            library: testLibrary
        }
    }
    function init() {
        testDraftSimulator.reset()
        testCatalog.sets = [{id:"TST", name:"Test set", productId:"test", authentic:false}]
        Theme.uiScale = 1
        window.width = 1280
        window.height = 800
    }
    function cleanup() { Theme.uiScale = 1 }
    function page() {
        const item = createTemporaryObject(pageComponent, window.contentItem,
            {width: window.width, height: window.height})
        verify(item)
        return item
    }
    function test_setupRequiresEnoughCubeCardsAndInstalledProduct() {
        const view = page()
        const start = findChild(view, "startDraftPracticeButton")
        verify(start.enabled)
        findChild(view, "draftPracticeSourceSelector").currentIndex = 1
        verify(!start.enabled)
        findChild(view, "draftPracticeSeatSelector").currentIndex = 0
        verify(start.enabled)
        start.clicked()
        compare(testDraftSimulator.state.participants.length, 2)
        compare(testDraftSimulator.state.eventType, "cube_draft")
        compare(testDraftSimulator.state.currentPack.length, 15)
    }
    function test_missingSetDisablesStart() {
        testCatalog.sets = []
        const view = page()
        verify(!findChild(view, "startDraftPracticeButton").enabled)
    }
    function test_navigationKeepsPendingPackAndPicks() {
        let view = pageComponent.createObject(window.contentItem, {width:1280, height:800})
        verify(view)
        findChild(view, "startDraftPracticeButton").clicked()
        const draft = findChild(view, "draftPracticeDraftView")
        draft.confirmCard(testDraftSimulator.state.currentPack[0].instanceId)
        const nextId = testDraftSimulator.state.currentPack[0].instanceId
        waitForRendering(view)
        view.destroy()
        wait(0)
        view = page()
        compare(testDraftSimulator.state.pool.length, 1)
        compare(testDraftSimulator.state.currentPack[0].instanceId, nextId)
        compare(findChild(view, "draftPracticeDraftView").pendingPickId, "")
    }
    function test_setupFitsScaledWindow() {
        Theme.uiScale = 1.8
        window.width = 900
        window.height = 620
        const view = page()
        const scroll = findChild(view, "draftPracticeSetup")
        const button = findChild(view, "startDraftPracticeButton")
        scroll.contentItem.contentY = Math.max(0, scroll.contentHeight - scroll.height)
        waitForRendering(view)
        const point = button.mapToItem(scroll, 0, 0)
        verify(point.y >= 0 && point.y + button.height <= scroll.height + 1)
        mouseClick(button)
        verify(testDraftSimulator.state.active)
    }
    function test_fullPracticeReusesPickAndConstructionControls() {
        let view = pageComponent.createObject(window.contentItem, {width:1280, height:800})
        verify(view)
        findChild(view, "startDraftPracticeButton").clicked()
        for (let pick = 0; pick < 42; ++pick) {
            waitForRendering(view)
            const draft = findChild(view, "draftPracticeDraftView")
            verify(draft)
            const id = testDraftSimulator.state.currentPack[0].instanceId
            draft.selectCard(id)
            verify(draft.canConfirm)
            draft.confirmPick()
            compare(testDraftSimulator.state.pool.length, pick + 1)
            if (pick < 41) compare(draft.pendingPickId, "")
        }
        compare(testDraftSimulator.state.stage, "deck_building")
        waitForRendering(view)
        let builder = findChild(view, "draftPracticeDeckBuilder")
        verify(builder)
        builder.chooseInitialPool(false)
        for (let index = 0; index < 23; ++index)
            builder.moveToMainDeck(testDraftSimulator.state.pool[index].instanceId)
        builder.updateAutoBasics()
        compare(builder.selectedCount, 40)
        const save = findChild(view, "limitedSubmitDeckButton")
        compare(save.text, "Save to deck library")
        save.clicked()
        verify(testDraftSimulator.state.deckSubmitted)
        verify(!save.enabled)
        compare(findChild(view, "limitedDeckSubmissionStatus").text, "Saved to deck library")
        builder.moveToSideboard(testDraftSimulator.state.pool[0].instanceId)
        builder.adjustBasic("Island", 1)
        verify(save.enabled)
        compare(save.text, "Save new copy")
        waitForRendering(view)
        view.destroy()
        wait(0)
        view = page()
        builder = findChild(view, "draftPracticeDeckBuilder")
        compare(builder.selectedPoolCount, 22)
        verify(builder.hasUnsubmittedChanges)
        const restart = findChild(view, "restartDraftPracticeDialog")
        findChild(view, "newDraftPracticeButton").clicked()
        verify(restart.opened)
        restart.close()
        verify(testDraftSimulator.state.active)
        findChild(view, "newDraftPracticeButton").clicked()
        restart.confirmed()
        restart.close()
        verify(!testDraftSimulator.state.active)
        findChild(view, "startDraftPracticeButton").clicked()
        for (let pick = 0; pick < 42; ++pick) {
            waitForRendering(view)
            findChild(view, "draftPracticeDraftView").confirmCard(testDraftSimulator.state.currentPack[0].instanceId)
        }
        builder = findChild(view, "draftPracticeDeckBuilder")
        verify(!builder.initialPoolChosen)
        compare(builder.selectedPoolCount, 0)
        verify(!testDraftSimulator.state.deckSubmitted)
    }
}
