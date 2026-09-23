// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    required property var wsModel
    readonly property var failure: wsModel.rulesStartFailure || ({})
    readonly property bool active: !!failure.reason
    readonly property string details: I18n.rulesStartFailureDetails(failure)
    visible: active
    implicitHeight: noticeContent.implicitHeight

    function showDetails() {
        if (root.active)
            detailsDialog.open();
    }
    function syncDetails() {
        if (root.active)
            root.showDetails();
        else
            detailsDialog.close();
    }
    onFailureChanged: Qt.callLater(root.syncDetails)
    Component.onCompleted: Qt.callLater(root.syncDetails)

    ColumnLayout {
        id: noticeContent
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.size(8)
        InfoBanner {
            objectName: "rulesStartFailureSummary"
            Layout.fillWidth: true
            message: root.active ? I18n.rulesStartFailureReason(root.failure.reason) : ""
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(8)
            AppButton {
                objectName: "rulesStartFailureDetailsButton"
                compact: true
                text: qsTr("Show details")
                onClicked: root.showDetails()
            }
            AppButton {
                objectName: "rulesStartFailureCopyButton"
                compact: true
                variant: "ghost"
                text: qsTr("Copy details")
                onClicked: root.wsModel.copyToClipboard(root.details)
            }
            Item {
                Layout.fillWidth: true
            }
            AppButton {
                objectName: "rulesStartFailureDismissButton"
                compact: true
                variant: "ghost"
                text: qsTr("Dismiss")
                onClicked: root.wsModel.dismissRulesStartFailure()
            }
        }
    }

    AppPopup {
        id: detailsDialog
        objectName: "rulesStartFailureDialog"
        width: parent ? Math.min(Theme.size(720), Math.max(0, parent.width - Theme.size(48))) : 0
        height: parent ? Math.min(Theme.size(560), Math.max(0, parent.height - Theme.size(48))) : 0
        closePolicy: Popup.CloseOnEscape

        contentItem: ColumnLayout {
            spacing: Theme.size(16)
            AppPopupHeader {
                titleText: qsTr("Forge could not start the game")
                showClose: true
                closeObjectName: "rulesStartFailureCloseButton"
                onCloseRequested: detailsDialog.close()
            }
            ScrollView {
                objectName: "rulesStartFailureScroll"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                clip: true
                contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical.policy: ScrollBar.AsNeeded
                TextArea {
                    objectName: "rulesStartFailureText"
                    textFormat: TextEdit.PlainText
                    text: root.details
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(14)
                    background: null
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.size(10)
                AppButton {
                    objectName: "rulesStartFailureDialogCopyButton"
                    compact: true
                    text: qsTr("Copy details")
                    onClicked: root.wsModel.copyToClipboard(root.details)
                }
                Item {
                    Layout.fillWidth: true
                }
                AppButton {
                    objectName: "rulesStartFailureDialogCloseButton"
                    compact: true
                    variant: "ghost"
                    text: qsTr("Close")
                    onClicked: detailsDialog.close()
                }
            }
        }
    }
}
