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
    property bool localPractice: false
    property bool viewReady: false
    readonly property alias constructionDraftStage: constructionController.constructionDraftStage
    readonly property string draftServer: wsModel.serverUrl || ""
    readonly property alias draftEventId: constructionController.draftEventId
    readonly property alias draftIdentity: constructionController.draftIdentity
    property alias restoredDraftIdentity: constructionController.restoredDraftIdentity
    property alias selectedCards: constructionController.selectedCards
    property alias commanderInstanceIds: constructionController.commanderInstanceIds
    property alias commanderColors: constructionController.commanderColors
    property alias selectionRevision: constructionController.selectionRevision
    property alias basics: constructionController.basics
    property alias basicsRevision: constructionController.basicsRevision
    property alias basicPrintings: constructionController.basicPrintings
    property alias defaultBasicPrintings: constructionController.defaultBasicPrintings
    property alias basicPrintingCatalogIdentity: constructionController.basicPrintingCatalogIdentity
    property var pendingScrollPositions: null
    property alias sealedOpeningSeen: constructionController.sealedOpeningSeen
    property bool animatePackOpenings: typeof preferences !== "undefined" && preferences.animatePackOpenings
    property alias autoBasicLands: constructionController.autoBasicLands
    property alias constructionReady: constructionController.constructionReady
    property alias restoredSubmittedDeck: constructionController.restoredSubmittedDeck
    property alias firstSubmissionFingerprint: constructionController.firstSubmissionFingerprint
    property int groupingModeIndex: 0
    property alias metadataRevision: constructionController.metadataRevision
    property var cachedArtKeys: ({})
    property bool basicLandsExpanded: false
    property alias initialPoolChosen: constructionController.initialPoolChosen
    readonly property alias commanderDraft: constructionController.commanderDraft
    readonly property alias minimumDeckCards: constructionController.minimumDeckCards
    readonly property alias draftEvent: constructionController.draftEvent
    property alias filters: poolFilters
    property alias mainFilters: deckFilters
    property alias inspectedCard: preview.card
    property alias hoverPreviewVisible: preview.visible
    readonly property alias basicNames: constructionController.basicNames
    readonly property var groupingModes: ["mana", "color", "type", "name"]
    readonly property var groupingOptions: [qsTranslate("TournamentLobby", "Mana value"), qsTranslate("TournamentLobby", "Color"), qsTranslate("TournamentLobby", "Card type"), qsTranslate("TournamentLobby", "Name")]
    readonly property string groupingMode: groupingModes[groupingModeIndex]
    readonly property bool filtersActive: poolFilters.active
    readonly property alias enrichedPool: constructionController.enrichedPool
    readonly property alias selectedPoolCount: constructionController.selectedPoolCount
    readonly property alias optionalCards: constructionController.optionalCards
    readonly property alias selectedOptionalCards: constructionController.selectedOptionalCards
    readonly property alias fallbackCommanders: constructionController.fallbackCommanders
    readonly property alias selectedFallbackCommanders: constructionController.selectedFallbackCommanders
    readonly property alias selectedCount: constructionController.selectedCount
    readonly property alias hasUnsubmittedChanges: constructionController.hasUnsubmittedChanges
    readonly property alias participatingPlayers: constructionController.participatingPlayers
    readonly property alias automaticTableAfterSubmission: constructionController.automaticTableAfterSubmission
    readonly property alias mainDeckCards: constructionController.mainDeckCards
    readonly property alias basicLandPlan: constructionController.basicLandPlan
    readonly property alias landAssessment: constructionController.landAssessment
    readonly property alias landWarning: constructionController.landWarning
    readonly property alias commanderCards: constructionController.commanderCards
    readonly property alias commandersValid: constructionController.commandersValid
    readonly property alias commanderAdvice: constructionController.commanderAdvice
    readonly property alias commanderGuidance: constructionController.commanderGuidance
    readonly property alias sideboardCards: constructionController.sideboardCards
    readonly property var visibleSideboardCards: poolFilters.filter(sideboardCards)
    readonly property var sideboardGroups: grouping.groupCards(visibleSideboardCards)
    readonly property alias selectedLandCount: constructionController.selectedLandCount
    readonly property alias selectedNonlandCount: constructionController.selectedNonlandCount
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
    // Stable view aliases above expose one construction owner to existing screens.
    LimitedDeckConstructionController {
        id: constructionController
        limitedModel: root.limitedModel
        cardCatalogModel: root.cardCatalogModel
        draftStore: root.draftStore
        draftServer: root.draftServer
        participantId: root.participantId
        cubeFreePlay: root.cubeFreePlay
        localPractice: root.localPractice
        active: root.visible
        onMutationStarted: hidePreview => {
            root.preserveConstructionScroll()
            if (hidePreview) root.hideCardPreview()
        }
        onSubmissionRequested: (ids, lands, commanders, colors) => {
            if (root.commanderDraft)
                root.wsModel.submitLimitedCommanderDeck(qsTranslate("TournamentLobby", "Limited deck"), ids, lands, commanders, colors)
            else
                root.wsModel.submitLimitedDeck(qsTranslate("TournamentLobby", "Limited deck"), ids, lands)
        }
    }

    Component.onCompleted: {
        viewReady = true
        cachePoolCards()
        Qt.callLater(maybeOpenSealedPacks)
    }

    Connections {
        target: root.limitedModel
        ignoreUnknownSignals: true
        function onSnapshotChanged() {
            Qt.callLater(root.maybeOpenSealedPacks)
        }
    }

    Connections {
        target: root.cardCatalogModel
        ignoreUnknownSignals: true
        function onLanguageChanged() {
            root.cachedArtKeys = ({})
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
                            text: root.localPractice
                                  ? (root.limitedModel.deckSubmitted && !root.hasUnsubmittedChanges
                                     ? qsTranslate("TournamentLobby", "Saved to deck library")
                                     : qsTranslate("TournamentLobby", "Build a deck, then save a local copy."))
                                  : root.limitedModel.deckSubmitted && root.hasUnsubmittedChanges
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
                            text: root.localPractice
                                  ? (root.limitedModel.deckSubmitted ? qsTranslate("TournamentLobby", "Save new copy")
                                                                    : qsTranslate("TournamentLobby", "Save to deck library"))
                                  : root.limitedModel.deckSubmitted ? qsTranslate("TournamentLobby", "Update deck") : qsTranslate("TournamentLobby", "Submit deck")
                            enabled: root.selectedCount >= root.minimumDeckCards && root.commandersValid
                                     && root.limitedModel.pool.length > 0
                                     && root.wsModel.connected !== false
                                     && (!root.localPractice || !root.limitedModel.deckSubmitted || root.hasUnsubmittedChanges)
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

    function cardSelected(instanceId) { return constructionController.cardSelected(instanceId) }

    function cardsForSelection(wantSelected) { return constructionController.cardsForSelection(wantSelected) }

    function enrichPoolCards() { return constructionController.enrichPoolCards() }

    function moveToMainDeck(instanceId) { return constructionController.moveToMainDeck(instanceId) }

    function removeFromMainDeck(card) { return constructionController.removeFromMainDeck(card) }

    function chooseInitialPool(keepPicks) { return constructionController.chooseInitialPool(keepPicks) }

    function moveToSideboard(instanceId) { return constructionController.moveToSideboard(instanceId) }

    function selectedPhysicalCards() { return constructionController.selectedPhysicalCards() }

    function commanderCandidates() { return constructionController.commanderCandidates() }

    function toggleCommander(instanceId) { return constructionController.toggleCommander(instanceId) }

    function setCommanderColor(instanceId, color) { return constructionController.setCommanderColor(instanceId, color) }

    function countSelected() { return constructionController.countSelected() }

    function basicValue(name) { return constructionController.basicValue(name) }

    function countBasics() { return constructionController.countBasics() }

    function basicLabel(name) {
        const labels = {
            "Plains": qsTranslate("TournamentLobby", "Plains"), "Island": qsTranslate("TournamentLobby", "Island"),
            "Swamp": qsTranslate("TournamentLobby", "Swamp"), "Mountain": qsTranslate("TournamentLobby", "Mountain"),
            "Forest": qsTranslate("TournamentLobby", "Forest")
        }
        return labels[name] || name
    }

    function adjustBasic(name, amount) { return constructionController.adjustBasic(name, amount) }

    function setAutoBasicLands(enabled) { return constructionController.setAutoBasicLands(enabled) }

    function updateAutoBasics() { return constructionController.updateAutoBasics() }

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
        if (!viewReady || !visible || !cardCatalogModel || typeof cardCatalogModel.cacheCardsIncrementally !== "function") return
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

    function submit() { return constructionController.submit() }

    function submissionProgress() { return constructionController.submissionProgress() }

    function saveConstruction() { return constructionController.saveConstruction() }

    function restoreConstruction() { return constructionController.restoreConstruction() }

    function submissionDiffers() { return constructionController.submissionDiffers() }

    function selectionFingerprint() { return constructionController.selectionFingerprint() }

    function discardUnsubmittedChanges() { return constructionController.discardUnsubmittedChanges() }

    function restoreSubmission(force = false) { return constructionController.restoreSubmission(force) }

    function preserveConstructionScroll() {
        if (!viewReady || pendingScrollPositions) return
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

    function refreshBasicPrintings() { return constructionController.refreshBasicPrintings() }

    function resolveBasicPrintings() { return constructionController.resolveBasicPrintings() }

    function basicPrinting(name) { return constructionController.basicPrinting(name) }

    function printingIdentity(printing) { return constructionController.printingIdentity(printing) }

    function basicPrintingLabel(name) {
        const printing = basicPrinting(name)
        return printing.setCode ? printing.setCode + " · #" + printing.collectorNumber
            : qsTranslate("TournamentLobby", "Select printing")
    }

    function sanitizeBasicPrintings(values) { return constructionController.sanitizeBasicPrintings(values) }

    function setBasicPrinting(name, printing) { return constructionController.setBasicPrinting(name, printing) }

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
