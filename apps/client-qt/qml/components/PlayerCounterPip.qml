// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic

Item {
    id: root

    property string counterKey: ""
    property string label: ""
    property int value: 0
    property bool editable: false
    property bool selected: false
    property bool horizontalLabel: false
    property color pipColor: Theme.primary
    readonly property string accessibleSummary:
        (label.length > 0 ? label : qsTr("Counter"))
        + " · " + value
    signal adjustRequested(int delta)
    signal selectedRequested()

    activeFocusOnTab: editable
    Accessible.role: Accessible.Button
    Accessible.name: accessibleSummary
    Accessible.description:
        selected
        ? qsTr("Selected. Plus increases and minus decreases.")
        : qsTr("Press Enter to select this counter.")

    implicitWidth: Theme.size(horizontalLabel ? 58 : 23)
    implicitHeight: Theme.size(horizontalLabel ? 23 : 38)

    Keys.onPressed: function(event) {
        if (!editable)
            return
        if (event.key === Qt.Key_Return
                || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space) {
            selectedRequested()
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Plus
                || event.key === Qt.Key_Equal
                || event.key === Qt.Key_Up) {
            if (!selected)
                selectedRequested()
            else
                adjustRequested(1)
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Minus
                || event.key === Qt.Key_Down) {
            if (!selected)
                selectedRequested()
            else
                adjustRequested(-1)
            event.accepted = true
        }
    }

    Rectangle {
        id: circle
        anchors.top: parent.top
        anchors.left: root.horizontalLabel ? parent.left : undefined
        anchors.horizontalCenter: root.horizontalLabel
                                  ? undefined : parent.horizontalCenter
        width: Math.min(Theme.size(23), parent.width, parent.height)
        height: width
        radius: width / 2
        color: root.pipColor
        border.width: root.selected ? Theme.size(2) : 1
        border.color: root.selected ? Theme.text : Theme.borderStrong

        Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            width: parent.width - Theme.size(4)
            text: String(root.value)
            color: Theme.primaryInk
            font.pixelSize: Theme.fontSize(10)
            font.weight: Font.Bold
            fontSizeMode: Text.Fit
            minimumPixelSize: Theme.fontSize(6)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -Theme.size(4)
            enabled: root.editable
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
                if (!root.selected) {
                    root.selectedRequested()
                    return
                }
                root.adjustRequested(mouse.button === Qt.RightButton ? -1 : 1)
            }
        }
    }

    Text {
        textFormat: Text.PlainText
        id: labelText
        objectName: "playerCounterLabel"
        anchors.left: root.horizontalLabel ? circle.right : parent.left
        anchors.leftMargin: root.horizontalLabel ? Theme.size(4) : 0
        anchors.top: root.horizontalLabel ? parent.top : circle.bottom
        anchors.topMargin: root.horizontalLabel ? 0 : Theme.size(2)
        anchors.bottom: root.horizontalLabel ? parent.bottom : undefined
        width: root.horizontalLabel
               ? parent.width - circle.width - Theme.size(4) : parent.width
        text: root.label.length > 0
              ? root.label
              : (root.selected ? qsTr("I rename · S set") : "")
        color: root.selected ? Theme.text : Theme.textSecondary
        font.pixelSize: Theme.fontSize(7)
        font.weight: root.selected ? Font.DemiBold : Font.Normal
        elide: Text.ElideRight
        horizontalAlignment: root.horizontalLabel
                             ? Text.AlignLeft : Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

        MouseArea {
            anchors.fill: parent
            enabled: root.editable
            cursorShape: Qt.IBeamCursor
            onClicked: root.selectedRequested()
        }
    }

    HoverHandler { id: hoverHandler }

    ToolTip.visible: hoverHandler.hovered
    ToolTip.delay: 450
    ToolTip.text: (root.label.length > 0 ? root.label : qsTr("Counter"))
                  + " · " + root.value + "\n"
                  + qsTr("Click to select · selected: left +1 · right -1 · I rename · S set")
}
