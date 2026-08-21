// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    required property var tableController
    required property var publicZoneBrowserPopup

    function panelSlot(seat) {
        const seats = tableController.battlefieldSeats
                      ? tableController.battlefieldSeats : []
        let slot = 0
        for (let index = 0; index < seats.length; ++index) {
            const candidate = seats[index]
            if (!candidate
                    || candidate.seat
                       === tableController.roomSession.seatIndex) {
                continue
            }
            if (candidate.seat === seat)
                return slot
            ++slot
        }
        return slot
    }

    function battlefieldBounds(seat) {
        const bounds = tableController.battlefieldScene.seatBounds[seat]
        return bounds !== undefined ? bounds : ({})
    }

    anchors.fill: parent
    enabled: visible

    Repeater {
        model: root.tableController.battlefieldSeats
               ? root.tableController.battlefieldSeats : []

        delegate: BattlefieldOpponentZoneDock {
            required property var modelData

            tableController: root.tableController
            publicZoneBrowserPopup: root.publicZoneBrowserPopup
            seatData: modelData
            availableWidth: root.width
            availableHeight: root.height
            panelSlot: root.panelSlot(modelData.seat)
            battlefieldBounds: root.battlefieldBounds(modelData.seat)
            isOwn: modelData.seat
                   === root.tableController.roomSession.seatIndex
            expanded: !isOwn
                      && root.tableController.sharedZones.opponentZoneExpanded(
                          modelData.seat)
        }
    }
}
