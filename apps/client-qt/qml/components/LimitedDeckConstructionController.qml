// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "TournamentLobby"

import QtQuick

// Local construction state only. Authoritative pool/submission data arrive via
// limitedModel; transport, popups, filters and scroll position belong to the view.
QtObject {
    id: root
    required property var limitedModel
    required property var cardCatalogModel
    property var draftStore: null
    property string draftServer: ""
    property string participantId: ""
    property bool cubeFreePlay: false
    property bool localPractice: false
    property bool active: true
    signal mutationStarted(bool hidePreview)
    signal submissionRequested(var ids, var lands, var commanders, var colors)

    readonly property bool constructionDraftStage: limitedModel.stage === "deck_building"
        || (cubeFreePlay && (limitedModel.eventType === "cube_draft"
            || limitedModel.eventType === "commander_cube") && limitedModel.stage === "competition")
    readonly property string draftEventId: limitedModel.tournamentId || ""
    readonly property string draftIdentity: draftServer && draftEventId && participantId
        ? JSON.stringify([draftServer, draftEventId, participantId]) : ""
    property string restoredDraftIdentity: ""
    property var selectedCards: ({})
    property var commanderInstanceIds: []
    property var commanderColors: []
    property int selectionRevision: 0
    property var basics: ({"Plains": 0, "Island": 0, "Swamp": 0,
                           "Mountain": 0, "Forest": 0})
    property int basicsRevision: 0
    property var basicPrintings: ({})
    property var defaultBasicPrintings: ({})
    property string basicPrintingCatalogIdentity: ""
    property bool sealedOpeningSeen: false
    property bool autoBasicLands: true
    property bool constructionReady: false
    property bool restoredSubmittedDeck: false
    property string firstSubmissionFingerprint: ""
    property int metadataRevision: 0
    property bool initialPoolChosen: false
    readonly property bool commanderDraft: limitedModel.eventType === "commander_cube"
    readonly property int minimumDeckCards: Number(limitedModel.minimumDeckCards) > 0
        ? Number(limitedModel.minimumDeckCards) : commanderDraft ? 60 : 40
    readonly property bool draftEvent: limitedModel.eventType === "set_draft" || limitedModel.eventType === "cube_draft" || commanderDraft
    readonly property var basicNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"]
    readonly property var enrichedPool: enrichPoolCards()
    readonly property int selectedPoolCount: countSelected()
    readonly property var optionalCards: {
        void metadataRevision
        if (!commanderDraft) return []
        const cards = limitedModel.optionalCards || []
        return cardCatalogModel && typeof cardCatalogModel.enrichLimitedCards === "function"
            ? cardCatalogModel.enrichLimitedCards(cards) : cards
    }
    readonly property var selectedOptionalCards: {
        void selectionRevision
        return optionalCards.filter(card => !!selectedCards[card.instanceId])
    }
    readonly property var fallbackCommanders: {
        void metadataRevision
        if (!commanderDraft) return []
        const cards = limitedModel.fallbackCommanders || []
        const enriched = cardCatalogModel && typeof cardCatalogModel.enrichLimitedCards === "function"
            ? cardCatalogModel.enrichLimitedCards(cards) : cards
        return enriched.map(card => Object.assign({}, commanderSelection.withColor(card, commanderColors), {fallbackCommander: true}))
    }
    readonly property var selectedFallbackCommanders: fallbackCommanders.filter(card => commanderInstanceIds.indexOf(card.instanceId) >= 0)
    readonly property int selectedCount: selectedPoolCount + selectedFallbackCommanders.length + countBasics()
    readonly property bool hasUnsubmittedChanges: submissionDiffers()
    readonly property var participatingPlayers: (limitedModel.participants || []).filter(player => !player.withdrawn)
    readonly property bool automaticTableAfterSubmission: cubeFreePlay && limitedModel.stage === "deck_building"
        && (limitedModel.eventType === "cube_draft" || commanderDraft)
        && participatingPlayers.length >= 2 && participatingPlayers.length <= (commanderDraft ? 8 : 2)
        && participatingPlayers.some(player => player.participantId === participantId)
    readonly property var mainDeckCards: cardsForSelection(true).concat(selectedOptionalCards, selectedFallbackCommanders)
        .map(card => commanderSelection.withColor(card, commanderColors))
    readonly property var basicLandPlan: landPlanner.recommend(mainDeckCards, minimumDeckCards)
    readonly property var landAssessment: landPlanner.analyze(mainDeckCards, basics, minimumDeckCards)
    readonly property string landWarning: landAssessment.lowLandCount
        ? qsTranslate("TournamentLobby", "%1 lands in %2 cards. Consider at least %3 lands; this is a reminder, not a submission restriction.")
            .arg(landAssessment.landCount).arg(landAssessment.totalCards).arg(landAssessment.minimumSuggestedLands)
        : ""
    readonly property var commanderCards: mainDeckCards.filter(card => commanderInstanceIds.indexOf(card.instanceId) >= 0)
    readonly property bool commandersValid: !commanderDraft || (commanderInstanceIds.length > 0
        && commanderSelection.sanitize(commanderInstanceIds, commanderCandidates()).length === commanderInstanceIds.length
        && commanderSelection.colorsValid(commanderColors, commanderInstanceIds, commanderCandidates()))
    readonly property var commanderAdvice: commanderDraft
        ? commanderSelection.advisory(mainDeckCards, commanderInstanceIds, basics, commanderColors) : []
    readonly property var commanderGuidance: commanderAdvice.concat(commanderDraft
        && !commanderSelection.colorsValid(commanderColors, commanderInstanceIds, commanderCandidates())
        ? [qsTranslate("TournamentLobby", "Choose a color for each selected Piper before submitting.")] : [])
    readonly property var sideboardCards: cardsForSelection(false)
    readonly property int selectedLandCount: landAssessment.landCount
    readonly property int selectedNonlandCount: selectedCount - selectedLandCount

    readonly property LimitedBasicLandPlan landPlanner: LimitedBasicLandPlan {}
    readonly property LimitedCommanderSelection commanderSelection: LimitedCommanderSelection {}
    readonly property Connections snapshotConnection: Connections {
        target: root.limitedModel
        ignoreUnknownSignals: true
        function onSnapshotChanged() {
            root.refreshBasicPrintings()
            root.restoreConstruction()
            root.restoreSubmission()
        }
    }
    readonly property Connections catalogConnection: Connections {
        target: root.cardCatalogModel
        ignoreUnknownSignals: true
        function onCatalogChanged() {
            root.metadataRevision++
            root.refreshBasicPrintings()
        }
        function onLanguageChanged() {
            root.metadataRevision++
            root.refreshBasicPrintings()
        }
    }
    Component.onCompleted: {
        refreshBasicPrintings()
        restoreConstruction()
        restoreSubmission()
        constructionReady = true
        updateAutoBasics()
    }
    onMainDeckCardsChanged: Qt.callLater(updateAutoBasics)
    onMinimumDeckCardsChanged: Qt.callLater(updateAutoBasics)
    onDraftIdentityChanged: Qt.callLater(restoreConstruction)
    onActiveChanged: if (active) refreshBasicPrintings()

    function cardSelected(instanceId) {
        const revision = selectionRevision
        return !!selectedCards[instanceId] || revision < 0
    }

    function cardsForSelection(wantSelected) {
        const revision = selectionRevision
        const result = []
        for (let index = 0; index < enrichedPool.length; ++index) {
            const card = enrichedPool[index]
            if (!!selectedCards[card.instanceId] === wantSelected)
                result.push(card)
        }
        // Each visible view owns its sorting. Gallery grouping must not
        // invalidate the selected deck, mana plan or compact-list delegates.
        return revision < 0 ? [] : result
    }

    function enrichPoolCards() {
        const revision = metadataRevision
        if (!active) return []
        const pool = limitedModel.pool || []
        if (cardCatalogModel
                && typeof cardCatalogModel.enrichLimitedCards === "function") {
            const enriched = cardCatalogModel.enrichLimitedCards(pool)
            return revision < 0 ? [] : enriched
        }
        return revision < 0 ? [] : pool
    }

    function moveToMainDeck(instanceId) {
        if (!(limitedModel.pool || []).concat(optionalCards).some(card => card.instanceId === instanceId)) return
        mutationStarted(true)
        const changed = Object.assign({}, selectedCards)
        changed[instanceId] = true
        selectedCards = changed
        selectionRevision++
        updateAutoBasics()
        saveConstruction()
    }

    function removeFromMainDeck(card) {
        if (card.virtualBasic) adjustBasic(card.name, -1)
        else moveToSideboard(card.instanceId)
    }

    function chooseInitialPool(keepPicks) {
        if (initialPoolChosen || limitedModel.deckSubmitted) return
        const chosen = {}
        if (keepPicks) {
            for (const card of limitedModel.pool) chosen[card.instanceId] = true
        }
        selectedCards = chosen
        selectionRevision++
        initialPoolChosen = true
        updateAutoBasics()
        saveConstruction()
    }

    function moveToSideboard(instanceId) {
        mutationStarted(true)
        const changed = Object.assign({}, selectedCards)
        delete changed[instanceId]
        selectedCards = changed
        commanderInstanceIds = commanderInstanceIds.filter(id => id !== instanceId)
        commanderColors = commanderColors.filter(choice => choice.instanceId !== instanceId)
        selectionRevision++
        updateAutoBasics()
        saveConstruction()
    }

    function selectedPhysicalCards() {
        void selectionRevision
        return (limitedModel.pool || []).filter(card => !!selectedCards[card.instanceId])
    }

    function commanderCandidates() {
        return selectedPhysicalCards().concat(fallbackCommanders)
    }

    function toggleCommander(instanceId) {
        if (!commanderDraft) return
        const cards = enrichedPool.concat(fallbackCommanders)
        if (!commanderSelection.canSelect(instanceId, commanderInstanceIds, cards)) return
        mutationStarted(true)
        // Selecting a drafted commander also includes that physical instance in
        // the deck; the server still validates commanders against the mainboard.
        if (commanderInstanceIds.indexOf(instanceId) < 0 && !selectedCards[instanceId]
                && enrichedPool.some(card => card.instanceId === instanceId)) {
            selectedCards = Object.assign({}, selectedCards, {[instanceId]: true})
            selectionRevision++
        }
        commanderInstanceIds = commanderInstanceIds.indexOf(instanceId) >= 0
            ? commanderInstanceIds.filter(id => id !== instanceId)
            : commanderInstanceIds.concat([instanceId])
        commanderColors = commanderSelection.sanitizeColors(commanderColors, commanderInstanceIds, cards)
        updateAutoBasics()
        saveConstruction()
    }

    function setCommanderColor(instanceId, color) {
        const card = commanderCandidates().find(candidate => candidate.instanceId === instanceId)
        if (!commanderDraft || commanderInstanceIds.indexOf(instanceId) < 0 || !card
                || !commanderSelection.isPiper(card) || !/^[WUBRG]$/.test(color)) return
        commanderColors = commanderSelection.sanitizeColors(
            commanderColors.filter(choice => choice.instanceId !== instanceId).concat([{instanceId: instanceId, color: color}]),
            commanderInstanceIds, commanderCandidates())
        saveConstruction()
    }

    function countSelected() {
        const revision = selectionRevision
        return Object.keys(selectedCards).length + (revision < 0 ? 0 : 0)
    }

    function basicValue(name) {
        const revision = basicsRevision
        return Number(basics[name] || 0) + (revision < 0 ? 0 : 0)
    }

    function countBasics() {
        let total = 0
        for (let index = 0; index < basicNames.length; ++index)
            total += basicValue(basicNames[index])
        return total
    }

    function adjustBasic(name, amount) {
        mutationStarted(false)
        autoBasicLands = false
        const changed = Object.assign({}, basics)
        changed[name] = Math.max(0, Number(changed[name] || 0) + amount)
        basics = changed
        basicsRevision++
        saveConstruction()
    }

    function setAutoBasicLands(enabled) {
        autoBasicLands = enabled
        updateAutoBasics()
        saveConstruction()
    }

    function updateAutoBasics() {
        if (!constructionReady || !active || !autoBasicLands) return
        const proposed = basicLandPlan.basics
        if (basicNames.every(name => basicValue(name) === proposed[name])) return
        mutationStarted(false)
        basics = Object.assign({}, proposed)
        basicsRevision++
        saveConstruction()
    }

    function submit() {
        updateAutoBasics()
        if (commanderDraft && (!commandersValid || selectedCount < minimumDeckCards)) return
        const ids = Object.keys(selectedCards)
        const lands = []
        for (let index = 0; index < basicNames.length; ++index) {
            const count = basicValue(basicNames[index])
            if (count > 0)
                lands.push(Object.assign({"name": basicNames[index], "count": count}, basicPrinting(basicNames[index])))
        }
        // Keep the earliest in-flight baseline: more edits/submissions may precede its reply.
        if (!limitedModel.deckSubmitted && !firstSubmissionFingerprint)
            firstSubmissionFingerprint = selectionFingerprint()
        submissionRequested(ids, lands, commanderInstanceIds, commanderColors)
    }

    function submissionProgress() {
        let submitted = 0
        let active = 0
        for (let index = 0; index < limitedModel.participants.length; ++index) {
            if (limitedModel.participants[index].withdrawn) continue
            active++
            if (limitedModel.participants[index].deckSubmitted)
                submitted++
        }
        return submitted + " / " + active
    }

    function saveConstruction() {
        if (!draftStore || !draftIdentity || (limitedModel.deckSubmitted && !localPractice)
                || !constructionDraftStage) return
        const savedPrintings = Object.assign({}, basicPrintings)
        for (const name of basicNames) {
            if (basicValue(name) > 0 && basicPrinting(name).setCode)
                savedPrintings[name] = basicPrinting(name)
        }
        draftStore.saveDraft(draftServer, draftEventId, participantId, {
            mainboardInstanceIds: Object.keys(selectedCards),
            commanderInstanceIds: commanderInstanceIds,
            commanderColors: commanderColors,
            basics: basics, basicPrintings: savedPrintings, initialPoolChosen: initialPoolChosen,
            autoBasicLands: autoBasicLands, sealedOpeningSeen: sealedOpeningSeen
        })
    }

    function restoreConstruction() {
        // A sitting-out Cube player can build their first deck after the rest
        // of the room enters free play. Keep that local draft recoverable too.
        if (!draftStore || !draftIdentity || !constructionDraftStage
                || restoredDraftIdentity === draftIdentity) return
        if (restoredDraftIdentity && restoredDraftIdentity !== draftIdentity) {
            selectedCards = ({})
            commanderInstanceIds = []
            commanderColors = []
            basics = ({"Plains": 0, "Island": 0, "Swamp": 0, "Mountain": 0, "Forest": 0})
            initialPoolChosen = false
            basicPrintings = ({})
            sealedOpeningSeen = false
            autoBasicLands = true
            restoredSubmittedDeck = false
            firstSubmissionFingerprint = ""
            selectionRevision++
            basicsRevision++
        }
        restoredDraftIdentity = draftIdentity
        if (limitedModel.deckSubmitted && !localPractice) return
        const draft = draftStore.loadDraft(draftServer, draftEventId, participantId)
        // QVariantList is a QML sequence, not a JavaScript Array.
        sealedOpeningSeen = draft.sealedOpeningSeen === true
        basicPrintings = sanitizeBasicPrintings(draft.basicPrintings || {})
        const ids = draft.mainboardInstanceIds
        if (!ids || typeof ids === "string" || typeof ids.length !== "number") return
        // Existing manual drafts never opt in merely because the client updated.
        autoBasicLands = draft.autoBasicLands === true
        const available = new Set((limitedModel.pool || []).concat(optionalCards).map(card => card.instanceId))
        const restored = {}
        for (const id of ids) if (available.has(id)) restored[id] = true
        const lands = {}
        for (const name of basicNames) {
            const value = Number((draft.basics || {})[name] || 0)
            lands[name] = Number.isFinite(value) ? Math.max(0, Math.min(1000, Math.floor(value))) : 0
        }
        selectedCards = restored
        commanderInstanceIds = commanderDraft
            ? commanderSelection.sanitize(draft.commanderInstanceIds, commanderCandidates()) : []
        commanderColors = commanderSelection.sanitizeColors(draft.commanderColors, commanderInstanceIds, commanderCandidates())
        basics = lands
        initialPoolChosen = draft.initialPoolChosen === true
        if (localPractice && limitedModel.deckSubmitted)
            restoredSubmittedDeck = true
        selectionRevision++
        basicsRevision++
    }

    function submissionDiffers() {
        if (!constructionReady) return false
        void selectionRevision
        void basicsRevision
        if (!limitedModel.deckSubmitted)
            return selectedCount > 0
        const submittedIds = []
        for (const id of limitedModel.mainboardInstanceIds || []) submittedIds.push(id)
        const selectedIds = Object.keys(selectedCards).sort()
        submittedIds.sort()
        if (JSON.stringify(selectedIds) !== JSON.stringify(submittedIds)) return true
        if (commanderDraft) {
            const submittedCommanders = []
            for (const id of limitedModel.commanderInstanceIds || []) submittedCommanders.push(id)
            if (JSON.stringify(commanderInstanceIds.slice().sort()) !== JSON.stringify(submittedCommanders.sort())) return true
            const submittedColors = commanderSelection.sanitizeColors(limitedModel.commanderColors, submittedCommanders, commanderCandidates())
            if (JSON.stringify(commanderColors) !== JSON.stringify(submittedColors)) return true
        }
        const submittedBasics = {}
        for (const land of limitedModel.basicLands || [])
            submittedBasics[land.name] = land
        for (const name of basicNames) {
            const submitted = submittedBasics[name] || {}
            if (basicValue(name) !== Number(submitted.count || 0)) return true
            if (basicValue(name) > 0 && printingIdentity(basicPrinting(name)) !== printingIdentity(submitted)) return true
        }
        return false
    }

    function selectionFingerprint() {
        return JSON.stringify([
            Object.keys(selectedCards).sort(),
            commanderDraft ? commanderInstanceIds.slice().sort() : [],
            commanderDraft ? commanderColors : [],
            basicNames.map(name => [basicValue(name), printingIdentity(basicPrinting(name))])
        ])
    }

    function discardUnsubmittedChanges() {
        if (limitedModel.deckSubmitted) {
            restoreSubmission(true)
            return
        }
        autoBasicLands = false
        firstSubmissionFingerprint = ""
        selectedCards = ({})
        commanderInstanceIds = []
        commanderColors = []
        basics = ({"Plains": 0, "Island": 0, "Swamp": 0, "Mountain": 0, "Forest": 0})
        basicPrintings = ({})
        initialPoolChosen = false
        selectionRevision++
        basicsRevision++
        if (draftStore && draftIdentity)
            draftStore.removeDraft(draftServer, draftEventId, participantId)
    }

    function restoreSubmission(force = false) {
        if (!limitedModel.deckSubmitted)
            return
        if (!force && !restoredSubmittedDeck && firstSubmissionFingerprint
                && selectionFingerprint() !== firstSubmissionFingerprint && submissionDiffers()) {
            // This first acknowledgement confirms an older local submission, not
            // permission to overwrite edits made while it was in flight.
            restoredSubmittedDeck = true
            firstSubmissionFingerprint = ""
            return
        }
        if (!force && restoredSubmittedDeck) {
            if (!submissionDiffers() && draftStore && draftIdentity)
                draftStore.removeDraft(draftServer, draftEventId, participantId)
            return
        }
        autoBasicLands = false
        const restoredCards = {}
        for (let index = 0;
                index < limitedModel.mainboardInstanceIds.length; ++index) {
            restoredCards[limitedModel.mainboardInstanceIds[index]] = true
        }
        const restoredBasics = {"Plains": 0, "Island": 0, "Swamp": 0,
                                "Mountain": 0, "Forest": 0}
        const restoredPrintings = {}
        for (let index = 0; index < limitedModel.basicLands.length; ++index) {
            const land = limitedModel.basicLands[index]
            if (restoredBasics[land.name] !== undefined) {
                restoredBasics[land.name] = Number(land.count || 0)
                restoredPrintings[land.name] = land
            }
        }
        selectedCards = restoredCards
        commanderInstanceIds = commanderDraft
            ? commanderSelection.sanitize(limitedModel.commanderInstanceIds, commanderCandidates()) : []
        commanderColors = commanderSelection.sanitizeColors(limitedModel.commanderColors, commanderInstanceIds, commanderCandidates())
        basics = restoredBasics
        basicPrintings = sanitizeBasicPrintings(restoredPrintings)
        sealedOpeningSeen = true
        selectionRevision++
        basicsRevision++
        restoredSubmittedDeck = true
        firstSubmissionFingerprint = ""
        if (draftStore && draftIdentity)
            draftStore.removeDraft(draftServer, draftEventId, participantId)
    }

    function refreshBasicPrintings() {
        if (!active) return
        const identity = JSON.stringify([metadataRevision, (limitedModel.product || {}).setCode || ""])
        if (identity === basicPrintingCatalogIdentity) return
        basicPrintingCatalogIdentity = identity
        defaultBasicPrintings = resolveBasicPrintings()
    }

    function resolveBasicPrintings() {
        if (!cardCatalogModel || typeof cardCatalogModel.printings !== "function") return ({})
        const preferred = String((limitedModel.product || {}).setCode || "").toUpperCase()
        const options = {}
        let sharedSets = null
        for (const name of basicNames) {
            options[name] = cardCatalogModel.printings(name).filter(card => card.setCode && card.collectorNumber)
            const sets = new Set(options[name].map(card => String(card.setCode).toUpperCase()))
            sharedSets = sharedSets === null ? Array.from(sets) : sharedSets.filter(set => sets.has(set))
        }
        const fallback = (sharedSets || []).sort()[0] || ""
        const result = {}
        for (const name of basicNames) {
            const choices = options[name]
            const chosen = choices.find(card => String(card.setCode).toUpperCase() === preferred)
                || choices.find(card => String(card.setCode).toUpperCase() === fallback) || choices[0]
            if (chosen) result[name] = {setCode: String(chosen.setCode).toUpperCase(), collectorNumber: String(chosen.collectorNumber)}
        }
        return result
    }

    function basicPrinting(name) {
        return basicPrintings[name] !== undefined ? basicPrintings[name] : defaultBasicPrintings[name] || ({})
    }

    function printingIdentity(printing) {
        return JSON.stringify([String(printing.setCode || "").toUpperCase(), String(printing.collectorNumber || "")])
    }

    function sanitizeBasicPrintings(values) {
        const result = {}
        for (const name of basicNames) {
            if (values[name] === undefined) continue
            const value = values[name] || {}
            const set = String(value.setCode || "").trim().toUpperCase()
            const collector = String(value.collectorNumber || "").trim()
            if (set && collector && set.length <= 16 && collector.length <= 32)
                result[name] = {setCode: set, collectorNumber: collector}
            else if (!set && !collector) result[name] = {}
        }
        return result
    }

    function setBasicPrinting(name, printing) {
        if (basicNames.indexOf(name) < 0) return
        const values = sanitizeBasicPrintings({[name]: printing})
        if (!values[name] || !values[name].setCode) return
        mutationStarted(false)
        basicPrintings = Object.assign({}, basicPrintings, values)
        if (cardCatalogModel && typeof cardCatalogModel.cacheCardsIncrementally === "function")
            cardCatalogModel.cacheCardsIncrementally([Object.assign({name: name}, values[name])])
        saveConstruction()
    }
}
