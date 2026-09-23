// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "LibrarySearchPopup"
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 900
        height: 620
        visible: true
        LibrarySearchPopup { id: popup }
    }

    SignalSpy { id: searchSpy; target: popup; signalName: "searchRequested" }
    SignalSpy { id: resolveSpy; target: popup; signalName: "resolveAssignmentsRequested" }

    function init() {
        testWindow.requestActivate()
        tryCompare(testWindow, "active", true)
        searchSpy.clear()
        resolveSpy.clear()
    }

    function cleanup() {
        popup.close()
        Theme.uiScale = 1
        testWindow.width = 900
        testWindow.height = 620
    }

    function showTopCards(count, remote) {
        const cards = []
        for (let index = 0; index < count; ++index)
            cards.push({id: "card-" + index, name: "Card " + index,
                        setCode: "TST", collectorNumber: String(index + 1)})
        popup.showCards(cards, remote ? 1 : 0, remote ? "top-grant" : "",
                        0, "Alice", remote ? "Bob" : "Alice", count)
        tryCompare(popup, "opened", true)
        verify(waitForRendering(popup.contentItem))
    }

    function assignedIds(destination) {
        return popup.topCardAssignmentList().filter(card => card.toZone === destination)
                                           .map(card => card.cardId)
    }

    function topChild(cardId, name) {
        const list = findChild(popup, "libraryTopCardsList")
        const index = popup.topCardRows.findIndex(row => row.card.id === cardId)
        tryVerify(() => list.itemAtIndex(index) !== null)
        return findChild(list.itemAtIndex(index), name + "_" + cardId)
    }

    function test_topCardMoveRevealIsOptIn_data() {
        const rows = []
        for (const remote of [false, true]) {
            for (const action of ["LocalHand", "SourceTopOrdered", "SourceBottomOrdered",
                                  "LocalBattlefieldFaceDown"]) {
                for (const reveal of [false, true])
                    rows.push({tag: remote + "-" + action + "-" + reveal,
                               remote, action, reveal})
            }
        }
        return rows
    }

    function test_topCardMoveRevealIsOptIn(data) {
        showTopCards(1, data.remote)
        const reveal = findChild(popup, "revealLibrarySearch")
        verify(reveal.visible)
        verify(!reveal.checked)
        reveal.checked = data.reveal
        popup.contextCardId = "card-0"
        findChild(popup, "libraryContext" + data.action).triggered()
        compare(searchSpy.count, 1)
        compare(searchSpy.signalArguments[0][0], ["card-0"])
        compare(searchSpy.signalArguments[0][2],
                data.reveal && data.action !== "LocalBattlefieldFaceDown")
        compare(searchSpy.signalArguments[0][5], data.remote ? 1 : 0)
        compare(searchSpy.signalArguments[0][6], data.remote ? "top-grant" : "")
    }

    function test_revealedBatchIsSeparateFromLaterPrivateAssignments() {
        showTopCards(4, false)
        const reveal = findChild(popup, "topSelectedReveal")
        verify(reveal.visible)
        verify(!reveal.checked)
        popup.selectedOrder = ["card-0", "card-1"]
        mouseClick(reveal)
        mouseClick(findChild(popup, "assignSelectedTopCards"))
        verify(!reveal.checked)
        compare(popup.selectedCount, 0)
        compare(popup.topCardAssignmentList().filter(card => card.reveal)
                     .map(card => card.cardId), ["card-0", "card-1"])
        verify(topChild("card-0", "topCardStatus").text.includes("Reveal in log"))
        popup.selectedOrder = ["card-2"]
        mouseClick(findChild(popup, "assignSelectedTopCards"))
        verify(popup.topCardAssignment("card-0").reveal)
        verify(!popup.topCardAssignment("card-2").reveal)
        verify(!popup.topCardAssignment("card-3").reveal)
        verify(!topChild("card-2", "topCardStatus").text.includes("Reveal in log"))
        // A pending preference is not applied to already staged cards or the remainder.
        reveal.checked = true
        mouseClick(findChild(popup, "completeLibrarySearchButton"))
        compare(resolveSpy.count, 1)
        compare(resolveSpy.signalArguments[0][0], [
            {cardId: "card-0", toZone: "hand", faceDown: false, reveal: true},
            {cardId: "card-1", toZone: "hand", faceDown: false, reveal: true},
            {cardId: "card-2", toZone: "hand", faceDown: false},
            {cardId: "card-3", toZone: "library_top", faceDown: false}
        ])
    }

    function test_previewRevealsCanBeReviewedChangedAndCleared() {
        showTopCards(3, false)
        popup.assignTopCards(["card-0", "card-1"], "hand", false, true)
        popup.selectedIndex = 0
        const preview = findChild(popup, "topCardReveal")
        const scroll = findChild(popup, "libraryInspectorScroll")
        scroll.contentItem.contentY = scroll.contentItem.contentHeight - scroll.height
        verify(waitForRendering(popup.contentItem))
        verify(preview.checked)
        mouseClick(preview)
        verify(!popup.topCardAssignment("card-0").reveal)
        verify(popup.topCardAssignment("card-1").reveal)
        mouseClick(preview)
        verify(popup.topCardAssignment("card-0").reveal)

        popup.setTopCardDestination("card-0", "library_bottom")
        verify(popup.topCardAssignment("card-0").reveal)
        popup.setTopCardDestination("card-1", "library_bottom")
        popup.moveTopCardInGroup("card-1", -1)
        compare(assignedIds("library_bottom"), ["card-1", "card-0"])
        compare(popup.topCardAssignmentList().filter(card => card.reveal)
                     .map(card => card.cardId), ["card-1", "card-0"])
        compare(popup.selectedCard.id, "card-0")
        verify(preview.checked)

        popup.setTopCardDestination("card-0", "battlefield")
        popup.setTopCardFaceDown("card-0", false)
        verify(popup.topCardAssignment("card-0").reveal)
        popup.setTopCardFaceDown("card-0", true)
        verify(!popup.topCardAssignment("card-0").reveal)
        verify(!preview.enabled)
        verify(!preview.checked)
        popup.setTopCardFaceDown("card-0", false)
        verify(!popup.topCardAssignment("card-0").reveal)
        popup.useRemainderForTopCards(["card-1"])
        verify(!popup.topCardAssignment("card-1").reveal)
        compare(popup.topCardAssignmentList().filter(card => card.reveal), [])
    }

    function test_contextRevealUsesCurrentBatchAndResets_data() {
        return [
            {tag: "selected", selected: true, faceDown: false},
            {tag: "single", selected: false, faceDown: false},
            {tag: "face-down", selected: true, faceDown: true}
        ]
    }

    function test_contextRevealUsesCurrentBatchAndResets(data) {
        showTopCards(3, true)
        const reveal = findChild(popup, "topSelectedReveal")
        reveal.checked = true
        popup.selectedOrder = data.selected ? ["card-0", "card-1"] : ["card-1"]
        popup.contextCardId = "card-0"
        findChild(popup, "libraryContextLocal"
                  + (data.faceDown ? "BattlefieldFaceDown" : "Hand")).triggered()
        verify(!reveal.checked)
        compare(popup.topCardAssignment("card-0").reveal === true, !data.faceDown)
        compare(popup.topCardAssignment("card-1").reveal === true,
                data.selected && !data.faceDown)
        popup.contextCardId = "card-2"
        findChild(popup, "libraryContextLocalHand").triggered()
        verify(!popup.topCardAssignment("card-2").reveal)
        compare(searchSpy.count, 0)
        compare(resolveSpy.count, 0)
    }

    function test_fullSearchKeepsRevealPreferenceSeparateFromTopViews() {
        popup.showCards([{id: "full", name: "Forest"}], 0, "", 0, "Alice", "Alice", 0)
        tryCompare(popup, "opened", true)
        const reveal = findChild(popup, "revealLibrarySearch")
        verify(reveal.visible)
        verify(reveal.checked)
        popup.contextCardId = "full"
        findChild(popup, "libraryContextLocalHand").triggered()
        compare(searchSpy.signalArguments[0][2], true)
        tryCompare(popup, "visible", false)
        showTopCards(1, false)
        verify(!reveal.checked)
        reveal.checked = true
        popup.close()
        tryCompare(popup, "visible", false)
        showTopCards(1, false)
        verify(!reveal.checked)
    }

    function test_batchAssignmentsAndRemainderResolveTogether() {
        showTopCards(7, true)
        compare(popup.topRemainderCount, 7)
        mouseClick(topChild("card-0", "topCardSelect"))
        mouseClick(topChild("card-1", "topCardSelect"))
        mouseClick(findChild(popup, "assignSelectedTopCards"))
        compare(assignedIds("hand"), ["card-0", "card-1"])
        compare(popup.selectedCount, 0)
        compare(popup.topSelectionAnchor, "")
        compare(popup.topRemainderCount, 5)
        popup.setTopRemainderDestination("library_bottom")
        compare(assignedIds("library_bottom"), ["card-2", "card-3", "card-4", "card-5", "card-6"])
        popup.setTopRemainderDestination("graveyard")
        compare(assignedIds("hand"), ["card-0", "card-1"])
        popup.selectTopCard("card-1", false)
        mouseClick(findChild(popup, "useTopRemainder"))
        compare(popup.selectedCount, 0)
        compare(popup.topSelectionAnchor, "")
        compare(popup.topRemainderCount, 6)
        popup.setTopRemainderDestination("library_bottom")
        popup.assignTopCards(["card-2", "card-3"], "battlefield", true)
        compare(searchSpy.count, 0)
        compare(resolveSpy.count, 0)
        verify(popup.opened)
        findChild(popup, "topCardsRandomizeBottom").checked = true
        mouseClick(findChild(popup, "completeLibrarySearchButton"))
        compare(resolveSpy.count, 1)
        const args = resolveSpy.signalArguments[0]
        compare(args[0].length, 7)
        compare(args[0].map(card => card.cardId),
                ["card-0", "card-1", "card-2", "card-3", "card-4", "card-5", "card-6"])
        compare(args[0][0], {cardId: "card-0", toZone: "hand", faceDown: false})
        compare(args[0][1], {cardId: "card-1", toZone: "library_bottom", faceDown: false})
        compare(args[0][2], {cardId: "card-2", toZone: "battlefield", faceDown: true})
        compare(args[0][3], {cardId: "card-3", toZone: "battlefield", faceDown: true})
        compare(args[1], false)
        compare(args[2], true)
        compare(args[3], {x: 0.5, y: 0.5})
        compare(args[4], 1)
        compare(args[5], "top-grant")
        compare(searchSpy.count, 0)
    }

    function test_shiftSelectionInvertAndClear() {
        showTopCards(5, false)
        mouseClick(topChild("card-0", "topCardSelect"))
        mouseClick(topChild("card-2", "topCardSelect"), 10, 10,
                   Qt.LeftButton, Qt.ShiftModifier)
        compare(popup.selectedOrder, ["card-0", "card-1", "card-2"])
        mouseClick(findChild(popup, "invertTopCardSelection"))
        compare(popup.selectedOrder, ["card-3", "card-4"])
        mouseClick(findChild(popup, "selectAllTopCards"))
        compare(popup.selectedCount, 5)
        mouseClick(findChild(popup, "clearTopCardSelection"))
        compare(popup.selectedOrder, [])
        compare(popup.topSelectionAnchor, "")
    }

    function test_assignmentClearsSelectionBeforeNextDestination_data() {
        return [
            {tag: "own-library", remote: false},
            {tag: "approved-library", remote: true}
        ]
    }

    function test_assignmentClearsSelectionBeforeNextDestination(data) {
        showTopCards(4, data.remote)
        mouseClick(topChild("card-0", "topCardSelect"))
        mouseClick(findChild(popup, "assignSelectedTopCards"))
        compare(assignedIds("hand"), ["card-0"])
        compare(popup.selectedOrder, [])
        compare(popup.topSelectionAnchor, "")
        verify(!topChild("card-0", "topCardSelect").checked)
        verify(!findChild(popup, "assignSelectedTopCards").enabled)
        compare(popup.selectedCard.id, "card-0")

        // Shift must not extend a stale range across the regrouped cards.
        mouseClick(topChild("card-1", "topCardSelect"), 10, 10,
                   Qt.LeftButton, Qt.ShiftModifier)
        compare(popup.selectedOrder, ["card-1"])
        const destination = findChild(popup, "topSelectedDestination")
        destination.currentIndex = popup.topCardDestinations.findIndex(
                    option => option.value === "graveyard")
        mouseClick(findChild(popup, "assignSelectedTopCards"))
        compare(assignedIds("hand"), ["card-0"])
        compare(assignedIds("graveyard"), ["card-1"])
        compare(popup.selectedOrder, [])

        mouseClick(findChild(popup, "completeLibrarySearchButton"))
        compare(resolveSpy.count, 1)
        compare(resolveSpy.signalArguments[0][0], [
            {cardId: "card-0", toZone: "hand", faceDown: false},
            {cardId: "card-1", toZone: "graveyard", faceDown: false},
            {cardId: "card-2", toZone: "library_top", faceDown: false},
            {cardId: "card-3", toZone: "library_top", faceDown: false}
        ])
    }

    function test_contextAssignmentStagesSelectedOrSingleCard() {
        showTopCards(5, true)
        popup.selectedOrder = ["card-0", "card-1"]
        const row = topChild("card-0", "topCardRow")
        mouseClick(row, row.width / 2, row.height / 2, Qt.RightButton)
        const menu = findChild(popup, "libraryCardMenu")
        tryCompare(menu, "opened", true)
        compare(popup.contextCardId, "card-0")
        mouseClick(findChild(popup, "libraryContextLocalBattlefieldFaceDown"))
        tryCompare(menu, "opened", false)
        compare(assignedIds("battlefield"), ["card-0", "card-1"])
        verify(popup.topCardAssignment("card-0").faceDown)
        compare(popup.selectedOrder, [])
        popup.selectTopCard("card-4", false)
        popup.contextCardId = "card-3"
        const graveyard = findChild(popup, "libraryContextLocalGraveyard")
        compare(graveyard.text, "Bob · Graveyard")
        graveyard.triggered()
        compare(assignedIds("graveyard"), ["card-3"])
        compare(popup.selectedOrder, ["card-4"])
        compare(popup.topSelectionAnchor, "card-4")
        compare(searchSpy.count, 0)
        compare(resolveSpy.count, 0)
        verify(popup.opened)
        verify(!findChild(popup, "libraryContextSourceHand").visible)
        popup.selectedOrder = ["card-0", "card-1"]
        popup.topSelectionAnchor = "card-1"
        popup.contextCardId = "card-0"
        findChild(popup, "libraryContextSourceBottomRandom").triggered()
        compare(assignedIds("library_bottom"), ["card-0", "card-1"])
        compare(popup.selectedOrder, [])
        compare(popup.topSelectionAnchor, "")
        verify(popup.topGroupRandomized("library_bottom"))
        verify(!popup.topCardAssignment("card-0").faceDown)
    }

    function test_reorderingPreservesOtherGroupsAndPreview() {
        showTopCards(7, false)
        popup.assignTopCards(["card-1", "card-3", "card-5"], "library_bottom")
        popup.assignTopCards(["card-4"], "hand")
        popup.selectedIndex = 2
        popup.moveTopCardInGroup("card-6", -1)
        compare(assignedIds("library_top"), ["card-0", "card-6", "card-2"])
        compare(assignedIds("library_bottom"), ["card-1", "card-3", "card-5"])
        compare(popup.selectedCard.id, "card-2")
        popup.moveTopCardRelative("card-1", "card-5", true)
        compare(assignedIds("library_bottom"), ["card-3", "card-5", "card-1"])
        compare(assignedIds("library_top"), ["card-0", "card-6", "card-2"])
        popup.moveTopCardRelative("card-0", "card-1", true)
        compare(assignedIds("library_top"), ["card-0", "card-6", "card-2"])
        findChild(popup, "topCardsRandomizeTop").checked = true
        popup.moveTopCardInGroup("card-0", 1)
        compare(assignedIds("library_top"), ["card-0", "card-6", "card-2"])
        compare(searchSpy.count, 0)
        compare(resolveSpy.count, 0)
    }

    function test_dragReordersWithinGroup() {
        showTopCards(3, false)
        const handle = topChild("card-0", "topCardDrag")
        const target = topChild("card-2", "topCardRow")
        const from = handle.mapToItem(popup.contentItem, handle.width / 2, handle.height / 2)
        const to = target.mapToItem(popup.contentItem, target.width - 20, target.height - 12)
        mousePress(popup.contentItem, from.x, from.y, Qt.LeftButton)
        for (let step = 1; step <= 8; ++step)
            mouseMove(popup.contentItem, from.x + (to.x - from.x) * step / 8,
                      from.y + (to.y - from.y) * step / 8, 20)
        mouseRelease(popup.contentItem, to.x, to.y, Qt.LeftButton)
        tryCompare(popup, "cards", [popup.selectedCardForId("card-1"),
                                   popup.selectedCardForId("card-2"),
                                   popup.selectedCardForId("card-0")])
        compare(assignedIds("library_top"), ["card-1", "card-2", "card-0"])
        compare(resolveSpy.count, 0)
    }

    function test_cancelAndReopenDiscardDraft() {
        showTopCards(4, false)
        popup.assignTopCards(["card-0"], "hand", false, true)
        popup.setTopRemainderDestination("battlefield")
        popup.topRemainderFaceDown = true
        popup.assignTopCards(["card-1"], "battlefield", false)
        verify(!popup.topCardAssignment("card-1").faceDown)
        verify(popup.topCardAssignment("card-2").faceDown)
        popup.setTopRemainderDestination("exile")
        verify(!popup.topRemainderFaceDown)
        popup.assignTopCards(["absent"], "hand")
        popup.assignTopCards(["card-0"], "unsupported")
        compare(Object.keys(popup.topCardAssignments).length, 2)
        findChild(popup, "topSelectedReveal").checked = true
        popup.close()
        tryCompare(popup, "visible", false)
        compare(searchSpy.count, 0)
        compare(resolveSpy.count, 0)
        showTopCards(4, false)
        compare(popup.topRemainderDestination, "library_top")
        compare(popup.topRemainderCount, 4)
        compare(popup.selectedOrder, [])
        verify(!findChild(popup, "topSelectedReveal").checked)
        compare(popup.topCardAssignmentList().filter(card => card.reveal), [])
        compare(assignedIds("library_top"), ["card-0", "card-1", "card-2", "card-3"])
    }

    function test_dragSurvivesScrollingPastItsOriginalRow() {
        showTopCards(40, false)
        const list = findChild(popup, "libraryTopCardsList")
        const handle = topChild("card-0", "topCardDrag")
        const from = handle.mapToItem(popup.contentItem, handle.width / 2, handle.height / 2)
        const edge = list.mapToItem(popup.contentItem, list.width - 20, list.height - 8)
        mousePress(popup.contentItem, from.x, from.y, Qt.LeftButton)
        mouseMove(popup.contentItem, edge.x, edge.y, 20)
        tryVerify(() => list.contentY > 100, 2000)
        // Simulate the longer scroll once auto-scroll has been demonstrated.
        list.contentY = 1000
        verify(waitForRendering(list))
        verify(list.parent.dragging)
        const middle = list.mapToItem(popup.contentItem, list.width - 20, list.height / 2)
        mouseMove(popup.contentItem, middle.x, middle.y, 20)
        const targetId = list.parent.dropCardId
        verify(targetId.length > 0)
        const before = popup.cards.map(card => card.id)
        mouseRelease(popup.contentItem, middle.x, middle.y, Qt.LeftButton)
        tryVerify(() => popup.cards[0].id !== "card-0")
        compare(popup.cards.length, 40)
        compare(popup.cards.map(card => card.id).sort(), before.sort())
        compare(resolveSpy.count, 0)
    }

    function test_compactControls_data() {
        const rows = []
        for (const scale of [1.5, 1.8]) {
            for (const topCount of [0, 1, 3])
                rows.push({tag: scale + "-top-" + topCount, scale, topCount})
        }
        return rows
    }

    function test_destinationNamesLeadWithZoneAndRetainOwnership() {
        popup.showCards([{id: "a", name: "Island"}], 1, "approval", 0,
                        "Local player with a long name", "Remote player with a long name", 3)
        const options = popup.destinations
        compare(options[0].label, "Hand · Local player with a long name")
        compare(options[0].seat, 0)
        compare(options[4].label, "Hand · Remote player with a long name")
        compare(options[4].seat, 1)
        compare(options[8].label, "Top of library · Remote player with a long name")
        compare(options[8].value, "library_top")
        compare(popup.topCardDestinations[4].label,
                "Top of library · Remote player with a long name")
    }

    function test_compactControls(data) {
        Theme.uiScale = data.scale
        popup.showCards([
            {id: "a", name: "Lightning Bolt", setCode: "M11", collectorNumber: "149"},
            {id: "b", name: "Island", setCode: "TST", collectorNumber: "2"},
            {id: "c", name: "Forest", setCode: "TST", collectorNumber: "3"}
        ].slice(0, data.topCount === 1 ? 1 : 3), 0, "", 0, "Alice", "Alice", data.topCount)
        tryCompare(popup, "opened", true)
        verify(waitForRendering(popup.contentItem))
        const list = findChild(popup, data.topCount > 1
                              ? "libraryTopCardsList" : "librarySearchCards")
        verify(list.width >= 300, "List width " + list.width + ", popup width " + popup.availableWidth
               + ", inspector width " + findChild(popup, "libraryInspectorScroll").width)
        verify(list.height >= 150)
        if (data.topCount > 1) {
            const row = topChild("a", "topCardRow")
            const identity = topChild("a", "topCardIdentity")
            const down = topChild("a", "topCardDown")
            verify(identity.width >= Theme.size(70))
            verify(down.mapToItem(row, down.width, 0).x <= row.width)
            mouseClick(findChild(popup, "selectAllTopCards"))
            compare(popup.selectedCount, 3)
            const batchReveal = findChild(popup, "topSelectedReveal")
            const batchScroll = findChild(popup, "libraryInspectorScroll")
            const batchPoint = batchReveal.mapToItem(batchScroll.contentItem, 0, 0)
            batchScroll.contentItem.contentY += Math.max(
                        0, batchPoint.y + batchReveal.height - batchScroll.availableHeight)
            verify(waitForRendering(popup.contentItem))
            mouseClick(batchReveal)
            verify(batchReveal.contentItem.paintedWidth <= batchReveal.contentItem.width + 1)
            batchScroll.contentItem.contentY = 0
            verify(waitForRendering(popup.contentItem))
            mouseClick(findChild(popup, "assignSelectedTopCards"))
            compare(assignedIds("hand"), ["a", "b", "c"])
            compare(popup.topCardAssignmentList().filter(card => card.reveal).length, 3)
        }

        if (data.topCount === 0) {
            mouseClick(findChild(popup, "selectAllLibraryCards"))
            compare(popup.selectedOrder, ["a", "b", "c"])
        }
        const scroll = findChild(popup, "libraryInspectorScroll")
        scroll.contentItem.contentY = scroll.contentItem.contentHeight - scroll.height
        verify(waitForRendering(popup.contentItem))
        const toggle = findChild(popup, data.topCount > 1
                                 ? "topCardReveal" : "revealLibrarySearch")
        verify(toggle.width <= scroll.availableWidth + 1,
               "Toggle width " + toggle.width + ", inspector width " + scroll.availableWidth)
        verify(toggle.contentItem.paintedWidth <= toggle.contentItem.width + 1)
        if (data.topCount === 1) {
            verify(toggle.visible)
            verify(!toggle.checked)
            mouseClick(toggle)
            popup.contextCardId = "a"
            findChild(popup, "libraryContextLocalHand").triggered()
            compare(searchSpy.count, 1)
            compare(searchSpy.signalArguments[0][2], true)
            return
        }
        if (data.topCount === 0) {
            popup.moveSelectedCardInOrder("b", -1)
            verify(waitForRendering(popup.contentItem))
            const up = findChild(popup.contentItem, "librarySelectedMoveUp0")
            verify(up.width <= Theme.size(40))
        }
        const complete = findChild(popup, "completeLibrarySearchButton")
        const position = complete.mapToItem(popup.contentItem, 0, 0)
        verify(position.y >= 0)
        verify(position.y + complete.height <= popup.availableHeight + 1)
        mouseClick(complete)
        if (data.topCount === 0) {
            compare(searchSpy.count, 1)
            compare(searchSpy.signalArguments[0][0], ["b", "a", "c"])
        } else {
            compare(resolveSpy.count, 1)
            compare(resolveSpy.signalArguments[0][0].length, 3)
        }
    }
}
