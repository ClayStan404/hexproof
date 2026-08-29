// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: root

    required property var tableRoot

    property var selectedHandCard: ({})
    property int selectedCounterSeat: -1
    property string selectedCounterKey: ""
    property string pendingLibraryApprovalId: ""
    property string pendingLibraryRequesterName: ""
    property int pendingLibraryTopCount: 0
    property string libraryMoveDestination: ""
    property string pendingPublicZoneMoveApprovalId: ""
    property string pendingPublicZoneMoveRequesterName: ""
    property string pendingPublicZoneMoveSourceZone: ""
    property int pendingPublicZoneMoveCardCount: 0
    property string pendingPublicZoneMoveToZone: ""

    function setLibraryApproval(approvalId, requesterName, topCount) {
        pendingLibraryApprovalId = approvalId ? approvalId : ""
        pendingLibraryRequesterName = requesterName ? requesterName : ""
        pendingLibraryTopCount = topCount ? Math.max(0, topCount) : 0
    }

    function clearPendingLibraryApproval() {
        pendingLibraryApprovalId = ""
        pendingLibraryRequesterName = ""
        pendingLibraryTopCount = 0
    }

    function setPublicZoneMoveApproval(approvalId, requesterName,
                                       sourceZone, cardCount, toZone) {
        pendingPublicZoneMoveApprovalId = approvalId ? approvalId : ""
        pendingPublicZoneMoveRequesterName = requesterName ? requesterName : ""
        pendingPublicZoneMoveSourceZone = sourceZone ? sourceZone : ""
        pendingPublicZoneMoveCardCount = Math.max(0, cardCount ? cardCount : 0)
        pendingPublicZoneMoveToZone = toZone ? toZone : ""
    }

    function clearPendingPublicZoneMoveApproval() {
        pendingPublicZoneMoveApprovalId = ""
        pendingPublicZoneMoveRequesterName = ""
        pendingPublicZoneMoveSourceZone = ""
        pendingPublicZoneMoveCardCount = 0
        pendingPublicZoneMoveToZone = ""
    }

    function clearCounterSelection() {
        selectedCounterSeat = -1
        selectedCounterKey = ""
    }

    function clearLibraryMoveDestination() {
        libraryMoveDestination = ""
    }

    function handContainsSelectedCard() {
        if (!selectedHandCard.id)
            return true
        const hand = tableRoot.ownHand ? tableRoot.ownHand : []
        for (let index = 0; index < hand.length; ++index) {
            if (hand[index].id === selectedHandCard.id) {
                selectedHandCard = hand[index]
                return true
            }
        }
        return false
    }

    function counterSelectionStillExists() {
        if (selectedCounterSeat < 0 || selectedCounterKey.length === 0)
            return true
        const player = tableRoot.seatState.seatData(selectedCounterSeat)
        const counters = player.counters ? player.counters : []
        for (let index = 0; index < counters.length; ++index) {
            if (counters[index].key === selectedCounterKey)
                return true
        }
        return false
    }

    function reconcile() {
        if (!handContainsSelectedCard())
            selectedHandCard = ({})
        if (!counterSelectionStillExists())
            clearCounterSelection()
        if (tableRoot.wsModel.inRoom === false
                || tableRoot.roomSession.phase !== "started") {
            clearPendingLibraryApproval()
            clearPendingPublicZoneMoveApproval()
            clearLibraryMoveDestination()
        }
    }

    function reset() {
        selectedHandCard = ({})
        clearCounterSelection()
        clearPendingLibraryApproval()
        clearPendingPublicZoneMoveApproval()
        clearLibraryMoveDestination()
    }
}
