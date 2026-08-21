// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import "../components"

Page {
    id: root

    readonly property var appWindow: ApplicationWindow.window
    readonly property var formatOptions: [
        {"label": I18n.formatLabel("custom"), "value": "custom"},
        {"label": I18n.formatLabel("standard"), "value": "standard"},
        {"label": I18n.formatLabel("pioneer"), "value": "pioneer"},
        {"label": I18n.formatLabel("modern"), "value": "modern"},
        {"label": I18n.formatLabel("legacy"), "value": "legacy"},
        {"label": I18n.formatLabel("vintage"), "value": "vintage"},
        {"label": I18n.formatLabel("pauper"), "value": "pauper"},
        {"label": I18n.formatLabel("duel"), "value": "duel"},
        {"label": I18n.formatLabel("commander"), "value": "commander"}
    ]

    property string deckFormat: "custom"
    property bool importCompleted: false
    property string importWarningMessage: ""

    function loadDeckFile(fileUrl) {
        const loaded = deckLibrary.loadDeckTextFile(fileUrl)
        if (loaded.ok !== true) {
            root.appWindow.showBanner(I18n.status(deckLibrary.lastError))
            return
        }
        deckText.text = loaded.text
        if (nameField.text.trim().length === 0
                && loaded.suggestedName.length > 0) {
            nameField.text = loaded.suggestedName
        }
        deckText.forceActiveFocus()
    }

    function translatedImportWarnings() {
        const translated = []
        for (let index = 0;
             index < deckLibrary.lastImportWarnings.length; ++index) {
            translated.push(
                I18n.status(deckLibrary.lastImportWarnings[index]))
        }
        return translated.join("\n")
    }

    background: AppBackground { }

    ScreenHeader {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(22)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        title: qsTr("Import deck")
        subtitle: qsTr("Moxfield and common plain-text lists are supported")
        onBackRequested: {
            if (!deckLibrary.importingDeck)
                root.appWindow.popScreen()
        }
    }

    Surface {
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: Theme.size(14)
        anchors.bottomMargin: Theme.size(28)
        width: Math.min(Theme.size(800), parent.width - Theme.size(72))
        elevated: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.size(28)
            spacing: Theme.size(10)

            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    spacing: Theme.size(3)
                    Text {
                        textFormat: Text.PlainText
                        text: qsTr("Build from pasted text or a file")
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(24)
                        font.weight: Font.DemiBold
                    }
                    Text {
                        textFormat: Text.PlainText
                        text: qsTr("Import the list first. Choose printings in the editor, then cache art when the versions look right.")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(12)
                    }
                }
                Item { Layout.fillWidth: true }
                StatusPill {
                    text: qsTr("Local only")
                    statusColor: Theme.primary
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.size(14)
                spacing: Theme.size(18)

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.size(8)
                    Text {
                        textFormat: Text.PlainText
                        text: qsTr("DECK NAME")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(11)
                        font.weight: Font.Bold
                        font.letterSpacing: 1.1
                    }
                    AppTextField {
                        id: nameField
                        Layout.fillWidth: true
                        placeholderText: "Izzet Murktide"
                        maximumLength: 80
                        enabled: !deckLibrary.importingDeck
                                 && !root.importCompleted
                    }
                }

                ColumnLayout {
                    Layout.preferredWidth: Theme.size(330)
                    spacing: Theme.size(8)
                    Text {
                        textFormat: Text.PlainText
                        text: qsTr("FORMAT")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(11)
                        font.weight: Font.Bold
                        font.letterSpacing: 1.1
                    }
                    AppComboBox {
                        Layout.fillWidth: true
                        model: root.formatOptions
                        textRole: "label"
                        valueRole: "value"
                        currentIndex: 0
                        enabled: !deckLibrary.importingDeck
                                 && !root.importCompleted
                        onActivated: index => root.deckFormat =
                                     root.formatOptions[index].value
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.size(10)
                spacing: Theme.size(8)
                Text {
                    textFormat: Text.PlainText
                    text: qsTr("DECK LIST")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                    font.weight: Font.Bold
                    font.letterSpacing: 1.1
                }
                Item { Layout.fillWidth: true }
                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Example: 4 Lightning Bolt (M11) 149")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(10)
                }
                AppButton {
                    objectName: "chooseDeckListFileButton"
                    compact: true
                    variant: "secondary"
                    text: qsTr("Choose file…")
                    enabled: !deckLibrary.importingDeck
                             && !root.importCompleted
                    onClicked: importFileDialog.open()
                }
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: Theme.size(250)
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded
                ScrollBar.horizontal.policy: ScrollBar.AsNeeded

                TextArea {
                    id: deckText
                    placeholderText: "Deck\n4 Lightning Bolt\n4 Monastery Swiftspear\n\nSideboard\n2 Smash to Smithereens"
                    color: Theme.text
                    placeholderTextColor: Theme.textMuted
                    selectionColor: Theme.primaryMuted
                    selectedTextColor: Theme.text
                    font.pixelSize: Theme.fontSize(13)
                    font.family: "monospace"
                    wrapMode: TextArea.NoWrap
                    enabled: !deckLibrary.importingDeck
                             && !root.importCompleted
                    leftPadding: Theme.size(15)
                    rightPadding: Theme.size(15)
                    topPadding: Theme.size(14)
                    bottomPadding: Theme.size(14)
                    background: Rectangle {
                        color: Theme.surfaceMuted
                        radius: Theme.radiusMedium
                        border.width: 1
                        border.color: deckText.activeFocus ? Theme.primary : Theme.border
                    }
                }
            }

            InfoBanner {
                Layout.fillWidth: true
                message: root.importCompleted
                         ? root.importWarningMessage
                         : I18n.status(deckLibrary.lastError)
                tone: root.importCompleted ? "warning" : "error"
            }

            RowLayout {
                Layout.fillWidth: true
                visible: deckLibrary.importingDeck
                spacing: Theme.size(9)

                ActivityRing { }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: deckLibrary.importStage === "finalizing"
                          ? qsTr("Saving deck and queuing card images…")
                          : qsTr("Parsing deck list…")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(12)
                }
            }

            Text {
                textFormat: Text.PlainText
                objectName: "importDeckBlockerText"
                Layout.fillWidth: true
                visible: !root.importCompleted
                         && !deckLibrary.importingDeck
                         && text.length > 0
                text: root.importBlockerReason()
                color: Theme.warning
                font.pixelSize: Theme.fontSize(12)
                horizontalAlignment: Text.AlignRight
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.size(6)
                AppButton {
                    variant: "ghost"
                    text: root.importCompleted
                          ? qsTr("Done")
                          : qsTr("Cancel")
                    enabled: !deckLibrary.importingDeck
                    onClicked: root.appWindow.popScreen()
                }
                Item { Layout.fillWidth: true }
                AppButton {
                    visible: !root.importCompleted
                    variant: "primary"
                    text: deckLibrary.importingDeck
                          ? (deckLibrary.importStage === "finalizing"
                             ? qsTr("Finishing…")
                             : qsTr("Parsing…"))
                          : qsTr("Import deck")
                    leadingText: deckLibrary.importingDeck ? "" : "→"
                    enabled: !deckLibrary.importingDeck
                             && nameField.text.trim().length > 0
                             && deckText.text.trim().length > 0
                    disabledReason: root.importBlockerReason()
                    onClicked: {
                        deckLibrary.importDeckAsync(nameField.text.trim(),
                                                    root.deckFormat,
                                                    deckText.text)
                    }
                }
            }
        }
    }

    Connections {
        target: deckLibrary
        function onDeckImportFinished(success) {
            if (!success)
                return
            if (deckLibrary.lastImportWarnings.length > 0) {
                root.importCompleted = true
                root.importWarningMessage =
                    qsTr("Deck imported with warnings:")
                    + "\n" + root.translatedImportWarnings()
                return
            }
            root.appWindow.popScreen()
            root.appWindow.showBanner(qsTr("Deck imported"))
        }
    }

    FileDialog {
        id: importFileDialog
        objectName: "importDeckFileDialog"
        title: qsTr("Open deck list")
        fileMode: FileDialog.OpenFile
        nameFilters: [
            qsTr("Deck lists") + " (*.txt *.dec)",
            qsTr("All files") + " (*)"
        ]
        onAccepted: root.loadDeckFile(selectedFile)
    }

    function importBlockerReason() {
        if (deckLibrary.importingDeck || root.importCompleted)
            return ""
        if (nameField.text.trim().length === 0)
            return qsTr("Enter a deck name")
        if (deckText.text.trim().length === 0)
            return qsTr("Paste a deck list or choose a file")
        return ""
    }

    Component.onCompleted: {
        root.importCompleted = false
        root.importWarningMessage = ""
        deckLibrary.clearLastError()
    }
}
