// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "TableEditorPopups"
    width: 900
    height: 700

    QtObject {
        id: fakeCatalog
        property bool busy: false
        property string status: ""
        property bool tokenCatalogInstalled: true
        property bool tokenSearching: false
        property var tokenSearchResults: []
        property int imageRevision: 1
        property int prioritizeCalls: 0
        property var prioritizedCards: []
        function imageSource() { return "" }
        function matchesCardQuery() { return true }
        function cacheCards() {}
        function prioritizeCards(cards) {
            ++prioritizeCalls
            prioritizedCards = cards.slice()
        }
        function cacheToken() {}
        function downloadTokenCatalog() {}
        function searchTokens() {}
        function tokenImageSource() { return "" }
    }

    QtObject {
        id: fakeWs
        property int seatIndex: 0
        property int drawCalls: 0
        property int drawCount: 0
        property int dumpCalls: 0
        property int dumpSeat: -1
        property int dumpTopCount: -1
        property int moveLibraryCalls: 0
        property string movedDestination: ""
        property int renameCalls: 0
        property int tokenCalls: 0
        function searchLibraryCards() {}
        function resolveLibraryViewAssignments() {}
        function drawCards(value) { ++drawCalls; drawCount = value }
        function dumpLibrary(seat, topCount) {
            ++dumpCalls
            dumpSeat = seat
            dumpTopCount = topCount
        }
        function moveLibraryCards(value, destination) {
            ++moveLibraryCalls
            movedDestination = destination
        }
        function renameCounter() { ++renameCalls }
        function setCardCounter() {}
        function createToken() { ++tokenCalls }
        function shuffleLibrary() {}
    }

    QtObject {
        id: fakeRoomSession
        property int seatIndex: fakeWs.seatIndex
    }

    QtObject {
        id: fakeMoves
        property int faceCalls: 0
        property int battlefieldLibraryCalls: 0
        property int handLibraryCalls: 0
        function movePublicZoneCard() {}
        function movePublicZoneCards() {}
        function smartBattlefieldPosition() { return {"x": 0.5, "y": 0.58} }
        function smartBattlefieldAnchor() { return {"x": 0, "y": 0.05} }
        function finishCardFaceSelection() { ++faceCalls }
        function moveSelectedBattlefieldToLibrary() {
            ++battlefieldLibraryCalls
        }
        function moveSelectedHandToLibrary() { ++handLibraryCalls }
    }

    QtObject {
        id: fakeTransient
        property int clearCalls: 0
        function clearLibraryMoveDestination() { ++clearCalls }
    }

    QtObject {
        id: fakeDeckLibrary
        property var activeMatchTokens: [
            {"name": "Goblin", "displayName": "地精",
             "typeLine": "Token Creature — Goblin",
             "setCode": "TNEO", "collectorNumber": "12"}
        ]
    }

    Item {
        id: fakeTable
        property var wsModel: fakeWs
        property var roomSession: fakeRoomSession
        property var cardCatalogModel: fakeCatalog
        property var cardMoveCommands: fakeMoves
        property var transientState: fakeTransient
        property var deckLibraryModel: fakeDeckLibrary
        property var zoneState: fakeTable
        property var gameValues: fakeTable
        property var ownSeatData: ({"libraryCount": 20})
        property string libraryMoveDestination: "graveyard"
        property string selectedCounterKey: "energy"
        property string selectedBattlefieldCardId: "card-1"
        property bool canAct: true
        property int lifeValue: 0
        property int counterValue: 0
        function zoneCardsForSeat() { return [] }
        function setLife(value) { lifeValue = value }
        function setCounter(key, value) { counterValue = value }
    }

    TableEditorPopups {
        id: editors
        tableController: fakeTable
    }

    LandPlayPopup {
        id: landPlayPopup
        cardCatalogModel: fakeCatalog
    }

    function init() {
        fakeCatalog.tokenSearchResults = []
        fakeCatalog.prioritizeCalls = 0
        fakeCatalog.prioritizedCards = []
        fakeWs.drawCalls = 0
        fakeWs.drawCount = 0
        fakeWs.dumpCalls = 0
        fakeWs.dumpSeat = -1
        fakeWs.dumpTopCount = -1
        fakeWs.moveLibraryCalls = 0
        fakeWs.movedDestination = ""
        fakeWs.renameCalls = 0
        fakeWs.tokenCalls = 0
        fakeMoves.faceCalls = 0
        fakeMoves.battlefieldLibraryCalls = 0
        fakeMoves.handLibraryCalls = 0
        fakeTransient.clearCalls = 0
        fakeTable.lifeValue = 0
        fakeTable.counterValue = 0
        fakeTable.libraryMoveDestination = "graveyard"
    }

    function test_exposesAllPopupEndpoints() {
        verify(editors.librarySearchPopup !== null)
        verify(editors.shuffleLibraryReminder !== null)
        verify(editors.publicZoneBrowser !== null)
        verify(editors.lifeEditor !== null)
        verify(editors.drawCardsEditor !== null)
        verify(editors.libraryTopCountEditor !== null)
        verify(editors.libraryMoveCardsEditor !== null)
        verify(editors.cardCounterEditor !== null)
        verify(editors.cardFacePicker !== null)
        verify(editors.tokenPicker !== null)
    }

    function test_forwardsEditorRequests() {
        editors.lifeEditor.lifeRequested(25)
        editors.drawCardsEditor.valueRequested(4)
        editors.libraryMoveCardsEditor.valueRequested(2)
        editors.counterLabelEditor.labelRequested("energy", "Energy")
        editors.cardFacePicker.faceSelected("Back")
        editors.libraryPositionEditor.positionRequested(3)
        editors.handLibraryPositionEditor.positionRequested(2)
        editors.tokenPicker.tokenSelected({"name": "Goblin"})

        compare(fakeTable.lifeValue, 25)
        compare(fakeWs.drawCalls, 1)
        compare(fakeWs.drawCount, 4)
        compare(fakeWs.moveLibraryCalls, 1)
        compare(fakeWs.movedDestination, "graveyard")
        compare(fakeWs.renameCalls, 1)
        compare(fakeMoves.faceCalls, 1)
        compare(fakeMoves.battlefieldLibraryCalls, 1)
        compare(fakeMoves.handLibraryCalls, 1)
        compare(fakeWs.tokenCalls, 1)
        compare(fakeTransient.clearCalls, 1)
    }

    function test_cardFacePickerPrioritizesVisibleFaceImages() {
        const faces = [{
            "name": "Front // Back",
            "faceName": "",
            "setCode": "TST",
            "collectorNumber": "7"
        }, {
            "name": "Back",
            "faceName": "Back",
            "setCode": "TST",
            "collectorNumber": "7"
        }]
        editors.cardFacePicker.prioritizeFaceImages(faces)

        compare(fakeCatalog.prioritizeCalls, 1)
        compare(fakeCatalog.prioritizedCards.length, 2)
        compare(fakeCatalog.prioritizedCards[1].name, "Back")
    }

    function test_landPlayPopupPrioritizesCanonicalFrontAndBackImages() {
        const card = {
            "name": "Front // Back",
            "setCode": "TST",
            "collectorNumber": "7"
        }
        const faces = [{
            "faceName": "",
            "displayName": "Front"
        }, {
            "faceName": "Back",
            "displayName": "Back"
        }]
        landPlayPopup.prioritizeFaceImages(card, faces)

        compare(fakeCatalog.prioritizeCalls, 1)
        compare(fakeCatalog.prioritizedCards.length, 2)
        compare(fakeCatalog.prioritizedCards[0].name, "Front // Back")
        compare(fakeCatalog.prioritizedCards[1].name, "Back")
        compare(fakeCatalog.prioritizedCards[1].setCode, "TST")
        compare(fakeCatalog.prioritizedCards[1].collectorNumber, "7")
    }

    function test_libraryTopCountTargetsConfiguredSeat() {
        editors.libraryTopCountEditor.showForLibrary(1, 53, 5)
        compare(editors.libraryTopCountEditor.sourceSeat, 1)
        compare(editors.libraryTopCountEditor.maximumValue, 53)
        editors.libraryTopCountEditor.valueRequested(3)
        compare(fakeWs.dumpCalls, 1)
        compare(fakeWs.dumpSeat, 1)
        compare(fakeWs.dumpTopCount, 3)
        editors.libraryTopCountEditor.close()
    }

    function test_deckTokensAppearBeforeCatalogTokens() {
        fakeCatalog.tokenSearchResults = [
            {"name": "Treasure", "displayName": "Treasure",
             "typeLine": "Token Artifact — Treasure",
             "setCode": "TWOE", "collectorNumber": "30"},
            {"name": "Goblin", "displayName": "Goblin",
             "typeLine": "Token Creature — Goblin",
             "setCode": "TNEO", "collectorNumber": "12"}
        ]
        compare(editors.tokenPicker.displayedTokens.length, 2)
        compare(editors.tokenPicker.displayedTokens[0].name, "Goblin")
        verify(editors.tokenPicker.displayedTokens[0].preferred)
        compare(editors.tokenPicker.displayedTokens[1].name, "Treasure")
    }
}
