// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma Singleton

import QtQuick

QtObject {
    readonly property string announcementId: "founding-sponsors-2026-09"
    readonly property string afdianUrl: "https://afdian.com/a/hexproof"
    readonly property url wechatPayQrSource: Qt.resolvedUrl("../../assets/sponsors/wechat-pay.png")
    readonly property url alipayPayQrSource: Qt.resolvedUrl("../../assets/sponsors/alipay-pay.png")
    readonly property var sponsors: [
        {
            "name": "情报",
            "avatarSource": Qt.resolvedUrl("../../assets/sponsors/qingbao.jpg"),
            "profileUrl": "https://space.bilibili.com/7963465"
        },
        {
            "name": "豆豆(dodo)",
            "avatarSource": Qt.resolvedUrl("../../assets/sponsors/dodo.jpg"),
            "profileUrl": ""
        },
        {
            "name": "M0nta9e不太奇",
            "avatarSource": Qt.resolvedUrl("../../assets/sponsors/m0nta9e.jpg"),
            "profileUrl": ""
        }
    ]
}
