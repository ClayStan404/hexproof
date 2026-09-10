// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtTest
import "../../qml" as App

TestCase {
    id: testCase
    name: "ProfileUnavailable"
    when: windowShown

    Component {
        id: noticeComponent
        App.ProfileUnavailable { }
    }

    function test_minimumWindow_data() {
        return [{tag: "occupied", occupied: true},
                {tag: "unwritable", occupied: false}]
    }

    function test_minimumWindow(data) {
        const notice = noticeComponent.createObject(testCase, {
            profileOccupied: data.occupied, windowTitle: "Hexproof — Duplicate test",
            width: 360, height: 260
        })
        verify(notice !== null)
        compare(notice.title, "Hexproof — Duplicate test")
        const closeButton = findChild(notice.contentItem, "closeProfileNotice")
        verify(closeButton !== null)
        waitForRendering(closeButton)
        const point = closeButton.mapToItem(notice.contentItem, 0, 0)
        verify(point.x >= 0 && point.y >= 0)
        verify(point.x + closeButton.width <= notice.width)
        verify(point.y + closeButton.height <= notice.height)
        mouseClick(closeButton)
        tryCompare(notice, "visible", false)
        notice.destroy()
    }
}
