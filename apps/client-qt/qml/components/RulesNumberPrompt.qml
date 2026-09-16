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

    readonly property bool narrowLayout: width < Theme.size(490)

    implicitHeight: Math.max(Theme.size(48), numberLayout.implicitHeight)

    onPromptIdChanged: numberInput.value = Math.min(maximum, Math.max(minimum, 0))

    GridLayout {
        id: numberLayout
        anchors.fill: parent
        columns: root.narrowLayout ? 2 : 4
        columnSpacing: Theme.size(10)
        rowSpacing: Theme.size(8)

        Item { Layout.fillWidth: true; visible: !root.narrowLayout }

        Text {
            Layout.columnSpan: root.narrowLayout ? 2 : 1
            Layout.fillWidth: root.narrowLayout
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: qsTr("Choose from %1 to %2").arg(root.minimum).arg(root.maximum)
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(10)
        }

        SpinBox {
            id: numberInput

            Layout.fillWidth: root.narrowLayout
            Layout.preferredWidth: Theme.size(150)
            from: root.minimum
            to: root.maximum
            value: Math.min(root.maximum, Math.max(root.minimum, 0))
            editable: true
        }

        AppButton {
            objectName: "rulesConfirmNumber"
            Layout.minimumWidth: implicitWidth
            Layout.fillWidth: root.narrowLayout
            compact: true
            variant: "primary"
            text: qsTr("Confirm number")
            onClicked: root.wsModel.respondRulesPromptWithNumber(root.promptId,
                                                                 numberInput.value)
        }
    }
}
