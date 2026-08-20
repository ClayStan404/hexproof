// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import "../components"

Page {
    id: root

    readonly property var appWindow: ApplicationWindow.window
    readonly property var formatOptions: [
        {"label": I18n.formatLabel("custom"), "value": "custom"},
        {"label": I18n.formatLabel("standard"), "value": "standard"},
        {"label": I18n.formatLabel("pioneer"), "value": "pioneer"},
        {"label": I18n.formatLabel("modern"), "value": "modern"},
        {"label": I18n.formatLabel("legacy"), "value": "legacy"},
        {"label": I18n.formatLabel("vintage"), "value": "vintage"},
        {"label": I18n.formatLabel("pauper"), "value": "pauper"},
        {"label": I18n.formatLabel("duel"), "value": "duel"},
        {"label": I18n.formatLabel("commander"), "value": "commander"}
    ]
    property string pendingDeckFilterQuery: ""
    property string deckFilterQuery: ""
    property string pendingDeckFormat: ""
    readonly property var filteredMainCards:
        filterDeckCards(deckLibrary.mainCards)
    readonly property var filteredSideboardCards:
        filterDeckCards(deckLibrary.sideboardCards)
    readonly property var currentCommanderCards: commanderCards()
    readonly property bool commanderFormat:
        deckLibrary.currentDeckTableMode === "duel"
        || deckLibrary.currentDeckTableMode === "edh"

    background: AppBackground { }

    ScreenHeader {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(22)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        title: deckLibrary.currentDeckName.length > 0 ? deckLibrary.currentDeckName : qsTr("Deck editor")
        subtitle: qsTr("Changes save automatically")
        onBackRequested: root.closeEditor()
    }

    AppComboBox {
        id: formatSelector
        objectName: "deckFormatSelector"
        anchors.right: header.right
        anchors.verticalCenter: header.verticalCenter
        width: Theme.size(190)
        z: 1
        model: root.formatOptions
        textRole: "label"
        valueRole: "value"
        currentIndex: root.formatIndex(deckLibrary.currentDeckFormat)
        onActivated: index => root.requestFormatChange(index)
    }

    RowLayout {
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(14)
        anchors.bottomMargin: Theme.size(24)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        spacing: Theme.size(16)

        Surface {
            id: mainSurface
            Layout.fillWidth: true
            Layout.fillHeight: true
            elevated: true

            DropArea {
                anchors.fill: parent
                keys: ["application/x-hexproof-card"]
                onDropped: drop => {
                    const name = drop.getDataAsString("application/x-hexproof-card")
                    const fromSideboard = drop.getDataAsString("application/x-hexproof-sideboard") === "true"
                    if (fromSideboard && deckLibrary.moveCard(name, false))
                        drop.acceptProposedAction()
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.size(20)
                spacing: Theme.size(10)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.size(10)

                    ColumnLayout {
                        spacing: Theme.size(2)
                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("Main deck")
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(18)
                            font.weight: Font.DemiBold
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: qsTr(
                                      "%n cards · Drag a card here from the sideboard",
                                      "", deckLibrary.currentMainCount)
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(11)
                        }
                    }

                    Item { Layout.fillWidth: true }

                    AppButton {
                        objectName: "exportCurrentDeckButton"
                        compact: true
                        text: qsTr("Export")
                        enabled: deckLibrary.currentDeckId.length > 0
                        onClicked: exportDialog.open()
                    }

                    AppButton {
                        objectName: "cacheCurrentDeckArtButton"
                        compact: true
                        text: qsTr("Cache art")
                        enabled: deckLibrary.currentMissingImageCount > 0
                                 && !cardCatalog.busy
                        onClicked: deckLibrary.cacheCurrentDeckArt()
                    }

                    AppTextField {
                        id: deckFilterField
                        objectName: "deckFilterField"
                        Layout.preferredWidth:
                            Math.min(Theme.size(260), root.width * 0.22)
                        implicitHeight: Theme.size(40)
                        placeholderText: qsTr("Search this deck…")
                        onTextEdited: {
                            root.pendingDeckFilterQuery = text
                            deckFilterTimer.restart()
                        }
                        onAccepted: root.applyDeckFilter()
                    }

                    AppTextField {
                        id: nameField
                        Layout.preferredWidth: Math.min(
                                                   Theme.size(280),
                                                   root.width * 0.24)
                        implicitHeight: Theme.size(40)
                        placeholderText: qsTr("Deck name")
                        onAccepted: deckLibrary.renameCurrentDeck(text)
                        onEditingFinished: deckLibrary.renameCurrentDeck(text)
                        Component.onCompleted: text = deckLibrary.currentDeckName
                    }

                    StatusPill {
                        text: I18n.status(deckLibrary.currentStatus)
                        statusColor: deckLibrary.currentReady
                                     && deckLibrary.currentValidationVerified
                                     ? Theme.success
                                     : (!deckLibrary.currentValidationVerified
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
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.divider }

                ListView {
                    id: mainList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: root.filteredMainCards
                    spacing: Theme.size(7)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    section.property: "category"
                    section.criteria: ViewSection.FullString
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    section.delegate: Item {
                        required property string section
                        width: ListView.view.width
                        height: Theme.size(34)
                        Text {
                            textFormat: Text.PlainText
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Theme.size(7)
                            text: I18n.cardCategory(
                                      parent.section).toUpperCase()
                            color: Theme.primary
                            font.pixelSize: Theme.fontSize(10)
                            font.weight: Font.Bold
                            font.letterSpacing: 1.1
                        }
                    }

                    delegate: DeckCardRow {
                        required property var modelData
                        width: ListView.view.width
                        card: modelData
                        sideboard: false
                        sideboardEnabled: !root.commanderFormat
                        commanderEnabled: root.commanderFormat
                        printingEnabled: cardCatalog.installed
                        catalogModel: cardCatalog
                        incrementEnabled: deckLibrary.canAddCard(
                                              modelData.name,
                                              modelData.typeLine)
                        dropTarget: sideboardSurface
                        onMoveRequested: deckLibrary.moveCard(modelData.name, true)
                        onIncrementRequested: deckLibrary.changeCardCount(modelData.name, false, 1)
                        onDecrementRequested: deckLibrary.changeCardCount(modelData.name, false, -1)
                        onCommanderRequested: deckLibrary.setCommander(modelData.name)
                        onPrintingRequested: printingPicker.showFor(modelData, false)
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    visible: root.filteredMainCards.length === 0
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                    text: root.deckFilterQuery.trim().length > 0
                          ? qsTr("No cards match this deck search.")
                          : qsTr("Add cards from search or drag them back from the sideboard.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(12)
                }
            }
        }

        ColumnLayout {
            Layout.preferredWidth: root.width < Theme.size(1050)
                                   ? Theme.size(310) : Theme.size(390)
            Layout.maximumWidth: Theme.size(420)
            Layout.fillHeight: true
            spacing: Theme.size(16)

            Surface {
                Layout.fillWidth: true
                Layout.preferredHeight: cardCatalog.installed ? Theme.size(138) : Theme.size(230)
                elevated: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.size(18)
                    spacing: Theme.size(9)

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("Card search")
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(16)
                            font.weight: Font.DemiBold
                        }

                        Item { Layout.fillWidth: true }

                        StatusPill {
                            text: !cardCatalog.installed ? qsTr("Database needed")
                                  : (cardCatalog.enhancedIndexInstalled
                                     && cardCatalog.chineseIndexInstalled
                                     ? qsTr("Offline catalog") : qsTr("Update needed"))
                            statusColor: cardCatalog.enhancedIndexInstalled
                                         && cardCatalog.chineseIndexInstalled
                                         ? Theme.success : Theme.warning
                        }
                    }

                    AppButton {
                        Layout.fillWidth: true
                        leadingText: "⌕"
                        text: qsTr("Search card names…")
                        enabled: cardCatalog.installed
                        onClicked: searchPopup.openSearch()
                    }

                    Text {
                        textFormat: Text.PlainText
                        visible: !cardCatalog.installed
                        Layout.fillWidth: true
                        text: qsTr("Download a metadata package to search every card while offline.")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(11)
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }

                    AppButton {
                        visible: !cardCatalog.installed
                        Layout.alignment: Qt.AlignHCenter
                        compact: true
                        text: qsTr("Database settings")
                        onClicked: root.appWindow.pushScreen("screens/Settings.qml")
                    }
                }
            }

            Surface {
                id: tokenSurface
                objectName: "deckTokenSurface"
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.size(138)
                elevated: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.size(16)
                    spacing: Theme.size(10)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.size(10)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.size(2)

                            Text {
                                textFormat: Text.PlainText
                                text: qsTr("Deck tokens")
                                color: Theme.text
                                font.pixelSize: Theme.fontSize(16)
                                font.weight: Font.DemiBold
                            }

                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: deckLibrary.currentTokens.length > 0
                                      ? root.deckTokenSummary()
                                      : qsTr("No saved tokens")
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSize(10)
                                elide: Text.ElideRight
                            }
                        }

                        StatusPill {
                            text: qsTr("%1 saved").arg(
                                      deckLibrary.currentTokens.length)
                            statusColor: deckLibrary.currentTokens.length > 0
                                         ? Theme.primary : Theme.textMuted
                        }
                    }

                    AppButton {
                        objectName: "manageDeckTokensButton"
                        Layout.fillWidth: true
                        variant: "ghost"
                        text: qsTr("Manage deck tokens")
                        onClicked: deckTokenManager.open()
                    }
                }
            }

            Surface {
                id: sideboardSurface
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.commanderFormat
                elevated: true

                DropArea {
                    anchors.fill: parent
                    keys: ["application/x-hexproof-card"]
                    onDropped: drop => {
                        const name = drop.getDataAsString("application/x-hexproof-card")
                        const fromSideboard = drop.getDataAsString("application/x-hexproof-sideboard") === "true"
                        if (!fromSideboard && deckLibrary.moveCard(name, true))
                            drop.acceptProposedAction()
                    }
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
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: root.filteredSideboardCards
                        spacing: Theme.size(7)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: DeckCardRow {
                            required property var modelData
                            width: ListView.view.width
                            card: modelData
                            sideboard: true
                            printingEnabled: cardCatalog.installed
                            catalogModel: cardCatalog
                            incrementEnabled: deckLibrary.canAddCard(
                                                  modelData.name,
                                                  modelData.typeLine)
                            dropTarget: mainSurface
                            onMoveRequested: deckLibrary.moveCard(modelData.name, false)
                            onIncrementRequested: deckLibrary.changeCardCount(modelData.name, true, 1)
                            onDecrementRequested: deckLibrary.changeCardCount(modelData.name, true, -1)
                            onPrintingRequested: printingPicker.showFor(modelData, true)
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

            Surface {
                objectName: "commanderSurface"
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.commanderFormat
                elevated: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.size(18)
                    spacing: Theme.size(10)

                    RowLayout {
                        Layout.fillWidth: true

                        ColumnLayout {
                            spacing: Theme.size(2)
                            Text {
                                textFormat: Text.PlainText
                                text: qsTr("Commander")
                                color: Theme.text
                                font.pixelSize: Theme.fontSize(16)
                                font.weight: Font.DemiBold
                            }
                            Text {
                                textFormat: Text.PlainText
                                text: root.currentCommanderCards.length > 0
                                      ? root.commanderNames()
                                      : qsTr("No commander selected")
                                color: root.currentCommanderCards.length > 0
                                       ? Theme.primary : Theme.warning
                                font.pixelSize: Theme.fontSize(10)
                                elide: Text.ElideRight
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Row {
                            id: commanderArtRow
                            anchors.fill: parent
                            spacing: Theme.size(8)

                            Repeater {
                                model: root.currentCommanderCards

                                delegate: Image {
                                    required property var modelData
                                    width: (commanderArtRow.width
                                            - commanderArtRow.spacing
                                              * Math.max(
                                                  0,
                                                  root.currentCommanderCards.length
                                                  - 1))
                                           / Math.max(
                                               1,
                                               root.currentCommanderCards.length)
                                    height: commanderArtRow.height
                                    source: {
                                        if (modelData.imageSource)
                                            return modelData.imageSource
                                        if (!cardCatalog
                                                || typeof cardCatalog.imageSource
                                                   !== "function")
                                            return ""
                                        if (typeof cardCatalog.imageRevision
                                                !== "undefined"
                                                && cardCatalog.imageRevision === -1)
                                            return ""
                                        void cardCatalog.imageRevision
                                        return cardCatalog.imageSource(
                                            modelData.name || "",
                                            modelData.setCode || "",
                                            modelData.collectorNumber || "")
                                    }
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    smooth: true
                                }
                            }
                        }

                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            width: parent.width - Theme.size(24)
                            visible: root.currentCommanderCards.length === 0
                            text: qsTr("Choose up to two commanders using the stars beside main-deck cards.")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(11)
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: Theme.size(8)
        visible: cardCatalog.busy && !cardCatalog.searching
        width: cachingRow.implicitWidth + Theme.size(24)
        height: Theme.size(30)
        radius: Theme.size(15)
        color: Theme.surfaceElevated
        border.width: 1
        border.color: Theme.borderStrong

        Row {
            id: cachingRow
            anchors.centerIn: parent
            spacing: Theme.size(8)
            ActivityRing {
                width: Theme.size(14)
                height: Theme.size(14)
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                textFormat: Text.PlainText
                text: I18n.status(cardCatalog.status)
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(10)
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    PrintingPicker {
        id: printingPicker
        catalogModel: cardCatalog
        onChosen: (printing, isSideboard) => deckLibrary.setCardPrinting(
            printingPicker.cardName, isSideboard, printing.displayName, printing.typeLine,
            printing.setCode, printing.collectorNumber)
    }

    CardSearchPopup {
        id: searchPopup
        results: cardCatalog.searchResults
        searching: cardCatalog.searching
        deckLibraryModel: deckLibrary
        allowSideboard: !root.commanderFormat
        filtersAvailable: cardCatalog.enhancedIndexInstalled
        onSearchRequested: function(query, typeFilter, setFilter,
                                    languageFilter, colorFilter,
                                    rarityFilter, legalityFilter) {
            cardCatalog.search(query, typeFilter, setFilter, languageFilter,
                               colorFilter, rarityFilter, legalityFilter)
        }
        onAddRequested: (card, sideboard) => deckLibrary.addCard(
            card.name, card.displayName, card.typeLine,
            card.setCode, card.collectorNumber, sideboard)
    }

    TokenPicker {
        id: deckTokenPicker
        catalogModel: cardCatalog
        preferredTokens: deckLibrary.currentTokens
        titleText: qsTr("Add deck token")
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

    Timer {
        id: deckFilterTimer
        interval: 250
        onTriggered: root.applyDeckFilter()
    }

    function filterDeckCards(cards) {
        const query = deckFilterQuery.trim().toLocaleLowerCase()
        if (query.length === 0)
            return cards
        const filtered = []
        for (let index = 0; index < cards.length; ++index) {
            const card = cards[index]
            const haystack = [
                card.name ? card.name : "",
                card.displayName ? card.displayName : "",
                card.typeLine ? card.typeLine : "",
                card.setCode ? card.setCode : "",
                card.category ? card.category : ""
            ].join(" ").toLocaleLowerCase()
            if (haystack.includes(query))
                filtered.push(card)
        }
        return filtered
    }

    function applyDeckFilter() {
        deckFilterTimer.stop()
        deckFilterQuery = pendingDeckFilterQuery
    }

    function commanderCards() {
        const cards = deckLibrary.mainCards
        const commanders = []
        for (let index = 0; index < cards.length; ++index) {
            if (cards[index].commander === true)
                commanders.push(cards[index])
        }
        return commanders
    }

    function commanderNames() {
        const names = []
        for (let index = 0;
             index < currentCommanderCards.length; ++index) {
            names.push(currentCommanderCards[index].displayName)
        }
        return names.join(" / ")
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
        if (isCommanderDeckFormat(nextFormat) !== commanderFormat) {
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

    function deckTokenSummary() {
        const tokens = deckLibrary.currentTokens
        const names = []
        const visibleCount = Math.min(tokens.length, 3)
        for (let index = 0; index < visibleCount; ++index)
            names.push(tokens[index].displayName)
        if (tokens.length > visibleCount)
            names.push(qsTr("and %1 more").arg(tokens.length - visibleCount))
        return names.join(" · ")
    }

    function closeEditor() {
        deckLibrary.closeDeck()
        root.appWindow.popScreen()
    }

    Connections {
        target: deckLibrary

        function onCurrentDeckChanged() {
            root.syncFormatSelector()
        }
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

    ExportDeckDialog {
        id: exportDialog
        objectName: "exportCurrentDeckDialog"
        deckName: deckLibrary.currentDeckName
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

    FileDialog {
        id: exportFileDialog
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
