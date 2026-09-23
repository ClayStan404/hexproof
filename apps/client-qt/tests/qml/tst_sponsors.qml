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

    Component {
        id: sponsorListComponent
        SponsorList { }
    }

    readonly property var expectedSponsors: [
        {name: "情报", tier: "ragavan", avatar: "qingbao.jpg",
         profileUrl: "https://space.bilibili.com/7963465"},
        {name: "豆豆(dodo)", tier: "dockside", avatar: "dodo.jpg", profileUrl: ""},
        {name: "M0nta9e不太奇", tier: "dockside", avatar: "m0nta9e.jpg", profileUrl: ""},
        {name: "Orangezihan", tier: "ragavan", avatar: "orangezihan.jpeg",
         profileUrl: "https://afdian.com/u/5eeb2b8c1ba811ed985d52540025c377"},
        {name: "寡妇门前是非多", tier: "ragavan", avatar: "guafu.jpeg",
         profileUrl: "https://afdian.com/u/76b1c06e60b911ecb38952540025c377"},
        {name: "贝蒂小熊-乱世不败", tier: "ragavan", avatar: "beidi.jpeg",
         profileUrl: "https://afdian.com/u/50a0ee26bef411efa2a35254001e7c00"},
        {name: "鹌姬酸", tier: "omniscience", avatar: "anjisuan.jpg",
         profileUrl: "https://space.bilibili.com/6167941"},
        {name: "爱发电用户_1a326", tier: "ragavan", avatar: "afdian-1a326.png",
         profileUrl: "https://afdian.com/u/1a32609cb19e11f1b6925254001e7c00"},
        {name: "a1100011", tier: "ragavan", avatar: "a1100011.jpg", profileUrl: ""}
    ]

    QtObject {
        id: mockContent
        property var pendingIds: ["qingbao"]
        property var seenIds: []
        property bool offered: false
        property int acknowledgeCount: 0
        function takeSponsorAnnouncement() {
            if (offered)
                return []
            offered = true
            return pendingIds.filter(id => seenIds.indexOf(id) < 0)
        }
        function acknowledgeSponsors(ids) {
            seenIds = seenIds.concat(Array.from(ids))
            ++acknowledgeCount
            return true
        }
    }

    property var popup: null

    Component {
        id: popupComponent
        SponsorAnnouncementPopup {
            contentModel: mockContent
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

    SignalSpy {
        id: profileSpy
        signalName: "profileRequested"
    }

    SignalSpy {
        id: viewSponsorsSpy
        signalName: "viewSponsorsRequested"
    }

    function init() {
        testWindow.width = 900
        testWindow.height = 620
        Theme.uiScale = 1
        mockContent.pendingIds = ["qingbao"]
        mockContent.seenIds = []
        mockContent.offered = false
        mockContent.acknowledgeCount = 0
        profileSpy.target = null
        profileSpy.clear()
        viewSponsorsSpy.target = null
        viewSponsorsSpy.clear()
        popup = popupComponent.createObject(testWindow.contentItem)
        verify(popup !== null, "popup")
    }

    function cleanup() {
        if (popup !== null)
            popup.destroy()
        popup = null
        Theme.uiScale = 1
    }

    function test_catalogContainsRequestedSponsors() {
        compare(SponsorCatalog.sponsors.length, expectedSponsors.length)
        for (let index = 0; index < expectedSponsors.length; ++index) {
            const actual = SponsorCatalog.sponsors[index]
            const expected = expectedSponsors[index]
            compare(actual.name, expected.name)
            compare(actual.tier, expected.tier)
            compare(actual.profileUrl, expected.profileUrl)
            verify(String(actual.avatarSource).endsWith("/assets/sponsors/" + expected.avatar))
        }
    }

    function test_catalogGroupsSponsorsWithoutDuplicates() {
        compare(SponsorCatalog.tiers.length, 3)
        const expectedTiers = [
            {id: "omniscience", name: "Omniscience"},
            {id: "dockside", name: "Dockside Extortionist"},
            {id: "ragavan", name: "Ragavan, Nimble Pilferer"}
        ]
        const allNames = []
        for (let index = 0; index < expectedTiers.length; ++index) {
            const tier = SponsorCatalog.tiers[index]
            compare(tier.id, expectedTiers[index].id)
            compare(tier.name, expectedTiers[index].name)
            const expectedNames = expectedSponsors.filter(sponsor => sponsor.tier === tier.id)
                                                 .map(sponsor => sponsor.name)
            const sponsors = SponsorCatalog.sponsorsForTier(tier.id)
            compare(sponsors.length, expectedNames.length)
            for (let sponsorIndex = 0; sponsorIndex < sponsors.length; ++sponsorIndex) {
                compare(sponsors[sponsorIndex].name, expectedNames[sponsorIndex])
                verify(allNames.indexOf(sponsors[sponsorIndex].name) < 0)
                allNames.push(sponsors[sponsorIndex].name)
            }
        }
        compare(allNames.length, 9)
        compare(SponsorCatalog.sponsorsForTier("unknown-tier").length, 0)
    }

    function namedItems(item, prefix) {
        const found = []
        if (String(item.objectName).startsWith(prefix))
            found.push(item)
        const children = item.children || []
        for (let index = 0; index < children.length; ++index)
            found.push(...namedItems(children[index], prefix))
        return found
    }

    function test_sponsorListLoadsAvatarsAndRoutesOnlyAvailableLinks() {
        const list = createTemporaryObject(sponsorListComponent, testWindow.contentItem,
                                           {width: 840})
        verify(list !== null)
        profileSpy.target = list
        waitForRendering(list)
        compare(namedItems(list, "sponsorCard_").length, 9)
        let previousBottom = -1
        for (const tier of SponsorCatalog.tiers) {
            const group = findChild(list, "sponsorTier_" + tier.id)
            verify(group !== null, tier.id)
            const heading = findChild(group, "sponsorTierHeading_" + tier.id)
            verify(heading !== null, tier.id + " heading")
            compare(heading.text, tier.name)
            const empty = findChild(group, "sponsorTierEmpty_" + tier.id)
            verify(empty !== null)
            compare(empty.visible, SponsorCatalog.sponsorsForTier(tier.id).length === 0)
            verify(group.y >= previousBottom - 1, "Tier groups must keep their catalog order")
            previousBottom = group.y + group.height
        }
        const highestTier = findChild(list, "sponsorTier_omniscience")
        verify(!findChild(highestTier, "sponsorTierEmpty_omniscience").visible)
        compare(namedItems(highestTier, "sponsorCard_").length, 1)
        let expectedProfileSignals = 0
        for (const expected of expectedSponsors) {
            const group = findChild(list, "sponsorTier_" + expected.tier)
            const card = findChild(group, "sponsorCard_" + expected.name)
            verify(card !== null, expected.name + " in " + expected.tier)
            const avatar = findChild(card, "sponsorAvatar_" + expected.name)
            verify(avatar !== null, expected.name + " avatar")
            tryCompare(avatar, "status", Image.Ready)
            const name = findChild(card, "sponsorName_" + expected.name)
            verify(name !== null, expected.name + " name")
            compare(name.text, expected.name)
            const button = findChild(card, "sponsorProfileButton")
            verify(button !== null)
            compare(button.visible, expected.profileUrl.length > 0)
            if (expected.profileUrl.length > 0) {
                button.clicked()
                ++expectedProfileSignals
                compare(profileSpy.count, expectedProfileSignals)
                compare(profileSpy.signalArguments[expectedProfileSignals - 1][0],
                        expected.profileUrl)
            }
        }
        compare(profileSpy.count, 6)
    }

    function test_sponsorNamesAndLinksStayInsideNarrowCards_data() {
        return [
            {tag: "normal", width: 340, scale: 1, compact: false},
            {tag: "maximum", width: 360, scale: 1.8, compact: false},
            {tag: "compact-maximum", width: 360, scale: 1.8, compact: true},
            {tag: "wide", width: 820, scale: 1.8, compact: false}
        ]
    }

    function test_sponsorNamesAndLinksStayInsideNarrowCards(data) {
        Theme.uiScale = data.scale
        const list = createTemporaryObject(sponsorListComponent, testWindow.contentItem,
                                           {width: data.width, compact: data.compact})
        verify(list !== null)
        verify(waitForPolish(testWindow))
        for (const expected of expectedSponsors) {
            const card = findChild(list, "sponsorCard_" + expected.name)
            verify(card !== null, expected.name)
            verify(card.width > 0 && card.width <= list.width + 1)
            const name = findChild(card, "sponsorName_" + expected.name)
            const button = findChild(card, "sponsorProfileButton")
            verify(name !== null)
            compare(name.text, expected.name)
            verify(!name.truncated, "Preserve the full sponsor name: " + expected.name)
            verify(name.contentHeight <= name.height + 1, expected.name + " text is not clipped")
            verify(name.width >= Theme.size(70), "Keep a readable name area: " + expected.name)
            const recognition = findChild(card, "sponsorRecognition_" + expected.name)
            const thanks = findChild(card, "sponsorThanks_" + expected.name)
            for (const item of [name, button, recognition, thanks]) {
                if (!item.visible)
                    continue
                const point = item.mapToItem(card, 0, 0)
                verify(point.x >= -1 && point.y >= -1, expected.name + " starts inside card")
                verify(point.x + item.width <= card.width + 1,
                       expected.name + " " + item.objectName + " fits card width: "
                       + (point.x + item.width) + " <= " + card.width)
                verify(point.y + item.height <= card.height + 1,
                       expected.name + " fits card height")
                if (item === recognition || item === thanks)
                    verify(item.contentHeight <= item.height + 1, "Recognition text must not be clipped")
            }
            if (button.visible) {
                const namePoint = name.mapToItem(card, 0, 0)
                const buttonPoint = button.mapToItem(card, 0, 0)
                verify(namePoint.x + name.width <= buttonPoint.x + 1
                       || buttonPoint.x + button.width <= namePoint.x + 1
                       || namePoint.y + name.height <= buttonPoint.y + 1
                       || buttonPoint.y + button.height <= namePoint.y + 1,
                       expected.name + " must not overlap its profile button")
            }
        }
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

    function test_supportActionsRemainInsideSmallWindow_data() {
        return [{tag: "large", scale: 1.5}, {tag: "maximum", scale: 1.8}]
    }
    function test_supportActionsRemainInsideSmallWindow(data) {
        Theme.uiScale = data.scale
        const support = createTemporaryObject(supportPopupComponent, testWindow.contentItem)
        support.open()
        tryVerify(() => support.opened)
        waitForRendering(support.contentItem)
        for (const name of ["wechatPayQr", "alipayPayQr"]) {
            const qr = findChild(support, name)
            verify(qr.width >= 150, "QR code must retain a scannable size")
            const scroll = findChild(support, "sponsorSupportScroll")
            const visiblePoint = qr.mapToItem(scroll, 0, 0)
            verify(visiblePoint.y >= 0)
            verify(visiblePoint.y + qr.height <= scroll.height + 1,
                   "The complete QR code must be visible without scrolling")
            const qrPoint = qr.mapToItem(support.contentItem, 0, 0)
            verify(qrPoint.x >= 0 && qrPoint.x + qr.width <= support.contentItem.width + 1)
        }
        const close = findChild(support, "closeSponsorSupportButton")
        const point = close.mapToItem(testWindow.contentItem, 0, 0)
        verify(point.y >= 0)
        verify(point.y + close.height <= testWindow.height)
        mouseClick(close)
        tryVerify(() => !support.visible)
    }

    function test_sponsorsScreenOpensSupportPopupFromListBottom_data() {
        return [{tag: "normal", scale: 1}, {tag: "maximum", scale: 1.8}]
    }

    function test_sponsorsScreenOpensSupportPopupFromListBottom(data) {
        Theme.uiScale = data.scale
        const screen = createTemporaryObject(sponsorsScreenComponent, testWindow.contentItem,
                                              {width: testWindow.width, height: testWindow.height})
        verify(screen !== null)
        waitForRendering(screen)

        const supportButton = findChild(screen, "supportButton")
        verify(supportButton !== null, "supportButton")
        verify(supportButton.visible, "supportButton.visible")
        const sponsorList = findChild(screen, "sponsorList")
        verify(sponsorList !== null, "sponsorList")
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

        const scroll = findChild(screen, "sponsorsScreenScroll")
        verify(scroll !== null)
        const flickable = scroll.contentItem
        verify(flickable.contentHeight > flickable.height)
        mouseWheel(scroll, scroll.width / 2, scroll.height / 2, 0, -120)
        tryVerify(() => flickable.contentY > 0)
        flickable.contentY = flickable.contentHeight - flickable.height
        waitForRendering(screen)
        const buttonPoint = supportButton.mapToItem(screen, 0, 0)
        verify(buttonPoint.x >= 0 && buttonPoint.y >= 0)
        verify(buttonPoint.x + supportButton.width <= screen.width + 1)
        verify(buttonPoint.y + supportButton.height <= screen.height + 1,
               "Support action must be reachable below every sponsor group")

        const popup = findChild(screen, "sponsorSupportPopup")
        verify(popup !== null, "popup")
        verify(!popup.visible, "popup closed")

        mouseClick(supportButton)
        tryCompare(popup, "visible", true)

        popup.close()
    }

    function test_announcementOpensOnceAndPersistsOnClose() {
        popup.openIfNeeded()
        tryCompare(popup, "visible", true)

        popup.close()
        tryCompare(popup, "visible", false)
        tryCompare(mockContent, "acknowledgeCount", 1)
        compare(mockContent.seenIds, ["qingbao"])

        popup.openIfNeeded()
        wait(50)
        verify(!popup.visible, "popup closed")
        compare(mockContent.acknowledgeCount, 1)

        // Recreating the component must respect the acknowledged sponsor IDs,
        // not just an in-memory flag on the popup that was already dismissed.
        const reopened = createTemporaryObject(popupComponent, testWindow.contentItem)
        reopened.openIfNeeded()
        wait(50)
        verify(!reopened.visible)
        compare(mockContent.acknowledgeCount, 1)
    }

    function test_knownSponsorsDoNotRepeat() {
        mockContent.seenIds = ["qingbao"]
        popup.openIfNeeded()
        wait(50)
        verify(!popup.visible)
        compare(mockContent.acknowledgeCount, 0)
    }

    function test_newSponsorsAppearOnNextStartup() {
        popup.openIfNeeded()
        tryVerify(() => popup.opened)
        // An update received while the popup is open must not be acknowledged unseen.
        mockContent.pendingIds = ["qingbao", "dodo"]
        popup.close()
        tryVerify(() => !popup.visible)
        compare(mockContent.seenIds, ["qingbao"])
        popup.openIfNeeded()
        verify(!popup.visible)

        mockContent.offered = false
        const restarted = createTemporaryObject(popupComponent, testWindow.contentItem)
        restarted.openIfNeeded()
        tryVerify(() => restarted.opened)
        compare(Array.from(restarted.displayedSponsorIds), ["dodo"])
        restarted.close()
        tryVerify(() => !restarted.visible)
        compare(mockContent.acknowledgeCount, 2)
    }

    function test_openingFullListAcknowledgesOnlyOnce() {
        viewSponsorsSpy.target = popup
        popup.openIfNeeded()
        tryVerify(() => popup.opened)
        const view = findChild(popup, "viewSponsorsButton")
        verify(view !== null)
        mouseClick(view)
        tryVerify(() => !popup.visible)
        compare(viewSponsorsSpy.count, 1)
        compare(mockContent.acknowledgeCount, 1)
        compare(mockContent.seenIds, ["qingbao"])
    }

    function test_announcementScrollAndCloseRemainAccessible_data() {
        return [{tag: "normal", scale: 1}, {tag: "maximum", scale: 1.8}]
    }

    function test_announcementScrollAndCloseRemainAccessible(data) {
        Theme.uiScale = data.scale
        popup.openIfNeeded()
        tryVerify(() => popup.opened)
        waitForRendering(popup.contentItem)
        const scroller = findChild(popup, "sponsorAnnouncementScroll")
        verify(scroller !== null)
        verify(scroller.height > 0)
        verify(scroller.contentHeight > scroller.height, "All three groups require scrolling")
        mouseWheel(scroller, scroller.width / 2, scroller.height / 2, 0, -120)
        tryVerify(() => scroller.contentY > 0, 5000,
                  "Wheel input must scroll the sponsor groups")
        scroller.contentY = scroller.contentHeight - scroller.height
        waitForRendering(popup.contentItem)
        const finalTier = findChild(scroller, "sponsorTier_ragavan")
        verify(finalTier.width <= scroller.width - Theme.size(12),
               "Tier counts and profile actions must leave a scrollbar gutter")
        const point = finalTier.mapToItem(scroller, 0, finalTier.height)
        verify(point.y > 0 && point.y <= scroller.height + 1,
               "The last tier must be reachable by scrolling")
        for (const name of ["viewSponsorsButton", "dismissSponsorsButton"]) {
            const button = findChild(popup, name)
            verify(button !== null)
            const buttonPoint = button.mapToItem(testWindow.contentItem, 0, 0)
            verify(buttonPoint.x >= 0 && buttonPoint.y >= 0)
            verify(buttonPoint.x + button.width <= testWindow.width + 1)
            verify(buttonPoint.y + button.height <= testWindow.height + 1,
                   "Announcement actions must not be clipped at maximum UI scale")
        }
        const dismiss = findChild(popup, "dismissSponsorsButton")
        mouseClick(dismiss)
        tryVerify(() => !popup.visible)
        compare(mockContent.acknowledgeCount, 1)
    }
}
