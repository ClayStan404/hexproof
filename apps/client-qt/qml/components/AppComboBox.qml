// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic

ComboBox {
    id: control

    implicitHeight: Theme.size(44)
    leftPadding: Theme.size(13)
    rightPadding: Theme.size(34)
    font.pixelSize: Theme.fontSize(13)
    font.weight: Font.Medium
    hoverEnabled: true

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

    background: Rectangle {
        color: control.enabled ? Theme.surfaceMuted : Theme.disabled
        radius: Theme.radiusMedium
        border.width: 1
        border.color: control.activeFocus ? Theme.primary
                      : (control.hovered ? Theme.borderStrong : Theme.border)
    }

    delegate: ItemDelegate {
        id: delegateItem
        required property int index
        width: ListView.view ? ListView.view.width : control.width
        text: control.textAt(index)
        highlighted: control.highlightedIndex === index
        font: control.font

        contentItem: Text {
            textFormat: Text.PlainText
            text: delegateItem.text
            color: delegateItem.highlighted ? Theme.primary : Theme.text
            font: delegateItem.font
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        background: Rectangle {
            color: delegateItem.highlighted ? Theme.surfaceHover : Theme.surfaceElevated
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

        background: Rectangle {
            color: Theme.surfaceElevated
            radius: Theme.radiusMedium
            border.width: 1
            border.color: Theme.borderStrong
        }
    }
}
