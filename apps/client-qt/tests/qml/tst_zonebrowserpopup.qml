// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "ZoneBrowserPopup"
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 1100
        height: 800
        visible: true

        ZoneBrowserPopup {
            id: popup
            canMoveCards: true
            localSeatIndex: 0
            cards: [
                {"id": "c0", "name": "Opt", "setCode": "MID",
                 "collectorNumber": "1"},
                {"id": "c1", "name": "Ponder", "setCode": "M10",
                 "collectorNumber": "2"},
                {"id": "c2", "name": "Preordain", "setCode": "M11",
                 "collectorNumber": "3"}
            ]
        }
    }

    SignalSpy { id: batchSpy; target: popup; signalName: "movesRequested" }
    SignalSpy { id: singleSpy; target: popup; signalName: "moveRequested" }

    QtObject {
        id: catalog
        property var imageRequests: []
        function imageSource(name, setCode, number) {
            imageRequests.push(name)
            return ""
        }
        function matchesCardQuery(name, setCode, number, query) {
            return name.toLocaleLowerCase().includes(query)
        }
    }

    function init() {
        batchSpy.clear()
        singleSpy.clear()
        popup.canMoveCards = true
        popup.cardCatalogModel = null
        catalog.imageRequests = []
        popup.individualCards = false
        testWindow.width = 1100
        testWindow.height = 800
        Theme.uiScale = 1

        if (popup.opened)
            popup.close()
        popup.filterQuery = ""
        popup.selectedIndex = -1
        popup.selectedOrder = []
        popup.cards = [
            {"id": "c0", "name": "Opt", "setCode": "MID", "collectorNumber": "1"},
            {"id": "c1", "name": "Ponder", "setCode": "M10", "collectorNumber": "2"},
            {"id": "c2", "name": "Preordain", "setCode": "M11", "collectorNumber": "3"}
        ]
    }

    function cleanup() {
        if (popup.opened)
            popup.close()
        Theme.uiScale = 1
        wait(1)
    }

    function test_faceDownExileStaysSeparateAndNeverLooksUpIdentity() {
        popup.cardCatalogModel = catalog
        popup.cards = [
            {id: "hidden-1", faceDown: true},
            {id: "hidden-2", faceDown: true},
            // Presentation must also fail closed if private data is retained.
            {id: "hidden-3", faceDown: true, name: "Secret", setCode: "TST", collectorNumber: "3"}
        ]
        popup.showZone("Alice", 0, "exile")
        tryCompare(popup, "opened", true)
        compare(popup.groupedCards.length, 3)
        const list = findChild(popup, "zoneBrowserCards")
        for (let index = 0; index < 3; ++index) {
            tryVerify(() => list.itemAtIndex(index) !== null)
            const row = list.itemAtIndex(index)
            const label = findChild(row, "zoneBrowserCardName" + index)
            verify(label !== null)
            compare(label.text, "Face-down card")
            const image = findChild(row, "zoneBrowserCardImage" + index)
            verify(String(image.source).endsWith("card-back.jpg"))
        }
        popup.selectedIndex = 2
        verify(String(findChild(popup, "zoneBrowserPreviewImage").source).endsWith("card-back.jpg"))
        compare(catalog.imageRequests.indexOf("Secret"), -1)
        popup.filterQuery = "secret"
        compare(popup.visibleCards.length, 0)
        popup.filterQuery = ""
        popup.selectedOrder = ["hidden-1", "hidden-3"]
        popup.requestSelectedMove("hand", "", false)
        compare(batchSpy.count, 1)
        compare(Array.from(batchSpy.signalArguments[0]),
                [["hidden-1", "hidden-3"], "exile", 0, "hand", -1, "", false])
    }

    // showZone / onClosed assign searchField.text. That must not restart the
    // debounce timer and snap selectedIndex back to 0 after the user already
    // clicked a later card.
    function test_programmaticFilterClearDoesNotResetSelection() {
        popup.showZone("Alice", 0, "graveyard")
        tryVerify(() => popup.opened)
        const filter = findChild(popup, "zoneBrowserFilter")
        verify(filter !== null)
        filter.text = "tmp"
        filter.text = ""
        popup.selectedIndex = 2
        wait(200)
        compare(popup.selectedIndex, 2)
        compare(popup.filterQuery, "")
    }
    function test_enduranceUsesOneBatchWithExplicitRandomBottom() {
        popup.showZone("Alice", 0, "graveyard")
        tryVerify(() => popup.opened)
        mouseClick(findChild(popup, "selectAllZoneCards"))
        compare(popup.selectedCount, 3)
        mouseClick(findChild(popup, "moveZoneCardsButton"))
        const action = findChild(popup, "zoneCardToLibraryBottomRandom")
        verify(action !== null)
        verify(action.enabled)
        action.triggered()
        compare(batchSpy.count, 1)
        compare(singleSpy.count, 0)
        compare(Array.from(batchSpy.signalArguments[0]), [["c0", "c1", "c2"], "graveyard", 0, "library", -1, "bottom", true])
    }

    function test_singleCardLibraryOptionsStillUseBatchContract() {
        popup.showZone("Alice", 0, "exile")
        popup.selectedIndex = 1
        popup.requestSelectedMove("library", "shuffle", false)
        compare(batchSpy.count, 1)
        compare(singleSpy.count, 0)
        compare(batchSpy.signalArguments[0][0], ["c1"])
        compare(batchSpy.signalArguments[0][5], "shuffle")
    }

    function test_handManagerUsesPrivateSourceAndSelection() {
        popup.showZone("Alice", 0, "hand")
        verify(popup.multiSelectEnabled)
        popup.toggleAllVisible()
        popup.requestSelectedMove("library", "bottom", true)
        compare(batchSpy.count, 1)
        compare(batchSpy.signalArguments[0][1], "hand")
        compare(batchSpy.signalArguments[0][2], -1)
    }

    function test_filterSelectionKeepsUnselectedCardsAndBlocksForeignHiddenMove() {
        popup.showZone("Bob", 1, "graveyard")
        popup.filterQuery = "ponder"
        compare(popup.visibleCards.length, 1)
        popup.toggleAllVisible()
        compare(popup.selectedOrder, ["c1"])
        popup.requestSelectedMove("library", "bottom", true)
        compare(batchSpy.count, 0)
        compare(singleSpy.count, 0)
        popup.requestSelectedMove("exile")
        compare(singleSpy.count, 1)
        compare(singleSpy.signalArguments[0][0], "c1")
    }

    function test_compactScaledActionsAndCardsRemainReachable() {
        testWindow.width = 900
        testWindow.height = 620
        Theme.uiScale = 1.5
        popup.showZone("Alice", 0, "graveyard")
        tryVerify(() => popup.opened)
        const list = findChild(popup, "zoneBrowserCards")
        const move = findChild(popup, "moveZoneCardsButton")
        const done = findChild(popup, "doneZoneBrowserButton")
        tryVerify(() => list.width > 400 && list.height > 120, 5000, "list=" + list.width + "x" + list.height)
        for (const item of [move, done]) {
            const position = item.mapToItem(testWindow.contentItem, 0, 0)
            verify(position.x >= 0 && position.y >= 0)
            verify(position.x + item.width <= testWindow.width)
            verify(position.y + item.height <= testWindow.height)
        }
        mouseClick(move)
        const action = findChild(popup, "zoneCardToLibraryBottomRandom")
        verify(action.enabled)
        action.triggered()
        compare(batchSpy.count, 1)
    }

    function test_individualCopiesPreserveSelectionAcrossGroupingAndUpdates() {
        popup.cards = [
            {"id": "a", "name": "Opt", "setCode": "MID", "collectorNumber": "1"},
            {"id": "b", "name": "Opt", "setCode": "MID", "collectorNumber": "1"},
            {"id": "c", "name": "Ponder", "setCode": "M10", "collectorNumber": "2"}
        ]
        popup.showZone("Alice", 0, "graveyard")
        tryVerify(() => popup.opened)
        compare(popup.visibleCards.length, 2)
        mouseClick(findChild(popup, "zoneIndividualCards"))
        compare(popup.visibleCards.length, 3)
        popup.toggleCardGroup(popup.visibleCards[1])
        compare(popup.selectedOrder, ["b"])
        popup.filterQuery = "ponder"
        popup.toggleAllVisible()
        compare(popup.selectedOrder, ["b", "c"])
        popup.toggleAllVisible()
        compare(popup.selectedOrder, ["b"])
        popup.filterQuery = ""
        mouseClick(findChild(popup, "zoneIndividualCards"))
        compare(popup.visibleCards.length, 2)
        compare(popup.selectedOrder, ["b"])
        popup.cards = popup.cards.filter(card => card.id !== "b")
        compare(popup.selectedOrder, [])
    }

    function test_compactPreviewKeepsMoveActionAndSelection() {
        testWindow.width = 900
        testWindow.height = 620
        Theme.uiScale = 1.5
        popup.showZone("Alice", 0, "graveyard")
        tryVerify(() => popup.opened)
        popup.toggleAllVisible()
        const preview = findChild(popup, "zonePreviewButton")
        const list = findChild(popup, "zoneBrowserCards")
        verify(preview.visible)
        mouseClick(preview)
        verify(popup.showInspector)
        verify(!list.visible)
        compare(popup.selectedCount, 3)
        verify(findChild(popup, "moveZoneCardsButton").visible)
        mouseClick(preview)
        verify(list.visible)
        verify(!popup.showInspector)
        compare(popup.selectedCount, 3)
        popup.close()
        tryVerify(() => !popup.opened)
        popup.showZone("Alice", 0, "hand")
        verify(!popup.previewRequested)
        compare(popup.selectedCount, 0)
    }

}
