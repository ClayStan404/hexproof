// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "RulesTable"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Surface {
    id: root
    required property var tableController
    property bool opened: false
    property string cardId: ""
    property string cardName: ""
    property var actions: []
    objectName: "rulesCardActionPicker"
    visible: opened
    implicitHeight: choices.implicitHeight + Theme.size(24)
    color: "transparent"
    radius: 0
    border.width: 0
    border.color: "transparent"

    function close() {
        opened = false
        cardId = ""
        actions = []
    }
    function showFor(id, name, options) {
        cardId = id
        cardName = name
        actions = options
        opened = true
        scroll.contentY = 0
        forceActiveFocus(Qt.OtherFocusReason)
    }
    function submit(responseId) {
        const sourceCardId = cardId
        close()
        tableController.interaction.submitCardAction(sourceCardId, responseId)
    }
    Keys.onEscapePressed: close()
    Connections {
        target: root.tableController.rulesSession
        function onPromptChanged() { root.close() }
    }
    Connections {
        target: root.tableController
        function onLocalSeatChanged() { root.close() }
    }
    Connections {
        target: root.tableController.interaction
        function onContextActiveChanged() {
            if (!root.tableController.interaction.contextActive)
                root.close()
        }
    }

    Flickable {
        id: scroll
        anchors.fill: parent
        anchors.margins: Theme.size(12)
        contentWidth: width
        contentHeight: choices.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: choices
            width: scroll.width
            spacing: Theme.size(12)
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.cardName.length > 0
                      ? qsTr("Choose an action for %1").arg(root.cardName)
                      : qsTr("Choose an action")
                color: Theme.text
                font.pixelSize: Theme.fontSize(15)
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }
            Repeater {
                model: root.actions
                delegate: AppButton {
                    required property var modelData
                    objectName: "rulesCardAction-" + modelData.responseId
                    Layout.fillWidth: true
                    text: root.tableController.promptOptionLabel(
                              "chooseAction", modelData.responseId, modelData.label)
                    onClicked: root.submit(modelData.responseId)
                }
            }
            AppButton {
                Layout.alignment: Qt.AlignRight
                compact: true
                variant: "ghost"
                text: qsTr("Cancel")
                onClicked: root.close()
            }
        }
    }
}
