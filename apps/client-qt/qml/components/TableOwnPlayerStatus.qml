// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "Table"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: root

    required property var tableController
    Layout.fillWidth: true
    Layout.minimumHeight: Theme.size(28)
    spacing: Theme.size(4)

    RowLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.preferredHeight: Theme.size(28)
        spacing: Theme.size(5)
        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: root.tableController.ownSeatData.displayName
                  ? root.tableController.ownSeatData.displayName
                  : qsTranslate("Table", "You")
            color: Theme.text
            font.pixelSize: Theme.fontSize(11)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        AppButton {
            objectName: "decreaseLifeButton"
                        + root.tableController.roomSession.seatIndex
            compact: true
            variant: "ghost"
            Layout.preferredWidth: Theme.size(28)
            Layout.minimumWidth: Theme.size(28)
            Layout.maximumWidth: Theme.size(28)
            implicitHeight: Theme.size(26)
            visible: root.tableController.roomSession.role === "player"
            text: "−"
            accessibleName: qsTranslate("Table", "Decrease life")
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
            Layout.minimumWidth: Theme.size(44)
            Layout.maximumWidth: Theme.size(44)
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
                ? qsTranslate("Table", "Life is 0 or less. A card effect may still prevent losing.")
                : qsTranslate("Table", "Set life")
        }
        AppButton {
            objectName: "increaseLifeButton"
                        + root.tableController.roomSession.seatIndex
            compact: true
            variant: "ghost"
            Layout.preferredWidth: Theme.size(28)
            Layout.minimumWidth: Theme.size(28)
            Layout.maximumWidth: Theme.size(28)
            implicitHeight: Theme.size(26)
            visible: root.tableController.roomSession.role === "player"
            text: "+"
            accessibleName: qsTranslate("Table", "Increase life")
            enabled: root.tableController.canAct
                     && root.tableController.gameValues.displayedLife(
                         root.tableController.ownSeatData)
                        < 2147483647
            onClicked: root.tableController.gameValues.setLife(
                           root.tableController.gameValues.displayedLife(
                               root.tableController.ownSeatData) + 1)
        }
    }

    Flickable {
        id: counterScroll
        objectName: "ownPlayerCounters"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumWidth: 0
        Layout.minimumHeight: visible ? Theme.size(28) : 0
        Layout.preferredHeight: counterColumn.implicitHeight
        visible: root.tableController.ownCommanderCards.length > 0
                 || root.tableController.ownSeatData.mulliganCount > 0
                 || (root.tableController.visibleCounterCount > 0
                     && !!root.tableController.ownSeatData.counters
                     && root.tableController.ownSeatData.counters.length > 0)
        contentWidth: width
        contentHeight: counterColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
            id: counterColumn
            width: counterScroll.width
            spacing: Theme.size(4)

            Repeater {
                model: root.tableController.ownCommanderCards
                delegate: RowLayout {
                    id: commanderTaxGroup
                    required property var modelData
                    required property int index
                    objectName: index === 0
                                ? "commanderTaxControls" + root.tableController.roomSession.seatIndex
                                : "commanderTaxControls" + root.tableController.roomSession.seatIndex + "-" + index
                    width: counterColumn.width
                    height: Theme.size(28)
                    spacing: Theme.size(5)

                    HoverHandler { id: commanderTaxHover }
                    ToolTip.visible:
                        commanderTaxHover.hovered
                    ToolTip.text:
                        qsTranslate("Table", "Commander tax") + " · "
                        + root.tableController.gameValues.commanderTaxDisplayName(
                            commanderTaxGroup.modelData,
                            commanderTaxGroup.index) + "\n"
                        + qsTranslate("Table", "Command-zone casts: %1 · Additional cost: +%2")
                          .arg(root.tableController.gameValues.displayedCommanderTax(
                                   root.tableController.ownSeatData,
                                   commanderTaxGroup.modelData.id))
                          .arg(2 * root.tableController.gameValues.displayedCommanderTax(
                                   root.tableController.ownSeatData,
                                   commanderTaxGroup.modelData.id))

                    Text {
                        textFormat: Text.PlainText
                        objectName: commanderTaxGroup.index === 0
                                    ? "commanderTaxLabel" + root.tableController.roomSession.seatIndex
                                    : "commanderTaxLabel" + root.tableController.roomSession.seatIndex + "-" + commanderTaxGroup.index
                        Layout.fillWidth: true
                        Layout.minimumWidth: Theme.size(20)
                        text: root.tableController.gameValues.commanderTaxDisplayName(
                                  commanderTaxGroup.modelData,
                                  commanderTaxGroup.index)
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(11)
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
                        Layout.minimumWidth: Theme.size(28)
                        Layout.maximumWidth: Theme.size(28)
                        implicitHeight: Theme.size(26)
                        text: "−"
                        accessibleName: qsTranslate("Table", "Decrease commander cast count")
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
                        Layout.preferredWidth: Theme.size(44)
                        Layout.minimumWidth: Theme.size(44)
                        Layout.maximumWidth: Theme.size(44)
                        Layout.preferredHeight: Theme.size(26)
                        text: String(
                                  2 * root.tableController.gameValues.displayedCommanderTax(
                                      root.tableController.ownSeatData,
                                      commanderTaxGroup.modelData.id))
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(13)
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    AppButton {
                        objectName: commanderTaxGroup.index === 0
                                    ? "increaseCommanderTaxButton" + root.tableController.roomSession.seatIndex
                                    : "increaseCommanderTaxButton" + root.tableController.roomSession.seatIndex + "-" + commanderTaxGroup.index
                        compact: true
                        variant: "ghost"
                        Layout.preferredWidth: Theme.size(28)
                        Layout.minimumWidth: Theme.size(28)
                        Layout.maximumWidth: Theme.size(28)
                        implicitHeight: Theme.size(26)
                        text: "+"
                        accessibleName: qsTranslate("Table", "Increase commander cast count")
                        enabled: root.tableController.canAct
                        onClicked: root.tableController.gameValues.adjustCommanderTax(
                                       commanderTaxGroup.modelData.id, 1)
                    }
                }
            }

            Flow {
                id: counterFlow
                width: counterColumn.width
                spacing: Theme.size(5)
                visible: root.tableController.ownSeatData.mulliganCount > 0
                         || (root.tableController.visibleCounterCount > 0
                             && !!root.tableController.ownSeatData.counters
                             && root.tableController.ownSeatData.counters.length > 0)
                height: visible ? implicitHeight : 0
                StatusPill {
                    objectName: "ownMulliganCount"
                    visible: root.tableController.ownSeatData.mulliganCount > 0
                    text: qsTranslate("Table", "Mulligan %1").arg(
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
                        width: Theme.size(31)
                        height: Theme.size(28)
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
            }
        }
    }
}
