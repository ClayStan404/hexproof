// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "CardInspectionProportions"
    when: windowShown
    readonly property var single: ({id:"single", name:"Ordinary Card", setCode:"TST", collectorNumber:"1"})
    ApplicationWindow {
        id: window
        width: 1920; height: 1011; visible: true
        LibrarySearchPopup { id: library; cardCatalogModel: catalog }
        ZoneBrowserPopup { id: zones; cardCatalogModel: catalog; canMoveCards: true; localSeatIndex: 0 }
    }
    QtObject {
        id: catalog
        function cardFaces(name, set, number) {
            return name === "Two Faces" ? [{name:"Front"}, {name:"Back"}] : []
        }
        function imageSource(name, set, number) { return "" }
        function cardDisplayName(name) { return name }
    }
    function init() { Theme.uiScale = 1 }
    function cleanup() { library.close(); zones.close() }
    function test_singleLibraryFaceKeepsDestinationOnInitialScreen() {
        library.showCards([single], 0, "", 0, "Alice", "Alice", 0)
        tryCompare(library, "opened", true)
        verify(waitForPolish(window))
        const scroll = findChild(library, "libraryInspectorScroll")
        const gallery = findChild(library, "libraryFaceGallery")
        const destination = findChild(library, "libraryDestination")
        verify(destination.visible)
        const rect = destination.mapToItem(scroll, 0, 0, destination.width, destination.height)
        verify(rect.y >= 0 && rect.y + rect.height <= scroll.height + 0.1,
            "Ordinary-card destination must be initially visible without scrolling: "
            + JSON.stringify({destination:rect, viewportHeight:scroll.height,
                inspectorWidth:scroll.width, artHeight:gallery.implicitHeight}))
        verify(scroll.width <= Theme.size(340) + 0.1)
        verify(gallery.implicitHeight <= Theme.size(220) + 0.1)
        mouseClick(destination)
        tryCompare(destination.popup, "opened", true)
        destination.popup.close()
    }
    function test_singleZoneFaceRetainsListSpaceAndPopupFootprint() {
        zones.cards = [single, {id:"second", name:"Another ordinary card with a readable name"}]
        zones.showZone("Alice", 0, "graveyard")
        tryCompare(zones, "opened", true)
        verify(waitForPolish(window))
        const list = findChild(zones, "zoneBrowserCards")
        const inspector = findChild(zones, "zoneBrowserArtScroll")
        verify(list.width >= Theme.size(540),
            "A single face must retain the public browser's readable list allocation: "
            + JSON.stringify({popupWidth:zones.width, listWidth:list.width, inspectorWidth:inspector.width}))
        fuzzyCompare(zones.width, Theme.size(960), 0.1)
        verify(inspector.width <= Theme.size(320) + 0.1)
    }
    function test_multifaceInspectionRetainsExpandedSpace() {
        const two = {id:"two", name:"Two Faces"}
        zones.cards = [two]
        zones.showZone("Alice", 0, "exile")
        tryCompare(zones, "opened", true)
        const zoneGallery = findChild(zones, "zoneBrowserFaceGallery")
        tryCompare(zoneGallery, "faceCount", 2)
        verify(waitForPolish(window))
        verify(zones.width > Theme.size(960))
        verify(findChild(zones, "zoneBrowserArtScroll").width > Theme.size(320))
        zones.close()
        library.showCards([two], 0, "", 0, "Alice", "Alice", 0)
        tryCompare(library, "opened", true)
        const libraryGallery = findChild(library, "libraryFaceGallery")
        tryCompare(libraryGallery, "faceCount", 2)
        verify(waitForPolish(window))
        verify(findChild(library, "libraryInspectorScroll").width > Theme.size(340))
        compare(library.selectedCard.id, "two")
    }
}
