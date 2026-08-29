// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    required property var wsModel
    required property int promptId
    required property int minimum
    required property int maximum

    implicitHeight: Theme.size(48)

    onPromptIdChanged: numberInput.value = Math.min(maximum, Math.max(minimum, 0))

    RowLayout {
        anchors.fill: parent
        spacing: Theme.size(10)

        Item { Layout.fillWidth: true }

        Text {
            textFormat: Text.PlainText
            text: qsTr("Choose from %1 to %2").arg(root.minimum).arg(root.maximum)
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(10)
        }

        SpinBox {
            id: numberInput

            Layout.preferredWidth: Theme.size(150)
            from: root.minimum
            to: root.maximum
            value: Math.min(root.maximum, Math.max(root.minimum, 0))
            editable: true
        }

        AppButton {
            compact: true
            variant: "primary"
            text: qsTr("Confirm number")
            onClicked: root.wsModel.respondRulesPromptWithNumber(root.promptId,
                                                                 numberInput.value)
        }
    }
}
