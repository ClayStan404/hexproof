// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "TableOverlayLayer"
    width: 800
    height: 600
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 800
        height: 600
        visible: true
        MouseArea {
            id: backgroundInput
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            property int clicks: 0
            onClicked: clicks++
        }
    }

    QtObject {
        id: fakeWs
        property bool sideboarding: false
        property bool reconnecting: false
        property int reconnectSecondsRemaining: 179
    }
    QtObject {
        id: catalog
        property int imageRevision: 0
        property string language: "en"
        property var requests: []
        property bool missingBack: false
        function imageSource(name, set, number) {
            requests.push([name,set,number])
            if (name === "Back" && missingBack) return ""
            return "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="63" height="88"><rect width="63" height="88" fill="' + (name === "Back" ? "blue" : "red") + '"/></svg>')
        }
        function cardFaces(name, set, number) {
            if (name !== "Front") return []
            return [{name:"Front", faceName:"", displayName:"Front", setCode:set, collectorNumber:number},
                {name:"Back", faceName:"Back", displayName:"Back", setCode:set, collectorNumber:number,
                    oracleText: "Back rules. ".repeat(90)}]
        }
    }

    Item {
        id: fakeTable
        parent: testWindow.contentItem
        width: 800
        height: 600
        property var wsModel: fakeWs
        property var gameSession: fakeWs
        property var presentation: presentationController
        property var cardCatalogModel: catalog
        property url cardBackSource: ""
        property bool tableModalOpen: false
        property alias hoverPreviewVisible: presentationController.hoverPreviewVisible
        property alias hoverPreviewX: presentationController.hoverPreviewX
        property alias hoverPreviewY: presentationController.hoverPreviewY
        property alias inspectedCard: presentationController.inspectedCard
        Item { id: source; x:30; y:40; width:80; height:112 }
    }
    TableCardPresentationController {
        id: presentationController
        tableRoot: fakeTable
    }

    TableOverlayLayer {
        id: overlayLayer
        parent: testWindow.contentItem
        tableController: fakeTable
    }

    function init() {
        backgroundInput.clicks = 0
        fakeWs.sideboarding = false
        fakeWs.reconnecting = false
        catalog.missingBack = false
        presentationController.reset()
        fakeTable.tableModalOpen = false
        fakeTable.hoverPreviewVisible = true
        fakeTable.hoverPreviewX = 120
        fakeTable.hoverPreviewY = 80
        fakeTable.inspectedCard = {"name": "Preview card"}
        catalog.requests = []
    }

    function test_modalShieldAndPreviewFollowTableState() {
        const shield = findChild(overlayLayer, "tableModalInputShield")
        const preview = findChild(overlayLayer, "cardHoverPreview")
        verify(!shield.visible)
        verify(preview.visible)
        compare(preview.x, 120)
        compare(preview.y, 80)

        fakeTable.tableModalOpen = true
        verify(shield.visible)
        verify(!preview.visible)
    }

    function test_reconnectOverlayKeepsCountdownAndBlocksTableInput() {
        const overlay = findChild(overlayLayer, "tableReconnectOverlay")
        const preview = findChild(overlayLayer, "cardHoverPreview")
        const countdown = findChild(overlayLayer, "tableReconnectCountdown")
        fakeWs.reconnecting = true
        tryCompare(overlay, "visible", true)
        compare(countdown.text, "Table actions are paused · 2:59 remaining")
        verify(!preview.visible)
        verify(waitForRendering(overlay))
        mouseClick(backgroundInput, 20, 20)
        compare(backgroundInput.clicks, 0)
        fakeWs.reconnecting = false
        tryCompare(overlay, "visible", false)
        mouseClick(backgroundInput, 20, 20)
        compare(backgroundInput.clicks, 1)
    }

    function test_hidesFaceDownPreviewName() {
        catalog.requests = []
        fakeTable.inspectedCard = {"name": "Willbender", "faceDown": true}
        const gallery = findChild(overlayLayer, "cardHoverPreviewFaces")
        compare(gallery.faceCount, 0)
        verify(findChild(overlayLayer, "cardHoverPreviewName") === null)
        verify(findChild(overlayLayer, "cardHoverPreviewHiddenArt").visible)
        verify(catalog.requests.every(row => row[0] !== "Willbender"),
            "Hiding a card must not request art for its retained private identity")
    }
    function test_multifacePreviewShowsBothImagesWithoutChangingCard() {
        const card = {id:"physical-card", name:"Front", setCode:"TST", collectorNumber:"9"}
        presentationController.inspectCard(card, source)
        const preview = findChild(overlayLayer, "cardHoverPreview")
        const front = findChild(preview, "cardHoverPreviewArt")
        const reverse = findChild(preview, "cardHoverPreviewArt-1")
        tryCompare(front, "status", Image.Ready)
        tryCompare(reverse, "status", Image.Ready)
        verify(String(front.source) !== String(reverse.source))
        compare(presentationController.facePreview.displayFaces.map(face => face.name), ["Front", "Back"])
        verify(findChild(preview, "viewOtherFaceButton") === null)
        mouseMove(source)
        presentationController.hideCardPreview(source)
        mouseMove(reverse)
        wait(380)
        verify(preview.visible)
        compare(fakeTable.inspectedCard.name, "Front")
        compare(card.faceName, undefined)
        verify(catalog.requests.some(row => row[0] === "Back" && row[1] === "TST" && row[2] === "9"))
        presentationController.hideCardPreview()
        verify(!preview.visible)
    }
    function test_uncachedBackShowsIndependentBoundedFallback() {
        catalog.missingBack = true
        presentationController.inspectCard({id:"physical-card", name:"Front", setCode:"TST", collectorNumber:"9"}, source)
        const preview = findChild(overlayLayer, "cardHoverPreview")
        const front = findChild(preview, "cardHoverPreviewArt")
        const reverse = findChild(preview, "cardHoverPreviewArt-1")
        const fallback = findChild(preview, "cardHoverPreviewName-1")
        tryCompare(front, "status", Image.Ready)
        compare(reverse.status, Image.Null)
        verify(fallback.visible)
        verify(fallback.text.startsWith("Back"))
        verify(fallback.text.includes("Back rules."))
        verify(fallback.clip)
        const corner = fallback.mapToItem(preview, fallback.width, fallback.height)
        verify(corner.x <= preview.width && corner.y <= preview.height)
        compare(fakeTable.inspectedCard.name, "Front")
    }
    function test_bothArtBodiesPassInputAndHoverStaysLocal() {
        const card = {id:"physical-card", name:"Front", setCode:"TST", collectorNumber:"9"}
        presentationController.inspectCard(card, source)
        const preview = findChild(overlayLayer, "cardHoverPreview")
        const front = findChild(preview, "cardHoverPreviewArt")
        const reverse = findChild(preview, "cardHoverPreviewArt-1")
        verify(waitForRendering(preview))
        mouseClick(front, front.width / 2, front.height / 2)
        compare(backgroundInput.clicks, 1)
        mouseMove(reverse, reverse.width / 2, reverse.height / 2)
        tryCompare(presentationController, "previewHeld", true)
        presentationController.hideCardPreview(source)
        wait(400)
        verify(preview.visible)
        mouseClick(reverse, reverse.width / 2, reverse.height / 2)
        compare(backgroundInput.clicks, 2)
        compare(fakeTable.inspectedCard.name, "Front")
        compare(card.faceName, undefined)
        presentationController.hideCardPreview()
        verify(!preview.visible)
    }
}
