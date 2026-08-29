// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property var wsModel
    required property var choiceModel
    required property int promptId
    required property int minimumTotal
    required property int maximumTotal
    property var selectedIds: []
    property int selectedTotal: 0
    readonly property bool directChoice: minimumTotal === 1 && maximumTotal === 1
    readonly property bool validSelection: selectedTotal >= minimumTotal
                                                   && selectedTotal <= maximumTotal

    implicitHeight: Theme.size(48)

    function resetSelection() {
        selectedIds = []
        selectedTotal = 0
    }

    function choiceLabel(label) {
        switch (label) {
        case "White": return qsTr("White")
        case "Blue": return qsTr("Blue")
        case "Black": return qsTr("Black")
        case "Red": return qsTr("Red")
        case "Green": return qsTr("Green")
        case "Yes": return qsTr("Yes")
        case "No": return qsTr("No")
        default: return label
        }
    }

    function selectionCount(responseId) {
        return selectedIds.filter(value => value === responseId).length
    }

    function addChoice(responseId, weight, canRepeat) {
        if ((!canRepeat && selectionCount(responseId) > 0)
                || selectedTotal + weight > maximumTotal)
            return
        selectedIds = selectedIds.concat([responseId])
        selectedTotal += weight
    }

    function removeChoice(responseId, weight) {
        const index = selectedIds.lastIndexOf(responseId)
        if (index < 0)
            return
        const next = selectedIds.slice()
        next.splice(index, 1)
        selectedIds = next
        selectedTotal -= weight
    }

    function choose(responseId, weight, canRepeat) {
        if (directChoice && weight === 1) {
            wsModel.respondRulesPromptWithChoices(promptId, [responseId])
            return
        }
        addChoice(responseId, weight, canRepeat)
    }

    function submit() {
        if (validSelection)
            wsModel.respondRulesPromptWithChoices(promptId, selectedIds)
    }

    onPromptIdChanged: resetSelection()

    RowLayout {
        anchors.fill: parent
        spacing: Theme.size(10)

        ListView {
            id: choiceList

            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: ListView.Horizontal
            spacing: Theme.size(8)
            clip: true
            model: root.choiceModel

            delegate: RowLayout {
                id: choiceRow

                required property string responseId
                required property string label
                required property int weight
                required property bool canRepeat
                readonly property int count: root.selectionCount(responseId)

                width: implicitWidth
                height: choiceList.height
                spacing: Theme.size(5)

                AppButton {
                    compact: true
                    variant: choiceRow.count > 0 ? "highlight" : "secondary"
                    text: choiceRow.weight > 1
                          ? qsTr("%1 · weight %2")
                            .arg(root.choiceLabel(choiceRow.label)).arg(choiceRow.weight)
                          : root.choiceLabel(choiceRow.label)
                    enabled: root.directChoice
                             || root.selectedTotal + choiceRow.weight <= root.maximumTotal
                             || choiceRow.count > 0
                    onClicked: root.choose(choiceRow.responseId, choiceRow.weight,
                                           choiceRow.canRepeat)
                }

                AppButton {
                    Layout.preferredWidth: Theme.size(42)
                    compact: true
                    visible: !root.directChoice && choiceRow.count > 0
                    text: "−"
                    accessibleName: qsTr("Remove %1").arg(root.choiceLabel(choiceRow.label))
                    onClicked: root.removeChoice(choiceRow.responseId, choiceRow.weight)
                }

                Text {
                    textFormat: Text.PlainText
                    visible: !root.directChoice && choiceRow.count > 0
                    text: "×" + choiceRow.count
                    color: Theme.primary
                    font.pixelSize: Theme.fontSize(11)
                    font.weight: Font.DemiBold
                }

                AppButton {
                    Layout.preferredWidth: Theme.size(42)
                    compact: true
                    visible: !root.directChoice && choiceRow.canRepeat
                    text: "+"
                    accessibleName: qsTr("Add %1").arg(root.choiceLabel(choiceRow.label))
                    enabled: root.selectedTotal + choiceRow.weight <= root.maximumTotal
                    onClicked: root.addChoice(choiceRow.responseId, choiceRow.weight, true)
                }
            }
        }

        Text {
            textFormat: Text.PlainText
            visible: !root.directChoice
            text: root.minimumTotal === root.maximumTotal
                  ? qsTr("Total %1 of %2").arg(root.selectedTotal).arg(root.maximumTotal)
                  : qsTr("Total %1 · choose %2–%3")
                    .arg(root.selectedTotal).arg(root.minimumTotal).arg(root.maximumTotal)
            color: root.validSelection ? Theme.success : Theme.textSecondary
            font.pixelSize: Theme.fontSize(10)
        }

        AppButton {
            compact: true
            variant: "primary"
            visible: !root.directChoice
            text: qsTr("Confirm choices")
            enabled: root.validSelection
            disabledReason: qsTr("Choose a valid total")
            onClicked: root.submit()
        }
    }
}
