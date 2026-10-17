// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

// Production modal panels, real installed catalog/printing/art resolution.
// Only the two search-result rows and opening the panels are explicit fixtures.
// This is a system-input panel probe, not a live engine game or deck edit.
Item {
    id: driver
    property var steps: []
    property var assertions: []
    property var screenshots: []
    property var printingPicker: null
    property var searchPopup: null
    property var savedPreferences: ({})
    property var expectedPrinting: ({})
    property bool cacheRequested: false
    property int chosenCount: 0
    property int addCount: 0
    property int searchRequestCount: 0
    property int index: 0
    property bool acted: false
    property bool dispatching: false
    property bool finished: false
    property double stepStarted: Date.now()
    readonly property var delver: ({instanceId:"panel-delver", name:"Delver of Secrets // Insectile Aberration",
                                   setCode:"ISD", collectorNumber:"51"})
    readonly property var roku: ({instanceId:"panel-roku", name:"The Legend of Roku // Avatar Roku",
                                 setCode:"TLA", collectorNumber:"357"})

    function require(value, message) {
        if (!value) throw new Error(message + (auditProbe.lastError ? "; " + auditProbe.lastError : ""))
    }
    function find(name, scope) {
        return auditProbe.find(scope && scope.contentItem ? scope.contentItem : scope || auditWindow, name)
    }
    function lookup(name, scope) {
        if (!scope) return null
        if (scope.objectName === name) return scope
        for (const child of scope.children || []) {
            const found = lookup(name, child)
            if (found) return found
        }
        return null
    }
    function add(name, action, check, timeout) {
        steps.push({name:name, action:action, check:check || (() => true), timeout:timeout || 20000})
    }
    function waited(ms) { return Date.now() - stepStarted >= ms }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        screenshots.push(name + ".png")
    }
    function click(name, scope) { require(auditProbe.click(find(name, scope)), "Cannot click " + name) }
    function hover(name, scope) { require(auditProbe.hover(find(name, scope)), "Cannot hover " + name) }
    function faceState(scope) {
        if (scope && scope.facePreview) return scope.facePreview
        const gallery = lookup("printingFaceGallery", scope && scope.contentItem)
        return gallery ? gallery.controller : null
    }
    function searchPreview() {
        return searchPopup && lookup("cardHoverPreview", searchPopup.contentItem.parent)
    }
    function ready(scope, artName, expectedName, printingArt) {
        const state = faceState(scope)
        if (!state) return false
        const index = state.displayFaces.findIndex(face => face.name === expectedName)
        if (index < 0) return false
        const art = lookup(artName + (index ? "-" + index : ""), scope && scope.contentItem ? scope.contentItem : scope)
        if (!art || art.status !== Image.Ready) return false
        const viewed = state.displayFaces[index].card
        const exactSource = printingArt
            ? cardCatalog.printingImageSource(viewed.name, viewed.setCode, viewed.collectorNumber)
            : cardCatalog.imageSource(expectedName, viewed.setCode, viewed.collectorNumber)
        return !!exactSource && String(art.source) === String(exactSource)
    }
    function unchangedPrinting() {
        require(chosenCount === 0, "Local face inspection selected a printing")
        require(JSON.stringify(printingPicker.previewPrinting) === JSON.stringify(expectedPrinting),
                "Local face inspection replaced the printing object")
        require(printingPicker.currentSetCode === expectedPrinting.setCode
            && printingPicker.currentCollectorNumber === expectedPrinting.collectorNumber
            && printingPicker.previewIsCurrent, "The exact current printing changed")
    }
    function unchangedSearch() {
        require(addCount === 0 && searchPopup.selectedCard === null,
                "Hover face inspection selected or added a search result")
        require(searchPopup.results.length === 2 && searchPopup.results[0].instanceId === delver.instanceId
            && searchPopup.results[1].instanceId === roku.instanceId, "Search rows changed during preview")
    }
    function finish(error) {
        if (finished) return
        finished = true
        if (error && auditProbe.capture(auditWindow, "failure")) screenshots.push("failure.png")
        if (printingPicker) { printingPicker.close(); printingPicker.destroy() }
        if (searchPopup) { searchPopup.close(); searchPopup.destroy() }
        if (savedPreferences.uiLanguage !== undefined) preferences.uiLanguage = savedPreferences.uiLanguage
        if (savedPreferences.cardLanguage !== undefined) preferences.cardLanguage = savedPreferences.cardLanguage
        const geometry = auditProbe.observe(auditWindow)
        auditProbe.record("window-geometry", geometry)
        auditProbe.record("result", {status:error ? "failed" : "passed", scenario:"card-face-panels",
            evidence:auditProbe.environment("HEXPROOF_AUDIT_OS_INPUT_HELPER") ? "system-input" : "native-qt-input",
            setup:"production-modal-panels-and-two-fixed-search-result-rows", liveEngineGame:false,
            realInstalledCatalog:true, realCatalogPrintingList:true, fixtureCards:[delver, roku],
            error:error || "", pendingStep:index < steps.length ? steps[index].name : "",
            assertions:assertions, requiredScreenshots:screenshots, printingsChosen:chosenCount,
            cardsAdded:addCount, searchRequests:searchRequestCount,
            windowMode:geometry.windowMode, width:geometry.width, height:geometry.height,
            dpr:geometry.dpr, screenGeometry:geometry.screenGeometry})
        auditProbe.finish(error ? 1 : 0)
    }
    function plan() {
        add("Dismiss first-launch notices", () => {
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"]) {
                if (find(name)) { click(name); return false }
            }
            return true
        })
        add("Prepare two exact printings with the real catalog", () => {
            require(auditProbe.observe(auditWindow).windowMode === "maximized", "Expected a maximized window")
            require(cardCatalog.installed, "An installed card database is required")
            savedPreferences = {uiLanguage:preferences.uiLanguage, cardLanguage:preferences.cardLanguage}
            preferences.uiLanguage = "en"
            preferences.cardLanguage = "en"
            for (const card of [delver, roku])
                if (typeof cardCatalog.prepareCardFacePreview === "function")
                    cardCatalog.prepareCardFacePreview(card.name, card.setCode, card.collectorNumber)
            auditProbe.fixture("card-face-panels", {description:"PrintingPicker and CardSearchPopup production controls; fixed search rows only; no live game",
                cards:[delver, roku], realCatalogMethods:["cardFaces", "printings", "imageSource", "printingImageSource"]})
        }, () => {
            const groups = [delver, roku].map(card => cardCatalog.cardFaces(card.name, card.setCode, card.collectorNumber))
            if (groups.some(faces => faces.length !== 2)) return false
            if (!cacheRequested) {
                const requests = []
                for (const faces of groups)
                    for (const face of faces) requests.push(face)
                cardCatalog.prioritizeCards(requests)
                cacheRequested = true
            }
            return groups.every(faces => faces.every(face => !!cardCatalog.imageSource(
                face.faceName || face.name, face.setCode, face.collectorNumber)))
        }, 60000)
        add("Open the production PrintingPicker on ISD 51", () => {
            const component = Qt.createComponent("qrc:/qml/components/PrintingPicker.qml")
            require(component.status === Component.Ready, component.errorString())
            printingPicker = component.createObject(auditWindow.contentItem, {catalogModel:cardCatalog})
            require(printingPicker, "Cannot create PrintingPicker")
            printingPicker.chosen.connect(() => { chosenCount++ })
            printingPicker.showFor(delver, false)
            expectedPrinting = Object.assign({}, printingPicker.previewPrinting)
            require(expectedPrinting.setCode === "ISD" && expectedPrinting.collectorNumber === "51",
                    "The real printing query did not preserve ISD 51")
        }, () => printingPicker.opened && ready(printingPicker, "printingPreviewImage", "Delver of Secrets", true))
        add("Read both exact printing faces without a switch", () => {
            unchangedPrinting()
            require(printingPicker.modal, "Expected the real modal ancestor")
            require(!lookup("viewOtherFaceButton", printingPicker.contentItem), "Unexpected face switch")
        }, () => ready(printingPicker, "printingPreviewImage", "Delver of Secrets", true)
            && ready(printingPicker, "printingPreviewImage", "Insectile Aberration", true))
        add("Capture both exact faces without choosing a printing", () => {
            unchangedPrinting()
            require(!lookup("usePrintingButton", printingPicker.contentItem).enabled,
                    "Viewing a back enabled Use version for the current printing")
            auditProbe.record("printing-back", {printing:expectedPrinting, viewed:faceState(printingPicker).viewedCard,
                imageSources:faceState(printingPicker).displayFaces.map(face => face.imageSource), chosenCount:chosenCount})
            capture("printing-delver-both-faces")
            require(auditProbe.key(Qt.Key_Escape), "Cannot dismiss PrintingPicker")
        }, () => !printingPicker.opened)
        add("Reopen the same printing and verify the front resets", () => printingPicker.showFor(delver, false),
            () => printingPicker.opened && ready(printingPicker, "printingPreviewImage", "Delver of Secrets", true))
        add("Replace the picker source with the exact Roku printing", () => {
            unchangedPrinting()
            printingPicker.showFor(roku, false)
            expectedPrinting = Object.assign({}, printingPicker.previewPrinting)
            require(expectedPrinting.setCode === "TLA" && expectedPrinting.collectorNumber === "357",
                    "The real printing query did not preserve TLA 357")
        }, () => ready(printingPicker, "printingPreviewImage", "The Legend of Roku", true))
        add("Capture the new printing front and dismiss the picker", () => {
            unchangedPrinting()
            capture("printing-roku-reset-front")
            require(auditProbe.key(Qt.Key_Escape), "Cannot dismiss PrintingPicker")
        }, () => !printingPicker.opened)
        add("Open the production CardSearchPopup with a recorded result fixture", () => {
            const component = Qt.createComponent("qrc:/qml/components/CardSearchPopup.qml")
            require(component.status === Component.Ready, component.errorString())
            searchPopup = component.createObject(auditWindow.contentItem, {catalogModel:cardCatalog})
            require(searchPopup, "Cannot create CardSearchPopup")
            searchPopup.searchRequested.connect(() => {
                searchRequestCount++
                searchPopup.results = [delver, roku]
            })
            searchPopup.addRequested.connect(() => { addCount++ })
            searchPopup.openSearch()
        }, () => waited(300) && searchPopup.opened && !!find("workbenchSearch", searchPopup))
        add("Enter a query through the focused modal text field", () => {
            click("workbenchSearch", searchPopup)
            require(auditProbe.text("card face fixture"), "Cannot enter the search fixture query")
        }, () => !searchPopup.searchPending && !!find("workbenchCard-panel-delver", searchPopup))
        add("Hover Delver's search result without selecting it", () => hover("workbenchCard-panel-delver", searchPopup),
            () => searchPreview() && searchPreview().visible
                && ready(searchPreview(), "cardHoverPreviewArt", "Delver of Secrets", false))
        add("Read both search faces without selecting a result", () => {
            unchangedSearch()
            require(searchPopup.modal, "Expected the real search modal ancestor")
            require(searchPreview().sourceActive || searchPreview().previewHeld,
                    "The pointer must remain over the search card or its preview")
        }, () => waited(550) && searchPreview().visible
            && ready(searchPreview(), "cardHoverPreviewArt", "Delver of Secrets", false)
            && ready(searchPreview(), "cardHoverPreviewArt", "Insectile Aberration", false))
        add("Capture the held back with no add or selection", () => {
            unchangedSearch()
            capture("search-delver-both-faces")
            auditProbe.record("search-back", {source:searchPreview().card, viewed:searchPreview().facePreview.viewedCard,
                imageSource:String(lookup("cardHoverPreviewArt", searchPreview()).source), added:addCount, selected:searchPopup.selectedCard})
            preferences.uiLanguage = "zh_CN"
        }, () => waited(300) && ready(searchPreview(), "cardHoverPreviewArt", "Delver of Secrets", false)
            && ready(searchPreview(), "cardHoverPreviewArt", "Insectile Aberration", false))
        add("Keep both faces inside the Chinese search modal boundary", () => {
            unchangedSearch()
            const button = searchPreview()
            const boundary = searchPopup.contentItem.parent
            const point = button.mapToItem(boundary, 0, 0)
            auditProbe.record("translated-preview-boundary", {x:point.x, y:point.y,
                width:button.width, height:button.height,
                boundaryWidth:boundary.width, boundaryHeight:boundary.height})
            require(point.x >= 0 && point.y >= 0
                && point.x + button.width <= boundary.width + 1
                && point.y + button.height <= boundary.height + 1,
                "Dual-face preview exceeds the search modal boundary")
            require(ready(searchPreview(), "cardHoverPreviewArt", "Insectile Aberration", false),
                    "Changing UI language lost an inspected card face")
            capture("search-delver-both-faces-chinese-ui")
            preferences.uiLanguage = "en"
            click("workbenchSearch", searchPopup)
        }, () => waited(500) && !searchPreview().visible)
        add("Hover the other search row and verify source reset", () => hover("workbenchCard-panel-roku", searchPopup),
            () => ready(searchPreview(), "cardHoverPreviewArt", "The Legend of Roku", false))
        add("Capture the changed hover source and verify reset", () => {
            unchangedSearch()
            require(searchPreview().card.instanceId === roku.instanceId && searchPreview().facePreview.faceIndex === 0,
                    "Changing the search source retained the previous back")
            capture("search-roku-reset-front")
            click("cardSearchDoneButton", searchPopup)
        }, () => !searchPopup.opened && (!searchPreview() || !searchPreview().visible))
    }

    Component.onCompleted: plan()
    Timer {
        interval: 60
        repeat: true
        running: !driver.finished
        onTriggered: {
            if (driver.dispatching || auditWindow.stack.busy) return
            driver.dispatching = true
            try {
                if (driver.index >= driver.steps.length) { driver.finish(""); return }
                const step = driver.steps[driver.index]
                if (!driver.acted) {
                    if (step.action() === false) {
                        driver.require(Date.now() - driver.stepStarted < step.timeout, "Cannot reach " + step.name)
                        return
                    }
                    driver.acted = true
                }
                if (step.check()) {
                    driver.assertions.push({step:step.name, elapsedMs:Date.now() - driver.stepStarted})
                    driver.index++
                    driver.acted = false
                    driver.stepStarted = Date.now()
                } else driver.require(Date.now() - driver.stepStarted < step.timeout, "Timed out: " + step.name)
            } catch (error) { driver.finish(String(error)) }
            finally { driver.dispatching = false }
        }
    }
}
