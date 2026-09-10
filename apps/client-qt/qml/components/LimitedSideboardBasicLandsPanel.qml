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
    implicitHeight: basicControls.implicitHeight + Theme.size(18)
    color: Theme.surfaceMuted

    GridLayout {
        id: basicControls
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.size(9)
        columns: width < Theme.size(420) ? 1 : width < Theme.size(1000) ? 2 : 5
        columnSpacing: Theme.size(6)
        rowSpacing: Theme.size(6)

        Text {
            Layout.columnSpan: basicControls.columns
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: qsTranslate("SideboardPanel", "Unlimited basic lands")
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
                        objectName: "sideboardBasicRemove-" + basicControl.modelData
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
                        objectName: "sideboardBasicAdd-" + basicControl.modelData
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
            "Plains": qsTranslate("SideboardPanel", "Plains"), "Island": qsTranslate("SideboardPanel", "Island"),
            "Swamp": qsTranslate("SideboardPanel", "Swamp"), "Mountain": qsTranslate("SideboardPanel", "Mountain"),
            "Forest": qsTranslate("SideboardPanel", "Forest")
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
