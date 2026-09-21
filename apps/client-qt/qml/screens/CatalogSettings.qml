// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import "../components"

Page {
    id: root
    objectName: "catalogSettingsScreen"
    property string pendingPackage: ""
    background: AppBackground { }

    SettingsPage {
        anchors.fill: parent
        title: qsTr("Card database")
        subtitle: qsTr("Searchable metadata for the deck editor")

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
                                .arg(root.packageLabel(cardCatalog.packageName))
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
                            .arg(root.catalogVersionDate(cardCatalog.installedCatalogVersion))
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
                                   .arg(root.catalogVersionDate(cardCatalog.latestCatalogVersion))
                                   .arg(cardCatalog.latestCatalogSchemaVersion)
                                 : qsTr("Unavailable"))
                        color: cardCatalog.latestCatalogKnown ? Theme.text : Theme.textMuted
                        font.pixelSize: Theme.fontSize(11)
                        font.weight: Font.DemiBold
                    }
                    AppButton {
                        objectName: "settingsCheckCatalogUpdatesButton"
                        compact: true
                        variant: "ghost"
                        text: qsTr("Check updates")
                        enabled: !cardCatalog.checkingCatalogVersion && !cardCatalog.busy
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
                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("Default Cards")
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(14)
                            font.weight: Font.DemiBold
                        }
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
                                objectName: "settingsDownloadCatalogButton"
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
                                objectName: "settingsImportCatalogButton"
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
                    Text {
                        textFormat: Text.PlainText
                        text: I18n.status(cardCatalog.status)
                        color: Theme.primary
                        font.pixelSize: Theme.fontSize(12)
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        textFormat: Text.PlainText
                        text: Math.round(cardCatalog.progress * 100) + "%"
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(11)
                    }
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

    ConfirmDialog {
        id: downloadDialog
        objectName: "settingsCatalogDownloadDialog"
        titleText: qsTr("Download the card database?")
        message: qsTr("Hexproof will download and verify the latest prebuilt database. It will not build a database from upstream sources on this device.")
        confirmText: qsTr("Download")
        onConfirmed: cardCatalog.downloadCatalog(root.pendingPackage)
    }

    FileDialog {
        id: catalogFileDialog
        objectName: "catalogImportFileDialog"
        title: qsTr("Import card database")
        fileMode: FileDialog.OpenFile
        nameFilters: [
            qsTr("Card database files") + " (*.sqlite *.db *.json *.gz)",
            qsTr("All files") + " (*)"
        ]
        onAccepted: cardCatalog.importCatalogFile(selectedFile, root.pendingPackage)
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

    Component.onCompleted: {
        cardCatalog.clearLastError()
        cardCatalog.checkCatalogUpdateIfDue()
    }
}
