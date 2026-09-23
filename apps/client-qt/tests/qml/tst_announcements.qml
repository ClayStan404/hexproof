// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"
import "../../qml/screens"

TestCase {
    name: "Announcements"
    when: windowShown

    ApplicationWindow {
        id: window
        width: 1000
        height: 800
        visible: true
        function popScreen() { }
    }
    QtObject {
        id: model
        property var currentAnnouncements: []
        property var historicalAnnouncements: []
        property int unreadCount: 1
        property bool refreshing: false
        property bool refreshFailed: false
        property int refreshCount: 0
        property string readId: ""
        function refresh(force) { ++refreshCount }
        function markRead(id) { readId = id; unreadCount = 0; return true }
        function markAllRead() { unreadCount = 0; return true }
    }
    Component {
        id: screenComponent
        Announcements { contentModel: model }
    }
    function entry(id, unread) {
        return {id: id, title: "Announcement " + id, body: "Full announcement body\nSecond paragraph.",
                publishedAt: new Date("2026-09-23T12:00:00Z"), unread: unread, pinned: false}
    }
    function init() {
        window.width = 1000
        window.height = 800
        Theme.uiScale = 1
        model.currentAnnouncements = [entry("current", true)]
        model.historicalAnnouncements = [entry("past", false)]
        model.unreadCount = 1
        model.readId = ""
        model.refreshCount = 0
    }
    function cleanup() { Theme.uiScale = 1 }
    function test_readRequiresOpeningDetailsAndHistoryRemainsAvailable() {
        const screen = createTemporaryObject(screenComponent, window.contentItem,
                                             {width: window.width, height: window.height})
        waitForRendering(screen)
        compare(model.unreadCount, 1)
        compare(model.refreshCount, 1)
        const body = findChild(screen, "announcementBody_current")
        verify(!body.visible)
        mouseClick(findChild(screen, "readAnnouncement_current"))
        tryCompare(body, "visible", true)
        compare(model.readId, "current")
        compare(model.unreadCount, 0)
        mouseClick(findChild(screen, "historicalAnnouncementsButton"))
        tryVerify(() => findChild(screen, "announcement_past") !== null)
        compare(model.readId, "current")
        mouseClick(findChild(screen, "readAnnouncement_past"))
        compare(model.readId, "past")
        mouseClick(findChild(screen, "refreshPublicContentButton"))
        compare(model.refreshCount, 2)
    }
    function test_longContentWrapsAndScrollsAtLargeScale() {
        Theme.uiScale = 2
        window.width = 900
        window.height = 700
        let item = entry("long", true)
        item.title = "A long announcement title ".repeat(10)
        item.body = "公告正文与离线历史内容。".repeat(120)
        model.currentAnnouncements = [item]
        const screen = createTemporaryObject(screenComponent, window.contentItem,
                                             {width: window.width, height: window.height})
        screen.expandedId = "long"
        waitForRendering(screen)
        const body = findChild(screen, "announcementBody_long")
        verify(body.width > 0 && body.width < screen.width)
        verify(body.lineCount > 2)
        const scroll = findChild(screen, "announcementsScroll").contentItem
        verify(scroll.contentHeight > scroll.height)
        scroll.contentY = scroll.contentHeight - scroll.height
        waitForRendering(screen)
        const button = findChild(screen, "readAnnouncement_long")
        const point = button.mapToItem(screen, 0, 0)
        verify(point.x >= 0 && point.x + button.width <= screen.width)
        verify(point.y >= 0 && point.y + button.height <= screen.height)
    }
}
