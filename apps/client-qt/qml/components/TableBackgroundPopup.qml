// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

AppPopup {
    id: root

    property var preferencesModel: null

    objectName: "tableBackgroundPopup"
    width: parent ? Math.min(Theme.size(780), Math.max(0, parent.width - Theme.size(32))) : 0
    height: parent ? Math.min(body.implicitHeight + padding * 2,
                             Math.max(0, parent.height - Theme.size(32))) : 0
    padding: Theme.size(20)

    contentItem: ColumnLayout {
        id: body
        spacing: Theme.size(14)

        ScrollView {
            id: backgroundScroll
            objectName: "tableBackgroundScroll"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: picker.implicitHeight
            contentWidth: availableWidth
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            TableBackgroundPicker {
                id: picker
                width: backgroundScroll.availableWidth
                enabled: root.preferencesModel !== null
                selectedId: root.preferencesModel
                            && root.preferencesModel.tableBackground !== undefined
                            ? root.preferencesModel.tableBackground : "default"
                onBackgroundSelected: key => root.preferencesModel.tableBackground = key
            }
        }

        AppButton {
            objectName: "closeTableBackgroundButton"
            Layout.alignment: Qt.AlignRight
            compact: true
            text: qsTr("Done")
            onClicked: root.close()
        }
    }
}
