// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

AppPopup {
    id: root

    required property var wsModel

    objectName: "serverTransferOverlay"
    visible: wsModel.transferring === true
    closePolicy: Popup.NoAutoClose
    width: parent ? Math.min(Theme.size(420), parent.width - Theme.size(48)) : 0

    contentItem: RowLayout {
        objectName: "serverTransferProgress"
        spacing: Theme.size(16)

        ActivityRing { ringColor: Theme.accent }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Opening your room or event…")
            color: Theme.text
            font.pixelSize: Theme.fontSize(15)
            wrapMode: Text.WordWrap
        }
    }
}
