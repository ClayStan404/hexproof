// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Layouts

Surface {
    id: root

    required property var updater

    implicitHeight: content.implicitHeight + Theme.size(48)
    elevated: true

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Theme.size(24)
        spacing: Theme.size(12)

        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(3)

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Application updates")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(20)
                    font.weight: Font.DemiBold
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Check GitHub Releases and download the verified package for this device.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(12)
                    wrapMode: Text.WordWrap
                }
            }

            StatusPill {
                objectName: "applicationUpdateStatus"
                text: root.statusText()
                statusColor: root.statusColor()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.divider
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Theme.size(20)
            rowSpacing: Theme.size(8)

            Text {
                textFormat: Text.PlainText
                text: qsTr("Installed version")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(11)
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.updater.currentVersion
                color: Theme.text
                font.pixelSize: Theme.fontSize(11)
                font.weight: Font.DemiBold
            }

            Text {
                textFormat: Text.PlainText
                text: root.updater.exactVersion
                      ? qsTr("Required version") : qsTr("Latest version")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(11)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.size(8)

                Text {
                    objectName: "applicationLatestVersion"
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: root.latestVersionText()
                    color: root.updater.releaseAvailable ? Theme.text : Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                    font.weight: Font.DemiBold
                }

                AppButton {
                    objectName: "checkApplicationUpdatesButton"
                    compact: true
                    variant: "ghost"
                    text: qsTr("Check updates")
                    enabled: !root.updater.checking && !root.updater.downloading
                    onClicked: root.updater.checkForUpdates()
                }
            }
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: root.updater.releaseAvailable && root.updater.publishedAt.length > 0
            text: qsTr("Published %1").arg(root.releaseDate(root.updater.publishedAt))
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize(10)
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: root.updater.releaseNotes.length > 0
            text: root.updater.releaseNotes
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(11)
            wrapMode: Text.WordWrap
            maximumLineCount: 5
            elide: Text.ElideRight
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.updater.downloading
            spacing: Theme.size(7)

            RowLayout {
                Layout.fillWidth: true

                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Downloading update…")
                    color: Theme.primary
                    font.pixelSize: Theme.fontSize(12)
                }

                Item { Layout.fillWidth: true }

                Text {
                    textFormat: Text.PlainText
                    text: Math.round(root.updater.progress * 100) + "%"
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
                    width: parent.width * root.updater.progress
                    height: parent.height
                    radius: Theme.size(3)
                    color: Theme.primary
                    Behavior on width { NumberAnimation { duration: Theme.motionNormal } }
                }
            }
        }

        InfoBanner {
            Layout.fillWidth: true
            visible: root.updater.downloadReady
            tone: "success"
            message: qsTr("The update package was downloaded and verified. Exit Hexproof before replacing the installed application.")
        }

        InfoBanner {
            Layout.fillWidth: true
            visible: root.updater.lastError.length > 0
            tone: "warning"
            message: I18n.status(root.updater.lastError)
        }

        Flow {
            Layout.fillWidth: true
            Layout.topMargin: Theme.size(4)
            spacing: Theme.size(10)

            AppButton {
                objectName: "downloadApplicationUpdateButton"
                visible: root.updater.updateAvailable && !root.updater.downloadReady
                text: root.updater.exactVersion
                      ? qsTr("Download matching version") : qsTr("Download update")
                enabled: !root.updater.checking && !root.updater.downloading
                onClicked: root.updater.downloadUpdate()
            }

            AppButton {
                objectName: "openApplicationUpdateFolderButton"
                visible: root.updater.downloadReady
                text: qsTr("Open download folder")
                onClicked: root.updater.openDownloadLocation()
            }

            AppButton {
                objectName: "cancelApplicationUpdateButton"
                visible: root.updater.downloading
                variant: "ghost"
                text: qsTr("Cancel download")
                onClicked: root.updater.cancelDownload()
            }

            AppButton {
                objectName: "viewApplicationReleaseButton"
                visible: root.updater.releaseAvailable
                compact: true
                variant: "ghost"
                text: qsTr("View release")
                onClicked: root.updater.openReleasePage()
            }
        }
    }

    function latestVersionText() {
        if (root.updater.checking)
            return qsTr("Checking…")
        if (!root.updater.releaseAvailable)
            return qsTr("Not checked")
        if (root.updater.cachedRelease && root.updater.lastError.length > 0)
            return qsTr("%1 (cached)").arg(root.updater.targetVersion)
        return root.updater.targetVersion
    }

    function statusText() {
        if (root.updater.checking)
            return qsTr("Checking")
        if (root.updater.downloading)
            return qsTr("Downloading")
        if (root.updater.downloadReady)
            return qsTr("Ready to install")
        if (root.updater.updateAvailable)
            return root.updater.exactVersion
                    ? qsTr("Matching version found") : qsTr("Update available")
        if (root.updater.lastError.length > 0)
            return qsTr("Check failed")
        if (root.updater.releaseAvailable)
            return qsTr("Up to date")
        return qsTr("Latest unknown")
    }

    function statusColor() {
        if (root.updater.downloadReady)
            return Theme.success
        if (root.updater.lastError.length > 0)
            return Theme.warning
        if (root.updater.releaseAvailable && !root.updater.updateAvailable)
            return Theme.success
        if (root.updater.checking || root.updater.downloading)
            return Theme.primary
        return Theme.warning
    }

    function releaseDate(value) {
        const parsed = new Date(value)
        return isNaN(parsed.getTime()) ? qsTr("Unknown")
                                        : Qt.formatDateTime(parsed, "yyyy-MM-dd")
    }
}
