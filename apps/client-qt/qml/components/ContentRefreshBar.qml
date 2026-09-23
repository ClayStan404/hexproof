// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root
    property var contentModel: publicContent
    spacing: Theme.size(12)

    Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: root.contentModel.refreshing ? qsTr("Checking for updates…")
              : root.contentModel.refreshFailed ? qsTr("Saved content · Refresh unavailable")
              : qsTr("Available offline")
        color: Theme.textMuted
        font.pixelSize: Theme.fontSize(12)
        wrapMode: Text.WordWrap
    }

    AppButton {
        objectName: "refreshPublicContentButton"
        text: qsTr("Refresh")
        compact: true
        enabled: !root.contentModel.refreshing
        onClicked: root.contentModel.refresh(true)
    }
}
