// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"
import "../../qml/components"

TestCase {
    name: "DeckEditorIdentity"
    when: windowShown

    QtObject {
        id: progressCatalog
        property bool busy: false
        property bool cacheProgressActive: false
        property bool searching: false
        property bool tokenSearching: false
        property bool searchPreviewBusy: false
        property real progress: 0.375
        property string status: "Caching card images…"
    }

    SignalSpy { id: deckCallSpy; target: deckLibrary; signalName: "capturedCallsChanged" }

    ApplicationWindow {
        id: testWindow
        width: 1280
        height: 800
        visible: true

        function popScreen() {}
        function pushScreen() {}
        function showBanner() {}

        DeckEditor {
            id: editor
            anchors.fill: parent
        }
    }

    function init() {
        deckLibrary.resetCapturedCalls()
        deckLibrary.currentDeckTableMode = "modern"
    }

    function cleanup() {
        findChild(editor, "deckEditorCacheProgress").catalogModel = Qt.binding(() => cardCatalog)
        progressCatalog.busy = false
        progressCatalog.cacheProgressActive = false
        testWindow.width = 1280
        testWindow.height = 800
        Theme.uiScale = 1
        Theme.uiTheme = "classic"
        deckLibrary.currentDeckTableMode = "modern"
        findChild(editor, "exportCurrentDeckDialog").close()
        findChild(editor, "currentDeckArtExportDialog").close()
    }

    function findInTree(item, predicate) {
        if (predicate(item)) return item
        for (const child of item.children || []) {
            const found = findInTree(child, predicate)
            if (found) return found
        }
        return null
    }

    function editorRect(item) { return item.mapToItem(editor, 0, 0, item.width, item.height) }

    function compareEditorRect(item, expected, label) {
        const actual = editorRect(item)
        compare(actual.x, expected.x, label + " x")
        compare(actual.y, expected.y, label + " y")
        compare(actual.width, expected.width, label + " width")
        compare(actual.height, expected.height, label + " height")
    }

    function test_progressChangesKeepFirstClickOnSamePrinting_data() {
        return [{tag: "warm", cold: false, width: 1280, height: 800, scale: 1},
                {tag: "cold", cold: true, width: 1280, height: 800, scale: 1},
                {tag: "warm scaled", cold: false, width: 1600, height: 1000, scale: 1.35},
                {tag: "cold scaled", cold: true, width: 1600, height: 1000, scale: 1.35},
                {tag: "warm compact", cold: false, width: 900, height: 800, scale: 1.35},
                {tag: "cold compact", cold: true, width: 900, height: 800, scale: 1.35}]
    }

    function test_progressChangesKeepFirstClickOnSamePrinting(data) {
        testTranslations.setLanguage("en")
        testWindow.width = data.width
        testWindow.height = data.height
        Theme.uiScale = data.scale
        Theme.uiTheme = "glass"
        const progress = findChild(editor, "deckEditorCacheProgress")
        progressCatalog.busy = data.cold
        progressCatalog.cacheProgressActive = data.cold
        progress.catalogModel = progressCatalog
        const gallery = findChild(editor, "groupedDeckGallery")
        verify(waitForRendering(gallery))
        gallery.forceLayout()
        tryVerify(() => gallery.itemAtIndex(0) !== null)
        const card = findInTree(gallery.itemAtIndex(0), item => item.card
            && typeof item.incrementRequested === "function"
            && item.card.setCode === "M11" && item.card.collectorNumber === "149")
        verify(card !== null)
        const plus = findInTree(card, item => item.text === "+" && typeof item.clicked === "function")
        verify(plus !== null)
        const plusInGallery = plus.mapToItem(gallery, plus.width / 2, plus.height / 2)
        gallery.contentY = Math.round(Math.max(gallery.originY, Math.min(
            gallery.originY + gallery.contentHeight - gallery.height,
            gallery.contentY + Math.max(0, plusInGallery.y - gallery.height + Theme.size(20)))))
        verify(waitForRendering(gallery))
        const galleryRect = editorRect(gallery)
        const plusRect = editorRect(plus)
        const contentY = gallery.contentY
        const clickPoint = plus.mapToItem(editor, plus.width / 2, plus.height / 2)
        mouseMove(editor, clickPoint.x, clickPoint.y)
        progressCatalog.busy = false
        progressCatalog.cacheProgressActive = !data.cold
        verify(waitForRendering(editor))
        compareEditorRect(gallery, galleryRect, "Gallery after progress transition")
        compareEditorRect(plus, plusRect, "Count action after progress transition")
        compare(gallery.contentY, contentY)
        deckCallSpy.clear()
        mouseClick(editor, clickPoint.x, clickPoint.y)
        compare(deckCallSpy.count, 1, "The first click at the saved scene position must activate once")
        compare(deckLibrary.lastCountChange, ["Lightning Bolt", "M11", "149", false, 1])

        progressCatalog.busy = true
        progressCatalog.cacheProgressActive = true
        verify(waitForRendering(editor))
        verify(progress.visible)
        compare(findChild(progress, "cardCacheProgressStatus").text, "Caching card images…")
        compare(findChild(progress, "cardCacheProgressPercent").text, "38%")
        compareEditorRect(gallery, galleryRect, "Gallery with explicit progress")
        compareEditorRect(plus, plusRect, "Count action with explicit progress")
        progressCatalog.busy = false
        progressCatalog.cacheProgressActive = false
        verify(waitForRendering(editor))
        verify(!progress.visible)
        compareEditorRect(gallery, galleryRect, "Gallery after completion")
        compareEditorRect(plus, plusRect, "Count action after completion")
        compare(gallery.contentY, contentY)
    }

    function test_editorArtExportTargetsCurrentDeck() {
        waitForPolish(testWindow)
        mouseClick(findChild(editor, "deckEditorMoreButton"))
        const overflow = findChild(editor, "deckEditorMoreMenu")
        tryVerify(() => overflow.opened)
        mouseClick(findChild(editor, "exportCurrentDeckButton"))
        const menu = findChild(editor, "exportCurrentDeckDialog")
        tryVerify(() => menu.opened)
        waitForPolish(testWindow)
        const body = findChild(menu, "deckExportBody")
        body.contentY = Math.max(0, body.contentHeight - body.height)
        waitForPolish(testWindow)
        mouseClick(findChild(menu, "exportDeckArtButton"))
        const artDialog = findChild(editor, "currentDeckArtExportDialog")
        tryVerify(() => artDialog.opened)
        compare(artDialog.deckName, deckLibrary.currentDeckName)
        compare(artDialog.cardRequests.length,
                deckLibrary.mainCards.length + deckLibrary.sideboardCards.length)
        compare(artDialog.cardRequests[0].setCode, "M11")
    }

    function test_narrowEditorControlsStayInsidePanel_data() {
        return [{tag: "minimum", width: 900, height: 620, scale: 1},
                {tag: "scaled", width: 1280, height: 800, scale: 1.25},
                {tag: "large", width: 900, height: 620, scale: 1.5},
                {tag: "maximum", width: 900, height: 620, scale: 1.8}]
    }

    function test_narrowEditorControlsStayInsidePanel(data) {
        testWindow.width = data.width
        testWindow.height = data.height
        Theme.uiScale = data.scale
        waitForRendering(editor)
        const search = findChild(editor, "deckEditorSearchButton")
        verify(search !== null && search.visible)
        const searchPoint = search.mapToItem(testWindow.contentItem, 0, 0)
        verify(searchPoint.x >= 0 && searchPoint.y >= 0
               && searchPoint.x + search.width <= testWindow.width
               && searchPoint.y + search.height <= testWindow.height,
               "Catalog search must remain reachable without scrolling the deck")
        const surface = findChild(editor, "deckEditorMainSurface")
        for (const name of ["deckEditorMoreButton", "manageConsiderButton",
                            "deckEditorSearchButton", "manageDeckTokensButton"]) {
            const item = findChild(editor, name)
            verify(item !== null, name)
            const topLeft = item.mapToItem(editor, 0, 0)
            const bottomRight = item.mapToItem(editor, item.width, item.height)
            verify(item.width > 0 && item.height > 0, name + " must be usable")
            verify(topLeft.x >= 0 && topLeft.y >= 0 && bottomRight.x <= editor.width + 1
                   && bottomRight.y <= editor.height + 1, name + " must not be clipped")
        }
        for (const name of ["deckEditorViewMode", "deckEditorGroupMode", "deckEditorSortMode"]) {
            const item = findChild(editor, name)
            verify(item !== null, name)
            const topLeft = item.mapToItem(surface, 0, 0)
            const bottomRight = item.mapToItem(surface, item.width, item.height)
            verify(item.width > 0 && item.height > 0, name + " must be usable")
            verify(topLeft.x >= 0 && topLeft.y >= 0 && bottomRight.x <= surface.width + 1
                   && bottomRight.y <= surface.height + 1, name + " must not be clipped")
        }
    }

    function test_editorActionsMatchSearchButtonStyle() {
        Theme.uiTheme = "glass"
        waitForRendering(editor)
        const search = findChild(editor, "deckEditorSearchButton")
        verify(search !== null)
        for (const name of ["deckEditorMoreButton", "manageConsiderButton"]) {
            const button = findChild(editor, name)
            verify(button !== null, name)
            compare(button.compact, search.compact)
            compare(button.variant, search.variant)
            compare(button.implicitHeight, search.implicitHeight)
        }
        verify(Theme.useGlass)
    }

    function test_headerTitleRenamesDeck() {
        waitForRendering(editor)
        const title = findChild(editor, "screenHeaderTitle")
        verify(title !== null)
        compare(title.text, deckLibrary.currentDeckName)
        mouseClick(title)
        const field = findChild(editor, "screenHeaderTitleField")
        verify(field !== null)
        tryVerify(() => field.visible)
        field.text = "Renamed editor deck"
        field.editingFinished()
        compare(deckLibrary.lastRename, "Renamed editor deck")
        verify(!field.visible)
        verify(title.visible)
    }

    function test_commanderUsesFullWidthGallery() {
        deckLibrary.currentDeckTableMode = "edh"
        waitForRendering(editor)
        verify(findChild(editor, "commanderSurface") === null)
        const sidebar = findChild(editor, "deckEditorSidebar")
        verify(sidebar !== null)
        verify(!sidebar.visible)
        const search = findChild(editor, "deckEditorSearchButton")
        const tokens = findChild(editor, "manageDeckTokensButton")
        const surface = findChild(editor, "deckEditorMainSurface")
        const body = findChild(editor, "deckEditorBody")
        verify(search !== null && tokens !== null && surface !== null && body !== null)
        verify(search.visible && tokens.visible)
        compare(search.parent, tokens.parent)
        verify(surface.width >= body.width - 2)
    }

    function test_viewGroupSortShareFilterRowOnWideEditor() {
        testWindow.width = 1280
        testWindow.height = 800
        Theme.uiScale = 1
        waitForRendering(editor)
        const surface = findChild(editor, "deckEditorMainSurface")
        const search = findChild(surface, "workbenchSearch")
        const view = findChild(editor, "deckEditorViewMode")
        const group = findChild(editor, "deckEditorGroupMode")
        const sort = findChild(editor, "deckEditorSortMode")
        verify(search !== null && view !== null && group !== null && sort !== null)
        const searchY = search.mapToItem(surface, 0, 0).y
        for (const item of [view, group, sort]) {
            const point = item.mapToItem(surface, 0, 0)
            verify(Math.abs(point.y - searchY) < Theme.size(8),
                   item.objectName + " must stay on the deck-local search row")
        }
    }

    function dropPayload(name, setCode, collectorNumber, fromSideboard) {
        return {
            "accepted": false,
            "getDataAsString": function(type) {
                if (type === "application/x-hexproof-card")
                    return name
                if (type === "application/x-hexproof-set-code")
                    return setCode
                if (type === "application/x-hexproof-collector-number")
                    return collectorNumber
                if (type === "application/x-hexproof-sideboard")
                    return fromSideboard ? "true" : "false"
                return ""
            },
            "acceptProposedAction": function() {
                this.accepted = true
            }
        }
    }

    function test_sideboardControlsForwardPrintingIdentity() {
        const sideboardList = findChild(editor, "sideboardList")
        verify(sideboardList !== null)
        tryVerify(() => sideboardList.itemAtIndex(0) !== null)
        const row = sideboardList.itemAtIndex(0)

        row.incrementRequested()
        compare(deckLibrary.lastCountChange,
                ["Counterspell", "MH2", "267", true, 1])
        row.decrementRequested()
        compare(deckLibrary.lastCountChange,
                ["Counterspell", "MH2", "267", true, -1])
        row.moveRequested()
        compare(deckLibrary.lastMove,
                ["Counterspell", "MH2", "267", false])

        row.printingRequested()
        const picker = findChild(editor, "deckPrintingPicker")
        verify(picker !== null)
        compare(picker.cardName, "Counterspell")
        compare(picker.currentSetCode, "MH2")
        compare(picker.currentCollectorNumber, "267")
        verify(picker.sideboard)
        picker.close()
    }

    function test_dropDirectionsForwardMimePrintingIdentity() {
        const toMain = dropPayload("Lightning Bolt", "2X2", "117", true)
        verify(editor.forwardDeckCardDrop(toMain, false))
        verify(toMain.accepted)
        compare(deckLibrary.lastMove,
                ["Lightning Bolt", "2X2", "117", false])

        const toSideboard = dropPayload("Lightning Bolt", "M11", "149", false)
        verify(editor.forwardDeckCardDrop(toSideboard, true))
        verify(toSideboard.accepted)
        compare(deckLibrary.lastMove,
                ["Lightning Bolt", "M11", "149", true])
    }

    function test_pickerBridgeTargetsCurrentSameNamePrinting() {
        const picker = findChild(editor, "deckPrintingPicker")
        verify(picker !== null)
        picker.showFor(deckLibrary.mainCards[1], false)
        tryVerify(() => picker.opened)
        compare(picker.currentSetCode, "2X2")
        compare(picker.currentCollectorNumber, "117")

        const printingList = findChild(picker, "printingOptions")
        verify(printingList !== null)
        compare(printingList.count, 2)
        tryVerify(() => printingList.itemAtIndex(1) !== null)
        const m11Option = printingList.itemAtIndex(1)
        mouseClick(m11Option, m11Option.width / 2, m11Option.height / 2)

        const useButton = findChild(picker, "usePrintingButton")
        verify(useButton !== null)
        verify(useButton.enabled)
        mouseClick(useButton, useButton.width / 2, useButton.height / 2)
        compare(deckLibrary.lastPrintingChange,
                ["Lightning Bolt", "2X2", "117", false,
                 "Lightning Bolt M11", "Instant M11", "M11", "149"])
    }
}
