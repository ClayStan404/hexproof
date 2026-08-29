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
    required property var sourceModel
    required property int promptId
    required property string assignmentKind
    property var assignments: ({})
    readonly property int assignedCount: Object.keys(assignments).length
    readonly property bool validSelection: sourceModel
                                                   && sourceModel.validAssignments(assignments)

    implicitHeight: Theme.size(150)

    function resetAssignments() {
        assignments = ({})
    }

    function choiceOptions(validTargets) {
        const result = [{"responseId": "",
                         "label": assignmentKind === "attackers"
                                  ? qsTr("Do not attack") : qsTr("Do not block")}]
        for (const target of validTargets) {
            const choice = Object.assign({}, target)
            if (assignmentKind === "blockers" && target.mustReceiveIfAble) {
                choice.label = qsTr("%1 · must be blocked if able").arg(target.label)
            }
            result.push(choice)
        }
        return result
    }

    function choiceIndex(sourceId, choices) {
        const selected = assignments[sourceId] || ""
        for (let index = 0; index < choices.length; ++index) {
            if (choices[index].responseId === selected)
                return index
        }
        return -1
    }

    function setAssignment(sourceId, targetId) {
        const next = Object.assign({}, assignments)
        if (!targetId)
            delete next[sourceId]
        else
            next[sourceId] = targetId
        assignments = next
    }

    function submitAssignments() {
        if (!validSelection)
            return
        const result = []
        for (const sourceId of Object.keys(assignments)) {
            result.push({"sourceId": sourceId,
                         "targetId": assignments[sourceId]})
        }
        wsModel.respondRulesPromptWithAssignments(promptId, result)
    }

    onPromptIdChanged: resetAssignments()

    RowLayout {
        anchors.fill: parent
        spacing: Theme.size(12)

        ListView {
            id: combatList

            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: ListView.Horizontal
            spacing: Theme.size(8)
            clip: true
            model: root.sourceModel

            delegate: Rectangle {
                id: combatTile

                required property string responseId
                required property string label
                required property string name
                required property string setCode
                required property string collectorNumber
                required property bool token
                required property var validTargets
                required property bool mustAssignIfAble
                readonly property var choiceModel: root.choiceOptions(validTargets)

                width: Theme.size(228)
                height: combatList.height
                radius: Theme.radiusSmall
                color: Theme.surfaceMuted
                border.width: mustAssignIfAble ? 2 : 1
                border.color: mustAssignIfAble ? Theme.warning : Theme.border

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.size(6)
                    spacing: Theme.size(7)

                    Rectangle {
                        Layout.preferredWidth: Theme.size(82)
                        Layout.fillHeight: true
                        radius: Theme.radiusSmall
                        color: Theme.surface
                        clip: true

                        Image {
                            id: art

                            anchors.fill: parent
                            anchors.margins: Theme.size(2)
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            source: {
                                if (!root.cardCatalogModel || !combatTile.name
                                        || typeof root.cardCatalogModel.tableImageSource
                                        !== "function") {
                                    return ""
                                }
                                void root.cardCatalogModel.imageRevision
                                return root.cardCatalogModel.tableImageSource(
                                            combatTile.name, combatTile.setCode,
                                            combatTile.collectorNumber)
                            }
                        }

                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            width: parent.width - Theme.size(8)
                            visible: art.status !== Image.Ready
                            text: combatTile.label
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSize(9)
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.size(5)

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: combatTile.label
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(10)
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            visible: combatTile.mustAssignIfAble
                            text: root.assignmentKind === "attackers"
                                  ? qsTr("Must attack if able") : ""
                            color: Theme.warning
                            font.pixelSize: Theme.fontSize(9)
                        }

                        ComboBox {
                            id: assignmentBox

                            Layout.fillWidth: true
                            model: combatTile.choiceModel
                            textRole: "label"
                            valueRole: "responseId"
                            currentIndex: root.choiceIndex(combatTile.responseId,
                                                           combatTile.choiceModel)
                            displayText: currentIndex >= 0 ? currentText
                                                          : qsTr("Choose target")
                            enabled: combatTile.choiceModel.length > 0
                            onActivated: root.setAssignment(combatTile.responseId,
                                                            currentValue)
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.preferredWidth: Theme.size(184)
            spacing: Theme.size(8)

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.assignmentKind === "attackers"
                      ? qsTr("%1 attacker(s) assigned").arg(root.assignedCount)
                      : qsTr("%1 blocker(s) assigned").arg(root.assignedCount)
                color: root.validSelection ? Theme.success : Theme.textSecondary
                font.pixelSize: Theme.fontSize(11)
                horizontalAlignment: Text.AlignHCenter
            }

            AppButton {
                Layout.fillWidth: true
                compact: true
                variant: "primary"
                text: root.assignmentKind === "attackers"
                      ? qsTr("Declare attackers") : qsTr("Declare blockers")
                enabled: root.validSelection
                disabledReason: qsTr("Resolve invalid combat assignments")
                onClicked: root.submitAssignments()
            }
        }
    }
}
