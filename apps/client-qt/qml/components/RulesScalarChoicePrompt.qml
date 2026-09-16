// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    required property var wsModel
    required property var choiceModel
    required property int promptId
    property string promptKind: ""
    property string promptTitle: ""
    property string promptDetail: ""
    required property int minimumTotal
    required property int maximumTotal
    property var selectedIds: []
    property int selectedTotal: 0
    readonly property bool directChoice: minimumTotal === 1 && maximumTotal === 1
    readonly property bool validSelection: selectedTotal >= minimumTotal
                                                   && selectedTotal <= maximumTotal

    readonly property bool narrowLayout: width < Theme.size(490)

    property real candidateHeight: Theme.size(38)
    implicitHeight: candidateHeight + (directChoice ? 0 : Theme.size(46))

    // ListView estimates variable row heights during layout. Measure after that
    // pass so a prompt switch cannot feed the estimate into its parent layout.
    Timer {
        id: measureChoices
        interval: 0
        onTriggered: root.candidateHeight = Math.max(Theme.size(38),
                            Math.min(choiceList.contentHeight, Theme.size(280)))
    }

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
        default: return RulesText.choice(promptKind, label, promptTitle, promptDetail)
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

    onPromptIdChanged: {
        resetSelection()
        choiceList.positionViewAtBeginning()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.size(8)

        ListView {
            id: choiceList
            objectName: "rulesScalarCandidates"

            readonly property real itemHeight: Theme.size(38)
            implicitHeight: root.candidateHeight
            onContentHeightChanged: measureChoices.restart()
            onWidthChanged: measureChoices.restart()
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            Layout.minimumHeight: itemHeight
            clip: true
            spacing: Theme.size(8)
            model: root.choiceModel
            currentIndex: -1
            activeFocusOnTab: true
            boundsBehavior: Flickable.StopAtBounds

            function reveal(index) {
                positionViewAtIndex(index, ListView.Contain)
            }
            Keys.onPressed: event => {
                switch (event.key) {
                case Qt.Key_Home: positionViewAtBeginning(); event.accepted = true; break
                case Qt.Key_End: positionViewAtEnd(); event.accepted = true; break
                case Qt.Key_Up: contentY = Math.max(originY, contentY - itemHeight); event.accepted = true; break
                case Qt.Key_Down:
                    contentY = Math.min(Math.max(originY, originY + contentHeight - height), contentY + itemHeight)
                    event.accepted = true
                    break
                }
            }
            ScrollBar.vertical: ScrollBar {
                id: choiceScrollBar
                objectName: "rulesScalarCandidatesScrollBar"
                policy: choiceList.contentHeight > choiceList.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
            }

            delegate: ColumnLayout {
                id: choiceRow

                required property int index
                required property string responseId
                required property string label
                required property int weight
                required property bool canRepeat
                readonly property int count: root.selectionCount(responseId)

                width: choiceList.width - Theme.size(14)
                spacing: Theme.size(5)

                AppButton {
                    id: choiceButton
                    Layout.fillWidth: true
                    implicitWidth: Theme.size(88)
                    implicitHeight: Math.max(Theme.size(38), choiceText.implicitHeight + Theme.size(20))
                    compact: true
                    variant: choiceRow.count > 0 ? "highlight" : "secondary"
                    text: choiceRow.weight > 1
                          ? qsTr("%1 · weight %2")
                            .arg(root.choiceLabel(choiceRow.label)).arg(choiceRow.weight)
                          : root.choiceLabel(choiceRow.label)
                    enabled: root.directChoice
                             || root.selectedTotal + choiceRow.weight <= root.maximumTotal
                             || choiceRow.count > 0
                    objectName: "rulesScalarChoice-" + choiceRow.responseId
                    contentItem: Text {
                        id: choiceText
                        textFormat: Text.PlainText
                        text: choiceButton.text
                        color: choiceButton.foregroundColor
                        font.pixelSize: Theme.fontSize(11)
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                        verticalAlignment: Text.AlignVCenter
                    }
                    onActiveFocusChanged: if (activeFocus) choiceList.reveal(choiceRow.index)
                    onClicked: root.choose(choiceRow.responseId, choiceRow.weight,
                                           choiceRow.canRepeat)
                }

                RowLayout {
                    visible: !root.directChoice && (choiceRow.count > 0 || choiceRow.canRepeat)
                    spacing: Theme.size(5)
                    AppButton {
                        Layout.preferredWidth: Theme.size(42)
                        compact: true
                        visible: choiceRow.count > 0
                        text: "−"
                        accessibleName: qsTr("Remove %1").arg(root.choiceLabel(choiceRow.label))
                        onActiveFocusChanged: if (activeFocus) choiceList.reveal(choiceRow.index)
                        onClicked: root.removeChoice(choiceRow.responseId, choiceRow.weight)
                    }
                    Text {
                        textFormat: Text.PlainText
                        visible: choiceRow.count > 0
                        text: "×" + choiceRow.count
                        color: Theme.primary
                        font.pixelSize: Theme.fontSize(11)
                        font.weight: Font.DemiBold
                    }
                    AppButton {
                        Layout.preferredWidth: Theme.size(42)
                        compact: true
                        visible: choiceRow.canRepeat
                        text: "+"
                        accessibleName: qsTr("Add %1").arg(root.choiceLabel(choiceRow.label))
                        enabled: root.selectedTotal + choiceRow.weight <= root.maximumTotal
                        onActiveFocusChanged: if (activeFocus) choiceList.reveal(choiceRow.index)
                        onClicked: root.addChoice(choiceRow.responseId, choiceRow.weight, true)
                    }
                }
            }
        }

        RowLayout {
            id: choiceControls

            Layout.fillWidth: true
            Layout.preferredHeight: Theme.size(38)
            visible: !root.directChoice
            spacing: Theme.size(8)

            Text {
                Layout.fillWidth: root.narrowLayout
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: root.minimumTotal === root.maximumTotal
                      ? qsTr("Total %1 of %2").arg(root.selectedTotal).arg(root.maximumTotal)
                      : qsTr("Total %1 · choose %2–%3")
                        .arg(root.selectedTotal).arg(root.minimumTotal).arg(root.maximumTotal)
                color: root.validSelection ? Theme.success : Theme.textSecondary
                font.pixelSize: Theme.fontSize(10)
            }

            AppButton {
                objectName: "rulesConfirmChoices"
                compact: true
                variant: "primary"
                text: qsTr("Confirm choices")
                enabled: root.validSelection
                disabledReason: qsTr("Choose a valid total")
                onClicked: root.submit()
            }
        }
    }
}
