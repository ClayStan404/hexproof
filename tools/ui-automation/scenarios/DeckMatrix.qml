// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: driver

    readonly property string manifestFile: auditProbe.environment("AUDIT_DECK_MANIFEST")
    readonly property bool includeNegatives: auditProbe.environment("AUDIT_MATRIX_NEGATIVES") !== "0"
    readonly property bool includeRoundTrips: auditProbe.environment("AUDIT_MATRIX_ROUNDTRIP") === "1"
    readonly property string artifactDirectory: auditProbe.environment("AUDIT_OUTPUT")
    property var cases: []
    property var steps: []
    property var assertions: []
    property var outcomes: []
    property var screenshots: []
    property var sourceSnapshot: ({})
    property int initialDeckCount: 0
    property int expectedDeckCount: 0
    property int stepIndex: 0
    property int scrollAttempts: 0
    property bool actionComplete: false
    property bool dispatching: false
    property bool finished: false
    property bool sawCacheActivity: false
    property double started: Date.now()
    property double stepStarted: 0
    property double lastHeartbeat: Date.now()
    property double maximumHeartbeat: 0

    function require(value, message) {
        if (!value) throw new Error(message)
    }

    function page() { return auditWindow.stack.currentItem }

    function find(name, identity) {
        return auditProbe.find(auditWindow, name, identity || ({}))
    }

    function click(name, scrollName, direction) {
        const body = scrollName ? find(scrollName) : null
        if (body && (body.moving === true
                     || (body.contentItem && body.contentItem.moving === true))) return false
        const item = find(name)
        if (item) {
            require(auditProbe.click(item), "Cannot click " + name)
            scrollAttempts = 0
            return true
        }
        if (body && ++scrollAttempts <= 40)
            require(auditProbe.wheel(body, direction || -360), "Cannot scroll " + scrollName)
        return false
    }

    function fill(name, value, identity) {
        const item = find(name, identity)
        if (!item) return false
        require(auditProbe.click(item), "Cannot focus " + name)
        require(auditProbe.key(Qt.Key_A, Qt.ControlModifier), "Cannot select text in " + name)
        require(value.length ? auditProbe.text(value) : auditProbe.key(Qt.Key_Backspace),
                "Cannot type " + name)
        require(item.text === value, "Text input mismatch in " + name)
        return true
    }

    function selectOpenCombo(index) {
        require(index >= 0, "Requested option is unavailable")
        require(auditProbe.key(Qt.Key_Home), "Cannot reach first option")
        for (let n = 0; n < index; ++n)
            require(auditProbe.key(Qt.Key_Down), "Cannot reach option " + index)
        require(auditProbe.key(Qt.Key_Return), "Cannot accept option " + index)
    }

    function add(name, action, check, timeout) {
        steps.push({name: name, action: action, check: check || (() => true), timeout: timeout || 20000})
    }

    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        screenshots.push(name + ".png")
    }

    function exactKey(card) {
        return card.name + "\u001f" + String(card.setCode).toUpperCase()
            + "\u001f" + card.collectorNumber
    }

    function sourceText(deck) {
        const parentPath = manifestFile.slice(0, manifestFile.lastIndexOf("/") + 1)
        return auditProbe.readText(deck.textFile.startsWith("/") ? deck.textFile : parentPath + deck.textFile)
    }

    function loadCases() {
        require(manifestFile.length > 0, "AUDIT_DECK_MANIFEST must identify the independent fixture")
        const manifest = JSON.parse(auditProbe.readText(manifestFile))
        require(manifest.schema === "hexproof.card-shape-fixtures.v1", "Unsupported fixture manifest")
        require(manifest.rulesMode === "manual" && manifest.imagesPrecached === false,
                "Deck matrix requires the manual, uncached text fixture")
        sourceSnapshot = manifest.source
        const formats = ["custom", "standard", "pioneer", "modern", "legacy", "vintage",
                         "pauper", "duel", "commander", "cube"]
        for (const format of formats) {
            require(manifest.decks[format], "Missing supported format: " + format)
            const expected = JSON.parse(JSON.stringify(manifest.decks[format]))
            expected.name = "Matrix — " + expected.name
            cases.push({id: format, expected: expected, text: sourceText(expected), positive: true})
        }
        if (includeNegatives) {
            for (const id of Object.keys(manifest.negativeDecks).sort()) {
                const expected = JSON.parse(JSON.stringify(manifest.negativeDecks[id]))
                expected.name = "Matrix — " + expected.name
                cases.push({id: id, expected: expected, text: sourceText(expected), positive: false})
            }
        }
        const original = manifest.decks.modern
        const prepare = original.mainboard.find(card => card.setCode.toUpperCase() === "SOS"
            && card.collectorNumber === "13"
            && card.name === "Emeritus of Truce // Swords to Plowshares")
        require(prepare, "The independent fixture must include the SOS/13 Prepare regression")
        const alias = JSON.parse(JSON.stringify(original))
        alias.name = "Matrix — Modern Prepare characteristic"
        const aliasCard = alias.mainboard.find(card => card.id === prepare.id)
        aliasCard.name = "Swords to Plowshares"
        const text = sourceText(original).replace(prepare.name + " (SOS) 13",
                                                  aliasCard.name + " (SOS) 13")
        require(text !== sourceText(original), "Prepare input alias was not substituted")
        cases.push({id: "modern-prepare-characteristic", expected: alias, text: text, positive: true})
        require(auditProbe.record("fixture-cases", {source: sourceSnapshot, cases: cases}),
                "Cannot record independent fixture expectations")
    }

    function openNamedDeck(name) {
        const list = find("libraryDeckList")
        if (list && list.moving) return false
        const label = find("libraryDeckName", {text: name})
        if (label) {
            require(auditProbe.doubleClick(label), "Cannot open imported deck " + name)
            return true
        }
        if (list && ++scrollAttempts <= 40)
            require(auditProbe.wheel(list, 720), "Cannot reach newly imported deck")
        return false
    }

    function validateRows(expected, actual, zone) {
        require(expected.length === actual.length, zone + " printing rows were merged or split")
        const byKey = ({})
        for (const card of actual) {
            const key = exactKey(card)
            require(byKey[key] === undefined, zone + " has duplicate editable identity: " + key)
            byKey[key] = card
        }
        for (const card of expected) {
            const observed = byKey[exactKey(card)]
            require(observed && observed.count === card.count,
                    zone + " count or printing mismatch: " + exactKey(card))
            require(observed.typeLine.length > 0, "Missing offline metadata: " + card.name)
        }
    }

    function selectionState(expected) {
        // These const projection queries observe the result of native UI
        // mutations. They do not select a deck, send a command, or change state.
        const choices = deckLibrary.matchDecks(expected.deckFormat, true)
        const selected = choices.find(deck => deck.deckId === deckLibrary.currentDeckId)
        require(selected, "Imported deck is absent from its format selection model")
        return selected
    }

    function validationReady() {
        return !deckLibrary.importingDeck
            && deckLibrary.currentStatus !== "Checking deck legality…"
            && deckLibrary.currentValidationVerified
            && !deckLibrary.mainCards.some(card => !card.typeLine)
            && !deckLibrary.sideboardCards.some(card => !card.typeLine)
    }

    function validateCase(testCase) {
        const expected = testCase.expected
        require(deckLibrary.currentDeckName === expected.name, "Wrong deck is open")
        require(deckLibrary.currentDeckFormat === expected.deckFormat, "Import changed the deck format")
        require(deckLibrary.currentDeckTableMode === expected.tableMode, "Incorrect derived table mode")
        require(deckLibrary.currentMainCount === expected.mainCount, "Main count changed")
        require(deckLibrary.currentSideboardCount === expected.sideCount, "Sideboard count changed")
        validateRows(expected.mainboard, Array.from(deckLibrary.mainCards), "Main")
        validateRows(expected.sideboard, Array.from(deckLibrary.sideboardCards), "Sideboard")
        const actualCommanders = deckLibrary.mainCards.filter(card => card.commander).map(card => card.name).sort()
        require(JSON.stringify(actualCommanders) === JSON.stringify(expected.commanders.slice().sort()),
                "Commander designation changed")
        const selection = selectionState(expected)
        require(selection.ready === expected.validationExpectation.valid,
                "Unexpected selection acceptance: " + testCase.id + "; " + selection.status
                + "; " + JSON.stringify(selection.legalityIssues))
        const warnings = Array.from(deckLibrary.currentValidationWarnings)
        const issues = Array.from(deckLibrary.currentValidationIssues)
        if (testCase.positive) {
            require(warnings.length === 0 && issues.length === 0,
                    "Legal fixture acquired validation issues: " + JSON.stringify(issues))
        } else {
            require(issues.length > 0, "Invalid/advisory fixture has no explanation")
            require((warnings.length > 0) === (expected.validationExpectation.warning === true),
                    "Blocking and advisory policy were confused")
        }
        for (const format of ["custom", "standard", "pioneer", "modern", "legacy", "vintage",
                              "pauper", "duel", "commander", "cube"]) {
            if (format === expected.deckFormat) continue
            require(!deckLibrary.matchDecks(format, true).some(deck => deck.deckId === deckLibrary.currentDeckId),
                    "Deck leaked into another format selector: " + format)
        }
        const result = {id: testCase.id, name: expected.name, format: expected.deckFormat,
            deckId: deckLibrary.currentDeckId, tableMode: deckLibrary.currentDeckTableMode,
            mainCount: deckLibrary.currentMainCount, sideCount: deckLibrary.currentSideboardCount,
            commanders: actualCommanders, verified: deckLibrary.currentValidationVerified,
            selectionAcceptedIgnoringArt: selection.ready, status: deckLibrary.currentStatus,
            issues: issues, warnings: warnings, missingImages: deckLibrary.currentMissingImageCount,
            shapeCoverage: expected.shapeCoverage, unavailableShapes: expected.unavailableShapes,
            exactMain: Array.from(deckLibrary.mainCards), exactSide: Array.from(deckLibrary.sideboardCards)}
        outcomes.push(result)
        require(auditProbe.record("case-" + testCase.id, result), "Cannot record case outcome")
        capture("deck-" + testCase.id)
    }

    function quantityButton(card, name) {
        const row = find("deckCardRow-" + card.name, {"card.setCode": card.setCode,
                         "card.collectorNumber": card.collectorNumber})
        if (!row) return false
        const button = auditProbe.find(row, name)
        if (!button) return false
        require(auditProbe.click(button), "Cannot activate " + name)
        return true
    }

    function appendRoundTrip(testCase) {
        const expected = JSON.parse(JSON.stringify(testCase.expected))
        expected.name += " (file round trip)"
        const copy = {id: testCase.id + "-file-roundtrip", expected: expected, positive: true}
        const savedPath = artifactDirectory + "/deck-export-" + testCase.id + ".txt"
        const label = copy.id + ": "
        let originalDeckId = ""
        let savedText = ""
        add(label + "Open actual editor export", () => {
            originalDeckId = deckLibrary.currentDeckId
            return click("exportCurrentDeckButton", "deckEditorBody", 360)
        }, () => !!find("saveDeckExportButton"))
        add(label + "Choose text file export", () => click("saveDeckExportButton"),
            () => auditProbe.fileDialogState("exportDeckFileDialog").visible === true)
        add(label + "Save through the native file chooser", () => {
            require(auditProbe.chooseFile("exportDeckFileDialog", savedPath),
                    "Cannot save the exported deck through native input")
        }, () => auditProbe.fileDialogState("exportDeckFileDialog").visible === false)
        add(label + "Observe the exported file", () => {
            savedText = auditProbe.readText(savedPath)
            require(savedText.length > 0, "Native export did not create a nonempty text file")
            require(auditProbe.record("export-" + testCase.id, {path: savedPath,
                sourceDeckId: originalDeckId, textLength: savedText.length}),
                "Cannot record exported-file provenance")
        })
        add(label + "Return to library for a fresh import", () => click("screenBackButton"),
            () => !!find("deckLibraryImportButton"))
        add(label + "Open import form", () => click("deckLibraryImportButton"),
            () => !!find("importDeckName"))
        add(label + "Name the independently imported copy", () => fill("importDeckName", expected.name))
        add(label + "Open format selector", () => click("importDeckFormat"),
            () => { const item = find("importDeckFormat"); return item && item.popup.visible })
        add(label + "Select the original format", () => {
            selectOpenCombo(page().formatOptions.findIndex(option => option.value === expected.deckFormat))
        }, () => page().deckFormat === expected.deckFormat)
        add(label + "Open the native deck-list picker", () => click("chooseDeckListFileButton"),
            () => auditProbe.fileDialogState("importDeckFileDialog").visible === true)
        add(label + "Select the file produced by the editor", () => {
            require(auditProbe.chooseFile("importDeckFileDialog", savedPath),
                    "Cannot select the exported file through native input")
        }, () => {
            const text = find("importDeckText")
            return auditProbe.fileDialogState("importDeckFileDialog").visible === false
                && text && text.text === savedText
        })
        add(label + "Import the file through the visible form", () => {
            const submitted = click("importDeckSubmitButton", "importDeckBody")
            if (submitted) ++expectedDeckCount
            return submitted
        }, () => !deckLibrary.importingDeck && deckLibrary.count === expectedDeckCount
            && !!find("deckLibraryImportButton"), 60000)
        add(label + "Open the newly imported copy", () => openNamedDeck(expected.name),
            () => deckLibrary.currentDeckName === expected.name && !!find("deckFormatSelector"))
        add(label + "Compare every printing against the independent fixture", () => {}, () => {
            if (!validationReady()) return false
            require(deckLibrary.currentDeckId !== originalDeckId,
                    "File import reused the edited deck instead of creating a new deck")
            validateCase(copy)
            return true
        }, 60000)
    }

    function appendCase(testCase) {
        const expected = testCase.expected
        const label = testCase.id + ": "
        add(label + "Open real import form", () => click("deckLibraryImportButton"),
            () => !!find("importDeckName"))
        add(label + "Enter deck name", () => fill("importDeckName", expected.name))
        add(label + "Open format selector", () => click("importDeckFormat"),
            () => { const item = find("importDeckFormat"); return item && item.popup.visible })
        add(label + "Select supported deck format", () => {
            selectOpenCombo(page().formatOptions.findIndex(option => option.value === expected.deckFormat))
        }, () => page().deckFormat === expected.deckFormat)
        add(label + "Enter independent import text", () => fill("importDeckText", testCase.text))
        add(label + "Import without requesting card-art cache", () => {
            const submitted = click("importDeckSubmitButton", "importDeckBody")
            if (submitted) ++expectedDeckCount
            return submitted
        }, () => !deckLibrary.importingDeck && deckLibrary.count === expectedDeckCount
            && !!find("deckLibraryImportButton"), 60000)
        add(label + "Open imported deck through its visible row", () => openNamedDeck(expected.name),
            () => deckLibrary.currentDeckName === expected.name && !!find("deckFormatSelector"))
        add(label + "Verify exact printings and actual validation", () => {}, () => {
            if (!validationReady()) return false
            validateCase(testCase)
            return true
        }, 60000)
        if (testCase.positive) {
            const editCard = expected.mainboard.find(card => card.shapes.indexOf("basic_land") >= 0)
                || expected.mainboard.find(card => expected.commanders.indexOf(card.name) < 0)
            add(label + "Find an exact printing for reversible quantity edit", () =>
                fill("workbenchSearch", editCard.name, {placeholderText: "Search this deck…"}))
            add(label + "Open editor view selector", () => click("deckEditorViewMode"),
                () => { const item = find("deckEditorViewMode"); return item && item.popup.visible })
            add(label + "Use native list controls", () => selectOpenCombo(0),
                () => !!find("deckCardRow-" + editCard.name))
            add(label + "Increase printing quantity", () => quantityButton(editCard, "increaseDeckCardCountButton"),
                () => deckLibrary.currentMainCount === expected.mainCount + 1)
            add(label + "Restore printing quantity", () => quantityButton(editCard, "decreaseDeckCardCountButton"),
                () => deckLibrary.currentMainCount === expected.mainCount)
            add(label + "Verify all identities after edits", () => {}, () => {
                if (!validationReady()) return false
                validateRows(expected.mainboard, Array.from(deckLibrary.mainCards), "Edited main")
                require(selectionState(expected).ready, "Reverted legal deck stayed unavailable")
                return true
            }, 30000)
            if (includeRoundTrips) appendRoundTrip(testCase)
        }
        add(label + "Return to deck library", () => click("screenBackButton"),
            () => !!find("deckLibraryImportButton"))
    }

    function plan() {
        loadCases()
        add("Dismiss first-launch notices", () => {
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"]) {
                const notice = find(name)
                if (notice) {
                    require(auditProbe.click(notice), "Cannot dismiss " + name)
                    return false
                }
            }
            return !!find("mainMenuDeckLibraryButton")
        })
        add("Record installed-catalog starting state", () => {
            require(preferences.uiLanguage === "en", "Deck matrix requires English UI")
            require(cardCatalog.installed && cardCatalog.installedCatalogSchemaVersion === 10,
                    "A previously installed catalog is required")
            initialDeckCount = deckLibrary.count
            expectedDeckCount = initialDeckCount
            require(auditProbe.record("starting-state", {catalogVersion: cardCatalog.installedCatalogVersion,
                schema: cardCatalog.installedCatalogSchemaVersion, source: sourceSnapshot,
                initialDeckCount: initialDeckCount,
                catalogSetup: "Preinstalled catalog or previous native bootstrap stage",
                artPolicy: "Import is metadata-only; no Cache art command is sent by this scenario"}),
                "Cannot record starting state")
            capture("matrix-start")
        })
        add("Open native deck library", () => click("mainMenuDeckLibraryButton", "mainMenuBody"),
            () => !!find("deckLibraryImportButton"))
        for (const testCase of cases) appendCase(testCase)
        add("Verify the complete imported library", () => {
            const copies = includeRoundTrips ? cases.filter(testCase => testCase.positive).length : 0
            require(deckLibrary.count === initialDeckCount + cases.length + copies,
                    "Imported library lost a case")
            capture("matrix-library")
        })
    }

    function finish(status, error) {
        if (finished) return
        finished = true
        auditProbe.record("result", {status: status, scenario: "deck-matrix", error: error || "",
            requiredScreenshots: screenshots, assertions: assertions, outcomes: outcomes,
            completedSteps: stepIndex,
            plannedCases: cases.length + (includeRoundTrips ? cases.filter(testCase => testCase.positive).length : 0),
            completedCases: outcomes.length,
            pendingStep: stepIndex < steps.length ? steps[stepIndex].name : "",
            elapsedMs: Date.now() - started, sawCacheActivity: sawCacheActivity,
            coverage: "Native UI import and reversible quantity edits; exact identity, catalog policy and selection-model projections",
            notRun: ["Room/server acceptance (covered by match scenarios)", "Explicit card-art caching"]
                .concat(includeRoundTrips ? [] : ["File export and reimport"]),
            excluded: ["Forge"], includeNegatives: includeNegatives,
            fileExportAndReimport: includeRoundTrips})
        auditProbe.finish(status === "passed" ? 0 : 1)
    }

    Component.onCompleted: {
        try { plan() } catch (error) { finish("failed", String(error)) }
    }

    Timer {
        interval: 16
        running: !driver.finished
        repeat: true
        onTriggered: {
            const now = Date.now()
            driver.maximumHeartbeat = Math.max(driver.maximumHeartbeat, now - driver.lastHeartbeat)
            driver.lastHeartbeat = now
            if (cardCatalog.cacheProgressActive) driver.sawCacheActivity = true
        }
    }

    Timer {
        interval: 150
        running: !driver.finished
        repeat: true
        onTriggered: {
            if (driver.dispatching) return
            driver.dispatching = true
            try {
                if (driver.stepIndex >= driver.steps.length) {
                    driver.finish("passed", "")
                    return
                }
                const step = driver.steps[driver.stepIndex]
                if (driver.stepStarted === 0) {
                    driver.stepStarted = Date.now()
                    driver.maximumHeartbeat = 0
                    driver.scrollAttempts = 0
                }
                driver.require(Date.now() - driver.stepStarted < step.timeout,
                    "Timed out: " + step.name + "; " + deckLibrary.lastError + "; " + deckLibrary.currentStatus)
                if (auditWindow.stack.busy) return
                if (!driver.actionComplete) driver.actionComplete = step.action() !== false
                if (!driver.actionComplete || !step.check()) return
                driver.assertions.push({name: step.name, status: "passed",
                    elapsedMs: Date.now() - driver.stepStarted, maximumHeartbeatMs: driver.maximumHeartbeat})
                driver.require(auditProbe.record("assertions", driver.assertions), "Cannot record assertions")
                ++driver.stepIndex
                driver.stepStarted = 0
                driver.actionComplete = false
            } catch (error) {
                auditProbe.record("failure-observation", auditProbe.observe(auditWindow))
                auditProbe.record("failure-selector", {lastError: auditProbe.lastError})
                auditProbe.capture(auditWindow, "failure")
                driver.finish("failed", String(error))
            } finally {
                driver.dispatching = false
            }
        }
    }
}
