// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "Table"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    required property var tableController
    property string pendingCommanderId: ""
    property int pendingTargetSeat: -1
    property bool pendingRecordsCombatDamage: false

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(760), parent.width - Theme.size(48))
    height: Math.min(Theme.size(680), parent.height - Theme.size(48))
    padding: Theme.size(22)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    Overlay.modal: Rectangle { color: Theme.modalScrim }

    background: Rectangle {
        color: Theme.surfaceElevated
        radius: Theme.radiusLarge
        border.width: 1
        border.color: Theme.borderStrong
    }

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
        damageEditor.titleText = qsTr("Set commander damage")
        damageEditor.message = qsTr("This corrects the public damage total without changing life.")
        damageEditor.confirmText = qsTr("Set")
        damageEditor.showFor(commanderDamage(commander.cardId, targetSeat))
    }

    function showRecordEditor(commander, targetSeat) {
        pendingCommanderId = commander.cardId
        pendingTargetSeat = targetSeat
        pendingRecordsCombatDamage = true
        damageEditor.titleText = qsTr("Record commander combat damage")
        damageEditor.message = qsTr("The same amount is subtracted from life and added to this commander's public damage total.")
        damageEditor.confirmText = qsTr("Record")
        damageEditor.showFor(1)
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(14)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(10)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(2)

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Commander damage")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(21)
                    font.weight: Font.DemiBold
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Totals are tracked per physical commander. Reaching 21 is a reminder, not an automatic loss.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(10)
                    wrapMode: Text.WordWrap
                }
            }

            AppButton {
                compact: true
                variant: "ghost"
                text: "×"
                accessibleName: qsTr("Close")
                onClicked: root.close()
            }
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
                                text: commanderGroup.modelData.name + " · "
                                      + qsTr("Owner: %1").arg(
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
                                        accessibleName: qsTr("Decrease commander damage")
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
                                                      ? qsTr("21 or more commander combat damage. Check whether this player has lost.")
                                                      : qsTr("Set exact commander damage")
                                    }

                                    AppButton {
                                        compact: true
                                        variant: "ghost"
                                        Layout.preferredWidth: Theme.size(34)
                                        text: "+"
                                        enabled: root.canCorrect(
                                                     commanderGroup.modelData,
                                                     damageRow.modelData.seat)
                                        accessibleName: qsTr("Increase commander damage")
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
                                        text: qsTr("Record damage…")
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
        placeholderText: qsTr("Damage")
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
