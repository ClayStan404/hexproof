// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: driver

    readonly property string mode: auditProbe.environment("AUDIT_ART_TRANSFER_MODE") || "export"
    readonly property string manifestFile: auditProbe.environment("AUDIT_DECK_MANIFEST")
    readonly property string variant: auditProbe.environment("AUDIT_VARIANT") || "modern"
    readonly property string artifactDirectory: auditProbe.environment("AUDIT_OUTPUT")
    readonly property string packFile: mode === "export"
        ? artifactDirectory + "/complex-deck.hexproof-artpack" : auditProbe.environment("AUDIT_ART_PACK")
    readonly property string invalidPack: auditProbe.environment("AUDIT_INVALID_ART_PACK")
    property var expectedDeck: ({})
    property string importText: ""
    property var exportResult: ({})
    property var firstInventory: ({})
    property var firstCache: ({})
    property var duplicateBaselineInventory: ({})
    property var duplicateBaselineCache: ({})
    property var faces: []
    property int inspectionCount: 0
    property int previousInspectionCount: 0
    property int inventoryCount: 0
    property int previousInventoryCount: 0
    property var steps: []
    property var assertions: []
    property var screenshots: []
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

    function find(name, identity) {
        return auditProbe.find(auditWindow, name, identity || ({}))
    }

    function click(name, scrollName, direction, identity) {
        const body = scrollName ? find(scrollName) : null
        if (body && (body.moving === true
                     || (body.contentItem && body.contentItem.moving === true))) return false
        const item = find(name, identity)
        if (item) {
            require(auditProbe.click(item), "Cannot click " + name)
            scrollAttempts = 0
            return true
        }
        if (body && ++scrollAttempts <= 45)
            require(auditProbe.wheel(body, direction || -360), "Cannot scroll " + scrollName)
        return false
    }

    function fill(name, value) {
        const item = find(name)
        if (!item) return false
        require(auditProbe.click(item), "Cannot focus " + name)
        require(auditProbe.key(Qt.Key_A, Qt.ControlModifier), "Cannot select text")
        require(auditProbe.text(value), "Cannot enter " + name)
        require(item.text === value, "Text input mismatch")
        return true
    }

    function add(name, action, check, timeout) {
        steps.push({name: name, action: action, check: check || (() => true), timeout: timeout || 30000})
    }

    function record(name, value) {
        require(auditProbe.record(name, value), "Cannot record " + name)
    }

    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        screenshots.push(name + ".png")
    }

    function loadFixture() {
        require(mode === "export" || mode === "import", "Unknown art-transfer mode")
        require(packFile.startsWith("/"), "An absolute AUDIT_ART_PACK is required for import")
        const manifest = JSON.parse(auditProbe.readText(manifestFile))
        require(manifest.schema === "hexproof.card-shape-fixtures.v1" && manifest.decks[variant],
                "An independent real-card fixture is required")
        expectedDeck = manifest.decks[variant]
        const directory = manifestFile.slice(0, manifestFile.lastIndexOf("/") + 1)
        importText = auditProbe.readText(directory + expectedDeck.textFile)
        require(importText.length > 0, "The fixture import text is empty")
        record("expected-deck", {source: manifest.source, deck: expectedDeck})
    }

    function cacheSnapshot() {
        return JSON.parse(auditProbe.readText(auditProbe.environment("XDG_DATA_HOME")
                         + "/Hexproof/Hexproof/card-cache.json"))
    }

    function inventory() { return JSON.parse(JSON.stringify(cardArtManager.inventory)) }

    function requireEmptyInventory() {
        const value = inventory()
        require(value.imageCount === 0 && value.indexedEntryCount === 0
                && value.missingEntryCount === 0 && value.orphanCount === 0,
                "The receiving profile is not cold or an operation left partial files: " + JSON.stringify(value))
    }

    function validateDeck(expectArt) {
        require(deckLibrary.currentDeckName === expectedDeck.name, "Wrong deck is open")
        require(deckLibrary.currentMainCount === expectedDeck.mainCount
                && deckLibrary.currentSideboardCount === expectedDeck.sideCount, "Deck counts changed")
        require(deckLibrary.currentDeckFormat === expectedDeck.deckFormat, "Deck format changed")
        const pairs = [[expectedDeck.mainboard, Array.from(deckLibrary.mainCards)],
                       [expectedDeck.sideboard, Array.from(deckLibrary.sideboardCards)]]
        faces = []
        for (const pair of pairs) {
            require(pair[0].length === pair[1].length, "Exact printing rows were merged or lost")
            for (const expected of pair[0]) {
                const actual = pair[1].find(card => card.name === expected.name
                    && card.setCode.toUpperCase() === expected.setCode.toUpperCase()
                    && card.collectorNumber === expected.collectorNumber)
                require(actual && actual.count === expected.count, "Printing changed: " + expected.name)
                require(actual.typeLine.length > 0, "Metadata missing: " + expected.name)
                if (!expectArt) continue
                require(actual.imageSource.startsWith("file:"), "Editor art missing: " + expected.name)
                const sources = []
                for (const face of expected.faces) {
                    // A const lookup observes availability without requesting a
                    // download or using the app's face list as our expectation.
                    const source = cardCatalog.imageSource(face, expected.setCode, expected.collectorNumber)
                    require(source.startsWith("file:"), "Cached face missing: " + face)
                    sources.push(source)
                    faces.push({cardName: expected.name, faceName: face, setCode: expected.setCode,
                        collectorNumber: expected.collectorNumber, imageSource: source})
                }
                if (expected.imageFaceCount === 2)
                    require(sources.length === 2 && sources[0] !== sources[1],
                            "Independent faces collapsed to the same image: " + expected.name)
            }
        }
        require(expectArt ? deckLibrary.currentMissingImageCount === 0
                          : deckLibrary.currentMissingImageCount === expectedDeck.mainboard.length + expectedDeck.sideboard.length,
                "Unexpected missing-art count")
        if (expectArt) require(deckLibrary.currentReady, "The transferred deck is not playable")
        record(expectArt ? "available-deck-faces" : "cold-deck", {
            mainboard: Array.from(deckLibrary.mainCards), sideboard: Array.from(deckLibrary.sideboardCards),
            missingImages: deckLibrary.currentMissingImageCount, faces: faces})
    }

    function openExpectedDeck() {
        const item = find("libraryDeckName", {text: expectedDeck.name})
        if (!item) return false
        require(auditProbe.doubleClick(item), "Cannot open the imported deck")
        return true
    }

    function appendOpenDeck(expectArt) {
        add("Open the exact fixture deck", () => openExpectedDeck(),
            () => deckLibrary.currentDeckName === expectedDeck.name && !!find("deckFormatSelector"))
        add(expectArt ? "Verify every printing and independent image face" : "Verify the imported deck is still uncached",
            () => {}, () => {
                if (!deckLibrary.currentValidationVerified || deckLibrary.currentStatus === "Checking deck legality…") return false
                validateDeck(expectArt)
                capture(expectArt ? "deck-with-transferred-art" : "deck-before-art-import")
                return true
            })
    }

    function appendExport() {
        add("Open the cached deck library", () => click("mainMenuDeckLibraryButton"),
            () => !!find("deckLibraryImportButton"))
        appendOpenDeck(true)
        add("Open the production export menu", () => click("exportCurrentDeckButton", "deckEditorBody", 360),
            () => !!find("exportDeckArtButton"))
        add("Choose this deck's card-art export", () => click("exportDeckArtButton", "deckExportBody"),
            () => !!find("saveDeckArtPackButton"))
        add("Choose the native card-art save dialog", () => click("saveDeckArtPackButton"),
            () => auditProbe.fileDialogState("currentDeckArtExportFileDialog").visible === true)
        add("Save a new real card-art container", () => {
            require(auditProbe.chooseFile("currentDeckArtExportFileDialog", packFile), "Cannot select the pack destination")
        }, () => auditProbe.fileDialogState("currentDeckArtExportFileDialog").visible === false)
        add("Verify completed export and face coverage", () => {}, () => {
            if (cardArtManager.busy || exportResult.ok === undefined) return false
            require(exportResult.ok && cardArtManager.lastError.length === 0,
                    "Art export failed: " + JSON.stringify(exportResult))
            const count = expectedDeck.mainboard.length + expectedDeck.sideboard.length
            const faceCount = expectedDeck.mainboard.concat(expectedDeck.sideboard)
                .reduce((sum, card) => sum + card.imageFaceCount, 0)
            require(exportResult.requestedPrintingCount >= count && exportResult.requestedFaceCount >= faceCount,
                    "Export omitted requested printings or faces")
            // Several exact face records can share one content-addressed image.
            // The independent verifier checks every face mapping and blob hash.
            require(exportResult.imageCount > 0 && exportResult.entryCount >= faceCount
                    && exportResult.entryCount >= exportResult.imageCount
                    && exportResult.bytes > 0 && exportResult.faceCoverageVerified
                    && exportResult.missingPrintingCount === 0 && exportResult.missingFaceCount === 0
                    && exportResult.skippedEntryCount === 0, "The exported pack is partial")
            record("export-completed", {file: packFile, result: exportResult, expectedFaces: faces})
            capture("export-completed")
            return true
        }, 90000)
    }

    function appendSelectPack(path, label) {
        add(label + ": open native chooser", () => {
            previousInspectionCount = inspectionCount
            return click("importArtPackButton", "cardArtManagerBody")
        },
            () => auditProbe.fileDialogState("cardArtImportFileDialog").visible === true)
        add(label + ": select the actual exported file", () => {
            require(auditProbe.chooseFile("cardArtImportFileDialog", path), "Cannot choose the art pack")
        }, () => auditProbe.fileDialogState("cardArtImportFileDialog").visible === false)
        add(label + ": wait for bounded pack inspection", () => {}, () => {
            if (cardArtManager.busy) return false
            const state = {preview: cardArtManager.packPreview, error: cardArtManager.lastError,
                inspectionCount: inspectionCount, previousInspectionCount: previousInspectionCount}
            if (inspectionCount <= previousInspectionCount) {
                if (cardArtManager.lastError.length > 0) {
                    record("rejected-pack-inspection", state)
                    throw new Error("The chosen pack was not inspected: " + cardArtManager.lastError)
                }
                return false
            }
            record("latest-pack-inspection", state)
            return true
        }, 90000)
    }

    function appendImport() {
        add("Require a new receiving profile", () => require(deckLibrary.count === 0, "Cold import requires an empty deck library"))
        add("Open metadata-only deck import", () => click("mainMenuDeckLibraryButton"),
            () => !!find("deckLibraryImportButton"))
        add("Open actual import form", () => click("deckLibraryImportButton"), () => !!find("importDeckName"))
        add("Enter fixture deck name", () => fill("importDeckName", expectedDeck.name))
        add("Open the format selector", () => click("importDeckFormat"),
            () => { const item = find("importDeckFormat"); return item && item.popup.visible })
        add("Select the fixture format", () => {
            const index = auditWindow.stack.currentItem.formatOptions.findIndex(option => option.value === expectedDeck.deckFormat)
            require(index >= 0 && auditProbe.key(Qt.Key_Home), "Cannot locate the format")
            for (let n = 0; n < index; ++n) require(auditProbe.key(Qt.Key_Down), "Cannot select format")
            require(auditProbe.key(Qt.Key_Return), "Cannot accept format")
        }, () => auditWindow.stack.currentItem.deckFormat === expectedDeck.deckFormat)
        add("Enter the independent real-card list", () => fill("importDeckText", importText))
        add("Import the deck without downloading images", () => click("importDeckSubmitButton", "importDeckBody"),
            () => !deckLibrary.importingDeck && deckLibrary.count === 1 && !!find("deckLibraryImportButton"), 60000)
        appendOpenDeck(false)
        add("Return from editor", () => click("screenBackButton"), () => !!find("deckLibraryImportButton"))
        add("Return from library", () => click("screenBackButton"), () => !!find("mainMenuSettingsButton"))
        add("Open actual Settings", () => click("mainMenuSettingsButton"), () => !!find("settingsBody"))
        add("Open card-art storage management", () => click("settingsManageArtButton", "settingsBody"),
            () => !!find("cardArtManagerBody"))
        add("Record empty receiving cache", () => {}, () => {
            if (cardArtManager.busy || cardArtManager.inventory.imageCount === undefined) return false
            requireEmptyInventory()
            record("cold-inventory", inventory())
            capture("cold-inventory")
            return true
        })
        if (invalidPack.length > 0) {
            appendSelectPack(invalidPack, "Damaged pack")
            add("Reject damaged image bytes through the actual import action", () => {
                if (cardArtManager.lastError.length > 0) return true
                require(cardArtManager.packPreview.ok, "Damaged pack neither inspected nor rejected")
                return click("confirmButton", "", 0, {text: "Import"})
            }, () => !cardArtManager.busy && cardArtManager.lastError.length > 0, 90000)
            add("Verify failed import did not leave partial cache files", () => {
                requireEmptyInventory()
                record("damaged-pack-rejected", {error: cardArtManager.lastError, inventory: inventory()})
                capture("damaged-pack-rejected")
            })
        }
        appendSelectPack(packFile, "Cancel before import")
        add("Check independent cold preview", () => {
            const preview = cardArtManager.packPreview
            require(preview.ok && preview.newEntryCount === preview.entryCount
                    && preview.entryCount > 0 && preview.existingEntryCount === 0 && preview.imageCount > 0,
                    "Cold preview did not describe an entirely new pack")
            record("cold-pack-preview", preview)
            capture("cold-pack-preview")
        })
        add("Cancel through the visible confirmation button", () => click("cancelButton"),
            () => !find("confirmButton", {text: "Import"}))
        add("Verify cancellation preserved the empty cache", () => { requireEmptyInventory(); record("cancelled-inventory", inventory()) })
        appendSelectPack(packFile, "First import")
        add("Confirm the real cold import", () => click("confirmButton", "", 0, {text: "Import"}),
            () => !cardArtManager.busy && cardArtManager.lastResult.length > 0, 90000)
        add("Record committed mappings and image inventory", () => {
            require(cardArtManager.lastError.length === 0, "Cold pack import failed: " + cardArtManager.lastError)
            firstInventory = inventory()
            require(firstInventory.imageCount === cardArtManager.packPreview.imageCount
                    && firstInventory.indexedEntryCount === cardArtManager.packPreview.entryCount
                    && firstInventory.missingEntryCount === 0 && firstInventory.orphanCount === 0,
                    "Cold import inventory is incomplete or contains unused files")
            firstCache = cacheSnapshot()
            record("inventory-after-import", firstInventory)
            record("cache-after-import", firstCache)
            capture("import-completed")
        })
        add("Refresh inventory after background card hydration", () => {
            if (cardArtManager.busy || cardCatalog.busy) return false
            previousInventoryCount = inventoryCount
            return click("refreshArtInventoryButton", "cardArtManagerBody", 360)
        }, () => inventoryCount > previousInventoryCount && !cardArtManager.busy
            && !cardCatalog.busy && !cardCatalog.cacheProgressActive, 90000)
        add("Record the settled baseline before duplicate import", () => {}, () => {
            if (cardArtManager.busy || cardCatalog.busy || cardCatalog.cacheProgressActive) return false
            const current = inventory()
            const cache = cacheSnapshot()
            // The inventory scan waits for pending hydration through the real
            // Refresh action. Persistence may finish on a later event-loop turn.
            if (Object.keys(cache.positive).length !== current.indexedEntryCount) return false
            for (const key of ["imageCount", "missingEntryCount", "orphanCount", "totalBytes"])
                require(current[key] === firstInventory[key], "Background hydration changed image storage: " + key)
            for (const key of Object.keys(firstCache.positive))
                require(JSON.stringify(cache.positive[key]) === JSON.stringify(firstCache.positive[key]),
                        "Background hydration replaced an imported mapping: " + key)
            duplicateBaselineInventory = current
            duplicateBaselineCache = cache
            record("inventory-before-duplicate", duplicateBaselineInventory)
            record("cache-before-duplicate", duplicateBaselineCache)
            return true
        }, 90000)
        appendSelectPack(packFile, "Duplicate import")
        add("Verify the pack is now entirely cached", () => {
            const preview = cardArtManager.packPreview
            record("duplicate-pack-preview", preview)
            require(preview.ok && preview.newEntryCount === 0 && preview.existingEntryCount === preview.entryCount,
                    "Duplicate import unexpectedly proposes new cache entries")
        })
        add("Confirm the duplicate import through UI", () => click("confirmButton", "", 0, {text: "Import"}),
            () => !cardArtManager.busy && cardArtManager.lastResult.length > 0, 90000)
        add("Verify duplicate import preserved mappings and storage", () => {
            require(cardArtManager.lastError.length === 0, "Duplicate import failed")
            const current = inventory()
            for (const key of ["imageCount", "indexedEntryCount", "missingEntryCount", "orphanCount", "totalBytes"])
                require(current[key] === duplicateBaselineInventory[key], "Duplicate import changed " + key)
            const cache = cacheSnapshot()
            require(JSON.stringify(cache.positive) === JSON.stringify(duplicateBaselineCache.positive)
                    && JSON.stringify(cache.negative) === JSON.stringify(duplicateBaselineCache.negative),
                    "Duplicate import changed persisted mappings")
            record("inventory-after-duplicate", current)
            record("cache-after-duplicate", cache)
            capture("duplicate-import-completed")
        })
        add("Return to Settings", () => click("screenBackButton"), () => !!find("settingsBody"))
        add("Return to main menu", () => click("screenBackButton"), () => !!find("mainMenuDeckLibraryButton"))
        add("Reopen the imported deck library", () => click("mainMenuDeckLibraryButton"), () => !!find("deckLibraryImportButton"))
        appendOpenDeck(true)
    }

    function plan() {
        loadFixture()
        add("Dismiss first-launch notices", () => {
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"]) {
                const item = find(name)
                if (item) { require(auditProbe.click(item), "Cannot dismiss " + name); return false }
            }
            return !!find("mainMenuDeckLibraryButton")
        })
        add("Verify catalog and native UI preconditions", () => {
            require(auditProbe.environment("AUDIT_NETWORK_ISOLATED") === "1",
                    "Art transfer requires the runner's --network-isolated mode")
            require(preferences.uiLanguage === "en" && cardCatalog.installed, "An installed catalog and English UI are required")
            record("transfer-input", {mode: mode, file: packFile, invalidFile: invalidPack,
                catalogVersion: cardCatalog.installedCatalogVersion, variant: variant})
        })
        if (mode === "export") appendExport()
        else appendImport()
        add("Record local cache activity inside the offline namespace", () => {
            record("offline-cache-activity", {networkIsolated: true, sawCacheActivity: sawCacheActivity})
        })
    }

    function finish(status, error) {
        if (finished) return
        finished = true
        auditProbe.record("result", {status: status, scenario: "art-transfer-lifecycle", mode: mode,
            error: error || "", packFile: packFile, requiredScreenshots: screenshots, assertions: assertions,
            completedSteps: stepIndex, pendingStep: stepIndex < steps.length ? steps[stepIndex].name : "",
            elapsedMs: Date.now() - started, sawCacheActivity: sawCacheActivity,
            networkIsolated: auditProbe.environment("AUDIT_NETWORK_ISOLATED") === "1", exportResult: exportResult,
            coverage: mode === "export" ? "Native deck-art export from an already cached real-card profile"
                : "Native cold-profile pack import, cancellation, duplicate import, persisted mappings and independent face lookups",
            damagedPackExercised: mode === "import" && invalidPack.length > 0,
            hashes: "Run verify-art-transfer.py for independent container and persisted-file SHA-256 verification",
            excluded: ["Forge", "Mid-write interruption"]})
        auditProbe.finish(status === "passed" ? 0 : 1)
    }

    Connections {
        target: cardArtManager
        function onDeckExportFinished(result) { driver.exportResult = result }
        function onPackInspectionFinished() { ++driver.inspectionCount }
        function onInventoryChanged() { ++driver.inventoryCount }
    }

    Component.onCompleted: { try { plan() } catch (error) { finish("failed", String(error)) } }
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
                if (driver.stepIndex >= driver.steps.length) { driver.finish("passed", ""); return }
                const step = driver.steps[driver.stepIndex]
                if (driver.stepStarted === 0) {
                    driver.stepStarted = Date.now()
                    driver.maximumHeartbeat = 0
                    driver.scrollAttempts = 0
                }
                driver.require(Date.now() - driver.stepStarted < step.timeout,
                    "Timed out: " + step.name + "; " + cardArtManager.lastError)
                if (auditWindow.stack.busy) return
                if (!driver.actionComplete) driver.actionComplete = step.action() !== false
                if (!driver.actionComplete || !step.check()) return
                driver.assertions.push({name: step.name, status: "passed", elapsedMs: Date.now() - driver.stepStarted,
                    maximumHeartbeatMs: driver.maximumHeartbeat})
                driver.record("assertions", driver.assertions)
                ++driver.stepIndex
                driver.stepStarted = 0
                driver.actionComplete = false
            } catch (error) {
                auditProbe.record("failure-observation", auditProbe.observe(auditWindow))
                auditProbe.capture(auditWindow, "failure")
                driver.finish("failed", String(error))
            } finally { driver.dispatching = false }
        }
    }
}
