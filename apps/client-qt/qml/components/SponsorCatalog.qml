// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma Singleton

import QtQuick

QtObject {
    readonly property string afdianUrl: "https://afdian.com/a/hexproof"
    readonly property url wechatPayQrSource: Qt.resolvedUrl("../../assets/sponsors/wechat-pay.png")
    readonly property url alipayPayQrSource: Qt.resolvedUrl("../../assets/sponsors/alipay-pay.png")
    readonly property var tiers: [
        {"id": "omniscience", "name": qsTr("Omniscience")},
        {"id": "dockside", "name": qsTr("Dockside Extortionist")},
        {"id": "ragavan", "name": qsTr("Ragavan, Nimble Pilferer")}
    ]
    readonly property var sponsors: publicContent.sponsors

    function sponsorsForTier(tierId) {
        const result = []
        for (const sponsor of sponsors) {
            if (sponsor.tier === tierId)
                result.push(sponsor)
        }
        return result
    }
}
