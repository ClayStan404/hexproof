// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "ForgeCardPresentation"
    when: windowShown
    property var sampleCard
    property var tile: null

    function picture(width, height, content) {
        return "data:image/svg+xml," + encodeURIComponent(
            '<svg xmlns="http://www.w3.org/2000/svg" width="' + width + '" height="' + height + '">'
            + content + '</svg>')
    }
    ApplicationWindow {
        id: window
        width: 600; height: 500; visible: true
        Rectangle { id: scene; anchors.fill: parent; color: "#46586a"; focus: true }
    }
    QtObject {
        id: catalog
        property string language: "en"
        property string frame: "standard"
        property var frameQueries: []
        property var nameQueries: []
        property string cropSource: ""
        property var cropQueries: []
        signal artCacheContentsChanged()
        signal cardArtCropAvailable(string requestedName)
        signal customArtContentsChanged()
        signal reuseLocalCardArtChanged()
        function cardArtFrame(name, set, number) {
            frameQueries.push([name, set, number])
            return frame
        }
        function cardDisplayName(name) {
            nameQueries.push(name)
            return name
        }
        function tableArtCropSource(name, set, number) {
            cropQueries.push([name, set, number])
            return cropSource
        }
    }
    QtObject {
        id: session
        property string gameId: "presentation"
        property string promptId: "prompt-1"
        property string promptKind: "chooseAction"
        property string promptPaymentId: ""
        property int snapshotRevision: 0
        function cardForInspection(id) { return ({}) }
    }
    QtObject {
        id: interaction
        property bool contextActive: true
        property bool canRespond: true
        property bool waitingForResponse: false
        property bool chosen: false
        property string submittedKind: ""
        property string submittedId: ""
        property var paymentQueue: []
        property var activations: []
        function objectSelected(kind, id) { return chosen }
        function nativeObjectSelected(kind, id) { return false }
        function objectOffered(kind, id) { return false }
        function offeredActionsForCard(id) { return [{kind: "activate", responseId: id}] }
        function activateObject(kind, id, name) {
            activations = activations.concat([[kind, id, name]])
            return true
        }
        function dismissQueuedPayment(id) { return false }
        function responseBlocked(kind, id) {}
    }
    QtObject {
        id: combat
        property bool active: false
        property bool canAct: true
        property bool attacking: false
        property bool destination: false
        property var hoveredTarget: null
        property var chosenSource: null
        function offered(id) { return destination }
        function targetActionable(id) { return destination }
        function selected(id) { return false }
        function labelFor(id) { return "" }
        function hoverCard(id, hovered) {}
        function activate(id) { return false }
    }
    QtObject {
        id: controller
        property var rulesSession: session
        property var cardCatalogModel: catalog
        property var combatInteraction: combat
        property var interaction: interaction
        property var presentation: null
        property int localSeat: 0
        property string imageSource: ""
        property string cardBackSource: ""
        property var imageQueries: []
        property var previews: []
        property var details: []
        function cardImage(name, set, number) {
            imageQueries.push([name, set, number])
            return imageSource
        }
        function previewCard(id, source, keyboard) { previews = previews.concat([id]) }
        function endCardPreview(source) {}
        function openCardDetails(id, source) { details = details.concat([id]) }
    }
    Component {
        id: cardComponent
        ForgeCard {
            x: 100; y: 100
            tableController: controller
            card: testCase.sampleCard
            hoverPreview: false
        }
    }
    function init() {
        testTranslations.setLanguage("en")
        Theme.motionEnabled = false
        Theme.uiScale = 1
        sampleCard = {cardId: "sample", name: "Public card", setCode: "TST", collectorNumber: "1",
            visibleIdentity: true, faceDown: false, zone: "battlefield", hintKey: "", actionCount: 0,
            targetCount: 0, nativeTargetSelected: false, tapped: false}
        catalog.frame = "standard"
        catalog.frameQueries = []; catalog.nameQueries = []
        catalog.cropSource = ""; catalog.cropQueries = []
        controller.imageSource = picture(488, 680, '<rect width="488" height="680" fill="#208de0"/>')
        controller.cardBackSource = picture(488, 680, '<rect width="488" height="680" fill="#713588"/>')
        controller.imageQueries = []; controller.previews = []; controller.details = []
        session.promptKind = "chooseAction"
        interaction.contextActive = true; interaction.canRespond = true; interaction.waitingForResponse = false
        interaction.chosen = false; interaction.submittedKind = ""; interaction.submittedId = ""
        interaction.paymentQueue = []; interaction.activations = []
        combat.active = false; combat.destination = false; combat.hoveredTarget = null
        window.requestActivate()
        scene.forceActiveFocus()
        mouseMove(scene, 10, 10)
    }
    function cleanup() {
        tile = null
        Theme.motionEnabled = true
        Theme.uiScale = 1
    }
    function createCard(properties) {
        tile = createTemporaryObject(cardComponent, scene, properties || {})
        verify(tile)
        tryCompare(findChild(tile, "forgeCardArt-sample"), "status", Image.Ready)
        tryCompare(tile, "artFrame", tile.publicFace && !tile.fullFace ? catalog.frame : "full")
        grabImage(scene)
        return tile
    }
    function setCard(values) { sampleCard = Object.assign({}, sampleCard, values) }
    function pixelAt(image, item, x, y) {
        const point = item.mapToItem(scene, x, y)
        const px = Math.round(point.x), py = Math.round(point.y)
        return [image.red(px, py), image.green(px, py), image.blue(px, py)]
    }
    function samePixel(image, other, item, x, y) {
        compare(pixelAt(image, item, x, y), pixelAt(other, item, x, y))
    }
    function test_fallbackArtworkFillsStableFrameWithoutStretching_data() {
        return [{tag: "portrait", w: 488, h: 680}, {tag: "landscape custom", w: 680, h: 350}]
    }
    function test_fallbackArtworkFillsStableFrameWithoutStretching(data) {
        catalog.frame = "full"
        controller.imageSource = picture(data.w, data.h,
            '<rect width="' + data.w + '" height="' + data.h + '" fill="#208de0"/><circle cx="' + data.w / 2
            + '" cy="' + data.h / 2 + '" r="60" fill="lime"/>')
        createCard()
        const originalSize = Qt.size(tile.width, tile.height)
        const face = findChild(tile, "forgeCardFace-sample")
        compare(Qt.size(face.width, face.height), originalSize, "Every fallback uses the complete battlefield frame")
        const pixels = grabImage(scene)
        for (const x of [1, tile.width - 2]) {
            const color = pixelAt(pixels, tile, x, tile.height / 2)
            verify(color[2] > color[0] * 3, "Fallback art fills both sides without a transparent gap: " + color)
        }
        function green(color) { return color[1] > color[0] * 2 && color[1] > color[2] * 2 }
        let horizontal = 0, vertical = 0
        for (let x = 0; x < tile.width; ++x)
            if (green(pixelAt(pixels, tile, x, tile.height / 2))) ++horizontal
        for (let y = 0; y < tile.height; ++y)
            if (green(pixelAt(pixels, tile, tile.width / 2, y))) ++vertical
        verify(horizontal > 30 && Math.abs(horizontal - vertical) <= 2,
            "A circular art feature stays round under aspect-preserving fill: " + horizontal + "," + vertical)
        setCard({actionCount: 1})
        interaction.chosen = true
        interaction.submittedKind = "card"; interaction.submittedId = "sample"
        grabImage(scene)
        const outline = findChild(tile, "forgeCardStateOutline-sample")
        compare(Qt.size(outline.width, outline.height), originalSize)
        compare(Qt.size(tile.width, tile.height), originalSize)
        mouseClick(tile, 3, tile.height / 2)
        compare(interaction.activations, [["card", "sample", "Public card"]], "The same edge retains its exact-object hit target")
        mouseClick(tile, 3, tile.height / 2, Qt.RightButton)
        compare(controller.details, ["sample"])
    }
    function test_frameAndImageChangesNeverResizeTheBattlefieldFace() {
        createCard()
        const face = findChild(tile, "forgeCardFace-sample")
        const outline = findChild(tile, "forgeCardStateOutline-sample")
        const original = Qt.rect(face.x, face.y, face.width, face.height)
        const changes = [{frame:"full", w:488, h:680}, {frame:"standard", w:488, h:680},
            {frame:"planeswalker", w:488, h:680}, {frame:"full", w:680, h:350},
            {frame:"saga", w:488, h:680}]
        for (const change of changes) {
            catalog.frame = change.frame
            controller.imageSource = picture(change.w, change.h,
                '<rect width="' + change.w + '" height="' + change.h + '" fill="#208de0"/>')
            catalog.artCacheContentsChanged()
            compare(Qt.rect(face.x, face.y, face.width, face.height), original,
                "An image or metadata refresh cannot transiently shrink the visible frame")
            tryCompare(tile, "artFrame", change.frame)
            tryCompare(findChild(tile, "forgeCardArt-sample"), "status", Image.Ready)
            grabImage(scene)
            compare(Qt.rect(face.x, face.y, face.width, face.height), original)
            compare(Qt.size(outline.width, outline.height), Qt.size(tile.width, tile.height))
        }
    }
    function test_standardArtworkReachesTileEdgeWithoutPadding() {
        createCard()
        const pixels = grabImage(scene)
        for (const x of [0, 1, 2, tile.width - 3, tile.width - 2, tile.width - 1]) {
            const color = pixelAt(pixels, tile, x, tile.height / 2)
            verify(color[2] > 140 && color[2] > color[0] * 3,
                "Known artwork must reach both edges without a neutral pad: " + color)
        }
        verify(!findChild(tile, "forgeCardStateOutline-sample").visible)
    }
    function test_stateOutlineDoesNotRepaintArtwork_data() {
        return ["offered", "selected", "located", "focus", "pay", "undo", "waiting undo", "combat", "combat hover"]
            .map(state => ({tag: state, state: state}))
    }
    function test_stateOutlineDoesNotRepaintArtwork(data) {
        createCard()
        const before = grabImage(scene)
        switch (data.state) {
        case "offered": setCard({actionCount: 1}); break
        case "selected": interaction.chosen = true; break
        case "located": tile.located = true; break
        case "focus": tile.forceActiveFocus(); tryCompare(tile, "activeFocus", true); break
        case "pay": session.promptKind = "payManaCost"; setCard({hintKey: "pay", actionCount: 1}); break
        case "undo": setCard({hintKey: "undo", actionCount: 1}); break
        case "waiting undo":
            setCard({hintKey: "undo", actionCount: 1}); interaction.canRespond = false; interaction.waitingForResponse = true; break
        case "combat": combat.active = true; combat.destination = true; break
        case "combat hover": combat.active = true; combat.destination = true; combat.hoveredTarget = {objectId: "sample"}; break
        }
        grabImage(scene)
        const after = grabImage(scene)
        let changed = 0
        for (let x = 0; x < tile.width; ++x) {
            if (String(pixelAt(before, tile, x, tile.height / 2)) !== String(pixelAt(after, tile, x, tile.height / 2)))
                ++changed
        }
        verify(changed > 0 && changed <= 6, "State emphasis is confined to a thin edge, not a backing fill: " + changed)
        for (const x of [5, tile.width / 2, tile.width - 6]) samePixel(before, after, tile, x, tile.height / 2)
        const hint = findChild(tile, "forgeCardInteractionHint-sample")
        if (data.state === "pay") { compare(hint.text, "Tap for mana"); verify(hint.visible) }
        if (data.state === "undo") { compare(hint.text, "Undo mana"); verify(hint.visible) }
        if (data.state === "waiting undo") verify(!hint.visible)
    }
    function test_fallbackFaceKeepsPublicOverlaysAndUndimmedStats() {
        catalog.frame = "full"
        setCard({power: "3", toughness: "4", countersSummary: "+1/+1 × 1", damage: 2, actionCount: 1,
            hintKey: "undo", nativeTargetSelected: true})
        createCard()
        const stats = findChild(tile, "forgeCardStats-sample")
        compare(stats.text, "3 / 4")
        const state = findChild(tile, "forgeCardState-sample")
        verify(state.text.includes("+1/+1 × 1")); verify(state.text.includes("2 dmg"))
        verify(findChild(tile, "forgeCardNativeSelection-sample").visible)
        verify(findChild(tile, "forgeCardInteractionHint-sample").visible)
        const before = grabImage(scene)
        setCard({tapped: true})
        grabImage(scene)
        const after = grabImage(scene)
        const badge = stats.parent
        for (let y = 3; y < badge.height - 3; ++y)
            for (let x = 3; x < badge.width - 3; ++x) samePixel(before, after, badge, x, y)
        verify(findChild(tile, "forgeCardTappedMark-sample").visible)
        verify(tile.readoutRects(scene).length >= 4)
    }
    function test_hiddenFaceNeverRequestsIdentity() {
        catalog.cropSource = picture(600, 400, '<rect width="600" height="400" fill="lime"/>')
        setCard({name: "Secret face", visibleIdentity: false, faceDown: true, power: "2", toughness: "2"})
        createCard()
        compare(findChild(tile, "forgeCardName-sample").text, "Hidden card")
        compare(findChild(tile, "forgeCardStats-sample").text, "2 / 2")
        compare(catalog.frameQueries, []); compare(catalog.nameQueries, []); compare(controller.imageQueries, [])
        compare(catalog.cropQueries, []); verify(!tile.usingArtCrop)
        catalog.artCacheContentsChanged()
        grabImage(scene)
        compare(catalog.frameQueries, []); compare(catalog.nameQueries, []); compare(controller.imageQueries, [])
        compare(catalog.cropQueries, [])
    }
    function test_fullInspectionKeepsAllImageEdges_data() {
        return [{tag:"saga",frame:"saga",x:250,y:150,w:190,h:350},
            {tag:"planeswalker",frame:"planeswalker",x:39,y:95,w:410,h:238}]
    }
    function test_fullInspectionKeepsAllImageEdges(data) {
        catalog.frame = data.frame
        catalog.cropSource = picture(600, 400, '<rect width="600" height="400" fill="blue"/>')
        controller.imageSource = picture(488, 680,
            '<rect width="488" height="680" fill="red"/><rect x="' + data.x + '" y="' + data.y
            + '" width="' + data.w + '" height="' + data.h + '" fill="lime"/>')
        createCard({fullFace: true})
        const face = findChild(tile, "forgeCardFace-sample")
        const pixels = grabImage(scene)
        for (const point of [Qt.point(.1, .1), Qt.point(.9, .1), Qt.point(.1, .9), Qt.point(.9, .9)]) {
            const color = pixelAt(pixels, face, face.width * point.x, face.height * point.y)
            verify(color[0] > 240 && color[1] < 10, "Full inspection preserves every printed edge")
        }
        if (data.frame === "planeswalker") {
            const art = pixelAt(pixels, face, face.width * .5, face.height * .3)
            const rules = pixelAt(pixels, face, face.width * .5, face.height * .65)
            verify(art[1] > 240 && art[0] < 10, "Full inspection retains the planeswalker illustration")
            verify(rules[0] > 240 && rules[1] < 10, "Full inspection retains the printed type and loyalty abilities")
        }
        compare(catalog.frameQueries, [])
        compare(catalog.cropQueries, []); verify(!tile.usingArtCrop)
    }
    function test_cachedArtworkBypassesFullCardCrop_data() {
        return [{tag: "planeswalker", frame: "planeswalker"}, {tag: "saga", frame: "saga"},
            {tag: "battle", frame: "battle"}, {tag: "unrecognized frame", frame: "full"}]
    }
    function test_cachedArtworkBypassesFullCardCrop(data) {
        catalog.frame = data.frame
        catalog.cropSource = picture(600, 400,
            '<rect width="600" height="400" fill="lime"/><circle cx="300" cy="200" r="60" fill="red"/>')
        createCard()
        tryCompare(tile, "usingArtCrop", true)
        const image = findChild(tile, "forgeCardArtCrop-sample")
        compare(image.rotation, 0, "Independent art already has the correct orientation")
        compare(Qt.size(image.width, image.height), Qt.size(tile.width, tile.height))
        const pixels = grabImage(scene)
        const center = pixelAt(pixels, tile, tile.width / 2, tile.height / 2)
        verify(center[0] > center[1] * 3, "The artwork center survives without a second frame crop")
        for (const x of [.03, .97]) {
            const edge = pixelAt(pixels, tile, tile.width * x, tile.height / 2)
            verify(edge[1] > edge[0] * 3, "Cached artwork covers the entire battlefield tile")
        }
        const queries = catalog.cropQueries.length
        tile.width += 60
        grabImage(scene)
        compare(catalog.cropQueries.length, queries, "Resizing never reloads metadata or initiates network work")
    }
    function test_optionalArtworkArrivalAndRemovalKeepFallbackAndGeometry() {
        createCard()
        const face = findChild(tile, "forgeCardFace-sample")
        const full = findChild(tile, "forgeCardArt-sample")
        const original = Qt.rect(face.x, face.y, face.width, face.height)
        const fullSource = full.source.toString()
        verify(!tile.usingArtCrop)
        const cropQueries = catalog.cropQueries.length
        const frameQueries = catalog.frameQueries.length
        catalog.cropSource = picture(600, 400, '<rect width="600" height="400" fill="lime"/>')
        catalog.cardArtCropAvailable("Unrelated card")
        grabImage(scene)
        compare(catalog.cropQueries.length, cropQueries, "Another card's crop must not refresh this tile")
        compare(catalog.frameQueries.length, frameQueries, "Another card's crop must not reload frame metadata")
        verify(!tile.usingArtCrop)
        catalog.cardArtCropAvailable(sampleCard.name)
        compare(Qt.rect(face.x, face.y, face.width, face.height), original)
        tryCompare(tile, "usingArtCrop", true)
        compare(full.source.toString(), fullSource, "An optional crop cannot replace the full inspection asset")
        compare(Qt.rect(face.x, face.y, face.width, face.height), original)
        const cropped = grabImage(scene)
        const green = pixelAt(cropped, tile, tile.width / 2, tile.height / 2)
        verify(green[1] > green[2] * 3)
        catalog.cropSource = ""
        catalog.artCacheContentsChanged()
        tryCompare(tile, "usingArtCrop", false)
        tryCompare(tile, "artFrame", catalog.frame)
        const fallback = grabImage(scene)
        const blue = pixelAt(fallback, tile, tile.width / 2, tile.height / 2)
        verify(blue[2] > blue[0] * 3, "Missing artwork immediately leaves the existing full-card fallback usable")
        compare(Qt.rect(face.x, face.y, face.width, face.height), original)
        mouseClick(tile, 3, tile.height / 2)
        compare(interaction.activations, [["card", "sample", "Public card"]])
    }
    function test_customArtAndReusePolicyRefreshCachedArtwork_data() {
        return [{tag: "custom binding", custom: true}, {tag: "reuse disabled", custom: false}]
    }
    function test_customArtAndReusePolicyRefreshCachedArtwork(data) {
        catalog.cropSource = picture(600, 400, '<rect width="600" height="400" fill="lime"/>')
        createCard()
        tryCompare(tile, "usingArtCrop", true)
        const size = Qt.size(tile.width, tile.height)
        catalog.cropSource = ""
        catalog.frame = "full"
        controller.imageSource = picture(600, 400, '<rect width="600" height="400" fill="red"/>')
        if (data.custom)
            catalog.customArtContentsChanged()
        else
            catalog.reuseLocalCardArtChanged()
        tryCompare(tile, "usingArtCrop", false)
        tryCompare(tile, "artFrame", "full")
        tryCompare(findChild(tile, "forgeCardArt-sample"), "status", Image.Ready)
        const pixels = grabImage(scene)
        const color = pixelAt(pixels, tile, tile.width / 2, tile.height / 2)
        verify(color[0] > color[1] * 3, "A cached official crop cannot cover a newly selected local image")
        compare(Qt.size(tile.width, tile.height), size)
    }
    function test_planeswalkerTileExcludesPrintedTypeAndRules_data() {
        return [{tag:"ordinary-size",width:180,height:167},
            {tag:"compact-size",width:110,height:102},
            {tag:"wide-lane",width:260,height:140}]
    }
    function test_planeswalkerTileExcludesPrintedTypeAndRules(data) {
        catalog.frame = "planeswalker"
        // The reported Ugin printing is 488x680: its type/rules start just
        // below y=333 (49% down), well above the ordinary card text box.
        controller.imageSource = picture(488, 680,
            '<rect width="488" height="680" fill="red"/>'
            + '<rect x="39" y="95" width="410" height="238" fill="lime"/>')
        createCard({width:data.width,height:data.height})
        const face = findChild(tile, "forgeCardFace-sample")
        const outline = findChild(tile, "forgeCardStateOutline-sample")
        compare(Qt.size(face.width,face.height),Qt.size(data.width,data.height),
            "A shorter illustration changes the image crop, not the battlefield slot")
        const pixels = grabImage(scene)
        for (const x of [.25,.5,.75]) {
            for (const y of [.55,.8,.88,.92,.96]) {
                const color = pixelAt(pixels,tile,tile.width*x,tile.height*y)
                verify(color[1] > color[0] * 2,
                    "Planeswalker type/rules must stay outside the tile, including its lower edge: "
                        + [data.tag,x,y,color].join(","))
            }
        }
        interaction.chosen = true
        grabImage(scene)
        compare(Qt.size(tile.width,tile.height),Qt.size(data.width,data.height))
        compare(Qt.size(outline.width,outline.height),Qt.size(data.width,data.height))
        mouseClick(tile,3,tile.height/2)
        compare(interaction.activations,[["card","sample","Public card"]],
            "Artwork cropping must preserve the card's full interaction footprint")
    }
    function test_specialCropStillShowsOnlyArtwork_data() {
        return [
            {tag: "saga", frame: "saga", x: 250, y: 150, w: 190, h: 350},
            {tag: "class", frame: "class", x: 55, y: 90, w: 175, h: 430},
            {tag: "planeswalker", frame: "planeswalker", x: 39, y: 95, w: 410, h: 238},
            {tag: "battle", frame: "battle", x: 70, y: 80, w: 195, h: 570},
            {tag: "flip", frame: "flip", x: 45, y: 218, w: 395, h: 220},
            {tag: "flip back", frame: "flip-back", x: 45, y: 218, w: 395, h: 220}]
    }
    function test_specialCropStillShowsOnlyArtwork(data) {
        catalog.frame = data.frame
        controller.imageSource = picture(488, 680,
            '<rect width="488" height="680" fill="red"/><rect x="' + data.x + '" y="' + data.y
            + '" width="' + data.w + '" height="' + data.h + '" fill="lime"/>')
        createCard()
        const pixels = grabImage(scene)
        for (const x of [.15, .5, .85]) {
            const color = pixelAt(pixels, tile, tile.width * x, tile.height / 2)
            verify(color[1] > color[0] * 2, "Special artwork crop must exclude printed rules")
        }
        const calls = catalog.frameQueries.length
        tile.width += 60
        grabImage(scene)
        compare(catalog.frameQueries.length, calls, "Resizing only changes presentation, not metadata resolution")
    }
}
