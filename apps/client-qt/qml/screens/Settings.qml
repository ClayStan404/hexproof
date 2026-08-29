// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import "../components"

Page {
    id: root

    readonly property var appWindow: ApplicationWindow.window

    property string pendingPackage: ""

    background: AppBackground { }

    ScreenHeader {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(22)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        title: qsTr("Settings")
        subtitle: qsTr("Language, updates, and local card data")
        onBackRequested: root.appWindow.popScreen()
    }

    ScrollView {
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(14)
        anchors.bottomMargin: Theme.size(28)
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            width: Math.min(Theme.size(760), parent.width - Theme.size(72))
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.size(16)

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
                        Layout.fillWidth: true
                        options: [qsTr("Scryfall (default)"), qsTr("MTGCH")]
                        currentIndex: preferences.cardArtProvider === "mtgch" ? 1 : 0
                        onActivated: index => preferences.cardArtProvider = index === 1
                                              ? "mtgch" : "scryfall"
                    }
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: qsTr("The preferred source is tried first for uncached art. Missing or unavailable images automatically fall back to the other source.")
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
                        message: preferences.cardArtProvider === "mtgch"
                                 ? qsTr("Local art remains first. MTGCH is preferred for new downloads; Scryfall remains the automatic fallback.")
                                 : qsTr("Local art remains first. Scryfall is preferred for new downloads; MTGCH remains the automatic fallback.")
                    }
                }
            }

            ApplicationUpdatePanel {
                Layout.fillWidth: true
                updater: appUpdater
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
                            onClicked: root.setInterfaceScale(
                                preferences.interfaceScale - 0.05)
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
                            accessibleName: qsTr("Increase interface scale")
                            Layout.preferredWidth: Theme.size(48)
                            enabled: preferences.interfaceScale < 1.5
                            onClicked: root.setInterfaceScale(
                                preferences.interfaceScale + 0.05)
                        }

                        Item { Layout.fillWidth: true }

                        AppButton {
                            compact: true
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

            Surface {
                Layout.fillWidth: true
                implicitHeight: shortcutContent.implicitHeight + Theme.size(48)
                elevated: true

                RowLayout {
                    id: shortcutContent
                    anchors.fill: parent
                    anchors.margins: Theme.size(24)
                    spacing: Theme.size(18)

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.size(4)
                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("Keyboard shortcuts")
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(20)
                            font.weight: Font.DemiBold
                        }
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: qsTr("Reassign, disable, or restore application, table, and replay actions.")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSize(12)
                            wrapMode: Text.WordWrap
                        }
                    }
                    AppButton {
                        text: qsTr("Customize…")
                        onClicked: root.appWindow.pushScreen(
                                       "screens/ShortcutSettings.qml")
                    }
                }
            }

            Surface {
                Layout.fillWidth: true
                implicitHeight: catalogContent.implicitHeight + Theme.size(48)
                elevated: true

                ColumnLayout {
                    id: catalogContent
                    anchors.fill: parent
                    anchors.margins: Theme.size(24)
                    spacing: Theme.size(12)

                    RowLayout {
                        Layout.fillWidth: true
                        ColumnLayout {
                            spacing: Theme.size(3)
                            Text {
                                textFormat: Text.PlainText
                                text: qsTr("Searchable card database")
                                color: Theme.text
                                font.pixelSize: Theme.fontSize(20)
                                font.weight: Font.DemiBold
                            }
                            Text {
                                textFormat: Text.PlainText
                                text: cardCatalog.installed
                                      ? qsTr("%1 installed locally")
                                        .arg(root.packageLabel(
                                                 cardCatalog.packageName))
                                      : qsTr("No full metadata package installed")
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSize(12)
                            }
                        }
                        Item { Layout.fillWidth: true }
                        StatusPill {
                            text: root.catalogStatusText()
                            statusColor: root.catalogStatusColor()
                        }
                    }

                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.divider }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: Theme.size(20)
                        rowSpacing: Theme.size(6)

                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("Installed version")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(11)
                        }
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: cardCatalog.installed
                                  ? qsTr("%1 · schema %2")
                                    .arg(root.catalogVersionDate(
                                             cardCatalog.installedCatalogVersion))
                                    .arg(cardCatalog.installedCatalogSchemaVersion)
                                  : qsTr("Not installed")
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(11)
                            font.weight: Font.DemiBold
                        }

                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("Latest version")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(11)
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.size(8)
                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: cardCatalog.checkingCatalogVersion
                                      ? qsTr("Checking…")
                                      : (cardCatalog.latestCatalogKnown
                                         ? qsTr("%1 · schema %2")
                                           .arg(root.catalogVersionDate(
                                                    cardCatalog.latestCatalogVersion))
                                           .arg(cardCatalog.latestCatalogSchemaVersion)
                                         : qsTr("Unavailable"))
                                color: cardCatalog.latestCatalogKnown
                                       ? Theme.text : Theme.textMuted
                                font.pixelSize: Theme.fontSize(11)
                                font.weight: Font.DemiBold
                            }
                            AppButton {
                                compact: true
                                variant: "ghost"
                                text: qsTr("Check updates")
                                enabled: !cardCatalog.checkingCatalogVersion
                                         && !cardCatalog.busy
                                onClicked: cardCatalog.checkCatalogUpdate()
                            }
                        }
                    }

                    InfoBanner {
                        Layout.fillWidth: true
                        visible: cardCatalog.catalogVersionError.length > 0
                        tone: "warning"
                        message: I18n.status(cardCatalog.catalogVersionError)
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: qsTr("The database enables full offline search in the deck editor. Images are still downloaded only when a card is used.")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(12)
                        lineHeight: 1.35
                        wrapMode: Text.WordWrap
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.size(6)
                        spacing: Theme.size(12)

                        Surface {
                            Layout.fillWidth: true
                            implicitHeight: Theme.size(158)
                            radius: Theme.radiusMedium
                            color: Theme.surfaceMuted

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.size(14)
                                spacing: Theme.size(4)
                                Text { textFormat: Text.PlainText; text: qsTr("Default Cards"); color: Theme.text; font.pixelSize: Theme.fontSize(14); font.weight: Font.DemiBold }
                                Text {
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: qsTr("All printings and collector detail · ~80 MiB compressed + Chinese names")
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fontSize(10)
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                                Item { Layout.fillHeight: true }
                                RowLayout {
                                    Layout.fillWidth: true
                                    AppButton {
                                        Layout.fillWidth: true
                                        compact: true
                                        visible: !cardCatalog.installed
                                                 || cardCatalog.catalogUpdateAvailable
                                                 || !cardCatalog.enhancedIndexInstalled
                                                 || !cardCatalog.chineseIndexInstalled
                                        text: !cardCatalog.installed
                                              ? qsTr("Download Default")
                                              : qsTr("Update now")
                                        enabled: !cardCatalog.busy
                                        onClicked: root.confirmDownload("default_cards")
                                    }
                                    AppButton {
                                        compact: true
                                        text: qsTr("Import…")
                                        enabled: !cardCatalog.busy
                                        onClicked: root.chooseImport("default_cards")
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.size(6)
                        visible: cardCatalog.busy
                        spacing: Theme.size(7)

                        RowLayout {
                            Layout.fillWidth: true
                            Text { textFormat: Text.PlainText; text: I18n.status(cardCatalog.status); color: Theme.primary; font.pixelSize: Theme.fontSize(12) }
                            Item { Layout.fillWidth: true }
                            Text { textFormat: Text.PlainText; text: Math.round(cardCatalog.progress * 100) + "%"; color: Theme.textMuted; font.pixelSize: Theme.fontSize(11) }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Theme.size(6)
                            radius: Theme.size(3)
                            color: Theme.disabled
                            Rectangle {
                                width: parent.width * cardCatalog.progress
                                height: parent.height
                                radius: Theme.size(3)
                                color: Theme.primary
                                Behavior on width { NumberAnimation { duration: Theme.motionNormal } }
                            }
                        }
                    }

                    InfoBanner {
                        Layout.fillWidth: true
                        message: I18n.status(cardCatalog.lastError)
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: qsTr("Metadata: Scryfall · Chinese names: MTGCH (CC BY-SA 4.0) · Stored only on this device")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(10)
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }

    ConfirmDialog {
        id: downloadDialog
        titleText: qsTr("Download the card database?")
        message: qsTr("Hexproof will download and verify the latest prebuilt database. It will not build a database from upstream sources on this device.")
        confirmText: qsTr("Download")
        onConfirmed: cardCatalog.downloadCatalog(root.pendingPackage)
    }

    FileDialog {
        id: catalogFileDialog
        title: qsTr("Import card database")
        fileMode: FileDialog.OpenFile
        nameFilters: [
            qsTr("Card database files") + " (*.sqlite *.db *.json *.gz)",
            qsTr("All files") + " (*)"
        ]
        onAccepted:
            cardCatalog.importCatalogFile(selectedFile, root.pendingPackage)
    }

    function confirmDownload(packageType) {
        root.pendingPackage = packageType
        downloadDialog.open()
    }

    function chooseImport(packageType) {
        root.pendingPackage = packageType
        catalogFileDialog.open()
    }

    function packageLabel(packageType) {
        return packageType === "default_cards"
               ? qsTr("Default Cards") : qsTr("Legacy card database")
    }

    function catalogVersionDate(version) {
        if (!version)
            return qsTr("Unknown")
        const parsed = new Date(version)
        return isNaN(parsed.getTime()) ? qsTr("Unknown")
                                        : Qt.formatDateTime(parsed, "yyyy-MM-dd")
    }

    function catalogStatusText() {
        if (cardCatalog.checkingCatalogVersion)
            return qsTr("Checking")
        if (!cardCatalog.installed)
            return cardCatalog.latestCatalogKnown ? qsTr("Ready to download")
                                                   : qsTr("Not installed")
        if (!cardCatalog.enhancedIndexInstalled || !cardCatalog.chineseIndexInstalled)
            return qsTr("Update needed")
        if (cardCatalog.catalogUpdateAvailable)
            return qsTr("Update available")
        if (cardCatalog.latestCatalogKnown && cardCatalog.latestCatalogCompatible)
            return qsTr("Up to date")
        return qsTr("Latest unknown")
    }

    function catalogStatusColor() {
        if (cardCatalog.checkingCatalogVersion)
            return Theme.primary
        if (cardCatalog.installed && cardCatalog.latestCatalogKnown
                && cardCatalog.latestCatalogCompatible
                && !cardCatalog.catalogUpdateAvailable
                && cardCatalog.enhancedIndexInstalled
                && cardCatalog.chineseIndexInstalled)
            return Theme.success
        return Theme.warning
    }

    function setInterfaceScale(scale) {
        preferences.interfaceScale = Math.round(scale * 20) / 20
    }

    Component.onCompleted: {
        cardCatalog.clearLastError()
        cardCatalog.checkCatalogUpdateIfDue()
    }
}
