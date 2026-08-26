// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    property var cards: []
    property var cardCatalogModel: null
    property int selectedIndex: -1
    property int sourceSeat: -1
    property int localSeat: -1
    property string sourceDisplayName: ""
    property string localDisplayName: ""
    property string approvalId: ""
    property int topCount: 0
    property var selectedOrder: []
    property string contextCardId: ""
    property string filterQuery: ""
    property bool offerShuffleOnClose: false
    readonly property var visibleCards: filterCards()
    readonly property int selectedCount: selectedOrder.length
    readonly property bool topCardMode: topCount === 1
    readonly property bool reorderMode: topCount > 1
    readonly property var selectedCard:
        selectedIndex >= 0 && selectedIndex < visibleCards.length
        ? visibleCards[selectedIndex] : ({})
    readonly property bool remoteSource: sourceSeat >= 0
                                         && sourceSeat !== localSeat
    readonly property var destinations: destinationOptions()
    signal searchRequested(var cardIds, string destination, bool reveal,
                           bool randomize, var position, int sourceSeat,
                           string approvalId, int destinationSeat,
                           bool faceDown)
    signal reorderRequested(var cardIds)
    signal resolveRequested(var selectedCardIds, var remainderCardIds,
                            string destination, string remainderPlacement,
                            bool randomizeRemainder, bool faceDown,
                            var position, int sourceSeat, string approvalId)
    signal shuffleReminderRequested()

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(1080), parent.width - Theme.size(48))
    height: Math.min(Theme.size(760), parent.height - Theme.size(56))
    padding: Theme.size(22)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    Overlay.modal: Rectangle { color: "#A6050B09" }

    background: Rectangle {
        color: Theme.surfaceElevated
        radius: Theme.radiusLarge
        border.width: 1
        border.color: Theme.borderStrong
    }

    function showCards(libraryCards, librarySeat, libraryApprovalId,
                       ownSeat, ownName, libraryOwnerName,
                       requestedTopCount) {
        cards = libraryCards ? libraryCards : []
        sourceSeat = librarySeat !== undefined ? librarySeat : -1
        approvalId = libraryApprovalId ? libraryApprovalId : ""
        localSeat = ownSeat !== undefined ? ownSeat : -1
        localDisplayName = ownName ? ownName : qsTr("Player")
        sourceDisplayName = libraryOwnerName
                            ? libraryOwnerName : localDisplayName
        topCount = requestedTopCount ? requestedTopCount : 0
        selectedOrder = []
        contextCardId = ""
        filterQuery = ""
        cardBrowser.resetFilter()
        destinationBox.currentIndex = 0
        topDestinationBox.currentIndex = 0
        remainderPlacementBox.currentIndex = 0
        randomizeRemainderToggle.checked = false
        faceDownToggle.checked = false
        revealToggle.checked = true
        selectedIndex = cards.length > 0 ? 0 : -1
        offerShuffleOnClose = topCount === 0 && sourceSeat === localSeat
                              && localSeat >= 0
        open()
        if (!topCardMode && !reorderMode)
            cardBrowser.focusFilter()
    }

    function filterCards() {
        const query = filterQuery
        if (query.length === 0)
            return cards
        const result = []
        for (let i = 0; i < cards.length; ++i) {
            const card = cards[i]
            if (cardCatalogModel
                && cardCatalogModel.matchesCardQuery(
                    card.name ? card.name : "",
                    card.setCode ? card.setCode : "",
                    card.collectorNumber ? card.collectorNumber : "",
                    query)) {
                result.push(card)
            } else if (!cardCatalogModel
                       && (card.name ? card.name : "")
                       .toLocaleLowerCase().includes(query)) {
                result.push(card)
            }
        }
        return result
    }

    function selectedCardIdList() {
        return selectedOrder.slice()
    }

    function selectedCardForId(cardId) {
        for (let i = 0; i < cards.length; ++i) {
            if (cards[i].id === cardId)
                return cards[i]
        }
        return ({})
    }

    function cardSelected(cardId) {
        return selectedOrder.indexOf(cardId) >= 0
    }

    function contextCardIdList() {
        if (!contextCardId)
            return []
        if (cardSelected(contextCardId))
            return selectedCardIdList()
        return [contextCardId]
    }

    function toggleCard(cardId) {
        if (!cardId)
            return
        const order = selectedOrder.slice()
        const index = order.indexOf(cardId)
        if (index >= 0)
            order.splice(index, 1)
        else
            order.push(cardId)
        selectedOrder = order
    }

    function selectAllVisible() {
        const order = selectedOrder.slice()
        for (let i = 0; i < visibleCards.length; ++i) {
            if (order.indexOf(visibleCards[i].id) < 0)
                order.push(visibleCards[i].id)
        }
        selectedOrder = order
    }

    function moveSelectedCardInOrder(cardId, delta) {
        const next = selectedOrder.slice()
        const index = next.indexOf(cardId)
        const target = index + delta
        if (index < 0 || target < 0 || target >= next.length)
            return
        const value = next[index]
        next[index] = next[target]
        next[target] = value
        selectedOrder = next
    }

    function moveCardInOrder(cardId, delta) {
        const next = cards.slice()
        let index = -1
        for (let i = 0; i < next.length; ++i) {
            if (next[i].id === cardId) {
                index = i
                break
            }
        }
        const target = index + delta
        if (index < 0 || target < 0 || target >= next.length)
            return
        const value = next[index]
        next[index] = next[target]
        next[target] = value
        cards = next
        selectedIndex = target
    }

    function destinationOptions() {
        const options = [
            {"value": "hand",
             "label": localDisplayName + " · " + qsTr("Hand"),
             "seat": localSeat},
            {"value": "battlefield",
             "label": localDisplayName + " · " + qsTr("Battlefield"),
             "seat": localSeat},
            {"value": "graveyard",
             "label": localDisplayName + " · " + qsTr("Graveyard"),
             "seat": localSeat},
            {"value": "exile",
             "label": localDisplayName + " · " + qsTr("Exile"),
             "seat": localSeat}
        ]
        if (remoteSource) {
            options.push(
                {"value": "hand",
                 "label": sourceDisplayName + " · " + qsTr("Hand"),
                 "seat": sourceSeat},
                {"value": "battlefield",
                 "label": sourceDisplayName + " · " + qsTr("Battlefield"),
                 "seat": sourceSeat},
                {"value": "graveyard",
                 "label": sourceDisplayName + " · " + qsTr("Graveyard"),
                 "seat": sourceSeat},
                {"value": "exile",
                 "label": sourceDisplayName + " · " + qsTr("Exile"),
                 "seat": sourceSeat})
        }
        options.push(
            {"value": "library_top",
             "label": sourceDisplayName + " · " + qsTr("Top of library"),
             "seat": sourceSeat},
            {"value": "library_bottom",
             "label": sourceDisplayName + " · " + qsTr("Bottom of library"),
             "seat": sourceSeat})
        return options
    }

    function completeSearch(destination, destinationSeat, randomize,
                            requestedCardIds, faceDown) {
        const cardIds = requestedCardIds !== undefined
                        ? requestedCardIds : selectedCardIdList()
        if (cardIds.length === 0)
            return
        const position = destination === "battlefield"
                         ? {"x": 0.5, "y": 0.5} : ({})
        searchRequested(cardIds, destination,
                        faceDown === true ? false : revealToggle.checked,
                        randomize === true, position, sourceSeat, approvalId,
                        destinationSeat, faceDown === true)
        close()
    }

    function completeContextSearch(destination, destinationSeat, randomize,
                                   faceDown) {
        completeSearch(destination, destinationSeat, randomize,
                       contextCardIdList(), faceDown === true)
    }

    function saveTopOrder() {
        const cardIds = []
        for (let i = 0; i < cards.length; ++i)
            cardIds.push(cards[i].id)
        if (cardIds.length === 0)
            return
        reorderRequested(cardIds)
        close()
    }

    function resolveTopCards() {
        const selected = selectedCardIdList()
        const remainder = []
        for (let index = 0; index < cards.length; ++index) {
            if (selected.indexOf(cards[index].id) < 0)
                remainder.push(cards[index].id)
        }
        const destination = selected.length > 0
                            ? topDestinationBox.currentValue : ""
        resolveRequested(selected, remainder, destination,
                         remainderPlacementBox.currentValue,
                         randomizeRemainderToggle.checked,
                         destination === "battlefield"
                         && faceDownToggle.checked,
                         destination === "battlefield"
                         ? ({"x": 0.5, "y": 0.5}) : ({}),
                         sourceSeat, approvalId)
        close()
    }

    onClosed: {
        const remind = offerShuffleOnClose
        cards = []
        selectedIndex = -1
        sourceSeat = -1
        localSeat = -1
        sourceDisplayName = ""
        localDisplayName = ""
        approvalId = ""
        topCount = 0
        selectedOrder = []
        contextCardId = ""
        filterQuery = ""
        offerShuffleOnClose = false
        cardBrowser.resetFilter()
        if (remind)
            shuffleReminderRequested()
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(14)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(12)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(3)

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: root.reorderMode
                          ? qsTr("Arrange top cards")
                          : (root.topCardMode
                             ? qsTr("View top card")
                             : qsTr("Search library"))
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(20)
                    font.weight: Font.DemiBold
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: root.reorderMode
                          ? qsTr("Select cards to move to hand, battlefield, or the bottom of the library, then choose how the remaining cards return.")
                          : (root.topCardMode
                             ? qsTr("Only you can see this card. Right-click it to move it.")
                             : qsTr("Only you can see these cards. Use the checkboxes to select cards; click elsewhere on a card to preview it.")
                               + " " + qsTr("Right-click a card for move actions.")
                               + (root.offerShuffleOnClose
                                  ? " " + qsTr("Hexproof will remind you to shuffle after this search if the card effect requires it.")
                                  : ""))
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(11)
                    wrapMode: Text.WordWrap
                }
            }

            StatusPill {
                text: I18n.count("card", root.cards.length)
                statusColor: Theme.primary
            }

            AppButton {
                objectName: "closeLibrarySearchButton"
                compact: true
                variant: "ghost"
                text: "×"
                accessibleName: qsTr("Close")
                Layout.preferredWidth: Theme.size(40)
                onClicked: root.close()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.divider
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.size(16)

            LibrarySearchCardList {
                id: cardBrowser
                popupController: root
                cardMenu: libraryCardMenu
            }

            Rectangle {
                Layout.fillHeight: true
                implicitWidth: 1
                color: Theme.divider
            }

            ColumnLayout {
                Layout.preferredWidth: Theme.size(340)
                Layout.fillHeight: true
                spacing: Theme.size(12)

                Surface {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.surfaceMuted
                    clip: true

                    Image {
                        anchors.fill: parent
                        anchors.margins: Theme.size(12)
                        source: root.selectedCard.name && root.cardCatalogModel
                                ? root.cardCatalogModel.imageSource(
                                      root.selectedCard.name,
                                      root.selectedCard.setCode,
                                      root.selectedCard.collectorNumber)
                                : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: root.selectedCard.name ? root.selectedCard.name
                                                 : qsTr("Select a card")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(14)
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.reorderMode
                    spacing: Theme.size(7)

                    Text {
                        textFormat: Text.PlainText
                        text: qsTr("Move selected cards to")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(10)
                        font.weight: Font.DemiBold
                    }
                    AppComboBox {
                        id: topDestinationBox
                        objectName: "topCardsDestination"
                        Layout.fillWidth: true
                        model: [
                            {"label": qsTr("Hand"), "value": "hand"},
                            {"label": qsTr("Battlefield"), "value": "battlefield"},
                            {"label": qsTr("Bottom of library"), "value": "library_bottom"}
                        ]
                        textRole: "label"
                        valueRole: "value"
                        enabled: root.selectedCount > 0
                    }
                    AppToggle {
                        id: faceDownToggle
                        objectName: "topCardsFaceDown"
                        Layout.fillWidth: true
                        visible: topDestinationBox.currentValue === "battlefield"
                        enabled: root.selectedCount > 0
                        text: qsTr("Put onto battlefield face down")
                    }
                    Text {
                        textFormat: Text.PlainText
                        text: qsTr("Return remaining cards to")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(10)
                        font.weight: Font.DemiBold
                    }
                    AppComboBox {
                        id: remainderPlacementBox
                        objectName: "topCardsRemainderPlacement"
                        Layout.fillWidth: true
                        model: [
                            {"label": qsTr("Top of library"), "value": "top"},
                            {"label": qsTr("Bottom of library"), "value": "bottom"}
                        ]
                        textRole: "label"
                        valueRole: "value"
                    }
                    AppToggle {
                        id: randomizeRemainderToggle
                        objectName: "topCardsRandomizeRemainder"
                        Layout.fillWidth: true
                        text: qsTr("Randomize remaining cards")
                    }
                    StatusPill {
                        text: qsTr("Selected") + " · " + root.selectedCount
                        statusColor: Theme.primary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: !root.reorderMode && !root.topCardMode
                             && root.selectedCount > 1
                    spacing: Theme.size(5)

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: qsTr("Selected card order")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(10)
                        font.weight: Font.DemiBold
                    }
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: qsTr("Use the arrows to choose the order sent to the destination.")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(9)
                        wrapMode: Text.WordWrap
                    }
                    ListView {
                        id: selectedOrderList
                        objectName: "librarySelectedOrder"
                        Layout.fillWidth: true
                        Layout.preferredHeight:
                            Math.min(Theme.size(150),
                                     contentHeight)
                        model: root.selectedCardIdList()
                        spacing: Theme.size(3)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical:
                            ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Surface {
                            id: selectedOrderRow
                            required property string modelData
                            required property int index
                            readonly property var card:
                                root.selectedCardForId(modelData)
                            width: ListView.view.width
                            height: Theme.size(36)
                            radius: Theme.radiusSmall
                            color: Theme.surfaceMuted

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.size(8)
                                anchors.rightMargin: Theme.size(4)
                                spacing: Theme.size(4)

                                Text {
                                    textFormat: Text.PlainText
                                    Layout.preferredWidth:
                                        Theme.size(22)
                                    text: selectedOrderRow.index + 1
                                    color: Theme.textMuted
                                    font.pixelSize:
                                        Theme.fontSize(9)
                                }
                                Text {
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: selectedOrderRow.card.name
                                          ? selectedOrderRow.card.name : ""
                                    color: Theme.text
                                    font.pixelSize:
                                        Theme.fontSize(10)
                                    elide: Text.ElideRight
                                }
                                AppButton {
                                    compact: true
                                    variant: "ghost"
                                    text: "↑"
                                    enabled:
                                        selectedOrderRow.index > 0
                                    onClicked:
                                        root.moveSelectedCardInOrder(
                                            selectedOrderRow.modelData, -1)
                                }
                                AppButton {
                                    compact: true
                                    variant: "ghost"
                                    text: "↓"
                                    enabled: selectedOrderRow.index
                                             < root.selectedCount - 1
                                    onClicked:
                                        root.moveSelectedCardInOrder(
                                            selectedOrderRow.modelData, 1)
                                }
                            }
                        }
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Destination")
                    visible: !root.reorderMode && !root.topCardMode
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(10)
                    font.weight: Font.DemiBold
                }
                AppComboBox {
                    id: destinationBox
                    objectName: "libraryDestination"
                    Layout.fillWidth: true
                    model: root.destinations
                    textRole: "label"
                    valueRole: "value"
                    visible: !root.reorderMode && !root.topCardMode
                }

                AppToggle {
                    id: revealToggle
                    objectName: "revealLibrarySearch"
                    Layout.fillWidth: true
                    checked: true
                    text: qsTr("Reveal card name in the game log")
                    visible: !root.reorderMode && !root.topCardMode
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: revealToggle.checked
                          ? qsTr("Every viewer will see the selected card name in the log.")
                          : qsTr("The log will say “a card”; hidden-zone identities stay private.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(9)
                    wrapMode: Text.WordWrap
                    visible: !root.reorderMode && !root.topCardMode
                }

                AppButton {
                    objectName: "completeLibrarySearchButton"
                    Layout.fillWidth: true
                    visible: !root.topCardMode
                    variant: "primary"
                    text: root.reorderMode
                          ? qsTr("Resolve top cards")
                          : qsTr("Complete search")
                    enabled: root.reorderMode
                             ? root.cards.length > 0
                             : root.selectedCount > 0
                    onClicked: {
                        if (root.reorderMode) {
                            root.resolveTopCards()
                            return
                        }
                        const option =
                            root.destinations[destinationBox.currentIndex]
                        if (option)
                            root.completeSearch(option.value, option.seat,
                                                false)
                    }
                }
                StatusPill {
                    visible: !root.reorderMode && !root.topCardMode
                    text: qsTr("Selected") + " · " + root.selectedCount
                    statusColor: Theme.primary
                }
            }
        }
    }

    LibrarySearchContextMenu {
        id: libraryCardMenu
        popupController: root
    }
}
