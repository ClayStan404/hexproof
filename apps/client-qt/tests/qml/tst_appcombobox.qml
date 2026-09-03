// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    id: root

    name: "AppComboBox"
    property var labels: ["Server 1 · Checking", "Server 2 · Checking"]

    AppComboBox {
        id: serverSelector
        model: 2
        currentIndex: 1
        textForIndex: function(index) {
            return root.labels[index]
        }
    }

    AppComboBox {
        id: formatSelector
        model: [
            {"label": "Standard", "value": "standard"},
            {"label": "Commander", "value": "commander"}
        ]
        textRole: "label"
        valueRole: "value"
        currentIndex: 0
    }

    AppComboBox {
        id: sortSelector
        model: ["Newest", "Oldest"]
        currentIndex: 0
    }

    function init() {
        labels = ["Server 1 · Checking", "Server 2 · Checking"]
        serverSelector.currentIndex = 1
    }

    function test_dynamicLabelsPreserveSelection() {
        compare(serverSelector.currentIndex, 1)
        compare(serverSelector.displayText, "Server 2 · Checking")

        labels = ["Server 1 · 18 ms", "Server 2 · 42 ms"]

        tryCompare(serverSelector, "displayText", "Server 2 · 42 ms")
        compare(serverSelector.currentIndex, 1)
    }

    function test_defaultTextForObjectModel() {
        compare(formatSelector.currentIndex, 0)
        compare(formatSelector.displayText, "Standard")
    }

    function test_defaultTextForStringModel() {
        compare(sortSelector.currentIndex, 0)
        compare(sortSelector.displayText, "Newest")
    }
}
