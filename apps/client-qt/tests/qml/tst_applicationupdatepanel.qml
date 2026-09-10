// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "ApplicationUpdatePanel"
    when: windowShown

    ApplicationWindow {
        id: window
        width: 900
        height: 620
        visible: true
    }
    QtObject {
        id: updateModel
        property bool checking: false
        property bool downloading: false
        property bool downloadReady: false
        property bool updateAvailable: true
        property bool exactVersion: true
        property bool releaseAvailable: true
        property string currentVersion: "1.0.6"
        property string targetVersion: "1.0.7"
        property string publishedAt: "2026-09-10"
        property string releaseNotes: "A verified update for the current server version."
        property real progress: 0.45
        property string lastError: ""
        property string lastAction: ""
        function checkForUpdates() { lastAction = "check" }
        function downloadUpdate() { lastAction = "download" }
        function cancelDownload() { lastAction = "cancel" }
        function openDownloadLocation() { lastAction = "folder" }
        function openReleasePage() { lastAction = "release" }
    }
    Component {
        id: panelComponent
        ScrollView {
            id: viewport
            property alias panel: updatePanel
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ApplicationUpdatePanel {
                id: updatePanel
                width: viewport.availableWidth
                updater: updateModel
            }
        }
    }
    function init() {
        updateModel.checking = false
        updateModel.downloading = false
        updateModel.downloadReady = false
        updateModel.lastAction = ""
    }
    function cleanup() { Theme.uiScale = 1 }
    function test_actionsRemainReachable_data() {
        return [
            {tag: "normal", scale: 1},
            {tag: "large", scale: 1.5},
            {tag: "maximum", scale: 1.8},
            {tag: "maximum-short-viewport", scale: 1.8, viewportHeight: 480}
        ]
    }
    function checkBounds(panel, names) {
        verify(waitForPolish(window))
        for (const name of names) {
            const item = findChild(panel, name)
            verify(item !== null)
            verify(item.visible)
            const position = item.mapToItem(panel, 0, 0)
            verify(position.x >= 0 && position.x + item.width <= panel.width + 1,
                   name + " must remain within the panel width")
            verify(position.y >= 0 && position.y + item.height <= panel.height + 1,
                   name + " must contribute to the scrollable panel height")
        }
    }
    function clickAction(viewport, name, action) {
        verify(waitForPolish(window))
        const button = findChild(viewport.panel, name)
        verify(button !== null)
        verify(button.visible)
        verify(button.enabled)

        const scroll = viewport.contentItem
        const position = button.mapToItem(scroll.contentItem, 0, 0)
        scroll.contentY = Math.max(0, Math.min(scroll.contentHeight - scroll.height,
                                             position.y - (scroll.height - button.height) / 2))
        verify(waitForPolish(window))
        const visiblePosition = button.mapToItem(viewport, 0, 0)
        verify(visiblePosition.x >= 0
               && visiblePosition.x + button.width <= viewport.availableWidth + 1,
               name + " must be fully visible before clicking")
        verify(visiblePosition.y >= 0
               && visiblePosition.y + button.height <= viewport.availableHeight + 1,
               name + " must be fully visible before clicking")
        mouseClick(button)
        compare(updateModel.lastAction, action)
    }
    function test_actionsRemainReachable(data) {
        Theme.uiScale = data.scale
        // Settings hosts this panel in a scroll view; large content can exceed the window height.
        const viewport = createTemporaryObject(panelComponent, window.contentItem,
                                               {width: 828,
                                                height: data.viewportHeight || window.height})
        verify(viewport !== null)
        const panel = viewport.panel
        checkBounds(panel, ["applicationUpdateStatus", "checkApplicationUpdatesButton",
                            "downloadApplicationUpdateButton", "viewApplicationReleaseButton"])
        clickAction(viewport, "downloadApplicationUpdateButton", "download")
        updateModel.downloading = true
        checkBounds(panel, ["cancelApplicationUpdateButton", "viewApplicationReleaseButton"])
        verify(!findChild(panel, "downloadApplicationUpdateButton").enabled)
        verify(!findChild(panel, "checkApplicationUpdatesButton").enabled)
        clickAction(viewport, "cancelApplicationUpdateButton", "cancel")
        updateModel.downloading = false
        updateModel.downloadReady = true
        checkBounds(panel, ["openApplicationUpdateFolderButton", "viewApplicationReleaseButton"])
        clickAction(viewport, "openApplicationUpdateFolderButton", "folder")
        clickAction(viewport, "viewApplicationReleaseButton", "release")
        if (data.scale === 1.8) {
            verify(panel.height > viewport.height)
            verify(viewport.contentItem.contentY > 0)
        }
    }
}
