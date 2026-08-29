// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "Table"

import QtQuick

QtObject {
    id: root

    required property var tableRoot
    required property var warningDialog
    required property var combatPopup

    property string pendingNavigationAction: ""
    property string pendingPhase: ""
    property string warningTitle: ""
    property string warningMessage: ""
    property string warningConfirmText: qsTr("Continue")

    function possibleLoss(player) {
        return player && player.seat !== undefined
                && tableRoot.gameValues.displayedLife(player) <= 0
    }

    function oversizedHand(player) {
        return player && player.handCount !== undefined
                && Number(player.handCount) > 7
    }

    function emptyLibrary(player) {
        return player && player.libraryCount !== undefined
                && Number(player.libraryCount) <= 0
    }

    function holdPlayerNames() {
        const result = []
        const seats = tableRoot.authoritativeSeats
                      ? tableRoot.authoritativeSeats : []
        for (let index = 0; index < seats.length; ++index) {
            if (seats[index].responseStatus === "hold") {
                result.push(seats[index].displayName
                            ? seats[index].displayName
                            : qsTr("Seat") + " " + (seats[index].seat + 1))
            }
        }
        return result
    }

    function navigationWarnings(endingTurn) {
        const warnings = []
        if (tableRoot.stackCards.length > 0) {
            warnings.push(qsTr("The shared stack still contains %1 card(s).")
                          .arg(tableRoot.stackCards.length))
        }
        const holdNames = holdPlayerNames()
        if (holdNames.length > 0) {
            warnings.push(qsTr("These players are still waiting: %1.")
                          .arg(holdNames.join(", ")))
        }
        if (endingTurn && oversizedHand(tableRoot.ownSeatData)) {
            warnings.push(qsTr("Your hand contains %1 cards; the usual maximum hand size is 7.")
                          .arg(tableRoot.ownSeatData.handCount))
        }
        return warnings
    }

    function showNavigationWarning(action, phase, warnings) {
        pendingNavigationAction = action
        pendingPhase = phase ? phase : ""
        warningTitle = action === "turn"
                     ? qsTr("End the turn anyway?")
                     : qsTr("Advance the phase anyway?")
        warningMessage = warnings.join("\n\n")
                         + "\n\n"
                         + qsTr("Card effects may override these reminders; Hexproof will not enforce them.")
        warningConfirmText = action === "turn"
                           ? qsTr("End turn") : qsTr("Advance")
        warningDialog.open()
    }

    function requestSetPhase(phase) {
        if (!tableRoot.isActivePlayer || !phase
                || phase === tableRoot.displayedPhase) {
            return
        }
        const warnings = navigationWarnings(false)
        if (warnings.length === 0) {
            tableRoot.gameValues.setPhase(phase)
            return
        }
        showNavigationWarning("phase", phase, warnings)
    }

    function requestAdvancePhase() {
        if (!tableRoot.isActivePlayer)
            return
        if (tableRoot.displayedPhase === "end") {
            requestAdvanceTurn()
            return
        }
        const warnings = navigationWarnings(false)
        if (warnings.length === 0) {
            tableRoot.gameValues.advancePhase()
            return
        }
        showNavigationWarning("next_phase", "", warnings)
    }

    function requestAdvanceTurn() {
        if (!tableRoot.isActivePlayer)
            return
        const warnings = navigationWarnings(true)
        if (warnings.length === 0) {
            tableRoot.gameValues.advanceTurn()
            return
        }
        showNavigationWarning("turn", "", warnings)
    }

    function confirmPendingNavigation() {
        const action = pendingNavigationAction
        const phase = pendingPhase
        pendingNavigationAction = ""
        pendingPhase = ""
        if (action === "phase")
            tableRoot.gameValues.setPhase(phase)
        else if (action === "next_phase")
            tableRoot.gameValues.advancePhase()
        else if (action === "turn")
            tableRoot.gameValues.advanceTurn()
    }

    function cancelPendingNavigation() {
        pendingNavigationAction = ""
        pendingPhase = ""
    }

    function combatCard(cardId) {
        const source = tableRoot.zoneState.cardDataForId(cardId)
        const card = Object.assign({}, source)
        card.tapped = tableRoot.gameValues.displayedTapped(source)
        const typeLine = tableRoot.cardMoveCommands.resolvedTypeLine(card)
        const lowerType = String(typeLine).toLocaleLowerCase()
        card.assistTypeLine = typeLine
        card.assistCreature = lowerType.includes("creature")
                              || lowerType.includes("生物")
        return card
    }

    function combatTargetLabel(targetCardId, targetSeat) {
        if (targetSeat >= 0) {
            const player = tableRoot.seatState.seatData(targetSeat)
            return player.displayName
                   ? player.displayName
                   : qsTr("Seat") + " " + (targetSeat + 1)
        }
        const card = tableRoot.zoneState.cardDataForId(targetCardId)
        return card.name ? card.name : qsTr("Battlefield permanent")
    }

    function requestCombatDeclaration(kind, sourceCardIds,
                                      targetCardId, targetSeat) {
        if (!tableRoot.canAct || !sourceCardIds
                || sourceCardIds.length === 0) {
            return
        }
        const cards = []
        for (let index = 0; index < sourceCardIds.length; ++index) {
            const card = combatCard(sourceCardIds[index])
            if (card.id)
                cards.push(card)
        }
        if (cards.length !== sourceCardIds.length)
            return
        combatPopup.showFor(
                    kind, cards,
                    targetCardId ? targetCardId : "",
                    targetSeat !== undefined ? targetSeat : -1,
                    combatTargetLabel(targetCardId, targetSeat))
        tableRoot.selection.endRelationTarget()
    }

    function commitCombatDeclaration(kind, sourceCardIds,
                                     targetCardId, targetSeat,
                                     tappedSourceCardIds) {
        const tapped = tappedSourceCardIds ? tappedSourceCardIds : []
        for (let index = 0; index < tapped.length; ++index) {
            tableRoot.optimisticCommandModel.setValue(
                        "tapped", tapped[index], true)
        }
        if (tapped.length > 0) {
            tableRoot.optimisticCommands.trackOptimisticValues(
                        "tapped", tapped)
        }
        tableRoot.wsModel.setCombatArrows(
                    sourceCardIds, kind, targetCardId,
                    targetSeat, tapped)
        tableRoot.selection.clear()
    }
}
