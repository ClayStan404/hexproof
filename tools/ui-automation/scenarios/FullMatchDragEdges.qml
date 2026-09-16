// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: root
    required property var driver
    required property var probe
    readonly property bool requested: probe.environment("HEXPROOF_AUDIT_DRAG_EDGES") === "1"
    readonly property var requiredScreenshots: requested
        ? ["edge-tapped-source.png", "edge-stack.png", "edge-hand-from-stack.png",
           "edge-hand-from-reveal.png", "edge-restored.png"] : []

    function contains(zone) {
        return gameTable.cardInZone(driver.movedCard, zone,
                                    zone === "stack" || zone === "reveal" ? -1 : driver.ownSeat())
    }
    function sharedItem(zone) {
        const model = zone === "stack" ? gameTable.stackModel : gameTable.revealedModel
        for (let index = 0; index < model.count; ++index) {
            const row = driver.item("sharedCard" + index)
            if (row && row.cardId === driver.movedCard && row.zoneName === zone) return row
        }
        return null
    }
    function edgeDrag(source, target, fromZone, toZone) {
        if (!source || !target) return false
        driver.require(contains(fromZone), "Edge drag source zone does not contain the physical card")
        driver.require(source.cardId === driver.movedCard && source.modelData.name === driver.movedCardName,
                       "Edge drag selected a different physical card")
        return driver.checkedDrag(source, target, "Edge drag " + fromZone + " -> " + toZone,
                                  source.width - 2, (source.revealDividerHeight || 0) + 2)
    }
    function capture(name) {
        driver.operation("Capture " + name, () => {
            driver.capture(name)
            probe.record(name, driver.interactionState())
        })
    }
    function append() {
        if (!requested) return
        const state = {hand: 0}
        driver.operation("Verify tapped source before edge drag cycle", () => {
            state.hand = driver.myHand().count
            driver.require(contains("battlefield") && gameTable.cardData(driver.movedCard).tapped === true,
                           "Edge cycle requires the same tapped permanent")
            driver.require(gameTable.stackModel.count === 0 && gameTable.revealedModel.count === 0,
                           "Edge cycle requires empty shared zones")
        })
        capture("edge-tapped-source")
        driver.operation("Drag tapped battlefield card from its edge to stack", () => {
            const area = driver.item("battlefieldDrag" + driver.movedCard)
            const source = area && area.parent
            if (!source || source.rotation !== 90) return false
            return edgeDrag(source, driver.item("sharedCards"), "battlefield", "stack")
        }, () => contains("stack") && !contains("battlefield")
                 && gameTable.stackModel.count === 1)
        capture("edge-stack")
        driver.operation("Drag same stack card from its edge to hand", () =>
            edgeDrag(sharedItem("stack"), driver.item("ownHand"), "stack", "hand"),
            () => contains("hand") && !contains("stack")
                  && driver.myHand().count === state.hand + 1 && gameTable.stackModel.count === 0)
        capture("edge-hand-from-stack")
        driver.operation("Reveal hand containing the same edge-dragged card", () =>
            driver.inputKey(Qt.Key_H, Qt.ControlModifier),
            () => contains("reveal") && !contains("hand") && driver.myHand().count === 0
                  && gameTable.revealedModel.count === state.hand + 1)
        driver.operation("Drag same revealed card from its edge to hand", () =>
            edgeDrag(sharedItem("reveal"), driver.item("ownHand"), "reveal", "hand"),
            () => contains("hand") && !contains("reveal") && driver.myHand().count === 1
                  && gameTable.revealedModel.count === state.hand)
        capture("edge-hand-from-reveal")
        driver.operation("Recall remaining revealed hand after edge drag", () =>
            driver.inputKey(Qt.Key_H, Qt.ControlModifier),
            () => gameTable.revealedModel.count === 0 && driver.myHand().count === state.hand + 1)
        driver.operation("Restore the same edge-dragged card to battlefield", () =>
            driver.checkedDrag(driver.handItem(driver.movedCard),
                               driver.item("battlefieldZone" + driver.ownSeat()),
                               "Restore edge-dragged physical card to battlefield"),
            () => contains("battlefield") && !contains("hand") && driver.myHand().count === state.hand)
        driver.operation("Restore tapped state after edge drag cycle", () => {
            if (gameTable.cardData(driver.movedCard).tapped === true) return true
            const permanent = driver.item("battlefieldCard" + driver.movedCard)
            return permanent && probe.doubleClick(permanent)
        }, () => gameTable.cardData(driver.movedCard).tapped === true
                 && gameTable.cardData(driver.movedCard).name === driver.movedCardName)
        capture("edge-restored")
    }
}
