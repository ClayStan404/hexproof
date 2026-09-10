// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "DeckCardDrag"
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 1000
        height: 500
        visible: true

        property int dropCount: 0
        property int printingClicks: 0

        Item {
            id: dropTarget
            x: 550
            width: 450
            height: parent.height
        }

        QtObject {
            id: fakeCatalog
            property int imageRevision: 0
            // Mutate a plain array so instrumentation cannot invalidate the caller's binding.
            property var cachedTypeLineRequests: []
            function imageSource(name, setCode, collectorNumber) {
                return "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            }
            function cachedCardTypeLine(name, setCode, collectorNumber) {
                cachedTypeLineRequests.push([name, setCode, collectorNumber])
                return "Instant"
            }
        }

        DeckCardRow {
            id: cardRow
            x: 20
            y: 100
            width: 900
            dropTarget: dropTarget
            card: ({
                "name": "Lightning Bolt",
                "displayName": "Lightning Bolt",
                "typeLine": "Instant",
                "imageSource": "",
                "setCode": "M11",
                "collectorNumber": "149",
                "count": 4,
                "totalCount": 4,
                "commander": false
            })
            onMoveRequested: testWindow.dropCount++
            onPrintingRequested: testWindow.printingClicks++
        }
    }

    function sampleCard(overrides) {
        const card = {
            "name": "Lightning Bolt",
            "displayName": "Lightning Bolt",
            "typeLine": "Instant",
            "imageSource": "",
            "setCode": "M11",
            "collectorNumber": "149",
            "count": 4,
            "totalCount": 4,
            "commander": false
        }
        if (overrides) {
            for (const key in overrides)
                card[key] = overrides[key]
        }
        return card
    }

    function init() {
        testWindow.dropCount = 0
        testWindow.printingClicks = 0
        cardRow.sideboard = false
        cardRow.printingEnabled = false
        cardRow.customArtEnabled = false
        cardRow.considerEnabled = false
        cardRow.commanderEnabled = false
        cardRow.catalogModel = null
        fakeCatalog.cachedTypeLineRequests = []
        cardRow.card = sampleCard()
        cardRow.width = 900
    }

    function cleanup() { Theme.uiScale = 1 }

    function test_scaledActionsStayWithinRow_data() {
        return [{tag: "main-large", scale: 1.5, width: 740, sideboard: false},
                {tag: "main-maximum", scale: 1.8, width: 720, sideboard: false},
                {tag: "side-large", scale: 1.5, width: 390, sideboard: true},
                {tag: "side-maximum", scale: 1.8, width: 390, sideboard: true}]
    }

    function test_scaledActionsStayWithinRow(data) {
        Theme.uiScale = data.scale
        cardRow.width = data.width
        cardRow.sideboard = data.sideboard
        cardRow.printingEnabled = true
        cardRow.considerEnabled = true
        cardRow.customArtEnabled = true
        waitForRendering(cardRow)
        function inspect(item) {
            if (item.visible && typeof item.clicked === "function") {
                const point = item.mapToItem(cardRow, 0, 0)
                verify(point.x >= -1 && point.x + item.width <= cardRow.width + 1,
                       String(item.objectName || item.text))
                verify(point.y >= -1 && point.y + item.height <= cardRow.height + 1,
                       String(item.objectName || item.text))
            }
            for (const child of item.children || [])
                inspect(child)
        }
        inspect(cardRow)
        const printing = findChild(cardRow, data.sideboard ? "sideboardPrintingButton" : "printingButton")
        mouseClick(printing)
        compare(testWindow.printingClicks, 1)
    }

    function test_dragAcrossPanels() {
        cardRow.width = 450
        wait(100)
        const handle = findChild(cardRow, "dragHandle")
        verify(handle !== null)
        let pressedChanges = 0
        handle.pressedChanged.connect(() => pressedChanges++)
        mouseDrag(handle, handle.width / 2, handle.height / 2,
                  350, 0, Qt.LeftButton, Qt.NoModifier, 30)
        compare(pressedChanges, 2)
        tryCompare(testWindow, "dropCount", 1)
    }

    function test_dragMimeCarriesPrintingIdentity() {
        compare(cardRow.Drag.mimeData["application/x-hexproof-card"], "Lightning Bolt")
        compare(cardRow.Drag.mimeData["application/x-hexproof-set-code"], "M11")
        compare(cardRow.Drag.mimeData["application/x-hexproof-collector-number"], "149")
        compare(cardRow.Drag.mimeData["application/x-hexproof-sideboard"], "false")
    }

    function test_rowsStayCompact() {
        waitForRendering(cardRow)
        compare(cardRow.implicitHeight, Theme.size(66))
        cardRow.sideboard = true
        waitForRendering(cardRow)
        compare(cardRow.implicitHeight, Theme.size(68))
        cardRow.sideboard = false
    }

    function test_offersPrintingChoiceWithoutSetCode() {
        cardRow.printingEnabled = true
        cardRow.card = sampleCard({
            "setCode": "",
            "collectorNumber": ""
        })
        const button = findChild(cardRow, "printingButton")
        verify(button !== null)
        verify(button.visible)
        compare(button.text, "Select printing")
        mouseClick(button, button.width / 2, button.height / 2)
        compare(testWindow.printingClicks, 1)
    }

    function test_thumbnailOpensPrintingPickerAndShowsCachedArt() {
        cardRow.printingEnabled = true
        cardRow.catalogModel = fakeCatalog
        cardRow.card = sampleCard({ "imageSource": "" })
        const art = findChild(cardRow, "cardArt")
        verify(art !== null)
        verify(String(art.source).indexOf("data:image") >= 0)
        const thumbnail = findChild(cardRow, "cardThumbnail")
        verify(thumbnail !== null)
        mouseClick(thumbnail, thumbnail.width / 2, thumbnail.height / 2)
        compare(testWindow.printingClicks, 1)
    }

    function test_typeLineUsesCacheOnlyLookupWhenDeckHasNone() {
        cardRow.catalogModel = fakeCatalog
        cardRow.card = sampleCard({ "typeLine": "" })
        compare(cardRow.resolvedTypeLine, "Instant")
        verify(fakeCatalog.cachedTypeLineRequests.length > 0)
        compare(fakeCatalog.cachedTypeLineRequests[0], ["Lightning Bolt", "M11", "149"])
    }
}
