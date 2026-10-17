// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import "../components"

Page {
    id: root

    readonly property var appWindow: ApplicationWindow.window
    readonly property var customArtStore: typeof customCardArtStore !== "undefined"
                                         ? customCardArtStore : null
    readonly property var formatOptions: I18n.deckFormatOptions()
    readonly property string deckFilterQuery: localFilters.query
    property alias cardFilters: localFilters
    CardFilterState { id: localFilters }
    readonly property bool compactLayout: width < Theme.size(1000)
    property string searchTarget: "deck"
    property string pendingDeckFormat: ""
    property bool deckScrollRestorePending: false
    property real savedSideboardContentY: 0
    readonly property var filteredMainCards:
        filterDeckCards(deckLibrary.mainCards)
    readonly property var filteredSideboardCards:
        filterDeckCards(deckLibrary.sideboardCards)
    readonly property bool commanderFormat:
        deckLibrary.currentDeckTableMode === "duel"
        || deckLibrary.currentDeckTableMode === "edh"
    readonly property bool cubeFormat: deckLibrary.currentDeckFormat === "cube"
    readonly property bool showSideboardColumn:
        !root.commanderFormat && !root.cubeFormat

    background: AppBackground { }

    ColumnLayout {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(12)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        spacing: Theme.size(6)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(10)

            ScreenHeader {
                Layout.fillWidth: true
                Layout.minimumWidth: Theme.size(140)
                compact: true
                title: deckLibrary.currentDeckName.length > 0 ? deckLibrary.currentDeckName : qsTr("Deck editor")
                subtitle: root.cubeFormat
                          ? qsTr("%n physical card(s)", "", deckLibrary.currentMainCount)
                          : qsTr("%n cards", "", deckLibrary.currentMainCount)
                titleEditable: deckLibrary.currentDeckId.length > 0
                onBackRequested: root.closeEditor()
                onTitleEdited: name => {
                    if (!deckLibrary.renameCurrentDeck(name))
                        root.appWindow.showBanner(I18n.status(deckLibrary.lastError))
                }
            }

            StatusPill {
                objectName: "deckEditorStatus"
                maximumWidth: Theme.size(180)
                text: I18n.status(deckLibrary.currentStatus)
                statusColor: deckLibrary.currentReady
                             && deckLibrary.currentValidationVerified
                             && deckLibrary.currentValidationWarnings.length === 0
                             ? Theme.success
                             : (!deckLibrary.currentValidationVerified
                                || deckLibrary.currentValidationWarnings.indexOf(
                                    deckLibrary.currentStatus) >= 0
                                ? Theme.warning
                             : (deckLibrary.currentStatus === "Commander required"
                                ? Theme.warning : Theme.textMuted))
                ToolTip.visible: legalityStatusHover.hovered
                                 && deckLibrary.currentValidationIssues.length > 0
                ToolTip.delay: 350
                ToolTip.text: deckLibrary.currentValidationIssues
                              .map(issue => I18n.status(issue)).join("\n")
                HoverHandler { id: legalityStatusHover }
            }

            AppComboBox {
                id: formatSelector
                objectName: "deckFormatSelector"
                Layout.preferredWidth: Theme.size(168)
                model: root.formatOptions
                textRole: "label"
                valueRole: "value"
                implicitHeight: Theme.size(38)
                currentIndex: root.formatIndex(deckLibrary.currentDeckFormat)
                onActivated: index => root.requestFormatChange(index)
            }
        }

        Flow {
            id: deckActions
            objectName: "deckEditorActions"
            Layout.fillWidth: true
            spacing: Theme.size(6)

            AppButton {
                objectName: "deckEditorSearchButton"
                compact: true
                leadingText: "⌕"
                text: qsTr("Search cards")
                enabled: cardCatalog.installed
                onClicked: root.openCardSearch("deck")
            }

            AppButton {
                objectName: "manageConsiderButton"
                compact: true
                text: qsTr("Consider (%1)").arg(deckLibrary.currentConsiderCount)
                onClicked: considerManager.open()
            }

            AppButton {
                objectName: "manageDeckTokensButton"
                compact: true
                visible: !root.cubeFormat
                text: deckLibrary.currentTokens.length > 0
                      ? qsTr("Tokens · %1").arg(deckLibrary.currentTokens.length)
                      : qsTr("Tokens")
                onClicked: deckTokenManager.open()
            }

            AppButton {
                id: moreButton
                objectName: "deckEditorMoreButton"
                compact: true
                leadingText: "⋯"
                text: qsTr("More")
                enabled: deckLibrary.currentDeckId.length > 0
                onClicked: moreMenu.popup(moreButton, 0, moreButton.height + Theme.size(4))
            }

            AppButton {
                compact: true
                visible: !cardCatalog.installed
                text: qsTr("Database settings")
                onClicked: root.appWindow.pushScreen("screens/CatalogSettings.qml")
            }
        }
    }

    Flickable {
        id: editorBody
        objectName: "deckEditorBody"
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(6)
        anchors.bottomMargin: Theme.size(12)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        contentWidth: width
        contentHeight: editorContent.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        GridLayout {
            id: editorContent
            width: editorBody.width
            height: Math.max(editorBody.height, implicitHeight)
            columns: root.compactLayout || !root.showSideboardColumn ? 1 : 2
            columnSpacing: Theme.size(16)
            rowSpacing: Theme.size(12)

            Surface {
                id: mainSurface
                objectName: "deckEditorMainSurface"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.fillHeight: true
                implicitHeight: mainContent.implicitHeight + Theme.size(20)
                elevated: true
                clip: true

                DropArea {
                    anchors.fill: parent
                    keys: ["application/x-hexproof-card"]
                    onDropped: drop => root.forwardDeckCardDrop(drop, false)
                }

                ColumnLayout {
                    id: mainContent
                    anchors.fill: parent
                    anchors.margins: Theme.size(10)
                    spacing: Theme.size(6)

                    CardCacheProgress {
                        id: deckEditorCacheProgress
                        objectName: "deckEditorCacheProgress"
                        Layout.fillWidth: true
                        catalogModel: cardCatalog
                    }

                    DeckMainCollection {
                        id: mainCollection
                        outerFlickable: editorBody
                        Layout.minimumHeight: Theme.size(350)
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.fillHeight: true
                        cards: root.filteredMainCards
                        deckLibraryModel: deckLibrary
                        catalogModel: cardCatalog
                        commanderFormat: root.commanderFormat
                        cubeFormat: root.cubeFormat
                        customArtEnabled: root.customArtStore !== null
                        searchActive: root.deckFilterQuery.trim().length > 0
                        filterState: localFilters
                        filterPlaceholder: qsTr("Search this deck…")
                        sideboardDropTarget: sideboardSurface
                        onPrintingRequested: card => printingPicker.showFor(card, false)
                        onCustomArtRequested: card => customArtDialog.showFor(card)
                    }
                }
            }

            ColumnLayout {
                objectName: "deckEditorSidebar"
                visible: root.showSideboardColumn
                Layout.fillWidth: root.compactLayout
                Layout.preferredWidth: root.compactLayout ? -1 : Theme.size(390)
                Layout.minimumWidth: 0
                Layout.maximumWidth: root.compactLayout ? Number.POSITIVE_INFINITY : Theme.size(420)
                Layout.fillHeight: true
                spacing: Theme.size(12)

                Surface {
                    id: sideboardSurface
                    Layout.minimumHeight: Theme.size(240)
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !root.commanderFormat && !root.cubeFormat
                    elevated: true

                    DropArea {
                        anchors.fill: parent
                        keys: ["application/x-hexproof-card"]
                        onDropped: drop => root.forwardDeckCardDrop(drop, true)
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.size(18)
                        spacing: Theme.size(9)

                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                spacing: Theme.size(2)
                                Text {
                                    textFormat: Text.PlainText
                                    text: qsTr("Sideboard")
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSize(16)
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    textFormat: Text.PlainText
                                    text: qsTr(
                                              "%n cards · Drop main-deck cards here",
                                              "",
                                              deckLibrary.currentSideboardCount)
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fontSize(10)
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }

                        ListView {
                            id: sideboardList
                            objectName: "sideboardList"
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.fillHeight: true
                            model: root.filteredSideboardCards
                            spacing: Theme.size(7)
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                            ScrollChainHandler {
                                innerFlickable: sideboardList
                                outerFlickable: editorBody
                            }

                            delegate: DeckCardRow {
                                required property var modelData
                                width: sideboardList.width
                                card: modelData
                                sideboard: true
                                printingEnabled: cardCatalog.installed
                                customArtEnabled: root.customArtStore !== null
                                catalogModel: cardCatalog
                                incrementEnabled: deckLibrary.canAddCard(
                                                      modelData.name,
                                                      modelData.typeLine)
                                dropTarget: mainSurface
                                onMoveRequested: deckLibrary.moveCard(
                                                     modelData.name,
                                                     modelData.setCode,
                                                     modelData.collectorNumber,
                                                     false)
                                onIncrementRequested: deckLibrary.changeCardCount(
                                                          modelData.name,
                                                          modelData.setCode,
                                                          modelData.collectorNumber,
                                                          true, 1)
                                onDecrementRequested: deckLibrary.changeCardCount(
                                                          modelData.name,
                                                          modelData.setCode,
                                                          modelData.collectorNumber,
                                                          true, -1)
                                onPrintingRequested: printingPicker.showFor(modelData, true)
                                onCustomArtRequested: customArtDialog.showFor(modelData)
                            }
                        }

                        Text {
                            textFormat: Text.PlainText
                            visible: root.filteredSideboardCards.length === 0
                            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                            text: qsTr("No sideboard cards")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(11)
                        }
                    }
                }
            }
        }
    }

    PrintingPicker {
        id: printingPicker
        objectName: "deckPrintingPicker"
        catalogModel: cardCatalog
        onChosen: (printing, isSideboard) => deckLibrary.setCardPrinting(
            printingPicker.cardName, printingPicker.currentSetCode,
            printingPicker.currentCollectorNumber, isSideboard,
            printing.displayName, printing.typeLine,
            printing.setCode, printing.collectorNumber)
    }

    CardSearchPopup {
        id: searchPopup
        objectName: "deckEditorSearchPopup"
        catalogModel: cardCatalog
        results: cardCatalog.searchResults
        searching: cardCatalog.searching
        deckLibraryModel: deckLibrary
        allowSideboard: !root.commanderFormat && !root.cubeFormat
        considerOnly: root.searchTarget === "consider"
        filtersAvailable: cardCatalog.enhancedIndexInstalled
        onSearchRequested: function(query, typeFilter, setFilter,
                                    languageFilter, colorFilter,
                                    rarityFilter, legalityFilter, manaFilter) {
            cardCatalog.search(query, typeFilter, setFilter, languageFilter,
                               colorFilter, rarityFilter, legalityFilter, manaFilter)
        }
        onAddRequested: (card, destination) => {
            if (destination === "consider") {
                deckLibrary.addConsiderCard(card.name, card.displayName,
                                            card.typeLine, card.setCode,
                                            card.collectorNumber)
            } else {
                deckLibrary.addCard(card.name, card.displayName, card.typeLine,
                                    card.setCode, card.collectorNumber,
                                    destination === "sideboard")
            }
        }
    }

    TokenPicker {
        id: deckTokenPicker
        catalogModel: cardCatalog
        preferredTokens: deckLibrary.currentTokens
        titleText: qsTr("Add deck tokens and emblems")
        actionText: qsTr("Add")
        existingTokensDisabled: true
        onTokenSelected: token => deckLibrary.addToken(token)
    }

    DeckTokenManager {
        id: deckTokenManager
        objectName: "deckTokenManager"
        deckLibraryModel: deckLibrary
        catalogModel: cardCatalog
        onAddRequested: deckTokenPicker.open()
    }

    DeckConsiderManager {
        id: considerManager
        objectName: "deckConsiderManager"
        deckLibraryModel: deckLibrary
        catalogModel: cardCatalog
        onAddRequested: root.openCardSearch("consider")
        customArtEnabled: root.customArtStore !== null
        onCustomArtRequested: card => customArtDialog.showFor(card)
    }

    CustomCardArtDialog {
        id: customArtDialog
        objectName: "deckCustomCardArtDialog"
        store: root.customArtStore
        catalogModel: cardCatalog
    }

    function filterDeckCards(cards) { return localFilters.filter(cards) }

    function forwardDeckCardDrop(drop, toSideboard) {
        const name = drop.getDataAsString("application/x-hexproof-card")
        const setCode = drop.getDataAsString("application/x-hexproof-set-code")
        const collectorNumber = drop.getDataAsString(
                                  "application/x-hexproof-collector-number")
        const fromSideboard = drop.getDataAsString(
                                  "application/x-hexproof-sideboard") === "true"
        if (fromSideboard === toSideboard
                || !deckLibrary.moveCard(name, setCode, collectorNumber,
                                         toSideboard))
            return false
        drop.acceptProposedAction()
        return true
    }

    function openCardSearch(target) {
        searchTarget = target
        searchPopup.openSearch()
    }

    function formatIndex(value) {
        for (let index = 0; index < formatOptions.length; ++index) {
            if (formatOptions[index].value === value)
                return index
        }
        return 0
    }

    function isCommanderDeckFormat(format) {
        return format === "duel" || format === "commander"
    }

    function formatKind(format) {
        if (isCommanderDeckFormat(format))
            return "commander"
        return format === "cube" ? "cube" : "constructed"
    }

    function syncFormatSelector() {
        const index = formatIndex(deckLibrary.currentDeckFormat)
        if (formatSelector.currentIndex !== index)
            formatSelector.currentIndex = index
    }

    function requestFormatChange(index) {
        if (index < 0 || index >= formatOptions.length) {
            syncFormatSelector()
            return
        }
        const nextFormat = formatOptions[index].value
        if (nextFormat === deckLibrary.currentDeckFormat) {
            pendingDeckFormat = ""
            return
        }
        pendingDeckFormat = nextFormat
        if (formatKind(nextFormat)
                !== formatKind(deckLibrary.currentDeckFormat)) {
            formatChangeConfirmation.open()
            return
        }
        applyPendingFormatChange()
    }

    function applyPendingFormatChange() {
        const nextFormat = pendingDeckFormat
        pendingDeckFormat = ""
        if (nextFormat.length === 0) {
            syncFormatSelector()
            return
        }
        if (!deckLibrary.changeCurrentDeckFormat(nextFormat)) {
            syncFormatSelector()
            root.appWindow.showBanner(I18n.status(deckLibrary.lastError))
        }
    }

    function formatChangeMessage() {
        if (pendingDeckFormat === "cube") {
            if (deckLibrary.currentSideboardCount > 0) {
                return qsTr(
                    "%n sideboard card(s) will be moved into the Cube pool. Commander designations will be cleared. No cards will be deleted.",
                    "", deckLibrary.currentSideboardCount)
            }
            return qsTr("Commander designations will be cleared. Every card will remain in the Cube pool.")
        }
        if (deckLibrary.currentDeckFormat === "cube") {
            return qsTr("Every Cube card will remain in the main deck. The sideboard starts empty, and no cards will be deleted.")
        }
        if (isCommanderDeckFormat(pendingDeckFormat)) {
            if (deckLibrary.currentSideboardCount > 0) {
                return qsTr(
                    "%n sideboard card(s) will be moved into the main deck. Commander selection will start empty. No cards will be deleted.",
                    "", deckLibrary.currentSideboardCount)
            }
            return qsTr("Commander selection will start empty. No cards will be deleted.")
        }
        return qsTr("Commander designations will be cleared. Those cards will remain in the main deck, and no cards will be deleted.")
    }

    function restoreListContentY(listView, savedContentY) {
        const minimum = listView.originY
        const maximum = Math.max(minimum,
                                 minimum + listView.contentHeight
                                 - listView.height)
        listView.contentY = Math.max(minimum,
                                     Math.min(savedContentY, maximum))
    }

    function restoreDeckScrollPositions() {
        if (!deckScrollRestorePending)
            return
        restoreListContentY(sideboardList, savedSideboardContentY)
        deckScrollRestorePending = false
    }

    function closeEditor() {
        deckLibrary.closeDeck()
        root.appWindow.popScreen()
    }

    Connections {
        target: deckLibrary

        function onCurrentDeckCardsAboutToChange() {
            if (root.deckScrollRestorePending)
                return
            root.savedSideboardContentY = sideboardList.contentY
            root.deckScrollRestorePending = true
        }

        function onCurrentDeckCardsChanged() {
            if (root.deckScrollRestorePending)
                deckScrollRestoreTimer.restart()
        }

        function onCurrentDeckChanged() {
            root.syncFormatSelector()
        }
    }

    Timer {
        id: deckScrollRestoreTimer
        interval: 0
        repeat: false
        onTriggered: Qt.callLater(root.restoreDeckScrollPositions)
    }

    ConfirmDialog {
        id: formatChangeConfirmation
        objectName: "formatChangeConfirmation"
        titleText: qsTr("Change format to %1?").arg(
                       I18n.formatLabel(root.pendingDeckFormat))
        message: root.formatChangeMessage()
        confirmText: qsTr("Change format")
        onConfirmed: root.applyPendingFormatChange()
        onCancelled: {
            root.pendingDeckFormat = ""
            root.syncFormatSelector()
        }
    }

    AppMenu {
        id: moreMenu
        objectName: "deckEditorMoreMenu"

        AppMenuItem {
            objectName: "exportCurrentDeckButton"
            text: qsTr("Export")
            enabled: deckLibrary.currentDeckId.length > 0
            onTriggered: exportDialog.open()
        }

        AppMenuItem {
            objectName: "cacheCurrentDeckArtButton"
            text: qsTr("Cache deck art")
            enabled: deckLibrary.currentDeckId.length > 0
                     && !deckEditorCacheProgress.cacheActive
            onTriggered: deckLibrary.cacheCurrentDeckArt()
        }
    }

    ExportDeckDialog {
        id: exportDialog
        objectName: "exportCurrentDeckDialog"
        deckName: deckLibrary.currentDeckName
        onCardArtRequested: deckArtExportDialog.prepare(
                                deckLibrary.currentDeckName,
                                deckLibrary.cardArtExportRequests(deckLibrary.currentDeckId))
        onCopyRequested: {
            if (deckLibrary.copyCurrentDeckText())
                root.appWindow.showBanner(qsTr("Deck list copied"))
            else
                root.appWindow.showBanner(I18n.status(deckLibrary.lastError))
        }
        onSaveRequested: {
            exportFileDialog.selectedFile = deckLibrary.suggestedExportUrl("")
            exportFileDialog.open()
        }
    }

    DeckArtExportDialog {
        id: deckArtExportDialog
        objectName: "currentDeckArtExportDialog"
        fileDialogObjectName: "currentDeckArtExportFileDialog"
        manager: typeof cardArtManager !== "undefined" ? cardArtManager : null
    }

    FileDialog {
        id: exportFileDialog
        objectName: "exportDeckFileDialog"
        title: qsTr("Save deck list")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "txt"
        nameFilters: [
            qsTr("Deck lists") + " (*.txt)",
            qsTr("All files") + " (*)"
        ]
        onAccepted: {
            if (deckLibrary.saveCurrentDeckText(selectedFile))
                root.appWindow.showBanner(qsTr("Deck list saved"))
            else
                root.appWindow.showBanner(I18n.status(deckLibrary.lastError))
        }
    }

    Component.onCompleted: {
        if (deckLibrary.currentDeckId.length === 0)
            Qt.callLater(() => root.appWindow.popScreen())
        else
            root.syncFormatSelector()
    }
}
