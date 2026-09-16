// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: driver

    // Use one isolated 960-card Cube. A generated fixture requires its
    // independent manifest; the legacy real-library fixture has fixed oracles.
    property var steps: []
    property var results: []
    property int index: 0
    property double started: 0
    property double lastTick: Date.now()
    property double longestTick: 0
    property bool acted: false
    property bool dispatching: false
    property bool finished: false
    readonly property bool searchOnly: auditProbe.environment("HEXPROOF_AUDIT_VARIANT") === "search"
    readonly property string manifestFile: auditProbe.environment("AUDIT_DECK_MANIFEST")
    property var expectedCards: []
    property var editedPrinting: ({name: "Esper Sentinel", setCode: "MH2", collectorNumber: "12"})
    property var expectedIdentityCounts: ({W: 235, WU: 48, WUB: 18})
    property var searchGrid: null

    function require(value, message) {
        if (!value) throw new Error(message)
    }
    function find(name, identity) {
        return auditProbe.find(auditWindow, name, identity || ({}))
    }
    function click(name, scrollName) {
        const item = find(name)
        if (!item) {
            const body = scrollName ? find(scrollName) : null
            if (body && !body.moving) require(auditProbe.wheel(body, -360), "Cannot scroll to " + name)
            return false
        }
        require(auditProbe.click(item), "Click failed: " + name)
        return true
    }
    function fill(value, catalogSearch) {
        const item = find("workbenchSearch", {placeholderText: catalogSearch
                         ? "Search English or Chinese names…" : "Search this deck…"})
        if (!item) return false
        require(auditProbe.click(item), "Cannot focus local search")
        require(auditProbe.key(Qt.Key_A, Qt.ControlModifier), "Cannot select query")
        require(value ? auditProbe.text(value) : auditProbe.key(Qt.Key_Backspace), "Cannot type query")
        require(item.text === value, "Search input did not accept the requested text")
        return true
    }
    function add(name, action, check) {
        steps.push({name: name, action: action, check: check || (() => true)})
    }
    function cards() { return auditWindow.stack.currentItem.filteredMainCards }
    function exactCount(count) {
        const card = deckLibrary.mainCards.find(row => row.name === editedPrinting.name
            && row.setCode === editedPrinting.setCode && row.collectorNumber === editedPrinting.collectorNumber)
        return card && card.count === count && deckLibrary.currentMainCount === 959 + count
    }
    function identityCount(colors) {
        return expectedIdentityCounts[colors]
    }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        lastTick = Date.now()
    }
    function plan() {
        if (manifestFile) {
            add("Read independent generated Cube oracle", () => {
                const manifest = JSON.parse(auditProbe.readText(manifestFile))
                expectedCards = manifest.decks.cube.mainboard
                require(expectedCards.length === 960 && expectedCards.every(card => card.count === 1),
                        "The manifest must describe 960 singleton printing rows")
                editedPrinting = expectedCards[0]
                const counts = ({})
                for (const colors of ["W", "WU", "WUB"])
                    counts[colors] = expectedCards.filter(card => Array.from(colors)
                        .every(color => card.colorIdentity.includes(color))).length
                expectedIdentityCounts = counts
            })
        }
        add("Open isolated library", () => click("mainMenuDeckLibraryButton"),
            () => !!find("editLibraryDeckButton"))
        add("Open 960-card Cube", () => click("editLibraryDeckButton"),
            () => !!find("deckEditorViewMode") && deckLibrary.currentMainCount === 960)
        add("Verify fixture", () => {
            require(deckLibrary.count === 1 && deckLibrary.mainCards.length === 960,
                    "Expected one 960-entry Cube")
            require(exactCount(1), "Missing exact-printing fixture")
            const printingKey = card => [card.name, card.setCode, card.collectorNumber].join("\u001f")
            const actualCards = ({})
            for (const card of deckLibrary.mainCards) actualCards[printingKey(card)] = card
            for (const expected of expectedCards) {
                const actual = actualCards[printingKey(expected)]
                require(actual && actual.count === expected.count, "Wrong printing fixture: " + expected.name)
            }
            auditProbe.fixture(manifestFile ? "generated-library-copy" : "real-library-copy",
                               {entries: 960, language: preferences.cardLanguage, manifest: manifestFile})
            capture("large-cube-before")
        })
        if (searchOnly) { planSearch(); return }
        if (!manifestFile) {
            add("Find localized Gnome", () => fill("Oswald Fiddlebender"), () => cards().length === 1)
            add("Gnome subtype does not turn a creature into a land", () => {
                const gallery = find("groupedDeckGallery")
                if (!gallery || gallery.rows.length !== 1) return false
                auditProbe.record("localized-category", {card: cards()[0], rows: gallery.rows})
                capture("localized-gnome-category")
                require(gallery.rows[0].groupKey === "Creatures", "Oswald is a creature; Gnome subtype must not match Land")
            })
            add("Clear localized-card query", () => fill(""), () => cards().length === 960)
        }
        for (let cycle = 0; cycle < 8; ++cycle) {
            add("White identity filter " + cycle, () => click("filterColor-W"), () => cards().length === identityCount("W"))
            add("White-blue identity intersection " + cycle, () => click("filterColor-U"), () => cards().length === identityCount("WU"))
            add("White-blue-black identity intersection " + cycle, () => click("filterColor-B"), () => cards().length === identityCount("WUB"))
            add("Remove black " + cycle, () => click("filterColor-B"), () => cards().length === identityCount("WU"))
            add("Remove blue " + cycle, () => click("filterColor-U"), () => cards().length === identityCount("W"))
            add("Restore all cards " + cycle, () => click("filterColor-W"), () => cards().length === 960)
        }
        add("Open list-view selector", () => click("deckEditorViewMode"),
            () => { const c = find("deckEditorViewMode"); return c && c.popup.visible })
        add("Choose list view", () => {
            require(auditProbe.key(Qt.Key_Home), "Cannot select list view")
            require(auditProbe.key(Qt.Key_Return), "Cannot accept list view")
        }, () => !find("groupedDeckGallery"))
        add("Find exact card", () => fill(editedPrinting.name), () => cards().length === 1)
        for (let cycle = 0; cycle < 20; ++cycle) {
            add("Increment exact card " + cycle, () => click("increaseDeckCardCountButton"), () => exactCount(2))
            add("Decrement exact card " + cycle, () => click("decreaseDeckCardCountButton"), () => exactCount(1))
        }
        add("Clear local query", () => fill(""), () => cards().length === 960)
        add("Capture restored large deck", () => capture("large-cube-after"))
        add("Close editor", () => click("screenBackButton"), () => !!find("editLibraryDeckButton"))
        add("Reopen saved Cube", () => click("editLibraryDeckButton"), () => !!find("deckEditorViewMode"))
        add("Verify persistence and printing", () => {
            require(exactCount(1) && deckLibrary.mainCards.length === 960,
                    "Repeated edits or reopening changed cards")
            require(auditProbe.record("editor-observation", auditProbe.observe(auditWindow)),
                    "Cannot record editor geometry")
            capture("large-cube-reopened")
        })
        planSearch()
    }
    function planSearch() {
        add("Open catalog search", () => click(find("deckEditorQuickSearchButton")
            ? "deckEditorQuickSearchButton" : "deckEditorSearchButton", "deckEditorBody"),
            () => !!find("cardSearchDoneButton"))
        add("Load old search results", () => fill("Lightning Bolt", true),
            () => !cardCatalog.searching && !!find("workbenchCard-Lightning Bolt"))
        add("Capture old search", () => capture("search-old-query"))
        add("New query immediately removes old clickable results", () => {
            searchGrid = find("cardSearchResults")
            require(!!searchGrid, "Missing search grid")
            if (!fill("Counterspell", true)) return false
            const oldResults = searchGrid.count
            const field = find("workbenchSearch", {placeholderText: "Search English or Chinese names…"})
            auditProbe.record("query-transition", {query: field.text, gridCount: oldResults,
                searching: cardCatalog.searching, catalogNames: cardCatalog.searchResults.map(card => card.name)})
            require(oldResults === 0, "Previous query cards remain clickable during debounce")
        })
        add("Await current query result", () => {}, () => !cardCatalog.searching
            && !!find("workbenchCard-Counterspell")
            && searchGrid.cards.every(card => !card.name.includes("Lightning Bolt")))
        add("Capture current search", () => capture("search-current-query"))
        add("Close while next query is pending", () => {
            if (!fill("Swords to Plowshares", true)) return false
            return click("cardSearchDoneButton")
        }, () => !find("cardSearchDoneButton"))
        add("Closed search releases result delegates", () => {
            require(searchGrid.count === 0, "Closed search retained result delegates")
            require(exactCount(1), "Searching or closing unexpectedly changed the deck")
            capture("search-closed")
        })
    }
    function finish(error) {
        finished = true
        auditProbe.record("result", {status: error ? "failed" : "passed", error: error || "",
            scenario: manifestFile ? "generated-library-stress" : "real-library-stress",
            assertions: results, pendingStep: index < steps.length ? steps[index].name : "",
            requiredScreenshots: searchOnly
                ? ["large-cube-before.png", "search-old-query.png", "search-current-query.png", "search-closed.png"]
                : ["large-cube-before.png", "large-cube-after.png", "large-cube-reopened.png",
                    "search-old-query.png", "search-current-query.png", "search-closed.png"]
                  .concat(manifestFile ? [] : ["localized-gnome-category.png"]),
            timing: "Step durations and heartbeat include Qt event dispatch and rendering; captures are separate steps."})
        auditProbe.finish(error ? 1 : 0)
    }
    Component.onCompleted: plan()
    Timer {
        interval: 16
        repeat: true
        running: !driver.finished
        onTriggered: {
            const now = Date.now()
            driver.longestTick = Math.max(driver.longestTick, now - driver.lastTick)
            driver.lastTick = now
        }
    }
    Timer {
        interval: 50
        repeat: true
        running: !driver.finished
        onTriggered: {
            if (driver.dispatching) return
            driver.dispatching = true
            try {
                if (driver.index >= driver.steps.length) { driver.finish(""); return }
                const step = driver.steps[driver.index]
                if (!driver.started) { driver.started = Date.now(); driver.longestTick = 0 }
                driver.require(Date.now() - driver.started < 20000, "Timed out: " + step.name)
                if (auditWindow.stack.busy) return
                if (!driver.acted) driver.acted = step.action() !== false
                if (!driver.acted || !step.check()) return
                driver.results.push({name: step.name, elapsedMs: Date.now() - driver.started,
                    longestTickMs: driver.longestTick})
                auditProbe.record("assertions", driver.results)
                driver.index++; driver.started = 0; driver.acted = false
            } catch (error) {
                auditProbe.record("failure-observation", auditProbe.observe(auditWindow))
                auditProbe.capture(auditWindow, "failure")
                driver.finish(String(error))
            } finally { driver.dispatching = false }
        }
    }
}
