// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "RulesZoneDock"
    when: windowShown
    property var snapshot

    ApplicationWindow {
        id: testWindow
        width: 800; height: 240; visible: true
        QtObject {
            id: controller
            property var rulesSession: testRulesPrompt.session
            property int localSeat: 0
            property url cardBackSource: ""
            property string inspected: ""
            property int inspections: 0
            property string preview: ""
            property var requestedNames: []
            function zoneLabel(zone) {
                return zone === "command" ? "Command zone"
                     : zone.charAt(0).toUpperCase() + zone.slice(1)
            }
            function zoneCount(seat, zone) {
                void rulesSession.snapshotRevision
                return rulesSession.zoneCount(seat, zone)
            }
            function cardImage(name, setCode, collectorNumber) {
                requestedNames.push(name)
                return ""
            }
            function openCardDetails(id) { inspected = id; inspections++ }
            function previewCard(id, source) { preview = id }
            function endCardPreview(source) { preview = "" }
        }
        RulesOpponentZoneDock {
            id: dock
            x: 20; y: 20
            tableController: controller
            ownerSeat: 1
            compact: true
        }
        Item { id: other; x: 450; y: 10; width: 50; height: 50 }
    }

    function init() {
        testTranslations.setLanguage("en")
        testWindow.requestActivate()
        tryCompare(testWindow, "active", true)
        Theme.uiScale = 1
        controller.inspected = ""
        controller.inspections = 0
        controller.preview = ""
        controller.requestedNames = []
        dock.compact = true
        mouseMove(other)
        snapshot = {roomId: "DOCK01", gameId: "dock-game", turn: 1, step: "main1",
            activeSeat: 0, prioritySeat: 0, players: [], stack: [], zones: [
                {zone: "library", ownerSeat: 1, count: 43, cards: [
                    {id: "secret-library", visible: false, identity: {name: "Secret library card"}}]},
                {zone: "graveyard", ownerSeat: 1, count: 2, cards: [
                    {id: "grave-bottom", visible: true, identity: {name: "Opt"}},
                    {id: "grave-top", visible: true, identity: {name: "Consider"}}]},
                {zone: "exile", ownerSeat: 1, count: 1, cards: [
                    {id: "exile-card", visible: true, identity: {name: "Lightning Bolt"}}]},
                {zone: "command", ownerSeat: 1, count: 0, cards: []}
            ]}
        verify(testRulesPrompt.applySnapshot(snapshot))
        waitForRendering(dock)
    }

    function cleanup() { testRulesPrompt.clear() }

    function test_compactCountsStayReadableWithoutLoadingCardArt() {
        compare(dock.height, Theme.size(30))
        for (const value of [{zone:"library", count:43}, {zone:"graveyard", count:2},
                             {zone:"exile", count:1}, {zone:"command", count:0}]) {
            const count=findChild(dock, "rulesOpponentZoneCount-1-"+value.zone)
            const name=findChild(dock, "rulesOpponentZoneName-1-"+value.zone)
            compare(count.text, String(value.count))
            verify(count.visible && name.visible)
            verify(count.width >= count.implicitWidth)
            verify(count.mapToItem(dock, count.width, count.height).x <= dock.width)
            verify(count.mapToItem(dock, count.width, count.height).y <= dock.height)
            verify(name.width > 0)
            verify(!name.truncated)
            if (value.zone === "command")
                compare(name.text, "Command")
        }
        compare(controller.requestedNames.length, 0)
        verify(!findChild(dock, "rulesOpponentZoneCard-1-library-secret-library"))
        mouseClick(findChild(dock, "rulesOpponentZoneTile-1-library"))
        compare(controller.inspected, "")
        snapshot.zones[0].count=42
        verify(testRulesPrompt.applySnapshot(snapshot))
        tryCompare(findChild(dock, "rulesOpponentZoneCount-1-library"), "text", "42")
    }

    function test_compactTopCardRetainsHoverClickAndKeyboardInspection() {
        const top=findChild(dock, "rulesOpponentZoneCard-1-graveyard-grave-top")
        verify(top)
        compare(top.source.toString(), "")
        mouseMove(top)
        tryCompare(controller, "preview", "grave-top")
        mouseClick(top)
        compare(controller.inspected, "grave-top")
        compare(controller.inspections, 1)
        mouseMove(other)
        top.forceActiveFocus()
        tryCompare(top, "activeFocus", true)
        keyClick(Qt.Key_Return)
        compare(controller.inspected, "grave-top")
        compare(controller.inspections, 2)
        tryCompare(controller, "preview", "grave-top")
    }

    function test_fullDockRetainsCardPileArtAndHeight() {
        dock.compact=false
        compare(dock.height, Theme.size(78))
        tryVerify(() => controller.requestedNames.includes("Consider"))
        verify(!controller.requestedNames.includes("Secret library card"))
        verify(!findChild(dock,"rulesOpponentZoneCount-1-library").visible)
    }
}
