// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "SideboardReview"
    when: windowShown
    property var snapshot
    property var review
    property bool motionEnabledBefore: true

    ApplicationWindow {
        id: testWindow
        width: 1200
        height: 800
        visible: true
    }
    QtObject {
        id: reviewPanel
        property var rulesSession: testRulesPrompt.session
        property var gameTableModel: ({publicReviewCards: []})
        property var roomSession: ({maxSeats: 2})
        function displayName(seat) { return seat === 0 ? "Alice" : "Bob" }
        function cardImageSource(card) {
            return card.name ? Qt.resolvedUrl("../../qml/assets/card-back.jpg") : ""
        }
    }
    Component { id: reviewComponent; SideboardBoardReview { panel: reviewPanel } }

    function init() {
        testTranslations.setLanguage("en")
        motionEnabledBefore = Theme.motionEnabled
        Theme.motionEnabled = false
        testWindow.requestActivate()
        tryCompare(testWindow, "active", true)
        testRulesPrompt.clear()
        reviewPanel.rulesSession = testRulesPrompt.session
        snapshot = {
            roomId: "REVIEW", gameId: "previous-game", turn: 7, step: "end",
            activeSeat: 0, prioritySeat: 0, players: [], stack: [],
            zones: [{zone: "battlefield", ownerSeat: 0, count: 1, cards: [
                {id: "bear", visible: true, identity: {name: "Grizzly Bears", setCode: "M10", collectorNumber: "180"}}
            ]}, {zone: "graveyard", ownerSeat: 1, count: 1, cards: [
                {id: "bolt", visible: true, identity: {name: "Lightning Bolt", setCode: "M10", collectorNumber: "146"}}
            ]}]
        }
        verify(testRulesPrompt.applySnapshot(snapshot))
        review = createTemporaryObject(reviewComponent, testWindow.contentItem)
        verify(review !== null)
        review.open()
        tryCompare(review, "opened", true)
        compare(review.inspectedCard.name, "Grizzly Bears")
    }

    function cleanup() {
        review.close()
        testRulesPrompt.clear()
        Theme.motionEnabled = motionEnabledBefore
    }

    function chooseFilter(name, index) {
        const picker = findChild(review.contentItem, name)
        verify(picker !== null)
        picker.forceActiveFocus()
        keyClick(Qt.Key_Home)
        for (let offset = 0; offset < index; ++offset)
            keyClick(Qt.Key_Down)
        compare(picker.currentIndex, index)
    }

    function selectCard(index) {
        const grid = findChild(review.contentItem, "sideboardReviewCards")
        verify(waitForPolish(testWindow))
        const card = grid.itemAtIndex(index)
        verify(card !== null)
        mouseClick(card)
    }

    function test_filtersUpdateOrClearPreview() {
        chooseFilter("sideboardReviewSeat", 2)
        compare(review.filteredCards.length, 1)
        compare(review.inspectedCard.name, "Lightning Bolt")
        chooseFilter("sideboardReviewZone", 1)
        compare(review.filteredCards.length, 0)
        compare(review.inspectedCard.name || "", "")
        compare(String(findChild(review.contentItem, "sideboardReviewPreviewImage").source), "")
    }

    function test_reconnectClearsThenRestoresPreview() {
        testRulesPrompt.clear()
        compare(review.filteredCards.length, 0)
        compare(review.inspectedCard.name || "", "")
        verify(testRulesPrompt.applySnapshot(snapshot))
        compare(review.inspectedCard.name, "Grizzly Bears")
    }

    function test_authoritativeIdentityRefreshesAndHiddenCardDisappears() {
        snapshot.zones[0].cards[0].identity.name = "Runeclaw Bear"
        verify(testRulesPrompt.applySnapshot(snapshot))
        compare(review.inspectedCard.name, "Runeclaw Bear")
        snapshot.zones[0].cards[0].faceDown = true
        verify(testRulesPrompt.applySnapshot(snapshot))
        compare(review.filteredCards.length, 1)
        compare(review.inspectedCard.name, "Lightning Bolt")
        snapshot.zones[1].cards = []
        snapshot.zones[1].count = 0
        verify(testRulesPrompt.applySnapshot(snapshot))
        compare(review.inspectedCard.name || "", "")
    }

    function test_manualSelectionUsesRefreshedSameId() {
        reviewPanel.rulesSession = null
        reviewPanel.gameTableModel = {publicReviewCards: [
            {id: "first", name: "Grizzly Bears", seat: 0, zone: "battlefield"},
            {id: "selected", name: "Lightning Bolt", seat: 1, zone: "graveyard"}
        ]}
        selectCard(1)
        compare(review.inspectedCard.id, "selected")
        reviewPanel.gameTableModel = {publicReviewCards: [
            {id: "first", name: "Grizzly Bears", seat: 0, zone: "battlefield"},
            {id: "selected", name: "Lightning Bolt", setCode: "M11", seat: 1, zone: "graveyard"}
        ]}
        compare(review.inspectedCard.id, "selected")
        compare(review.inspectedCard.setCode, "M11")
    }

    function test_reopenSelectsCurrentFirstCard() {
        selectCard(1)
        compare(review.inspectedCard.name, "Lightning Bolt")
        review.close()
        tryCompare(review, "opened", false)
        review.open()
        tryCompare(review, "opened", true)
        compare(review.inspectedCard.name, "Grizzly Bears")
    }
}
