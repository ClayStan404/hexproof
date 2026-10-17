// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"
import "../../qml/components"

TestCase {
    name: "PackSimulator"
    when: windowShown
    ApplicationWindow { id: window; width: 900; height: 620; visible: true }
    QtObject {
        id: catalog
        signal catalogChanged()
        property int imageRevision: 0
        property int openedCount: 0
        property var products: [{id:"test", name:"Example set — Draft", authentic:true}]
        function limitedProducts() { return products }
        function limitedProduct(id) { return products[0] }
        function simulateLimitedPacks(product, count) {
            openedCount = count
            return [{cards:[{name:"Island", rarity:"common"}]}]
        }
        function cacheCardsIncrementally(cards) { }
        function tableImageSource(name, set, number) { return "" }
        function imageSource(name, set, number) { return "" }
        function prioritizeCards(cards) {}
        function cardFaces(name, set, number) {
            return name === "Front // Back"
                ? [{name:"Front", faceName:"", displayName:"Front", setCode:set, collectorNumber:number},
                   {name:"Back", faceName:"Back", displayName:"Back", setCode:set, collectorNumber:number}] : []
        }
    }
    Component {
        id: pageComponent
        LimitedHub {
            property var cardCatalog: catalog
            property var preferences: ({animatePackOpenings:false})
        }
    }
    function cleanup() { Theme.uiScale = 1 }
    function test_formRemainsUsable_data() {
        return [{tag:"large",scale:1.5}, {tag:"maximum",scale:1.8}]
    }
    function test_formRemainsUsable(data) {
        Theme.uiScale = data.scale
        catalog.openedCount = 0
        const page = createTemporaryObject(pageComponent, window.contentItem,
                                            {width:window.width,height:window.height})
        verify(page !== null)
        waitForRendering(page)
        const body = findChild(page, "packSimulatorBody")
        const button = findChild(page, "openSimulatedPacksButton")
        body.contentY = Math.max(0, button.mapToItem(body.contentItem, 0, 0).y
                                   + button.height - body.height)
        waitForRendering(page)
        const point = button.mapToItem(body, 0, 0)
        verify(point.x >= 0 && point.x + button.width <= body.width)
        verify(point.y >= 0 && point.y + button.height <= body.height + 1)
        mouseClick(button)
        compare(catalog.openedCount, 1)
        compare(page.openedPacks.length, 1)
        const search = findChild(page, "limitedSetSearchField")
        search.text = "missing product"
        verify(!button.enabled)
        findChild(page, "limitedSetSearchClearButton").clicked()
        verify(button.enabled)
    }
    function test_openedResultsPreviewBothFacesWithoutChangingPack() {
        const page = createTemporaryObject(pageComponent, window.contentItem,
                                            {width:window.width,height:window.height})
        verify(page !== null)
        page.openedPacks = [{cards:[{name:"Front // Back", setCode:"TST", collectorNumber:"7"}]}]
        waitForPolish(window)
        const card = findChild(page, "simulatedPackCard0-0")
        verify(card !== null)
        const body = findChild(page, "packSimulatorBody")
        body.contentY = Math.max(0, card.mapToItem(body.contentItem, 0, 0).y
                                + card.height - body.height)
        waitForPolish(window)
        mouseMove(window, 1, 1)
        mouseMove(card, card.width / 2, card.height / 2)
        const preview = findChild(page, "simulatedPackCardPreview")
        tryCompare(preview, "visible", true)
        compare(preview.facePreview.displayFaces.map(face => face.name), ["Front", "Back"])
        verify(findChild(preview, "cardHoverPreviewArt-1") !== null)
        verify(findChild(preview, "viewOtherFaceButton") === null)
        compare(page.openedPacks[0].cards[0].name, "Front // Back")
        compare(page.openedPacks[0].cards[0].collectorNumber, "7")
        page.openedPacks = []
        verify(!preview.visible)
    }
}
