// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    objectName: "languageSettingsScreen"
    background: AppBackground { }

    SettingsPage {
        anchors.fill: parent
        title: qsTr("Language & cards")
        subtitle: qsTr("Menus, card names, and preferred art source")

    Surface {
        Layout.fillWidth: true
        implicitHeight: languageContent.implicitHeight + Theme.size(48)
        elevated: true

        ColumnLayout {
            id: languageContent
            anchors.fill: parent
            anchors.margins: Theme.size(24)
            spacing: Theme.size(12)

            Text {
                textFormat: Text.PlainText
                text: qsTr("Interface language")
                color: Theme.text
                font.pixelSize: Theme.fontSize(20)
                font.weight: Font.DemiBold
            }
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTr("Choose the language used by menus, buttons, and game screens.")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(12)
                wrapMode: Text.WordWrap
            }
            SegmentedControl {
                objectName: "settingsLanguageSelector"
                Layout.fillWidth: true
                Layout.topMargin: Theme.size(6)
                options: [qsTr("English"), qsTr("简体中文")]
                currentIndex: preferences.uiLanguage === "zh" ? 1 : 0
                onActivated: index => preferences.uiLanguage = index === 1 ? "zh" : "en"
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Theme.size(8)
                Layout.bottomMargin: Theme.size(8)
                implicitHeight: 1
                color: Theme.divider
            }

            Text {
                textFormat: Text.PlainText
                text: qsTr("Card language and art")
                color: Theme.text
                font.pixelSize: Theme.fontSize(20)
                font.weight: Font.DemiBold
            }
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTr("Choose card names, metadata, and preferred card art independently from the interface.")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(12)
                wrapMode: Text.WordWrap
            }
            SegmentedControl {
                objectName: "settingsCardLanguageSelector"
                Layout.fillWidth: true
                Layout.topMargin: Theme.size(6)
                options: [qsTr("English cards"), qsTr("Chinese cards")]
                currentIndex: preferences.cardLanguage === "zh" ? 1 : 0
                onActivated: index => preferences.cardLanguage = index === 1 ? "zh" : "en"
            }
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                Layout.topMargin: Theme.size(6)
                text: qsTr("Preferred card art source")
                color: Theme.text
                font.pixelSize: Theme.fontSize(13)
                font.weight: Font.DemiBold
            }
            SegmentedControl {
                objectName: "settingsCardArtProviderSelector"
                Layout.fillWidth: true
                options: [qsTr("Automatic (default)"), qsTr("Scryfall"), qsTr("MTGCH"), qsTr("Parallel")]
                currentIndex: preferences.cardArtProvider === "scryfall" ? 1
                              : preferences.cardArtProvider === "mtgch" ? 2
                              : preferences.cardArtProvider === "parallel" ? 3 : 0
                onActivated: index => preferences.cardArtProvider = index === 1
                                      ? "scryfall" : index === 2 ? "mtgch"
                                      : index === 3 ? "parallel" : "auto"
            }
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: preferences.cardArtProvider === "parallel"
                      ? qsTr("Use both sources to speed up large card downloads, such as EDH games.")
                      : qsTr("The preferred source is tried first for uncached art. Missing or unavailable images automatically fall back to the other source.")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(11)
                wrapMode: Text.WordWrap
            }
            AppToggle {
                Layout.fillWidth: true
                Layout.topMargin: Theme.size(4)
                text: qsTr("Prefer existing local art for the same card")
                checked: preferences.reuseLocalCardArt
                onToggled: preferences.reuseLocalCardArt = checked
            }
            InfoBanner {
                Layout.fillWidth: true
                message: I18n.status(preferences.lastError)
            }
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTr("When the requested printing is not cached, reuse a cached printing of the same card and language instead of downloading another image.")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(11)
                wrapMode: Text.WordWrap
            }
            InfoBanner {
                Layout.fillWidth: true
                tone: "warning"
                message: preferences.cardArtProvider === "parallel"
                         ? qsTr("Local art remains first. Scryfall and MTGCH download different cards in parallel, with Chinese art preferred for Chinese cards and automatic fallback.")
                         : preferences.cardArtProvider === "auto"
                         ? qsTr("Local art remains first. Automatic mode prefers MTGCH for Chinese cards and Scryfall for English cards, with automatic fallback.")
                         : preferences.cardArtProvider === "mtgch"
                         ? qsTr("Local art remains first. MTGCH is preferred for new downloads; Scryfall remains the automatic fallback.")
                         : qsTr("Local art remains first. Scryfall is preferred for new downloads; MTGCH remains the automatic fallback.")
            }
        }
    }
    }
}
