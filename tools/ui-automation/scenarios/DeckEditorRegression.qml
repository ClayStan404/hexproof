// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import "qrc:/qml/components" as Components

// Production editor/backend acceptance, using make-deck-regression-fixture.py.
// Fixtures prepare data only. All navigation, wheel, drag and count actions use
// the guarded native input API. No view positions or progress flags are written.
Item {
    id: driver

    property var manifest: ({})
    property var steps: []
    property var assertions: []
    property var cases: []
    property var capabilities: ({})
    property var screenshots: []
    property var segments: []
    property var frames: []
    property var modelEvents: []
    property var cacheEvents: []
    property var pressEvents: []
    property var previewTarget: null
    property var galleryTarget: null
    property var progressTarget: null
    property var countTarget: null
    property var countButton: null
    property var countIdentity: ({})
    property var countBefore: ({})
    property var countBaseline: null
    property var wheelPoint: null
    property var wheelDown: null
    property var wheelUp: null
    property var previewDistances: []
    property var previewPoints: []
    property var coldIdentity: null
    property string coldTypeBefore: ""
    property string segment: ""
    property int index: 0
    property int wheelEvents: 0
    property int countPresses: 0
    property double started: 0
    property double waitStarted: 0
    property double wheelBefore: 0
    property double singleNotchTravel: 0
    property double unitsPerNotch: 0
    property double barBefore: 0
    property double barAfter: 0
    property double barSettledAt: 0
    property double sideBefore: 0
    property double sideDistance: 0
    property bool acted: false
    property bool dispatching: false
    property bool recording: false
    property bool finished: false

    function require(value, message) {
        if (!value) throw new Error(message)
    }
    function find(name, scope) {
        return auditProbe.find(scope || auditWindow, name, ({}))
    }
    function walk(item, predicate, found) {
        found = found || []
        if (!item) return found
        if (predicate(item)) found.push(item)
        for (const child of item.children || []) walk(child, predicate, found)
        return found
    }
    function key(card) {
        return [card.name, card.setCode, card.collectorNumber].join("\u001f")
    }
    function exact(card, identity) {
        return card && key(card) === key(identity)
    }
    function visibleCards() {
        const result = [], gallery = galleryTarget
        if (!gallery) return result
        // Inspect current model rows, never pooled delegates left in children.
        for (let rowIndex = 0; rowIndex < gallery.count; ++rowIndex) {
            const row = gallery.itemAtIndex(rowIndex)
            if (row) walk(row, item => item.card && typeof item.resolvedImageSource !== "undefined", result)
        }
        return result
    }
    function fullyVisible(item) {
        const rect = item.mapToItem(galleryTarget, 0, 0, item.width, item.height)
        return rect.y >= 0 && rect.y + rect.height <= galleryTarget.height + 0.5
            && rect.x >= 0 && rect.x + rect.width <= galleryTarget.width + 0.5
    }
    function visualCard(identity) {
        return visibleCards().find(item => (!identity || exact(item.card, identity)) && fullyVisible(item)) || null
    }
    function currentRow(item) {
        const row = item && item.parent ? item.parent.parent : null
        return !!row && galleryTarget.itemAtIndex(row.index) === row && !row.pooled
    }
    function click(name) {
        const item = find(name)
        if (!item) return false
        require(auditProbe.click(item), "Native click failed: " + name)
        return true
    }
    function wait(ms) {
        if (!waitStarted) waitStarted = Date.now()
        return Date.now() - waitStarted >= ms
    }
    function add(name, action, check) {
        steps.push({name: name, action: action, check: check || (() => true)})
    }
    function capture(name) {
        require(!recording, "Capture inside an observed segment")
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        screenshots.push(name + ".png")
    }
    function sample() {
        const gallery = galleryTarget, preview = previewTarget
        const rect = gallery ? gallery.mapToItem(auditWindow.contentItem, 0, 0) : null
        return {time: Date.now(), segment: segment, galleryY: gallery ? gallery.contentY : null,
            originY: gallery ? gallery.originY : null, galleryHeight: gallery ? gallery.height : null,
            gallerySceneY: rect ? rect.y : null, contentHeight: gallery ? gallery.contentHeight : null,
            scrolling: !!(gallery && gallery.scrolling), previewVisible: !!(preview && preview.visible),
            sourceActive: !!(preview && preview.sourceActive), held: !!(preview && preview.previewHeld),
            previewPrinting: preview && preview.card ? key(preview.card) : "",
            canSwitch: !!(preview && preview.facePreview.canSwitch),
            cacheActive: cardCatalog.cacheProgressActive, progressVisible: !!(progressTarget && progressTarget.visible),
            buttonY: countButton ? countButton.mapToItem(auditWindow.contentItem, 0, 0).y : null,
            buttonPrinting: countTarget ? key(countTarget.card) : "",
            currentCountRow: countTarget ? currentRow(countTarget) : false}
    }
    function begin(name) {
        require(!recording, "Nested observation segment")
        segment = name
        frames = []
        recording = true
    }
    function end() {
        recording = false
        const result = {name: segment, frames: frames}
        segments.push(result)
        segment = ""
        return result
    }
    function accept(id, observations) {
        require(!cases.some(row => row.id === id), "Duplicate acceptance case: " + id)
        cases.push({id: id, observations: observations})
    }
    function art(index) {
        const name = "cardHoverPreviewArt" + (index ? "-" + index : "")
        // This is an observation, not a pointer action. The interactive finder
        // correctly rejects a passive Image over another pointer receiver.
        return walk(previewTarget, item => item.objectName === name)[0] || null
    }
    function twoFacesReady() {
        return previewTarget && previewTarget.visible && previewTarget.facePreview.canSwitch
            && previewTarget.facePreview.faces.length === 2
            && [0, 1].every(index => {const image = art(index); return image && image.status === Image.Ready})
    }
    function hoverCard(identity) {
        const card = visualCard(identity)
        if (!card) return false
        require(currentRow(card) && auditProbe.hover(card), "Cannot hover current exact printing")
        return true
    }
    function leavePreview() {
        require(auditProbe.hover(find("deckEditorActions")), "Cannot hover owned editor header")
    }
    function wheel(target, delta, point) {
        require(target, "Wheel target is missing")
        require(point ? auditProbe.wheel(target, point.x, point.y, delta)
                      : auditProbe.wheel(target, delta), "Native wheel failed: " + auditProbe.lastError)
        ++wheelEvents
    }
    function coldPreview(identityField, held) {
        const label = held ? "held-cold" : "source-cold"
        add("Leave prior preview before " + label, leavePreview)
        add("Settle departure before " + label, () => wait(450))
        add("Observe " + label, () => {
            coldIdentity = manifest[identityField]
            coldTypeBefore = coldTypeLine(coldIdentity)
            require(coldTypeBefore.length > 0, "Missing exact cold-printing deck metadata")
            begin(label)
        })
        add("Inspect exact " + label + " printing", () => hoverCard(manifest[identityField]), twoFacesReady)
        if (held) {
            add("Hold real reverse-face preview before publication", () => {
                require(auditProbe.hover(art(1)), "Cannot move onto the real reverse-face image")
            }, () => previewTarget.previewHeld && !previewTarget.sourceActive)
        }
        add("Verify real " + label + " metadata publication", () => wait(1000), () => {
            const observed = end().frames
            const changes = modelEvents.filter(row => row.segment === label && row.event === "changed"
                && row.printing === key(coldIdentity) && row.typeLine.length > 0 && row.typeLine !== coldTypeBefore)
            const first = observed.find(row => row.previewVisible)
            require(first && changes.length > 0, label + " did not exercise real metadata publication")
            require(observed.some(row => row.previewVisible && row.time < changes[0].time),
                label + " did not render a visible preview before its metadata publication")
            const visibleWindow = observed.filter(row => row.time >= first.time)
            const hidden = visibleWindow.filter(row => !row.previewVisible).length
            require(hidden === 0 && previewTarget.visible, label + " rendered a hidden preview")
            const heldBefore = observed.some(row => row.time < changes[0].time && row.held && !row.sourceActive)
            require(!held || heldBefore, "Held preview was not established before metadata publication")
            require(visibleWindow.every(row => row.previewPrinting === key(manifest[identityField])), "Cold preview changed printing")
            const observations = {metadataPublications: changes.length, hiddenFrames: hidden,
                observedFrames: visibleWindow.length, heldBeforePublication: heldBefore,
                visibleBeforePublication: true, metadataChangedForPrinting: true,
                typeLineBefore: coldTypeBefore, typeLineAfter: changes[0].typeLine}
            accept(held ? "deck.preview_held" : "deck.preview_source", observations)
            capture(label)
        })
    }
    function coldTypeLine(identity) {
        const card = identity ? deckLibrary.mainCards.find(row => exact(row, identity)) : null
        return card ? card.typeLine : ""
    }
    function reverseFrames(observed, direction) {
        let count = 0
        for (let index = 1; index < observed.length; ++index)
            if ((observed[index].galleryY - observed[index - 1].galleryY) * direction < -0.5) ++count
        return count
    }
    function maxGalleryDelta(observed, baseline) {
        return Math.max(0, ...observed.map(row => Math.max(Math.abs(row.gallerySceneY - baseline.gallerySceneY),
            Math.abs(row.galleryHeight - baseline.galleryHeight))))
    }
    function counts() {
        const result = ({})
        for (const card of deckLibrary.mainCards) result[key(card)] = card.count
        return result
    }
    function plan() {
        add("Read portable fixture and require real OS input", () => {
            const path = auditProbe.environment("AUDIT_DECK_MANIFEST")
            require(path && auditProbe.environment("AUDIT_OS_INPUT_HELPER"), "Manifest and guarded OS input are required")
            manifest = JSON.parse(auditProbe.readText(path))
            require(manifest.schema === "hexproof.deck-editor-regression.v1" && manifest.synthetic,
                "Generate the explicit synthetic deck regression fixture")
            preferences.uiLanguage = "en"
            preferences.cardLanguage = "en"
            preferences.uiTheme = "glass"
            auditProbe.fixture("portable-deck-regression", {manifest: path, syntheticArt: true,
                coldMetadata: manifest.coldRefresh, productionBackend: true})
        })
        add("Dismiss isolated startup notices", () => {
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"]) {
                if (find(name)) {click(name); return false}
            }
            return !!find("mainMenuDeckLibraryButton")
        })
        add("Open production deck library", () => click("mainMenuDeckLibraryButton"), () => !!find("editLibraryDeckButton"))
        add("Open production image-view editor", () => click("editLibraryDeckButton"), () => !!find("groupedDeckGallery"))
        add("Check runtime fixture capabilities", () => wait(1500), () => {
            const geometry = auditProbe.observe(auditWindow)
            require(geometry.windowMode === "maximized", "Primary acceptance requires the actual maximized display")
            require(cardCatalog.installed && deckLibrary.count === 1, "Missing isolated production catalog/library")
            require(Components.Theme.useGlass, "Production Theme did not select glass")
            galleryTarget = find("groupedDeckGallery")
            progressTarget = walk(auditWindow.stack.currentItem, item => item.objectName === "deckEditorCacheProgress")[0]
            previewTarget = walk(auditWindow.stack.currentItem, item => typeof item.inspect === "function"
                && typeof item.sourceItem !== "undefined" && typeof item.hide === "function")[0]
            require(galleryTarget && progressTarget && previewTarget, "Missing production editor components")
            require(deckLibrary.mainCards.length === manifest.mainRows && deckLibrary.sideboardCards.length === manifest.sideRows,
                "Fixture row totals differ from its independent manifest")
            const faceCounts = [manifest.sourceCold, manifest.heldCold].map(card =>
                cardCatalog.cardFaces(card.name, card.setCode, card.collectorNumber).length)
            const singleFaces = cardCatalog.cardFaces(manifest.singleFace.name,
                manifest.singleFace.setCode, manifest.singleFace.collectorNumber).length
            const singleType = cardCatalog.cardTypeLine(manifest.singleFace.name,
                manifest.singleFace.setCode, manifest.singleFace.collectorNumber)
            require(faceCounts.every(count => count === 2) && singleFaces < 2 && singleType.length > 0,
                "Full exact face metadata and a valid single-face printing are required")
            require(galleryTarget.contentHeight > galleryTarget.height, "The gallery must actually scroll")
            capabilities = {syntheticArt: true, mainRows: deckLibrary.mainCards.length,
                sideRows: deckLibrary.sideboardCards.length, faceCount: Math.min(...faceCounts),
                catalogInstalled: cardCatalog.installed, exactFaceCounts: faceCounts, singleFaceCount: singleFaces,
                singleFaceTypeLine: singleType, uiScale: Components.Theme.uiScale}
            auditProbe.record("runtime-fixture", capabilities)
            auditProbe.record("window-geometry", geometry)
            capture("editor-idle")
        })
        coldPreview("sourceCold", false)
        coldPreview("heldCold", true)
        // The manifest is loaded by the first step, so late-bound identities
        // are resolved by these wrappers rather than plan-time values.
        add("Leave held preview before scrolling", leavePreview)
        add("Settle held departure", () => wait(450))
        add("Hover single-face art for native wheel", () => hoverCard(manifest.singleFace), () => previewTarget.visible)
        add("Calibrate actual single-notch travel", () => {
            const card = visualCard(manifest.singleFace)
            wheelPoint = card.mapToItem(galleryTarget, card.width / 2, card.height * 0.35)
            wheelBefore = galleryTarget.contentY
            begin("wheel-single-notch")
            wheel(galleryTarget, -120, wheelPoint)
        })
        add("Measure settled notch and require unbounded burst space", () => wait(400), () => {
            end()
            singleNotchTravel = galleryTarget.contentY - wheelBefore
            unitsPerNotch = singleNotchTravel / Components.Theme.uiScale
            const remaining = galleryTarget.originY + Math.max(0, galleryTarget.contentHeight - galleryTarget.height)
                - galleryTarget.contentY
            require(singleNotchTravel > 0 && unitsPerNotch >= 47.5, "Wheel travel regressed below the 2.5 behavior floor")
            require(remaining > 3 * singleNotchTravel + 1, "Same-direction burst would hit a scroll boundary")
        })
        add("Start constant downward wheel segment", () => {
            wheelBefore = galleryTarget.contentY
            begin("wheel-down")
        })
        for (let number = 0; number < 3; ++number)
            add("Downward art wheel " + number, () => wheel(galleryTarget, -120, wheelPoint))
        add("Settle downward wheel", () => wait(400), () => {
            wheelDown = end()
            wheelDown.distance = galleryTarget.contentY - wheelBefore
            require(wheelDown.distance > 0, "Downward wheel did not move the gallery")
        })
        add("Start constant upward wheel segment", () => {wheelBefore = galleryTarget.contentY; begin("wheel-up")})
        for (let number = 0; number < 3; ++number)
            add("Upward art wheel " + number, () => wheel(galleryTarget, 120, wheelPoint))
        add("Settle stationary pointer after upward wheel", () => wait(900), () => {
            wheelUp = end()
            wheelUp.distance = galleryTarget.contentY - wheelBefore
            require(wheelUp.distance < 0, "Upward wheel did not reverse gallery travel")
            require(previewTarget.visible && previewTarget.sourceActive && previewTarget.sourceItem
                && previewTarget.sourceItem.isHoveredForPreview(), "Stationary pointer did not recover inspection")
        })
        add("Observe rapid discrete reversals", () => begin("wheel-reversals"))
        for (let number = 0; number < 6; ++number)
            add("Rapid reverse wheel " + number, () => wheel(galleryTarget, number % 2 ? 120 : -120, wheelPoint))
        add("Verify wheel bounds after reversals", () => wait(450), () => {
            const rapid = end().frames
            require(rapid.length > 0 && rapid.every(row => row.galleryY >= row.originY - 0.5
                && row.galleryY <= row.originY + Math.max(0, row.contentHeight - row.galleryHeight) + 0.5),
                "Rapid reversal escaped the current scroll bounds")
        })
        add("Scroll actual sideboard", () => {
            const side = find("sideboardList")
            require(side && side.contentHeight > side.height, "Sideboard must actually scroll")
            sideBefore = side.contentY
            wheel(side, -120)
        })
        add("Complete native wheel acceptance", () => wait(450), () => {
            sideDistance = find("sideboardList").contentY - sideBefore
            const observed = wheelDown.frames.concat(wheelUp.frames)
            const scrolling = observed.filter(row => row.scrolling)
            const reversed = reverseFrames(wheelDown.frames, 1) + reverseFrames(wheelUp.frames, -1)
            const accumulated = wheelDown.distance / (3 * singleNotchTravel)
            require(wheelDown.frames.length > 0 && wheelUp.frames.length > 0, "Missing rendered wheel frames")
            require(scrolling.length > 0 && scrolling.every(row => !row.previewVisible), "Preview remained visible while scrolling")
            require(reversed === 0 && sideDistance > 0 && accumulated >= 0.95,
                "Wheel reversed, lost burst travel, or sideboard swallowed input")
            accept("deck.wheel", {wheelEvents: wheelEvents, downDistance: wheelDown.distance,
                upDistance: wheelUp.distance, sameDirectionReverseFrames: reversed,
                previewHiddenWhileScrolling: true, previewRecoveredAfterScroll: true,
                rapidReverseEvents: 6, sideboardDistance: sideDistance,
                unitsPerNotch: unitsPerNotch, accumulatedTravelRatio: accumulated,
                measuredSingleNotchTravel: singleNotchTravel, unboundedBurstNotches: 3})
        })
        for (let face = 0; face < 2; ++face) {
            add("Return gallery to top for preview face " + face, () => wheel(galleryTarget, 1920,
                {x: galleryTarget.width - 20, y: 80}))
            add("Settle gallery for preview face " + face, () => wait(450), () =>
                require(galleryTarget.atYBeginning, "Bounded reset did not reach the actual gallery beginning"))
            add("Leave old preview for face " + face, leavePreview)
            add("Settle departure for face " + face, () => wait(450))
            add("Inspect warmed modal printing for face " + face, () => hoverCard(manifest.sourceCold), twoFacesReady)
            add("Wheel over actual preview face " + face, () => {
                const image = art(face), gallery = galleryTarget, surface = find("deckEditorMainSurface")
                require(image && gallery.contentHeight > gallery.height, "Missing face image or scrollable gallery")
                const rect = image.mapToItem(gallery, 0, 0, image.width, image.height)
                const left = Math.max(0, rect.x), top = Math.max(0, rect.y)
                const right = Math.min(gallery.width, rect.x + rect.width), bottom = Math.min(gallery.height, rect.y + rect.height)
                require(right > left && bottom > top, "Preview face does not intersect gallery viewport")
                const point = {x: (left + right) / 2, y: (top + bottom) / 2}
                previewPoints.push({face: face, x: point.x, y: point.y, width: gallery.width, height: gallery.height})
                wheelBefore = gallery.contentY
                begin("preview-face-" + face)
                wheel(surface, -120, gallery.mapToItem(surface, point.x, point.y))
            })
            add("Verify preview face " + face + " wheel routing", () => wait(450), () => {
                end()
                previewDistances.push(galleryTarget.contentY - wheelBefore)
                require(previewDistances[face] > 0, "Preview swallowed wheel on face " + face)
            })
        }
        add("Complete both-face wheel acceptance", () => {
            accept("deck.preview_wheel", {faceCount: 2, frontDistance: previewDistances[0],
                backDistance: previewDistances[1], pointsInsideGallery: previewPoints.every(point =>
                    point.x >= 0 && point.x < point.width && point.y >= 0 && point.y < point.height)})
        })
        add("Start wheel then transfer ownership to scrollbar", () => {
            barBefore = galleryTarget.contentY
            begin("scrollbar")
            wheel(galleryTarget, -120, {x: galleryTarget.width - 20, y: 80})
            const bar = find("deckGalleryScrollBar"), thumb = bar ? bar.contentItem : null
            require(bar && thumb, "Missing actual gallery scrollbar")
            const point = thumb.mapToItem(bar, thumb.width / 2, thumb.height / 2)
            require(auditProbe.drag(bar, bar, point.x, point.y), "Cannot drag native scrollbar")
        })
        add("Settle scrollbar ownership", () => wait(350), () => {barAfter = galleryTarget.contentY; barSettledAt = Date.now()})
        add("Verify no scrollbar pullback", () => wait(450), () => {
            const observed = end().frames.filter(row => row.time >= barSettledAt)
            require(observed.length > 0, "No post-settle scrollbar frames")
            const drift = Math.max(...observed.map(row => Math.abs(row.galleryY - barAfter)))
            require(barAfter > barBefore && drift <= 0.5, "Scrollbar was pulled back by prior wheel motion")
            accept("deck.scrollbar", {distance: barAfter - barBefore, postSettleDrift: drift})
        })
        add("First exact-printing count click during hover cache activity", () => {
            countTarget = visibleCards().find(item => fullyVisible(item)
                && cardCatalog.cardFaces(item.card.name, item.card.setCode, item.card.collectorNumber).length < 2)
            require(countTarget && currentRow(countTarget), "No current fully visible single-face count target")
            countIdentity = {name: countTarget.card.name, setCode: countTarget.card.setCode,
                collectorNumber: countTarget.card.collectorNumber}
            require(deckLibrary.mainCards.some(card => card.name === countIdentity.name
                && key(card) !== key(countIdentity)), "Exact-count fixture needs a same-name sibling printing")
            countButton = walk(countTarget, item => item.text === "+" && item.visible && item.enabled)[0]
            require(countButton, "Missing exact-printing count button")
            countBefore = counts()
            countPresses = 0
            countButton.pressedChanged.connect(() => {
                if (countButton && countButton.pressed) {++countPresses; pressEvents.push(sample())}
            })
            begin("first-count")
            countBaseline = sample()
            const surface = find("deckEditorMainSurface")
            const originalPoint = countButton.mapToItem(surface, countButton.width / 2, countButton.height / 2)
            // Explicitly move first so the genuine deferred priority pulse
            // occurs before press, even with a very fast local-only fixture.
            // Retain the original point: never retarget after a layout change.
            require(auditProbe.hover(countButton), "Cannot hover the exact count control")
            require(auditProbe.click(surface, originalPoint.x, originalPoint.y), "First native count click was rejected")
        })
        add("Verify the first count click exactly once", () => wait(500), () => {
            const observed = end().frames, pressed = pressEvents[0], after = counts(), printing = key(countIdentity)
            require(pressed && countPresses === 1, "First count click did not reach its AppButton once")
            const window = observed.concat(cacheEvents).filter(row => row.segment === "first-count"
                && row.time >= countBaseline.time && row.time <= pressed.time).concat([countBaseline, pressed])
            const active = cacheEvents.some(row => row.segment === "first-count" && row.cacheActive
                && row.time >= countBaseline.time && row.time <= pressed.time)
            const galleryDelta = maxGalleryDelta(window, countBaseline)
            const buttonDelta = Math.max(...window.map(row => Math.abs(row.buttonY - countBaseline.buttonY)))
            const same = pressed.currentCountRow && pressed.buttonPrinting === printing
                && Object.keys(countBefore).every(identity => after[identity] === countBefore[identity] + (identity === printing ? 1 : 0))
            require(active && galleryDelta <= 0.5 && buttonDelta <= 0.5 && same, "Count target moved or changed printing during cache activity")
            accept("deck.first_count", {cacheActiveBeforePress: active, maxGalleryDelta: galleryDelta,
                maxButtonDelta: buttonDelta, countDelta: after[printing] - countBefore[printing],
                presses: countPresses, samePrinting: same})
            capture("first-count-once")
        })
        add("Leave preview before explicit caching", leavePreview)
        add("Settle activity before explicit caching", () => wait(500) && !cardCatalog.cacheProgressActive)
        add("Open real editor cache menu", () => click("deckEditorMoreButton"))
        add("Trigger real explicit deck-art caching", () => {
            begin("explicit-cache")
            countBaseline = sample()
            require(click("cacheCurrentDeckArtButton"), "Cannot trigger real cache command")
        })
        add("Verify visible progress without layout drift", () => wait(700) && !cardCatalog.cacheProgressActive, () => {
            const observed = end().frames
            const active = observed.filter(row => row.cacheActive)
            const delta = maxGalleryDelta(observed, countBaseline)
            require(active.length >= 2 && active.every(row => row.progressVisible), "Explicit cache progress was not visibly exercised")
            require(delta <= 0.5, "Real explicit cache activity moved gallery layout")
            accept("deck.explicit_cache", {activeSamples: active.length, visibleDuringActivity: true,
                maxGalleryDelta: delta, completed: !cardCatalog.cacheProgressActive})
            capture("explicit-cache-complete")
        })
    }
    function finish(error) {
        if (finished) return
        if (recording) end()
        finished = true
        auditProbe.record("observed-segments", segments)
        auditProbe.record("metadata-events", modelEvents)
        auditProbe.record("cache-events", cacheEvents)
        auditProbe.record("count-press-events", pressEvents)
        auditProbe.record("ui-baseline", {schema: "hexproof.ui-baseline-evidence.v1",
            referenceCommit: "8529743029c48334ab3e2381a74edd18087ba2e0", scenario: "deck-editor-regression",
            fixture: capabilities, cases: cases, performance: "not-assessed"})
        auditProbe.record("result", {status: error ? "failed" : "passed", scenario: "deck-editor-regression",
            error: error || "", pendingStep: index < steps.length ? steps[index].name : "",
            assertions: assertions, requiredScreenshots: screenshots, performance: "not-assessed",
            limitations: ["Synthetic geometric art and generated metadata; no real-game or artwork-fidelity claim.",
                "OS helper discrete wheel input does not represent fine deltas or physical polling cadence."]})
        auditProbe.finish(error ? 1 : 0)
    }
    Connections {
        target: deckLibrary
        function onCurrentDeckCardsAboutToChange() {driver.modelEvents.push({time: Date.now(), segment: driver.segment, event: "about"})}
        function onCurrentDeckCardsChanged() {
            driver.modelEvents.push({time: Date.now(), segment: driver.segment, event: "changed",
                printing: driver.coldIdentity ? driver.key(driver.coldIdentity) : "",
                typeLine: driver.coldTypeLine(driver.coldIdentity)})
        }
    }
    Connections {
        target: cardCatalog
        function onBusyChanged() {if (driver.recording) driver.cacheEvents.push(driver.sample())}
    }
    FrameAnimation {
        running: driver.recording
        onTriggered: {
            const value = driver.sample()
            value.frameTime = frameTime
            driver.frames.push(value)
        }
    }
    Component.onCompleted: plan()
    Timer {
        interval: 50
        repeat: true
        running: !driver.finished
        onTriggered: {
            if (driver.dispatching || auditWindow.stack.busy) return
            driver.dispatching = true
            try {
                if (driver.index >= driver.steps.length) {driver.finish(""); return}
                const step = driver.steps[driver.index]
                if (!driver.started) driver.started = Date.now()
                driver.require(Date.now() - driver.started < 20000, "Timed out: " + step.name)
                if (!driver.acted) driver.acted = step.action() !== false
                if (!driver.acted || step.check() === false) return
                driver.assertions.push({name: step.name, elapsedMs: Date.now() - driver.started})
                ++driver.index
                driver.started = 0
                driver.waitStarted = 0
                driver.acted = false
            } catch (error) {
                if (driver.recording) driver.end()
                driver.capture("failure")
                driver.finish(String(error))
            } finally {
                driver.dispatching = false
            }
        }
    }
}
