// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "DeckTokenManager"
    when: windowShown

    readonly property string testImage:
        "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC"
        + "AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="

    QtObject {
        id: fakeDeckLibrary
        property var currentTokens: [{
            "name": "Goblin",
            "displayName": "地精",
            "typeLine": "Token Creature — Goblin",
            "setCode": "TNEO",
            "collectorNumber": "12",
            "power": "1",
            "toughness": "1",
            "oracleText": "Haste"
        }]
        function removeToken() {}
    }

    QtObject {
        id: fakeCatalog
        property bool tokenCatalogInstalled: true
        property int imageRevision: -1
        property string language: "en"
        property var cachedLanguages: []
        property var prioritized: []
        property var metadata: ({})
        function tokenImageSource() { return testCase.testImage }
        function cacheToken() { cachedLanguages = cachedLanguages.concat([language]) }
        function prioritizeCards(cards) { prioritized = prioritized.concat(cards) }
        function tokenDetails() { return Object.assign({},metadata[language] || {}) }
    }

    ApplicationWindow {
        id: testWindow
        width: 1100
        height: 760
        visible: true

        DeckTokenManager {
            id: manager
            deckLibraryModel: fakeDeckLibrary
            catalogModel: fakeCatalog
        }
    }

    function init() {
        Theme.uiScale = 1
        fakeCatalog.imageRevision = -1
        fakeCatalog.language = "en"
        fakeCatalog.cachedLanguages = []
        fakeCatalog.prioritized = []
        fakeCatalog.metadata = {en:{displayName:"Goblin",typeLine:"Token Creature — Goblin",oracleText:"Haste"},
                                zh:{displayName:"地精",typeLine:"衍生生物～地精",oracleText:"敏捷"}}
        manager.close()
    }

    function cleanup() {
        manager.close()
        Theme.uiScale = 1
    }

    function test_previewDoesNotReflowGridOrLeaveWindow_data() {
        return [{tag:"normal",scale:1},{tag:"large",scale:1.5}]
    }

    function test_previewDoesNotReflowGridOrLeaveWindow(data) {
        Theme.uiScale = data.scale
        fakeCatalog.imageRevision = 0
        manager.open()
        tryCompare(manager,"opened",true)
        verify(waitForPolish(testWindow))
        mouseMove(testWindow,1,1)
        fakeCatalog.prioritized = []
        manager.cacheDisplayedTokens()
        compare(fakeCatalog.prioritized.length,0)
        const grid = findChild(manager,"managedDeckTokenGrid")
        tryVerify(() => grid.itemAtIndex(0) !== null)
        const thumbnail = findChild(grid.itemAtIndex(0),"managedDeckTokenImage")
        const originalGrid = {x:grid.x,y:grid.y,width:grid.width,height:grid.height}
        mouseMove(thumbnail,thumbnail.width/2,thumbnail.height/2)
        const preview = findChild(manager,"managedTokenArtPreview")
        tryCompare(preview,"visible",true)
        compare(fakeCatalog.prioritized.length,1)
        compare(fakeCatalog.prioritized[0].name,"Goblin")
        compare(fakeCatalog.prioritized[0].kind,"token")
        verify(waitForPolish(testWindow))
        compare({x:grid.x,y:grid.y,width:grid.width,height:grid.height},originalGrid,
                "Showing art must not shrink or relocate the deck-token grid")
        const point = preview.mapToItem(testWindow.contentItem,0,0)
        verify(point.x>=0 && point.y>=0)
        verify(point.x+preview.width<=testWindow.width && point.y+preview.height<=testWindow.height)
        const popupPoint = preview.mapToItem(manager.contentItem.parent,0,0)
        verify(popupPoint.x>=0 && popupPoint.y>=0)
        verify(popupPoint.x+preview.width<=manager.width && popupPoint.y+preview.height<=manager.height)
    }

    function test_refreshesImageAfterCacheRevisionChanges() {
        manager.open()
        tryVerify(() => manager.opened)
        const grid = findChild(manager, "managedDeckTokenGrid")
        verify(grid !== null)
        tryCompare(grid, "count", 1)
        tryVerify(() => grid.itemAtIndex(0) !== null)
        const image = findChild(grid.itemAtIndex(0),
                                "managedDeckTokenImage")
        verify(image !== null)
        const details = findChild(grid.itemAtIndex(0),
                                  "managedDeckTokenDetails")
        verify(details !== null)
        compare(details.text, "1/1 · Token Creature — Goblin · Haste")
        compare(image.source, "")

        fakeCatalog.imageRevision = 0
        tryCompare(image, "status", Image.Ready)
        verify(String(image.source).startsWith("data:image/png"))
    }

    function test_openManagerFollowsLanguageAndMetadataOnlyUpdates() {
        manager.open()
        tryCompare(manager,"opened",true)
        const grid = findChild(manager,"managedDeckTokenGrid")
        tryVerify(() => grid.itemAtIndex(0) !== null)
        const name = findChild(grid.itemAtIndex(0),"managedDeckTokenName")
        const details = findChild(grid.itemAtIndex(0),"managedDeckTokenDetails")
        compare(name.text,"Goblin")
        fakeCatalog.language = "zh"
        tryCompare(name,"text","地精")
        compare(details.text,"1/1 · 衍生生物～地精 · 敏捷")
        verify(fakeCatalog.cachedLanguages.includes("zh"))
        fakeCatalog.metadata.zh.oracleText = "敏捷，不能进行阻挡。"
        fakeCatalog.imageRevision++
        tryVerify(() => details.text.includes("不能进行阻挡"))
        compare(fakeDeckLibrary.currentTokens[0].oracleText,"Haste")
        fakeCatalog.language = "en"
        tryCompare(name,"text","Goblin")
        verify(details.text.includes("Haste"))
    }

    function test_clickOpensReadOnlyRulesWithoutChangingSavedMetadata_data() {
        return [{tag:"immediate",settled:false},{tag:"already-rendered",settled:true}]
    }

    function test_clickOpensReadOnlyRulesWithoutChangingSavedMetadata(data) {
        Theme.uiScale = 1.5
        fakeCatalog.language = "zh"
        fakeCatalog.metadata.zh.oracleText = "敏捷。\n\n".repeat(80) + "完整规则末尾。"
        fakeCatalog.imageRevision = 0
        manager.open()
        tryCompare(manager,"opened",true)
        const grid = findChild(manager,"managedDeckTokenGrid")
        tryVerify(() => grid.itemAtIndex(0) !== null)
        // Exercise an idle window as well as one still processing its first frame.
        if (data.settled) wait(50)
        // Click readiness depends on layout, not a future frameSwapped signal.
        verify(waitForPolish(testWindow))
        const summary = findChild(grid.itemAtIndex(0),"managedDeckTokenDetails")
        verify(summary !== null && summary.visible && summary.width>0 && summary.height>0)
        const point = summary.mapToItem(grid,summary.width/2,summary.height/2)
        verify(point.x>=0 && point.y>=0 && point.x<grid.width && point.y<grid.height,
               "The click target must be inside the visible token grid")
        mouseClick(summary)
        const detail = manager.detailsPopup
        tryCompare(detail,"opened",true)
        verify(fakeCatalog.prioritized.some(card => card.name === "Goblin" && card.kind === "token"))
        const rules = findChild(detail,"tokenDetailsRulesText")
        const art = findChild(detail,"tokenDetailsArt")
        tryCompare(art,"status",Image.Ready)
        verify(rules.text.endsWith("完整规则末尾。"))
        const scroll = findChild(detail,"tokenDetailsRulesScroll")
        verify(scroll.contentHeight>scroll.height)
        compare(detail.card.name,"Goblin")
        compare(fakeDeckLibrary.currentTokens[0].oracleText,"Haste")
        manager.close()
        tryCompare(detail,"opened",false)
    }
}
