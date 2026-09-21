// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

AppPopup {
    id: root

    property string mode: "number"
    property string cardName: ""
    property var abilityCounters: []
    signal counterRequested(string counterId, string kind, string label,
                            int value)

    width: Math.min(Theme.size(420), parent.width - Theme.size(48))

    function showNewAbility(name) {
        mode = "newAbility"
        cardName = name
        abilityCounters = []
        labelField.clear()
        valueField.text = "1"
        open()
        labelField.forceActiveFocus()
    }

    function showNumber(name, value) {
        mode = "number"
        cardName = name
        abilityCounters = []
        valueField.text = String(value)
        open()
        valueField.forceActiveFocus()
        valueField.selectAll()
    }

    function showAbility(name, counters) {
        mode = "ability"
        cardName = name
        abilityCounters = counters
        abilityPicker.currentIndex = 0
        valueField.text = counters.length > 0
                          ? String(counters[0].value) : "0"
        open()
        valueField.forceActiveFocus()
        valueField.selectAll()
    }

    function submit() {
        if (!valueField.acceptableInput)
            return
        const value = valueField.numberValue()
        if (mode === "newAbility") {
            const label = labelField.text.trim()
            if (label.length === 0 || label.length > 24)
                return
            close()
            counterRequested("", "ability", label, value)
            return
        }
        if (mode === "ability") {
            if (abilityPicker.currentIndex < 0
                || abilityPicker.currentIndex >= abilityCounters.length)
                return
            const counter = abilityCounters[abilityPicker.currentIndex]
            close()
            counterRequested(counter.id, "ability", counter.label, value)
            return
        }
        close()
        counterRequested("number", "number", "", value)
    }

    function clearSelectedAbility() {
        if (mode !== "ability"
            || abilityPicker.currentIndex < 0
            || abilityPicker.currentIndex >= abilityCounters.length) {
            return
        }
        const counter = abilityCounters[abilityPicker.currentIndex]
        close()
        counterRequested(counter.id, "ability", counter.label, 0)
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(14)

        AppPopupHeader {
            titleText: root.cardName + " · " + (root.mode === "newAbility"
                       ? qsTr("Add ability counter")
                       : qsTr("Set counters"))
        }

        AppTextField {
            id: labelField
            Layout.fillWidth: true
            visible: root.mode === "newAbility"
            maximumLength: 24
            placeholderText: qsTr("Ability counter name")
            onAccepted: root.submit()
        }

        ComboBox {
            id: abilityPicker
            Layout.fillWidth: true
            visible: root.mode === "ability"
            model: root.abilityCounters
            textRole: "label"
            onActivated: function(index) {
                if (index >= 0 && index < root.abilityCounters.length)
                    valueField.text =
                        String(root.abilityCounters[index].value)
            }
        }

        AppTextField {
            id: valueField
            objectName: "cardCounterValueField"
            Layout.fillWidth: true
            placeholderText: qsTr("Counter value")
            inputMethodHints: Qt.ImhDigitsOnly
            validator: IntValidator {
                bottom: 0
                top: 2147483647
            }
            onAccepted: root.submit()
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Set to zero to remove this counter.")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(10)
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(10)

            Item { Layout.fillWidth: true }

            AppButton {
                objectName: "clearAbilityCounterButton"
                compact: true
                variant: "danger"
                visible: root.mode === "ability"
                text: qsTr("Clear counter")
                enabled: abilityPicker.currentIndex >= 0
                         && abilityPicker.currentIndex
                            < root.abilityCounters.length
                onClicked: root.clearSelectedAbility()
            }
            AppButton {
                compact: true
                variant: "ghost"
                text: qsTr("Cancel")
                onClicked: root.close()
            }
            AppButton {
                compact: true
                variant: "primary"
                text: qsTr("Apply")
                enabled: valueField.acceptableInput
                         && (root.mode !== "newAbility"
                             || labelField.text.trim().length > 0)
                onClicked: root.submit()
            }
        }
    }
}
