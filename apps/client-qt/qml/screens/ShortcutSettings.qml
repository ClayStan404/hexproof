// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root

    objectName: "shortcutSettingsScreen"

    readonly property var appWindow: ApplicationWindow.window
    property string query: ""

    background: AppBackground { }

    ShortcutActionCatalog { id: catalog }

    ScreenHeader {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(22)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        title: qsTr("Keyboard shortcuts")
        subtitle: qsTr("Assign, disable, or restore every keyboard action")
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
            width: Math.min(Theme.size(860), parent.width - Theme.size(72))
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.size(14)

            Surface {
                Layout.fillWidth: true
                implicitHeight: searchContent.implicitHeight + Theme.size(36)
                elevated: true

                RowLayout {
                    id: searchContent
                    anchors.fill: parent
                    anchors.margins: Theme.size(18)
                    spacing: Theme.size(12)

                    AppTextField {
                        Layout.fillWidth: true
                        placeholderText: qsTr("Search actions…")
                        onTextChanged: root.query = text.trim().toLowerCase()
                    }
                    AppButton {
                        compact: true
                        variant: "ghost"
                        text: qsTr("Reset all")
                        enabled: root.anyCustomized()
                        onClicked: resetAllDialog.open()
                    }
                }
            }

            Repeater {
                model: catalog.groups

                delegate: Surface {
                    id: groupSurface
                    required property var modelData
                    readonly property var visibleActions:
                        root.filteredActions(groupSurface.modelData.actions)

                    Layout.fillWidth: true
                    implicitHeight: groupContent.implicitHeight + Theme.size(40)
                    elevated: true
                    visible: visibleActions.length > 0

                    ColumnLayout {
                        id: groupContent
                        anchors.fill: parent
                        anchors.margins: Theme.size(20)
                        spacing: Theme.size(8)

                        Text {
                            textFormat: Text.PlainText
                            text: groupSurface.modelData.name
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(18)
                            font.weight: Font.DemiBold
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: Theme.divider
                        }

                        Repeater {
                            model: groupSurface.visibleActions

                            delegate: RowLayout {
                                id: actionRow
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.minimumHeight: Theme.size(48)
                                spacing: Theme.size(12)

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.size(2)
                                    Text {
                                        textFormat: Text.PlainText
                                        Layout.fillWidth: true
                                        text: actionRow.modelData.label
                                        color: Theme.text
                                        font.pixelSize: Theme.fontSize(12)
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        Layout.fillWidth: true
                                        text: actionRow.modelData.id
                                        color: Theme.textMuted
                                        font.pixelSize: Theme.fontSize(9)
                                        elide: Text.ElideRight
                                    }
                                }

                                StatusPill {
                                    visible: {
                                        const revision = preferences.shortcutRevision
                                        return preferences.shortcutCustomized(
                                                    actionRow.modelData.id)
                                    }
                                    text: qsTr("Custom")
                                    statusColor: Theme.warning
                                }

                                Text {
                                    textFormat: Text.PlainText
                                    Layout.preferredWidth: Theme.size(160)
                                    text: {
                                        const revision = preferences.shortcutRevision
                                        return preferences.shortcutDisplay(
                                            actionRow.modelData.id)
                                    }
                                    color: Theme.accent
                                    font.pixelSize: Theme.fontSize(12)
                                    font.weight: Font.DemiBold
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                }

                                AppButton {
                                    compact: true
                                    variant: "ghost"
                                    text: qsTr("Reset")
                                    visible: {
                                        const revision = preferences.shortcutRevision
                                        return preferences.shortcutCustomized(
                                                    actionRow.modelData.id)
                                    }
                                    onClicked: preferences.resetShortcut(
                                                   actionRow.modelData.id)
                                }
                                AppButton {
                                    compact: true
                                    text: qsTr("Change")
                                    onClicked: capturePopup.startCapture(
                                                   actionRow.modelData.id,
                                                   actionRow.modelData.label)
                                }
                            }
                        }
                    }
                }
            }

            InfoBanner {
                Layout.fillWidth: true
                tone: "warning"
                message: qsTr("Text fields and modal editors temporarily pause shortcuts. Mouse and focus-navigation gestures are not keyboard bindings and remain fixed.")
            }

            InfoBanner {
                Layout.fillWidth: true
                message: I18n.status(preferences.lastError)
            }
        }
    }

    Popup {
        id: capturePopup

        objectName: "shortcutCapturePopup"

        property string actionId: ""
        property string actionLabel: ""
        property string capturedSequence: ""
        property string conflictAction: ""
        property bool hasCaptured: false

        parent: Overlay.overlay
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: Math.min(Theme.size(560), parent.width - Theme.size(48))
        height: Theme.size(360)
        padding: Theme.size(22)
        modal: true
        focus: true
        closePolicy: Popup.NoAutoClose
        Overlay.modal: Rectangle { color: "#A6050B09" }
        onOpened: {
            preferences.shortcutCaptureActive = true
            Qt.callLater(() => captureFocus.forceActiveFocus(
                             Qt.PopupFocusReason))
        }
        onClosed: preferences.shortcutCaptureActive = false

        function startCapture(actionId, actionLabel) {
            capturePopup.actionId = actionId
            capturePopup.actionLabel = actionLabel
            capturePopup.capturedSequence = ""
            capturePopup.conflictAction = ""
            capturePopup.hasCaptured = false
            preferences.clearLastError()
            capturePopup.open()
        }

        function acceptSequence() {
            if (capturePopup.conflictAction.length > 0)
                return
            if (preferences.setShortcutSequence(capturePopup.actionId,
                                                capturePopup.capturedSequence))
                capturePopup.close()
        }

        background: Rectangle {
            color: Theme.surfaceElevated
            radius: Theme.radiusLarge
            border.width: 1
            border.color: Theme.borderStrong
        }

        contentItem: FocusScope {
            id: captureFocus
            objectName: "shortcutCaptureFocus"
            focus: true

            Keys.priority: Keys.BeforeItem
            Keys.onShortcutOverride: event => event.accepted = true
            Keys.onPressed: event => {
                event.accepted = true
                if (event.isAutoRepeat)
                    return
                if (event.key === Qt.Key_Escape) {
                    capturePopup.close()
                    return
                }
                if (event.key === Qt.Key_Backspace
                        || event.key === Qt.Key_Delete) {
                    capturePopup.capturedSequence = ""
                    capturePopup.conflictAction = ""
                    capturePopup.hasCaptured = true
                    return
                }
                const sequence = preferences.keyEventSequence(
                                   event.key, event.modifiers)
                if (sequence.length === 0)
                    return
                capturePopup.capturedSequence = sequence
                capturePopup.hasCaptured = true
                capturePopup.conflictAction =
                        preferences.shortcutConflictAction(
                            capturePopup.actionId, sequence)
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: Theme.size(14)

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Change shortcut")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(20)
                    font.weight: Font.DemiBold
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: capturePopup.actionLabel
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(12)
                    wrapMode: Text.WordWrap
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.size(92)
                    radius: Theme.radiusMedium
                    color: Theme.surfaceMuted
                    border.width: 1
                    border.color: capturePopup.conflictAction.length > 0
                                  ? Theme.error : Theme.border

                    Column {
                        anchors.centerIn: parent
                        spacing: Theme.size(7)
                        Text {
                            textFormat: Text.PlainText
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: capturePopup.capturedSequence.length > 0
                                  ? capturePopup.capturedSequence
                                  : (capturePopup.hasCaptured
                                     ? qsTr("Unassigned")
                                     : qsTr("Press a key combination"))
                            color: capturePopup.capturedSequence.length > 0
                                   ? Theme.accent : Theme.textMuted
                            font.pixelSize: Theme.fontSize(18)
                            font.weight: Font.DemiBold
                        }
                        Text {
                            textFormat: Text.PlainText
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: qsTr("Backspace or Delete clears the binding · Escape cancels")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(10)
                        }
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    visible: capturePopup.conflictAction.length > 0
                    text: qsTr("Already assigned to: %1")
                          .arg(catalog.labelFor(capturePopup.conflictAction))
                    color: Theme.error
                    font.pixelSize: Theme.fontSize(11)
                    wrapMode: Text.WordWrap
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    visible: preferences.lastError.length > 0
                    text: I18n.status(preferences.lastError)
                    color: Theme.error
                    font.pixelSize: Theme.fontSize(11)
                    wrapMode: Text.WordWrap
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.size(10)
                    AppButton {
                        compact: true
                        variant: "ghost"
                        text: qsTr("Use default (%1)")
                              .arg(preferences.defaultShortcutDisplay(
                                       capturePopup.actionId))
                        onClicked: {
                            if (preferences.resetShortcut(capturePopup.actionId))
                                capturePopup.close()
                        }
                    }
                    Item { Layout.fillWidth: true }
                    AppButton {
                        compact: true
                        variant: "ghost"
                        text: qsTr("Cancel")
                        onClicked: capturePopup.close()
                    }
                    AppButton {
                        compact: true
                        variant: "primary"
                        text: qsTr("Save")
                        enabled: capturePopup.hasCaptured
                                 && capturePopup.conflictAction.length === 0
                        onClicked: capturePopup.acceptSequence()
                    }
                }
            }
        }
    }

    ConfirmDialog {
        id: resetAllDialog
        titleText: qsTr("Reset every shortcut?")
        message: qsTr("All keyboard actions will return to their default bindings.")
        confirmText: qsTr("Reset all")
        onConfirmed: preferences.resetAllShortcuts()
    }

    function filteredActions(actions) {
        if (root.query.length === 0)
            return actions
        return actions.filter(item => item.label.toLowerCase().includes(root.query)
                              || item.id.toLowerCase().includes(root.query))
    }

    function anyCustomized() {
        const revision = preferences.shortcutRevision
        for (const group of catalog.groups) {
            for (const action of group.actions) {
                if (preferences.shortcutCustomized(action.id))
                    return true
            }
        }
        return false
    }

    Component.onDestruction: preferences.shortcutCaptureActive = false
}
