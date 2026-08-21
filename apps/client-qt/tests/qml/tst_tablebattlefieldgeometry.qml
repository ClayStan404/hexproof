// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "TableBattlefieldGeometry"

    QtObject {
        id: fakeWs
        property string roomRole: "player"
        property int seatIndex: 1
    }

    QtObject {
        id: fakeRoomSession
        property string role: fakeWs.roomRole
        property int seatIndex: fakeWs.seatIndex
    }

    QtObject {
        id: fakeTable
        property var wsModel: fakeWs
        property var roomSession: fakeRoomSession
        property var preferencesModel: fakePreferences
        property bool usesEDHBattlefieldLayout: true
        property bool edhFocusLayout: edhBattlefieldLayout === "focus"
        property int edhFocusedSeat: -1
        property string edhBattlefieldLayout: "grid"
        property var battlefieldSeats: [
            {"seat": 2}, {"seat": 3}, {"seat": 1}, {"seat": 0}
        ]
    }

    QtObject {
        id: fakePreferences
        property real tableOverviewCardScale: 0
        property real tableFocusCardScale: 0
    }

    TableBattlefieldGeometry {
        id: geometry
        tableRoot: fakeTable
    }

    function init() {
        fakeTable.edhFocusedSeat = -1
        fakeTable.edhBattlefieldLayout = "grid"
        fakeTable.battlefieldSeats = [
            {"seat": 2}, {"seat": 3}, {"seat": 1}, {"seat": 0}
        ]
        fakeWs.roomRole = "player"
        fakeWs.seatIndex = 1
        fakeTable.usesEDHBattlefieldLayout = true
        fakePreferences.tableOverviewCardScale = 0
        fakePreferences.tableFocusCardScale = 0
    }

    function test_focusSeatUpdatesLayout() {
        geometry.focusSeat(3)
        compare(fakeTable.edhFocusedSeat, 3)
        compare(fakeTable.edhBattlefieldLayout, "focus")
        compare(geometry.effectiveFocusSeat(), 3)
    }

    function test_invalidFocusIsIgnored() {
        geometry.focusSeat(-1)
        compare(fakeTable.edhFocusedSeat, -1)
        compare(fakeTable.edhBattlefieldLayout, "grid")
    }

    function test_toggleFocusSeatReturnsToOverview() {
        geometry.toggleFocusSeat(3)
        compare(fakeTable.edhFocusedSeat, 3)
        compare(fakeTable.edhBattlefieldLayout, "focus")

        geometry.toggleFocusSeat(3)
        compare(fakeTable.edhFocusedSeat, 3)
        compare(fakeTable.edhBattlefieldLayout, "grid")

        geometry.toggleFocusSeat(2)
        compare(fakeTable.edhFocusedSeat, 2)
        compare(fakeTable.edhBattlefieldLayout, "focus")
    }

    function test_fourPlayerTopRowMirrorsAndBottomRowDoesNot() {
        verify(geometry.mirrorsSeat(2))
        verify(geometry.mirrorsSeat(3))
        verify(!geometry.mirrorsSeat(1))
        verify(!geometry.mirrorsSeat(0))

        const stored = geometry.positionFromView(2, 0.25, 0.2)
        compare(stored.x, 0.25)
        compare(stored.y, 0.8)
        verify(Math.abs(geometry.yForView(2, stored.y, 0) - 0.2)
               < 0.000001)

        const bottomStored = geometry.positionFromView(0, 0.25, 0.8)
        compare(bottomStored.x, 0.25)
        compare(bottomStored.y, 0.8)
        compare(geometry.yForView(0, bottomStored.y, 0), 0.8)
    }

    function test_spectatorUsesTheSameOverviewRowOrientation() {
        fakeWs.roomRole = "spectator"
        fakeWs.seatIndex = -1
        fakeTable.battlefieldSeats = [
            {"seat": 0}, {"seat": 1}, {"seat": 2}, {"seat": 3}
        ]

        verify(geometry.mirrorsSeat(0))
        verify(geometry.mirrorsSeat(1))
        verify(!geometry.mirrorsSeat(2))
        verify(!geometry.mirrorsSeat(3))
    }

    function test_threePlayerLayoutUsesOwnSeatAsWideLane() {
        fakeTable.battlefieldSeats = [
            {"seat": 2}, {"seat": 0}, {"seat": 1}
        ]
        compare(geometry.overviewWideSeat(), 1)
        compare(geometry.focusLaneCount(), 2)
        compare(geometry.automaticCardScale, 0.8)
        verify(geometry.mirrorsSeat(2))
        verify(geometry.mirrorsSeat(0))
        verify(!geometry.mirrorsSeat(1))

        fakeWs.roomRole = "spectator"
        fakeWs.seatIndex = -1
        compare(geometry.overviewWideSeat(), 1)
        verify(geometry.mirrorsSeat(2))
        verify(geometry.mirrorsSeat(0))
        verify(!geometry.mirrorsSeat(1))
    }

    function test_cardScaleUsesSeparateOverviewAndFocusPreferences() {
        compare(geometry.automaticCardScale, 0.7)
        compare(geometry.cardScale, 0.7)
        verify(geometry.automaticCardScaleEnabled)

        geometry.adjustCardScale(1)
        compare(fakePreferences.tableOverviewCardScale, 0.75)
        compare(geometry.cardScale, 0.75)
        verify(!geometry.automaticCardScaleEnabled)

        geometry.focusSeat(2)
        compare(geometry.automaticCardScale, 1.0)
        compare(geometry.cardScale, 1.0)
        geometry.adjustCardScale(-1)
        compare(fakePreferences.tableFocusCardScale, 0.95)
        compare(geometry.cardScale, 0.95)

        fakeTable.edhBattlefieldLayout = "grid"
        compare(geometry.cardScale, 0.75)
        geometry.resetCardScale()
        compare(fakePreferences.tableOverviewCardScale, 0.0)
        compare(geometry.cardScale, 0.7)
    }

    function test_cardScaleDefaultsToFullSizeOutsideEdhOverview() {
        fakeTable.usesEDHBattlefieldLayout = false
        compare(geometry.automaticCardScale, 1.0)
        compare(geometry.cardScale, 1.0)
        geometry.setCardScale(2.0)
        compare(fakePreferences.tableFocusCardScale, 1.25)
        geometry.setCardScale(0.1)
        compare(fakePreferences.tableFocusCardScale, 0.5)
    }
}
