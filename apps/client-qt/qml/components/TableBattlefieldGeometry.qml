// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

QtObject {
    id: root

    required property var tableRoot
    property real transientOverviewCardScale: 0
    property real transientFocusCardScale: 0
    readonly property bool overviewScaleMode:
        tableRoot.usesEDHBattlefieldLayout
        && tableRoot.battlefieldSeats.length >= 3
        && !tableRoot.edhFocusLayout
    readonly property real automaticCardScale:
        overviewScaleMode
        ? (tableRoot.battlefieldSeats.length >= 4 ? 0.7 : 0.8)
        : 1.0
    readonly property real storedOverviewCardScale: {
        const preferences = tableRoot.preferencesModel
        return preferences
                && preferences.tableOverviewCardScale !== undefined
                ? preferences.tableOverviewCardScale
                : transientOverviewCardScale
    }
    readonly property real storedFocusCardScale: {
        const preferences = tableRoot.preferencesModel
        return preferences
                && preferences.tableFocusCardScale !== undefined
                ? preferences.tableFocusCardScale
                : transientFocusCardScale
    }
    readonly property real manualCardScale:
        overviewScaleMode ? storedOverviewCardScale : storedFocusCardScale
    readonly property bool automaticCardScaleEnabled: manualCardScale <= 0
    readonly property real cardScale:
        automaticCardScaleEnabled ? automaticCardScale : manualCardScale

    function normalizedCardScale(scale) {
        if (!Number.isFinite(scale) || scale <= 0)
            return 0
        return Math.max(0.5, Math.min(1.25,
                                     Math.round(scale * 20) / 20))
    }

    function setCardScale(scale) {
        const normalized = normalizedCardScale(scale)
        const preferences = tableRoot.preferencesModel
        if (overviewScaleMode) {
            if (preferences
                    && preferences.tableOverviewCardScale !== undefined) {
                preferences.tableOverviewCardScale = normalized
            } else {
                transientOverviewCardScale = normalized
            }
            return
        }
        if (preferences && preferences.tableFocusCardScale !== undefined)
            preferences.tableFocusCardScale = normalized
        else
            transientFocusCardScale = normalized
    }

    function adjustCardScale(delta) {
        if (!Number.isFinite(delta) || delta === 0)
            return
        setCardScale(cardScale + (delta > 0 ? 0.05 : -0.05))
    }

    function resetCardScale() {
        setCardScale(0)
    }

    function focusSeat(seatIndex) {
        if (seatIndex < 0)
            return
        tableRoot.edhFocusedSeat = seatIndex
        tableRoot.edhBattlefieldLayout = "focus"
    }

    function toggleFocusSeat(seatIndex) {
        if (seatIndex < 0)
            return
        if (tableRoot.edhFocusLayout
                && effectiveFocusSeat() === seatIndex) {
            tableRoot.edhBattlefieldLayout = "grid"
            return
        }
        focusSeat(seatIndex)
    }

    function effectiveFocusSeat() {
        if (tableRoot.edhFocusedSeat >= 0) {
            for (let index = 0;
                 index < tableRoot.battlefieldSeats.length; ++index) {
                if (tableRoot.battlefieldSeats[index].seat
                    === tableRoot.edhFocusedSeat) {
                    return tableRoot.edhFocusedSeat
                }
            }
        }
        if (tableRoot.roomSession.role === "player"
            && tableRoot.roomSession.seatIndex >= 0) {
            return tableRoot.roomSession.seatIndex
        }
        return tableRoot.battlefieldSeats.length > 0
             ? tableRoot.battlefieldSeats[0].seat : -1
    }

    function focusSmallIndex(seatIndex) {
        const focusSeat = effectiveFocusSeat()
        let smallIndex = 0
        for (let index = 0;
             index < tableRoot.battlefieldSeats.length; ++index) {
            const seat = tableRoot.battlefieldSeats[index].seat
            if (seat === focusSeat)
                continue
            if (seat === seatIndex)
                return smallIndex
            ++smallIndex
        }
        return 0
    }

    function focusLaneCount() {
        return Math.max(1, tableRoot.battlefieldSeats.length - 1)
    }

    function overviewWideSeat() {
        if (tableRoot.battlefieldSeats.length !== 3)
            return -1
        if (tableRoot.roomSession.role === "player"
                && tableRoot.roomSession.seatIndex >= 0) {
            return tableRoot.roomSession.seatIndex
        }
        return tableRoot.battlefieldSeats[2].seat
    }

    function overviewRow(seatIndex, modelIndex) {
        if (tableRoot.battlefieldSeats.length === 3)
            return seatIndex === overviewWideSeat() ? 1 : 0
        return Math.floor(modelIndex / 2)
    }

    function overviewColumn(seatIndex, modelIndex) {
        if (tableRoot.battlefieldSeats.length === 3)
            return seatIndex === overviewWideSeat() ? 0 : modelIndex
        return modelIndex % 2
    }

    function overviewColumnSpan(seatIndex) {
        return tableRoot.battlefieldSeats.length === 3
                && seatIndex === overviewWideSeat() ? 2 : 1
    }

    function focusRow(seatIndex) {
        return seatIndex === effectiveFocusSeat()
             ? 0 : focusSmallIndex(seatIndex)
    }

    function focusColumn(seatIndex) {
        return seatIndex === effectiveFocusSeat() ? 0 : 3
    }

    function battlefieldSeatModelIndex(seatIndex) {
        for (let index = 0;
             index < tableRoot.battlefieldSeats.length; ++index) {
            if (tableRoot.battlefieldSeats[index].seat === seatIndex)
                return index
        }
        return -1
    }

    function isTopOverviewSeat(seatIndex) {
        const modelIndex = battlefieldSeatModelIndex(seatIndex)
        const seatCount = tableRoot.battlefieldSeats.length
        if (modelIndex < 0 || seatCount <= 1)
            return false
        if (tableRoot.usesEDHBattlefieldLayout && seatCount === 3)
            return seatIndex !== overviewWideSeat()
        return modelIndex < Math.ceil(seatCount / 2)
    }

    function mirrorsSeat(seatIndex) {
        return isTopOverviewSeat(seatIndex)
    }

    function yForView(seatIndex, value, fallback) {
        const coordinate = value !== undefined ? value : fallback
        return mirrorsSeat(seatIndex) ? 1 - coordinate : coordinate
    }

    function positionFromView(seatIndex, normalizedX, normalizedY) {
        const x = Math.max(0, Math.min(1, normalizedX))
        const y = Math.max(0, Math.min(1, normalizedY))
        if (!mirrorsSeat(seatIndex))
            return {"x": x, "y": y}
        return {"x": x, "y": 1 - y}
    }
}
