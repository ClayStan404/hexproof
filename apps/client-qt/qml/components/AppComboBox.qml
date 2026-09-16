// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic

ComboBox {
    id: control

    property var textForIndex: null
    property var enabledForIndex: null

    implicitHeight: Theme.size(44)
    leftPadding: Theme.size(13)
    rightPadding: Theme.size(34)
    font.pixelSize: Theme.fontSize(13)
    font.weight: Font.Medium
    hoverEnabled: true
    displayText: typeof control.textForIndex === "function"
                 ? optionText(currentIndex) : currentText

    function optionText(index) {
        if (index < 0)
            return ""
        return typeof control.textForIndex === "function"
                ? control.textForIndex(index) : control.textAt(index)
    }

    contentItem: Text {
        textFormat: Text.PlainText
        leftPadding: 0
        rightPadding: control.indicator.width + control.spacing
        text: control.displayText
        color: control.enabled ? Theme.text : Theme.textDisabled
        font: control.font
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: Text {
        textFormat: Text.PlainText
        x: control.width - width - Theme.size(12)
        y: Math.round((control.height - height) / 2)
        text: "⌄"
        color: control.hovered || control.activeFocus ? Theme.primary : Theme.textMuted
        font.pixelSize: Theme.fontSize(15)
    }

    background: Item {
        implicitHeight: Theme.size(44)

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
            border.color: control.activeFocus ? Theme.primary
                          : (control.hovered ? Theme.borderStrong : Theme.border)
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

    delegate: ItemDelegate {
        id: delegateItem
        required property int index
        enabled: typeof control.enabledForIndex !== "function" || control.enabledForIndex(index)
        width: ListView.view ? ListView.view.width : control.width
        text: control.optionText(index)
        highlighted: control.highlightedIndex === index
        font: control.font

        contentItem: Text {
            textFormat: Text.PlainText
            text: delegateItem.text
            color: !delegateItem.enabled ? Theme.textDisabled : delegateItem.highlighted ? Theme.primary : Theme.text
            font: delegateItem.font
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        background: Rectangle {
            color: delegateItem.highlighted
                   ? (Theme.useGlass ? Theme.glassElevated : Theme.surfaceHover)
                   : (Theme.useGlass ? "transparent" : Theme.surfaceElevated)
            radius: Theme.useGlass ? Theme.radiusSmall : 0
        }
    }

    popup: Popup {
        y: control.height + Theme.size(4)
        width: control.width
        implicitHeight: Math.min(contentItem.implicitHeight + padding * 2, Theme.size(320))
        padding: Theme.size(5)

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.delegateModel
            currentIndex: control.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
            ScrollIndicator.vertical: ScrollIndicator { }
        }

        background: Item {
            implicitHeight: Theme.size(44)

            GlassChrome {
                anchors.fill: parent
                radius: Theme.useGlass ? Theme.radiusLarge : Theme.radiusMedium
                visible: Theme.useGlass
            }

            Rectangle {
                anchors.fill: parent
                visible: !Theme.useGlass
                color: Theme.surfaceElevated
                radius: Theme.radiusMedium
                border.width: 1
                border.color: Theme.borderStrong
            }
        }
    }
}
