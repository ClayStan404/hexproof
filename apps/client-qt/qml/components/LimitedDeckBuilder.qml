// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "TournamentLobby"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    required property var limitedModel
    required property var wsModel
    required property var cardCatalogModel
    property var draftStore: typeof limitedDeckDrafts !== "undefined" ? limitedDeckDrafts : null
    property string participantId: ""
    property bool cubeFreePlay: false
    readonly property bool constructionDraftStage: limitedModel.stage === "deck_building"
        || (cubeFreePlay && (limitedModel.eventType === "cube_draft"
            || limitedModel.eventType === "commander_cube") && limitedModel.stage === "competition")
    readonly property string draftServer: wsModel.serverUrl || ""
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
    property var pendingScrollPositions: null
    property bool sealedOpeningSeen: false
    property bool animatePackOpenings: typeof preferences !== "undefined" && preferences.animatePackOpenings
    property bool autoBasicLands: true
    property bool constructionReady: false
    property bool restoredSubmittedDeck: false
    property string firstSubmissionFingerprint: ""
    property int groupingModeIndex: 0
    property int metadataRevision: 0
    property var cachedArtKeys: ({})
    property bool basicLandsExpanded: false
    property bool initialPoolChosen: false
    readonly property bool commanderDraft: limitedModel.eventType === "commander_cube"
    readonly property int minimumDeckCards: Number(limitedModel.minimumDeckCards) > 0
        ? Number(limitedModel.minimumDeckCards) : commanderDraft ? 60 : 40
    readonly property bool draftEvent: limitedModel.eventType === "set_draft" || limitedModel.eventType === "cube_draft" || commanderDraft
    property alias filters: poolFilters
    property alias mainFilters: deckFilters
    property alias inspectedCard: preview.card
    property alias hoverPreviewVisible: preview.visible
    readonly property var basicNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"]
    readonly property var groupingModes: ["mana", "color", "type", "name"]
    readonly property var groupingOptions: [qsTranslate("TournamentLobby", "Mana value"), qsTranslate("TournamentLobby", "Color"), qsTranslate("TournamentLobby", "Card type"), qsTranslate("TournamentLobby", "Name")]
    readonly property string groupingMode: groupingModes[groupingModeIndex]
    readonly property bool filtersActive: poolFilters.active
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
    readonly property var visibleSideboardCards: poolFilters.filter(sideboardCards)
    readonly property var sideboardGroups: grouping.groupCards(visibleSideboardCards)
    readonly property int selectedLandCount: landAssessment.landCount
    readonly property int selectedNonlandCount: selectedCount - selectedLandCount
    readonly property bool compactColumns: width < Theme.size(660)
    property int compactPaneIndex: 0
    readonly property bool compactDeckControls: compactColumns || height < Theme.size(440)
    readonly property var deckListCards: {
        const result = mainDeckCards.slice()
        for (const name of basicNames) {
            const count = basicValue(name)
            if (count > 0) result.push({name: name, displayName: basicLabel(name), count: count,
                                       typeLine: "Basic Land", cardColors: "", colors: "WUBRG"[basicNames.indexOf(name)], manaCost: "",
                                       manaValue: 0, virtualBasic: true,
                                       setCode: basicPrinting(name).setCode || "",
                                       collectorNumber: basicPrinting(name).collectorNumber || ""})
        }
        return result
    }
    readonly property var visibleDeckListCards: deckFilters.filter(deckListCards)
    CardFilterState { id: poolFilters }
    CardFilterState { id: deckFilters }
    LimitedBasicLandPlan { id: landPlanner }
    LimitedCommanderSelection { id: commanderSelection }

    Component.onCompleted: {
        refreshBasicPrintings()
        restoreConstruction()
        restoreSubmission()
        constructionReady = true
        updateAutoBasics()
        cachePoolCards()
        Qt.callLater(maybeOpenSealedPacks)
    }

    onMainDeckCardsChanged: Qt.callLater(updateAutoBasics)
    onMinimumDeckCardsChanged: Qt.callLater(updateAutoBasics)

    Connections {
        target: root.limitedModel
        ignoreUnknownSignals: true
        function onSnapshotChanged() {
            root.refreshBasicPrintings()
            root.restoreConstruction()
            root.restoreSubmission()
            Qt.callLater(root.maybeOpenSealedPacks)
        }
    }

    onDraftIdentityChanged: Qt.callLater(restoreConstruction)

    Connections {
        target: root.cardCatalogModel
        ignoreUnknownSignals: true
        function onCatalogChanged() {
            root.metadataRevision++
            root.refreshBasicPrintings()
        }
        function onLanguageChanged() {
            root.cachedArtKeys = ({})
            root.metadataRevision++
            root.refreshBasicPrintings()
        }
    }

    LimitedCardGrouping {
        id: grouping
        mode: root.groupingMode
    }

    implicitWidth: Theme.size(1100)
    implicitHeight: Theme.size(650)
    Layout.minimumWidth: 0
    Layout.minimumHeight: 0

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.size(8)
        SegmentedControl {
            objectName: "limitedWorkspaceTabs"
            Layout.fillWidth: true
            visible: root.compactColumns
            implicitHeight: Theme.size(34)
            options: [qsTranslate("TournamentLobby", "Pool · %1").arg(root.sideboardCards.length),
                      qsTranslate("TournamentLobby", "Main deck · %1").arg(root.selectedCount)]
            currentIndex: root.compactPaneIndex
            onActivated: index => root.compactPaneIndex = index
        }
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            columns: root.compactColumns ? 1 : 2
            columnSpacing: Theme.size(16)
            rowSpacing: Theme.size(10)
            ColumnLayout {
                objectName: "limitedSideboardSurface"
                visible: !root.compactColumns || root.compactPaneIndex === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                Layout.minimumHeight: 0
                CardFilterBar {
                    Layout.fillWidth: true
                    filters: poolFilters
                }
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: qsTranslate("TournamentLobby", "Sideboard / available pool") + " · " + root.visibleSideboardCards.length
                        color: Theme.textSecondary
                        elide: Text.ElideRight
                    }
                    AppButton {
                        objectName: "limitedSealedPacksButton"
                        compact: true
                        visible: root.limitedModel.eventType === "set_sealed"
                        text: qsTranslate("TournamentLobby", "View opened packs")
                        onClicked: root.showSealedPacks()
                    }
                    AppComboBox {
                        objectName: "limitedGroupingControl"
                        Layout.preferredWidth: Theme.size(136)
                        implicitHeight: Theme.size(34)
                        model: root.groupingOptions
                        currentIndex: root.groupingModeIndex
                        onActivated: index => root.groupingModeIndex = index
                    }
                }
                CardArtGrid {
                    id: availablePool
                    objectName: "limitedSideboardGrid"
                    cardObjectPrefix: "limitedCardTile-"
                    preferredCardWidth: Math.max(Theme.size(150),
                        Math.min(Theme.size(230), width / 5 - Theme.size(16)))
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 0
                    cards: root.sideboardGroups.reduce((cards, group) => cards.concat(group.cards), [])
                    catalogModel: root.cardCatalogModel
                    emptyText: root.filtersActive ? qsTranslate("TournamentLobby", "No cards match all active filters.")
                                                 : qsTranslate("TournamentLobby", "All pool cards are in your main deck.")
                    onCardActivated: card => root.moveToMainDeck(card.instanceId)
                    onCardInspected: (card, item) => root.inspectCard(card, item)
                    onCardInspectionEnded: item => root.hideCardPreview(item)
                    onMovingChanged: if (moving) root.hideCardPreview()
                }
            }
            Surface {
                objectName: "limitedMainDeckSurface"
                visible: !root.compactColumns || root.compactPaneIndex === 1
                Layout.fillWidth: root.compactColumns
                Layout.preferredWidth: Theme.size(320)
                Layout.maximumWidth: root.compactColumns ? root.width : Theme.size(350)
                Layout.minimumWidth: 0
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                color: Theme.surfaceMuted
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.size(root.compactDeckControls ? 8 : 12)
                    spacing: Theme.size(root.compactDeckControls ? 4 : 8)
                    InfoBanner {
                        Layout.fillWidth: true
                        tone: "warning"
                        message: root.draftStore && root.draftStore.lastError
                            ? qsTranslate("TournamentLobby", "Local deck draft storage is unavailable. Keep this view open until you submit.") : ""
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        ColumnLayout {
                            Layout.fillWidth: true
                            Text {
                                textFormat: Text.PlainText
                                visible: !root.compactDeckControls
                                text: qsTranslate("TournamentLobby", "Main deck")
                                font.pixelSize: Theme.fontSize(21)
                                font.bold: true
                                color: Theme.text
                            }
                            Text {
                                textFormat: Text.PlainText
                                objectName: "limitedMainDeckCount"
                                text: root.selectedCount + " / " + root.minimumDeckCards
                                font.pixelSize: Theme.fontSize(16)
                                color: root.selectedCount >= root.minimumDeckCards ? Theme.success : Theme.warning
                            }
                        }
                        CardManaCurve {
                            cards: root.mainDeckCards
                            Layout.preferredHeight: Theme.size(root.compactDeckControls ? 30 : 42)
                        }
                    }
                    Text {
                        textFormat: Text.PlainText
                        visible: !root.compactDeckControls
                        Layout.fillWidth: true
                        text: qsTranslate("TournamentLobby", "%1 cards · %2 lands · %3 nonlands").arg(root.selectedCount)
                                  .arg(root.selectedLandCount).arg(root.selectedNonlandCount)
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(10)
                        wrapMode: Text.WordWrap
                    }
                    CardFilterBar {
                        objectName: "limitedMainDeckFilters"
                        Layout.fillWidth: true
                        filters: deckFilters
                        compact: root.compactDeckControls
                    }
                    CompactCardList {
                        id: mainDeckList
                        objectName: "limitedMainDeckGrid"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: Theme.size(root.compactDeckControls ? 44 : 64)
                        cards: root.visibleDeckListCards
                        dropTarget: root.compactColumns ? null : availablePool
                        onCardDropped: card => root.removeFromMainDeck(card)
                        emptyText: deckFilters.active
                            ? qsTranslate("TournamentLobby", "No cards match all active filters.")
                            : qsTranslate("TournamentLobby", "Add cards from the sideboard to build your deck.")
                        onCardActivated: card => {
                            root.removeFromMainDeck(card)
                        }
                        onCardInspected: (card, item) => root.inspectCard(card, item)
                        onCardInspectionEnded: item => root.hideCardPreview(item)
                        onMovingChanged: if (moving) root.hideCardPreview()
                    }
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        visible: root.compactColumns
                        text: qsTranslate("TournamentLobby", "Click a card to return it to the pool.")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(10)
                        elide: Text.ElideRight
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: root.compactDeckControls ? 2 : 1
                        columnSpacing: Theme.size(8)
                        rowSpacing: Theme.size(8)
                        AppButton {
                            objectName: "limitedCommandersButton"
                            Layout.fillWidth: true
                            visible: root.commanderDraft
                            compact: true
                            text: qsTranslate("TournamentLobby", "Commanders · %1 / 2").arg(root.commanderInstanceIds.length)
                                + (root.commanderGuidance.length ? " ⚠" : "")
                            ToolTip.visible: hovered && root.commanderGuidance.length > 0
                            ToolTip.text: root.commanderGuidance.join("\n")
                            Accessible.description: root.commanderGuidance.join("\n")
                            onClicked: commanderPicker.open()
                        }
                        Text {
                            textFormat: Text.PlainText
                            objectName: "limitedCommanderSummary"
                            Layout.fillWidth: true
                            visible: root.commanderDraft && !root.compactDeckControls
                            text: root.commanderCards.length > 0
                                ? root.commanderCards.map(card => (card.displayName || card.name)
                                    + (card.commanderColor ? " · " + card.commanderColor : "")).join(" / ")
                                : qsTranslate("TournamentLobby", "Choose commanders from your drafted cards or use the Piper fallback.")
                            color: root.commandersValid ? Theme.textSecondary : Theme.warning
                            font.pixelSize: Theme.fontSize(10)
                            elide: Text.ElideRight
                        }
                        AppButton {
                            objectName: "limitedBasicLandsButton"
                            Layout.fillWidth: true
                            compact: true
                            text: (root.optionalCards.length > 0
                                ? qsTranslate("TournamentLobby", "Basic lands & optional cards")
                                : root.autoBasicLands
                                ? qsTranslate("TournamentLobby", "Basic lands · %1 · Auto").arg(root.countBasics())
                                : qsTranslate("TournamentLobby", "Basic lands · %1").arg(root.countBasics()))
                                + (root.landAssessment.lowLandCount ? " ⚠" : "")
                            ToolTip.visible: hovered && root.landWarning.length > 0
                            ToolTip.text: root.landWarning
                            Accessible.description: root.landWarning
                            onClicked: root.basicLandsExpanded = true
                        }
                    }
                    Text {
                        textFormat: Text.PlainText
                        objectName: "limitedAutoBasicLandsGuidance"
                        Layout.fillWidth: true
                        visible: root.autoBasicLands && root.selectedPoolCount > 0
                                 && root.basicLandPlan.needed > 0 && !root.basicLandPlan.hasColors
                        text: qsTranslate("TournamentLobby", "No colored mana requirements found. Choose basic lands manually.")
                        color: Theme.warning
                        font.pixelSize: Theme.fontSize(10)
                        wrapMode: Text.WordWrap
                    }
                    CardMetadataNotice {
                        Layout.fillWidth: true
                        cards: root.mainDeckCards
                    }
                    Text {
                        textFormat: Text.PlainText
                        objectName: "limitedAutomaticTableNotice"
                        Layout.fillWidth: true
                        visible: root.automaticTableAfterSubmission
                        text: qsTranslate("TournamentLobby", "When all participating players submit, the game room opens automatically.")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(10)
                        wrapMode: Text.WordWrap
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: root.compactDeckControls ? 2 : 1
                        columnSpacing: Theme.size(8)
                        rowSpacing: Theme.size(8)
                        Text {
                            textFormat: Text.PlainText
                            objectName: "limitedDeckSubmissionStatus"
                            Layout.fillWidth: true
                            text: root.limitedModel.deckSubmitted && root.hasUnsubmittedChanges
                                  ? qsTranslate("TournamentLobby", "Unsubmitted deck changes")
                                  : root.limitedModel.deckSubmitted && root.limitedModel.stage === "deck_building"
                                  ? qsTranslate("TournamentLobby", "Deck submitted · Waiting for participants: %1").arg(root.submissionProgress())
                                  : root.limitedModel.deckSubmitted ? qsTranslate("TournamentLobby", "Deck submitted")
                                  : qsTranslate("TournamentLobby", "Waiting for all participants: %1").arg(root.submissionProgress())
                            color: root.limitedModel.deckSubmitted && root.hasUnsubmittedChanges
                                   ? Theme.warning : root.limitedModel.deckSubmitted ? Theme.success : Theme.textMuted
                            font.pixelSize: Theme.fontSize(10)
                            wrapMode: Text.WordWrap
                        }
                        AppButton {
                            objectName: "limitedSubmitDeckButton"
                            Layout.fillWidth: true
                            compact: root.compactDeckControls
                            variant: "primary"
                            text: root.limitedModel.deckSubmitted ? qsTranslate("TournamentLobby", "Update deck") : qsTranslate("TournamentLobby", "Submit deck")
                            enabled: root.selectedCount >= root.minimumDeckCards && root.commandersValid
                                     && root.limitedModel.pool.length > 0
                                     && root.wsModel.connected !== false
                            onClicked: root.submit()
                        }
                    }
                }
            }
        }
    }
    Popup {
        id: startChoice
        objectName: "limitedDeckStartChoice"
        parent: Overlay.overlay
        visible: root.visible && root.draftEvent && root.limitedModel.stage === "deck_building"
                 && root.limitedModel.pool.length > 0 && !root.limitedModel.deckSubmitted && !root.initialPoolChosen
        width: Math.min(Theme.size(470), parent ? parent.width - Theme.size(24) : 470)
        height: Math.min(Theme.size(300), parent ? parent.height - Theme.size(24) : 300)
        x: parent ? (parent.width - width) / 2 : 0
        y: parent ? (parent.height - height) / 2 : 0
        modal: true
        focus: true
        closePolicy: Popup.NoAutoClose
        background: Surface { elevated: true }
        contentItem: ColumnLayout {
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTranslate("TournamentLobby", "Start deck building")
                color: Theme.text
                font.pixelSize: Theme.fontSize(21)
                font.bold: true
                wrapMode: Text.WordWrap
            }
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTranslate("TournamentLobby", "Keep all drafted cards in the main deck and remove unwanted cards, or start with an empty main deck.")
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
            }
            AppButton {
                objectName: "keepDraftedCardsButton"
                Layout.fillWidth: true
                variant: "primary"
                text: qsTranslate("TournamentLobby", "Keep drafted cards in main deck")
                onClicked: root.chooseInitialPool(true)
            }
            AppButton {
                objectName: "rebuildFromPoolButton"
                Layout.fillWidth: true
                text: qsTranslate("TournamentLobby", "Build again from the pool")
                onClicked: root.chooseInitialPool(false)
            }
        }
    }
    Popup {
        id: basicPopup
        objectName: "limitedBasicLandsPopup"
        parent: Overlay.overlay
        visible: root.basicLandsExpanded
        onClosed: root.basicLandsExpanded = false
        width: Math.min(Theme.size(460), parent ? parent.width - Theme.size(24) : 460)
        height: Math.min(Theme.size(620), parent ? parent.height - Theme.size(24) : 620)
        x: parent ? (parent.width - width) / 2 : 0
        y: parent ? (parent.height - height) / 2 : 0
        modal: true
        focus: true
        padding: Theme.size(16)
        background: Surface { elevated: true }
        contentItem: ColumnLayout {
            Text {
                textFormat: Text.PlainText
                text: root.optionalCards.length > 0
                    ? qsTranslate("TournamentLobby", "Basic lands & optional cards")
                    : qsTranslate("TournamentLobby", "Basic lands")
                color: Theme.text
                font.pixelSize: Theme.fontSize(20)
                font.bold: true
            }
            AppToggle {
                objectName: "limitedAutoBasicLandsControl"
                Layout.fillWidth: true
                text: qsTranslate("TournamentLobby", "Automatically add basic lands")
                checked: root.autoBasicLands
                onClicked: root.setAutoBasicLands(checked)
            }
            ScrollView {
                objectName: "limitedBasicLandScroll"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                contentWidth: availableWidth
                clip: true
                ColumnLayout {
                    width: parent.width
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: qsTranslate("TournamentLobby", "Fill to %1 cards using colored mana demand minus the sources supplied by selected lands. Flexible lands count as one shared source. Adjusting a basic land switches to manual mode.").arg(root.minimumDeckCards)
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(11)
                        wrapMode: Text.WordWrap
                    }
                    InfoBanner {
                        objectName: "limitedLowLandWarning"
                        Layout.fillWidth: true
                        tone: "warning"
                        message: root.landWarning
                    }
                    Text {
                        textFormat: Text.PlainText
                        objectName: "limitedUnknownManaSources"
                        Layout.fillWidth: true
                        visible: root.landAssessment.unknownSourceLandCount > 0
                        text: qsTranslate("TournamentLobby", "%1 selected lands have unresolved mana sources and are not used for color balancing. Review the mana base manually.").arg(root.landAssessment.unknownSourceLandCount)
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(11)
                        wrapMode: Text.WordWrap
                    }
                    Repeater {
                        model: root.basicNames
                        delegate: RowLayout {
                            id: basicRow
                            required property string modelData
                            Layout.fillWidth: true
                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: root.basicLabel(basicRow.modelData)
                                color: Theme.text
                            }
                            AppButton {
                                objectName: "limitedBasicLandPrinting-" + basicRow.modelData
                                compact: true
                                text: root.basicPrintingLabel(basicRow.modelData)
                                enabled: root.cardCatalogModel && typeof root.cardCatalogModel.printings === "function"
                                onClicked: basicPrintingPicker.showFor(Object.assign({name: basicRow.modelData},
                                    root.basicPrinting(basicRow.modelData)), false)
                            }
                            AppButton {
                                objectName: "limitedBasicLandRemove-" + basicRow.modelData
                                compact: true
                                implicitWidth: Theme.size(36)
                                text: "−"
                                enabled: root.basicValue(basicRow.modelData) > 0
                                onClicked: root.adjustBasic(basicRow.modelData, -1)
                            }
                            Text {
                                textFormat: Text.PlainText
                                text: root.basicValue(basicRow.modelData)
                                color: Theme.accent
                            }
                            AppButton {
                                objectName: "limitedBasicLandAdd-" + basicRow.modelData
                                compact: true
                                implicitWidth: Theme.size(36)
                                text: "+"
                                onClicked: root.adjustBasic(basicRow.modelData, 1)
                            }
                        }
                    }
                    ColumnLayout {
                        objectName: "limitedOptionalCardsPanel"
                        Layout.fillWidth: true
                        visible: root.optionalCards.length > 0
                        spacing: Theme.size(4)
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: qsTranslate("TournamentLobby", "Optional cards · one outside copy of each")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSize(12)
                            wrapMode: Text.WordWrap
                        }
                        Repeater {
                            model: root.optionalCards
                            delegate: RowLayout {
                                id: optionalRow
                                required property var modelData
                                Layout.fillWidth: true
                                Text {
                                    id: optionalName
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: optionalRow.modelData.displayName || optionalRow.modelData.name
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSize(13)
                                    elide: Text.ElideRight
                                    HoverHandler {
                                        onHoveredChanged: {
                                            if (hovered) root.inspectCard(optionalRow.modelData, optionalName)
                                            else root.hideCardPreview(optionalName)
                                        }
                                    }
                                }
                                AppButton {
                                    objectName: "limitedOptionalCard-" + optionalRow.modelData.instanceId
                                    compact: true
                                    text: root.cardSelected(optionalRow.modelData.instanceId)
                                        ? qsTranslate("TournamentLobby", "Remove") : qsTranslate("TournamentLobby", "Add")
                                    onClicked: {
                                        if (root.cardSelected(optionalRow.modelData.instanceId)) root.moveToSideboard(optionalRow.modelData.instanceId)
                                        else root.moveToMainDeck(optionalRow.modelData.instanceId)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            AppButton {
                objectName: "limitedBasicLandsDone"
                Layout.fillWidth: true
                text: qsTranslate("TournamentLobby", "Done")
                variant: "primary"
                onClicked: basicPopup.close()
            }
        }
    }
    PackOpeningOverlay {
        id: sealedPacksOverlay
        objectName: "limitedSealedPackOpening"
        cardCatalogModel: root.cardCatalogModel
    }
    PrintingPicker {
        id: basicPrintingPicker
        objectName: "limitedBasicPrintingPicker"
        catalogModel: root.cardCatalogModel
        onChosen: (printing, sideboard) => root.setBasicPrinting(cardName, printing)
    }
    CardHoverPreview {
        id: preview
        objectName: "limitedCardHoverPreview"
        artObjectName: "limitedCardHoverPreviewArt"
        catalogModel: root.cardCatalogModel
    }
    LimitedCommanderPicker {
        id: commanderPicker
        cards: root.enrichedPool
        fallbackCards: root.fallbackCommanders
        selectedIds: root.commanderInstanceIds
        selectedColors: root.commanderColors
        advice: root.commanderGuidance
        onToggleRequested: instanceId => root.toggleCommander(instanceId)
        onColorRequested: (instanceId, color) => root.setCommanderColor(instanceId, color)
        onCardInspected: (card, item) => root.inspectCard(card, item)
        onCardInspectionEnded: item => root.hideCardPreview(item)
        onClosed: root.hideCardPreview()
    }
    onVisibleChanged: {
        if (!visible) {
            hideCardPreview()
            basicLandsExpanded = false
            commanderPicker.close()
            basicPrintingPicker.close()
            sealedPacksOverlay.close()
        } else {
            refreshBasicPrintings()
            cachePoolCards()
            Qt.callLater(maybeOpenSealedPacks)
        }
    }
    onEnrichedPoolChanged: cachePoolCards()
    onFallbackCommandersChanged: cachePoolCards()
    onOptionalCardsChanged: cachePoolCards()
    onDefaultBasicPrintingsChanged: Qt.callLater(cachePoolCards)
    onBasicPrintingsChanged: Qt.callLater(cachePoolCards)

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
        if (!visible) return []
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
        preserveConstructionScroll()
        hideCardPreview()
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
        preserveConstructionScroll()
        hideCardPreview()
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
        preserveConstructionScroll()
        hideCardPreview()
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

    function basicLabel(name) {
        const labels = {
            "Plains": qsTranslate("TournamentLobby", "Plains"), "Island": qsTranslate("TournamentLobby", "Island"),
            "Swamp": qsTranslate("TournamentLobby", "Swamp"), "Mountain": qsTranslate("TournamentLobby", "Mountain"),
            "Forest": qsTranslate("TournamentLobby", "Forest")
        }
        return labels[name] || name
    }

    function adjustBasic(name, amount) {
        preserveConstructionScroll()
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
        if (!constructionReady || !visible || !autoBasicLands) return
        const proposed = basicLandPlan.basics
        if (basicNames.every(name => basicValue(name) === proposed[name])) return
        preserveConstructionScroll()
        basics = Object.assign({}, proposed)
        basicsRevision++
        saveConstruction()
    }

    function clearFilters() {
        poolFilters.reset()
        poolFilters.query = ""
        deckFilters.reset()
        deckFilters.query = ""
        hideCardPreview()
    }
    function inspectCard(card, item) { preview.inspect(card, item) }
    function hideCardPreview(item) { preview.hide(item) }

    function cachePoolCards() {
        if (!visible || !cardCatalogModel || typeof cardCatalogModel.cacheCardsIncrementally !== "function") return
        const basicCards = basicNames.map(name => Object.assign({name: name}, basicPrinting(name)))
            .filter(card => card.setCode && card.collectorNumber)
        const fresh = (limitedModel.pool || []).concat(fallbackCommanders, optionalCards, basicCards).filter(card => {
            const key = JSON.stringify([card.name, card.setCode || "", card.collectorNumber || ""])
            if (cachedArtKeys[key]) return false
            cachedArtKeys[key] = true
            return true
        })
        if (fresh.length) cardCatalogModel.cacheCardsIncrementally(fresh)
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
        if (commanderDraft)
            wsModel.submitLimitedCommanderDeck(qsTranslate("TournamentLobby", "Limited deck"), ids, lands, commanderInstanceIds, commanderColors)
        else
            wsModel.submitLimitedDeck(qsTranslate("TournamentLobby", "Limited deck"), ids, lands)
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
        if (!draftStore || !draftIdentity || limitedModel.deckSubmitted
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
        if (limitedModel.deckSubmitted) return
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
    function preserveConstructionScroll() {
        if (pendingScrollPositions) return
        pendingScrollPositions = [availablePool.contentY - availablePool.originY,
                                  mainDeckList.contentY - mainDeckList.originY]
        Qt.callLater(restoreConstructionScroll)
    }

    function restoreConstructionScroll() {
        if (!pendingScrollPositions) return
        const positions = pendingScrollPositions
        pendingScrollPositions = null
        for (let index = 0; index < 2; ++index) {
            const view = index === 0 ? availablePool : mainDeckList
            view.forceLayout()
            view.contentY = view.originY + Math.max(0, Math.min(positions[index], view.contentHeight - view.height))
        }
    }

    function refreshBasicPrintings() {
        if (!visible) return
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

    function basicPrintingLabel(name) {
        const printing = basicPrinting(name)
        return printing.setCode ? printing.setCode + " · #" + printing.collectorNumber
            : qsTranslate("TournamentLobby", "Select printing")
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
        preserveConstructionScroll()
        basicPrintings = Object.assign({}, basicPrintings, values)
        if (cardCatalogModel && typeof cardCatalogModel.cacheCardsIncrementally === "function")
            cardCatalogModel.cacheCardsIncrementally([Object.assign({name: name}, values[name])])
        saveConstruction()
    }

    function sealedPacks() {
        if (limitedModel.eventType !== "set_sealed" || !participantId) return []
        const count = Number((limitedModel.product || {}).cardsPerPack || 0)
        const cards = limitedModel.pool || []
        // The server preserves generation order and validates equal pack sizes.
        // Group the existing private instances; never generate or reroll cards.
        if (count < 1 || cards.length !== count * 6) return []
        const packs = []
        for (let index = 0; index < 6; ++index)
            packs.push({cards: cards.slice(index * count, (index + 1) * count)})
        return packs
    }

    function showSealedPacks() {
        const packs = sealedPacks()
        if (!visible || !packs.length) return
        sealedOpeningSeen = true
        saveConstruction()
        hideCardPreview()
        sealedPacksOverlay.showPacks(packs, (limitedModel.product || {}).name || "")
    }

    function maybeOpenSealedPacks() {
        if (constructionReady && visible && animatePackOpenings && !sealedOpeningSeen
                && !limitedModel.deckSubmitted && limitedModel.stage === "deck_building")
            showSealedPacks()
    }

}
