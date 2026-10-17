// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    required property var presentation
    readonly property var tableController: presentation.tableController
    readonly property real unit: presentation.unit
    readonly property var seatOrder: presentation.playerSeats
    readonly property int nearSeat: presentation.bottomSeat
    readonly property real gap: 6 * unit
    readonly property real seam: presentation.phaseTrackVisible ? 22 * unit : gap
    readonly property real fieldHeight: Math.max(0, (height - seam) / 2)
    objectName: "forgeMultiplayerBattlefield"

    function relativeSeat(seat) {
        const index = seatOrder.indexOf(seat)
        const nearIndex = Math.max(0, seatOrder.indexOf(nearSeat))
        return (index - nearIndex + seatOrder.length) % Math.max(1, seatOrder.length)
    }
    function fieldFor(seat) {
        for (let index = 0; index < fields.count; ++index) {
            const field = fields.itemAt(index) as ForgePlayerField
            if (field && field.seat === seat) return field
        }
        return null
    }
    function pointFor(id, target) {
        for (let index = 0; index < fields.count; ++index) {
            const field = fields.itemAt(index) as ForgePlayerField
            if (!field) continue
            const point = field.pointFor(id, target)
            if (point.x !== 0) return point
        }
        return Qt.point(0, 0)
    }
    function playerPoint(seat, target) {
        const field = fieldFor(seat)
        if (!field) return Qt.point(0, 0)
        void field.x; void field.y; void field.width; void field.height
        return field.playerPoint(target)
    }
    function reveal(id) {
        for (let index = 0; index < fields.count; ++index) {
            const field = fields.itemAt(index) as ForgePlayerField
            if (field && field.reveal(id)) return true
        }
        return false
    }
    Repeater {
        id: fields
        model: root.presentation.multiplayer ? root.tableController.rulesSession.players : null
        delegate: ForgePlayerField {
            readonly property int position: root.relativeSeat(seat)
            // Follow the engine's seat order around the table, starting at
            // the viewer's lower-left seat. A three-seat near field spans both columns.
            readonly property bool lowerRow: position === 0 || root.seatOrder.length === 4 && position === 1
            readonly property bool rightColumn: root.seatOrder.length === 4
                ? position === 1 || position === 2 : position === 1
            presentation: root.presentation
            nearSide: lowerRow
            x: rightColumn ? (root.width + root.gap) / 2 : 0
            y: lowerRow ? root.fieldHeight + root.seam : 0
            width: position === 0 && root.seatOrder.length === 3
                ? root.width : (root.width - root.gap) / 2
            height: root.fieldHeight
        }
    }
}
