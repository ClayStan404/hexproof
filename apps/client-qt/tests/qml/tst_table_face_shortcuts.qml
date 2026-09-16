// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "TableFaceShortcuts"
    when: windowShown

    property var table: null
    readonly property string delverName: "Delver of Secrets // Insectile Aberration"

    MatchLoadingTestHarness {
        id: harness
        testCase: testCase
    }

    function faces() {
        return [
            {name: delverName, faceName: "", displayName: "Delver of Secrets"},
            {name: "Insectile Aberration", faceName: "Insectile Aberration",
             displayName: "Insectile Aberration"}
        ]
    }

    function init() {
        verify(harness.reset())
        const seats = JSON.parse(JSON.stringify(harness.mockWsObject.gameSeats))
        seats[0].battlefield = [
            {id: "delver", name: delverName, faceName: "Insectile Aberration",
             ownerSeat: 0, setCode: "ISD", collectorNumber: "51",
             position: {x: 0.2, y: 0.5}},
            {id: "forest", name: "Forest", ownerSeat: 0,
             position: {x: 0.6, y: 0.5}}
        ]
        harness.mockWsObject.gameSeats = seats
        const faceMap = ({})
        faceMap[delverName] = faces()
        harness.mockCatalogObject.faces = faceMap
        table = createTemporaryObject(harness.tableComponentObject, harness.tableHostObject, {
            width: harness.testWindowObject.width, height: harness.testWindowObject.height
        })
        verify(table !== null)
        verify(waitForRendering(table))
        harness.testWindowObject.requestActivate()
        tryVerify(() => harness.testWindowObject.active)
    }

    function cleanup() {
        harness.cleanupHarness()
        table = null
    }

    function clickCard(id, modifiers) {
        const card = findChild(table, "battlefieldCard" + id)
        verify(card !== null)
        mouseClick(card, card.width / 2, card.height / 2,
                   Qt.LeftButton, modifiers || Qt.NoModifier)
    }

    function openFaces() {
        keyClick(Qt.Key_V)
        const picker = findChild(table, "cardFacePicker")
        verify(picker !== null)
        tryCompare(picker, "opened", true)
        compare(picker.cardName, delverName)
        compare(picker.faces.length, 2)
        compare(table.cardMoveCommands.pendingCardFaceAction.cardId, "delver")
        return picker
    }

    function test_leftClickThenVOpensActualFacePicker() {
        clickCard("delver")
        compare(table.selectedBattlefieldCardId, "delver")
        openFaces()
    }

    function test_singleFaceSelectionDoesNotKeepPreviousFaces() {
        clickCard("delver")
        const picker = openFaces()
        keyClick(Qt.Key_Escape)
        tryCompare(picker, "opened", false)
        clickCard("forest")
        compare(table.selectedBattlefieldCardId, "forest")
        compare(table.selectedBattlefieldFaces.length, 0)
        keyClick(Qt.Key_V)
        verify(!picker.opened)
    }

    function test_ctrlToggleRestoresRemainingCardsFaces() {
        clickCard("delver")
        clickCard("forest", Qt.ControlModifier)
        compare(table.selection.selectedCount(), 2)
        keyClick(Qt.Key_V)
        verify(!findChild(table, "cardFacePicker").opened)
        clickCard("forest", Qt.ControlModifier)
        compare(table.selection.selectedCount(), 1)
        compare(table.selectedBattlefieldCardId, "delver")
        openFaces()
    }

    function test_snapshotFallbackRestoresFaces() {
        clickCard("delver")
        clickCard("forest", Qt.ControlModifier)
        const seats = JSON.parse(JSON.stringify(harness.mockWsObject.gameSeats))
        seats[0].battlefield = seats[0].battlefield.filter(card => card.id !== "forest")
        harness.mockWsObject.gameSeats = seats
        tryCompare(table, "selectedBattlefieldCardId", "delver")
        openFaces()
    }

    function test_deselectAllClearsFaces() {
        clickCard("delver")
        compare(table.selectedBattlefieldFaces.length, 2)
        clickCard("delver", Qt.ControlModifier)
        compare(table.selection.selectedCount(), 0)
        compare(table.selectedBattlefieldFaces.length, 0)
        keyClick(Qt.Key_V)
        verify(!findChild(table, "cardFacePicker").opened)
    }

    function test_lateMetadataEnablesShortcutWithoutReselecting() {
        harness.mockCatalogObject.faces = ({})
        clickCard("delver")
        compare(table.selectedBattlefieldFaces.length, 0)
        keyClick(Qt.Key_V)
        verify(!findChild(table, "cardFacePicker").opened)
        // Model a C++ cache update: only the published revision notifies QML.
        harness.mockCatalogObject.faces[delverName] = faces()
        ++harness.mockCatalogObject.imageRevision
        openFaces()
    }
}
