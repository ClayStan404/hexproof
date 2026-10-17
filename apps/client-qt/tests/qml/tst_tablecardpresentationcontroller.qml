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
        property var faceRequests: []
        property var frontFaces: []
        property bool fullArtAvailable: true
        property var artRequests: []

        function imageSource(name, setCode, collectorNumber) {
            artRequests.push(["full", name, setCode, collectorNumber])
            return fullArtAvailable ? "image:" + name + ":" + setCode + ":" + collectorNumber : ""
        }

        function tableImageSource(name, setCode, collectorNumber) {
            artRequests.push(["table", name, setCode, collectorNumber])
            return "table:" + name + ":" + setCode + ":" + collectorNumber
        }

        function cardFaces(name, setCode, collectorNumber) {
            faceRequests.push([name, setCode, collectorNumber])
            return name === "Front" ? frontFaces : []
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
        property var gameTableModel: null
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

    // Mirrors CardCatalog's contract that a language change also bumps
    // imageRevision, so table image bindings re-resolve.
    QtObject {
        id: fakeRevisionCatalog
        property int imageRevision: 1
        property string language: "en"

        function tableImageSource(name, setCode, collectorNumber) {
            return "table:" + language + ":" + name + ":" + imageRevision
        }
    }

    Item {
        id: revisionTable
        property var cardCatalogModel: fakeRevisionCatalog
        property url cardBackSource: "back.jpg"
    }

    TableCardPresentationController {
        id: revisionController
        tableRoot: revisionTable
    }

    property var revisionCard: ({"name": "Front", "setCode": "abc",
                                 "collectorNumber": "7"})
    property string revisionBoundSource: revisionController.tableCardImageSource(
                                             revisionCard)

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
        fakeTable.gameTableModel = null
        testGameTable.clear()
        fakeCatalog.imageRevision = 1
        fakeCatalog.language = "en"
        fakeCatalog.prioritizeCalls = 0
        fakeCatalog.prioritizedCards = []
        fakeCatalog.reenterOnPrioritize = false
        fakeCatalog.faceRequests = []
        fakeCatalog.frontFaces = []
        fakeCatalog.fullArtAvailable = true
        fakeCatalog.artRequests = []
        fakeRevisionCatalog.imageRevision = 1
        fakeRevisionCatalog.language = "en"
        fakeTable.authoritativeOwnHand = []
        fakeTable.authoritativeSeats = []
        fakeTable.stackCards = []
        fakeTable.revealedCards = []
        fakeTable.zones = ({})
        controller.reset()
    }

    function test_boundTableSourceRefreshesOnImageRevision() {
        compare(revisionBoundSource, "table:en:Front:1")

        fakeRevisionCatalog.imageRevision = 2
        compare(revisionBoundSource, "table:en:Front:2")
    }

    function test_tableSourceTracksImageRevisionSentinel() {
        fakeRevisionCatalog.imageRevision = -1
        compare(revisionController.tableCardImageSource(revisionCard), "")

        fakeRevisionCatalog.imageRevision = 3
        compare(revisionController.tableCardImageSource(revisionCard),
                "table:en:Front:3")
    }

    function test_resolvesFacesAndTableImages() {
        fakeCatalog.frontFaces = faces()
        const card = {"name": "Front", "setCode": "abc",
                      "collectorNumber": "7"}
        compare(controller.cardImageSource(card), "image:Front:abc:7")
        compare(controller.tableCardImageSource(card), "table:Front:abc:7")
        compare(controller.availableCardFaces(card), faces())
        compare(fakeCatalog.faceRequests[fakeCatalog.faceRequests.length - 1], ["Front", "abc", "7"])
        compare(controller.tableCardImageSource({"name": "Hidden",
                                                 "faceDown": true}),
                fakeTable.cardBackSource)
    }
    function faces() {
        return [{name:"Front", faceName:"", displayName:"Front", setCode:"ABC", collectorNumber:"7"},
            {name:"Back", faceName:"Back", displayName:"Back", setCode:"ABC", collectorNumber:"7"}]
    }
    function test_multifaceDepartureAllowsPointerToReachPreview() {
        fakeCatalog.frontFaces = faces()
        const card = {id:"two-faced", name:"Front", setCode:"ABC", collectorNumber:"7"}
        controller.inspectCard(card, sourceItem)
        verify(controller.facePreview.canSwitch)
        controller.facePreview.nextFace()
        compare(controller.facePreview.viewedName, "Back")
        compare(card.name, "Front")
        compare(card.faceName, undefined)
        controller.hideCardPreview(sourceItem)
        wait(140)
        verify(controller.hoverPreviewVisible)
        controller.previewHeld = true
        wait(380)
        verify(controller.hoverPreviewVisible)
        controller.previewHeld = false
        tryCompare(controller, "hoverPreviewVisible", false)
        compare(controller.facePreview.faceIndex, 0)
    }
    function test_fullArtHasPriorityAndTableFallbackNeverLeaksToOtherFace() {
        fakeCatalog.frontFaces = faces()
        const card = {id:"two-faced", name:"Front", setCode:"ABC", collectorNumber:"7"}
        controller.inspectCard(card, sourceItem)
        compare(controller.facePreview.imageSource, "image:Front:ABC:7")
        fakeCatalog.fullArtAvailable = false
        compare(controller.facePreview.imageSource, "table:Front:ABC:7")
        controller.facePreview.nextFace()
        compare(controller.facePreview.viewedName, "Back")
        compare(controller.facePreview.imageSource, "", "A missing back cannot reuse the original table image")
        controller.facePreview.nextFace()
        compare(controller.facePreview.imageSource, "table:Front:ABC:7")
    }
    function test_tableFallbackCannotLookUpHiddenOrInactiveIdentity() {
        controller.hideCardPreview()
        fakeCatalog.artRequests.splice(0)
        controller.inspectedCard = {name:"Front", setCode:"ABC", collectorNumber:"7"}
        compare(controller.facePreview.fallbackImageSource, "")
        compare(controller.facePreview.imageSource, "")
        compare(fakeCatalog.artRequests.length, 0)
        for (const hidden of [{faceDown:true}, {visibleIdentity:false}, {visible:false}]) {
            controller.inspectCard(Object.assign({name:"Front", setCode:"ABC", collectorNumber:"7"}, hidden), sourceItem)
            compare(controller.facePreview.fallbackImageSource, "")
            compare(controller.facePreview.imageSource, "")
            compare(fakeCatalog.artRequests.length, 0)
            controller.hideCardPreview()
        }
    }
    function test_multifaceForceHideDoesNotWaitForDeparture() {
        fakeCatalog.frontFaces = faces()
        controller.inspectCard({name:"Front"}, sourceItem)
        controller.hideCardPreview(sourceItem)
        verify(controller.hoverPreviewVisible)
        controller.hideCardPreview()
        verify(!controller.hoverPreviewVisible)
        compare(controller.inspectedSourceItem, null)
    }
    function test_faceDownPreviewNeverResolvesFaces() {
        fakeCatalog.frontFaces = faces()
        controller.inspectCard({name:"Front", faceDown:true}, sourceItem)
        compare(controller.facePreview.faces.length, 0)
        compare(controller.facePreview.imageSource, "")
        compare(fakeCatalog.faceRequests.length, 0)
        controller.hideCardPreview(sourceItem)
        verify(!controller.hoverPreviewVisible)
    }
    function test_currentTypedProjectionUpdatesFaceAndClosesHiddenIdentity() {
        fakeCatalog.frontFaces = faces()
        fakeTable.gameTableModel = testGameTable
        const card = {id:"public-dfc", name:"Front", setCode:"ABC", collectorNumber:"7"}
        testGameTable.applySnapshot({seats:[{seat:0, battlefield:[card]}]})
        controller.inspectCard(testGameTable.cardData(card.id), sourceItem)
        controller.facePreview.nextFace()
        compare(controller.facePreview.viewedName, "Back")
        card.faceName = "Back"
        testGameTable.applySnapshot({seats:[{seat:0, battlefield:[card]}]})
        compare(controller.inspectedCard.faceName, "Back")
        compare(controller.facePreview.initialFaceIndex, 1)
        fakeCatalog.faceRequests.splice(0)
        card.faceDown = true
        testGameTable.applySnapshot({seats:[{seat:0, battlefield:[card]}]})
        verify(!controller.hoverPreviewVisible)
        compare(Object.keys(controller.inspectedCard).length, 0)
        compare(fakeCatalog.faceRequests.length, 0)
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
