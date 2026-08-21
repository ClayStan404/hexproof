// SPDX-License-Identifier: GPL-2.0-only
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
            function imageSource(name, setCode, collectorNumber) {
                return "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            }
            function cardTypeLine(name, setCode, collectorNumber) {
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
        cardRow.catalogModel = null
        cardRow.card = sampleCard()
        cardRow.width = 900
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

    function test_rowsStayCompact() {
        compare(cardRow.implicitHeight, Theme.size(66))
        cardRow.sideboard = true
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

    function test_typeLineFallsBackToCatalogWhenDeckHasNone() {
        cardRow.catalogModel = fakeCatalog
        cardRow.card = sampleCard({ "typeLine": "" })
        compare(cardRow.resolvedTypeLine, "Instant")
    }
}
