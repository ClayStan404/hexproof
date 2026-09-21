// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: driver

    // The runner supplies an isolated, empty library and a local metadata
    // catalog. Every application mutation below is triggered by native input.
    readonly property string deckName: "Native UI format audit"
    readonly property string deckText: "56 Island (M21) 263\n"
        + "1 Supreme Verdict (RTR) 201\n1 Swords to Plowshares (STA) 10\n"
        + "1 Counterspell (MH2) 267\n1 Lightning Bolt (M11) 149"
    readonly property var formats: ["modern", "commander", "duel", "legacy", "standard",
                                    "pioneer", "pauper", "vintage", "cube", "custom"]
    property var steps: []
    property var assertions: []
    property int stepIndex: 0
    property bool actionComplete: false
    property bool dispatching: false
    property double stepStarted: 0
    property double started: Date.now()
    property double lastHeartbeat: Date.now()
    property double maximumHeartbeat: 0
    property int scrollAttempts: 0
    property bool galleryNeedsScroll: false
    property real galleryScrollBefore: 0
    property bool finished: false

    function require(value, message) {
        if (!value)
            throw new Error(message)
    }

    function find(name, identity) {
        return auditProbe.find(auditWindow, name, identity || ({}))
    }

    function page() { return auditWindow.stack.currentItem }

    function click(name, scrollName, identity) {
        const body = scrollName ? find(scrollName) : null
        if (body && (body.moving === true
                     || (body.contentItem && body.contentItem.moving === true)))
            return false
        const item = find(name, identity)
        if (item) {
            require(auditProbe.click(item), "Native click failed: " + name)
            scrollAttempts = 0
            return true
        }
        if (scrollName && ++scrollAttempts <= 24) {
            if (body)
                require(auditProbe.wheel(body, -360), "Native scroll failed: " + scrollName)
        }
        return false
    }

    function fill(name, value, identity) {
        const field = find(name, identity)
        if (!field)
            return false
        require(auditProbe.click(field), "Cannot focus " + name)
        require(auditProbe.key(Qt.Key_A, Qt.ControlModifier), "Cannot select text in " + name)
        require(value.length === 0 ? auditProbe.key(Qt.Key_Backspace) : auditProbe.text(value),
                "Cannot replace text in " + name)
        require(field.text === value, "Text input mismatch in " + name)
        return true
    }

    function selectOpenCombo(index) {
        require(auditProbe.key(Qt.Key_Home), "Cannot move to first option")
        for (let n = 0; n < index; ++n)
            require(auditProbe.key(Qt.Key_Down), "Cannot move to option " + index)
        require(auditProbe.key(Qt.Key_Return), "Cannot accept option " + index)
    }

    function add(name, action, check, timeout) {
        steps.push({name: name, action: action, check: check || (() => true),
                    timeout: timeout || 15000})
    }

    function combo(name, index, check) {
        add("Open " + name + " for option " + index, () => click(name),
            () => { const item = find(name); return item && item.popup.visible })
        add("Choose " + name + " option " + index, () => selectOpenCombo(index), check)
    }

    function screenshot(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
    }

    function deckState() {
        return {format: deckLibrary.currentDeckFormat, tableMode: deckLibrary.currentDeckTableMode,
                mainCount: deckLibrary.currentMainCount, sideboardCount: deckLibrary.currentSideboardCount,
                status: deckLibrary.currentStatus,
                validationIssues: Array.from(deckLibrary.currentValidationIssues),
                validationWarnings: Array.from(deckLibrary.currentValidationWarnings)}
    }

    function plan() {
        add("Dismiss startup notices", () => {
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"]) {
                const notice = find(name)
                if (notice) {
                    require(auditProbe.click(notice), "Cannot dismiss " + name)
                    return false
                }
            }
            return !!find("mainMenuDeckLibraryButton")
        }, () => !auditWindow.stack.busy)
        add("Verify isolated initial state", () => {
            require(deckLibrary.count === 0, "Offline audit requires an empty isolated library")
            require(preferences.uiLanguage === "en", "Offline audit requires English UI")
            require(cardCatalog.installed, "Offline audit requires a local card catalog fixture")
            auditProbe.record("window-geometry", auditProbe.observe(auditWindow))
            screenshot("01-main-menu")
        })
        add("Open deck library", () => click("mainMenuDeckLibraryButton", "mainMenuBody"),
            () => !!find("deckLibraryImportButton"))
        add("Open import form", () => click("deckLibraryImportButton"),
            () => !!find("importDeckName"))
        add("Empty import is disabled", () => {
            const button = auditProbe.observe(auditWindow).items.find(
                item => item.objectName === "importDeckSubmitButton")
            require(button && !button.enabled, "Empty import must be disabled")
        })
        add("Type imported deck name", () => fill("importDeckName", deckName))
        add("Type imported deck list", () => fill("importDeckText", deckText),
            () => { const button = find("importDeckSubmitButton"); return button && button.enabled })
        add("Submit deck import", () => click("importDeckSubmitButton", "importDeckBody"),
            () => deckLibrary.count === 1 && !!find("editLibraryDeckButton"), 30000)
        add("Imported deck is visible", () => {
            require(find("libraryDeckName", {text: deckName}), "Imported deck name is missing")
            screenshot("02-imported-library")
        })
        add("Open imported deck editor", () => click("editLibraryDeckButton"),
            () => deckLibrary.currentDeckName === deckName && !!find("deckFormatSelector"))
        add("Imported cards retain quantities and printings", () => {}, () => {
            if (deckLibrary.mainCards.some(card => !card.typeLine))
                return false
            require(deckLibrary.currentMainCount === 60, "Import changed the main-deck total")
            require(deckLibrary.currentSideboardCount === 0, "Import created sideboard cards")
            const island = deckLibrary.mainCards.find(card => card.name === "Island")
            require(island && island.count === 56 && island.setCode === "M21"
                    && island.collectorNumber === "263", "Island quantity or printing mismatch")
            return true
        }, 30000)
        add("Filter white cards", () => click("filterColor-W"),
            () => page().filteredMainCards.length === 2)
        add("Combine white and blue filters", () => click("filterColor-U"), () => {
            const cards = page().filteredMainCards
            return cards.length === 1 && cards[0].name === "Supreme Verdict"
        })
        add("Capture color intersection", () => screenshot("03-white-blue-intersection"))
        add("Reach visual card actions by scrolling", () => {
            const gallery = find("groupedDeckGallery")
            if (!gallery || gallery.moving) return false
            galleryScrollBefore = gallery.contentY
            galleryNeedsScroll = gallery.contentHeight > gallery.height + 1
            if (galleryNeedsScroll)
                require(auditProbe.wheel(gallery, -960), "Cannot scroll the visual card list")
        }, () => {
            const gallery = find("groupedDeckGallery")
            return gallery && !gallery.moving
                    && (!galleryNeedsScroll || gallery.contentY > galleryScrollBefore)
                    && !!find("deckCardActionsButton")
        })
        add("Capture reachable visual card actions", () => screenshot("visual-card-actions"))
        add("Restore visual card list scroll", () => {
            const gallery = find("groupedDeckGallery")
            if (!gallery || gallery.moving) return false
            if (galleryNeedsScroll)
                require(auditProbe.wheel(gallery, 960), "Cannot restore the visual card list")
        }, () => {
            const gallery = find("groupedDeckGallery")
            return gallery && !gallery.moving && gallery.atYBeginning
        })
        add("Open advanced filters", () => click("advancedCardFiltersButton"),
            () => !!find("resetAdvancedCardFiltersButton"))
        add("Combine color and mana-value filters", () => click("filter-manaValues-4"),
            () => page().filteredMainCards.length === 1)
        add("Combine color, mana value, and card type", () => click("filter-types-Sorcery"),
            () => page().filteredMainCards.length === 1)
        add("Combine rarity with other filter categories", () => click("filter-rarities-rare"),
            () => page().filteredMainCards.length === 1)
        add("Add another mana-value choice", () => click("filter-manaValues-1"),
            () => page().filteredMainCards.length === 1)
        add("Remove the matching mana-value choice", () => click("filter-manaValues-4"),
            () => page().filteredMainCards.length === 0)
        add("Reset advanced filters", () => click("resetAdvancedCardFiltersButton"),
            () => page().filteredMainCards.length === 5)
        add("Close advanced filters", () => click("closeAdvancedCardFilters"),
            () => !find("closeAdvancedCardFilters"))
        add("Open catalog search", () => click("deckEditorSearchButton", "deckEditorBody"),
            () => !!find("cardSearchDoneButton"))
        add("Type exact catalog search", () => fill("workbenchSearch", "Dovin's Veto",
            {placeholderText: "Search English or Chinese names…"}),
            () => !cardCatalog.searching && !!find("workbenchCard-Dovin's Veto"), 30000)
        add("Add card from search result", () => click("workbenchCard-Dovin's Veto"),
            () => deckLibrary.currentMainCount === 61)
        add("Close catalog search", () => click("cardSearchDoneButton"),
            () => !find("cardSearchDoneButton"))
        add("Local deck search remains reachable after popup closes", () => {
            const field = find("workbenchSearch")
            auditProbe.record("local-search-control", {
                found: !!field,
                placeholderText: field ? field.placeholderText : "",
                lastError: auditProbe.lastError
            })
            require(!!field, "The local deck search input is not reachable")
        })
        add("Find added card in deck", () => fill("workbenchSearch", "Dovin's Veto",
            {placeholderText: "Search this deck…"}),
            () => page().filteredMainCards.length === 1
                && page().filteredMainCards[0].name === "Dovin's Veto")
        combo("deckEditorViewMode", 0, () => !!find("deckCardRow-Dovin's Veto"))
        add("Increase a card quantity", () => click("increaseDeckCardCountButton"),
            () => deckLibrary.currentMainCount === 62)
        add("Decrease a card quantity", () => click("decreaseDeckCardCountButton"),
            () => deckLibrary.currentMainCount === 61)
        add("Remove the added card", () => click("decreaseDeckCardCountButton"),
            () => deckLibrary.currentMainCount === 60
                && !deckLibrary.mainCards.some(card => card.name === "Dovin's Veto"))
        add("Clear deck search", () => fill("workbenchSearch", "",
            {placeholderText: "Search this deck…"}), () => page().filteredMainCards.length === 5)
        combo("deckEditorViewMode", 1, () => !!find("groupedDeckGallery"))
        add("Open deck export options", () => click("exportCurrentDeckButton", "deckEditorBody"),
            () => !!find("exportDeckArtButton"))
        add("Open deck-specific art export", () => click("exportDeckArtButton"), () => {
            const name = find("deckArtExportName")
            return name && name.text === deckName && !!find("saveDeckArtPackButton")
        })
        add("Capture art export options", () => screenshot("deck-art-export-options"))
        add("Close art export options", () => click("closeDeckArtExportButton"),
            () => !find("closeDeckArtExportButton"))
        add("Verify all format choices", () => {
            require(JSON.stringify(page().formatOptions.map(option => option.value))
                    === JSON.stringify(formats), "Unexpected supported deck format options")
        })
        combo("deckFormatSelector", 1, () => !!find("cancelButton"))
        add("Cancel a format change", () => click("cancelButton"),
            () => deckLibrary.currentDeckFormat === "modern"
                && find("deckFormatSelector").currentIndex === 0)
        for (let index = 0; index < formats.length; ++index) {
            const format = formats[index]
            combo("deckFormatSelector", index, () => deckLibrary.currentDeckFormat === format
                  || page().pendingDeckFormat === format)
            add("Confirm format " + format, () => {
                if (deckLibrary.currentDeckFormat === format)
                    return true
                return click("confirmButton")
            }, () => deckLibrary.currentDeckFormat === format)
            add("Validate format presentation " + format, () => {}, () => {
                if (deckLibrary.currentStatus === "Checking deck legality…")
                    return false
                require(deckLibrary.currentMainCount === 60, "Format change lost cards: " + format)
                const commander = format === "commander" || format === "duel"
                const mode = format === "commander" ? "edh" : format === "duel" ? "duel" : "modern"
                require(deckLibrary.currentDeckTableMode === mode, "Wrong table mode: " + format)
                require(page().commanderFormat === commander, "Wrong commander UI: " + format)
                require(page().cubeFormat === (format === "cube"), "Wrong Cube UI: " + format)
                if (commander)
                    require(deckLibrary.currentStatus === "Commander required", "Missing commander was accepted")
                if (format === "cube")
                    require(deckLibrary.currentStatus.includes("at least"), "Undersized Cube was accepted")
                if (["legacy", "vintage", "custom"].includes(format))
                    require(deckLibrary.currentStatus === "Playable",
                            "The cached fixture should be playable in " + format + ": "
                            + deckLibrary.currentStatus)
                if (["modern", "standard", "pioneer", "pauper"].includes(format)) {
                    const label = format.charAt(0).toUpperCase() + format.slice(1)
                    require(deckLibrary.currentValidationIssues.some(
                                issue => issue.includes("is not legal in " + label)),
                            "The fixture's illegal cards were accepted in " + format)
                }
                screenshot("format-" + format)
                return true
            }, 30000)
        }
        add("Return to library", () => click("screenBackButton"),
            () => !!find("deckLibraryFormatFilter"))
        combo("deckLibraryFormatFilter", 1, () => !find("editLibraryDeckButton"))
        combo("deckLibraryFormatFilter", 10, () => !!find("editLibraryDeckButton"))
        combo("deckLibraryFormatFilter", 0, () => !!find("editLibraryDeckButton"))
        add("Open settings", () => click("deckLibrarySettingsButton"),
            () => !!find("settingsBody"))
        add("Open appearance settings", () => click("settingsAppearanceModule", "settingsBody"),
            () => !!find("settingsThemeSelector"))
        add("Change appearance by pointer", () => {
            const control = find("settingsThemeSelector")
            if (!control) return false
            require(auditProbe.click(control, control.width * 0.75, control.height / 2), "Cannot select Glass")
        }, () => preferences.uiTheme === "glass")
        add("Return to settings categories", () => click("screenBackButton"),
            () => !!find("settingsLanguageModule"))
        add("Open language settings", () => click("settingsLanguageModule", "settingsBody"),
            () => !!find("settingsLanguageSelector"))
        add("Change interface language by pointer", () => {
            const control = find("settingsLanguageSelector")
            if (!control) return false
            require(auditProbe.click(control, control.width * 0.75, control.height / 2), "Cannot select Chinese")
        }, () => preferences.uiLanguage === "zh")
        add("Capture translated settings", () => screenshot("settings-chinese-glass"))
        add("Restore English by pointer", () => {
            const control = find("settingsLanguageSelector")
            require(auditProbe.click(control, control.width * 0.25, control.height / 2), "Cannot select English")
        }, () => preferences.uiLanguage === "en")
        add("Return to settings categories", () => click("screenBackButton"),
            () => !!find("settingsManageArtButton"))
        add("Open downloaded-art manager", () => click("settingsManageArtButton", "settingsBody"),
            () => !!find("manageCustomCardArtButton"))
        add("Refresh downloaded-art inventory", () => click("refreshArtInventoryButton"),
            () => !cardArtManager.busy && cardArtManager.inventory.imageCount !== undefined, 30000)
        add("Verify cached images remain intact", () => {
            const inventory = cardArtManager.inventory
            require(inventory.imageCount > 0, "Expected local fixture images")
            require(inventory.missingEntryCount === 0, "Cached image mappings became unavailable")
            auditProbe.record("art-inventory", inventory)
        })
        add("Capture downloaded-art manager", () => screenshot("art-manager"))
        add("Open custom-art manager", () => click("manageCustomCardArtButton"),
            () => !!find("customArtSearchField"))
        add("Search empty custom-art inventory", () => fill("customArtSearchField", "missing audit artwork"),
            () => page().filteredEntries.length === 0)
        add("Capture custom-art manager", () => screenshot("custom-art-manager"))
        add("Return from custom-art manager", () => click("screenBackButton"),
            () => !!find("manageCustomCardArtButton"))
        add("Return from downloaded-art manager", () => click("screenBackButton"),
            () => !!find("settingsBody"))
        add("Return from settings", () => click("screenBackButton"),
            () => !!find("deckLibraryImportButton"))
        add("Open deck deletion confirmation", () => click("deleteLibraryDeckButton"),
            () => !!find("confirmButton"))
        add("Cancel deck deletion", () => click("cancelButton"),
            () => deckLibrary.count === 1 && !find("cancelButton"))
        add("Reopen deck deletion confirmation", () => click("deleteLibraryDeckButton"),
            () => !!find("confirmButton"))
        add("Delete isolated fixture deck", () => click("confirmButton"),
            () => deckLibrary.count === 0)
        add("Return to main menu", () => click("screenBackButton"),
            () => !!find("mainMenuDeckLibraryButton"))
        add("Capture final menu", () => screenshot("final-main-menu"))
    }

    function finish(status, error) {
        if (finished) return
        finished = true
        auditProbe.record("result", {status: status, scenario: "offline-library", error: error || "",
            requiredScreenshots: ["01-main-menu.png", "02-imported-library.png",
                "03-white-blue-intersection.png", "visual-card-actions.png", "deck-art-export-options.png",
                "format-modern.png", "format-commander.png", "format-duel.png",
                "format-legacy.png", "format-standard.png", "format-pioneer.png",
                "format-pauper.png", "format-vintage.png", "format-cube.png", "format-custom.png",
                "settings-chinese-glass.png", "art-manager.png", "custom-art-manager.png",
                "final-main-menu.png"],
            assertions: assertions, step: stepIndex,
            pendingStep: stepIndex < steps.length ? steps[stepIndex].name : "",
            elapsedMs: Date.now() - started, deck: deckState(),
            fixture: "Empty isolated library; local catalog supplied by runner; deck imported through native text input",
            coverage: "Native menu/library/import/editor/filter/search-add/count/format/settings/art-manager navigation; Forge excluded"})
        auditProbe.finish(status === "passed" ? 0 : 1)
    }

    Component.onCompleted: plan()

    Timer {
        interval: 16
        running: !driver.finished
        repeat: true
        onTriggered: {
            const now = Date.now()
            driver.maximumHeartbeat = Math.max(driver.maximumHeartbeat, now - driver.lastHeartbeat)
            driver.lastHeartbeat = now
        }
    }

    Timer {
        interval: 180
        running: !driver.finished
        repeat: true
        onTriggered: {
            // QTest can process events while requesting activation or dragging.
            // A nested timer tick must not dispatch the same step twice.
            if (driver.dispatching)
                return
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
                               "Timed out: " + step.name)
                driver.require(Date.now() - driver.started < 360000, "Scenario exceeded six minutes")
                if (auditWindow.stack.busy)
                    return
                if (!driver.actionComplete)
                    driver.actionComplete = step.action() !== false
                if (!driver.actionComplete || !step.check())
                    return
                driver.assertions.push({name: step.name, status: "passed",
                    elapsedMs: Date.now() - driver.stepStarted,
                    maximumHeartbeatMs: driver.maximumHeartbeat, deck: driver.deckState()})
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
