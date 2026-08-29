// SPDX-License-Identifier: GPL-3.0-or-later
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
    property var topCardAssignments: ({})
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
    readonly property var topCardDestinations: topCardDestinationOptions()
    signal searchRequested(var cardIds, string destination, bool reveal,
                           bool randomize, var position, int sourceSeat,
                           string approvalId, int destinationSeat,
                           bool faceDown)
    signal resolveAssignmentsRequested(var assignments, bool randomizeTop,
                                       bool randomizeBottom, var position,
                                       int sourceSeat, string approvalId)
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
        const assignments = ({})
        if (topCount > 1) {
            for (let index = 0; index < cards.length; ++index) {
                assignments[cards[index].id] = {
                    "toZone": "library_top",
                    "faceDown": false
                }
            }
        }
        topCardAssignments = assignments
        contextCardId = ""
        filterQuery = ""
        cardBrowser.resetFilter()
        inspector.resetControls()
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

    function topCardDestinationOptions() {
        return [
            {"value": "hand",
             "label": localDisplayName + " · " + qsTr("Hand")},
            {"value": "battlefield",
             "label": localDisplayName + " · " + qsTr("Battlefield")},
            {"value": "graveyard",
             "label": sourceDisplayName + " · " + qsTr("Graveyard")},
            {"value": "exile",
             "label": sourceDisplayName + " · " + qsTr("Exile")},
            {"value": "library_top",
             "label": sourceDisplayName + " · " + qsTr("Top of library")},
            {"value": "library_bottom",
             "label": sourceDisplayName + " · " + qsTr("Bottom of library")}
        ]
    }

    function topCardAssignment(cardId) {
        const assignment = topCardAssignments[cardId]
        return assignment ? assignment : ({
            "toZone": "library_top",
            "faceDown": false
        })
    }

    function topCardDestinationIndex(cardId) {
        const destination = topCardAssignment(cardId).toZone
        for (let index = 0; index < topCardDestinations.length; ++index) {
            if (topCardDestinations[index].value === destination)
                return index
        }
        return 0
    }

    function setTopCardDestination(cardId, destination) {
        if (!cardId || !destination)
            return
        const current = topCardAssignment(cardId)
        const next = Object.assign({}, topCardAssignments)
        next[cardId] = {
            "toZone": destination,
            "faceDown": destination === "battlefield"
                        && current.faceDown === true
        }
        topCardAssignments = next
    }

    function setTopCardFaceDown(cardId, faceDown) {
        if (!cardId)
            return
        const current = topCardAssignment(cardId)
        const next = Object.assign({}, topCardAssignments)
        next[cardId] = {
            "toZone": current.toZone,
            "faceDown": current.toZone === "battlefield"
                        && faceDown === true
        }
        topCardAssignments = next
    }

    function topCardAssignmentList() {
        const assignments = []
        for (let index = 0; index < cards.length; ++index) {
            const assignment = topCardAssignment(cards[index].id)
            assignments.push({
                "cardId": cards[index].id,
                "toZone": assignment.toZone,
                "faceDown": assignment.toZone === "battlefield"
                            && assignment.faceDown === true
            })
        }
        return assignments
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
                        faceDown === true ? false : inspector.reveal,
                        randomize === true, position, sourceSeat, approvalId,
                        destinationSeat, faceDown === true)
        close()
    }

    function completeContextSearch(destination, destinationSeat, randomize,
                                   faceDown) {
        completeSearch(destination, destinationSeat, randomize,
                       contextCardIdList(), faceDown === true)
    }

    function resolveTopCards() {
        const assignments = topCardAssignmentList()
        if (assignments.length === 0)
            return
        let hasBattlefield = false
        for (let index = 0; index < assignments.length; ++index) {
            if (assignments[index].toZone === "battlefield") {
                hasBattlefield = true
                break
            }
        }
        resolveAssignmentsRequested(
                    assignments, inspector.randomizeTop,
                    inspector.randomizeBottom,
                    hasBattlefield ? ({"x": 0.5, "y": 0.5}) : ({}),
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
        topCardAssignments = ({})
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
                          ? qsTr("Choose a destination for every viewed card. Use the arrows to set the relative order of cards returning to the same end of the library.")
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

            LibrarySearchInspector {
                id: inspector
                popupController: root
            }
        }
    }

    LibrarySearchContextMenu {
        id: libraryCardMenu
        popupController: root
    }
}
