// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    required property var wsModel
    required property var cardCatalogModel
    required property int promptId
    required property bool cancellable
    property string searchText: ""
    property var suggestions: []
    readonly property string chosenName: nameInput.text.trim()
    readonly property bool validName: chosenName.length > 0
                                      && Array.from(chosenName).length <= 256
                                      && !/[\u0000-\u001f\u007f-\u009f]/.test(chosenName)

    implicitHeight: content.implicitHeight

    function resetInput() {
        searchTimer.stop()
        searchText = ""
        suggestions = []
        nameInput.text = ""
    }

    function searchNames() {
        suggestions = []
        searchText = chosenName
        if (!visible || !enabled || !cardCatalogModel || !cardCatalogModel.installed
                || searchText.length === 0 || typeof cardCatalogModel.search !== "function")
            return
        cardCatalogModel.search(searchText)
    }

    function submitName() {
        if (enabled && validName)
            wsModel.respondRulesPromptWithName(promptId, chosenName)
    }

    onPromptIdChanged: resetInput()
    onVisibleChanged: {
        if (!visible) {
            searchTimer.stop()
            searchText = ""
            suggestions = []
        }
    }

    Timer {
        id: searchTimer
        interval: 180
        onTriggered: root.searchNames()
    }

    Connections {
        target: root.cardCatalogModel
        ignoreUnknownSignals: true

        function onSearchResultsChanged() {
            if (!root.visible || root.searchText.length === 0
                    || root.searchText !== root.chosenName)
                return
            const cards = root.cardCatalogModel.searchResults
            const names = []
            for (let index = 0; index < cards.length && names.length < 12; ++index) {
                if (cards[index].name)
                    names.push({name: cards[index].name,
                                displayName: cards[index].displayName || cards[index].name})
            }
            root.suggestions = names
        }
    }

    ColumnLayout {
        id: content
        width: parent.width
        spacing: Theme.size(7)

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Enter an English card name, or choose a suggestion.")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(10)
            wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(8)

            TextField {
                id: nameInput
                objectName: "rulesCardNameInput"
                Layout.fillWidth: true
                placeholderText: qsTr("English card name")
                maximumLength: 512
                selectByMouse: true
                onTextEdited: {
                    root.suggestions = []
                    searchTimer.restart()
                }
                onAccepted: root.submitName()
            }

            AppButton {
                objectName: "confirmCardNameButton"
                compact: true
                variant: "primary"
                text: qsTr("Confirm name")
                enabled: root.validName
                onClicked: root.submitName()
            }

            AppButton {
                objectName: "cancelCardNameButton"
                compact: true
                visible: root.cancellable
                text: qsTr("Cancel")
                onClicked: root.wsModel.respondRulesPrompt(root.promptId, "$cancel")
            }
        }

        ListView {
            id: nameList
            objectName: "rulesCardNameSuggestions"
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(4, count) * Theme.size(32)
            visible: count > 0
            clip: true
            model: root.suggestions
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: AppButton {
                required property var modelData
                width: nameList.width
                height: Theme.size(32)
                compact: true
                text: modelData.displayName === modelData.name ? modelData.name
                      : modelData.displayName + " · " + modelData.name
                onClicked: {
                    nameInput.text = modelData.name
                    root.searchText = ""
                    root.suggestions = []
                    searchTimer.stop()
                    nameInput.forceActiveFocus()
                }
            }
        }
    }
}
