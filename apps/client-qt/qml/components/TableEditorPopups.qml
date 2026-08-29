// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "Table"

import QtQuick

Item {
    id: root

    required property var tableController
    anchors.fill: parent
    property alias librarySearchPopup: librarySearchPopup
    property alias shuffleLibraryReminder: shuffleReminder
    property alias publicZoneBrowser: publicZoneBrowser
    property alias lifeEditor: lifeEditor
    property alias drawCardsEditor: drawCardsEditor
    property alias libraryTopCountEditor: libraryTopCountEditor
    property alias libraryMoveCardsEditor: libraryMoveCardsEditor
    property alias counterLabelEditor: counterLabelEditor
    property alias playerCounterValueEditor: playerCounterValueEditor
    property alias cardCounterEditor: cardCounterEditor
    property alias cardFacePicker: cardFacePicker
    property alias libraryPositionEditor: libraryPositionEditor
    property alias handLibraryPositionEditor: handLibraryPositionEditor
    property alias tokenPicker: tokenPicker
    property alias commanderDamagePopup: commanderDamagePopup

    function libraryCardsForIds(cardIds, faceDown) {
        const requested = cardIds ? cardIds : []
        const available = librarySearchPopup.cards
                          ? librarySearchPopup.cards : []
        const result = []
        for (let idIndex = 0; idIndex < requested.length; ++idIndex) {
            for (let cardIndex = 0; cardIndex < available.length;
                 ++cardIndex) {
                if (available[cardIndex].id !== requested[idIndex])
                    continue
                result.push(faceDown === true
                            ? Object.assign(
                                  {}, available[cardIndex],
                                  {"faceDown": true})
                            : available[cardIndex])
                break
            }
        }
        return result
    }

    function libraryBattlefieldCardsForAssignments(assignments) {
        const requested = assignments ? assignments : []
        const available = librarySearchPopup.cards
                          ? librarySearchPopup.cards : []
        const result = []
        for (let assignmentIndex = 0;
             assignmentIndex < requested.length; ++assignmentIndex) {
            const assignment = requested[assignmentIndex]
            if (assignment.toZone !== "battlefield")
                continue
            for (let cardIndex = 0; cardIndex < available.length;
                 ++cardIndex) {
                if (available[cardIndex].id !== assignment.cardId)
                    continue
                result.push(assignment.faceDown === true
                            ? Object.assign({}, available[cardIndex],
                                            {"faceDown": true})
                            : available[cardIndex])
                break
            }
        }
        return result
    }

    LibrarySearchPopup {
        id: librarySearchPopup
        objectName: "librarySearchPopup"
        cardCatalogModel: root.tableController.cardCatalogModel
        onSearchRequested: function(cardIds, destination, reveal, randomize,
                                    position, sourceSeat, approvalId,
                                    destinationSeat, faceDown) {
            const resolvedPosition = destination === "battlefield"
                                     ? root.tableController.cardMoveCommands.smartBattlefieldAnchor(
                                           destinationSeat,
                                           root.libraryCardsForIds(
                                               cardIds, faceDown))
                                     : position
            root.tableController.wsModel.searchLibraryCards(
                        cardIds, destination, reveal, randomize,
                        resolvedPosition,
                        sourceSeat, approvalId, destinationSeat, faceDown)
        }
        onResolveAssignmentsRequested: function(assignments, randomizeTop,
                                                randomizeBottom, position,
                                                sourceSeat, approvalId) {
            const battlefieldCards =
                root.libraryBattlefieldCardsForAssignments(assignments)
            const resolvedPosition = battlefieldCards.length > 0
                                     ? root.tableController.cardMoveCommands.smartBattlefieldAnchor(
                                           root.tableController.roomSession.seatIndex,
                                           battlefieldCards)
                                     : position
            root.tableController.wsModel.resolveLibraryViewAssignments(
                        assignments, randomizeTop, randomizeBottom,
                        resolvedPosition, sourceSeat, approvalId)
        }
        onShuffleReminderRequested: {
            Qt.callLater(function() {
                if (root.tableController.canAct)
                    shuffleReminder.open()
            })
        }
    }

    ConfirmDialog {
        id: shuffleReminder
        objectName: "shuffleLibraryReminder"
        titleText: qsTr("Shuffle your library?")
        message: qsTr("Searching a library does not shuffle it automatically. Shuffle now if the card effect requires it.")
        confirmText: qsTr("Shuffle")
        onConfirmed: root.tableController.wsModel.shuffleLibrary()
    }

    ZoneBrowserPopup {
        id: publicZoneBrowser
        objectName: "publicZoneBrowserPopup"
        cardCatalogModel: root.tableController.cardCatalogModel
        canMoveCards: root.tableController.canAct
        localSeatIndex: root.tableController.roomSession.seatIndex
        cards: root.tableController.zoneState.zoneCardsForSeat(seatIndex, zoneKey)
        onMoveRequested: function(cardId, fromZone, fromSeat,
                                  toZone, toSeat) {
            root.tableController.cardMoveCommands.movePublicZoneCard(cardId, fromZone, fromSeat,
                                    toZone, toSeat)
        }
        onMovesRequested: function(cardIds, fromZone, fromSeat,
                                   toZone, toSeat) {
            root.tableController.cardMoveCommands.movePublicZoneCards(cardIds, fromZone, fromSeat,
                                     toZone, toSeat)
        }
        onCastCommanderRequested: commanderId =>
            root.tableController.wsModel.castCommander(commanderId)
    }

    LifeEditorPopup {
        id: lifeEditor
        objectName: "lifeEditorPopup"
        onLifeRequested: value => root.tableController.gameValues.setLife(value)
    }

    CommanderDamagePopup {
        id: commanderDamagePopup
        objectName: "commanderDamagePopup"
        tableController: root.tableController
    }

    NumberInputPopup {
        id: drawCardsEditor
        objectName: "drawCardsPopup"
        titleText: qsTr("Draw multiple cards")
        message: qsTr("Enter how many cards to draw from your library.")
        placeholderText: qsTr("Number of cards")
        confirmText: qsTr("Draw")
        minimumValue: 1
        maximumValue: Math.max(1, Math.min(
                                   1000, root.tableController.ownSeatData.libraryCount))
        onValueRequested: value => root.tableController.wsModel.drawCards(value)
    }

    NumberInputPopup {
        id: libraryTopCountEditor
        objectName: "libraryTopCountPopup"
        property int sourceSeat: -1
        property int sourceLibraryCount: 0

        function showForLibrary(seat, count, value) {
            sourceSeat = seat
            sourceLibraryCount = count
            showFor(value)
        }

        titleText: qsTr("View top cards")
        message: qsTr("Enter how many cards to view.")
        placeholderText: qsTr("Number of cards")
        confirmText: qsTr("View")
        minimumValue: 1
        maximumValue: Math.max(1, Math.min(
                                   1000, sourceLibraryCount))
        onValueRequested: value =>
            root.tableController.wsModel.dumpLibrary(sourceSeat, value)
    }

    NumberInputPopup {
        id: libraryMoveCardsEditor
        objectName: "libraryMoveCardsPopup"
        titleText: root.tableController.libraryMoveDestination === "exile"
                   ? qsTr("Put cards into exile")
                   : qsTr("Put cards into graveyard")
        message: qsTr("Enter how many cards to move from the top of your library.")
        placeholderText: qsTr("Number of cards")
        confirmText: qsTr("Move")
        minimumValue: 1
        maximumValue: Math.max(1, Math.min(
                                   1000, root.tableController.ownSeatData.libraryCount))
        onValueRequested: value => {
            root.tableController.wsModel.moveLibraryCards(value,
                                          root.tableController.libraryMoveDestination)
            root.tableController.transientState.clearLibraryMoveDestination()
        }
        onClosed: root.tableController.transientState.clearLibraryMoveDestination()
    }

    CounterLabelPopup {
        id: counterLabelEditor
        objectName: "counterLabelPopup"
        onLabelRequested: (counterKey, label) =>
            root.tableController.wsModel.renameCounter(counterKey, label)
    }

    NumberInputPopup {
        id: playerCounterValueEditor
        objectName: "playerCounterValuePopup"
        titleText: qsTr("Set counter value")
        message: qsTr("Enter an exact number for the selected counter.")
        placeholderText: qsTr("Counter value")
        confirmText: qsTr("Set")
        minimumValue: -2147483648
        maximumValue: 2147483647
        onValueRequested: value =>
            root.tableController.gameValues.setCounter(root.tableController.selectedCounterKey, value)
    }

    CardCounterEditor {
        id: cardCounterEditor
        objectName: "cardCounterEditor"
        onCounterRequested: function(counterId, kind, label, value) {
            root.tableController.wsModel.setCardCounter(
                        root.tableController.selectedBattlefieldCardId,
                        {
                            "counterId": counterId,
                            "kind": kind,
                            "label": label,
                            "value": value
                        })
        }
    }

    CardFacePicker {
        id: cardFacePicker
        objectName: "cardFacePicker"
        cardCatalogModel: root.tableController.cardCatalogModel
        onFaceSelected: faceName => root.tableController.cardMoveCommands.finishCardFaceSelection(faceName)
    }

    LibraryPositionPopup {
        id: libraryPositionEditor
        objectName: "libraryPositionEditor"
        onPositionRequested: function(position) {
            root.tableController.cardMoveCommands.moveSelectedBattlefieldToLibrary("index", position - 1)
        }
    }

    LibraryPositionPopup {
        id: handLibraryPositionEditor
        objectName: "handLibraryPositionEditor"
        onPositionRequested: function(position) {
            root.tableController.cardMoveCommands.moveSelectedHandToLibrary("index", position - 1)
        }
    }

    TokenPicker {
        id: tokenPicker
        objectName: "tokenPicker"
        catalogModel: root.tableController.cardCatalogModel
        preferredTokens: root.tableController.deckLibraryModel
                         ? root.tableController.deckLibraryModel.activeMatchTokens : []
        onTokenSelected: function(token) {
            const seat = root.tableController.roomSession.seatIndex
            root.tableController.wsModel.createToken(
                        token,
                        root.tableController.cardMoveCommands.smartBattlefieldPosition(
                            seat, token, ""))
        }
    }
}
