// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: root

    required property var gameTableModel
    function seatData(seatIndex) {
        // Subscribe QML bindings to snapshotChanged before using the indexed
        // lookup, whose return value does not itself carry a notify signal.
        const snapshotSeats = gameTableModel.seats
        return gameTableModel.seatData(seatIndex)
    }
}
