// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "SideboardPanel"

import QtQuick
import QtQuick.Layouts

Surface {
    id: root

    required property var panel
    readonly property var basicNames: ["Plains", "Island", "Swamp",
                                       "Mountain", "Forest"]

    objectName: "sideboardBasicLandsPanel"
    Layout.fillWidth: true
    visible: panel.isPlayer && panel.limitedDeck
             && panel.basicLandsExpanded
    implicitHeight: Theme.size(62)
    color: Theme.surfaceMuted

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.size(9)
        spacing: Theme.size(6)

        Text {
            textFormat: Text.PlainText
            text: qsTr("Unlimited basic lands")
            color: Theme.text
            font.pixelSize: Theme.fontSize(11)
            font.weight: Font.DemiBold
        }

        Repeater {
            model: root.basicNames

            delegate: Surface {
                id: basicControl

                required property string modelData
                Layout.fillWidth: true
                implicitHeight: Theme.size(46)
                color: Theme.surfaceElevated

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.size(5)
                    spacing: Theme.size(3)

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: root.basicLabel(basicControl.modelData)
                              + " "
                              + root.virtualBasicCount(basicControl.modelData)
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(9)
                        elide: Text.ElideRight
                    }

                    AppButton {
                        compact: true
                        implicitWidth: Theme.size(34)
                        text: "−"
                        enabled: !root.panel.ownReady
                                 && root.virtualBasicCount(
                                     basicControl.modelData) > 0
                        onClicked: root.adjustLimitedBasic(
                                       basicControl.modelData, -1)
                    }

                    AppButton {
                        compact: true
                        implicitWidth: Theme.size(34)
                        text: "+"
                        enabled: !root.panel.ownReady
                        onClicked: root.adjustLimitedBasic(
                                       basicControl.modelData, 1)
                    }
                }
            }
        }
    }

    function isVirtualOrdinaryBasic(card) {
        if (!card || card.virtualCard !== true)
            return false
        const normalized = String(card.name || "").trim().toLowerCase()
        return normalized === "plains" || normalized === "island"
                || normalized === "swamp" || normalized === "mountain"
                || normalized === "forest"
    }

    function virtualBasicCount(name) {
        let count = 0
        for (let index = 0; index < panel.mainboard.length; ++index) {
            const card = panel.mainboard[index]
            if (String(card.name || "").toLowerCase()
                    === String(name).toLowerCase()
                    && !String(card.setCode || "").trim()
                    && !String(card.collectorNumber || "").trim()) {
                count += Math.max(0, Number(card.count || 0))
            }
        }
        return count
    }

    function virtualBasicTotal() {
        let count = 0
        for (let index = 0; index < basicNames.length; ++index)
            count += virtualBasicCount(basicNames[index])
        return count
    }

    function basicLabel(name) {
        const labels = {
            "Plains": qsTr("Plains"), "Island": qsTr("Island"),
            "Swamp": qsTr("Swamp"), "Mountain": qsTr("Mountain"),
            "Forest": qsTr("Forest")
        }
        return labels[name] || name
    }

    function adjustLimitedBasic(name, amount) {
        const card = {"name": name, "setCode": "", "collectorNumber": ""}
        panel.wsModel.moveSideboardCard(
                    card,
                    amount > 0 ? "basic_lands" : "mainboard",
                    amount > 0 ? "mainboard" : "basic_lands")
    }
}
