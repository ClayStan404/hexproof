// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    name: "TableSeatStateController"

    TableSeatStateController {
        id: controller
        gameTableModel: testGameTable
    }

    function init() {
        testGameTable.clear()
    }

    function cleanup() {
        testGameTable.clear()
    }

    function test_indexedSnapshotLookup() {
        testGameTable.applySnapshot({"seats": [
            {"seat": 0, "displayName": "Alice"},
            {"seat": 2, "displayName": "Carol"}
        ]})

        compare(controller.seatData(2).displayName, "Carol")
        compare(Object.keys(controller.seatData(1)).length, 0)
    }
}
