// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "TableOptimisticTimeouts"
    when: windowShown

    readonly property alias testWindow: harness.testWindowObject
    readonly property alias tableHost: harness.tableHostObject
    readonly property alias tableComponent: harness.tableComponentObject

    MatchLoadingTestHarness {
        id: harness
        testCase: testCase
    }

    Timer {
        id: staggerTimer
        interval: 500
        repeat: false
        property var callback: null
        onTriggered: {
            const pending = callback
            callback = null
            if (pending)
                pending()
        }
    }

    function init() {
        staggerTimer.stop()
        staggerTimer.callback = null
        verify(harness.reset())
    }

    function cleanup() {
        staggerTimer.stop()
        staggerTimer.callback = null
        harness.cleanupHarness()
    }

    function test_optimisticValuesExpireIndependently() {
        const table = tableComponent.createObject(tableHost, {
            "width": testWindow.width,
            "height": testWindow.height,
            "optimisticValueTimeoutMs": 1500
        })
        verify(table !== null)

        table.optimisticCommandModel.lifeValues = ({"0": 19})
        table.optimisticCommands.trackOptimisticValues("life", ["0"])
        staggerTimer.callback = function() {
            table.optimisticCommandModel.counterValues = ({
                "0:counter-1": 1
            })
            table.optimisticCommands.trackOptimisticValues(
                        "counter", ["0:counter-1"])
        }
        staggerTimer.start()

        tryVerify(() => Object.prototype.hasOwnProperty.call(
                      table.optimisticCounterValues, "0:counter-1"), 3000)
        tryVerify(() => !Object.prototype.hasOwnProperty.call(
                      table.optimisticLifeTotals, "0"), 4000)
        verify(Object.prototype.hasOwnProperty.call(
                   table.optimisticCounterValues, "0:counter-1"))
        tryVerify(() => !Object.prototype.hasOwnProperty.call(
                      table.optimisticCounterValues, "0:counter-1"), 4000)
        table.destroy()
    }
}
