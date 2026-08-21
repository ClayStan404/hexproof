// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    name: "RoomListQuery"

    RoomListQuery {
        id: query
    }

    RoomListQuery {
        id: boundQuery
        rooms: testRoomList.roomList
    }

    property var sampleRooms: [
        {
            "roomId": "WAIT01",
            "name": "Friday Modern",
            "format": "modern",
            "phase": "waiting",
            "hasPassword": false,
            "playerJoinable": true,
            "spectatorJoinable": true,
            "playerCount": 1,
            "maxSeats": 2
        },
        {
            "roomId": "LOCK02",
            "name": "Locked Duel",
            "format": "duel",
            "phase": "waiting",
            "hasPassword": true,
            "playerJoinable": true,
            "spectatorJoinable": false,
            "playerCount": 1,
            "maxSeats": 2
        },
        {
            "roomId": "PLAY03",
            "name": "Commander Night",
            "format": "edh",
            "phase": "started",
            "hasPassword": false,
            "playerJoinable": false,
            "spectatorJoinable": true,
            "playerCount": 4,
            "maxSeats": 4
        }
    ]

    function init() {
        query.rooms = sampleRooms
        query.clearFilters()
    }

    function test_defaultsKeepJoinableRoomsFirst() {
        compare(query.visibleRooms.length, 3)
        compare(query.visibleRooms[0].roomId, "WAIT01")
        compare(query.visibleRooms[1].roomId, "LOCK02")
        compare(query.visibleRooms[2].roomId, "PLAY03")
        verify(!query.hasActiveFilters)
    }

    function test_filtersByJoinabilityPhaseAccessAndFormat() {
        query.availabilityFilter = "joinable"
        compare(query.visibleRooms.length, 2)
        query.accessFilter = "locked"
        compare(query.visibleRooms.length, 1)
        compare(query.visibleRooms[0].roomId, "LOCK02")

        query.clearFilters()
        query.phaseFilter = "in_game"
        query.formatFilter = "edh"
        compare(query.visibleRooms.length, 1)
        compare(query.visibleRooms[0].roomId, "PLAY03")
        verify(query.hasActiveFilters)
    }

    function test_searchesNameOrRoomCodeAndCanClear() {
        query.searchText = "wait01"
        compare(query.visibleRooms.length, 1)
        compare(query.visibleRooms[0].name, "Friday Modern")
        query.searchText = "commander"
        compare(query.visibleRooms.length, 1)
        compare(query.visibleRooms[0].roomId, "PLAY03")
        query.clearFilters()
        compare(query.searchText, "")
        compare(query.visibleRooms.length, 3)
    }

    function test_copiesBoundCppRoomLists() {
        verify(!Array.isArray(testRoomList.roomList))
        compare(testRoomList.roomList.length, 1)
        compare(boundQuery.visibleRooms.length, 1)
        compare(boundQuery.visibleRooms[0].roomId, "WAIT01")
    }

    function test_copiesArrayLikeRoomLists() {
        const seq = {
            "0": sampleRooms[0],
            "1": sampleRooms[1],
            length: 2
        }
        verify(!Array.isArray(seq))
        query.rooms = seq
        compare(query.visibleRooms.length, 2)
        compare(query.visibleRooms[0].roomId, "WAIT01")
    }

    function test_queryUsesExplicitFilterArguments() {
        query.searchText = "wait01"
        query.availabilityFilter = "joinable"
        query.phaseFilter = "waiting"
        query.formatFilter = "modern"
        const unfiltered = query.query(query.rooms, "", "all", "all", "all", "all",
                                       "joinable")
        compare(unfiltered.length, 3)
        const locked = query.query(query.rooms, "", "all", "all", "locked", "all",
                                   "name")
        compare(locked.length, 1)
        compare(locked[0].roomId, "LOCK02")
        compare(query.visibleRooms.length, 1)
        compare(query.visibleRooms[0].roomId, "WAIT01")
    }

    function test_sortsByNameAndOpenSeats() {
        query.sortMode = "name"
        compare(query.visibleRooms[0].roomId, "PLAY03")
        compare(query.visibleRooms[1].roomId, "WAIT01")
        compare(query.visibleRooms[2].roomId, "LOCK02")
        query.sortMode = "seats"
        compare(query.visibleRooms[0].playerCount, 1)
        compare(query.visibleRooms[2].roomId, "PLAY03")
    }
}
