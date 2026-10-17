// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "CardFacePreview"
    when: windowShown
    readonly property var front: ({name: "Front", displayName: "Front", faceName: "",
        setCode: "TST", collectorNumber: "7", typeLine: "Enchantment — Saga"})
    readonly property var back: ({name: "Back", displayName: "Back", faceName: "Back",
        setCode: "TST", collectorNumber: "7", typeLine: "Legendary Creature"})
    readonly property var sourceCard: ({id: "card-1", name: "Front // Back", setCode: "TST",
        collectorNumber: "7", oracleText: "Front rules", visibleIdentity: true})
    readonly property string testImage: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC"
        + "AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="

    ApplicationWindow { id: testWindow; width: 1000; height: 760; visible: true }
    Component {
        id: catalogComponent
        QtObject {
            property int imageRevision: 0
            property string language: "en"
            property var faceRows: [testCase.front, testCase.back]
            property var audit: ({faceQueries: 0, imageQueries: [], preparations: []})
            property var priorities: []
            property bool sourceAvailable: true
            property bool exactSources: true
            property bool revisionedSources: false
            function cardFaces(name, setCode, collectorNumber) { audit.faceQueries++; return faceRows }
            function cardDisplayName(name) { return language + ": " + name }
            function imageSource(name, setCode, collectorNumber) {
                audit.imageQueries.push(name + ":" + setCode + ":" + collectorNumber)
                return sourceAvailable && exactSources ? "fixture:" + name + ":" + setCode + ":" + collectorNumber : ""
            }
            function tokenImageSource(name, setCode, collectorNumber) { return imageSource(name, setCode, collectorNumber) }
            function previewImageSource(name, setCode, collectorNumber, token) {
                const source = imageSource(name, setCode, collectorNumber)
                return source && revisionedSources
                    ? source + ":" + imageRevision + ":" + (token ? "token" : "card") : source
            }
            function cardRulesText(name, setCode, collectorNumber) { return name === "Back" ? "Back rules" : "" }
            function tokenDetails(name, setCode, collectorNumber) { return ({}) }
            function prepareCardFacePreview(name, setCode, collectorNumber) { audit.preparations.push([name, setCode, collectorNumber]) }
            function prioritizeCards(cards) { priorities = priorities.concat(cards) }
        }
    }
    Component { id: controllerComponent; CardFacePreviewController {} }
    Component {
        id: galleryComponent
        CardFacePreviewGallery { width: 640 }
    }
    Component {
        id: previewComponent
        Item {
            id: scene
            width: 1000
            height: 760
            property var catalogModel: null
            property var card: testCase.sourceCard
            property int activationCount: 0
            property int backgroundClicks: 0
            property alias preview: preview
            property alias sourceTile: sourceTile
            property alias focusStart: focusStart
            property alias actionRegion: actionRegion
            property alias confirmAction: confirmAction
            property int confirmations: 0
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: scene.backgroundClicks++
            }
            AppButton {
                id: focusStart
                x: 10; y: 10
                text: "Focus start"
            }
            Rectangle {
                id: sourceTile
                x: 80; y: 100; width: 150; height: 210; color: "gray"
                MouseArea { anchors.fill: parent; onClicked: scene.activationCount++ }
                HoverHandler {
                    onHoveredChanged: hovered ? preview.inspect(scene.card, sourceTile) : preview.hide(sourceTile)
                }
            }
            Rectangle {
                id: actionRegion
                x: 590; y: 580; width: 400; height: 160
                visible: false
                AppButton {
                    id: confirmAction
                    anchors.centerIn: parent
                    text: "Confirm selection"
                    onClicked: scene.confirmations++
                }
            }
            CardHoverPreview {
                id: preview
                catalogModel: scene.catalogModel
                avoidItems: [actionRegion]
            }
        }
    }
    function catalog(properties) { return createTemporaryObject(catalogComponent, testCase, properties || {}) }
    function controller(model, card, properties) {
        return createTemporaryObject(controllerComponent, testCase,
            Object.assign({catalogModel: model, card: card || sourceCard}, properties || {}))
    }
    function scene(model) {
        return createTemporaryObject(previewComponent, testWindow.contentItem, {catalogModel: model})
    }
    function cleanup() { mouseMove(testWindow.contentItem, 2, 2) }

    function test_otherFaceKeepsPhysicalIdentityAndPrinting() {
        const model = catalog()
        const view = controller(model)
        compare(view.faceIndex, 0)
        compare(view.imageSource, "fixture:Front:TST:7")
        view.nextFace()
        compare(view.faceIndex, 1)
        compare(view.imageSource, "fixture:Back:TST:7")
        compare(view.viewedCard.id, sourceCard.id)
        compare(sourceCard.name, "Front // Back")
        verify(sourceCard.faceName === undefined)
        compare(model.priorities.length, 2)
        compare(model.priorities[1].name, "Back")
        compare(model.priorities[1].collectorNumber, "7")
        view.nextFace()
        compare(view.faceIndex, 0)
    }
    function test_initialFaceTracksAuthorityAndResetsOnPhysicalChange() {
        const model = catalog()
        const view = controller(model, Object.assign({}, sourceCard, {faceName: "Back"}))
        compare(view.faceIndex, 1)
        view.nextFace()
        compare(view.faceIndex, 0)
        view.card = Object.assign({}, view.card, {damage: 2})
        model.imageRevision++
        compare(view.faceIndex, 0)
        view.card = Object.assign({}, sourceCard, {id: "card-2"})
        compare(view.faceIndex, 0)
        view.nextFace()
        view.card = Object.assign({}, sourceCard, {id: "card-3"})
        compare(view.faceIndex, 0)
        view.card = Object.assign({}, sourceCard, {name: "Back"})
        compare(view.faceIndex, 1)
    }
    function test_revisionedSourcesPreserveEachFaceAndTokenPolicy_data() {
        return [{tag:"card", token:false}, {tag:"token", token:true}]
    }
    function test_revisionedSourcesPreserveEachFaceAndTokenPolicy(data) {
        const model = catalog({revisionedSources:true})
        const view = controller(model, sourceCard, {tokenArt:data.token})
        const suffix = data.token ? ":token" : ":card"
        compare(view.displayFaces[0].imageSource, "fixture:Front:TST:7:0" + suffix)
        compare(view.displayFaces[1].imageSource, "fixture:Back:TST:7:0" + suffix)
        model.imageRevision++
        compare(view.displayFaces[0].imageSource, "fixture:Front:TST:7:1" + suffix)
        compare(view.displayFaces[1].imageSource, "fixture:Back:TST:7:1" + suffix)
        const queries = model.audit.imageQueries.length
        view.identityVisible = false
        model.imageRevision++
        compare(view.displayFaces.length, 0)
        compare(model.audit.imageQueries.length, queries)
    }
    function test_sourceChangeResetsPreviewWithoutResettingOnMetadata() {
        const model = catalog()
        const view = controller(model)
        view.sourceItem = testWindow.contentItem
        view.nextFace()
        compare(view.faceIndex, 1)
        model.language = "zh"
        model.imageRevision++
        compare(view.faceIndex, 1)
        compare(view.displayName, "zh: Back")
        view.sourceItem = testWindow
        compare(view.faceIndex, 0)
    }
    function test_meldUsesRelatedPrintingInsteadOfComponentPrinting() {
        const result = Object.assign({}, back, {name: "Meld result", faceName: "Meld result", collectorNumber: "9"})
        const model = catalog({faceRows: [front, result]})
        const view = controller(model)
        view.nextFace()
        compare(view.imageSource, "fixture:Meld result:TST:9")
        compare(model.priorities[1].collectorNumber, "9")
        compare(view.displayFaces[1].card.collectorNumber, "9")
    }
    function test_sameNamedTokenUsesIndependentFrontAndBackRequests() {
        const model = catalog({faceRows: [
            {name: "Soldier // Soldier", faceName: "", displayName: "Soldier", setCode: "TOK", collectorNumber: "1"},
            {name: "Soldier", faceName: "Soldier", displayName: "Soldier", setCode: "TOK", collectorNumber: "1"}]})
        const view = controller(model, {name: "Soldier // Soldier", setCode: "TOK", collectorNumber: "1"}, {tokenArt: true})
        compare(view.faceIndex, 0)
        compare(view.imageSource, "fixture:Soldier // Soldier:TOK:1")
        view.nextFace()
        compare(view.imageSource, "fixture:Soldier:TOK:1")
        compare(model.priorities[0].kind, "token")
        const explicitBack = controller(model,
            {name: "Soldier // Soldier", faceName: "Soldier", setCode: "TOK", collectorNumber: "1"}, {tokenArt: true})
        compare(explicitBack.faceIndex, 1)
    }
    function test_unavailableBackNeverUsesFrontImageOrTokenRules() {
        const model = catalog({sourceAvailable: false})
        const view = controller(model, sourceCard, {fallbackImageSource: "front-only", tokenArt: true})
        compare(view.imageSource, "front-only")
        verify(view.fallbackText.indexOf("Front rules") >= 0)
        view.nextFace()
        compare(view.imageSource, "")
        verify(view.fallbackText.indexOf("Back") >= 0)
        verify(view.fallbackText.indexOf("Front rules") < 0)
        compare(view.viewedCard.oracleText, "")
    }
    function test_metadataHydrationAddsFaceControl() {
        const model = catalog({faceRows: []})
        const view = controller(model)
        verify(!view.canSwitch)
        view.nextFace()
        compare(model.priorities.length, 1)
        model.faceRows = [front, back]
        model.imageRevision++
        verify(view.canSwitch)
        view.nextFace()
        compare(view.faceIndex, 1)
    }
    function test_hiddenIdentityDoesNotQueryCatalog_data() {
        return [
            {tag: "face down known name", card: Object.assign({}, sourceCard, {faceDown: true}), identityVisible: true},
            {tag: "redacted identity", card: Object.assign({}, sourceCard, {visibleIdentity: false}), identityVisible: true},
            {tag: "invisible identity", card: Object.assign({}, sourceCard, {visible: false}), identityVisible: true},
            {tag: "explicit gate", card: sourceCard, identityVisible: false},
            {tag: "no name", card: {id: "hidden"}, identityVisible: true}]
    }
    function test_hiddenIdentityDoesNotQueryCatalog(data) {
        const model = catalog()
        const view = controller(model, data.card, {identityVisible: data.identityVisible})
        verify(!view.canSwitch)
        compare(view.imageSource, "")
        compare(view.fallbackText, "")
        compare(view.displayFaces.length, 0)
        const gallery = createTemporaryObject(galleryComponent, testWindow.contentItem, {controller: view})
        compare(gallery.faceCount, 0)
        compare(gallery.faceArt(0), null)
        view.nextFace()
        wait(0)
        compare(model.audit.faceQueries, 0)
        compare(model.audit.imageQueries.length, 0)
        compare(model.audit.preparations.length, 0)
        compare(model.priorities.length, 0)
    }
    function test_identityLossClearsFaceAndStopsResolution() {
        const model = catalog()
        const view = controller(model)
        view.nextFace()
        const queries = model.audit.faceQueries
        view.identityVisible = false
        compare(view.selectedFaceIndex, -1)
        compare(view.imageSource, "")
        model.imageRevision++
        compare(model.audit.faceQueries, queries)
        view.identityVisible = true
        compare(view.faceIndex, 0)
    }
    function test_legacyMetadataPreparationNeedsActiveVisibleInspection() {
        const model = catalog({faceRows: []})
        const view = controller(model, sourceCard, {active: false})
        compare(model.audit.preparations.length, 0)
        view.active = true
        tryVerify(() => model.audit.preparations.length > 0)
        compare(model.audit.preparations[0][0], sourceCard.name)
        const count = model.audit.preparations.length
        view.identityVisible = false
        view.card = Object.assign({}, sourceCard, {id: "hidden-2"})
        view.active = false
        view.active = true
        wait(0)
        compare(model.audit.preparations.length, count)
    }
    function test_displayOrderTracksAuthorityRatherThanSelectedPreviewFace() {
        const model = catalog()
        const original = Object.assign({}, sourceCard, {faceName: "Back", oracleText: "Current back rules"})
        const view = controller(model, original)
        const before = JSON.stringify(view.card)
        compare(view.displayFaces.length, 2)
        compare(view.displayFaces[0].faceIndex, 1)
        compare(view.displayFaces[0].name, "Back")
        compare(view.displayFaces[0].card.id, original.id)
        compare(view.displayFaces[1].faceIndex, 0)
        compare(view.displayFaces[1].name, "Front")
        compare(view.displayFaces[1].card.oracleText, "")
        verify(view.displayFaces[1].fallbackText.indexOf("Current back rules") < 0)
        view.nextFace()
        compare(view.faceIndex, 0)
        compare(view.displayFaces[0].faceIndex, 1)
        compare(view.displayFaces[1].faceIndex, 0)
        compare(JSON.stringify(view.card), before)
    }
    function test_allFacePrioritiesAreExactAndDeduplicatedAcrossImageUpdates() {
        const result = Object.assign({}, back, {name: "Meld result", faceName: "Meld result", setCode: "REL", collectorNumber: "9"})
        const model = catalog({faceRows: [front, result]})
        const view = controller(model)
        compare(model.priorities.length, 2)
        compare(model.priorities[0].setCode, "TST")
        compare(model.priorities[0].collectorNumber, "7")
        compare(model.priorities[1].setCode, "REL")
        compare(model.priorities[1].collectorNumber, "9")
        model.imageRevision++
        view.nextFace()
        wait(0)
        compare(model.priorities.length, 2)
        model.language = "zh"
        tryVerify(() => model.priorities.length === 4)
        compare(view.displayFaces[1].displayName, "zh: Meld result")
    }
    function test_exactPrintingOwnerCanDisableGenericPriorities() {
        const model = catalog()
        const view = controller(model, sourceCard, {prioritizeImages: false})
        compare(view.displayFaces.length, 2)
        compare(model.audit.preparations.length, 1)
        compare(model.priorities.length, 0)
        model.imageRevision++
        view.nextFace()
        wait(0)
        compare(model.priorities.length, 0)
    }
    function test_inactiveGalleryHasNoCatalogReadsOrScheduledRequests() {
        const model = catalog()
        const view = controller(model, sourceCard, {active: false})
        compare(view.displayFaces.length, 0)
        compare(view.imageSource, "")
        compare(view.fallbackText, "")
        model.imageRevision++
        wait(0)
        compare(model.audit.faceQueries, 0)
        compare(model.audit.imageQueries.length, 0)
        compare(model.audit.preparations.length, 0)
        compare(model.priorities.length, 0)
    }
    function test_galleryResponsiveRowsAndConstrainedFitRemainWithinBounds() {
        const view = controller(catalog({exactSources: false}))
        const gallery = createTemporaryObject(galleryComponent, testWindow.contentItem, {controller: view})
        compare(gallery.faceCount, 2)
        compare(gallery.columnCount, 2)
        compare(gallery.rowCount, 1)
        const frontArt = gallery.faceArt(0)
        const backArt = gallery.faceArt(1)
        verify(frontArt && backArt)
        compare(frontArt.objectName, "cardHoverPreviewArt")
        compare(backArt.objectName, "cardHoverPreviewArt-1")
        verify(backArt.parent.x > frontArt.parent.x)
        gallery.width = 300
        compare(gallery.columnCount, 1)
        compare(gallery.rowCount, 2)
        tryVerify(() => backArt.parent.y > frontArt.parent.y)
        verify(Math.abs(gallery.implicitHeight - (300 * 88 / 63 * 2 + gallery.gap)) < 0.01)
        const fit = gallery.fittedSize(380, 700, 240)
        compare(fit.columns, 2)
        verify(fit.width <= 700 && fit.height <= 240)
        // Height-constrained width can become narrower than the automatic
        // threshold. The returned forced column count preserves the fit.
        verify(fit.width < 2 * gallery.minimumFaceWidth + gallery.gap)
        gallery.columns = fit.columns
        gallery.width = fit.width
        compare(gallery.columnCount, 2)
        verify(Math.abs(gallery.implicitHeight - fit.height) < 0.01)
        const compact = gallery.fittedSize(380, 300, 500)
        compare(compact.columns, 1)
        verify(compact.width <= 300 && compact.height <= 500)
    }
    function test_threeFacesRetainCatalogOrderAfterCurrentFace() {
        const third = Object.assign({}, back, {name: "Third", faceName: "Third", collectorNumber: "9"})
        const view = controller(catalog({faceRows: [front, back, third], exactSources: false}),
            Object.assign({}, sourceCard, {faceName: "Back"}))
        compare(view.displayFaces.map(face => face.faceIndex).join(","), "1,0,2")
        const gallery = createTemporaryObject(galleryComponent, testWindow.contentItem, {controller: view})
        compare(gallery.faceCount, 3)
        compare(gallery.columnCount, 2)
        compare(gallery.rowCount, 2)
        verify(gallery.faceArt(2))
    }
    function test_galleryExactOverrideNeverSubstitutesFrontForMissingOtherFace() {
        const view = controller(catalog(), sourceCard,
            {fallbackImageSource: testImage, prioritizeImages: false})
        const gallery = createTemporaryObject(galleryComponent, testWindow.contentItem,
            {controller: view, artObjectName: "exactArt", fallbackObjectName: "exactFallback",
             imageSourceResolver: face => face.faceIndex === 0 ? testImage : ""})
        compare(view.displayFaces[0].imageSource, "fixture:Front:TST:7")
        compare(view.displayFaces[1].imageSource, "fixture:Back:TST:7")
        tryCompare(gallery.faceArt(0), "status", Image.Ready)
        compare(gallery.faceArt(0).objectName, "exactArt")
        compare(gallery.faceArt(1).objectName, "exactArt-1")
        compare(String(gallery.faceArt(1).source), "")
        const fallback = findChild(gallery, "exactFallback-1")
        verify(fallback.text.indexOf("Back rules") >= 0)
        verify(fallback.text.indexOf("Front rules") < 0)
    }
    function test_galleryImageDelegatesSurviveMetadataRevisions() {
        const model = catalog({exactSources: false})
        const view = controller(model)
        const gallery = createTemporaryObject(galleryComponent, testWindow.contentItem,
            {controller: view, imageSourceResolver: face => testImage})
        const first = gallery.faceArt(0)
        const second = gallery.faceArt(1)
        tryCompare(first, "status", Image.Ready)
        tryCompare(second, "status", Image.Ready)
        model.imageRevision++
        model.language = "zh"
        verify(gallery.faceArt(0) === first)
        verify(gallery.faceArt(1) === second)
        compare(first.status, Image.Ready)
        compare(second.status, Image.Ready)
        view.card = Object.assign({}, sourceCard, {faceName: "Back"})
        compare(view.displayFaces[0].name, "Back")
        verify(gallery.faceArt(0) === first)
        view.identityVisible = false
        compare(gallery.faceCount, 0)
        compare(gallery.faceArt(0), null)
    }
    function test_bothFacesVisibleWithoutControlsOrMutation() {
        const model = catalog({exactSources: false})
        const screen = scene(model)
        mouseMove(screen.sourceTile, 70, 90)
        tryCompare(screen.preview, "visible", true)
        const gallery = findChild(screen.preview, "cardHoverPreviewFaces")
        tryCompare(gallery, "faceCount", 2)
        const first = gallery.faceArt(0)
        const second = gallery.faceArt(1)
        verify(first && second)
        verify(first.visible && second.visible)
        verify(findChild(screen.preview, "cardPreviewFace-0").visible)
        verify(findChild(screen.preview, "cardPreviewFace-1").visible)
        compare(findChild(screen.preview, "viewOtherFaceButton"), null)
        verify(findChild(screen.preview, "cardHoverPreviewFallbackText").text.indexOf("Front rules") >= 0)
        verify(findChild(screen.preview, "cardHoverPreviewFallbackText-1").text.indexOf("Back rules") >= 0)
        compare(screen.preview.facePreview.faceIndex, 0)
        compare(JSON.stringify(screen.card), JSON.stringify(sourceCard))
        compare(screen.activationCount, 0)
        screen.preview.hide()
        verify(!screen.preview.visible)
        compare(screen.preview.sourceItem, null)
    }
    function test_allArtBodiesPassInputAndHoverStaysLocal() {
        const screen = scene(catalog({exactSources: false}))
        mouseMove(screen.sourceTile, 70, 90)
        tryCompare(screen.preview, "visible", true)
        verify(screen.preview.facePreview.canSwitch)
        const art = findChild(screen.preview, "cardHoverPreviewArt")
        const backArt = findChild(screen.preview, "cardHoverPreviewArt-1")
        verify(waitForRendering(screen.preview))
        mouseClick(art, art.width / 2, art.height / 2)
        compare(screen.backgroundClicks, 1)
        mouseClick(backArt, backArt.width / 2, backArt.height / 2)
        compare(screen.backgroundClicks, 2)
        compare(screen.activationCount, 0)
        mouseMove(art, art.width / 2, art.height / 2)
        tryCompare(screen.preview, "previewHeld", true)
        screen.preview.hide(screen.sourceTile)
        wait(400)
        verify(screen.preview.visible)
        compare(screen.preview.facePreview.faceIndex, 0)
        compare(screen.backgroundClicks, 2)
        compare(screen.activationCount, 0)
        screen.preview.hide()
        verify(!screen.preview.visible)
        compare(screen.preview.facePreview.faceIndex, 0)
    }
    function test_galleryClickDoesNotFocusOrPreventExpiry() {
        const screen = scene(catalog({exactSources: false}))
        mouseMove(screen.sourceTile, 70, 90)
        tryCompare(screen.preview, "visible", true)
        const art = findChild(screen.preview, "cardHoverPreviewArt-1")
        mouseMove(art, art.width / 2, art.height / 2)
        mouseClick(art, art.width / 2, art.height / 2)
        verify(!art.activeFocus)
        compare(screen.preview.facePreview.faceIndex, 0)
        verify(screen.preview.visible)
        mouseMove(screen, 950, 730)
        tryCompare(screen.preview, "visible", false, 1000)
        compare(screen.preview.sourceItem, null)
        compare(screen.preview.facePreview.faceIndex, 0)
        compare(screen.activationCount, 0)
    }
    function test_galleryAddsNoKeyboardFocusOrSpaceAction() {
        const screen = scene(catalog({exactSources: false}))
        mouseMove(screen.sourceTile, 70, 90)
        tryCompare(screen.preview, "visible", true)
        testWindow.requestActivate()
        mouseClick(screen.focusStart)
        tryCompare(screen.focusStart, "activeFocus", true)
        keyClick(Qt.Key_Tab)
        verify(!findChild(screen.preview, "cardHoverPreviewArt").activeFocus)
        verify(!findChild(screen.preview, "cardHoverPreviewArt-1").activeFocus)
        keyClick(Qt.Key_Space)
        compare(screen.preview.facePreview.faceIndex, 0)
        mouseMove(screen, 950, 730)
        compare(screen.activationCount, 0)
        tryCompare(screen.preview, "visible", false, 1000)
        compare(screen.preview.sourceItem, null)
    }
    function test_sourceExitExpiresAndStaleExitCannotHideNewCard() {
        const model = catalog({exactSources: false})
        const screen = scene(model)
        screen.preview.inspect(sourceCard, screen.sourceTile)
        screen.preview.hide(screen.sourceTile)
        verify(screen.preview.visible)
        tryCompare(screen.preview, "visible", false, 1000)
        screen.preview.inspect(sourceCard, screen)
        screen.preview.hide(screen.sourceTile)
        wait(450)
        verify(screen.preview.visible)
        screen.preview.hide()
    }
    function test_singleFaceExitRemainsImmediateAndPreviewFitsBounds() {
        const model = catalog({faceRows: [], exactSources: false})
        const screen = scene(model)
        screen.preview.inspect({name: "Normal"}, screen.sourceTile)
        verify(screen.preview.visible)
        verify(!screen.preview.enabled)
        screen.preview.hide(screen.sourceTile)
        verify(!screen.preview.visible)
        model.faceRows = [front, back]
        screen.preview.inspect(sourceCard, screen.sourceTile)
        tryVerify(() => screen.preview.y + screen.preview.height <= screen.height)
        tryVerify(() => screen.preview.x + screen.preview.width <= screen.width)
        screen.preview.card = Object.assign({}, sourceCard, {faceDown: true})
        tryCompare(screen.preview, "visible", false)
    }
    function test_previewKeepsActionsClear_data() {
        return [{tag:"single-face", faces:[], width:1000, height:760},
            {tag:"two-faces", faces:[front, back], width:1000, height:760},
            {tag:"compact-two-faces", faces:[front, back], width:900, height:620}]
    }
    function test_previewKeepsActionsClear(data) {
        const model = catalog({faceRows:data.faces, exactSources:false})
        const screen = scene(model)
        screen.width = data.width; screen.height = data.height
        const controls = screen.actionRegion, preview = screen.preview
        controls.y = screen.height - controls.height
        controls.visible = true
        preview.inspect(sourceCard, screen.sourceTile)
        function clearOfControls() {
            return preview.x + preview.width <= controls.x || preview.x >= controls.x + controls.width
                || preview.y + preview.height <= controls.y || preview.y >= controls.y + controls.height
        }
        tryVerify(clearOfControls)
        verify(preview.width > 180)
        compare(preview.facePreview.displayFaces.length, Math.max(1, data.faces.length))
        verify(preview.x >= 0 && preview.y >= 0)
        verify(preview.x + preview.width <= screen.width + 0.1)
        verify(preview.y + preview.height <= screen.height + 0.1)
        mouseClick(screen.confirmAction)
        compare(screen.confirmations, 1, "Inspection must leave the primary action usable")
        compare(preview.card.id, sourceCard.id)
        controls.x = 400; controls.y = 300; controls.width = 500; controls.height = 250
        tryVerify(clearOfControls, 5000, "Moving/resizing the action region updates the preview")
        preview.hide()
    }

    function test_previewUsesFullHeightSpaceBesideActions_data() {
        return [{tag:"left", actionX:500, expectedSide:"left"},
            {tag:"right", actionX:0, expectedSide:"right"}]
    }
    function test_previewUsesFullHeightSpaceBesideActions(data) {
        const screen = scene(catalog({faceRows:[], exactSources:false}))
        const controls = screen.actionRegion, preview = screen.preview
        controls.x = data.actionX; controls.y = 250; controls.width = 500; controls.height = 260
        controls.visible = true
        preview.inspect(sourceCard, screen.sourceTile)
        verify(waitForPolish(testWindow))
        compare(preview.width, Theme.size(380),
                "A full-size single face fits beside this action region")
        verify(data.expectedSide === "left" ? preview.x + preview.width <= controls.x
                                            : preview.x >= controls.x + controls.width)
        verify(preview.y >= 0 && preview.y + preview.height <= screen.height)
        mouseClick(screen.confirmAction)
        compare(screen.confirmations, 1)
        preview.hide()
    }

    function test_smallFreeAreaFitsBothRenderedFaces() {
        const screen = scene(catalog({faceRows:[front, back], exactSources:false}))
        const controls = screen.actionRegion, preview = screen.preview
        controls.x = 0; controls.y = 230; controls.width = 1000; controls.height = 300
        controls.visible = true
        preview.inspect(sourceCard, screen.sourceTile)
        verify(waitForPolish(testWindow))
        const gallery = findChild(preview, "cardHoverPreviewFaces")
        compare(preview.previewSize.columns, 2)
        verify(preview.width < 2 * gallery.minimumFaceWidth + gallery.gap,
               "This geometry exercises faces scaled below the automatic two-column threshold")
        compare(gallery.columnCount, preview.previewSize.columns)
        for (let index = 0; index < 2; ++index) {
            const face = findChild(preview, "cardPreviewFace-" + index)
            verify(face !== null)
            const start = face.mapToItem(preview, 0, 0)
            const end = face.mapToItem(preview, face.width, face.height)
            verify(start.x >= 0 && start.y >= 0)
            verify(end.x <= preview.width + 0.1 && end.y <= preview.height + 0.1,
                   "Every actual face must fit the rectangle used for avoidance")
            const windowEnd = face.mapToItem(screen, face.width, face.height)
            verify(windowEnd.y <= controls.y || preview.y >= controls.y + controls.height)
        }
        mouseClick(screen.confirmAction)
        compare(screen.confirmations, 1)
        preview.hide()
    }
}
