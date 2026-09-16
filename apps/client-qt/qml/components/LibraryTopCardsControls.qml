// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "LibrarySearchPopup"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var popupController
    spacing: Theme.size(8)

    function resetControls() {
        selectedDestination.currentIndex = 0
        selectedFaceDown.checked = false
    }

    RowLayout {
        Layout.fillWidth: true
        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Selected") + " · " + root.popupController.selectedCount
            color: Theme.text
            font.pixelSize: Theme.fontSize(12)
            font.weight: Font.DemiBold
        }
        AppButton {
            objectName: "useTopRemainder"
            implicitWidth: Theme.size(30)
            implicitHeight: Theme.size(28)
            compact: true
            variant: "ghost"
            text: "↶"
            accessibleName: qsTr("Use remainder destination")
            ToolTip.visible: hovered
            ToolTip.text: accessibleName
            enabled: root.popupController.selectedCount > 0
            onClicked: root.popupController.useRemainderForTopCards(
                           root.popupController.selectedCardIdList())
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.size(6)
        AppComboBox {
            id: selectedDestination
            objectName: "topSelectedDestination"
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            model: root.popupController.topCardDestinations
            textRole: "label"
            valueRole: "value"
            ToolTip.visible: hovered
            ToolTip.text: displayText
            onActivated: selectedFaceDown.checked = false
        }
        AppButton {
            objectName: "assignSelectedTopCards"
            implicitWidth: Theme.size(68)
            compact: true
            text: qsTr("Assign")
            accessibleName: qsTr("Assign selected cards")
            enabled: root.popupController.selectedCount > 0
            onClicked: root.popupController.assignTopCards(
                           root.popupController.selectedCardIdList(),
                           selectedDestination.currentValue, selectedFaceDown.checked)
        }
    }
    AppToggle {
        id: selectedFaceDown
        objectName: "topSelectedFaceDown"
        Layout.fillWidth: true
        visible: selectedDestination.currentValue === "battlefield"
        text: qsTr("Face down")
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Theme.divider
    }
    Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: qsTr("Remainder") + " · " + root.popupController.topRemainderCount
        color: Theme.text
        font.pixelSize: Theme.fontSize(12)
        font.weight: Font.DemiBold
    }
    AppComboBox {
        objectName: "topRemainderDestination"
        Layout.fillWidth: true
        model: root.popupController.topCardDestinations
        textRole: "label"
        valueRole: "value"
        currentIndex: root.popupController.topCardDestinations.findIndex(
                          option => option.value === root.popupController.topRemainderDestination)
        ToolTip.visible: hovered
        ToolTip.text: displayText
        onActivated: function(index) {
            root.popupController.setTopRemainderDestination(
                        root.popupController.topCardDestinations[index].value)
        }
    }
    AppToggle {
        objectName: "topRemainderFaceDown"
        Layout.fillWidth: true
        visible: root.popupController.topRemainderDestination === "battlefield"
        checked: root.popupController.topRemainderFaceDown
        text: qsTr("Face down")
        onToggled: root.popupController.topRemainderFaceDown = checked
    }
    Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: qsTr("Only cards without an individual assignment follow this destination.")
        color: Theme.textMuted
        font.pixelSize: Theme.fontSize(10)
        wrapMode: Text.WordWrap
    }
}
