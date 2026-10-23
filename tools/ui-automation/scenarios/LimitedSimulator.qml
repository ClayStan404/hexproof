// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: driver
    property int index: 0
    property bool acted: false
    property bool finished: false
    property bool dispatching: false
    property double started: Date.now()
    property var steps: []
    property var assertions: []
    property var screenshots: []
    property var revealedTile: null
    property int originalDeckCount: 0
    function require(value, message) { if (!value) throw new Error(message + "; " + auditProbe.lastError) }
    function find(name) { return auditProbe.find(auditWindow, name) }
    function click(name) {
        const target = find(name)
        if (!target) return false
        require(auditProbe.click(target), "Cannot click " + name)
        return true
    }
    function walk(root, predicate) {
        if (!root || !root.visible) return null
        if (predicate(root)) return root
        for (const child of root.children || []) { const result = walk(child, predicate); if (result) return result }
        return null
    }
    function fill(target, text) {
        if (!target) return false
        require(auditProbe.click(target), "Cannot focus field")
        require(auditProbe.key(Qt.Key_A, Qt.ControlModifier), "Cannot select field")
        require(auditProbe.type(text), "Cannot type field")
        return true
    }
    function add(name, action, check) { steps.push({name:name, action:action, check:check || (() => true)}) }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        screenshots.push(name + ".png")
    }
    Component.onCompleted: {
        originalDeckCount = deckLibrary.count
        add("Open the offline pack simulator", () => click("mainMenuPackSimulatorButton"), () => !!find("openSimulatedPacksButton"))
        add("Select the installed EOE Play product", () => fill(find("limitedSetSearchField"), "mtgjson-eoe-play"),
            () => find("limitedSetSelector") && find("limitedSetSelector").currentValue === "mtgjson-eoe-play")
        add("Request two boosters", () => fill(walk(auditWindow.contentItem, item => item.placeholderText === "Pack count"), "2"))
        add("Open simulated boosters", () => click("openSimulatedPacksButton"), () => !!find("packOpeningBooster"))
        add("Inspect unrevealed booster", () => capture("booster-before-opening"))
        add("Unwrap the first booster", () => click("packOpeningBooster"), () => !!find("packOpeningCard-3"))
        add("Reveal a specific card out of order", () => {
            const target = find("packOpeningCard-3")
            if (!target) return false
            revealedTile = target.parent
            require(auditProbe.click(target), "Cannot reveal chosen card")
            return true
        }, () => revealedTile && revealedTile.revealed && revealedTile.flipAngle === 180 && !!find("packOpeningCard-0"))
        add("Inspect independently selected reveal", () => capture("one-selected-card"))
        add("Reveal the remaining cards", () => click("packOpeningRevealAllButton"), () => {
            const grid = find("packOpeningCardGrid")
            if (!grid || !find("packOpeningContinueButton")) return false
            for (let i = 0; i < grid.count; ++i) {
                const cell = grid.itemAtIndex(i)
                if (!cell || cell.children[0].flipAngle !== 180) return false
            }
            return true
        })
        add("Inspect the complete first booster", () => {
            const grid = find("packOpeningCardGrid")
            const rarities = Array.from(grid.model).map(card => ["common", "uncommon", "rare", "mythic"].indexOf(card.rarity))
            require(rarities.every((rank, i) => i === 0 || rank >= rarities[i - 1]), "Reveal order is not rarity ordered")
            capture("first-booster-revealed")
        })
        add("Advance to the second booster", () => click("packOpeningContinueButton"), () => !!find("packOpeningBooster"))
        add("Skip the remaining animation", () => click("packOpeningSkipButton"), () => !!find("openSimulatedPacksButton"))
        add("Verify retained packs and offline isolation", () => {
            const packs = auditWindow.stack.currentItem.openedPacks
            const product = cardCatalog.limitedProduct("mtgjson-eoe-play")
            require(packs.length === 2 && packs.every(pack => pack.cards.length === product.cardsPerPack), "Opened pack cards disappeared")
            require(!ws.connected && !ws.inRoom && !tournament.inTournament && !limited.active, "Local simulation created online state")
            require(deckLibrary.count === originalDeckCount, "Local simulation changed the deck library")
            auditProbe.record("opened-packs", {product:product, packs:packs})
            capture("retained-simulated-packs")
        })
    }
    function finish(error) {
        if (finished) return
        finished = true
        if (error) {
            auditProbe.capture(auditWindow, "failure")
            auditProbe.record("failure-state", auditProbe.observe(auditWindow))
        }
        auditProbe.record("result", {status:error ? "failed" : "passed", scenario:"limited-simulator", evidence:"native-qt-input",
            error:error || "", pendingStep:index < steps.length ? steps[index].name : "", assertions:assertions, requiredScreenshots:screenshots,
            coverage:"Offline installed EOE Play product, two boosters, independent reveal, rarity order, next booster, skip and retained results; no online pack injection."})
        auditProbe.finish(error ? 1 : 0)
    }
    Timer {
        interval: 200; repeat: true; running: !driver.finished
        onTriggered: {
            if (driver.dispatching) return
            driver.dispatching = true
            try {
                if (driver.index >= driver.steps.length) { driver.finish(""); return }
                const step = driver.steps[driver.index]
                driver.require(Date.now() - driver.started < 30000, "Timed out: " + step.name)
                if (auditWindow.stack.busy) return
                if (!driver.acted) { if (step.action() === false) return; driver.acted = true }
                if (!step.check()) return
                driver.assertions.push({step:step.name, elapsedMs:Date.now() - driver.started})
                driver.index++; driver.acted = false; driver.started = Date.now()
            } catch (error) { driver.finish(String(error)) }
            finally { driver.dispatching = false }
        }
    }
}
