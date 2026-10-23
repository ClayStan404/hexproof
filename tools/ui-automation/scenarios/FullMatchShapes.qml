// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

Item {
    id: root
    required property var driver
    required property var probe
    required property var window

    function exact(card, expected) {
        return card.name === expected.name
            && String(card.setCode).toUpperCase() === String(expected.setCode).toUpperCase()
            && String(card.collectorNumber) === String(expected.collectorNumber)
    }
    function handMatch(expected) {
        const hand = driver.myHand()
        for (let index = 0; index < hand.count; ++index) {
            const card = hand.get(index)
            if (exact(card, expected)) return card
        }
        return null
    }
    function fill(name, value) {
        const field = driver.item(name)
        if (!field) return false
        driver.require(probe.click(field), "Cannot focus " + name)
        driver.inputKey(Qt.Key_A, Qt.ControlModifier)
        driver.require(probe.text(value), "Cannot enter " + name)
        driver.require(field.text === value, "Input text did not reach " + name)
        return true
    }
    function append(manifest) {
        const deck = manifest && manifest.decks && manifest.decks[driver.format]
        const shapes = deck && deck.shapeCards
        const planned = []
        for (const tag of ["transform", "modal_dfc", "prepare"]) {
            if (!shapes || !shapes[tag]) continue
            const card = shapes[tag]
            const state = {id: "", wasInHand: false, handBefore: 0, libraryBefore: 0}
            planned.push({tag: tag, name: card.name, setCode: card.setCode,
                          collectorNumber: card.collectorNumber})
            const label = tag + " · " + card.name
            driver.operation("Locate exact own card: " + label, () => {
                state.handBefore = driver.myHand().count
                state.libraryBefore = driver.ownData().libraryCount
                const found = handMatch(card)
                state.wasInHand = !!found
                if (found) state.id = found.id
            })
            driver.operation("Search own library when needed: " + label, () => state.wasInHand
                || driver.inputKey(Qt.Key_F, Qt.ControlModifier),
                () => state.wasInHand || !!driver.item("librarySearchFilter"))
            driver.operation("Filter library by real name: " + label,
                () => state.wasInHand || fill("librarySearchFilter", card.name),
                () => {
                    if (state.wasInHand) return true
                    const row = driver.item("librarySearchCard0")
                    return row && exact(row.modelData, card)
                })
            driver.operation("Select exact library printing: " + label, () => {
                if (state.wasInHand) return true
                const row = driver.item("librarySearchCard0")
                if (!row) return false
                driver.require(exact(row.modelData, card), "Wrong library printing")
                state.id = row.modelData.id
                driver.require(!!state.id, "Missing library physical card identity")
                return driver.rightClick("librarySearchCard0")
            }, () => state.wasInHand || !!driver.item("libraryContextLocalHand"))
            driver.operation("Move searched card to hand: " + label,
                () => state.wasInHand || driver.checkedClick("libraryContextLocalHand"),
                () => driver.inZone(state.id, "hand"))
            driver.operation("Decline optional search shuffle: " + label,
                () => state.wasInHand || driver.checkedClick("cancelButton"),
                () => !driver.item("cancelButton"))
            const isDoubleFaced = tag === "transform" || tag === "modal_dfc"
            if (isDoubleFaced) {
                driver.operation("Drag double-faced card to battlefield: " + label, () => {
                    const source = driver.handItem(state.id)
                    const target = driver.item("battlefieldZone" + driver.ownSeat())
                    return driver.checkedDrag(source, target, "Place " + label + " (" + state.id + ") on battlefield")
                }, () => !!driver.item("cardFaceChoice1"))
                driver.operation("Choose printed back face: " + label, () => {
                    const face = driver.item("cardFaceChoice1")
                    if (!face) return false
                    driver.require(card.faces && card.faces.length > 1,
                                   "Fixture must independently identify both printed faces")
                    driver.require(face.modelData.faceName === card.faces[1],
                                   "Back-face chooser differs from source fixture")
                    return driver.checkedClick("cardFaceChoice1")
                }, () => driver.inZone(state.id, "battlefield")
                    && gameTable.cardData(state.id).faceName === card.faces[1])
                driver.operation("Select double-faced permanent: " + label,
                    () => driver.checkedClick("battlefieldCard" + state.id))
                driver.operation("Reopen battlefield face chooser: " + label,
                    () => driver.inputKey(Qt.Key_V), () => !!driver.item("cardFaceChoice0"))
                driver.operation("Choose printed front face: " + label,
                    () => driver.checkedClick("cardFaceChoice0"),
                    () => driver.inZone(state.id, "battlefield")
                        && (!gameTable.cardData(state.id).faceName
                            || gameTable.cardData(state.id).faceName === card.faces[0]))
            } else {
                driver.operation("Cast special-layout card through stack: " + label, () => {
                    const source = driver.handItem(state.id)
                    const target = driver.item("sharedCards")
                    return driver.checkedDrag(source, target, "Cast " + label + " (" + state.id + ") through stack")
                }, () => driver.inZone(state.id, "stack"))
                driver.operation("Select exact special-layout stack card: " + label,
                    () => driver.checkedClick("sharedCard0"),
                    () => !!driver.item("sharedToBattlefieldButton"))
                driver.operation("Resolve special-layout card manually: " + label,
                    () => driver.checkedClick("sharedToBattlefieldButton"),
                    () => driver.inZone(state.id, "battlefield"))
                driver.operation("Special-layout identity remains one physical card: " + label, () => {
                    driver.require(!driver.item("cardFaceChoice1"),
                                   "Single-picture layout incorrectly required a double-face choice")
                    driver.require(exact(gameTable.cardData(state.id), card),
                                   "Layout resolution changed exact printing")
                })
            }
            driver.operation("Capture special-layout result: " + label, () => {
                probe.capture(window, "shape-" + tag)
                probe.record("shape-" + tag, {fixture: card, card: gameTable.cardData(state.id),
                             physicalId: state.id, operation: "manual-zone-and-face-controls"})
            })
            driver.operation("Select special card for return: " + label,
                () => driver.checkedClick("battlefieldCard" + state.id))
            driver.operation("Return special card to its original private zone: " + label,
                () => driver.inputKey(state.wasInHand ? Qt.Key_H : Qt.Key_Up, Qt.AltModifier),
                () => driver.myHand().count === state.handBefore
                    && driver.ownData().libraryCount === state.libraryBefore
                    && driver.zone("battlefield").count === 1
                    && (state.wasInHand ? driver.inZone(state.id, "hand")
                        : !driver.inZone(state.id, "battlefield")))
        }
        probe.fixture("special-layout-plan", {format: driver.format,
                      manifestProvided: !!deck, cards: planned,
                      scope: "Manual input and printing/face presentation, without automatic card rules"})
        return planned
    }
}
