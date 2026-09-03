// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"
import "../../qml/screens"

TestCase {
    name: "Sponsors"
    when: windowShown

    ApplicationWindow {
        id: testWindow
        width: 900
        height: 620
        visible: true
    }

    Component {
        id: sponsorsScreenComponent
        Sponsors { }
    }

    QtObject {
        id: mockPreferences
        property string seenAnnouncementId: ""
        property int acknowledgeCount: 0
        function sponsorAnnouncementSeen(announcementId) {
            return seenAnnouncementId === announcementId
        }
        function acknowledgeSponsorAnnouncement(announcementId) {
            seenAnnouncementId = announcementId
            ++acknowledgeCount
            return true
        }
    }

    property var popup: null

    Component {
        id: popupComponent
        SponsorAnnouncementPopup {
            preferencesModel: mockPreferences
        }
    }

    Component {
        id: supportPopupComponent
        SponsorSupportPopup { }
    }

    SignalSpy {
        id: afdianSpy
        signalName: "afdianRequested"
    }

    function init() {
        mockPreferences.seenAnnouncementId = ""
        mockPreferences.acknowledgeCount = 0
        popup = popupComponent.createObject(testWindow.contentItem)
        verify(popup !== null, "popup")
    }

    function cleanup() {
        if (popup !== null)
            popup.destroy()
        popup = null
    }

    function test_catalogContainsRequestedSponsors() {
        compare(SponsorCatalog.sponsors.length, 3)
        compare(SponsorCatalog.sponsors[0].name, "情报")
        compare(SponsorCatalog.sponsors[0].profileUrl,
                "https://space.bilibili.com/7963465")
        compare(SponsorCatalog.sponsors[1].name, "豆豆(dodo)")
        compare(SponsorCatalog.sponsors[1].profileUrl, "")
        compare(SponsorCatalog.sponsors[2].name, "M0nta9e不太奇")
        compare(SponsorCatalog.sponsors[2].profileUrl, "")
    }

    function test_catalogExposesSupportChannels() {
        compare(SponsorCatalog.afdianUrl, "https://afdian.com/a/hexproof")
        verify(SponsorCatalog.wechatPayQrSource.toString().length > 0)
        verify(SponsorCatalog.alipayPayQrSource.toString().length > 0)
    }

    function test_supportPopupShowsPaymentChannels() {
        afdianSpy.target = null
        const popup = supportPopupComponent.createObject(testWindow.contentItem)
        verify(popup !== null, "popup")
        afdianSpy.target = popup

        popup.open()
        tryCompare(popup, "visible", true)

        const wechatQr = findChild(popup, "wechatPayQr")
        verify(wechatQr !== null)
        compare(wechatQr.source, SponsorCatalog.wechatPayQrSource)
        tryCompare(wechatQr, "status", Image.Ready)

        const alipayQr = findChild(popup, "alipayPayQr")
        verify(alipayQr !== null)
        compare(alipayQr.source, SponsorCatalog.alipayPayQrSource)
        tryCompare(alipayQr, "status", Image.Ready)

        const afdianButton = findChild(popup, "afdianButton")
        verify(afdianButton !== null)
        verify(afdianButton.visible)
        afdianButton.clicked()
        compare(afdianSpy.count, 1)
        compare(afdianSpy.signalArguments[0][0], SponsorCatalog.afdianUrl)

        popup.close()
        tryCompare(popup, "visible", false)
        popup.destroy()
    }

    function test_sponsorsScreenOpensSupportPopupFromListBottom() {
        const screen = sponsorsScreenComponent.createObject(testWindow.contentItem)
        verify(screen !== null)

        // The support button sits below the sponsor list, hidden entry until clicked.
        const supportButton = findChild(screen, "supportButton")
        verify(supportButton !== null, "supportButton")
        verify(supportButton.visible, "supportButton.visible")
        const sponsorList = findChild(screen, "sponsorList")
        verify(sponsorList !== null, "sponsorList")
        // ColumnLayout child order is the on-screen stacking order; the
        // button must come after the sponsor list (layout polish is not
        // reliable in the offscreen test harness, so assert structure).
        const column = supportButton.parent
        let listIndex = -1
        let buttonIndex = -1
        for (let i = 0; i < column.children.length; ++i) {
            if (column.children[i] === sponsorList)
                listIndex = i
            if (column.children[i] === supportButton)
                buttonIndex = i
        }
        verify(listIndex >= 0, "list in column")
        verify(buttonIndex > listIndex, "button after list")

        const popup = findChild(screen, "sponsorSupportPopup")
        verify(popup !== null, "popup")
        verify(!popup.visible, "popup closed")

        supportButton.clicked()
        tryCompare(popup, "visible", true)

        popup.close()
        screen.destroy()
    }

    function test_announcementOpensOnceAndPersistsOnClose() {
        popup.openIfNeeded()
        tryCompare(popup, "visible", true)

        popup.close()
        tryCompare(popup, "visible", false)
        tryCompare(mockPreferences, "acknowledgeCount", 1)
        compare(mockPreferences.seenAnnouncementId,
                SponsorCatalog.announcementId)

        popup.openIfNeeded()
        wait(50)
        verify(!popup.visible, "popup closed")
        compare(mockPreferences.acknowledgeCount, 1)
    }
}
