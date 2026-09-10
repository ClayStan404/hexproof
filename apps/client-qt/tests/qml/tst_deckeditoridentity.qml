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
    }

    function cleanup() {
        testWindow.width = 1280
        testWindow.height = 800
        Theme.uiScale = 1
        findChild(editor, "exportCurrentDeckDialog").close()
        findChild(editor, "currentDeckArtExportDialog").close()
    }

    function test_editorArtExportTargetsCurrentDeck() {
        waitForPolish(testWindow)
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
        const surface = findChild(editor, "deckEditorMainSurface")
        for (const name of ["deckNameField", "exportCurrentDeckButton", "cacheCurrentDeckArtButton",
                            "manageConsiderButton", "deckEditorViewMode", "deckEditorGroupMode", "deckEditorSortMode"]) {
            const item = findChild(editor, name)
            verify(item !== null, name)
            const topLeft = item.mapToItem(surface, 0, 0)
            const bottomRight = item.mapToItem(surface, item.width, item.height)
            verify(item.width > 0 && item.height > 0, name + " must be usable")
            verify(topLeft.x >= 0 && topLeft.y >= 0 && bottomRight.x <= surface.width + 1
                   && bottomRight.y <= surface.height + 1, name + " must not be clipped")
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
