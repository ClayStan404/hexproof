// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root
    objectName: "gameplaySettingsScreen"
    property var settings: preferences
    background: AppBackground { }

    SettingsPage {
        anchors.fill: parent
        title: qsTr("Gameplay")
        subtitle: qsTr("Priority, phase stops, and direct connections")

        Surface {
            Layout.fillWidth: true
            implicitHeight: priorityContent.implicitHeight + Theme.size(48)
            elevated: true
            ColumnLayout {
                id: priorityContent
                anchors.fill: parent
                anchors.margins: Theme.size(24)
                spacing: Theme.size(12)
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: qsTr("Forge priority")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(20)
                    font.weight: Font.DemiBold
                }
                RulesPriorityMode {
                    Layout.fillWidth: true
                    settings: root.settings
                }
                RulesPhaseStops {
                    Layout.fillWidth: true
                    stops: root.settings.forgePhaseStops
                    onStopToggled: (step, ownTurn) => root.settings.toggleForgePhaseStop(step, ownTurn)
                }
            }
        }

        Surface {
            Layout.fillWidth: true
            implicitHeight: networkContent.implicitHeight + Theme.size(48)
            elevated: true
            ColumnLayout {
                id: networkContent
                anchors.fill: parent
                anchors.margins: Theme.size(24)
                spacing: Theme.size(12)
                AppToggle {
                    objectName: "settingsDirectPeer"
                    Layout.fillWidth: true
                    text: qsTr("Prefer direct connection (P2P)")
                    checked: root.settings.directPeerEnabled
                    onToggled: {
                        root.settings.directPeerEnabled = checked
                        checked = Qt.binding(function() { return root.settings.directPeerEnabled })
                    }
                }
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: qsTranslate("ForgePeerControls", "Direct connections share network addresses with the other player and use a STUN service. This preference is saved for future games.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(13)
                    wrapMode: Text.WordWrap
                }
            }
        }
        InfoBanner {
            Layout.fillWidth: true
            message: I18n.status(root.settings.lastError)
        }
    }
}
