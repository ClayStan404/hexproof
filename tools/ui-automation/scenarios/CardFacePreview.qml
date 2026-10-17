// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

// Production draft/table components and the real installed card catalog.
// Private packs and Forge snapshots are explicit fixtures, not live games.
Item {
    id: driver
    property var steps: []
    property var assertions: []
    property var screenshots: []
    property var draftView: null
    property var tableSnapshot: ({})
    property var stateBeforePreview: ({})
    property string manualHandBefore: ""
    property string manualCardBefore: ""
    property var originalPreferences: ({})
    property int index: 0
    property bool acted: false
    property bool dispatching: false
    property bool finished: false
    property double stepStarted: Date.now()
    readonly property var roku: ({instanceId:"preview-roku", name:"The Legend of Roku // Avatar Roku",
                                  setCode:"TLA", collectorNumber:"357"})
    readonly property var delver: ({instanceId:"preview-delver", name:"Delver of Secrets // Insectile Aberration",
                                    setCode:"ISD", collectorNumber:"51"})

    QtObject {
        id: privatePack
        signal snapshotChanged()
        property string eventType: "set_draft"
        property string tournamentId: "native-face-preview-fixture"
        property var participants: [{participantId:"preview-a", displayName:"Fixture player", autoDraft:false},
                                    {participantId:"preview-b", displayName:"Fixture neighbor", autoDraft:false}]
        property var currentPack: [driver.roku, driver.delver]
        property var currentPacks: []
        property var pool: []
        property int packRound: 1
        property int packsThisBatch: 1
        property int packsPerPlayer: 3
        property int picksRequired: 1
        property int direction: 1
    }
    QtObject {
        id: draftTournament
        property string participantId: "preview-a"
    }
    QtObject {
        id: draftTransport
        property bool connected: true
        property string serverUrl: "native-preview-fixture"
        property int pickCount: 0
        property var pickedIds: []
        function pickLimitedCard(id) { pickCount++; pickedIds = [id] }
        function pickLimitedCards(ids) { pickCount++; pickedIds = ids.slice() }
    }
    Item {
        id: draftHost
        objectName: "nativeDraftPreviewFixture"
        parent: auditWindow.contentItem
        anchors.fill: parent
        anchors.margins: 32
        visible: false
        z: 5000
        Rectangle { anchors.fill: parent; color: "#10231d" }
    }

    function require(value, message) {
        if (!value) throw new Error(message + (auditProbe.lastError ? "; " + auditProbe.lastError : ""))
    }
    function find(name, scope) { return auditProbe.find(scope || auditWindow, name) }
    function lookup(name, scope, hidden) {
        const walk = item => {
            if (item.objectName === name && (hidden || item.visible)) return item
            for (const child of item.children || []) {
                const found = walk(child)
                if (found) return found
            }
            return null
        }
        return walk(scope || auditWindow.contentItem)
    }
    function add(name, action, check, timeout) {
        steps.push({name:name, action:action, check:check || (() => true), timeout:timeout || 20000})
    }
    function waited(ms) { return Date.now() - stepStarted >= ms }
    function capture(name) {
        require(auditProbe.capture(auditWindow, name), "Cannot capture " + name)
        screenshots.push(name + ".png")
    }
    function hover(name, scope) {
        const target = find(name, scope)
        require(target, "Cannot locate hover target " + name)
        require(auditProbe.hover(target), "Cannot hover " + name)
    }
    function click(name, scope) { require(auditProbe.click(find(name, scope)), "Cannot click " + name) }
    function draftPreview() { return lookup("limitedDraftCardHoverPreview", draftView, true) }
    function table() { return lookup("forgeDuelTable") }
    function inspector() { return lookup("rulesCardInspector", auditWindow.contentItem, true) }
    function tablePreview() { return lookup("rulesCardHoverPreview", auditWindow.contentItem, true) }
    function manualPage() { return auditWindow.stack.currentItem }
    function manualPreview() { return lookup("cardHoverPreview", manualPage(), true) }
    function unchangedDraft() {
        require(draftView.selectedInstanceId === "", "Preview changed the draft selection")
        require(draftView.selectedInstanceIds.length === 0, "Preview changed multi-pick selection")
        require(draftTransport.pickCount === 0, "Preview submitted a draft pick")
        require(privatePack.currentPack.length === 2 && privatePack.pool.length === 0,
                "Preview changed the private pack or pool")
    }
    function rulesState() {
        return {gameId:ws.rulesSession.gameId, revision:ws.rulesSession.snapshotRevision,
                turn:ws.rulesSession.turn, step:ws.rulesSession.step,
                card:JSON.stringify(ws.rulesSession.cardForInspection("preview-permanent"))}
    }
    function unchangedRules() {
        require(JSON.stringify(rulesState()) === JSON.stringify(stateBeforePreview),
                "Viewing another face changed the rules projection")
    }
    function unchangedManualHand() {
        require(JSON.stringify(gameTable.zoneModel(0, "hand").get(0)) === manualHandBefore
            && JSON.stringify(gameTable.cardData("manual-preview-hand")) === manualCardBefore
            && gameTable.cardInZone("manual-preview-hand", "hand", 0),
            "Face inspection changed or moved the manual hand card")
        require(!manualPage().selectedHandCard.id && manualPage().activeHandDragCardId === "",
            "Face inspection selected or dragged the manual hand card")
    }
    function artReady(preview, name, artObjectName) {
        if (!preview || !preview.visible || preview.opacity < 0.99) return false
        const state = preview.facePreview || inspector().facePreview
        const faceIndex = state.displayFaces.findIndex(face => face.name === name)
        if (faceIndex < 0) return false
        const art = lookup(artObjectName + (faceIndex ? "-" + faceIndex : ""), preview, true)
        return !!art && art.status === Image.Ready
            && String(art.source) === String(state.displayFaces[faceIndex].imageSource)
    }
    function bothReady(preview, names, artObjectName) {
        return names.every(name => artReady(preview, name, artObjectName))
            && !(lookup("viewOtherFaceButton", preview, true))
    }
    function fieldCard(name, extra) {
        return Object.assign({id:"preview-permanent", ownerSeat:0, controllerSeat:0, visible:true,
            power:"1", toughness:"1", identity:{name:name, setCode:"ISD", collectorNumber:"51"}}, extra || {})
    }
    function applyTable(name, extra) {
        tableSnapshot = {roomId:"FACE01", gameId:"native-face-preview", turn:3, step:"main1",
            activeSeat:0, prioritySeat:0,
            players:[{seat:0, name:"Fixture player", life:20}, {seat:1, name:"Fixture opponent", life:20}],
            zones:[{zone:"battlefield", ownerSeat:0, count:1, cards:[fieldCard(name, extra)]},
                {zone:"battlefield", ownerSeat:1, count:0, cards:[]},
                {zone:"hand", ownerSeat:0, count:0, cards:[]}, {zone:"hand", ownerSeat:1, count:7, cards:[]},
                {zone:"library", ownerSeat:0, count:40, cards:[]}, {zone:"library", ownerSeat:1, count:40, cards:[]}],
            stack:[]}
        const room = {roomId:"FACE01", name:"Card-face preview fixture", format:"modern", deckFormat:"custom",
            rulesMode:"forge", hostingMode:"server", hostConnected:true, maxSeats:2, phase:"started",
            matchMode:"bo1", role:"player", seatIndex:0, host:true,
            seats:[{occupied:true, displayName:"Fixture player", host:true, ready:true, loaded:true},
                {occupied:true, displayName:"Fixture opponent", ready:true, loaded:true}]}
        require(auditProbe.applyRulesTableFixture(room, tableSnapshot), "Cannot apply Forge table fixture")
    }
    function finish(error) {
        if (finished) return
        finished = true
        if (error && auditProbe.capture(auditWindow, "failure")) screenshots.push("failure.png")
        if (draftView) {
            draftView.hideCardPreview()
            draftView.destroy()
            draftView = null
        }
        draftHost.visible = false
        const currentInspector = inspector()
        if (currentInspector) currentInspector.hidePreview()
        if (originalPreferences.uiLanguage !== undefined) preferences.uiLanguage = originalPreferences.uiLanguage
        if (originalPreferences.cardLanguage !== undefined) preferences.cardLanguage = originalPreferences.cardLanguage
        if (originalPreferences.forgeFullControl !== undefined) preferences.forgeFullControl = originalPreferences.forgeFullControl
        const geometry = auditProbe.observe(auditWindow)
        auditProbe.record("window-geometry", geometry)
        auditProbe.record("result", {status:error ? "failed" : "passed", scenario:"card-face-preview",
            evidence:"system-input", roomAndDeckSetup:"fixed-private-pack-and-rules-snapshot-fixtures",
            liveEngineGame:false, realInstalledCatalog:true, error:error || "",
            pendingStep:index < steps.length ? steps[index].name : "", assertions:assertions,
            requiredScreenshots:screenshots, picksSubmitted:draftTransport.pickCount,
            requestedWindowMode:geometry.requestedWindowMode, windowMode:geometry.windowMode,
            width:geometry.width, height:geometry.height, dpr:geometry.dpr, screenGeometry:geometry.screenGeometry})
        auditProbe.finish(error ? 1 : 0)
    }
    function plan() {
        add("Dismiss first-launch notices", () => {
            for (const name of ["dismissSponsorsButton", "laterCardArtRepairButton"]) {
                if (find(name)) { click(name); return false }
            }
            return !!find("mainMenuSettingsButton")
        })
        add("Prepare missing cached face metadata", () => {
            require(auditProbe.observe(auditWindow).windowMode === "maximized", "Expected a maximized window")
            require(cardCatalog.installed, "An installed card database is required")
            originalPreferences = {uiLanguage:preferences.uiLanguage, cardLanguage:preferences.cardLanguage,
                                   forgeFullControl:preferences.forgeFullControl}
            preferences.uiLanguage = "en"
            preferences.cardLanguage = "en"
            preferences.forgeFullControl = true
            for (const card of [roku, delver])
                cardCatalog.prepareCardFacePreview(card.name, card.setCode, card.collectorNumber)
        }, () => [roku, delver].every(card => cardCatalog.cardFaces(card.name, card.setCode, card.collectorNumber).length === 2), 90000)
        add("Load real printing faces through the normal catalog cache", () => {
            const requests = []
            for (const card of [roku, delver]) {
                const faces = cardCatalog.cardFaces(card.name, card.setCode, card.collectorNumber)
                require(faces.length === 2, "Expected two catalog faces for " + card.name)
                for (const face of faces) requests.push(face)
            }
            cardCatalog.prioritizeCards(requests)
            auditProbe.fixture("card-face-private-pack", {description:"Two fixed private cards in the production LimitedDraftView; not a live draft",
                cards:[roku, delver]})
        }, () => [roku, delver].every(card => cardCatalog.cardFaces(card.name, card.setCode, card.collectorNumber)
                .every(face => !!cardCatalog.imageSource(face.faceName || face.name, face.setCode, face.collectorNumber))), 90000)
        add("Create the production draft view with the private fixture", () => {
            const component = Qt.createComponent("qrc:/qml/components/LimitedDraftView.qml")
            require(component.status === Component.Ready, component.errorString())
            draftView = component.createObject(draftHost, {limitedModel:privatePack, tournamentModel:draftTournament,
                wsModel:draftTransport, cardCatalogModel:cardCatalog, draftStore:null,
                width:draftHost.width, height:draftHost.height})
            require(draftView, "Cannot create LimitedDraftView")
            draftView.anchors.fill = draftHost
            draftHost.visible = true
        }, () => !!find("limitedDraftPackCard-preview-roku", draftView))
        add("Hover the real Roku printing", () => hover("limitedDraftPackCard-preview-roku", draftView),
            () => artReady(draftPreview(), "The Legend of Roku", "limitedDraftCardHoverPreviewArt"))
        add("Read both Roku faces without clicking", () => {
            unchangedDraft()
            require(draftPreview().sourceActive, "The draft source must remain hovered")
        }, () => waited(550) && bothReady(draftPreview(), ["The Legend of Roku", "Avatar Roku"], "limitedDraftCardHoverPreviewArt"))
        add("Capture both draft faces with unchanged selection", () => {
            unchangedDraft()
            require(draftPreview().sourceItem !== null, "Lost the preview source during handoff")
            capture("draft-roku-both-faces")
        }, () => artReady(draftPreview(), "The Legend of Roku", "limitedDraftCardHoverPreviewArt"))
        add("Leave both draft faces and let the preview close", () => {
            unchangedDraft()
            hover("limitedDraftPicksScroll", draftView)
        }, () => !draftPreview().visible)
        add("Inspect another tile and clear the preview when the draft closes", () => {
            unchangedDraft()
            hover("limitedDraftPackCard-preview-delver", draftView)
        }, () => artReady(draftPreview(), "Delver of Secrets", "limitedDraftCardHoverPreviewArt"))
        add("Select the other tile deliberately and close the fixture", () => {
            unchangedDraft()
            click("limitedDraftPackCard-preview-delver", draftView)
            require(draftView.selectedInstanceId === "preview-delver", "The other tile did not remain selectable")
            require(draftTransport.pickCount === 0, "Selecting a tile unexpectedly submitted a pick")
            capture("draft-other-card-front")
            draftHost.visible = false
        }, () => !draftView.hoverPreviewVisible)
        add("Open the production Forge table on Delver's front", () => {
            draftView.destroy(); draftView = null
            applyTable("Delver of Secrets")
            auditWindow.showTable()
        }, () => table() && !table().stagingMotion && !lookup("forgeTurnCallout")
            && !!find("forgeCard-preview-permanent"))
        add("Hover the visible rules permanent", () => {
            stateBeforePreview = rulesState()
            hover("forgeCard-preview-permanent")
        }, () => inspector() && inspector().previewCardId === "preview-permanent"
            && artReady(tablePreview(), "Delver of Secrets", "rulesCardHoverPreviewArt"))
        add("Read both rules faces without transforming the permanent", () => {
            require(inspector().previewSourceActive, "The rules source must remain hovered")
        }, () => waited(550) && bothReady(tablePreview(), ["Delver of Secrets", "Insectile Aberration"], "rulesCardHoverPreviewArt"))
        add("Capture both faces and publish a real current-back projection", () => {
            unchangedRules()
            require(inspector().card.name === "Delver of Secrets", "Preview replaced current engine identity")
            capture("rules-front-permanent-both-faces")
            tableSnapshot.zones[0].cards[0] = fieldCard("Insectile Aberration", {power:"3", toughness:"2"})
            require(auditProbe.updateRulesTableFixture(tableSnapshot), "Cannot publish current back fixture")
        }, () => ws.rulesSession.cardForInspection("preview-permanent").name === "Insectile Aberration"
            && inspector().facePreview.viewedName === "Insectile Aberration")
        add("Start on the current back and read both faces", () => {
            stateBeforePreview = rulesState()
            require(inspector().previewSourceActive, "The rules source must remain hovered")
        }, () => waited(550) && bothReady(tablePreview(), ["Insectile Aberration", "Delver of Secrets"], "rulesCardHoverPreviewArt"))
        add("Capture current-back ordering and turn the permanent face down", () => {
            unchangedRules()
            require(inspector().card.name === "Insectile Aberration", "Preview changed the back permanent")
            capture("rules-back-permanent-both-faces")
            // The owner's wire projection may retain a known face-down identity.
            tableSnapshot.zones[0].cards[0] = fieldCard("Insectile Aberration", {faceDown:true, power:"2", toughness:"2"})
            require(auditProbe.updateRulesTableFixture(tableSnapshot), "Cannot publish face-down fixture")
        }, () => !inspector().hasIdentity && !inspector().facePreview.canSwitch && !tablePreview().visible)
        add("Keep known owner data separate from face-down inspection", () => {
            const known = ws.rulesSession.cardForInspection("preview-permanent")
            require(known.faceDown === true && known.visibleIdentity === true
                && known.name === "Insectile Aberration", "Changed the authorized owner projection")
            require(inspector().facePreview.faces.length === 0 && inspector().facePreview.viewedName === ""
                && inspector().facePreview.imageSource === "", "Face-down owner card retained preview data")
            // A redacted wire identity must discard even deliberately stale name data.
            tableSnapshot.zones[0].cards[0] = fieldCard("Insectile Aberration",
                {faceDown:true, visible:false, power:"2", toughness:"2"})
            require(auditProbe.updateRulesTableFixture(tableSnapshot), "Cannot publish redacted fixture")
        }, () => ws.rulesSession.cardForInspection("preview-permanent").visibleIdentity === false)
        add("Verify face-down privacy and capture the final table", () => {
            const hidden = ws.rulesSession.cardForInspection("preview-permanent")
            require(hidden.faceDown === true && hidden.visibleIdentity === false && !hidden.name,
                    "Face-down projection leaked the retained identity")
            require(inspector().facePreview.faces.length === 0 && inspector().facePreview.viewedName === ""
                && inspector().facePreview.imageSource === "", "Face-down card retained face inspection data")
            capture("rules-face-down-cleared")
        })
        add("Place the known double-faced card in the Forge hand", () => {
            tableSnapshot.zones[0].count = 0
            tableSnapshot.zones[0].cards = []
            tableSnapshot.zones[2].count = 1
            tableSnapshot.zones[2].cards = [fieldCard("Delver of Secrets")]
            require(auditProbe.updateRulesTableFixture(tableSnapshot), "Cannot publish Forge hand fixture")
        }, () => !!find("forgeHandCard-preview-permanent"))
        add("Hover the production Forge hand card", () => {
            stateBeforePreview = rulesState()
            hover("forgeHandCard-preview-permanent")
        }, () => inspector().previewCardId === "preview-permanent"
            && artReady(tablePreview(), "Delver of Secrets", "rulesCardHoverPreviewArt"))
        add("Read both Forge hand faces without playing the card", () => {
            require(inspector().previewSourceActive, "The rules source must remain hovered")
        }, () => waited(550) && bothReady(tablePreview(), ["Delver of Secrets", "Insectile Aberration"], "rulesCardHoverPreviewArt"))
        add("Capture the unchanged Forge hand and leave its preview", () => {
            unchangedRules()
            require(inspector().card.zone === "hand" && inspector().card.name === "Delver of Secrets",
                "Forge hand face inspection changed its current identity or zone")
            capture("forge-hand-both-faces")
            hover("rulesPlayerTarget1")
        }, () => !tablePreview().visible)
        add("Pin the Forge hand inspector and read both faces", () => {
            require(auditProbe.rightClick(find("forgeHandCard-preview-permanent")), "Cannot pin the hand inspector")
            hover("rulesPlayerTarget1")
        }, () => inspector().pinned && !inspector().previewCardId
            && bothReady(inspector(), ["Delver of Secrets", "Insectile Aberration"], "rulesCardInspectorArt"))
        add("Capture both pinned faces without changing the Forge hand", () => {
            unchangedRules()
            capture("forge-hand-pinned-both-faces")
        })
        add("Open the production manual table with a known private hand", () => {
            const seat = (index, hand) => ({seat:index, displayName:"Fixture player " + index, life:20,
                handCount:hand.length || 7, libraryCount:40, hand:hand, battlefield:[],
                graveyard:[], exile:[], commandZone:[], counters:[]})
            const hand = Object.assign({}, delver, {id:"manual-preview-hand", faceDown:false})
            const snapshot = {roomId:"HAND01", gameNumber:1, startingSeat:0, turnOrder:[0,1], activeSeat:0,
                currentPhase:"main1", seats:[seat(0,[hand]), seat(1,[])], stack:[], revealed:[],
                arrows:[], attachments:[], log:[], score:[0,0], result:{}, sideboard:{}}
            const room = {roomId:"HAND01", name:"Manual hand face-preview fixture", format:"modern",
                deckFormat:"custom", rulesMode:"manual", maxSeats:2, phase:"started", matchMode:"bo1",
                role:"player", seatIndex:0, host:true,
                seats:[{occupied:true, displayName:"Fixture player 0", host:true, ready:true, loaded:true},
                    {occupied:true, displayName:"Fixture player 1", ready:true, loaded:true}]}
            require(auditProbe.applyRulesTableFixture(room,
                {roomId:"HAND01", gameId:"manual-hand-fixture", players:[], zones:[], stack:[]}, snapshot),
                "Cannot apply manual table fixture")
            auditProbe.fixture("manual-hand-face-preview", {description:
                "Deterministic manual snapshot through real GameSession/GameTable models; not a live match", hand:hand})
            auditWindow.showTable()
        }, () => gameTable.hasSnapshot && gameTable.zoneModel(0, "hand").count === 1
            && !!find("handCard0", manualPage()))
        add("Hover the production manual hand card", () => {
            manualHandBefore = JSON.stringify(gameTable.zoneModel(0, "hand").get(0))
            manualCardBefore = JSON.stringify(gameTable.cardData("manual-preview-hand"))
            hover("handCard0", manualPage())
        }, () => artReady(manualPreview(), "Delver of Secrets", "cardHoverPreviewArt"))
        add("Read both manual hand faces without flipping or moving the card", () => {
            require(manualPage().presentation.previewSourceActive, "The manual hand source must remain hovered")
        }, () => waited(550) && bothReady(manualPreview(), ["Delver of Secrets", "Insectile Aberration"], "cardHoverPreviewArt"))
        add("Capture the unchanged manual hand and leave its preview", () => {
            unchangedManualHand()
            capture("manual-hand-both-faces")
            hover("tableSettingsButton", manualPage())
        }, () => !manualPreview().visible)
        add("Verify both hand inspections stayed local", () => unchangedManualHand())
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
