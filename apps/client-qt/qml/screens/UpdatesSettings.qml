// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    objectName: "updatesSettingsScreen"
    background: AppBackground { }

    SettingsPage {
        anchors.fill: parent
        title: qsTr("Application updates")
        subtitle: qsTr("Check GitHub Releases and download the verified package for this device.")

        ApplicationUpdatePanel {
            Layout.fillWidth: true
            updater: appUpdater
        }
    }
}
