// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

AppPopup {
    id: root
    objectName: "forgeCrashReportNotice"
    property var service: null
    property string reportId: ""
    property bool detailsVisible: false
    property bool suspended: false
    onSuspendedChanged: { if (!suspended) Qt.callLater(showNext) }
    width: parent ? Math.min(Theme.size(800), parent.width - Theme.size(48)) : 0
    height: parent ? Math.min(implicitHeight, parent.height - Theme.size(48)) : 0
    closePolicy: Popup.CloseOnEscape
    onClosed: {
        const dismissedId = reportId
        reportId = ""
        if (service && dismissedId) service.dismiss(dismissedId)
        Qt.callLater(root.showNext)
    }
    function showNext() {
        if (!service || !service.noticeId || opened || suspended) return
        reportId = service.noticeId
        detailsVisible = false
        open()
    }
    Connections {
        target: root.service
        function onNoticeChanged() {
            if (root.opened && root.service.noticeId !== root.reportId) root.close()
            else Qt.callLater(root.showNext)
        }
    }
    Component.onCompleted: Qt.callLater(showNext)
    contentItem: ColumnLayout {
        spacing: Theme.size(16)
        AppPopupHeader { titleText: qsTr("Forge stopped unexpectedly") }
        ForgeCrashReportPanel {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: root.detailsVisible ? Theme.size(440) : implicitHeight
            service: root.service
            reportId: root.reportId
            showDetails: root.detailsVisible
            saveDialogObjectName: "forgeCrashNoticeSaveDialog"
        }
        RowLayout {
            Layout.fillWidth: true
            AppButton {
                objectName: "forgeCrashToggleDetails"
                text: root.detailsVisible ? qsTr("Hide details") : qsTr("Show details")
                variant: "ghost"
                onClicked: root.detailsVisible = !root.detailsVisible
            }
            Item { Layout.fillWidth: true }
            AppButton {
                objectName: "forgeCrashDismiss"
                text: qsTr("Dismiss")
                onClicked: root.close()
            }
        }
    }
}
