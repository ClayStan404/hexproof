// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "CardArtRepairNotice"
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 700
        height: 520
        visible: true
    }

    QtObject {
        id: mockPreferences
        property int seenVersion: 0
        property int acknowledgeCount: 0
        function cardArtRepairNoticeSeen(version) {
            return seenVersion >= version
        }
        function acknowledgeCardArtRepairNotice(version) {
            seenVersion = Math.max(seenVersion, version)
            ++acknowledgeCount
            return true
        }
    }

    QtObject {
        id: mockArtManager
        property bool repairNeeded: false
        property int faceAuditVersion: 1
    }

    property var popup: null

    Component {
        id: popupComponent
        CardArtRepairNoticePopup {
            preferencesModel: mockPreferences
            artManagerModel: mockArtManager
        }
    }

    function init() {
        mockPreferences.seenVersion = 0
        mockPreferences.acknowledgeCount = 0
        mockArtManager.repairNeeded = false
        popup = popupComponent.createObject(testWindow.contentItem)
        verify(popup !== null)
    }

    function cleanup() {
        if (popup !== null)
            popup.destroy()
        popup = null
    }

    function test_noticeVersionTracksManagerAuditVersion() {
        // The notice version must derive from the manager's audit version so a
        // future kCardFaceAuditVersion bump re-shows the notice even for users
        // who acknowledged the previous one.
        compare(popup.noticeVersion, 1)
        mockArtManager.faceAuditVersion = 2
        compare(popup.noticeVersion, 2)
    }

    function test_onlyOpensForDetectedRepair() {
        popup.openIfNeeded()
        wait(50)
        verify(!popup.visible)

        mockArtManager.repairNeeded = true
        popup.openIfNeeded()
        tryCompare(popup, "visible", true)
    }

    function test_closingAcknowledgesThisNoticeVersion() {
        mockArtManager.repairNeeded = true
        popup.openIfNeeded()
        tryCompare(popup, "visible", true)
        popup.close()
        tryCompare(popup, "visible", false)
        tryCompare(mockPreferences, "acknowledgeCount", 1)
        compare(mockPreferences.seenVersion, popup.noticeVersion)

        popup.openIfNeeded()
        wait(50)
        verify(!popup.visible)
        compare(mockPreferences.acknowledgeCount, 1)
    }
}
