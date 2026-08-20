// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic

Button {
    id: control

    property string variant: "secondary"
    property string leadingText: ""
    property string accessibleName: ""
    property string disabledReason: ""
    property bool compact: false

    Accessible.role: Accessible.Button
    Accessible.name: accessibleName.length > 0
                     ? accessibleName
                     : (text.length > 0 ? text : leadingText)
    Accessible.description: !enabled ? disabledReason : ""
    ToolTip.text: disabledReason
    ToolTip.visible: !enabled && disabledReason.length > 0 && hovered
    ToolTip.delay: 350

    readonly property color foregroundColor: {
        if (!enabled)
            return Theme.textDisabled
        if (variant === "primary")
            return Theme.primaryInk
        if (variant === "danger")
            return Theme.error
        return Theme.text
    }

    readonly property color backgroundColor: {
        if (!enabled && variant === "highlight")
            return Theme.primaryMuted
        if (!enabled)
            return variant === "ghost" ? "transparent" : Theme.disabled
        if (variant === "primary")
            return down ? Theme.primaryStrong : (hovered ? "#91E9C4" : Theme.primary)
        if (variant === "highlight")
            return down ? "#214D3D"
                        : (hovered ? "#214A3B" : Theme.primaryMuted)
        if (variant === "danger")
            return down || hovered ? "#482528" : Theme.errorMuted
        if (variant === "ghost")
            return down || hovered ? Theme.surfaceHover : "transparent"
        return down || hovered ? Theme.surfaceHover : Theme.surfaceElevated
    }

    readonly property color outlineColor: {
        if (variant === "highlight")
            return enabled ? Theme.primary : Theme.borderStrong
        if (!enabled || variant === "primary" || variant === "ghost")
            return "transparent"
        if (variant === "danger")
            return "#653337"
        return hovered ? Theme.borderStrong : Theme.border
    }

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    implicitHeight: compact ? Theme.size(38) : Theme.controlHeight
    implicitWidth: Math.max(Theme.size(compact ? 88 : 112),
                            buttonContent.implicitWidth + Theme.size(compact ? 24 : 34))
    leftPadding: Theme.size(compact ? 12 : 17)
    rightPadding: leftPadding
    topPadding: 0
    bottomPadding: 0
    font.pixelSize: Theme.fontSize(compact ? 13 : 14)
    font.weight: Font.DemiBold
    scale: down ? 0.985 : 1.0

    Behavior on scale {
        NumberAnimation { duration: Theme.motionFast; easing.type: Easing.OutCubic }
    }

    contentItem: Row {
        id: buttonContent
        spacing: Theme.size(8)
        anchors.centerIn: parent

        Text {
            textFormat: Text.PlainText
            visible: control.leadingText.length > 0
            text: control.leadingText
            color: control.foregroundColor
            font.pixelSize: Theme.fontSize(control.compact ? 14 : 16)
            font.weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            textFormat: Text.PlainText
            visible: control.text.length > 0
            text: control.text
            color: control.foregroundColor
            font: control.font
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    background: Rectangle {
        color: control.backgroundColor
        radius: Theme.radiusMedium
        border.width: 1
        border.color: control.activeFocus ? Theme.primary : control.outlineColor

        Behavior on color { ColorAnimation { duration: Theme.motionFast } }
        Behavior on border.color { ColorAnimation { duration: Theme.motionFast } }
    }
}
