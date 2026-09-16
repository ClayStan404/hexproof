// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: root

    property string selectedId: "default"
    signal backgroundSelected(string key)

    spacing: Theme.size(12)

    Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: qsTr("Battlefield background")
        color: Theme.text
        font.pixelSize: Theme.fontSize(20)
        font.weight: Font.DemiBold
        wrapMode: Text.WordWrap
    }

    Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: qsTr("Use the default background without an image, or choose artwork independently of the interface theme. Changes apply immediately and are saved on this device.")
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSize(12)
        wrapMode: Text.WordWrap
    }

    GridLayout {
        Layout.fillWidth: true
        columns: width >= Theme.size(540) ? 3 : 2
        columnSpacing: Theme.size(10)
        rowSpacing: Theme.size(10)

        Repeater {
            model: TableBackgrounds.entries

            AbstractButton {
                id: choice
                required property var modelData
                readonly property bool selected: TableBackgrounds.entry(root.selectedId).key === modelData.key

                objectName: "tableBackgroundChoice-" + modelData.key
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitWidth: Theme.size(150)
                implicitHeight: contentItem.implicitHeight + topPadding + bottomPadding
                padding: Theme.size(6)
                text: modelData.name
                Accessible.role: Accessible.RadioButton
                Accessible.checkable: true
                Accessible.checked: selected
                hoverEnabled: true
                onClicked: root.backgroundSelected(modelData.key)

                background: Rectangle {
                    color: choice.selected ? Theme.primaryMuted
                                          : choice.hovered ? Theme.surfaceHover : Theme.surfaceMuted
                    radius: Theme.radiusSmall
                    border.width: choice.selected || choice.activeFocus ? Theme.size(2) : 1
                    border.color: choice.selected || choice.activeFocus ? Theme.primary : Theme.border
                }

                contentItem: Column {
                    spacing: Theme.size(7)

                    Item {
                        width: parent.width
                        height: Math.round(width * 2 / 3)

                        Rectangle {
                            anchors.fill: parent
                            visible: choice.modelData.key === "default"
                            color: Theme.surfaceMuted

                            Rectangle {
                                x: parent.width * 0.06
                                y: parent.height * 0.07
                                width: parent.width * 0.88
                                height: parent.height * 0.41
                                color: Theme.surfaceHover
                                border.color: Theme.border
                            }

                            Rectangle {
                                x: parent.width * 0.06
                                y: parent.height * 0.52
                                width: parent.width * 0.88
                                height: parent.height * 0.41
                                color: Theme.primaryMuted
                                border.color: Theme.border
                            }
                        }

                        Image {
                            objectName: "tableBackgroundThumbnail-" + choice.modelData.key
                            anchors.fill: parent
                            visible: choice.modelData.key !== "default"
                            source: choice.modelData.source
                            sourceSize: Qt.size(384, 256)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }

                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: choice.text
                        color: choice.selected ? Theme.primary : Theme.text
                        font.pixelSize: Theme.fontSize(12)
                        font.weight: choice.selected ? Font.DemiBold : Font.Normal
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
