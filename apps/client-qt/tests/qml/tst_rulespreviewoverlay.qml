// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "RulesPreviewOverlay"
    when: windowShown
    ApplicationWindow {
        id: window
        width: 1100; height: 850; visible: true
        property int backgroundClicks: 0
        AppButton {
            id: backgroundButton
            x: 920; y: 770; width: 150; height: 45
            text: "Background action"
            onClicked: window.backgroundClicks++
        }
        AppPopup {
            id: modal
            width: 950; height: 730
            contentItem: Item { id: modalContent }
        }
    }
    QtObject {
        id: transport
        function respondRulesPrompt(id, response) {}
        function respondRulesPromptWithCards(id, response, cards) {}
        function respondRulesPromptWithScry(id, piles) {}
        function respondRulesPromptWithOrder(id, order) {}
    }
    Component { id: browser; RulesCardBrowser {
        cardModel: testRulesPrompt.session.promptCards
        cardCatalogModel: null
        promptId: 1
    } }
    Component { id: selection; RulesCardSelectionPrompt {
        wsModel: transport
        cardModel: testRulesPrompt.session.promptCards
        cardCatalogModel: null
        promptId: 1
        minimumSelections: 0; maximumSelections: 1; confirmationText: "Confirm"
    } }
    Component { id: reveal; RulesRevealPrompt {
        wsModel: transport
        cardModel: testRulesPrompt.session.promptCards
        cardCatalogModel: null
        promptId: 1
    } }
    Component { id: scry; RulesScryPrompt {
        wsModel: transport
        cardModel: testRulesPrompt.session.promptCards
        cardCatalogModel: null
        promptId: 1
        destinations: ["libraryTop", "libraryBottom"]
    } }
    Component { id: order; RulesOrderPrompt {
        wsModel: transport
        orderModel: testRulesPrompt.session.promptOrderItems
        cardCatalogModel: null
        promptId: 1
    } }
    Component { id: context; RulesPromptContext {
        cardCatalogModel: null
        sourceCardModel: testRulesPrompt.session.promptContextCards
        targetModel: testRulesPrompt.session.promptContextTargets
        contextText: ""
        promptId: 1
    } }
    Component {
        id: fittedHover
        Item {
            id: viewport
            Item { id: source; x: 20; y: 20; width: 50; height: 70 }
            QtObject {
                id: tableController
                property bool roomConnected: true
                property bool sideboarding: false
                property bool priorityInputBlocked: false
                property url cardBackSource: ""
            }
            QtObject {
                id: faces
                property var displayFaces: [
                    {name:"Delver of Secrets", imageSource:"data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' width='63' height='88'><rect width='63' height='88' fill='red'/></svg>"},
                    {name:"Insectile Aberration", imageSource:"data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' width='63' height='88'><rect width='63' height='88' fill='blue'/></svg>"}
                ]
            }
            QtObject {
                id: inspector
                property var previewSource: source
                property string previewCardId: "delver"
                property bool hasCard: true
                property bool hasIdentity: true
                property bool previewHeld: false
            property bool previewNeedsInspection: false
                property string persistentSummary: ""
                property var facePreview: faces
                function hidePreview() { previewCardId = "" }
            }
            RulesCardHoverPreview {
                tableController: tableController
                inspector: inspector
            }
        }
    }
    function init() {
        window.requestActivate()
        tryCompare(window, "active", true)
        window.backgroundClicks = 0
        testRulesPrompt.clear()
        modal.close()
    }
    function cleanup() { modal.close() }
    function test_bothHoverFacesFitSmallViewport_data() {
        return [{tag:"compact-landscape", width:600, height:450, columns:2},
            {tag:"narrow-portrait", width:320, height:600, columns:1}]
    }
    function test_bothHoverFacesFitSmallViewport(data) {
        const viewport = createTemporaryObject(fittedHover, window.contentItem,
            {width:data.width, height:data.height})
        verify(viewport !== null)
        const preview = findChild(viewport, "rulesCardHoverPreview")
        const gallery = findChild(preview, "rulesCardHoverPreviewGallery")
        tryCompare(preview, "visible", true)
        compare(gallery.columnCount, data.columns)
        verify(preview.x >= 0 && preview.y >= 0)
        verify(preview.x + preview.width <= viewport.width)
        verify(preview.y + preview.height <= viewport.height)
        for (let index = 0; index < 2; ++index) {
            const art = gallery.faceArt(index)
            verify(art !== null && art.visible)
            tryCompare(art, "status", Image.Ready)
            verify(art.width >= 180 && art.height >= 250)
            const point = art.mapToItem(viewport, 0, 0)
            verify(point.x >= 0 && point.y >= 0)
            verify(point.x + art.width <= viewport.width)
            verify(point.y + art.height <= viewport.height)
        }
        compare(findChild(preview, "viewOtherFaceButton"), null)
    }
    function test_inactivePromptCannotInterceptWindowInput_data() {
        return [{tag:"browser", component:browser}, {tag:"selection", component:selection},
            {tag:"reveal", component:reveal}, {tag:"scry", component:scry}, {tag:"order", component:order},
            {tag:"context", component:context}]
    }
    function test_inactivePromptCannotInterceptWindowInput(data) {
        const prompt = createTemporaryObject(data.component, window.contentItem,
            {width:900, height:650, visible:false})
        verify(prompt !== null)
        waitForRendering(window.contentItem)
        mouseClick(backgroundButton)
        compare(window.backgroundClicks, 1)
    }
    function test_retainedClosedModalPromptCannotInterceptWindowInput_data() {
        return test_inactivePromptCannotInterceptWindowInput_data()
    }
    function test_retainedClosedModalPromptCannotInterceptWindowInput(data) {
        const prompt = createTemporaryObject(data.component, modalContent, {width:850, height:600})
        verify(prompt !== null)
        modal.open()
        tryCompare(modal, "opened", true)
        waitForRendering(modalContent)
        modal.close()
        tryCompare(modal, "opened", false)
        waitForRendering(window.contentItem)
        mouseClick(backgroundButton)
        compare(window.backgroundClicks, 1)
    }
}
