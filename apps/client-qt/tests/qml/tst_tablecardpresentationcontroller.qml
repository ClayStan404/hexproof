// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "TableCardPresentationController"
    width: 800
    height: 600

    QtObject {
        id: fakeCatalog
        property int imageRevision: 1
        property string language: "en"
        property int prioritizeCalls: 0
        property var prioritizedCards: []
        property bool reenterOnPrioritize: false

        function imageSource(name, setCode, collectorNumber) {
            return "image:" + name + ":" + setCode + ":" + collectorNumber
        }

        function tableImageSource(name, setCode, collectorNumber) {
            return "table:" + name + ":" + setCode + ":" + collectorNumber
        }

        function cardFaces(name, setCode, collectorNumber) {
            return [name, setCode, collectorNumber]
        }

        function prioritizeCards(cards) {
            ++prioritizeCalls
            prioritizedCards = cards.slice()
            if (!reenterOnPrioritize || prioritizeCalls >= 20)
                return
            ++imageRevision
            controller.prioritizeVisibleCards()
        }
    }

    Item {
        id: fakeTable
        property var zoneState: fakeTable
        width: 800
        height: 600
        property var cardCatalogModel: fakeCatalog
        property url cardBackSource: "back.jpg"
        property var authoritativeOwnHand: []
        property var authoritativeSeats: []
        property var stackCards: []
        property var revealedCards: []
        property var zones: ({})

        function zoneCardsForSeat(seat, zone) {
            return zones[String(seat) + ":" + zone] || []
        }
    }

    Item {
        id: sourceItem
        parent: fakeTable
        x: 100
        y: 80
        width: 80
        height: 112
    }

    Item {
        id: secondSourceItem
        parent: fakeTable
        x: 220
        y: 80
        width: 80
        height: 112
    }

    TableCardPresentationController {
        id: controller
        tableRoot: fakeTable
    }

    function init() {
        fakeCatalog.imageRevision = 1
        fakeCatalog.language = "en"
        fakeCatalog.prioritizeCalls = 0
        fakeCatalog.prioritizedCards = []
        fakeCatalog.reenterOnPrioritize = false
        fakeTable.authoritativeOwnHand = []
        fakeTable.authoritativeSeats = []
        fakeTable.stackCards = []
        fakeTable.revealedCards = []
        fakeTable.zones = ({})
        controller.reset()
    }

    function test_resolvesFacesAndTableImages() {
        const card = {"name": "Front", "setCode": "abc",
                      "collectorNumber": "7"}
        compare(controller.cardImageSource(card), "image:Front:abc:7")
        compare(controller.tableCardImageSource(card), "table:Front:abc:7")
        compare(controller.availableCardFaces(card).length, 3)
        compare(controller.tableCardImageSource({"name": "Hidden",
                                                 "faceDown": true}),
                fakeTable.cardBackSource)
    }

    function test_omitsFaceDownPlaceholderName() {
        compare(controller.tableCardPlaceholderName(
                    {"name": "Island", "faceDown": true}), "")
        compare(controller.tableCardPlaceholderName(
                    {"name": "Island"}), "Island")
        compare(controller.tableCardPlaceholderName(null), "")
        compare(controller.tableCardPlaceholderName({}), "")
    }

    function test_staleExitDoesNotHideNewerCardPreview() {
        controller.inspectCard({"id": "first", "name": "First"},
                               sourceItem)
        controller.inspectCard({"id": "second", "name": "Second"},
                               secondSourceItem)

        controller.hideCardPreview(sourceItem)
        verify(controller.hoverPreviewVisible)
        compare(controller.inspectedCard.name, "Second")

        controller.hideCardPreview(secondSourceItem)
        verify(!controller.hoverPreviewVisible)
    }

    function test_prioritizesVisibleCardsByTierAndDeduplicates() {
        fakeTable.authoritativeOwnHand = [
            {"id": "hand", "name": "Hand"},
            {"id": "duplicate", "name": "Same", "setCode": "A"}
        ]
        fakeTable.authoritativeSeats = [{"seat": 0}, {"seat": 1}]
        fakeTable.zones = ({
            "0:battlefield": [{"id": "battle", "name": "Battle"}],
            "1:battlefield": [{"id": "dup-2", "name": "Same",
                                "setCode": "A"}],
            "0:graveyard": [{"id": "grave", "name": "Grave"}],
            "1:command": [{"id": "command", "name": "Command"}]
        })
        fakeTable.stackCards = [{"id": "stack", "name": "Stack"}]
        fakeTable.revealedCards = [{
            "id": "reveal",
            "name": "Front // Back",
            "faceName": "Back"
        }]

        controller.prioritizeVisibleCards()
        compare(fakeCatalog.prioritizeCalls, 1)
        compare(fakeCatalog.prioritizedCards.length, 7)
        compare(fakeCatalog.prioritizedCards[0].name, "Hand")
        compare(fakeCatalog.prioritizedCards[2].name, "Battle")
        compare(fakeCatalog.prioritizedCards[3].name, "Stack")
        compare(fakeCatalog.prioritizedCards[4].name, "Back")

        controller.prioritizeVisibleCards()
        compare(fakeCatalog.prioritizeCalls, 1)
        fakeCatalog.imageRevision = 2
        controller.prioritizeVisibleCards()
        compare(fakeCatalog.prioritizeCalls, 1)
    }

    function test_prioritizeDoesNotRecurseWhenCatalogBumpsImageRevision() {
        fakeTable.authoritativeOwnHand = [
            {"id": "hand", "name": "Island"}
        ]
        fakeCatalog.reenterOnPrioritize = true

        controller.prioritizeVisibleCards()
        compare(fakeCatalog.prioritizeCalls, 1)
    }

    function test_positionsAndHidesHoverPreview() {
        controller.inspectCard({"name": "Preview"}, sourceItem)
        verify(controller.hoverPreviewVisible)
        compare(controller.inspectedCard.name, "Preview")
        verify(controller.hoverPreviewX >= 0)
        verify(controller.hoverPreviewY >= 0)
        controller.hideCardPreview()
        verify(!controller.hoverPreviewVisible)
    }
}
