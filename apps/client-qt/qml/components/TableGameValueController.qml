// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "Table"

import QtQuick

QtObject {
    id: root

    required property var tableRoot
    readonly property var phaseOrder: [
        "untap", "upkeep", "draw", "main_1", "begin_combat",
        "declare_attackers", "declare_blockers", "combat_damage",
        "end_combat", "main_2", "end"
    ]

    function displayedLife(player) {
        if (!player || player.seat === undefined)
            return 0
        const key = String(player.seat)
        if (Object.prototype.hasOwnProperty.call(
                    tableRoot.optimisticLifeTotals, key)) {
            return tableRoot.optimisticLifeTotals[key]
        }
        return player.life !== undefined ? player.life : 0
    }

    function setLife(value) {
        if (!tableRoot.canAct || tableRoot.roomSession.seatIndex < 0)
            return
        const key = String(tableRoot.roomSession.seatIndex)
        tableRoot.optimisticCommandModel.setValue("life", key, value)
        tableRoot.optimisticCommands.trackOptimisticValues("life", [key])
        tableRoot.wsModel.setCounter("life", value)
    }

    function displayedTapped(card) {
        if (!card || !card.id)
            return false
        if (Object.prototype.hasOwnProperty.call(
                    tableRoot.optimisticTappedCards, card.id)) {
            return tableRoot.optimisticTappedCards[card.id]
        }
        return card.tapped === true
    }

    function toggleTapped(card) {
        if (!tableRoot.canAct || !card || !card.id)
            return
        const tapped = !displayedTapped(card)
        tableRoot.optimisticCommandModel.setValue(
                    "tapped", card.id, tapped)
        tableRoot.optimisticCommands.trackOptimisticValues("tapped", [card.id])
        tableRoot.wsModel.setCardTapped(card.id, tapped)
    }

    function hasTappedOwnPermanent() {
        const cards = tableRoot.zoneState.zoneCardsForSeat(
                          tableRoot.roomSession.seatIndex, "battlefield")
        for (let index = 0; index < cards.length; ++index) {
            if (displayedTapped(cards[index]))
                return true
        }
        return false
    }

    function untapOwnBattlefield() {
        if (!tableRoot.canAct)
            return
        const cards = tableRoot.zoneState.zoneCardsForSeat(
                          tableRoot.roomSession.seatIndex, "battlefield")
        const trackedCardIds = []
        for (let index = 0; index < cards.length; ++index) {
            const card = cards[index]
            if (!card.id || !displayedTapped(card))
                continue
            tableRoot.optimisticCommandModel.setValue(
                        "tapped", card.id, false)
            trackedCardIds.push(card.id)
        }
        if (trackedCardIds.length === 0)
            return
        tableRoot.optimisticCommands.trackOptimisticValues("tapped", trackedCardIds)
        for (let index = 0; index < trackedCardIds.length; ++index)
            tableRoot.wsModel.setCardTapped(trackedCardIds[index], false)
    }

    function declaredAttackers() {
        const result = []
        const arrows = tableRoot.tableArrows
        for (let index = 0; index < arrows.length; ++index) {
            const arrow = arrows[index]
            if (arrow.kind !== "attack"
                    || arrow.seat !== tableRoot.roomSession.seatIndex)
                continue
            const card = tableRoot.gameTableModel.cardData(arrow.sourceCardId)
            if (card.id)
                result.push(card)
        }
        return result
    }

    function hasUntappedDeclaredAttacker() {
        const cards = declaredAttackers()
        for (let index = 0; index < cards.length; ++index) {
            if (!displayedTapped(cards[index]))
                return true
        }
        return false
    }

    function tapDeclaredAttackers() {
        if (!tableRoot.isActivePlayer
                || tableRoot.gameSession.currentPhase !== "declare_attackers")
            return
        const cards = declaredAttackers()
        const trackedCardIds = []
        for (let index = 0; index < cards.length; ++index) {
            if (!cards[index].id || displayedTapped(cards[index]))
                continue
            tableRoot.optimisticCommandModel.setValue(
                        "tapped", cards[index].id, true)
            trackedCardIds.push(cards[index].id)
        }
        if (trackedCardIds.length === 0)
            return
        tableRoot.optimisticCommands.trackOptimisticValues(
                    "tapped", trackedCardIds)
        for (let index = 0; index < trackedCardIds.length; ++index)
            tableRoot.wsModel.setCardTapped(trackedCardIds[index], true)
    }

    function displayedCounterValue(seat, counter) {
        const key = String(seat) + ":" + counter.key
        if (Object.prototype.hasOwnProperty.call(
                    tableRoot.optimisticCounterValues, key)) {
            return tableRoot.optimisticCounterValues[key]
        }
        return counter.value !== undefined ? counter.value : 0
    }

    function adjustCounter(seat, counter, delta) {
        if (!tableRoot.canAct
                || seat !== tableRoot.roomSession.seatIndex
                || !counter.key) {
            return
        }
        const key = String(seat) + ":" + counter.key
        tableRoot.optimisticCommandModel.setValue(
                    "counter", key,
                    displayedCounterValue(seat, counter) + delta)
        tableRoot.optimisticCommands.trackOptimisticValues("counter", [key])
        tableRoot.wsModel.adjustCounter(counter.key, delta)
    }

    function setCounter(counterKey, value) {
        if (!tableRoot.canAct
                || !counterKey
                || tableRoot.roomSession.seatIndex < 0) {
            return
        }
        const key = String(tableRoot.roomSession.seatIndex) + ":" + counterKey
        tableRoot.optimisticCommandModel.setValue("counter", key, value)
        tableRoot.optimisticCommands.trackOptimisticValues("counter", [key])
        tableRoot.wsModel.setCounter(counterKey, value)
    }

    function commanderCards(player) {
        if (!player || player.seat === undefined)
            return []
        const result = []
        const seen = ({})
        const identities = tableRoot.tableCommanders
                           ? tableRoot.tableCommanders : []
        for (let index = 0; index < identities.length; ++index) {
            const identity = identities[index]
            if (identity.ownerSeat !== player.seat || !identity.cardId)
                continue
            seen[identity.cardId] = true
            result.push({
                            "id": identity.cardId,
                            "name": identity.name,
                            "ownerSeat": identity.ownerSeat,
                            "commander": true
                        })
        }
        const zones = [
            tableRoot.zoneState.zoneCardsForSeat(player.seat, "command"),
            tableRoot.zoneState.zoneCardsForSeat(player.seat, "battlefield"),
            tableRoot.zoneState.zoneCardsForSeat(player.seat, "graveyard"),
            tableRoot.zoneState.zoneCardsForSeat(player.seat, "exile"),
            tableRoot.zoneState.zoneCardsForSeat(player.seat, "hand")
        ]
        for (let zoneIndex = 0; zoneIndex < zones.length; ++zoneIndex) {
            for (let index = 0; index < zones[zoneIndex].length; ++index) {
                const card = zones[zoneIndex][index]
                if ((zoneIndex === 0 || card.commander === true)
                        && card.id && !seen[card.id]) {
                    seen[card.id] = true
                    result.push(card)
                }
            }
        }
        const taxes = player.commanderTaxes ? player.commanderTaxes : ({})
        const ids = Object.keys(taxes)
        for (let index = 0; index < ids.length; ++index) {
            if (!seen[ids[index]])
                result.push({"id": ids[index], "commander": true})
        }
        return result
    }

    function commanderTaxDisplayName(card, index) {
        if (!card || !card.name)
            return qsTr("Commander") + " " + (index + 1)
        const name = String(card.name)
        const separator = name.indexOf(",")
        return separator > 0 ? name.slice(0, separator) : name
    }

    function displayedCommanderTax(player, commanderId) {
        if (!player || player.seat === undefined || !commanderId)
            return 0
        const key = String(player.seat) + ":" + commanderId
        if (Object.prototype.hasOwnProperty.call(
                    tableRoot.optimisticCommanderTax, key)) {
            return tableRoot.optimisticCommanderTax[key]
        }
        if (player.commanderTaxes
                && player.commanderTaxes[commanderId] !== undefined) {
            return player.commanderTaxes[commanderId]
        }
        return player.commanderTax !== undefined ? player.commanderTax : 0
    }

    function commanderTaxSummary(player) {
        const commanders = commanderCards(player)
        const values = []
        for (let index = 0; index < commanders.length; ++index) {
            values.push("+" + String(2 * displayedCommanderTax(
                            player, commanders[index].id)))
        }
        return values.length > 0 ? values.join(" / ") : "+0"
    }

    function adjustCommanderTax(commanderId, delta) {
        if (!tableRoot.canAct
                || tableRoot.roomSession.seatIndex < 0
                || !commanderId) {
            return
        }
        const player = tableRoot.seatState.seatData(tableRoot.roomSession.seatIndex)
        const key = String(tableRoot.roomSession.seatIndex) + ":" + commanderId
        tableRoot.optimisticCommandModel.setValue(
                    "tax", key,
                    Math.max(
                        0,
                        displayedCommanderTax(player, commanderId) + delta))
        tableRoot.optimisticCommands.trackOptimisticValues("tax", [key])
        tableRoot.wsModel.adjustCommanderTax(commanderId, delta)
    }

    function setPhase(phase) {
        if (!tableRoot.isActivePlayer || !phase)
            return
        tableRoot.optimisticCommandModel.beginPhase(phase)
        tableRoot.wsModel.setPhase(phase)
    }

    function advancePhase() {
        if (!tableRoot.isActivePlayer)
            return
        const currentIndex = phaseOrder.indexOf(tableRoot.displayedPhase)
        if (currentIndex < 0) {
            setPhase(phaseOrder[0])
        } else if (currentIndex < phaseOrder.length - 1) {
            setPhase(phaseOrder[currentIndex + 1])
        } else {
            advanceTurn()
        }
    }

    function advanceTurn() {
        if (!tableRoot.isActivePlayer)
            return
        tableRoot.optimisticCommandModel.beginPhase("untap")
        tableRoot.wsModel.nextTurn()
    }

    function reconcile() {
        reconcileLife()
        reconcileTapped()
        reconcileCounters()
        reconcileCommanderTax()
        if (tableRoot.optimisticPhase.length > 0
                && tableRoot.gameSession.currentPhase
                   === tableRoot.optimisticPhase) {
            tableRoot.optimisticCommands.clearOptimisticPhase()
        }
    }

    function reconcileLife() {
        const lifeSeats = Object.keys(tableRoot.optimisticLifeTotals)
        for (let index = 0; index < lifeSeats.length; ++index) {
            const key = lifeSeats[index]
            const player = tableRoot.seatState.seatData(Number(key))
            if (player.life === tableRoot.optimisticLifeTotals[key])
                tableRoot.optimisticCommandModel.removeValue("life", key)
        }
    }

    function reconcileTapped() {
        const cardIds = Object.keys(tableRoot.optimisticTappedCards)
        for (let index = 0; index < cardIds.length; ++index) {
            const cardId = cardIds[index]
            let reconciled = false
            for (let seatIndex = 0;
                 seatIndex < tableRoot.authoritativeSeats.length
                 && !reconciled;
                 ++seatIndex) {
                const cards = tableRoot.zoneState.zoneCardsForSeat(
                                  tableRoot.authoritativeSeats[seatIndex].seat,
                                  "battlefield")
                for (let cardIndex = 0;
                     cardIndex < cards.length;
                     ++cardIndex) {
                    if (cards[cardIndex].id === cardId
                            && (cards[cardIndex].tapped === true)
                               === tableRoot.optimisticTappedCards[cardId]) {
                        tableRoot.optimisticCommandModel.removeValue(
                                    "tapped", cardId)
                        reconciled = true
                        break
                    }
                }
            }
        }
    }

    function reconcileCounters() {
        const counterKeys = Object.keys(tableRoot.optimisticCounterValues)
        for (let index = 0; index < counterKeys.length; ++index) {
            const composite = counterKeys[index]
            const separator = composite.indexOf(":")
            const seat = Number(composite.slice(0, separator))
            const counterKey = composite.slice(separator + 1)
            const player = tableRoot.seatState.seatData(seat)
            const counters = player.counters ? player.counters : []
            for (let counterIndex = 0;
                 counterIndex < counters.length;
                 ++counterIndex) {
                if (counters[counterIndex].key === counterKey
                        && counters[counterIndex].value
                           === tableRoot.optimisticCounterValues[composite]) {
                    tableRoot.optimisticCommandModel.removeValue(
                                "counter", composite)
                    break
                }
            }
        }
    }

    function reconcileCommanderTax() {
        const taxKeys = Object.keys(tableRoot.optimisticCommanderTax)
        for (let index = 0; index < taxKeys.length; ++index) {
            const key = taxKeys[index]
            const separator = key.indexOf(":")
            const player = tableRoot.seatState.seatData(
                               Number(key.slice(0, separator)))
            const commanderId = key.slice(separator + 1)
            if (player.commanderTaxes
                    && player.commanderTaxes[commanderId]
                       === tableRoot.optimisticCommanderTax[key]) {
                tableRoot.optimisticCommandModel.removeValue("tax", key)
            }
        }
    }
}
