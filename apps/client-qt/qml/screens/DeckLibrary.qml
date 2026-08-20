// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import "../components"

Page {
    id: root

    readonly property var appWindow: ApplicationWindow.window
    readonly property var formatOptions: [
        {"label": qsTr("All formats"), "value": "all"},
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
    property string pendingDeckId: ""
    property string pendingDeckName: ""

    background: AppBackground { }

    ScreenHeader {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(22)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        title: qsTr("Deck library")
        subtitle: qsTr("Your local decks are available with or without a server connection")
        onBackRequested: root.appWindow.popScreen()
    }

    RowLayout {
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(14)
        anchors.bottomMargin: Theme.size(28)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        spacing: Theme.size(18)

        Surface {
            Layout.fillWidth: true
            Layout.fillHeight: true
            elevated: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.size(24)
                spacing: Theme.size(14)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.size(12)

                    ColumnLayout {
                        spacing: Theme.size(2)
                        Text {
                            textFormat: Text.PlainText
                            text: I18n.count("deck", deckLibrary.count)
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(20)
                            font.weight: Font.DemiBold
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: cardCatalog.busy ? I18n.status(cardCatalog.status)
                                                   : qsTr("Double-click a deck to edit it")
                            color: cardCatalog.busy ? Theme.primary : Theme.textMuted
                            font.pixelSize: Theme.fontSize(11)
                        }
                    }

                    Item { Layout.fillWidth: true }

                    AppComboBox {
                        Layout.preferredWidth: Theme.size(230)
                        model: root.formatOptions
                        textRole: "label"
                        valueRole: "value"
                        currentIndex: root.formatIndex(deckLibrary.formatFilter)
                        onActivated: index => deckLibrary.formatFilter =
                                     root.formatOptions[index].value
                    }

                    AppButton {
                        text: qsTr("Settings")
                        leadingText: "⚙"
                        onClicked: root.appWindow.pushScreen("screens/Settings.qml")
                    }

                    AppButton {
                        variant: "primary"
                        text: qsTr("Import deck")
                        leadingText: "+"
                        onClicked: root.appWindow.pushScreen("screens/ImportDeck.qml")
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Theme.divider
                }

                RowLayout {
                    id: deckStatusRow

                    readonly property string statusMessage:
                        I18n.status(deckLibrary.lastError.length > 0
                                    ? deckLibrary.lastError : cardCatalog.lastError)
                    readonly property bool retryAvailable:
                        deckLibrary.hasMissingArt && !cardCatalog.busy

                    Layout.fillWidth: true
                    spacing: Theme.size(10)
                    visible: statusMessage.length > 0 || retryAvailable

                    InfoBanner {
                        Layout.fillWidth: true
                        message: deckStatusRow.statusMessage
                    }

                    AppButton {
                        objectName: "cacheDeckArtButton"
                        compact: true
                        visible: deckStatusRow.retryAvailable
                        text: qsTr("Cache art")
                        onClicked: deckLibrary.refreshMissingArt()
                    }

                    AppButton {
                        objectName: "retryDeckArtButton"
                        compact: true
                        visible: deckStatusRow.retryAvailable
                        text: qsTr("Retry failed downloads")
                        onClicked: deckLibrary.retryMissingArt()
                    }
                }

                ListView {
                    id: deckList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: deckLibrary
                    spacing: Theme.size(10)
                    clip: true
                    visible: deckLibrary.count > 0
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Surface {
                        id: deckRow

                        required property string deckId
                        required property string deckName
                        required property string deckFormat
                        required property string tableMode
                        required property int mainCount
                        required property int sideboardCount
                        required property bool ready
                        required property string status
                        required property string commander
                        required property bool legalityVerified
                        required property var legalityIssues

                        width: ListView.view.width
                        height: Theme.size(86)
                        radius: Theme.radiusMedium
                        color: rowHover.hovered ? Theme.surfaceHover : Theme.surfaceMuted
                        border.color: rowHover.hovered ? Theme.borderStrong : Theme.border

                        HoverHandler {
                            id: rowHover
                        }

                        TapHandler {
                            id: rowTap
                            acceptedButtons: Qt.LeftButton
                            onDoubleTapped: {
                                if (deckLibrary.openDeck(deckRow.deckId))
                                    root.appWindow.pushScreen("screens/DeckEditor.qml")
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.size(16)
                            anchors.rightMargin: Theme.size(12)
                            spacing: Theme.size(14)

                            Rectangle {
                                Layout.preferredWidth: Theme.size(50)
                                Layout.preferredHeight: Theme.size(60)
                                radius: Theme.size(10)
                                color: deckRow.tableMode !== "modern" ? Theme.accentMuted : Theme.primaryMuted
                                border.width: 1
                                border.color: deckRow.tableMode !== "modern" ? "#695834" : "#2C654E"

                                Text {
                                    textFormat: Text.PlainText
                                    anchors.centerIn: parent
                                    text: deckRow.deckFormat === "custom" ? "1"
                                          : (deckRow.deckFormat === "duel" ? "D"
                                             : (deckRow.deckFormat === "commander" ? "C"
                                                : I18n.formatLabel(deckRow.deckFormat).charAt(0)))
                                    color: deckRow.tableMode !== "modern" ? Theme.accent : Theme.primary
                                    font.pixelSize: Theme.fontSize(20)
                                    font.weight: Font.Bold
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Theme.size(5)

                                RowLayout {
                                    spacing: Theme.size(10)
                                    Text {
                                        textFormat: Text.PlainText
                                        text: deckRow.deckName
                                        color: Theme.text
                                        font.pixelSize: Theme.fontSize(16)
                                        font.weight: Font.DemiBold
                                    }
                                    StatusPill {
                                        text: I18n.formatLabel(deckRow.deckFormat)
                                        statusColor: deckRow.tableMode !== "modern" ? Theme.accent : Theme.primary
                                    }
                                }

                                Text {
                                    textFormat: Text.PlainText
                                    text: qsTr("%1 main · %2 side")
                                          .arg(deckRow.mainCount)
                                          .arg(deckRow.sideboardCount)
                                          + (deckRow.tableMode !== "modern"
                                             && deckRow.commander.length > 0
                                             ? (" · " + deckRow.commander) : "")
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fontSize(11)
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            StatusPill {
                                text: I18n.status(deckRow.status)
                                statusColor: deckRow.ready && deckRow.legalityVerified
                                             ? Theme.success
                                             : (!deckRow.legalityVerified ? Theme.warning
                                             : (deckRow.status === "Commander required"
                                                ? Theme.warning : Theme.textMuted))
                                ToolTip.visible: legalityStatusHover.hovered
                                                 && deckRow.legalityIssues.length > 0
                                ToolTip.delay: 350
                                ToolTip.text: deckRow.legalityIssues
                                              .map(issue => I18n.status(issue)).join("\n")
                                HoverHandler { id: legalityStatusHover }
                            }

                            AppButton {
                                compact: true
                                text: qsTr("Edit")
                                onClicked: {
                                    if (deckLibrary.openDeck(deckRow.deckId))
                                        root.appWindow.pushScreen("screens/DeckEditor.qml")
                                }
                            }

                            AppButton {
                                objectName: "exportDeckButton"
                                compact: true
                                text: qsTr("Export")
                                onClicked: {
                                    root.pendingDeckId = deckRow.deckId
                                    root.pendingDeckName = deckRow.deckName
                                    exportDialog.open()
                                }
                            }

                            AppButton {
                                compact: true
                                variant: "ghost"
                                text: qsTr("Delete")
                                onClicked: {
                                    root.pendingDeckId = deckRow.deckId
                                    root.pendingDeckName = deckRow.deckName
                                    deleteDialog.open()
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: deckLibrary.count === 0

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Theme.size(12)

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: Theme.size(64)
                            Layout.preferredHeight: Theme.size(76)
                            radius: Theme.size(14)
                            color: Theme.primaryMuted
                            border.width: 1
                            border.color: Theme.borderStrong
                            Text {
                                textFormat: Text.PlainText
                                anchors.centerIn: parent
                                text: "◇"
                                color: Theme.primary
                                font.pixelSize: Theme.fontSize(30)
                            }
                        }
                        Text {
                            textFormat: Text.PlainText
                            Layout.alignment: Qt.AlignHCenter
                            text: qsTr("Your library is empty")
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(19)
                            font.weight: Font.DemiBold
                        }
                        Text {
                            textFormat: Text.PlainText
                            Layout.alignment: Qt.AlignHCenter
                            text: qsTr("Paste a list from Moxfield or any common plain-text export.")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(12)
                        }
                        AppButton {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: Theme.size(4)
                            variant: "primary"
                            text: qsTr("Import your first deck")
                            leadingText: "+"
                            onClicked: root.appWindow.pushScreen("screens/ImportDeck.qml")
                        }
                    }
                }
            }
        }
    }

    function formatIndex(value) {
        for (let index = 0; index < formatOptions.length; ++index) {
            if (formatOptions[index].value === value)
                return index
        }
        return 0
    }

    ConfirmDialog {
        id: deleteDialog
        titleText: qsTr("Delete %1?").arg(root.pendingDeckName)
        message: qsTr("The local deck list will be removed. Downloaded card images remain cached for other decks.")
        confirmText: qsTr("Delete deck")
        dangerous: true
        onConfirmed: deckLibrary.deleteDeck(root.pendingDeckId)
    }

    ExportDeckDialog {
        id: exportDialog
        objectName: "exportDeckDialog"
        deckName: root.pendingDeckName
        onCopyRequested: {
            if (deckLibrary.copyDeckText(root.pendingDeckId))
                root.appWindow.showBanner(qsTr("Deck list copied"))
            else
                root.appWindow.showBanner(I18n.status(deckLibrary.lastError))
        }
        onSaveRequested: {
            exportFileDialog.selectedFile =
                    deckLibrary.suggestedExportUrl(root.pendingDeckId)
            exportFileDialog.open()
        }
    }

    FileDialog {
        id: exportFileDialog
        title: qsTr("Save deck list")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "txt"
        nameFilters: [
            qsTr("Deck lists") + " (*.txt)",
            qsTr("All files") + " (*)"
        ]
        onAccepted: {
            if (deckLibrary.saveDeckText(root.pendingDeckId, selectedFile))
                root.appWindow.showBanner(qsTr("Deck list saved"))
            else
                root.appWindow.showBanner(I18n.status(deckLibrary.lastError))
        }
    }

    Component.onCompleted: {
        deckLibrary.clearLastError()
        cardCatalog.clearLastError()
    }
}
