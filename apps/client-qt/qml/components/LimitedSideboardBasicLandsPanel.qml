// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "SideboardPanel"

import QtQuick
import QtQuick.Layouts

Surface {
    id: root

    required property var panel
    property var preferredPrintings: ({})
    Component.onCompleted: rememberPrintings()
    Connections {
        target: root.panel
        function onMainboardChanged() { root.rememberPrintings() }
    }
    function rememberPrintings() {
        const next = Object.assign({}, preferredPrintings)
        for (const card of panel.mainboard) {
            if (isVirtualOrdinaryBasic(card))
                next[String(card.name).toLowerCase()] = card
        }
        preferredPrintings = next
    }
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
        if (!card || (card.virtualCard !== true && card.virtualBasic !== true
                && (String(card.setCode || "").trim() || String(card.collectorNumber || "").trim())))
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
                    && isVirtualOrdinaryBasic(card)) {
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

    function printingForNewBasic(name) {
        const fallback = {"name": name, "setCode": "", "collectorNumber": ""}
        if (!panel.cardCatalogModel || typeof panel.cardCatalogModel.printings !== "function")
            return fallback
        const preferredSets = []
        function appendSet(value) {
            const set = String(value || "").trim().toUpperCase()
            if (set && preferredSets.indexOf(set) < 0)
                preferredSets.push(set)
        }
        function appendCardSets(cards) {
            const counts = ({})
            for (const card of cards) {
                const set = String(card && card.setCode || "").trim().toUpperCase()
                if (set)
                    counts[set] = (counts[set] || 0) + Math.max(1, Number(card.count || 1))
            }
            const sets = Object.keys(counts).sort((left, right) =>
                counts[right] - counts[left] || left.localeCompare(right))
            for (const set of sets)
                appendSet(set)
        }
        const limited = panel.wsModel.limitedSession
        if (limited && limited.product)
            appendSet(limited.product.setCode)
        appendCardSets(basicNames.map(basicName => preferredPrintings[basicName.toLowerCase()]).filter(card => !!card))
        // Reconnecting after clearing the pending mainboard has no local
        // printing memory. Its physical pool still identifies the environment.
        appendCardSets(panel.mainboard.concat(panel.sideboard))
        const options = panel.cardCatalogModel.printings(name).filter(card =>
            card.setCode && card.collectorNumber)
        options.sort((left, right) => {
            const setOrder = String(left.setCode).toUpperCase().localeCompare(String(right.setCode).toUpperCase())
            if (setOrder !== 0)
                return setOrder
            const leftNumber = Number(left.collectorNumber)
            const rightNumber = Number(right.collectorNumber)
            if (Number.isFinite(leftNumber) && Number.isFinite(rightNumber)
                    && leftNumber !== rightNumber)
                return leftNumber - rightNumber
            return String(left.collectorNumber).localeCompare(String(right.collectorNumber))
        })
        for (const set of preferredSets) {
            const selected = options.find(card => String(card.setCode).toUpperCase() === set)
            if (selected)
                return {"name": name, "setCode": selected.setCode,
                        "collectorNumber": selected.collectorNumber}
        }
        if (options.length === 0)
            return fallback
        // Cube pools may contain no set with ordinary basics. Prefer one
        // shared series for all five colors before choosing an individual art.
        let sharedSets = Array.from(new Set(options.map(card => String(card.setCode).toUpperCase())))
        for (const basicName of basicNames) {
            if (basicName === name)
                continue
            const sets = new Set(panel.cardCatalogModel.printings(basicName)
                .filter(card => card.setCode && card.collectorNumber)
                .map(card => String(card.setCode).toUpperCase()))
            sharedSets = sharedSets.filter(set => sets.has(set))
        }
        const commonSet = sharedSets.sort()[0] || ""
        const selected = options.find(card => String(card.setCode).toUpperCase() === commonSet) || options[0]
        return {"name": name, "setCode": selected.setCode,
                "collectorNumber": selected.collectorNumber}
    }

    function adjustLimitedBasic(name, amount) {
        let card = preferredPrintings[name.toLowerCase()]
                || printingForNewBasic(name)
        for (const existing of panel.mainboard) {
            if (String(existing.name || "").toLowerCase() === name.toLowerCase()
                    && isVirtualOrdinaryBasic(existing)) {
                card = existing
                break
            }
        }
        panel.wsModel.moveSideboardCard(
                    card,
                    amount > 0 ? "basic_lands" : "mainboard",
                    amount > 0 ? "mainboard" : "basic_lands")
    }
}
