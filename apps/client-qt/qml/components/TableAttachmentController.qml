// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: root

    required property var tableRoot

    readonly property var crossLaneStacks: {
        const attachments = tableRoot.tableAttachments
                            ? tableRoot.tableAttachments : []
        const seats = tableRoot.gameTableModel.seats
        void seats
        const stacksByTarget = ({})
        const result = []
        for (let index = 0; index < attachments.length; ++index) {
            const attachment = attachments[index]
            const sourceSeat = tableRoot.gameTableModel.visibleZoneSeat(
                                 attachment.sourceCardId, "battlefield")
            const targetSeat = tableRoot.gameTableModel.visibleZoneSeat(
                                 attachment.targetCardId, "battlefield")
            if (sourceSeat < 0 || targetSeat < 0
                    || sourceSeat === targetSeat)
                continue
            const stackIndex = stacksByTarget[attachment.targetCardId] || 0
            stacksByTarget[attachment.targetCardId] = stackIndex + 1
            result.push({
                            "sourceCardId": attachment.sourceCardId,
                            "targetCardId": attachment.targetCardId,
                            "sourceSeat": sourceSeat,
                            "targetSeat": targetSeat,
                            "stackIndex": stackIndex,
                            "card": tableRoot.zoneState.cardDataForId(
                                        attachment.sourceCardId)
                        })
        }
        return result
    }

    function selectedOwnedByLocal() {
        if (!tableRoot.canAct
                || tableRoot.selection.selectedCount() !== 1)
            return false
        const card = tableRoot.selectedBattlefieldCard
        if (!card || !card.id)
            return false
        const owner = card.ownerSeat !== undefined
                      ? Number(card.ownerSeat)
                      : tableRoot.selectedBattlefieldOwnerSeat
        return owner === tableRoot.roomSession.seatIndex
    }

    function canAttachSelected() {
        return selectedOwnedByLocal()
    }

    function canDetachSelected() {
        if (!selectedOwnedByLocal())
            return false
        const attachment = tableRoot.gameTableModel.attachmentForSource(
                             tableRoot.selectedBattlefieldCardId)
        return !!(attachment && attachment.targetCardId)
    }

    function beginAttach() {
        if (!canAttachSelected())
            return
        tableRoot.selection.beginRelationTarget("attach")
    }

    function detachSelected() {
        if (!canDetachSelected())
            return
        tableRoot.wsModel.setAttachment(tableRoot.selectedBattlefieldCardId)
        tableRoot.selection.clear()
    }

    function hidesHomeLaneCard(cardId, seatIndex) {
        const attachment = tableRoot.gameTableModel.attachmentForSource(cardId)
        if (!attachment || !attachment.targetCardId)
            return false
        const targetSeat = tableRoot.gameTableModel.visibleZoneSeat(
                             attachment.targetCardId, "battlefield")
        return targetSeat >= 0 && targetSeat !== seatIndex
    }

    function isAttachmentSource(cardId) {
        const attachment = tableRoot.gameTableModel.attachmentForSource(cardId)
        return !!(attachment && attachment.sourceCardId)
    }

    function attachmentStackPosition(base, stackIndex) {
        const step = stackIndex + 1
        return {
            "x": Math.max(0, Math.min(1, base.x + 0.04 * step)),
            "y": Math.max(0, Math.min(1, base.y + 0.05 * step))
        }
    }
}
