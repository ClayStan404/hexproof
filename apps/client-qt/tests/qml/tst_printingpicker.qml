// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "PrintingPicker"
    when: windowShown

    readonly property string testImage:
        "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC"
        + "AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="

    ApplicationWindow {
        id: testWindow
        width: 1100
        height: 760
        visible: true

        PrintingPicker {
            id: picker
        }

        QtObject {
            id: fakeCatalog
            property int imageRevision: 0
            property string printingsError: ""
            property var cached: ({})
            property string fallbackSource: ""
            property var cacheRequests: []
            signal cardCacheFinished(string name, string setCode,
                                     string collectorNumber, bool success)
            function imageSource(name, setCode, collectorNumber) {
                return cached[String(setCode) + "/" + String(collectorNumber)]
                       || fallbackSource
            }
            function printingImageSource(name, setCode, collectorNumber) {
                return cached[String(setCode) + "/" + String(collectorNumber)] || ""
            }
            function cacheCardsIncrementally(cards) {
                cacheRequests = cards
            }
            function printings(name) {
                return []
            }
        }
    }

    SignalSpy {
        id: chosenSpy
        target: picker
        signalName: "chosen"
    }

    function init() {
        picker.close()
        picker.catalogModel = null
        picker.cardName = "Lightning Bolt"
        picker.currentSetCode = "M11"
        picker.currentCollectorNumber = "149"
        picker.currentImageSource = testImage
        fakeCatalog.imageRevision = 0
        fakeCatalog.printingsError = ""
        fakeCatalog.cached = ({})
        fakeCatalog.fallbackSource = ""
        fakeCatalog.cacheRequests = []
        picker.options = [{
            "name": "Lightning Bolt",
            "displayName": "Lightning Bolt",
            "typeLine": "Instant",
            "setCode": "M11",
            "collectorNumber": "149",
            "imageUrl": ""
        }, {
            "name": "Lightning Bolt",
            "displayName": "Lightning Bolt",
            "typeLine": "Instant",
            "setCode": "2X2",
            "collectorNumber": "117",
            "imageUrl": testImage
        }]
        picker.previewPrinting = picker.options[0]
        chosenSpy.clear()
    }

    function cleanup() {
        picker.close()
    }

    function test_previewsVersionBeforeConfirming() {
        picker.open()
        tryVerify(() => picker.opened)
        verify(picker.width >= Theme.size(900))

        const previewImage = findChild(picker, "printingPreviewImage")
        verify(previewImage !== null)
        tryCompare(previewImage, "status", Image.Ready)

        const printingList = findChild(picker, "printingOptions")
        verify(printingList !== null)
        compare(printingList.count, 2)
        tryVerify(() => printingList.itemAtIndex(1) !== null)
        const secondOption = printingList.itemAtIndex(1)
        mouseClick(secondOption, secondOption.width / 2, secondOption.height / 2)
        compare(picker.previewPrinting.setCode, "2X2")
        compare(picker.previewImageSource, testImage)

        const useButton = findChild(picker, "usePrintingButton")
        verify(useButton !== null)
        verify(useButton.enabled)
        mouseClick(useButton, useButton.width / 2, useButton.height / 2)
        compare(chosenSpy.count, 1)
        compare(chosenSpy.signalArguments[0][0].setCode, "2X2")
    }

    function test_doesNotPreviewRemoteHttpUrls() {
        picker.currentImageSource = ""
        picker.previewPrinting = {
            "name": "Crystal Barricade",
            "displayName": "Crystal Barricade",
            "typeLine": "Artifact Creature — Wall",
            "setCode": "FDN",
            "collectorNumber": "7",
            "imageUrl": "https://cards.scryfall.io/normal/front/9/0/example.jpg"
        }
        verify(String(picker.previewImageSource).indexOf("https:") < 0)
        verify(String(picker.previewImageSource).indexOf("http:") < 0)
    }

    function test_showsPrintingQueryErrors() {
        picker.catalogModel = fakeCatalog
        fakeCatalog.printingsError = "The local card database query failed."
        picker.showFor({
            "name": "Lightning Bolt",
            "setCode": "M11",
            "collectorNumber": "149",
            "imageSource": ""
        }, false)
        tryVerify(() => picker.opened)
        const error = findChild(picker, "printingQueryError")
        verify(error !== null)
        verify(error.visible)
        compare(picker.queryError, fakeCatalog.printingsError)
    }

    function test_cachesPreviewThroughCatalogInsteadOfRemoteImage() {
        picker.catalogModel = fakeCatalog
        picker.currentImageSource = ""
        picker.currentSetCode = ""
        picker.currentCollectorNumber = ""
        picker.previewPrinting = {
            "name": "Crystal Barricade",
            "displayName": "Crystal Barricade",
            "typeLine": "Artifact Creature — Wall",
            "setCode": "FDN",
            "collectorNumber": "7",
            "imageUrl": "https://cards.scryfall.io/normal/front/9/0/example.jpg"
        }
        compare(fakeCatalog.cacheRequests.length, 1)
        compare(fakeCatalog.cacheRequests[0].name, "Crystal Barricade")
        compare(fakeCatalog.cacheRequests[0].setCode, "FDN")
        compare(fakeCatalog.cacheRequests[0].collectorNumber, "7")
        verify(fakeCatalog.cacheRequests[0].exactArt)
        compare(picker.previewImageSource, "")
        verify(picker.waitingForPreview)

        fakeCatalog.cached = { "FDN/7": testImage }
        fakeCatalog.imageRevision++
        compare(picker.previewImageSource, testImage)
        verify(!picker.waitingForPreview)
    }

    function test_keepsWaitingUntilCachedPreviewAppears() {
        picker.catalogModel = fakeCatalog
        picker.currentImageSource = ""
        picker.currentSetCode = "M11"
        picker.currentCollectorNumber = "149"
        picker.previewPrinting = picker.options[0]
        compare(picker.previewImageSource, "")
        verify(picker.waitingForPreview)

        fakeCatalog.cached = { "M11/149": testImage }
        fakeCatalog.imageRevision++
        compare(picker.previewImageSource, testImage)
        verify(!picker.waitingForPreview)
    }

    function test_doesNotReuseCurrentArtForAnotherPrintingPreview() {
        picker.catalogModel = fakeCatalog
        picker.currentImageSource = testImage
        fakeCatalog.fallbackSource = testImage
        picker.previewPrinting = {
            "name": "Lightning Bolt",
            "displayName": "Lightning Bolt",
            "typeLine": "Instant",
            "setCode": "2X2",
            "collectorNumber": "117",
            "imageUrl": "https://cards.example.test/2x2-117.jpg"
        }

        compare(fakeCatalog.imageSource("Lightning Bolt", "2X2", "117"), testImage)
        compare(picker.previewImageSource, "")
        verify(picker.waitingForPreview)
        compare(fakeCatalog.cacheRequests.length, 1)
        compare(fakeCatalog.cacheRequests[0].setCode, "2X2")
        compare(fakeCatalog.cacheRequests[0].collectorNumber, "117")
        verify(fakeCatalog.cacheRequests[0].exactArt)

        const selectedSource = "file:///tmp/hexproof-selected-printing.png"
        fakeCatalog.cached = { "2X2/117": selectedSource }
        fakeCatalog.imageRevision++
        compare(picker.previewImageSource, selectedSource)
        verify(!picker.waitingForPreview)
    }

    function test_refreshesPreviewWhenCacheFinishedWithoutRevisionBump() {
        picker.catalogModel = fakeCatalog
        picker.currentImageSource = ""
        picker.currentSetCode = ""
        picker.currentCollectorNumber = ""
        picker.previewPrinting = {
            "name": "Crystal Barricade",
            "displayName": "Crystal Barricade",
            "typeLine": "Artifact Creature — Wall",
            "setCode": "FDN",
            "collectorNumber": "7",
            "imageUrl": "https://cards.scryfall.io/normal/front/9/0/example.jpg"
        }
        compare(picker.previewImageSource, "")
        verify(picker.waitingForPreview)

        fakeCatalog.cached = { "FDN/7": testImage }
        compare(fakeCatalog.imageRevision, 0)
        fakeCatalog.cardCacheFinished("Crystal Barricade", "FDN", "7", true)
        compare(fakeCatalog.imageRevision, 0)
        compare(picker.previewImageSource, testImage)
        verify(!picker.waitingForPreview)
    }
}
