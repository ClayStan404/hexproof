// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "Emblems"
    when: windowShown

    readonly property string testImage:
        "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC"
        + "AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    readonly property var emblem: ({id: "emblem-a", kind: "emblem", name: "Teferi, Hero of Dominaria Emblem",
        setCode: "TCMM", collectorNumber: "79", typeLine: "Emblem — Teferi",
        oracleText: "Whenever you draw a card, exile target permanent an opponent controls."})
    readonly property var token: ({kind: "token", name: "Goblin", setCode: "TNEO", collectorNumber: "12"})
    property var selection: ({})
    property int selectionSeat: -1
    property string removedId: ""

    QtObject {
        id: catalog
        property bool tokenCatalogInstalled: true
        property bool tokenSearching: false
        property int imageRevision: 1
        property string language: "en"
        property var tokenSearchResults: []
        property var lastSearch: ({})
        property var cached: []
        property var prioritized: []
        property bool artAvailable: true
        property var metadata: ({})
        function searchTokens(query, kind, setCodes) { lastSearch = {query,kind,setCodes} }
        function tokenImageSource() { return artAvailable ? testCase.testImage : "" }
        function tokenDisplayName(name) { return language === "zh" ? "多明纳里亚英雄泰菲力徽记" : name }
        function tokenDetails(name) {
            if (name === "Goblin") return language === "zh"
                ? {displayName:"地精", typeLine:"衍生生物～地精", oracleText:"敏捷"}
                : {displayName:name, typeLine:"Token Creature — Goblin", oracleText:"Haste"}
            return Object.assign({},metadata[language] || {})
        }
        function cacheToken(card) { cached = cached.concat([Object.assign({},card,{requestedLanguage:language})]) }
        function prioritizeCards(cards) { prioritized = prioritized.concat(cards) }
    }
    QtObject {
        id: session
        property int seatIndex: 0
    }
    QtObject {
        id: controller
        property var roomSession: session
        property var cardCatalogModel: catalog
        property var wsModel: controller
        property bool canAct: true
        property var battlefieldSeats: []
        function removeEmblem(id) { testCase.removedId = id }
    }
    ApplicationWindow {
        id: testWindow
        width: 1100
        height: 780
        visible: true
        TokenPicker {
            id: picker
            catalogModel: catalog
            players: [{seat: 0, label: "Alice"}, {seat: 1, label: "Bob"}]
            defaultRecipientSeat: 0
            onTokenSelected: card => testCase.selection = card
            onEmblemSelected: (card, seat) => {
                testCase.selection = card
                testCase.selectionSeat = seat
            }
        }
        EmblemBrowser {
            id: browser
            tableController: controller
        }
    }

    function init() {
        Theme.uiScale = 1
        testWindow.width = 1100
        testWindow.height = 780
        testTranslations.setLanguage("en")
        catalog.tokenCatalogInstalled = true
        catalog.tokenSearchResults = [token, emblem]
        catalog.cached = []
        catalog.prioritized = []
        catalog.lastSearch = ({})
        catalog.language = "en"
        catalog.artAvailable = true
        catalog.metadata = {en:{displayName:emblem.name, typeLine:emblem.typeLine, oracleText:emblem.oracleText},
                            zh:{displayName:"多明纳里亚英雄泰菲力徽记", typeLine:"徽记～泰菲力",
                                oracleText:"每当你抓一张牌时，放逐目标由对手操控的永久物。"}}
        picker.preferredTokens = []
        picker.environmentSetCodes = []
        picker.environmentOnly = false
        picker.existingTokensDisabled = false
        picker.allowEmblemRecipient = false
        picker.kindFilter = "all"
        selection = ({})
        selectionSeat = -1
        removedId = ""
        session.seatIndex = 0
        controller.canAct = true
        controller.battlefieldSeats = [{seat: 0, displayName: "Alice", emblems: [emblem]},
                                      {seat: 1, displayName: "Bob", emblems: [Object.assign({},emblem,{id:"emblem-b"})]}]
    }

    function test_limitedEnvironmentDefaultsToItsTokenSetAndCanBroaden() {
        picker.environmentSetCodes = ["NEO"]
        picker.open()
        tryCompare(picker, "opened", true)
        verify(picker.environmentOnly)
        compare(picker.displayedTokens.length, 1)
        compare(picker.displayedTokens[0].name, "Goblin")
        compare(catalog.lastSearch.setCodes[0], "NEO")
        picker.environmentOnly = false
        tryCompare(picker.displayedTokens, "length", 2)
        tryVerify(() => catalog.lastSearch.setCodes.length === 0)
    }

    function cleanup() {
        picker.close()
        browser.close()
        tryCompare(picker, "opened", false)
        tryCompare(browser, "opened", false)
        Theme.uiScale = 1
        testTranslations.setLanguage("en")
    }

    function rowAt(index) {
        verify(waitForRendering(picker.contentItem))
        const list = findChild(picker, "tokenSearchResults")
        tryVerify(() => list.itemAtIndex(index) !== null)
        return list.itemAtIndex(index)
    }

    function test_filtersCatalogAndSavedEmblems() {
        picker.preferredTokens = [emblem]
        picker.open()
        tryCompare(picker, "opened", true)
        verify(waitForRendering(picker.contentItem))
        compare(picker.displayedTokens.length, 2)
        compare(picker.displayedTokens[0].kind, "emblem")
        verify(picker.displayedTokens[0].preferred)
        const filters = findChild(picker, "tokenKindFilters").itemAt(2)
        verify(filters !== null)
        mouseClick(filters)
        tryVerify(() => catalog.lastSearch.kind === "emblem")
        compare(picker.displayedTokens.length, 1)
        compare(picker.displayedTokens[0].name, emblem.name)
        mouseClick(findChild(picker, "tokenKindFilters").itemAt(1))
        tryVerify(() => catalog.lastSearch.kind === "token")
        compare(picker.displayedTokens.length, 1)
        compare(picker.displayedTokens[0].name, token.name)
    }

    function test_offlineSavedEmblemsAreSearchable() {
        catalog.tokenCatalogInstalled = false
        catalog.tokenSearchResults = []
        picker.preferredTokens = [token, emblem]
        picker.open()
        tryCompare(picker, "opened", true)
        const search = findChild(picker, "tokenSearchField")
        verify(search.enabled)
        search.text = "teferi"
        tryCompare(picker, "displayedTokens", [picker.copyToken(emblem,true)])
    }

    function test_deckPickerPreservesEmblemKind() {
        picker.open()
        tryCompare(picker, "opened", true)
        picker.kindFilter = "emblem"
        const row = rowAt(0)
        verify(!findChild(row, "emblemRecipientSelector").visible)
        mouseClick(findChild(row, "createTokenResultButton"))
        compare(selection.kind, "emblem")
        compare(selection.typeLine, emblem.typeLine)
        compare(selection.oracleText, emblem.oracleText)
        compare(selectionSeat, -1)
    }

    function test_gamePickerSelectsRecipientOnlyForEmblems() {
        picker.allowEmblemRecipient = true
        picker.open()
        tryCompare(picker, "opened", true)
        compare(picker.recipientSeat, 0)
        verify(!findChild(rowAt(0), "emblemRecipientSelector").visible)
        const recipient = findChild(rowAt(1), "emblemRecipientSelector")
        verify(recipient.visible)
        compare(recipient.count, 2)
        recipient.currentIndex = 1
        recipient.activated(1)
        mouseClick(findChild(rowAt(1), "createTokenResultButton"))
        compare(selection.kind, "emblem")
        compare(selectionSeat, 1)
        picker.open()
        tryCompare(picker, "opened", true)
        compare(picker.recipientSeat, 0)
    }

    function test_pickerHoverOpensFullArt_data() {
        return [{tag:"normal",scale:1,width:1100,height:780},
                {tag:"large-compact",scale:1.5,width:1000,height:720}]
    }

    function test_pickerHoverOpensFullArt(data) {
        Theme.uiScale = data.scale
        testWindow.width = data.width
        testWindow.height = data.height
        picker.open()
        tryCompare(picker, "opened", true)
        const thumbnail = findChild(rowAt(1), "tokenResultThumbnail")
        const list = findChild(picker,"tokenSearchResults")
        const originalList = {x:list.x,y:list.y,width:list.width,height:list.height}
        mouseMove(thumbnail,thumbnail.width/2,thumbnail.height/2)
        const preview = findChild(picker, "tokenArtPreview")
        tryCompare(preview, "visible", true)
        compare(preview.card.kind, "emblem")
        verify(preview.height > thumbnail.height * 2)
        verify(catalog.cached.some(card => card.kind === "emblem"))
        verify(waitForRendering(picker.contentItem))
        compare({x:list.x,y:list.y,width:list.width,height:list.height},originalList,
                "A hover overlay must not participate in the popup's ColumnLayout")
        const point = preview.mapToItem(testWindow.contentItem,0,0)
        verify(point.x>=0 && point.y>=0)
        verify(point.x+preview.width<=testWindow.width && point.y+preview.height<=testWindow.height,
               "The full preview must stay inside the actual window")
        const popupPoint = preview.mapToItem(picker.contentItem.parent,0,0)
        verify(popupPoint.x>=0 && popupPoint.y>=0)
        verify(popupPoint.x+preview.width<=picker.width && popupPoint.y+preview.height<=picker.height,
               "The full preview must stay inside the popup overlay")
    }

    function test_closedPickerDoesNotStartAStaleSearch() {
        picker.open()
        tryCompare(picker,"opened",true)
        picker.kindFilter = "emblem"
        picker.close()
        tryCompare(picker,"opened",false)
        catalog.lastSearch = ({query:"new picker",kind:"token"})
        wait(220)
        compare(catalog.lastSearch,{query:"new picker",kind:"token"})
    }

    function test_gamePickerFitsCompactLargeScale_data() {
        return [{tag:"english",language:"en"},{tag:"chinese",language:"zh"}]
    }

    function test_gamePickerFitsCompactLargeScale(data) {
        testTranslations.setLanguage(data.language)
        testWindow.width = 1000
        testWindow.height = 720
        Theme.uiScale = 1.5
        picker.allowEmblemRecipient = true
        picker.preferredTokens = [emblem]
        picker.open()
        tryCompare(picker,"opened",true)
        const row = rowAt(0)
        const recipient = findChild(row,"emblemRecipientSelector")
        const create = findChild(row,"createTokenResultButton")
        verify(recipient.width>0 && recipient.height>0)
        verify(create.contentItem.width>=create.contentItem.implicitWidth)
        for (const control of [recipient,create]) {
            const point = control.mapToItem(testWindow.contentItem,0,0)
            verify(point.x>=0 && point.y>=0)
            verify(point.x+control.width<=testWindow.width)
            verify(point.y+control.height<=testWindow.height)
        }
    }

    function test_browserPublicArtAndRemovalPermissions_data() {
        return [{tag:"owner",seat:0,viewer:0,canAct:true,canRemove:true},
                {tag:"opponent",seat:1,viewer:0,canAct:true,canRemove:false},
                {tag:"spectator",seat:0,viewer:-1,canAct:false,canRemove:false},
                {tag:"finished",seat:0,viewer:0,canAct:false,canRemove:false}]
    }

    function test_browserPublicArtAndRemovalPermissions(data) {
        session.seatIndex = data.viewer
        controller.canAct = data.canAct
        browser.showSeat(data.seat)
        tryCompare(browser, "opened", true)
        compare(browser.canRemove, data.canRemove)
        const art = findChild(browser, "emblemBrowserArt")
        tryCompare(art, "status", Image.Ready)
        tryVerify(() => art.height > 300)
        const list = findChild(browser, "emblemBrowserList")
        tryVerify(() => list.itemAtIndex(0) !== null)
        const select = findChild(list.itemAtIndex(0), "selectEmblem" + browser.selectedEmblem.id)
        compare(select.contentItem.verticalAlignment, Text.AlignVCenter)
        const remove = findChild(list.itemAtIndex(0), "removeEmblem" + browser.selectedEmblem.id)
        compare(remove.visible,data.canRemove)
        compare(remove.enabled,data.canRemove)
        if (data.canRemove) {
            mouseClick(remove)
            compare(removedId,"emblem-a")
        } else compare(removedId,"")
        verify(catalog.cached.some(card => card.kind === "emblem"))
    }

    function test_browserReflectsAuthoritativeRemoval() {
        browser.showSeat(0)
        tryCompare(browser, "opened", true)
        compare(browser.emblems.length,1)
        controller.battlefieldSeats = [{seat:0,displayName:"Alice",emblems:[]}]
        tryCompare(browser,"emblems",[])
        compare(browser.selectedEmblem.name,undefined)
    }

    function test_browserLocalizesWithoutChangingSearchState() {
        browser.showSeat(0)
        tryCompare(browser,"opened",true)
        const list = findChild(browser,"emblemBrowserList")
        tryVerify(() => list.itemAtIndex(0) !== null)
        const select = findChild(list.itemAtIndex(0),"selectEmblememblem-a")
        compare(select.accessibleName,emblem.name)
        catalog.language = "zh"
        tryCompare(select,"accessibleName","多明纳里亚英雄泰菲力徽记")
        compare(catalog.tokenSearchResults,[token,emblem])
        compare(Object.keys(catalog.lastSearch).length,0)
    }

    function test_browserLanguageSwitchKeepsEnglishFallbackArtAndRefreshesRules() {
        browser.showSeat(0)
        tryCompare(browser,"opened",true)
        const rules = findChild(browser,"emblemRulesText")
        const art = findChild(browser,"emblemBrowserArt")
        tryCompare(art,"status",Image.Ready)
        verify(rules.text.includes(emblem.oracleText))
        const originalArt = art.source
        catalog.language = "zh"
        tryVerify(() => rules.text.includes("每当你抓一张牌时"))
        verify(rules.text.includes("徽记～泰菲力"))
        compare(art.source,originalArt,"An English fallback image must not suppress available Chinese rules")
        verify(catalog.cached.some(card => card.requestedLanguage === "zh"))
        catalog.metadata.zh.oracleText += " 元数据更新。"
        catalog.imageRevision++
        tryVerify(() => rules.text.endsWith("元数据更新。"))
        catalog.language = "en"
        tryVerify(() => rules.text.includes(emblem.oracleText))
        compare(browser.selectedEmblem.name,emblem.name)
        compare(browser.selectedEmblem.typeLine,emblem.typeLine)
    }

    function test_browserLongChineseRulesScrollWithoutClippingControls() {
        Theme.uiScale = 1.5
        testWindow.width = 1000
        testWindow.height = 720
        catalog.language = "zh"
        catalog.metadata.zh.oracleText = ("每当你抓一张牌时，放逐目标由对手操控的永久物。\n\n").repeat(50) + "规则正文末尾。"
        catalog.imageRevision++
        browser.showSeat(0)
        tryCompare(browser,"opened",true)
        verify(waitForRendering(browser.contentItem))
        const scroll = findChild(browser,"emblemRulesScroll")
        const rules = findChild(browser,"emblemRulesText")
        verify(scroll.contentHeight > scroll.height * 2)
        verify(rules.text.endsWith("规则正文末尾。"))
        mouseWheel(scroll,scroll.width/2,scroll.height/2,0,-120)
        tryVerify(() => scroll.contentY > 0)
        scroll.contentY = scroll.contentHeight - scroll.height
        verify(scroll.atYEnd)
        const list = findChild(browser,"emblemBrowserList")
        tryVerify(() => list.itemAtIndex(0) !== null)
        for (const control of [scroll, findChild(browser,"emblemBrowserArt"),
                               findChild(browser,"closeEmblemBrowserButton"),
                               findChild(list.itemAtIndex(0),"removeEmblememblem-a")]) {
            verify(control.width>0 && control.height>0)
            const point = control.mapToItem(testWindow.contentItem,0,0)
            verify(point.x>=0 && point.y>=0)
            verify(point.x+control.width<=testWindow.width && point.y+control.height<=testWindow.height)
        }
        catalog.language = "en"
        tryCompare(scroll,"contentY",0)
        verify(rules.text.includes(emblem.oracleText))
    }

    function test_pickerLocalizesVisibleMetadataWithoutMutatingSelectedCard() {
        picker.kindFilter = "all"
        picker.open()
        tryCompare(picker,"opened",true)
        const row = rowAt(1)
        const name = findChild(row,"tokenResultName")
        const details = findChild(row,"tokenResultDetails")
        catalog.language = "zh"
        tryCompare(name,"text","多明纳里亚英雄泰菲力徽记")
        verify(details.text.includes("徽记～泰菲力"))
        verify(!details.text.includes("每当你抓一张牌时"))
        verify(catalog.cached.some(card => card.requestedLanguage === "zh"))
        mouseClick(details)
        tryCompare(picker.detailsPopup, "opened", true)
        const rules = findChild(picker.detailsPopup, "tokenDetailsRulesText")
        tryVerify(() => rules.text.includes("每当你抓一张牌时"))
        catalog.metadata.zh.oracleText += " 元数据更新。"
        catalog.imageRevision++
        tryVerify(() => rules.text.includes("元数据更新。"))
        picker.detailsPopup.close()
        tryCompare(picker.detailsPopup, "opened", false)
        mouseClick(findChild(row,"createTokenResultButton"))
        compare(selection.name,emblem.name)
        compare(selection.typeLine,emblem.typeLine)
        compare(selection.oracleText,emblem.oracleText)
    }

    function test_hoverFallbackIncludesLocalizedRules() {
        catalog.language = "zh"
        catalog.artAvailable = false
        picker.open()
        tryCompare(picker,"opened",true)
        const thumbnail = findChild(rowAt(1),"tokenResultThumbnail")
        mouseMove(testWindow,1,1)
        mouseMove(thumbnail,thumbnail.width/2,thumbnail.height/2)
        const preview = findChild(picker,"tokenArtPreview")
        tryCompare(preview,"visible",true)
        const fallback = findChild(preview,"cardHoverPreviewFallbackText")
        verify(fallback.visible)
        verify(fallback.text.includes("每当你抓一张牌时"))
        verify(fallback.text.includes("徽记～泰菲力"))
        catalog.language = "en"
        tryVerify(() => fallback.text.includes(emblem.oracleText))
    }

    function test_pickerOffersScrollableFullRulesBesideReadyArt_data() {
        return [{tag:"thumbnail",scale:1,entry:"tokenResultThumbnail"},
                {tag:"rules-compact",scale:1.5,entry:"tokenResultDetails"}]
    }

    function test_explicitTokenInspectionTakesPriorityOverBackgroundBatch() {
        picker.open()
        tryCompare(picker,"opened",true)
        const row = rowAt(1)
        mouseMove(testWindow,1,1)
        catalog.prioritized = []
        picker.cacheDisplayedTokens()
        verify(catalog.cached.length > 0)
        compare(catalog.prioritized.length,0,"Background results must remain low priority")
        const thumbnail = findChild(row,"tokenResultThumbnail")
        mouseMove(thumbnail,thumbnail.width/2,thumbnail.height/2)
        tryCompare(catalog,"prioritized",[picker.copyToken(emblem,false)])
        catalog.prioritized = []
        catalog.language = "zh"
        compare(catalog.prioritized.length,1)
        compare(catalog.prioritized[0].name,emblem.name)
        catalog.prioritized = []
        mouseClick(findChild(row,"tokenResultDetails"))
        tryCompare(picker.detailsPopup,"opened",true)
        compare(catalog.prioritized.length,1)
        compare(catalog.prioritized[0].name,emblem.name)
        compare(catalog.prioritized[0].kind,"emblem")
        picker.detailsPopup.close()
        tryCompare(picker.detailsPopup,"opened",false)
        catalog.prioritized = []
        mouseClick(findChild(row,"createTokenResultButton"))
        compare(catalog.prioritized.length,1)
        compare(catalog.prioritized[0].name,emblem.name)
        compare(catalog.prioritized[0].oracleText,emblem.oracleText)
        compare(selection.name,emblem.name)
    }

    function test_emblemBrowserPrioritizesOnlySelectedIdentity() {
        const second = Object.assign({},emblem,{id:"second",name:"Another Emblem"})
        controller.battlefieldSeats = [{seat:0,displayName:"Alice",emblems:[emblem,second]}]
        browser.showSeat(0)
        tryCompare(browser,"opened",true)
        compare(catalog.prioritized.length,1)
        compare(catalog.prioritized[0].name,emblem.name)
        compare(catalog.prioritized[0].kind,"emblem")
        const list = findChild(browser,"emblemBrowserList")
        tryVerify(() => list.itemAtIndex(1) !== null)
        catalog.prioritized = []
        mouseClick(findChild(list.itemAtIndex(1),"selectEmblemsecond"))
        compare(catalog.prioritized.length,1)
        compare(catalog.prioritized[0].name,second.name)
        catalog.prioritized = []
        catalog.language = "zh"
        compare(catalog.prioritized.length,1)
        compare(catalog.prioritized[0].name,second.name)
    }

    function test_pickerOffersScrollableFullRulesBesideReadyArt(data) {
        Theme.uiScale = data.scale
        testWindow.width = 1000
        testWindow.height = 720
        catalog.language = "zh"
        catalog.metadata.zh.oracleText = ("每当你抓一张牌时，放逐目标由对手操控的永久物。\n\n").repeat(30) + "完整规则末尾。"
        catalog.imageRevision++
        picker.preferredTokens = [emblem]
        picker.open()
        tryCompare(picker,"opened",true)
        mouseClick(findChild(rowAt(0),data.entry))
        const detail = picker.detailsPopup
        tryCompare(detail,"opened",true)
        verify(picker.opened)
        verify(waitForRendering(detail.contentItem))
        const rules = findChild(detail,"tokenDetailsRulesText")
        const scroll = findChild(detail,"tokenDetailsRulesScroll")
        const art = findChild(detail,"tokenDetailsArt")
        tryCompare(art,"status",Image.Ready)
        verify(rules.text.endsWith("完整规则末尾。"))
        verify(scroll.contentHeight>scroll.height)
        mouseWheel(scroll,scroll.width/2,scroll.height/2,0,-120)
        tryVerify(() => scroll.contentY>0)
        scroll.contentY = scroll.contentHeight-scroll.height
        verify(scroll.atYEnd)
        for (const control of [scroll,art,findChild(detail,"closeTokenDetailsButton")]) {
            verify(control.width>0 && control.height>0)
            const point = control.mapToItem(testWindow.contentItem,0,0)
            verify(point.x>=0 && point.y>=0)
            verify(point.x+control.width<=testWindow.width && point.y+control.height<=testWindow.height)
        }
        catalog.language = "en"
        tryVerify(() => rules.text.includes(emblem.oracleText))
        tryCompare(scroll,"contentY",0)
        compare(detail.card.name,emblem.name)
        testWindow.requestActivate()
        tryCompare(testWindow,"active",true)
        tryCompare(detail,"activeFocus",true)
        keyClick(Qt.Key_Escape)
        tryCompare(detail,"opened",false)
        verify(picker.opened,"Escape should dismiss only the topmost detail popup")
        detail.showCard(emblem)
        tryCompare(detail,"opened",true)
        picker.close()
        tryCompare(detail,"opened",false)
    }

    function test_browserFitsCompactLargeScale() {
        Theme.uiScale = 1.5
        browser.showSeat(0)
        tryCompare(browser,"opened",true)
        verify(waitForRendering(browser.contentItem))
        verify(browser.y >= 0)
        verify(browser.y+browser.height <= testWindow.height)
        const art = findChild(browser,"emblemBrowserArt")
        verify(art.width>0 && art.height>0)
        const close = findChild(browser,"closeEmblemBrowserButton")
        const point = close.mapToItem(testWindow.contentItem,0,0)
        verify(point.x>=0 && point.y>=0)
        verify(point.y+close.height <= testWindow.height)
    }
}
