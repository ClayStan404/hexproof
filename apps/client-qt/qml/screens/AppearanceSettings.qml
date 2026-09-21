// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root
    objectName: "appearanceSettingsScreen"
    background: AppBackground { }

    SettingsPage {
        anchors.fill: parent
        title: qsTr("Appearance")
        subtitle: qsTr("Theme, battlefield background, scale, and motion")

    Surface {
        Layout.fillWidth: true
        implicitHeight: appearanceContent.implicitHeight + Theme.size(48)
        elevated: true

        ColumnLayout {
            id: appearanceContent
            anchors.fill: parent
            anchors.margins: Theme.size(24)
            spacing: Theme.size(12)

            Text {
                textFormat: Text.PlainText
                text: qsTr("Appearance")
                color: Theme.text
                font.pixelSize: Theme.fontSize(20)
                font.weight: Font.DemiBold
            }
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTr("Choose Classic or Glass controls and panels. Battlefield backgrounds are selected separately.")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(12)
                wrapMode: Text.WordWrap
            }
            SegmentedControl {
                objectName: "settingsThemeSelector"
                Layout.fillWidth: true
                Layout.topMargin: Theme.size(6)
                options: [qsTr("Classic"), qsTr("Glass")]
                currentIndex: preferences.uiTheme === "glass" ? 1 : 0
                onActivated: index => preferences.uiTheme = index === 1 ? "glass" : "classic"
            }
        }
    }

    Surface {
        Layout.fillWidth: true
        implicitHeight: backgroundPicker.implicitHeight + Theme.size(48)
        elevated: true

        TableBackgroundPicker {
            id: backgroundPicker
            anchors.fill: parent
            anchors.margins: Theme.size(24)
            selectedId: preferences.tableBackground
            onBackgroundSelected: key => preferences.tableBackground = key
        }
    }

    Surface {
        Layout.fillWidth: true
        implicitHeight: scaleContent.implicitHeight + Theme.size(48)
        elevated: true

        ColumnLayout {
            id: scaleContent
            anchors.fill: parent
            anchors.margins: Theme.size(24)
            spacing: Theme.size(12)

            Text {
                textFormat: Text.PlainText
                text: qsTr("Interface scale")
                color: Theme.text
                font.pixelSize: Theme.fontSize(20)
                font.weight: Font.DemiBold
            }
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTr("Adjust text, controls, spacing, and dialogs together while preserving automatic window scaling.")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(12)
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.size(6)
                spacing: Theme.size(10)

                AppButton {
                    compact: true
                    variant: "ghost"
                    text: "−"
                    accessibleName: qsTr("Decrease interface scale")
                    Layout.preferredWidth: Theme.size(48)
                    enabled: preferences.interfaceScale > 0.75
                    onClicked: root.setInterfaceScale(preferences.interfaceScale - 0.05)
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.preferredWidth: Theme.size(90)
                    text: Math.round(preferences.interfaceScale * 100) + "%"
                    color: Theme.primary
                    font.pixelSize: Theme.fontSize(22)
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                }
                AppButton {
                    compact: true
                    variant: "ghost"
                    text: "+"
                    objectName: "settingsIncreaseScaleButton"
                    accessibleName: qsTr("Increase interface scale")
                    Layout.preferredWidth: Theme.size(48)
                    enabled: preferences.interfaceScale < 1.5
                    onClicked: root.setInterfaceScale(preferences.interfaceScale + 0.05)
                }
                Item { Layout.fillWidth: true }
                AppButton {
                    compact: true
                    objectName: "settingsResetScaleButton"
                    text: qsTr("Reset to 100%")
                    enabled: Math.abs(preferences.interfaceScale - 1.0) > 0.001
                    onClicked: root.setInterfaceScale(1.0)
                }
            }
            InfoBanner {
                Layout.fillWidth: true
                tone: "success"
                message: qsTr("The scale applies immediately to every theme-aware UI component.")
            }
        }
    }

    Surface {
        Layout.fillWidth: true
        implicitHeight: motionContent.implicitHeight + Theme.size(48)
        elevated: true

        ColumnLayout {
            id: motionContent
            anchors.fill: parent
            anchors.margins: Theme.size(24)
            spacing: Theme.size(10)

            Text {
                textFormat: Text.PlainText
                text: qsTr("Motion effects")
                color: Theme.text
                font.pixelSize: Theme.fontSize(20)
                font.weight: Font.DemiBold
            }
            AppToggle {
                Layout.fillWidth: true
                text: qsTr("Animate simulated pack openings")
                checked: preferences.animatePackOpenings
                onToggled: preferences.animatePackOpenings = checked
            }
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTr("Turn this off to show simulated pack contents immediately. Every opening animation can also be skipped while it is playing.")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(12)
                wrapMode: Text.WordWrap
            }
        }
    }

    }

    function setInterfaceScale(scale) {
        preferences.interfaceScale = Math.round(scale * 20) / 20
    }
}
