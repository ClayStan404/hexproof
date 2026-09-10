// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma Singleton

import QtQuick

QtObject {
    readonly property string announcementId: "founding-sponsors-2026-09"
    readonly property string afdianUrl: "https://afdian.com/a/hexproof"
    readonly property url wechatPayQrSource: Qt.resolvedUrl("../../assets/sponsors/wechat-pay.png")
    readonly property url alipayPayQrSource: Qt.resolvedUrl("../../assets/sponsors/alipay-pay.png")
    readonly property var tiers: [
        {"id": "omniscience", "name": qsTr("Omniscience")},
        {"id": "dockside", "name": qsTr("Dockside Extortionist")},
        {"id": "ragavan", "name": qsTr("Ragavan, Nimble Pilferer")}
    ]
    readonly property var sponsors: [
        {
            "name": "情报",
            "tier": "ragavan",
            "avatarSource": Qt.resolvedUrl("../../assets/sponsors/qingbao.jpg"),
            "profileUrl": "https://space.bilibili.com/7963465"
        },
        {
            "name": "豆豆(dodo)",
            "tier": "dockside",
            "avatarSource": Qt.resolvedUrl("../../assets/sponsors/dodo.jpg"),
            "profileUrl": ""
        },
        {
            "name": "M0nta9e不太奇",
            "tier": "dockside",
            "avatarSource": Qt.resolvedUrl("../../assets/sponsors/m0nta9e.jpg"),
            "profileUrl": ""
        },
        {
            "name": "Orangezihan",
            "tier": "ragavan",
            "avatarSource": Qt.resolvedUrl("../../assets/sponsors/orangezihan.jpeg"),
            "profileUrl": "https://afdian.com/u/5eeb2b8c1ba811ed985d52540025c377"
        },
        {
            "name": "寡妇门前是非多",
            "tier": "ragavan",
            "avatarSource": Qt.resolvedUrl("../../assets/sponsors/guafu.jpeg"),
            "profileUrl": "https://afdian.com/u/76b1c06e60b911ecb38952540025c377"
        },
        {
            "name": "贝蒂小熊-乱世不败",
            "tier": "ragavan",
            "avatarSource": Qt.resolvedUrl("../../assets/sponsors/beidi.jpeg"),
            "profileUrl": "https://afdian.com/u/50a0ee26bef411efa2a35254001e7c00"
        }
    ]

    function sponsorsForTier(tierId) {
        return sponsors.filter(sponsor => sponsor.tier === tierId)
    }
}
