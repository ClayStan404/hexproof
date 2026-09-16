// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var tableController
    readonly property var actions: tableController.interaction.zoneActions
    property real listHeight: Theme.size(52)
    spacing: Theme.size(6)
    Timer {
        id: measure
        interval: 0
        onTriggered: root.listHeight = root.actions.length > 0
            ? Math.max(Theme.size(52), Math.min(list.contentHeight, Theme.size(172))) : 0
    }

    Text {
        id: heading
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: qsTr("Available in other zones · %1").arg(root.actions.length)
        color: Theme.primary
        font.pixelSize: Theme.fontSize(11)
        wrapMode: Text.Wrap
    }
    ListView {
        id: list
        objectName: "rulesZoneActions"
        Layout.fillWidth: true
        Layout.preferredHeight: root.listHeight
        Layout.maximumHeight: root.listHeight
        Layout.minimumHeight: 0
        model: root.actions
        onCountChanged: measure.restart()
        onContentHeightChanged: measure.restart()
        onWidthChanged: measure.restart()
        spacing: Theme.size(5)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: AppButton {
            id: action
            required property var modelData
            required property int index
            objectName: "rulesZoneAction-" + modelData.responseId
            width: list.width - Theme.size(14)
            implicitHeight: Math.max(Theme.size(52), label.implicitHeight + Theme.size(16))
            variant: "highlight"
            enabled: root.tableController.interaction.canRespond
            text: (modelData.zoneOwnerSeat === root.tableController.localSeat
                ? root.tableController.zoneLabel(modelData.zone)
                : qsTr("Opponent's %1").arg(root.tableController.zoneLabel(modelData.zone))) + " · "
                + root.tableController.promptOptionLabel("chooseAction", modelData.responseId, modelData.label)
            contentItem: Text {
                id: label
                textFormat: Text.PlainText
                text: action.text
                color: action.foregroundColor
                font.pixelSize: Theme.fontSize(11)
                wrapMode: Text.Wrap
                verticalAlignment: Text.AlignVCenter
            }
            onActiveFocusChanged: if (activeFocus) list.positionViewAtIndex(index, ListView.Contain)
            onClicked: root.tableController.interaction.submitCardAction(modelData.cardId, modelData.responseId)
        }
    }
}
