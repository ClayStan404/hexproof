// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: driver

    readonly property string catalogFile: auditProbe.environment("AUDIT_CATALOG_IMPORT")
    readonly property string manifestFile: auditProbe.environment("AUDIT_DECK_MANIFEST")
    readonly property string variant: auditProbe.environment("AUDIT_VARIANT") || "modern"
    readonly property string mode: auditProbe.environment("AUDIT_BOOTSTRAP_MODE")
        || (catalogFile.length > 0 ? "local-import" : "online-install")
    readonly property bool artDownloadOnly: mode === "art-download"
    readonly property string artProvider: auditProbe.environment("AUDIT_CARD_ART_PROVIDER") || "parallel"
    readonly property bool restarting: Number(auditProbe.environment("AUDIT_STAGE") || "1") > 1
    readonly property int seat: Number(auditProbe.environment("AUDIT_SEAT") || "1")
    readonly property string cardLanguage: auditProbe.environment("AUDIT_CARD_LANGUAGE") || "en"
    property var expectedDeck: ({})
    property string importText: ""
    property var steps: []
    property var assertions: []
    property var screenshots: []
    property var installedState: ({})
    property var verifiedDeck: ({})
    property var finalInventory: ({})
    property int stepIndex: 0
    property bool actionComplete: false
    property bool dispatching: false
    property bool finished: false
    property bool sawColdCacheActivity: false
    property double started: Date.now()
    property double stepStarted: 0
    property double lastHeartbeat: Date.now()
    property double maximumHeartbeat: 0
    property int scrollAttempts: 0
    property double downloadStarted: 0
    property double downloadElapsed: 0
    property var downloadHeartbeats: []
    property int interactionsDuringDownload: 0

    function require(value, message) {
        if (!value)
            throw new Error(message)
    }

    function find(name, identity) {
        return auditProbe.find(auditWindow, name, identity || ({}))
    }

    function click(name, scrollName, direction) {
        const body = scrollName ? find(scrollName) : null
        if (body && (body.moving === true
                     || (body.contentItem && body.contentItem.moving === true)))
            return false
        const item = find(name)
        if (item) {
            require(auditProbe.click(item), "Native click failed: " + name)
            scrollAttempts = 0
            return true
        }
        if (body && ++scrollAttempts <= 36)
            require(auditProbe.wheel(body, direction || -360), "Cannot scroll " + scrollName)
        return false
    }

    function fill(name, value) {
        const field = find(name)
        if (!field)
            return false
        require(auditProbe.click(field), "Cannot focus " + name)
        require(auditProbe.key(Qt.Key_A, Qt.ControlModifier), "Cannot select " + name)
        require(auditProbe.text(value), "Cannot type " + name)
        require(field.text === value, "Native text input changed " + name)
        return true
    }

    function add(name, action, check, timeout) {
        steps.push({name: name, action: action, check: check || (() => true),
                    timeout: timeout || 20000})
    }

    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        screenshots.push(name + ".png")
        lastHeartbeat = Date.now()
    }

    function catalogState() {
        return {installed: cardCatalog.installed,
            installedVersion: cardCatalog.installedCatalogVersion,
            schemaVersion: cardCatalog.installedCatalogSchemaVersion,
            latestVersion: cardCatalog.latestCatalogVersion,
            latestSchemaVersion: cardCatalog.latestCatalogSchemaVersion,
            latestKnown: cardCatalog.latestCatalogKnown,
            updateAvailable: cardCatalog.catalogUpdateAvailable,
            packageName: cardCatalog.packageName, busy: cardCatalog.busy,
            status: cardCatalog.status, error: cardCatalog.lastError,
            versionError: cardCatalog.catalogVersionError}
    }

    function deckState() {
        return {name: deckLibrary.currentDeckName, format: deckLibrary.currentDeckFormat,
            mainCount: deckLibrary.currentMainCount, sideboardCount: deckLibrary.currentSideboardCount,
            missingImages: deckLibrary.currentMissingImageCount, ready: deckLibrary.currentReady,
            status: deckLibrary.currentStatus, mainboard: Array.from(deckLibrary.mainCards),
            sideboard: Array.from(deckLibrary.sideboardCards)}
    }

    function installationFinished() {
        if (cardCatalog.busy)
            return false
        require(cardCatalog.operationError.length === 0,
                "Database installation failed: " + cardCatalog.operationError)
        return cardCatalog.installed
    }

    function loadFixture() {
        require(manifestFile.length > 0, "An independent deck manifest is required")
        const manifest = JSON.parse(auditProbe.readText(manifestFile))
        require(manifest.decks && manifest.decks[variant], "Missing format fixture: " + variant)
        expectedDeck = manifest.decks[variant]
        require(expectedDeck.name && expectedDeck.textFile
                && Array.isArray(expectedDeck.mainboard)
                && Array.isArray(expectedDeck.sideboard), "Incomplete deck fixture")
        const parentPath = manifestFile.slice(0, manifestFile.lastIndexOf("/") + 1)
        const sourcePath = expectedDeck.textFile.startsWith("/")
            ? expectedDeck.textFile : parentPath + expectedDeck.textFile
        importText = auditProbe.readText(sourcePath)
        require(importText.length > 0, "The fixture deck text is empty")
        require(auditProbe.record("expected-deck", expectedDeck), "Cannot record fixture oracle")
    }

    function validateDeck() {
        const total = rows => rows.reduce((count, card) => count + card.count, 0)
        require(deckLibrary.currentDeckName === expectedDeck.name, "Wrong imported deck")
        require(deckLibrary.currentDeckFormat === expectedDeck.deckFormat, "Import changed the format")
        require(deckLibrary.currentDeckTableMode === expectedDeck.tableMode, "Wrong table mode")
        require(deckLibrary.currentMainCount === total(expectedDeck.mainboard), "Main count changed")
        require(deckLibrary.currentSideboardCount === total(expectedDeck.sideboard), "Sideboard count changed")
        for (const pair of [[expectedDeck.mainboard, deckLibrary.mainCards],
                            [expectedDeck.sideboard, deckLibrary.sideboardCards]]) {
            require(pair[0].length === pair[1].length, "Printing rows were merged or split")
            for (const expected of pair[0]) {
                const actual = pair[1].find(card => card.name === expected.name
                    && card.setCode.toUpperCase() === expected.setCode.toUpperCase()
                    && card.collectorNumber === expected.collectorNumber)
                require(actual && actual.count === expected.count,
                        "Printing/count mismatch: " + expected.name + " "
                        + expected.setCode + "/" + expected.collectorNumber)
                require(actual.typeLine.length > 0, "Metadata missing: " + expected.name)
                require(actual.imageSource.startsWith("file:"), "Local art missing: " + expected.name)
            }
        }
        require(deckLibrary.currentMissingImageCount === 0, "Deck still has missing images")
        require(!deckLibrary.hasMissingArt, "The library still reports missing images")
        require(deckLibrary.currentReady, "Deck is not playable: " + deckLibrary.currentStatus)
    }

    function plan() {
        add("Read independent printing fixture", () => loadFixture())
        add("Dismiss first-launch notices through UI", () => {
            require(auditProbe.activate(), "Cannot activate the current bootstrap seat")
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"]) {
                const notice = find(name)
                if (notice) {
                    require(auditProbe.click(notice), "Cannot dismiss " + name)
                    return false
                }
            }
            return !!find("mainMenuSettingsButton")
        })
        add("Verify profile bootstrap state", () => {
            require(cardCatalog.installed === (restarting || artDownloadOnly),
                    restarting ? "Installed catalog did not survive restart" : "Catalog was preseeded")
            require(deckLibrary.count === (restarting ? 1 : 0), "Unexpected initial library")
            capture("01-bootstrap-menu")
        })
        add("Open actual Settings screen", () => click("mainMenuSettingsButton"),
            () => !!find("settingsBody"))
        add("Choose English through Settings", () => {
            if (preferences.uiLanguage === "en") return
            const selector = find("settingsLanguageSelector")
            if (!selector) return false
            require(auditProbe.click(selector, selector.width * 0.25, selector.height / 2), "Cannot choose English")
        }, () => preferences.uiLanguage === "en")
        add("Choose card language through Settings", () => {
            if (preferences.cardLanguage === cardLanguage) return
            const selector = find("settingsCardLanguageSelector")
            if (!selector) return false
            require(auditProbe.click(selector, selector.width * (cardLanguage === "zh" ? 0.75 : 0.25),
                                    selector.height / 2), "Cannot choose card language")
        }, () => preferences.cardLanguage === cardLanguage)
        if (artDownloadOnly) {
            add("Choose art provider through Settings", () => {
                const index = ["auto", "scryfall", "mtgch", "parallel"].indexOf(artProvider)
                require(index >= 0, "Unknown art provider")
                if (restarting) require(preferences.cardArtProvider === artProvider,
                                        "Art provider did not survive restart")
                const body = find("settingsBody")
                if (body && (body.moving || (body.contentItem && body.contentItem.moving))) return false
                const selector = find("settingsCardArtProviderSelector")
                if (!selector) {
                    if (body) require(auditProbe.wheel(body, -360), "Cannot scroll to art provider")
                    return false
                }
                require(auditProbe.click(selector, selector.width * (index + 0.5) / 4,
                                        selector.height / 2), "Cannot choose art provider")
            }, () => preferences.cardArtProvider === artProvider)
        }
        if (!restarting) {
            add("Open initially empty card-art inventory", () => click("settingsManageArtButton", "settingsBody"),
                () => !!find("refreshArtInventoryButton"))
            add("Refresh empty inventory", () => click("refreshArtInventoryButton"),
                () => !cardArtManager.busy && cardArtManager.inventory.imageCount !== undefined)
            add("Verify genuinely cold art cache", () => {
                require(cardArtManager.inventory.imageCount === 0, "Card images were preseeded")
                require(auditProbe.record("initial-art-inventory", cardArtManager.inventory),
                        "Cannot record initial inventory")
                capture("02-empty-art-cache")
            })
            add("Return to database settings", () => click("screenBackButton"),
                () => !!find("settingsBody"))
            if (artDownloadOnly) {
                add("Record preinstalled catalog fixture", () => auditProbe.fixture("preinstalled-catalog", catalogState()))
            } else if (mode === "local-import" || mode === "online-update") {
                add("Open native catalog file chooser", () => click("settingsImportCatalogButton", "settingsBody"),
                    () => auditProbe.fileDialogState("catalogImportFileDialog").visible === true)
                add("Select the database through its file chooser", () => {
                    require(catalogFile.length > 0, "No catalog import path supplied")
                    require(auditProbe.chooseFile("catalogImportFileDialog", catalogFile),
                            "Catalog file chooser failed: " + auditProbe.lastError)
                }, () => installationFinished(), 180000)
            } else {
                require(mode === "online-install", "Unknown bootstrap mode: " + mode)
                add("Request the official database through Settings", () => click("settingsDownloadCatalogButton", "settingsBody"),
                    () => !!find("confirmButton"))
                add("Confirm official database download", () => click("confirmButton"),
                    () => installationFinished(), 900000)
            }
        }
        add("Verify installed catalog and offline indexes", () => {
            require(cardCatalog.installed && cardCatalog.installedCatalogSchemaVersion === 10,
                    "Catalog installation failed: " + cardCatalog.lastError)
            require(cardCatalog.enhancedIndexInstalled && cardCatalog.chineseIndexInstalled,
                    "The imported catalog lacks expected offline indexes")
            require(cardCatalog.tokenCatalogInstalled, "Support-card catalog is unavailable")
            require(cardCatalog.packageName === "default_cards", "Wrong catalog package")
            installedState = catalogState()
            require(auditProbe.record("installed-catalog", installedState), "Cannot record installed catalog")
            capture("03-installed-catalog")
        })
        if (!artDownloadOnly) {
            add("Check online catalog version through Settings", () => {
                if (cardCatalog.checkingCatalogVersion)
                    return false
                return click("settingsCheckCatalogUpdatesButton", "settingsBody")
            }, () => !cardCatalog.checkingCatalogVersion, 180000)
            add("Validate the actual official version response", () => {
                require(auditProbe.record("online-catalog-check", catalogState()),
                        "Cannot record online database check")
                require(cardCatalog.catalogVersionError.length === 0,
                        "Online database check failed: " + cardCatalog.catalogVersionError)
                require(cardCatalog.latestCatalogKnown && cardCatalog.latestCatalogCompatible,
                        "The official database version is missing or incompatible")
                capture("online-catalog-version")
            })
        }
        if (!restarting && mode === "online-update") {
            add("Require a newer database for upgrade coverage", () => {
                require(cardCatalog.catalogUpdateAvailable, "No newer database; upgrade was not exercised")
                require(cardCatalog.latestCatalogVersion !== installedState.installedVersion,
                        "Database fixture is already current")
            })
            add("Request database update through Settings", () => click("settingsDownloadCatalogButton", "settingsBody"),
                () => !!find("confirmButton"))
            add("Install the actual online database update", () => click("confirmButton"),
                () => installationFinished(), 900000)
            add("Verify database version advanced", () => {
                require(cardCatalog.installedCatalogVersion === cardCatalog.latestCatalogVersion
                        && cardCatalog.installedCatalogVersion !== installedState.installedVersion,
                        "The installed database did not advance to the official release")
                require(auditProbe.record("updated-catalog", catalogState()), "Cannot record database upgrade")
                capture("updated-catalog")
            })
        }
        add("Return from Settings", () => click("screenBackButton"),
            () => !!find("mainMenuDeckLibraryButton"))
        add("Open the library", () => click("mainMenuDeckLibraryButton", "mainMenuBody"),
            () => !!find("deckLibraryImportButton"))
        if (!restarting) {
            add("Open deck import", () => click("deckLibraryImportButton"),
                () => !!find("importDeckName"))
            add("Type fixture deck name", () => fill("importDeckName", expectedDeck.name))
            add("Open import format selector", () => click("importDeckFormat"),
                () => { const field = find("importDeckFormat"); return field && field.popup.visible })
            add("Select requested format by keyboard", () => {
                const options = auditWindow.stack.currentItem.formatOptions
                const index = options.findIndex(option => option.value === expectedDeck.deckFormat)
                require(index >= 0, "Format is not offered: " + expectedDeck.deckFormat)
                require(auditProbe.key(Qt.Key_Home), "Cannot select first format")
                for (let n = 0; n < index; ++n)
                    require(auditProbe.key(Qt.Key_Down), "Cannot reach requested format")
                require(auditProbe.key(Qt.Key_Return), "Cannot select requested format")
            }, () => auditWindow.stack.currentItem.deckFormat === expectedDeck.deckFormat)
            add("Type the independent deck list", () => fill("importDeckText", importText))
            add("Submit metadata-only deck import", () => click("importDeckSubmitButton", "importDeckBody"),
                () => deckLibrary.count === 1 && !!find("editLibraryDeckButton"), 60000)
            add("Record cold-cache state before explicit download", () => {
                require(auditProbe.record("cold-cache-after-import", {busy: cardCatalog.cacheProgressActive,
                    status: cardCatalog.status, missing: deckLibrary.hasMissingArt}),
                    "Cannot record cold cache state")
                capture("04-imported-cold-deck")
            })
            add("Wait for outstanding metadata work", () => {},
                () => !cardCatalog.cacheProgressActive, 240000)
            add("Explicitly cache the library through UI", () => {
                if (!click("cacheDeckArtButton")) return false
                downloadStarted = Date.now()
                lastHeartbeat = downloadStarted
            }, () => artDownloadOnly || !cardCatalog.cacheProgressActive, 240000)
        }
        add("Open cached deck for exact identity validation", () => click("editLibraryDeckButton"),
            () => deckLibrary.currentDeckName === expectedDeck.name && !!find("deckFormatSelector"))
        if (artDownloadOnly) {
            for (let cycle = 0; cycle < 4; ++cycle) {
                for (const filtered of [true, false]) {
                    add("Search deck during download " + cycle + (filtered ? " filtered" : " all"), () => {
                        const field = find("workbenchSearch", {placeholderText: "Search this deck…"})
                        if (!field) return false
                        const text = filtered ? expectedDeck.mainboard[0].name : ""
                        require(auditProbe.click(field), "Cannot focus local search")
                        require(auditProbe.key(Qt.Key_A, Qt.ControlModifier), "Cannot select search")
                        require(text ? auditProbe.text(text) : auditProbe.key(Qt.Key_Backspace), "Cannot type search")
                        if (cardCatalog.cacheProgressActive) ++interactionsDuringDownload
                    }, () => {
                        const rows = auditWindow.stack.currentItem.filteredMainCards
                        return filtered ? rows.length > 0 && rows.every(row => row.name.includes(expectedDeck.mainboard[0].name))
                                        : rows.length === expectedDeck.mainboard.length
                    })
                }
            }
            add("Switch the deck to list view during download", () => click("deckEditorViewMode"),
                () => { const field = find("deckEditorViewMode"); return field && field.popup.visible })
            add("Select list view by keyboard", () => {
                require(auditProbe.key(Qt.Key_Home) && auditProbe.key(Qt.Key_Return), "Cannot select list view")
                if (cardCatalog.cacheProgressActive) ++interactionsDuringDownload
            }, () => !find("groupedDeckGallery"))
        }
        add("Verify cached deck and every printing", () => {}, () => {
            if (cardCatalog.cacheProgressActive || deckLibrary.currentStatus === "Checking deck legality…")
                return false
            validateDeck()
            // Metadata presentation is coalesced separately from network
            // completion. Observe the visible badge before capturing it.
            const badge = find("deckEditorStatus")
            if (!badge || badge.text !== deckLibrary.currentStatus) return false
            verifiedDeck = deckState()
            require(auditProbe.record("cached-deck", verifiedDeck), "Cannot record cached deck")
            capture("05-cached-deck")
            return true
        }, 90000)
        add("Return to cached library", () => click("screenBackButton"),
            () => !!find("deckLibrarySettingsButton"))
        add("Open Settings after caching", () => click("deckLibrarySettingsButton"),
            () => !!find("settingsBody"))
        add("Open populated art inventory", () => click("settingsManageArtButton", "settingsBody"),
            () => !!find("refreshArtInventoryButton"))
        add("Refresh populated inventory", () => click("refreshArtInventoryButton"),
            () => !cardArtManager.busy && cardArtManager.inventory.imageCount !== undefined, 30000)
        add("Verify downloaded files and index agree", () => {
            finalInventory = cardArtManager.inventory
            require(finalInventory.imageCount > 0, "No downloaded card images")
            require(finalInventory.missingEntryCount === 0, "Cache index refers to missing images")
            require(finalInventory.orphanCount === 0, "Cold cache created orphan images")
            require(auditProbe.record("final-art-inventory", finalInventory), "Cannot record final inventory")
            capture("06-populated-art-cache")
        })
    }

    function finish(status, error) {
        if (finished) return
        finished = true
        auditProbe.record("result", {status: status, scenario: "bootstrap-lifecycle",
            error: error || "", stage: restarting ? "restart" : "bootstrap", mode: mode,
            variant: variant, requiredScreenshots: screenshots, assertions: assertions,
            completedSteps: stepIndex, pendingStep: stepIndex < steps.length ? steps[stepIndex].name : "",
            elapsedMs: Date.now() - started, catalog: catalogState(), deck: verifiedDeck,
            inventory: finalInventory, sawColdCacheActivity: sawColdCacheActivity,
            artProvider: preferences.cardArtProvider, downloadElapsedMs: downloadElapsed,
            downloadHeartbeatMs: heartbeatSummary(), interactionsDuringDownload: interactionsDuringDownload,
            fixture: artDownloadOnly ? "Read-only catalog backup; deck imported by native UI; no seeded images"
                                     : "Isolated profile; catalog installed and deck imported by real UI input; no seeded images",
            coverage: artDownloadOnly ? "Cold art cache, local search and view switching during download, optional restart; no catalog installation coverage"
                                      : "Catalog installation, exact-printing deck import, cold art cache, optional restart; Forge excluded"})
        if (status === "passed") auditProbe.share("bootstrap-seat-" + seat, {completed: true})
        auditProbe.finish(status === "passed" ? 0 : 1)
    }

    function heartbeatSummary() {
        const samples = downloadHeartbeats.slice().sort((a, b) => a - b)
        const at = fraction => samples.length ? samples[Math.min(samples.length - 1, Math.floor(samples.length * fraction))] : 0
        return {count: samples.length, median: at(0.5), p95: at(0.95), maximum: at(1),
                note: "GUI timer intervals, not frame times; native event dispatch included, screenshots excluded"}
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
            if (driver.downloadStarted > 0 && driver.downloadElapsed === 0) {
                driver.downloadHeartbeats.push(now - driver.lastHeartbeat)
                if (!cardCatalog.cacheProgressActive)
                    driver.downloadElapsed = now - driver.downloadStarted
            }
            driver.lastHeartbeat = now
            if (deckLibrary.count > 0 && cardCatalog.cacheProgressActive)
                driver.sawColdCacheActivity = true
        }
    }

    Timer {
        interval: 180
        running: !driver.finished
        repeat: true
        onTriggered: {
            if (driver.dispatching) return
            if (driver.seat > 1 && !(auditProbe.readShared("bootstrap-seat-" + (driver.seat - 1)) || {}).completed) return
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
                    "Timed out: " + step.name + "; catalog: " + JSON.stringify(driver.catalogState()))
                if (auditWindow.stack.busy) return
                if (!driver.actionComplete)
                    driver.actionComplete = step.action() !== false
                if (!driver.actionComplete || !step.check()) return
                driver.assertions.push({name: step.name, status: "passed",
                    elapsedMs: Date.now() - driver.stepStarted, maximumHeartbeatMs: driver.maximumHeartbeat})
                driver.require(auditProbe.record("assertions", driver.assertions), "Cannot save assertions")
                driver.stepIndex++
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
