// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

QtObject {
    id: root

    property var rooms: []
    property string searchText: ""
    property string availabilityFilter: "all"
    property string phaseFilter: "all"
    property string accessFilter: "all"
    property string formatFilter: "all"
    property string sortMode: "joinable"

    readonly property var visibleRooms: query(rooms, searchText, availabilityFilter,
                                              phaseFilter, accessFilter, formatFilter,
                                              sortMode)
    readonly property bool hasActiveFilters: searchText.trim().length > 0
                                             || availabilityFilter !== "all"
                                             || phaseFilter !== "all"
                                             || accessFilter !== "all"
                                             || formatFilter !== "all"
                                             || sortMode !== "joinable"

    function normalizedSearch(text) {
        return String(text || "").trim().toLowerCase()
    }

    function matches(room, searchText, availabilityFilter, phaseFilter, accessFilter,
                     formatFilter) {
        if (!room)
            return false
        const needle = normalizedSearch(searchText)
        if (needle.length > 0) {
            const name = String(room.name || "").toLowerCase()
            const roomId = String(room.roomId || "").toLowerCase()
            if (name.indexOf(needle) < 0 && roomId.indexOf(needle) < 0)
                return false
        }
        if (availabilityFilter === "joinable" && room.playerJoinable !== true)
            return false
        if (availabilityFilter === "watchable" && room.spectatorJoinable !== true)
            return false
        if (phaseFilter === "waiting" && room.phase !== "waiting")
            return false
        if (phaseFilter === "in_game" && room.phase !== "started"
                && room.phase !== "loading")
            return false
        if (accessFilter === "open" && room.hasPassword === true)
            return false
        if (accessFilter === "locked" && room.hasPassword !== true)
            return false
        if (formatFilter !== "all" && String(room.format || "") !== formatFilter)
            return false
        return true
    }

    function phaseRank(phase) {
        if (phase === "waiting")
            return 0
        if (phase === "loading")
            return 1
        if (phase === "started")
            return 2
        return 3
    }

    function compareRooms(left, right, sortMode) {
        if (sortMode === "name") {
            const nameCmp = String(left.name || "").localeCompare(
                              String(right.name || ""))
            if (nameCmp !== 0)
                return nameCmp
            return String(left.roomId || "").localeCompare(String(right.roomId || ""))
        }
        if (sortMode === "seats") {
            const leftOpen = Number(left.maxSeats || 0) - Number(left.playerCount || 0)
            const rightOpen = Number(right.maxSeats || 0) - Number(right.playerCount || 0)
            if (leftOpen !== rightOpen)
                return rightOpen - leftOpen
            return String(left.name || "").localeCompare(String(right.name || ""))
        }
        if (left.playerJoinable !== right.playerJoinable)
            return left.playerJoinable ? -1 : 1
        const phaseCmp = phaseRank(left.phase) - phaseRank(right.phase)
        if (phaseCmp !== 0)
            return phaseCmp
        return String(left.name || "").localeCompare(String(right.name || ""))
    }

    function copyRooms(source) {
        // ws.roomList is a C++ QVariantList sequence. QML reports .length and
        // supports indexing, but Array.isArray() is false, so slice() cannot
        // be the copy path.
        const list = []
        if (!source)
            return list
        const count = source.length
        if (typeof count !== "number")
            return list
        for (let i = 0; i < count; ++i)
            list.push(source[i])
        return list
    }

    function query(source, searchText, availabilityFilter, phaseFilter, accessFilter,
                   formatFilter, sortMode) {
        const matched = copyRooms(source).filter(room => matches(room, searchText,
                                                               availabilityFilter, phaseFilter,
                                                               accessFilter, formatFilter))
        matched.sort((left, right) => compareRooms(left, right, sortMode))
        return matched
    }

    function clearFilters() {
        searchText = ""
        availabilityFilter = "all"
        phaseFilter = "all"
        accessFilter = "all"
        formatFilter = "all"
        sortMode = "joinable"
    }
}
