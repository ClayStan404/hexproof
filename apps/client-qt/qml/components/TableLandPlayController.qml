// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: root

    required property var tableRoot
    required property var popup
    property var pendingCard: ({})

    readonly property int authoritativeCount:
        tableRoot.gameTableModel.landPlaysThisTurn
    readonly property int displayedCount:
        tableRoot.optimisticCommands.displayedLandPlayCount(
            authoritativeCount)

    function normalizedFaces(card) {
        const catalogFaces = tableRoot.presentation.availableCardFaces(card)
        const result = []
        if (catalogFaces.length === 0) {
            result.push({
                "faceName": "",
                "displayName": card.name ? card.name : "",
                "typeLine": tableRoot.cardMoveCommands.resolvedTypeLine(card)
            })
            return result
        }
        for (let index = 0; index < catalogFaces.length; ++index) {
            const face = catalogFaces[index]
            const faceName = face.faceName !== undefined
                             ? face.faceName : (face.name ? face.name : "")
            const preview = Object.assign({}, card, {"faceName": faceName})
            result.push({
                "faceName": faceName,
                "displayName": face.displayName
                               ? face.displayName : faceName,
                "typeLine": face.typeLine
                            ? face.typeLine
                            : tableRoot.cardMoveCommands.resolvedTypeLine(preview)
            })
        }
        return result
    }

    function requestSelectedHandCard() {
        const card = tableRoot.selectedHandCard
        if (!tableRoot.isActivePlayer || !card || !card.id)
            return
        pendingCard = Object.assign({}, card)
        popup.showFor(
                    pendingCard, normalizedFaces(pendingCard),
                    displayedCount, tableRoot.displayedPhase,
                    tableRoot.stackCards.length)
    }

    function commit(faceName) {
        const card = pendingCard
        pendingCard = ({})
        if (!tableRoot.isActivePlayer || !card || !card.id
                || displayedCount >= 2147483647)
            return
        const selectedFaceName = faceName ? faceName : ""
        const previewCard = Object.assign(
                                {}, card, {"faceName": selectedFaceName})
        const seat = tableRoot.roomSession.seatIndex
        const position = tableRoot.cardMoveCommands.smartBattlefieldPosition(
                             seat, previewCard, card.id)
        tableRoot.cardMoveCommands.beginBattlefieldPreviewForCard(
                    card.id, "hand", seat, previewCard, seat,
                    position.x, position.y)
        tableRoot.optimisticCommands.beginLandPlayCount(displayedCount + 1)
        tableRoot.wsModel.playLand(
                    card.id, {"x": position.x, "y": position.y},
                    selectedFaceName)
        tableRoot.selectedHandCard = ({})
    }

    function cancel() {
        pendingCard = ({})
    }

    function adjustCount(delta) {
        if (!tableRoot.isActivePlayer || delta === 0)
            return
        const next = Math.max(
                         0, Math.min(2147483647, displayedCount + delta))
        if (next === displayedCount)
            return
        tableRoot.optimisticCommands.beginLandPlayCount(next)
        tableRoot.wsModel.setLandPlayCount(next)
    }
}
