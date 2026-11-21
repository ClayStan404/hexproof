// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

AppPopup {
    id: root

    required property var library
    readonly property var formatOptions: I18n.deckFormatOptions()
    signal created()

    width: parent ? Math.min(Theme.size(520), parent.width - Theme.size(48)) : 0
    height: parent ? Math.min(implicitHeight, parent.height - Theme.size(48)) : 0
    onOpened: {
        nameField.text = ""
        formatField.currentIndex = 0
        formBody.contentY = 0
        library.clearLastError()
        nameField.forceActiveFocus()
    }

    function submit() {
        if (!library.createDeck(nameField.text, formatOptions[formatField.currentIndex].value))
            return
        if (library.formatFilter !== "all"
                && library.formatFilter !== library.currentDeckFormat)
            library.formatFilter = "all"
        close()
        created()
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(18)

        AppPopupHeader { titleText: qsTr("New deck") }

        Flickable {
            id: formBody
            objectName: "createDeckBody"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            implicitHeight: fields.implicitHeight
            contentWidth: width
            contentHeight: fields.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: fields
                width: formBody.width
                spacing: Theme.size(12)

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Deck name")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(14)
                }
                AppTextField {
                    id: nameField
                    objectName: "createDeckNameField"
                    Layout.fillWidth: true
                    onAccepted: root.submit()
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Format")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(14)
                }
                AppComboBox {
                    id: formatField
                    objectName: "createDeckFormatField"
                    Layout.fillWidth: true
                    model: root.formatOptions
                    textRole: "label"
                    valueRole: "value"
                }
                InfoBanner {
                    objectName: "createDeckError"
                    Layout.fillWidth: true
                    message: I18n.status(root.library.lastError)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(10)
            Item { Layout.fillWidth: true }
            AppButton {
                objectName: "cancelCreateDeckButton"
                compact: true
                variant: "ghost"
                text: qsTr("Cancel")
                onClicked: root.close()
            }
            AppButton {
                objectName: "confirmCreateDeckButton"
                compact: true
                variant: "primary"
                text: qsTr("Create deck")
                onClicked: root.submit()
            }
        }
    }
}
