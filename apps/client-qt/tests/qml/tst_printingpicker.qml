// SPDX-License-Identifier: GPL-3.0-or-later
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
            property var faces: ({})
            signal cardCacheFinished(string name, string setCode,
                                     string collectorNumber, bool success)
            function imageSource(name, setCode, collectorNumber) {
                return cached[String(setCode) + "/" + String(collectorNumber)]
                       || fallbackSource
            }
            function printingImageSource(name, setCode, collectorNumber) {
                return cached[name + "/" + setCode + "/" + collectorNumber]
                       || cached[String(setCode) + "/" + String(collectorNumber)] || ""
            }
            function cardFaces(name, setCode, collectorNumber) { return faces[name] || [] }
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

    function previewArt(scope, name) {
        const lookup = item => {
            if (item.objectName === name) return item
            for (const child of item.children || []) {
                const found = lookup(child)
                if (found) return found
            }
            return null
        }
        const boundary = scope.contentItem || scope
        tryVerify(() => lookup(boundary) !== null)
        return lookup(boundary)
    }

    function init() {
        testWindow.requestActivate()
        tryCompare(testWindow, "active", true)
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
        fakeCatalog.faces = ({})
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
        picker.open()
        tryCompare(picker, "opened", true)
    }

    function cleanup() {
        picker.close()
        Theme.uiScale = 1
        testWindow.width = 1100
        testWindow.height = 760
    }

    function test_missingArtMessageFitsCompactPreview() {
        testWindow.width = 900
        testWindow.height = 620
        Theme.uiScale = 1.5
        picker.currentImageSource = ""
        picker.open()
        tryVerify(() => picker.opened)
        waitForRendering(picker.contentItem)
        const area = findChild(picker, "printingPreviewArea")
        const message = previewArt(picker, "printingPreviewFallback")
        verify(message.visible)
        const point = message.mapToItem(area, 0, 0)
        verify(point.y >= 0)
        verify(point.y + message.height <= area.height)
    }

    function test_previewsVersionBeforeConfirming() {
        picker.open()
        tryVerify(() => picker.opened)
        verify(picker.width >= Theme.size(900))

        const previewImage = previewArt(picker, "printingPreviewImage")
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

        // Use real local art distinct from the current printing. A nonexistent
        // asynchronous image can emit a warning after this test has returned.
        const selectedSource = Qt.resolvedUrl("../../assets/icons/hexproof.png").toString()
        verify(selectedSource !== testImage)
        fakeCatalog.cached = { "2X2/117": selectedSource }
        fakeCatalog.imageRevision++
        compare(picker.previewImageSource, selectedSource)
        verify(!picker.waitingForPreview)
        tryCompare(previewArt(picker, "printingPreviewImage"), "status", Image.Ready)
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

    function test_allFacesUseExactPrintingsAndPreserveChoice_data() {
        return [{tag: "desktop", width: 1100, height: 760, scale: 1},
                {tag: "compact-scaled", width: 900, height: 620, scale: 1.8}]
    }

    function test_allFacesUseExactPrintingsAndPreserveChoice(data) {
        testWindow.width = data.width
        testWindow.height = data.height
        Theme.uiScale = data.scale
        const front = {name: "Front Card", displayName: "Front Card",
                       setCode: "FCE", collectorNumber: "1", typeLine: "Creature"}
        const back = {name: "Meld Result", faceName: "Meld Result",
                      setCode: "FCE", collectorNumber: "2b"}
        fakeCatalog.faces = {"Front Card": [front, back]}
        fakeCatalog.fallbackSource = testImage
        picker.catalogModel = fakeCatalog
        picker.cardName = front.name
        picker.currentSetCode = front.setCode
        picker.currentCollectorNumber = front.collectorNumber
        picker.previewPrinting = front
        picker.open()
        tryVerify(() => picker.opened)
        const controller = findChild(picker, "printingFacePreviewController")
        const first = previewArt(picker, "printingPreviewImage")
        const second = previewArt(picker, "printingPreviewImage-1")
        verify(first && second)
        compare(findChild(picker, "viewOtherFaceButton"), null)
        compare(controller.displayFaces.map(face => face.card.name), [front.name, back.name])
        compare(picker.previewImageSource, testImage)
        compare(String(second.source), "", "Missing reverse art cannot reuse the current front")
        verify(picker.waitingForPreview)
        verify(fakeCatalog.cacheRequests.some(card => card.name === back.name
            && card.collectorNumber === "2b" && card.exactArt))
        compare(picker.previewPrinting, front)
        compare(chosenSpy.count, 0)
        const backSource = Qt.resolvedUrl("../../assets/icons/hexproof.png").toString()
        fakeCatalog.cached = {"Meld Result/FCE/2b": backSource}
        fakeCatalog.cardCacheFinished(back.name, "FCE", "2b", true)
        tryCompare(second, "status", Image.Ready)
        compare(String(second.source), backSource)
        compare(picker.previewImageSource, testImage)
        verify(!picker.waitingForPreview)
        verify(waitForPolish(testWindow))
        const area = findChild(picker, "printingPreviewArea")
        const firstPoint = first.mapToItem(area.contentItem.contentItem, 0, 0)
        const secondPoint = second.mapToItem(area.contentItem.contentItem, 0, 0)
        if (data.scale === 1) {
            compare(firstPoint.y, secondPoint.y)
            verify(secondPoint.x > firstPoint.x)
        } else {
            verify(secondPoint.y > firstPoint.y)
            verify(area.contentItem.contentHeight > area.height)
        }
        picker.currentSetCode = "OLD"
        mouseClick(findChild(picker, "usePrintingButton"))
        compare(chosenSpy.count, 1)
        compare(chosenSpy.signalArguments[0][0], front)
        tryVerify(() => !picker.opened)
    }

    function test_printingChangeReplacesAllFaces() {
        const front = {name: "Front Card", setCode: "FCE", collectorNumber: "1"}
        fakeCatalog.faces = {"Front Card": [front,
            {name: "Reverse Card", faceName: "Reverse Card", setCode: "FCE", collectorNumber: "1"}]}
        picker.catalogModel = fakeCatalog
        picker.previewPrinting = front
        picker.open()
        tryVerify(() => picker.opened)
        const controller = findChild(picker, "printingFacePreviewController")
        compare(controller.displayFaces.length, 2)
        picker.previewPrinting = {name: "Single Face", setCode: "ONE", collectorNumber: "3"}
        compare(controller.displayFaces.length, 1)
        compare(controller.displayFaces[0].card.collectorNumber, "3")
        const gallery = findChild(picker, "printingFaceGallery")
        compare(gallery.faceCount, 1)
        compare(gallery.faceArt(1), null)
        compare(chosenSpy.count, 0)
    }

    function test_missingBackDoesNotInheritLocalFrontImageUrl() {
        // Production cardFaces records carry each printing's identity, but do
        // not include the printing choice's imageUrl fallback.
        const front = {name: "Front Card", setCode: "FCE", collectorNumber: "1"}
        const back = {name: "Reverse Card", faceName: "Reverse Card",
                      setCode: "FCE", collectorNumber: "1"}
        fakeCatalog.faces = {"Front Card": [front, back]}
        picker.catalogModel = fakeCatalog
        picker.cardName = front.name
        picker.currentSetCode = "OLD"
        picker.currentImageSource = ""
        picker.previewPrinting = Object.assign({}, front, {imageUrl: testImage})

        const first = previewArt(picker, "printingPreviewImage")
        const second = previewArt(picker, "printingPreviewImage-1")
        const fallback = previewArt(picker, "printingPreviewFallback-1")
        tryCompare(first, "status", Image.Ready)
        compare(picker.previewImageSource, testImage)
        compare(String(second.source), "")
        compare(second.status, Image.Null)
        verify(fallback.visible)
        verify(fallback.text.includes(back.name))
        verify(!fallback.text.includes(front.name))
        verify(picker.waitingForPreview)
        compare(fakeCatalog.cacheRequests.length, 1)
        compare(fakeCatalog.cacheRequests[0].name, back.name)
        compare(fakeCatalog.cacheRequests[0].setCode, back.setCode)
        compare(fakeCatalog.cacheRequests[0].collectorNumber, back.collectorNumber)
        verify(fakeCatalog.cacheRequests[0].exactArt)
        compare(chosenSpy.count, 0)

        const backSource = Qt.resolvedUrl("../../assets/icons/hexproof.png").toString()
        fakeCatalog.cached = {"Reverse Card/FCE/1": backSource}
        fakeCatalog.cardCacheFinished(back.name, back.setCode, back.collectorNumber, true)
        tryCompare(second, "status", Image.Ready)
        compare(String(second.source), backSource)
        compare(String(first.source), testImage)
        verify(!fallback.visible)
        verify(!picker.waitingForPreview)
    }
}
