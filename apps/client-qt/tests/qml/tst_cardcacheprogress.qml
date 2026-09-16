// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "CardCacheProgress"
    when: windowShown

    QtObject {
        id: catalog
        property bool busy: false
        property bool cacheProgressActive: busy
        property bool searchPreviewBusy: false
        property bool searching: false
        property bool tokenSearching: false
        property real progress: 0
        property string status: "Caching card images…"
    }
    ApplicationWindow {
        id: window
        width: 600
        height: 160
        visible: true
        CardCacheProgress {
            id: panel
            width: parent.width - 40
            x: 20
            y: 20
            catalogModel: catalog
        }
    }

    function init() {
        catalog.busy = false
        catalog.cacheProgressActive = Qt.binding(() => catalog.busy)
        catalog.searchPreviewBusy = false
        catalog.searching = false
        catalog.tokenSearching = false
        catalog.progress = 0
        window.width = 600
        Theme.uiScale = 1
    }

    function cleanup() { Theme.uiScale = 1 }

    function test_tracksProgress_data() {
        return [
            {tag: "start", progress: 0, expected: 0, label: "0%"},
            {tag: "partial", progress: 0.375, expected: 0.375, label: "38%"},
            {tag: "complete", progress: 1, expected: 1, label: "100%"},
            {tag: "negative", progress: -1, expected: 0, label: "0%"},
            {tag: "overflow", progress: 2, expected: 1, label: "100%"}
        ]
    }
    function test_tracksProgress(data) {
        verify(!panel.visible)
        catalog.busy = true
        catalog.progress = data.progress
        tryCompare(panel, "visible", true)
        const bar = findChild(panel, "cardCacheProgressBar")
        const percent = findChild(panel, "cardCacheProgressPercent")
        compare(bar.value, data.expected)
        compare(percent.text, data.label)
        verify(!bar.indeterminate)
        catalog.busy = false
        tryCompare(panel, "visible", false)
    }

    function test_searchDoesNotMasqueradeAsCaching() {
        catalog.busy = true
        catalog.searching = true
        verify(!panel.visible)
        catalog.searching = false
        verify(panel.visible)
        catalog.tokenSearching = true
        verify(!panel.visible)
    }

    function test_speculativePreviewsDoNotAppearAsDeckDownloads() {
        catalog.busy = true
        catalog.cacheProgressActive = false
        catalog.searchPreviewBusy = true
        verify(!panel.visible)
        catalog.cacheProgressActive = true
        verify(panel.visible)
        catalog.status = "Caching Razorkin Hordecaller…"
        compare(findChild(panel, "cardCacheProgressStatus").text, "Caching card images…")
    }

    function test_fitsNarrowScaledPanel() {
        catalog.busy = true
        catalog.progress = 0.5
        window.width = 250
        Theme.uiScale = 1.5
        waitForRendering(panel)
        for (const name of ["cardCacheProgressStatus", "cardCacheProgressPercent", "cardCacheProgressBar"]) {
            const item = findChild(panel, name)
            const position = item.mapToItem(panel, 0, 0)
            verify(item.width > 0 && item.height > 0)
            verify(position.x >= 0 && position.x + item.width <= panel.width + 1)
            verify(position.y >= 0 && position.y + item.height <= panel.height + 1)
        }
    }
}
