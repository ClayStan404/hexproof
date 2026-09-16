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
    property string topRemainderDestination: "library_top"
    property bool topRemainderFaceDown: false
    property string topSelectionAnchor: ""
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
    readonly property var topCardRows: groupedTopCardRows()
    readonly property int topRemainderCount:
        cards.filter(card => !topCardAssignments[card.id]).length
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
        topCardAssignments = ({})
        topRemainderDestination = "library_top"
        topRemainderFaceDown = false
        topSelectionAnchor = ""
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

    function invalidate() {
        // A grant belongs to one game. Invalidation is not a completed search
        // and must not offer to shuffle the replacement game's library.
        offerShuffleOnClose = false
        cards = []
        approvalId = ""
        selectedIndex = -1
        selectedOrder = []
        topCardAssignments = ({})
        contextCardId = ""
        close()
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

    function destinationOptions() {
        const options = [
            {"value": "hand",
             "label": qsTr("Hand") + " · " + localDisplayName,
             "seat": localSeat},
            {"value": "battlefield",
             "label": qsTr("Battlefield") + " · " + localDisplayName,
             "seat": localSeat},
            {"value": "graveyard",
             "label": qsTr("Graveyard") + " · " + localDisplayName,
             "seat": localSeat},
            {"value": "exile",
             "label": qsTr("Exile") + " · " + localDisplayName,
             "seat": localSeat}
        ]
        if (remoteSource) {
            options.push(
                {"value": "hand",
                 "label": qsTr("Hand") + " · " + sourceDisplayName,
                 "seat": sourceSeat},
                {"value": "battlefield",
                 "label": qsTr("Battlefield") + " · " + sourceDisplayName,
                 "seat": sourceSeat},
                {"value": "graveyard",
                 "label": qsTr("Graveyard") + " · " + sourceDisplayName,
                 "seat": sourceSeat},
                {"value": "exile",
                 "label": qsTr("Exile") + " · " + sourceDisplayName,
                 "seat": sourceSeat})
        }
        options.push(
            {"value": "library_top",
             "label": qsTr("Top of library") + " · " + sourceDisplayName,
             "seat": sourceSeat},
            {"value": "library_bottom",
             "label": qsTr("Bottom of library") + " · " + sourceDisplayName,
             "seat": sourceSeat})
        return options
    }

    function topCardDestinationOptions() {
        return [
            {"value": "hand",
             "label": qsTr("Hand") + " · " + localDisplayName},
            {"value": "battlefield",
             "label": qsTr("Battlefield") + " · " + localDisplayName},
            {"value": "graveyard",
             "label": qsTr("Graveyard") + " · " + sourceDisplayName},
            {"value": "exile",
             "label": qsTr("Exile") + " · " + sourceDisplayName},
            {"value": "library_top",
             "label": qsTr("Top of library") + " · " + sourceDisplayName},
            {"value": "library_bottom",
             "label": qsTr("Bottom of library") + " · " + sourceDisplayName}
        ]
    }

    function topCardAssignment(cardId) {
        const assignment = topCardAssignments[cardId]
        return assignment ? assignment : ({
            "toZone": topRemainderDestination,
            "faceDown": topRemainderDestination === "battlefield"
                        && topRemainderFaceDown
        })
    }

    function topDestinationLabel(destination) {
        const option = topCardDestinations.find(option => option.value === destination)
        return option ? option.label : ""
    }

    function groupedTopCardRows() {
        const rows = []
        const groups = ["library_top", "hand", "battlefield", "graveyard",
                        "exile", "library_bottom"]
        for (const destination of groups) {
            const group = []
            for (let index = 0; index < cards.length; ++index) {
                if (topCardAssignment(cards[index].id).toZone === destination) {
                    group.push({"card": cards[index], "sourceIndex": index,
                                "destination": destination, "groupIndex": group.length})
                }
            }
            for (const row of group) {
                row.groupSize = group.length
                rows.push(row)
            }
        }
        return rows
    }

    function topGroupCount(destination) {
        return topCardRows.filter(row => row.destination === destination).length
    }

    function topGroupRandomized(destination) {
        return (destination === "library_top" && inspector.randomizeTop)
               || (destination === "library_bottom" && inspector.randomizeBottom)
    }

    function selectTopCard(cardId, range) {
        const ids = topCardRows.map(row => row.card.id)
        const target = ids.indexOf(cardId)
        if (target < 0)
            return
        const anchor = ids.indexOf(topSelectionAnchor)
        if (range && anchor >= 0) {
            const next = selectedOrder.slice()
            for (let index = Math.min(anchor, target); index <= Math.max(anchor, target); ++index) {
                if (next.indexOf(ids[index]) < 0)
                    next.push(ids[index])
            }
            selectedOrder = next
        } else {
            toggleCard(cardId)
            topSelectionAnchor = cardId
        }
    }

    function invertTopSelection() {
        selectedOrder = topCardRows.map(row => row.card.id)
                                  .filter(cardId => !cardSelected(cardId))
        topSelectionAnchor = ""
    }

    function setTopRemainderDestination(destination) {
        if (!topCardDestinations.some(option => option.value === destination))
            return
        topRemainderDestination = destination
        if (destination !== "battlefield")
            topRemainderFaceDown = false
    }

    function assignTopCards(cardIds, destination, faceDown) {
        if (!reorderMode || !topCardDestinations.some(option => option.value === destination))
            return
        const next = Object.assign({}, topCardAssignments)
        for (const cardId of cardIds) {
            if (!selectedCardForId(cardId).id)
                continue
            next[cardId] = {
                "toZone": destination,
                "faceDown": destination === "battlefield"
                            && (faceDown === undefined
                                ? topCardAssignment(cardId).faceDown === true
                                : faceDown === true)
            }
        }
        topCardAssignments = next
    }

    function useRemainderForTopCards(cardIds) {
        const next = Object.assign({}, topCardAssignments)
        for (const cardId of cardIds)
            delete next[cardId]
        topCardAssignments = next
    }

    function moveTopCardRelative(cardId, targetId, after) {
        if (!selectedCardForId(cardId).id || !selectedCardForId(targetId).id
            || cardId === targetId)
            return
        const destination = topCardAssignment(cardId).toZone
        if (topCardAssignment(targetId).toZone !== destination
            || topGroupRandomized(destination))
            return
        const group = cards.filter(card => topCardAssignment(card.id).toZone === destination)
        const card = group.splice(group.findIndex(card => card.id === cardId), 1)[0]
        group.splice(group.findIndex(card => card.id === targetId) + (after ? 1 : 0), 0, card)
        const previewId = selectedCard.id
        let groupIndex = 0
        // Replace only this group's slots, preserving every other group's order.
        cards = cards.map(card => topCardAssignment(card.id).toZone === destination
                                 ? group[groupIndex++] : card)
        selectedIndex = cards.findIndex(card => card.id === previewId)
    }

    function moveTopCardInGroup(cardId, delta) {
        const destination = topCardAssignment(cardId).toZone
        const group = cards.filter(card => topCardAssignment(card.id).toZone === destination)
        const target = group.findIndex(card => card.id === cardId) + delta
        if (target >= 0 && target < group.length)
            moveTopCardRelative(cardId, group[target].id, delta > 0)
    }

    function setTopCardDestination(cardId, destination) {
        assignTopCards([cardId], destination)
    }

    function setTopCardFaceDown(cardId, faceDown) {
        const current = topCardAssignment(cardId)
        assignTopCards([cardId], current.toZone, faceDown)
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
                        topCount === 0 && faceDown !== true && inspector.reveal,
                        randomize === true, position, sourceSeat, approvalId,
                        destinationSeat, faceDown === true)
        close()
    }

    function completeContextSearch(destination, destinationSeat, randomize,
                                   faceDown) {
        if (reorderMode) {
            assignTopCards(contextCardIdList(), destination, faceDown === true)
            if (destination === "library_top")
                inspector.randomizeTop = randomize === true
            else if (destination === "library_bottom")
                inspector.randomizeBottom = randomize === true
            return
        }
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
        topRemainderDestination = "library_top"
        topRemainderFaceDown = false
        topSelectionAnchor = ""
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
                    elide: Text.ElideRight
                    text: root.reorderMode
                          ? qsTr("Arrange top cards")
                          : (root.topCardMode
                             ? qsTr("View top card")
                             : qsTr("Search library"))
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(20)
                    font.weight: Font.DemiBold
                }
                ScrollView {
                    id: instructionsScroll
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(instructions.implicitHeight, Theme.size(40))
                    contentWidth: availableWidth
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    Text {
                        id: instructions
                        textFormat: Text.PlainText
                        width: instructionsScroll.availableWidth
                        text: root.reorderMode
                              ? qsTr("Select cards to assign together; the rest follow the remainder destination. Drag the handle or use arrows to reorder cards within a destination.")
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
                visible: !root.reorderMode
                popupController: root
                cardMenu: libraryCardMenu
            }

            LibraryTopCardsView {
                visible: root.reorderMode
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
