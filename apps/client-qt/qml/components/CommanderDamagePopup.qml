// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "Table"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

AppPopup {
    id: root

    required property var tableController
    property string pendingCommanderId: ""
    property int pendingTargetSeat: -1
    property bool pendingRecordsCombatDamage: false

    width: Math.min(Theme.size(760), parent.width - Theme.size(48))
    height: Math.min(Theme.size(680), parent.height - Theme.size(48))
    padding: Theme.size(22)

    function seatData(seat) {
        return tableController.seatState.seatData(seat)
    }

    function commanderDamage(commanderId, targetSeat) {
        const entries = tableController.tableCommanderDamage
                        ? tableController.tableCommanderDamage : []
        for (let index = 0; index < entries.length; ++index) {
            if (entries[index].commanderId === commanderId
                    && entries[index].targetSeat === targetSeat) {
                return entries[index].value
            }
        }
        return 0
    }

    function commanderControllerSeat(commanderId, ownerSeat) {
        const visibleSeat = tableController.gameTableModel.visibleZoneSeat(
                              commanderId, "battlefield")
        return visibleSeat >= 0 ? visibleSeat : ownerSeat
    }

    function canCorrect(commander, targetSeat) {
        if (!tableController.canAct)
            return false
        const ownSeat = tableController.roomSession.seatIndex
        return ownSeat === commander.ownerSeat
                || ownSeat === commanderControllerSeat(
                    commander.cardId, commander.ownerSeat)
                || ownSeat === targetSeat
    }

    function canRecord(commander, targetSeat) {
        if (!tableController.canAct)
            return false
        const ownSeat = tableController.roomSession.seatIndex
        const controllerSeat = commanderControllerSeat(
                                 commander.cardId, commander.ownerSeat)
        return ownSeat === controllerSeat && targetSeat !== controllerSeat
    }

    function showExactEditor(commander, targetSeat) {
        pendingCommanderId = commander.cardId
        pendingTargetSeat = targetSeat
        pendingRecordsCombatDamage = false
        damageEditor.titleText = qsTranslate("Table", "Set commander damage")
        damageEditor.message = qsTranslate("Table", "This corrects the public damage total without changing life.")
        damageEditor.confirmText = qsTranslate("Table", "Set")
        damageEditor.showFor(commanderDamage(commander.cardId, targetSeat))
    }

    function showRecordEditor(commander, targetSeat) {
        pendingCommanderId = commander.cardId
        pendingTargetSeat = targetSeat
        pendingRecordsCombatDamage = true
        damageEditor.titleText = qsTranslate("Table", "Record commander combat damage")
        damageEditor.message = qsTranslate("Table", "The same amount is subtracted from life and added to this commander's public damage total.")
        damageEditor.confirmText = qsTranslate("Table", "Record")
        damageEditor.showFor(1)
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(14)

        AppPopupHeader {
            titleText: qsTranslate("Table", "Commander damage")
            subtitleText: qsTranslate("Table", "Totals are tracked per physical commander. Reaching 21 is a reminder, not an automatic loss.")
            showClose: true
            onCloseRequested: root.close()
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.divider
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth

            Column {
                width: parent.width
                spacing: Theme.size(10)

                Repeater {
                    model: root.tableController.tableCommanders
                           ? root.tableController.tableCommanders : []

                    delegate: Surface {
                        id: commanderGroup
                        required property var modelData
                        required property int index
                        width: parent ? parent.width : 0
                        implicitHeight: commanderContent.implicitHeight
                                        + Theme.size(20)
                        color: Theme.surfaceMuted
                        border.width: 1
                        border.color: Theme.border

                        ColumnLayout {
                            id: commanderContent
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Theme.size(10)
                            spacing: Theme.size(7)

                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: root.tableController.gameValues.commanderDisplayName(
                                          commanderGroup.modelData, commanderGroup.index) + " · "
                                      + qsTranslate("Table", "Owner: %1").arg(
                                          root.seatData(
                                              commanderGroup.modelData.ownerSeat).displayName)
                                color: Theme.text
                                font.pixelSize: Theme.fontSize(13)
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Repeater {
                                model: root.tableController.authoritativeSeats

                                delegate: RowLayout {
                                    id: damageRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: Theme.size(6)
                                    readonly property int damage:
                                        root.commanderDamage(
                                            commanderGroup.modelData.cardId,
                                            modelData.seat)

                                    Text {
                                        textFormat: Text.PlainText
                                        Layout.fillWidth: true
                                        text: damageRow.modelData.displayName
                                        color: Theme.textSecondary
                                        font.pixelSize: Theme.fontSize(11)
                                        elide: Text.ElideRight
                                    }

                                    AppButton {
                                        compact: true
                                        variant: "ghost"
                                        Layout.preferredWidth: Theme.size(34)
                                        text: "−"
                                        enabled: damageRow.damage > 0
                                                 && root.canCorrect(
                                                     commanderGroup.modelData,
                                                     damageRow.modelData.seat)
                                        accessibleName: qsTranslate("Table", "Decrease commander damage")
                                        onClicked:
                                            root.tableController.wsModel.setCommanderDamage(
                                                commanderGroup.modelData.cardId,
                                                damageRow.modelData.seat,
                                                -1, false, false)
                                    }

                                    AppButton {
                                        objectName: "commanderDamageValue-"
                                                    + commanderGroup.modelData.cardId
                                                    + "-" + damageRow.modelData.seat
                                        compact: true
                                        variant: damageRow.damage >= 21
                                                 ? "danger" : "secondary"
                                        Layout.preferredWidth: Theme.size(62)
                                        text: String(damageRow.damage)
                                        enabled: root.canCorrect(
                                                     commanderGroup.modelData,
                                                     damageRow.modelData.seat)
                                        onClicked: root.showExactEditor(
                                                       commanderGroup.modelData,
                                                       damageRow.modelData.seat)
                                        ToolTip.visible: hovered
                                        ToolTip.text: damageRow.damage >= 21
                                                      ? qsTranslate("Table", "21 or more commander combat damage. Check whether this player has lost.")
                                                      : qsTranslate("Table", "Set exact commander damage")
                                    }

                                    AppButton {
                                        compact: true
                                        variant: "ghost"
                                        Layout.preferredWidth: Theme.size(34)
                                        text: "+"
                                        enabled: root.canCorrect(
                                                     commanderGroup.modelData,
                                                     damageRow.modelData.seat)
                                        accessibleName: qsTranslate("Table", "Increase commander damage")
                                        onClicked:
                                            root.tableController.wsModel.setCommanderDamage(
                                                commanderGroup.modelData.cardId,
                                                damageRow.modelData.seat,
                                                1, false, false)
                                    }

                                    AppButton {
                                        compact: true
                                        variant: "primary"
                                        Layout.preferredWidth: Theme.size(118)
                                        text: qsTranslate("Table", "Record damage…")
                                        enabled: root.canRecord(
                                                     commanderGroup.modelData,
                                                     damageRow.modelData.seat)
                                        onClicked: root.showRecordEditor(
                                                       commanderGroup.modelData,
                                                       damageRow.modelData.seat)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    NumberInputPopup {
        id: damageEditor
        objectName: "commanderDamageEditor"
        minimumValue: root.pendingRecordsCombatDamage ? 1 : 0
        maximumValue: 2147483647
        placeholderText: qsTranslate("Table", "Damage")
        onValueRequested: value => {
            root.tableController.wsModel.setCommanderDamage(
                        root.pendingCommanderId,
                        root.pendingTargetSeat,
                        value,
                        !root.pendingRecordsCombatDamage,
                        root.pendingRecordsCombatDamage)
        }
    }
}
