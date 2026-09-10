// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"
import "../../qml/screens"

TestCase {
    id: testCase
    name: "CustomCardArt"
    when: windowShown
    readonly property string imageUrl: Qt.resolvedUrl("../../assets/icons/hexproof.png").toString()
    readonly property string otherImageUrl: Qt.resolvedUrl("../../assets/icons/hicolor/64x64/apps/io.github.claystan404.hexproof.png").toString()
    readonly property var artStore: store
    readonly property var front: ({name: "Front // Back", faceName: "", label: "Front",
                                  setCode: "TST", collectorNumber: "7†", oracleId: "oracle"})
    readonly property var back: ({name: "Front // Back", faceName: "Back", label: "Back",
                                 setCode: "TST", collectorNumber: "7†", oracleId: "oracle"})
    readonly property var deckCard: ({name: "Front // Back", displayName: "Front", typeLine: "Creature",
                                     setCode: "TST", collectorNumber: "7†", count: 1,
                                     imageSource: imageUrl})
    ApplicationWindow {
        id: window
        width: 1000
        height: 720
        visible: true
        function popScreen() {}
        function pushScreen() {}
        function showBanner() {}
        CustomCardArtDialog { id: dialog; store: store; catalogModel: catalog }
        CustomArtImportDialog { id: importDialog; store: store }
    }
    QtObject {
        id: store
        property bool busy: false
        property int revision: 0
        property var entries: []
        property var preview: ({})
        property string lastError: ""
        property string lastResult: ""
        property string status: "Working"
        property var calls: []
        signal changed()
        signal inspectionFinished()
        signal operationFinished(var result)
        function entryFor(binding) {
            return entries.find(entry => entry.scope === binding.scope
                    && entry.name === binding.name && entry.faceName === binding.faceName) || ({})
        }
        function inspectImage(url) { calls = ["inspectImage", String(url)]; busy = true }
        function setImage(url, binding) { calls = ["setImage", String(url), Object.assign({}, binding)]; busy = true }
        function removeBindings(binding, allFaces) { calls = ["removeBindings", Object.assign({}, binding), allFaces]; busy = true }
        function inspectDirectory(url) { calls = ["inspectDirectory", String(url)]; busy = true }
        function inspectPack(url) { calls = ["inspectPack", String(url)]; busy = true }
        function importPreview(replace) { calls = ["importPreview", replace]; busy = true }
        function removeEntry(id) { calls = ["removeEntry", id]; busy = true }
        function clear() { calls = ["clear"]; busy = true }
        function clearMessages() { lastError = ""; lastResult = "" }
        function exportPack(url, ids) { calls = ["exportPack", String(url), ids.slice()]; busy = true }
        function suggestedExportUrl() { return "file:///tmp/custom.hexproof-custom-artpack" }
    }
    QtObject {
        id: catalog
        property int imageRevision: 0
        property bool installed: true
        property var faces: [testCase.front, testCase.back]
        property string overrideSource: ""
        property bool artAvailable: true
        property string language: "en"
        function customArtBindings(card) { return faces }
        function customImageSource() { return overrideSource }
        function imageSource() { return artAvailable ? overrideSource || testCase.imageUrl : "" }
        function tokenImageSource() { return imageSource() }
        function tokenDetails() { return ({}) }
        function prioritizeCards() {}
    }
    QtObject {
        id: considerLibrary
        property int currentConsiderCount: 1
        property var considerCards: [testCase.deckCard]
        function canAddCard() { return true }
        function changeConsiderCardCount() {}
        function moveConsiderCardToMain() {}
    }
    Component {
        id: managerComponent
        CustomCardArtManager { store: testCase.artStore; catalogModel: catalog }
    }
    Component {
        id: rowComponent
        DeckCardRow {
            width: 650
            card: testCase.deckCard
            catalogModel: catalog
            customArtEnabled: true
            printingEnabled: true
        }
    }
    Component {
        id: visualComponent
        DeckVisualCard {
            width: 220
            height: 400
            card: testCase.deckCard
            catalogModel: catalog
            customArtEnabled: true
            printingEnabled: true
        }
    }
    Component {
        id: tokenComponent
        TokenDetailsPopup {
            property var customCardArtStore: testCase.artStore
            catalogModel: catalog
        }
    }
    Component {
        id: considerComponent
        DeckConsiderManager {
            deckLibraryModel: considerLibrary
            catalogModel: catalog
            customArtEnabled: true
        }
    }
    SignalSpy { id: actionSpy; signalName: "customArtRequested" }

    function init() {
        testTranslations.setLanguage("en")
        window.width = 1000
        window.height = 720
        Theme.uiScale = 1
        store.busy = false
        store.entries = []
        store.calls = []
        store.preview = ({})
        store.lastError = ""
        store.lastResult = ""
        catalog.faces = [front, back]
        catalog.overrideSource = ""
        catalog.artAvailable = true
        dialog.pendingOperation = ""
        dialog.close()
        importDialog.importing = false
        importDialog.close()
    }
    function cleanup() {
        store.busy = false
        dialog.close()
        importDialog.importing = false
        importDialog.close()
        Theme.uiScale = 1
        actionSpy.target = null
    }
    function openCard(value) {
        verify(dialog.showFor(value || deckCard))
        tryVerify(() => dialog.opened)
        waitForPolish(window)
    }
    function finishInspection(value) {
        store.preview = value
        store.busy = false
        store.inspectionFinished()
        waitForPolish(window)
    }
    function finishOperation(operation, ok, fileUrl) {
        store.busy = false
        store.lastResult = ok ? "Custom image updated." : ""
        store.lastError = ok ? "" : "Image is invalid."
        store.operationFinished({operation: operation, ok: ok, fileUrl: fileUrl || "",
                                 error: store.lastError})
        waitForPolish(window)
    }
    function test_imagePreviewCommitsVerifiedSnapshotAtExactFace() {
        openCard()
        compare(dialog.scope, "printing")
        const selector = findChild(dialog, "customArtFaceSelector")
        selector.activated(1)
        compare(dialog.binding.faceName, "Back")
        const chooser = findChild(dialog, "customArtImageFileDialog")
        chooser.selectedFile = imageUrl
        chooser.accepted()
        compare(store.calls[0], "inspectImage")
        verify(!findChild(dialog, "applyCustomArtButton").enabled)
        finishInspection({kind: "image", fileUrl: "file:///tmp/other.png", ok: true, imageSource: imageUrl})
        verify(!dialog.candidate.ok)
        finishInspection({kind: "image", fileUrl: imageUrl, ok: true,
                          imageSource: otherImageUrl, width: 64, height: 64})
        verify(dialog.canApply)
        mouseClick(findChild(dialog, "applyCustomArtButton"))
        compare(store.calls[0], "setImage")
        compare(store.calls[1], otherImageUrl, "Apply the validated staged image, not a changed original")
        compare(store.calls[2].scope, "printing")
        compare(store.calls[2].collectorNumber, "7†")
        compare(store.calls[2].faceName, "Back")
        finishOperation("setImage", true, otherImageUrl)
        verify(dialog.resultMessage.length > 0)
        verify(dialog.opened)
    }
    function test_scopeAndFaceChangesDiscardUnappliedImage() {
        openCard()
        dialog.candidate = {ok: true, imageSource: imageUrl}
        findChild(dialog, "customArtScopeSelector").activated(1)
        compare(dialog.scope, "card")
        verify(!dialog.canApply)
        dialog.candidate = {ok: true, imageSource: imageUrl}
        findChild(dialog, "customArtFaceSelector").activated(1)
        compare(dialog.binding.faceName, "Back")
        verify(!dialog.canApply)
        catalog.faces = [{name: "Whole card", faceName: "", label: "Whole image", oracleId: "whole-oracle"}]
        openCard({name: "Whole card"})
        compare(dialog.scope, "")
        verify(!dialog.binding.name)
        findChild(dialog, "customArtScopeSelector").activated(0)
        compare(dialog.scope, "card")
        compare(dialog.binding.faceName, "")
    }
    function test_cardWideScopeRequiresStableIdentity() {
        catalog.faces = [{name: "Goblin", faceName: "", label: "Goblin", setCode: "TTST", collectorNumber: "1"}]
        openCard({name: "Goblin", token: true})
        compare(dialog.scopeOptions.length, 1)
        compare(dialog.scopeOptions[0].value, "printing")
        dialog.scope = "card"
        dialog.candidate = {ok: true, imageSource: imageUrl}
        verify(!dialog.canApply)
        catalog.faces = [{name: "Goblin", faceName: "", label: "Goblin"}]
        openCard({name: "Goblin", token: true})
        compare(dialog.scopeOptions.length, 0)
        verify(dialog.errorMessage.indexOf("exact printing") >= 0)
    }
    function test_restoreTargetsSelectedScopeAndFace() {
        store.entries = [Object.assign({id: "back-override", scope: "printing"}, back)]
        openCard(Object.assign({}, deckCard, {faceName: "Back"}))
        compare(dialog.faceIndex, 1)
        verify(findChild(dialog, "restoreCustomArtFaceButton").enabled)
        dialog.restore(false)
        compare(store.calls[0], "removeBindings")
        compare(store.calls[1].scope, "printing")
        compare(store.calls[1].faceName, "Back")
        compare(store.calls[2], false)
        finishOperation("removeBindings", true)
        dialog.restore(true)
        compare(store.calls[2], true)
    }
    function test_editExistingCardWideOverridePreservesItsScope() {
        store.entries = [Object.assign({id: "all-printings-back", scope: "card"}, back)]
        openCard(store.entries[0])
        compare(dialog.faceIndex, 1)
        compare(dialog.scope, "card")
        verify(findChild(dialog, "restoreCustomArtFaceButton").enabled)
        dialog.restore(false)
        compare(store.calls[1].scope, "card")
        compare(store.calls[1].faceName, "Back")
        finishOperation("removeBindings", true)
    }
    function test_invalidImageReportsErrorAndAllowsRetry() {
        openCard()
        dialog.inspectImage("file:///tmp/bad.png")
        finishInspection({kind: "image", fileUrl: "file:///tmp/bad.png", ok: false, error: "Image is too large."})
        compare(dialog.errorMessage, "Image is too large.")
        verify(!dialog.canApply)
        dialog.inspectImage("file:///tmp/good.png")
        finishInspection({kind: "image", fileUrl: "file:///tmp/good.png", ok: true, imageSource: imageUrl})
        dialog.applyImage()
        finishOperation("setImage", false, imageUrl)
        compare(dialog.errorMessage, "Image is invalid.")
        verify(dialog.canApply)
    }
    function test_customActionsAndReactiveArt_data() {
        return [{tag: "list", component: rowComponent}, {tag: "gallery", component: visualComponent}]
    }
    function test_customActionsAndReactiveArt(data) {
        const item = createTemporaryObject(data.component, window.contentItem)
        verify(item !== null)
        waitForPolish(window)
        compare(item.resolvedImageSource, imageUrl)
        catalog.artAvailable = false
        ++catalog.imageRevision
        item.card = Object.assign({}, deckCard, {imageSourceResolved: true})
        compare(item.resolvedImageSource, "", "An unavailable configured location must not reuse an old stored path")
        catalog.artAvailable = true
        catalog.overrideSource = otherImageUrl
        ++catalog.imageRevision
        compare(item.resolvedImageSource, otherImageUrl)
        catalog.overrideSource = ""
        ++catalog.imageRevision
        compare(item.resolvedImageSource, imageUrl)
        actionSpy.target = item
        actionSpy.clear()
        mouseClick(findChild(item, "deckCardActionsButton"))
        const action = findChild(item, "deckCardCustomArtAction")
        tryVerify(() => action.visible && action.parent.visible)
        waitForPolish(window)
        mouseClick(action)
        compare(actionSpy.count, 1)
    }
    function findCardDelegate(item) {
        if (item.card && typeof item.customArtRequested === "function")
            return item
        for (const child of item.children || []) {
            const result = findCardDelegate(child)
            if (result)
                return result
        }
        return null
    }
    function test_considerActionPreservesCardIdentity() {
        const popup = createTemporaryObject(considerComponent, window.contentItem)
        verify(popup !== null)
        popup.open()
        waitForPolish(window)
        const card = findCardDelegate(findChild(popup, "considerCardGrid"))
        verify(card !== null)
        verify(card.customArtEnabled)
        actionSpy.target = popup
        actionSpy.clear()
        card.customArtRequested()
        compare(actionSpy.count, 1)
        compare(actionSpy.signalArguments[0][0].collectorNumber, "7†")
        popup.close()
    }
    function test_tokenAndEmblemDetailsOpenTheSameCustomizationDialog() {
        catalog.faces = [{name: "Teferi Emblem", label: "Teferi Emblem", faceName: "",
                          setCode: "TTST", collectorNumber: "1", oracleId: "emblem-id"}]
        const popup = createTemporaryObject(tokenComponent, window.contentItem)
        verify(popup !== null)
        popup.showCard({name: "Teferi Emblem", kind: "emblem", setCode: "TTST", collectorNumber: "1"})
        waitForPolish(window)
        const button = findChild(popup, "tokenCustomArtButton")
        verify(button.visible)
        mouseClick(button)
        const custom = findChild(popup, "tokenCustomCardArtDialog")
        tryVerify(() => custom.opened)
        compare(custom.card.kind, "emblem")
        compare(custom.binding.name, "Teferi Emblem")
        compare(custom.binding.setCode, "TTST")
        custom.close()
        popup.close()
    }
    function test_largeScaleCardDialogKeepsButtonsAndScrollUsable() {
        window.width = 900
        window.height = 620
        Theme.uiScale = 1.8
        openCard()
        const body = findChild(dialog, "customCardArtBody")
        verify(body.contentHeight > body.height)
        mouseWheel(body, body.width / 2, body.height / 2, 0, -120)
        tryVerify(() => body.contentY > 0)
        const apply = findChild(dialog, "applyCustomArtButton")
        const point = apply.mapToItem(window.contentItem, 0, 0)
        verify(point.x >= 0 && point.x + apply.width <= window.width)
        verify(point.y >= 0 && point.y + apply.height <= window.height)
    }
    function test_customPackRequiresExplicitReviewAndPreservesConflicts() {
        const rows = []
        for (let index = 0; index < 1500; ++index)
            rows.push(Object.assign({}, front, {id: "id-" + index, valid: true, conflict: index === 0,
                                               scope: "printing", fileName: "image-" + index, imageSource: ""}))
        importDialog.showPreview({ok: true, kind: "pack", rows: rows, validCount: 1500,
                                  conflictCount: 1, errorCount: 2})
        waitForPolish(window)
        compare(store.calls.length, 0)
        verify(!importDialog.replaceExisting)
        compare(findChild(importDialog, "customArtImportMappings").count, 1500)
        importDialog.importConfirmed()
        compare(store.calls[0], "importPreview")
        compare(store.calls[1], false)
        finishOperation("importPreview", true)
        verify(importDialog.resultMessage.length > 0)
        verify(!importDialog.canImport)
        importDialog.showPreview({ok: true, kind: "directory", rows: rows, validCount: 1500, conflictCount: 1})
        importDialog.replaceExisting = true
        importDialog.importConfirmed()
        compare(store.calls[1], true)
    }
    function test_scaledImportAndManagerControlsRemainReachable() {
        window.width = 900
        window.height = 620
        Theme.uiScale = 1.8
        const page = createTemporaryObject(managerComponent, window.contentItem,
                                          {width: window.width, height: window.height})
        verify(page !== null)
        waitForPolish(window)
        const pageBody = findChild(page, "customCardArtManagerBody")
        verify(pageBody.contentHeight > pageBody.height)
        for (const name of ["importCustomArtFolderButton", "importCustomArtPackButton",
                            "exportCustomArtPackButton", "clearCustomArtButton"]) {
            const button = findChild(page, name)
            const point = button.mapToItem(page, 0, 0)
            verify(point.x >= 0 && point.x + button.width <= page.width)
        }
        pageBody.contentY = pageBody.contentHeight - pageBody.height
        store.busy = true
        waitForPolish(window)
        const progress = findChild(page, "customArtManagerProgress")
        const progressPoint = progress.mapToItem(window.contentItem, 0, 0)
        verify(progress.visible)
        verify(progressPoint.y >= 0 && progressPoint.y + progress.height <= window.height)
        store.busy = false
        importDialog.showPreview({ok: true, rows: [Object.assign({}, front, {valid: true})],
                                  validCount: 1, conflictCount: 1, errorCount: 1})
        waitForPolish(window)
        for (const name of ["confirmCustomArtImportButton", "closeCustomArtImportButton"]) {
            const button = findChild(importDialog, name)
            const point = button.mapToItem(window.contentItem, 0, 0)
            verify(point.x >= 0 && point.x + button.width <= window.width)
            verify(point.y >= 0 && point.y + button.height <= window.height)
        }
        const importBody = findChild(importDialog, "customArtImportBody")
        mouseWheel(importBody, importBody.width / 2, importBody.height / 2, 0, -120)
        tryVerify(() => importBody.contentY > 0)
    }
    function test_unmappedImportRowShowsItsOriginalFileName() {
        importDialog.showPreview({ok: true, rows: [{valid: false,
            sourceFile: "unmapped original.jpg", error: "No exact printing"}],
            validCount: 0, errorCount: 1})
        waitForPolish(window)
        const mappings = findChild(importDialog, "customArtImportMappings")
        tryVerify(() => mappings.itemAtIndex(0) !== null)
        compare(findChild(mappings.itemAtIndex(0), "customArtImportRowName").text,
                "unmapped original.jpg")
    }
    function test_managerInspectionRoutingAndExportSelectionSnapshot() {
        const page = createTemporaryObject(managerComponent, window.contentItem,
                                          {width: window.width, height: window.height})
        verify(page !== null)
        store.entries = [Object.assign({}, front, {id: "front", scope: "printing", imageSource: ""}),
                         Object.assign({}, back, {id: "back", scope: "printing", imageSource: ""})]
        waitForPolish(window)
        page.selectEntry("back", true)
        page.chooseExport()
        page.selectEntry("front", true)
        const file = findChild(page, "customArtExportPackDialog")
        compare(file.defaultSuffix, "hexproof-custom-artpack")
        file.selectedFile = "file:///tmp/share.hexproof-custom-artpack"
        file.accepted()
        file.close()
        compare(store.calls[2], ["back"])
        finishOperation("exportPack", true, "file:///tmp/share.hexproof-custom-artpack")
        page.inspectSource("file:///tmp/folder", "directory")
        const preview = findChild(page, "customArtImportPreviewDialog")
        finishInspection({ok: true, kind: "image", fileUrl: "file:///tmp/folder", rows: []})
        verify(!preview.opened)
        finishInspection({ok: true, kind: "directory", fileUrl: "file:///tmp/folder", rows: [], validCount: 0})
        tryVerify(() => preview.opened)
        verify(!preview.canImport)
        preview.close()
    }
}
