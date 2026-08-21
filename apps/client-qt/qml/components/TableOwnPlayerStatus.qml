// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "Table"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

RowLayout {
    id: root

    required property var tableController
    Layout.fillWidth: true
    Layout.minimumHeight: Theme.size(28)
    Layout.preferredHeight: Theme.size(28)
    Layout.maximumHeight: Theme.size(28)
    spacing: Theme.size(5)

    Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: root.tableController.ownSeatData.displayName
              ? root.tableController.ownSeatData.displayName
              : qsTr("You")
        color: Theme.text
        font.pixelSize: Theme.fontSize(11)
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }

    StatusPill {
        objectName: "ownMulliganCount"
        visible: root.tableController.ownSeatData.mulliganCount > 0
        text: qsTr("Mulligan %1").arg(
                  root.tableController.ownSeatData.mulliganCount)
        statusColor: Theme.textMuted
    }

    Repeater {
        model: root.tableController.ownSeatData.counters
               ? root.tableController.ownSeatData.counters.slice(
                     0, root.tableController.visibleCounterCount)
               : []
        delegate: PlayerCounterPip {
            required property var modelData
            required property int index
            objectName: "playerCounterPip"
                        + root.tableController.roomSession.seatIndex
                        + "-" + index
            Layout.preferredWidth: Theme.size(31)
            Layout.preferredHeight: Theme.size(28)
            counterKey: modelData.key
            label: modelData.label
            value: root.tableController.gameValues.displayedCounterValue(
                       root.tableController.roomSession.seatIndex,
                       modelData)
            editable: root.tableController.canAct
            selected:
                root.tableController.selectedCounterSeat
                === root.tableController.roomSession.seatIndex
                && root.tableController.selectedCounterKey
                   === modelData.key
            pipColor: [
                "#FFF196", "#9696FF", "#969696",
                "#FA9696", "#96FF96", "#F2F6F2",
                "#FF961E"
            ][index]
            onAdjustRequested: delta =>
                root.tableController.gameValues.adjustCounter(
                    root.tableController.roomSession.seatIndex,
                    modelData, delta)
            onSelectedRequested: {
                root.tableController.selectedCounterSeat =
                    root.tableController.roomSession.seatIndex
                root.tableController.selectedCounterKey =
                    modelData.key
            }
        }
    }
    Repeater {
        model: root.tableController.ownCommanderCards
        delegate: Rectangle {
            id: commanderTaxGroup
            required property var modelData
            required property int index
            objectName: index === 0
                        ? "commanderTaxControls" + root.tableController.roomSession.seatIndex
                        : "commanderTaxControls" + root.tableController.roomSession.seatIndex + "-" + index
            Layout.minimumWidth: Theme.size(108)
            Layout.preferredWidth: Theme.size(
                                       root.tableController.hasPartnerCommanders
                                       ? 124 : 150)
            Layout.preferredHeight: Theme.size(28)
            radius: Theme.radiusSmall
            color: index === 0
                   ? Theme.primaryMuted
                   : Theme.accentMuted
            border.width: 1
            border.color: index === 0
                          ? Theme.primary
                          : Theme.accent

            HoverHandler { id: commanderTaxHover }
            ToolTip.visible:
                commanderTaxHover.hovered
            ToolTip.text:
                qsTr("Commander tax") + " · "
                + root.tableController.gameValues.commanderTaxDisplayName(
                    commanderTaxGroup.modelData,
                    commanderTaxGroup.index) + "\n"
                + qsTr("Command-zone casts: %1 · Additional cost: +%2")
                  .arg(root.tableController.gameValues.displayedCommanderTax(
                           root.tableController.ownSeatData,
                           commanderTaxGroup.modelData.id))
                  .arg(2 * root.tableController.gameValues.displayedCommanderTax(
                           root.tableController.ownSeatData,
                           commanderTaxGroup.modelData.id))

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.size(4)
                anchors.rightMargin: Theme.size(2)
                spacing: Theme.size(1)

                Text {
                    textFormat: Text.PlainText
                    objectName: commanderTaxGroup.index === 0
                                ? "commanderTaxLabel" + root.tableController.roomSession.seatIndex
                                : "commanderTaxLabel" + root.tableController.roomSession.seatIndex + "-" + commanderTaxGroup.index
                    Layout.fillWidth: true
                    Layout.minimumWidth: Theme.size(20)
                    text: qsTr("Tax") + " · "
                          + root.tableController.gameValues.commanderTaxDisplayName(
                              commanderTaxGroup.modelData,
                              commanderTaxGroup.index)
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(9)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                AppButton {
                    objectName: commanderTaxGroup.index === 0
                                ? "decreaseCommanderTaxButton" + root.tableController.roomSession.seatIndex
                                : "decreaseCommanderTaxButton" + root.tableController.roomSession.seatIndex + "-" + commanderTaxGroup.index
                    compact: true
                    variant: "ghost"
                    Layout.preferredWidth: Theme.size(28)
                    Layout.minimumWidth: Theme.size(24)
                    implicitHeight: Theme.size(26)
                    text: "−"
                    accessibleName: qsTr("Decrease commander cast count")
                    enabled: root.tableController.canAct
                             && root.tableController.gameValues.displayedCommanderTax(root.tableController.ownSeatData, commanderTaxGroup.modelData.id) > 0
                    onClicked: root.tableController.gameValues.adjustCommanderTax(
                                   commanderTaxGroup.modelData.id, -1)
                }
                Text {
                    textFormat: Text.PlainText
                    objectName: commanderTaxGroup.index === 0
                                ? "commanderTaxValue" + root.tableController.roomSession.seatIndex
                                : "commanderTaxValue" + root.tableController.roomSession.seatIndex + "-" + commanderTaxGroup.index
                    Layout.preferredWidth: Theme.size(18)
                    text: String(
                              2 * root.tableController.gameValues.displayedCommanderTax(
                                  root.tableController.ownSeatData,
                                  commanderTaxGroup.modelData.id))
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(13)
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                }
                AppButton {
                    objectName: commanderTaxGroup.index === 0
                                ? "increaseCommanderTaxButton" + root.tableController.roomSession.seatIndex
                                : "increaseCommanderTaxButton" + root.tableController.roomSession.seatIndex + "-" + commanderTaxGroup.index
                    compact: true
                    variant: "ghost"
                    Layout.preferredWidth: Theme.size(28)
                    Layout.minimumWidth: Theme.size(24)
                    implicitHeight: Theme.size(26)
                    text: "+"
                    accessibleName: qsTr("Increase commander cast count")
                    enabled: root.tableController.canAct
                    onClicked: root.tableController.gameValues.adjustCommanderTax(
                                   commanderTaxGroup.modelData.id, 1)
                }
            }
        }
    }
    AppButton {
        objectName: "decreaseLifeButton"
                    + root.tableController.roomSession.seatIndex
        compact: true
        variant: "ghost"
        Layout.preferredWidth: Theme.size(28)
        Layout.minimumWidth: Theme.size(24)
        implicitHeight: Theme.size(26)
        visible: root.tableController.roomSession.role === "player"
        text: "−"
        accessibleName: qsTr("Decrease life")
        enabled: root.tableController.canAct
                 && root.tableController.gameValues.displayedLife(
                     root.tableController.ownSeatData)
                    > -2147483648
        onClicked: root.tableController.gameValues.setLife(
                       root.tableController.gameValues.displayedLife(
                           root.tableController.ownSeatData) - 1)
    }
    AppButton {
        objectName: "setLifeButton"
                    + root.tableController.roomSession.seatIndex
        compact: true
        variant: root.tableController.rulesAssist.possibleLoss(
                     root.tableController.ownSeatData)
                 ? "danger" : "ghost"
        Layout.preferredWidth: Theme.size(44)
        Layout.minimumWidth: Theme.size(36)
        implicitHeight: Theme.size(26)
        visible: root.tableController.roomSession.role === "player"
        text: String(root.tableController.gameValues.displayedLife(
                         root.tableController.ownSeatData))
        enabled: root.tableController.canAct
        onClicked: root.tableController.lifeEditor.showFor(
                       root.tableController.ownSeatData.displayName,
                       root.tableController.gameValues.displayedLife(
                           root.tableController.ownSeatData))
        ToolTip.visible: hovered
        ToolTip.text:
            root.tableController.rulesAssist.possibleLoss(
                root.tableController.ownSeatData)
            ? qsTr("Life is 0 or less. A card effect may still prevent losing.")
            : qsTr("Set life")
    }
    AppButton {
        objectName: "increaseLifeButton"
                    + root.tableController.roomSession.seatIndex
        compact: true
        variant: "ghost"
        Layout.preferredWidth: Theme.size(28)
        Layout.minimumWidth: Theme.size(24)
        implicitHeight: Theme.size(26)
        visible: root.tableController.roomSession.role === "player"
        text: "+"
        accessibleName: qsTr("Increase life")
        enabled: root.tableController.canAct
                 && root.tableController.gameValues.displayedLife(
                     root.tableController.ownSeatData)
                    < 2147483647
        onClicked: root.tableController.gameValues.setLife(
                       root.tableController.gameValues.displayedLife(
                           root.tableController.ownSeatData) + 1)
    }
}
