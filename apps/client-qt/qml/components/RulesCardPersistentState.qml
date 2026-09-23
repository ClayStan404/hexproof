// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

QtObject {
    id: root
    required property var card
    required property var rulesSession
    required property var cardCatalogModel

    function cardName(name) {
        if (!cardCatalogModel || typeof cardCatalogModel.cardDisplayName !== "function") return name
        void cardCatalogModel.language
        void cardCatalogModel.imageRevision
        return cardCatalogModel.cardDisplayName(name)
    }
    function colorName(color) {
        switch (color) {
        case "White": return qsTr("White")
        case "Blue": return qsTr("Blue")
        case "Black": return qsTr("Black")
        case "Red": return qsTr("Red")
        case "Green": return qsTr("Green")
        case "Colorless": return qsTr("Colorless")
        default: return color
        }
    }
    readonly property var choiceLines: {
        if (!card || card.visibleIdentity !== true || card.faceDown === true) return []
        const grouped = ({})
        for (const annotation of card.annotations || []) {
            if (!grouped[annotation.kind]) grouped[annotation.kind] = []
            grouped[annotation.kind].push(annotation.kind === "namedCard" ? cardName(annotation.value)
                : annotation.kind === "chosenColor" ? colorName(annotation.value) : annotation.value)
        }
        const lines = []
        if (grouped.namedCard) lines.push(qsTr("Named: %1").arg(grouped.namedCard.join(", ")))
        if (grouped.chosenType) lines.push(qsTr("Type: %1").arg(grouped.chosenType.join(", ")))
        if (grouped.chosenColor) lines.push(qsTr("Color: %1").arg(grouped.chosenColor.join(", ")))
        if (grouped.chosenNumber) lines.push(qsTr("Number: %1").arg(grouped.chosenNumber.join(", ")))
        if (grouped.chosenMode) lines.push(qsTr("Mode: %1").arg(grouped.chosenMode.join(", ")))
        if (grouped.classLevel) lines.push(qsTr("Class level: %1").arg(grouped.classLevel.join(", ")))
        if (grouped.dungeonRoom) lines.push(qsTr("Room: %1").arg(grouped.dungeonRoom.join(", ")))
        return lines
    }
    readonly property string chosenSummary: {
        void rulesSession.snapshotRevision
        if (!card || card.visibleIdentity !== true || card.faceDown === true) return ""
        const names = []
        const seen = ({})
        for (const id of card.chosenCardIds || []) {
            if (seen[id] || typeof rulesSession.cardForInspection !== "function") continue
            seen[id] = true
            const linked = rulesSession.cardForInspection(id)
            if (linked.visibleIdentity === true && linked.name) names.push(cardName(linked.name))
        }
        return names.length ? qsTr("Chosen: %1").arg(names.join(", ")) : ""
    }
    readonly property string exiledNames: {
        void rulesSession.snapshotRevision
        if (!card || !(card.exiledCardCount > 0)) return ""
        const names = []
        const seen = ({})
        for (const id of card.exiledCardIds || []) {
            if (seen[id] || typeof rulesSession.cardForInspection !== "function") continue
            seen[id] = true
            const linked = rulesSession.cardForInspection(id)
            if (linked.zone === "exile" && linked.visibleIdentity === true && linked.name)
                names.push(cardName(linked.name))
        }
        const hidden = Math.max(0, card.exiledCardCount - names.length)
        if (hidden) names.push(qsTr("%1 hidden card(s)").arg(hidden))
        return names.join(", ")
    }
    readonly property string exiledSummary: exiledNames.length
        ? qsTr("Exiled with this card: %1").arg(exiledNames) : ""
    readonly property var arrivalLines: {
        if (!card || card.zone !== "battlefield") return []
        const parts = []
        if (card.enteredThisTurn === true) parts.push(qsTr("Entered this turn"))
        if (card.summoningSick === true) parts.push(qsTr("Summoning sickness"))
        return parts.length ? [parts.join(" · ")] : []
    }
    readonly property var persistentLines: arrivalLines.concat(choiceLines,
        chosenSummary.length ? [chosenSummary] : [])
    readonly property string boardSummary: persistentLines.concat(exiledNames.length
        ? [qsTr("Exiled: %1").arg(exiledNames)] : []).join("\n")
    readonly property string detailSummary: persistentLines.concat(exiledSummary.length
        ? [exiledSummary] : []).join("\n")
}
