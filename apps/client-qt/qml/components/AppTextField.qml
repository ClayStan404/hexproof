// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic

TextField {
    id: control

    property int maximumUtf8Bytes: 0
    readonly property int utf8ByteLength: encodedUtf8Length(text)
    readonly property bool withinUtf8ByteLimit:
        maximumUtf8Bytes <= 0 || utf8ByteLength <= maximumUtf8Bytes

    function numberValue() {
        const integerValidator = validator as IntValidator
        if (!integerValidator)
            return NaN
        // Use the validator's locale, including its digits and group separator.
        try {
            return Number.fromLocaleString(Qt.locale(integerValidator.locale), text)
        } catch (error) {
            return NaN
        }
    }

    function encodedUtf8Length(value) {
        let bytes = 0
        for (let index = 0; index < value.length; ++index) {
            const code = value.charCodeAt(index)
            if (code <= 0x7f) {
                ++bytes
            } else if (code <= 0x7ff) {
                bytes += 2
            } else if (code >= 0xd800 && code <= 0xdbff
                       && index + 1 < value.length) {
                const nextCode = value.charCodeAt(index + 1)
                if (nextCode >= 0xdc00 && nextCode <= 0xdfff) {
                    bytes += 4
                    ++index
                } else {
                    bytes += 3
                }
            } else {
                bytes += 3
            }
        }
        return bytes
    }

    hoverEnabled: true
    selectByMouse: true
    focusPolicy: Qt.StrongFocus
    implicitHeight: Theme.size(52)
    leftPadding: Theme.size(15)
    rightPadding: Theme.size(15)
    color: Theme.text
    placeholderTextColor: Theme.textMuted
    selectionColor: Theme.primaryMuted
    selectedTextColor: Theme.text
    font.pixelSize: Theme.fontSize(14)
    passwordCharacter: "•"

    background: Item {
        implicitHeight: Theme.size(52)

        LiquidGlass {
            anchors.fill: parent
            radius: Theme.radiusMedium
            compact: true
            elevated: control.activeFocus || control.hovered
            visible: Theme.useGlass && control.enabled
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusMedium
            antialiasing: true
            visible: !Theme.useGlass || !control.enabled
            color: control.enabled ? Theme.surfaceMuted : Theme.disabled
            border.width: 1
            border.color: control.activeFocus
                          ? Theme.primary
                          : (control.hovered ? Theme.borderStrong : Theme.border)

            Behavior on border.color { ColorAnimation { duration: Theme.motionFast } }
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusMedium
            antialiasing: true
            visible: Theme.useGlass && control.enabled
            color: Theme.withAlpha("#FFFFFF",
                                   control.activeFocus || control.hovered
                                   ? 0.12 : 0.08)
            border.width: 1
            border.color: control.activeFocus ? Theme.primary
                          : Theme.glassBorder
        }
    }
}
