// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "SideboardPreviewPlacement"
    when: windowShown
    readonly property alias testWindow: harness.testWindowObject
    readonly property alias tableHost: harness.tableHostObject
    readonly property alias mockWs: harness.mockWsObject
    readonly property alias mockCatalog: harness.mockCatalogObject
    readonly property alias tableComponent: harness.tableComponentObject
    readonly property var front: ({name:"Front Card", count:1, setCode:"FCE", collectorNumber:"1"})
    readonly property var faces: [front, {name:"Reverse Card", faceName:"Reverse Card", setCode:"FCE", collectorNumber:"1"}]

    MatchLoadingTestHarness { id: harness; testCase: testCase }
    Component { id: sourceComponent; Item { x:1000; y:100; width:100; height:140 } }

    function init() {
        verify(harness.reset())
        Theme.uiScale = 1
        testWindow.width = 1400; testWindow.height = 800
        mockCatalog.faces = ({})
    }
    function cleanup() { harness.cleanupHarness() }
    function test_expandingFacesRepositionsBesideSource_data() {
        return [{tag:"first-hover", delayed:false}, {tag:"metadata-arrives", delayed:true}]
    }
    function test_expandingFacesRepositionsBesideSource(data) {
        if (!data.delayed) mockCatalog.faces = {"Front Card":faces}
        mockWs.sideboarding = true
        mockWs.gameFinished = true
        mockWs.sideboardState = {
            deadlineUnixMs:Date.now() + 300000,
            seats:[{seat:0, ready:false, mainboardCount:1, sideboardCount:0}],
            mainboard:[front], sideboard:[]
        }
        const table = createTemporaryObject(tableComponent, tableHost,
            {width:testWindow.width, height:testWindow.height})
        verify(table !== null)
        const panel = findChild(table, "sideboardPanel")
        const source = createTemporaryObject(sourceComponent, panel)
        verify(source !== null)
        verify(waitForPolish(testWindow))
        panel.inspectSideboardCard(front, source)
        const preview = findChild(panel, "sideboardHoverPreview")
        tryCompare(preview, "visible", true)
        if (data.delayed) {
            fuzzyCompare(preview.width, Theme.size(320), 0.1,
                "The original single-face preview remains 320 units wide")
            mockCatalog.faces = {"Front Card":faces}
            mockCatalog.imageRevision++
        }
        const gallery = findChild(preview, "sideboardHoverPreviewFaces")
        tryCompare(gallery, "faceCount", 2)
        verify(waitForPolish(testWindow))
        verify(preview.x + preview.width <= source.x - Theme.size(12) + 0.1,
            "Expanded faces must remain wholly beside their source: "
            + JSON.stringify({sourceX:source.x, storedX:panel.hoverPreviewX,
                x:preview.x, width:preview.width, right:preview.x + preview.width}))
        fuzzyCompare(preview.x + preview.width, source.x - Theme.size(12), 0.1)
        compare(mockWs.sideboardMoveCount, 0)
        panel.inspectSideboardCard({name:"Single Card"}, source)
        tryCompare(gallery, "faceCount", 1)
        verify(waitForPolish(testWindow))
        fuzzyCompare(preview.width, Theme.size(320), 0.1)
        fuzzyCompare(preview.x + preview.width, source.x - Theme.size(12), 0.1,
            "Returning to a single face retains the original size and adjacent side")
        compare(mockWs.sideboardMoveCount, 0)
    }
    function test_singleFaceRetainsCompactPanelProportion() {
        testWindow.width = 900; testWindow.height = 620
        mockWs.sideboarding = true
        mockWs.gameFinished = true
        mockWs.sideboardState = {
            deadlineUnixMs:Date.now() + 300000,
            seats:[{seat:0, ready:false, mainboardCount:1, sideboardCount:0}],
            mainboard:[front], sideboard:[]
        }
        const table = createTemporaryObject(tableComponent, tableHost,
            {width:testWindow.width, height:testWindow.height})
        verify(table !== null)
        const panel = findChild(table, "sideboardPanel")
        const source = createTemporaryObject(sourceComponent, panel, {x:600})
        verify(waitForPolish(testWindow))
        panel.inspectSideboardCard(front, source)
        const preview = findChild(panel, "sideboardHoverPreview")
        tryCompare(preview, "visible", true)
        verify(waitForPolish(testWindow))
        fuzzyCompare(preview.width, Math.min(Theme.size(320), panel.width * 0.25), 0.1,
            "The ordinary single face retains the public quarter-panel cap")
        verify(preview.x + preview.width <= source.x - Theme.size(12) + 0.1)
    }
}
