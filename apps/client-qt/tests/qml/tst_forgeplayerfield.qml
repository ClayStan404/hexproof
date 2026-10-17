// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "ForgePlayerField"
    when: windowShown
    Component {
        id: sourceProbeComponent
        Item {
            property string cardId: "anchor-source"
            property real visualDx: 0
            property real visualDy: 0
            x: 20; y: 20; width: 40; height: 30
            transform: Translate { x: visualDx; y: visualDy }
        }
    }
    Component {
        id: headerArrowComponent
        ForgeArrow {
            width: fieldPresentation.width; height: fieldPresentation.height
            z: 80
            preview: true
            excludedRects: fields.readoutRects(fieldPresentation)
        }
    }
    ApplicationWindow { id: window; width: 1920; height: 1011; visible: true }
    QtObject {
        id: controller
        property var rulesSession: testRulesPrompt.session
        property var cardCatalogModel: null
        property url cardBackSource: ""
        property bool canViewSpectatorHands: false
        property int spectatedHandSeat: -1
        property int handOwnerSeat: 0
        property int localSeat: 0
        property var interaction: ({seatOffered: () => false, seatSelected: () => false,
            objectSelected: () => false, contextActive:false,
            canRespond: false, waitingForResponse: false, fanOwner: null})
        property var combatInteraction: ({active: false, canAct: false, hoveredTarget: null})
        function zoneCount(seat, zone) { return zone === "library" ? 90 : zone === "hand" ? 7 : 0 }
        function zoneLabel(zone) { return zone }
        function topPublicZoneCard() { return null }
        function beginCardPreview() {}
        function endCardPreview() {}
    }
    Item {
        id: fieldPresentation
        parent: window.contentItem
        width: window.width; height: window.height
        property var tableController: controller
        property real unit: Math.min(width / 1600, height / 1000)
        property real boardWidth: width
        property var playerSeats: [0, 1, 2, 3]
        property int bottomSeat: 0
        property bool multiplayer: true
        property bool phaseTrackVisible: true
        property real centerBandHeight: 60 * unit
        property bool turnReady: true
        property int locatedSeat: -1
        property string locatedId: ""
        property var openedZones: []
        property alias decisionDock: dock
        property rect dockReservation: Qt.rect(dock.x, height - 12 * unit - Theme.size(120),
                                               dock.width, Theme.size(120))
        function actionClockText() { return "" }
        function unobscuredRight() { return boardWidth }
        function fieldObstacles(originX, originY) {
            if (!dock.visible) return []
            const margin = 12 * unit, area = dockReservation
            return [Qt.rect(area.x - margin - originX, area.y - margin - originY,
                area.width + 2 * margin, area.height + 2 * margin)]
        }
        function openZone(seat, zone) { openedZones = openedZones.concat([{seat: seat, zone: zone}]) }
        ForgeMultiplayerBattlefield {
            id: fields
            presentation: fieldPresentation
            x: 10; y: 10; width: fieldPresentation.boardWidth - 20; height: window.height * 0.85
        }
        Rectangle {
            id: dock
            x: fieldPresentation.boardWidth - width - 16 * fieldPresentation.unit
            y: fieldPresentation.height - height - 12 * fieldPresentation.unit
            width: Math.min(window.width * 0.3, Math.max(330 * fieldPresentation.unit, Theme.size(280)))
            height: Theme.size(100)
        }
        ForgeArrow {
            id: anchorProbe
            anchors.fill: parent
            startPoint: fields.pointFor("anchor-source", fieldPresentation)
            endPoint: fields.playerPoint(1, fieldPresentation)
        }
    }
    function init() {
        window.width = 1920; window.height = 1011
        Theme.uiScale = 1; Theme.motionEnabled = false
        fieldPresentation.boardWidth = Qt.binding(() => fieldPresentation.width)
        fieldPresentation.playerSeats = [0, 1, 2, 3]
        fieldPresentation.openedZones = []
        fields.y = 10
        controller.canViewSpectatorHands = false
        dock.height = Qt.binding(() => Theme.size(100))
        const players = [], zones = []
        for (let seat = 0; seat < 4; ++seat) {
            players.push({seat: seat, name: "Preview Player " + (seat + 1), life: 40, status: "playing"})
            zones.push({ownerSeat: seat, zone: "battlefield", count: 0, cards: []})
        }
        verify(testRulesPrompt.applySnapshot({roomId: "FIELDS", gameId: "headers", turn: 8,
            step: "declare_blockers", activeSeat: 0, prioritySeat: 0, players: players, zones: zones, stack: []}))
        window.requestActivate()
        tryCompare(window, "active", true)
    }
    function cleanup() { testRulesPrompt.clear(); Theme.uiScale = 1 }
    function bounds(item) { return item.mapToItem(fieldPresentation, 0, 0, item.width, item.height) }
    function intersects(a, b) {
        return a.x < b.x + b.width - 0.5 && a.x + a.width > b.x + 0.5
            && a.y < b.y + b.height - 0.5 && a.y + a.height > b.y + 0.5
    }
    function assertReadableSeat(seat, clickZones) {
        const field = fields.fieldFor(seat)
        verify(field !== null)
        const life = findChild(fieldPresentation, "rulesPlayerTarget" + seat)
        const name = findChild(fieldPresentation, "forgePlayerName-" + seat)
        const hand = findChild(fieldPresentation, "forgePlayerZones-" + seat)
        verify(name.width > 0 && !name.truncated, "The player name must remain readable beside inspection and decisions")
        verify(hand.width > 0 && !hand.truncated, "The Hand count must remain readable")
        verify(!intersects(bounds(name), bounds(life)))
        verify(!intersects(bounds(name), bounds(dock)))
        for (const zone of ["library", "graveyard", "exile", "command"]) {
            const pile = findChild(fieldPresentation, "forgeSeatZone-" + seat + "-" + zone)
            const label = findChild(pile, "forgeZoneSummary")
            verify(label.paintedWidth <= label.width + 0.5, "The complete " + zone + " label must fit")
            verify(!intersects(bounds(pile), bounds(life)), "A zone must not overlap the life disc")
            verify(!intersects(bounds(pile), bounds(name)), "A zone must not overlap the player name")
            verify(!intersects(bounds(pile), bounds(dock)), "A public zone must stay clear of the decision")
            if (clickZones) {
                mouseClick(pile)
                compare(fieldPresentation.openedZones[fieldPresentation.openedZones.length - 1], {seat: seat, zone: zone})
            }
        }
    }
    function test_inspectionKeepsPlayerIdentityAndZonesReadable_data() {
        return [{tag: "maximized-scaled", width: 1920, height: 1011, scale: 1.9, side: 440},
                {tag: "compact-scaled", width: 900, height: 620, scale: 1.2, side: 360},
                {tag: "spectator-mana", width: 1920, height: 1011, scale: 1.9, side: 440, spectator: true}]
    }
    function test_inspectionKeepsPlayerIdentityAndZonesReadable(data) {
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        waitForRendering(fields)
        assertReadableSeat(1)
        if (data.spectator) {
            controller.canViewSpectatorHands = true
            fields.fieldFor(1).manaPool = [{color: "W", amount: 2}, {color: "U", amount: 1}]
        }
        fieldPresentation.boardWidth = window.width - data.side
        verify(waitForPolish(window))
        waitForRendering(fields)
        assertReadableSeat(1, true)
        if (data.spectator) {
            const viewHand = findChild(fieldPresentation, "forgeViewHand-1")
            const mana = findChild(fieldPresentation, "forgeManaPool-1")
            verify(!intersects(bounds(viewHand), bounds(mana)))
            verify(!intersects(bounds(viewHand), bounds(dock)))
            mouseClick(viewHand)
            compare(controller.spectatedHandSeat, 1)
        }
        if (fields.fieldFor(1).headerAboveDock) {
            // Ordinary controls can grow within their stable reservation.
            // Expanded decisions are hideable overlays, covered by the real
            // RulesTable integration rather than this metadata-only fixture.
            dock.height = Math.min(dock.height + Theme.size(30), fieldPresentation.dockReservation.height)
            verify(waitForPolish(window))
            waitForRendering(fields)
            assertReadableSeat(1)
        }
        fieldPresentation.boardWidth = window.width
        verify(waitForPolish(window))
        waitForRendering(fields)
        assertReadableSeat(1)
    }
    function test_arrowBindingsFollowHeaderAndAncestorMovement_data() {
        return [{tag: "maximized-pin", width: 1920, height: 1011, scale: 1.9, side: 440},
                {tag: "compact-dock", width: 900, height: 620, scale: 1.2, side: 360}]
    }
    function test_arrowBindingsFollowHeaderAndAncestorMovement(data) {
        window.width = data.width; window.height = data.height; Theme.uiScale = data.scale
        // Empty categories now surrender their allocation. Give this geometry
        // probe a projected creature so it exercises a real occupied lane.
        const players = [], zones = []
        for (let seat = 0; seat < 4; ++seat) {
            players.push({seat:seat, name:"Preview Player " + (seat + 1), life:40, status:"playing"})
            const cards = seat === 1 ? [{id:"anchor-source", ownerSeat:1, controllerSeat:1,
                visible:false, power:"1", toughness:"1"}] : []
            zones.push({ownerSeat:seat, zone:"battlefield", count:cards.length, cards:cards})
        }
        verify(testRulesPrompt.applySnapshot({roomId:"FIELDS", gameId:"headers", turn:8,
            step:"declare_blockers", activeSeat:0, prioritySeat:0, players:players, zones:zones, stack:[]}))
        verify(waitForPolish(window))
        const lane = findChild(fields, "forgeCreatures-1")
        verify(lane !== null)
        compare(lane.stackCount, 1)
        // Only the card slot geometry is synthetic. The lane, field, player
        // target and ForgeArrow use their production coordinate functions.
        const source = createTemporaryObject(sourceProbeComponent, lane.scrollArea.contentItem)
        verify(source !== null)
        // Keep the synthetic anchor visible while the pinned inspector leaves
        // a short scroll viewport; this test exercises binding propagation.
        source.y = Qt.binding(() => lane.scrollArea.contentY + lane.scrollArea.height / 2 - source.height / 2)
        lane.visibleCards = [source]
        const life = findChild(fieldPresentation, "rulesPlayerTarget1")
        function verifyBoundAnchors(stage) {
            verify(waitForPolish(window))
            waitForRendering(fields)
            const expectedEnd = life.mapToItem(fieldPresentation, life.width / 2, life.height / 2)
            const expectedStart = source.mapToItem(fieldPresentation, source.width / 2, source.height / 2)
            // Read the persistent arrow bindings. Calling playerPoint/pointFor
            // here would hide missing dependency notifications after a move.
            compare(anchorProbe.endPoint, expectedEnd, stage + ": player anchor follows the life disc")
            fuzzyCompare(anchorProbe.startPoint.x, expectedStart.x, 0.000001, stage + ": card x follows its field")
            fuzzyCompare(anchorProbe.startPoint.y, expectedStart.y, 0.000001, stage + ": card y follows its field")
        }
        try {
            verifyBoundAnchors("initial")
            fieldPresentation.boardWidth = window.width - data.side
            verifyBoundAnchors("inspection opened")
            dock.height += Theme.size(30)
            verifyBoundAnchors("decision grew")
            fields.y += 17
            verifyBoundAnchors("battlefield ancestor moved")
            fieldPresentation.boardWidth = window.width
            verifyBoundAnchors("inspection closed")
        } finally {
            lane.visibleCards = []
        }
    }
    function test_headerReadoutsStayAboveCrossingAim_data() {
        return [{tag:"maximized", width:1920, height:1011, scale:1, side:0},
            {tag:"pinned-scaled", width:1920, height:1011, scale:1.9, side:440}]
    }
    function test_headerReadoutsStayAboveCrossingAim(data) {
        window.width=data.width; window.height=data.height; Theme.uiScale=data.scale
        controller.canViewSpectatorHands=true
        fields.fieldFor(1).manaPool=[{color:"W",amount:2},{color:"U",amount:1}]
        fieldPresentation.boardWidth=window.width-data.side
        verify(waitForPolish(window)); verify(waitForRendering(fields))
        const name=findChild(fieldPresentation,"forgePlayerName-1")
        const hand=findChild(fieldPresentation,"forgePlayerZones-1")
        const status=findChild(fieldPresentation,"forgeSeatStatus-0")
        const zone=findChild(fieldPresentation,"forgeSeatZone-1-library")
        const summary=findChild(zone,"forgeZoneSummary")
        const life=findChild(fieldPresentation,"forgeLifeValue-1")
        const mana=findChild(fieldPresentation,"forgeManaPool-1")
        const viewHand=findChild(fieldPresentation,"forgeViewHand-1")
        const arrow=createTemporaryObject(headerArrowComponent,fieldPresentation)
        verify(arrow !== null)
        for (const region of [name,hand,status,summary,life,mana,viewHand.contentItem]) {
            verify(region.visible && region.width>0 && region.height>0)
            const width=region.paintedWidth !== undefined ? Math.min(region.width,region.paintedWidth) : region.width
            const height=region.paintedHeight !== undefined ? Math.min(region.height,region.paintedHeight) : region.height
            const dx=region.horizontalAlignment===Text.AlignHCenter ? (region.width-width)/2 : 0
            const dy=region.verticalAlignment===Text.AlignVCenter ? (region.height-height)/2 : 0
            const rect=region.mapToItem(fieldPresentation,dx,dy,width,height)
            arrow.startPoint=Qt.point(rect.x-40,rect.y+rect.height/2)
            arrow.endPoint=Qt.point(rect.x+rect.width/2,rect.y+rect.height/2)
            const endpoint=arrow.endPoint
            verify(waitForRendering(fieldPresentation)); const painted=grabImage(fieldPresentation)
            arrow.visible=false
            verify(waitForRendering(fieldPresentation)); const plain=grabImage(fieldPresentation)
            let changes=0
            const scale=painted.width/fieldPresentation.width
            for (let y=Math.ceil((rect.y+1)*scale);y<Math.floor((rect.y+rect.height-1)*scale);++y)
                for (let x=Math.ceil((rect.x+1)*scale);x<Math.floor((rect.x+rect.width-1)*scale);++x)
                    if (painted.pixel(x,y)!==plain.pixel(x,y)) ++changes
            compare(changes,0,"Aiming must not paint over public header readout "+region.objectName)
            compare(arrow.endPoint,endpoint,"Text clipping must preserve the exact target")
            arrow.visible=true
        }
    }
    function test_headerReadoutBindingsFollowReflowAndLifeDelta() {
        Theme.motionEnabled=true
        const probe=createTemporaryObject(headerArrowComponent,fieldPresentation)
        verify(probe !== null)
        function covered(label) {
            const point=label.mapToItem(fieldPresentation,label.width/2,label.height/2)
            return probe.excludedRects.some(rect=>point.x>=rect.x && point.x<=rect.x+rect.width
                && point.y>=rect.y && point.y<=rect.y+rect.height)
        }
        const value=findChild(fieldPresentation,"forgeLifeValue-1")
        verify(covered(value))
        fieldPresentation.boardWidth=window.width-440
        dock.height+=Theme.size(30)
        fields.y+=17
        verify(waitForPolish(window));verify(waitForRendering(fields))
        verify(covered(value),"The persistent exclusion binding follows the moved header")
        const players=[],zones=[]
        for (let seat=0;seat<4;++seat) {
            players.push({seat:seat,name:"Preview Player "+(seat+1),life:seat===1?37:40,status:"playing"})
            zones.push({ownerSeat:seat,zone:"battlefield",count:0,cards:[]})
        }
        verify(testRulesPrompt.applySnapshot({roomId:"FIELDS",gameId:"headers",turn:8,
            step:"declare_blockers",activeSeat:0,prioritySeat:0,players:players,zones:zones,stack:[]}))
        const delta=findChild(fieldPresentation,"forgeLifeDelta-1")
        for (const delay of [40,90,150]) {
            wait(delay);verify(waitForRendering(fields))
            verify(delta.opacity>0)
            verify(covered(delta),"The visible life delta remains protected while rising")
        }
        const withDelta=probe.excludedRects.length
        Theme.finishMotion()
        tryCompare(delta,"opacity",0)
        tryCompare(probe.excludedRects,"length",withDelta-1)
        verify(covered(value))
    }
}
