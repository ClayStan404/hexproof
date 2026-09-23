// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic

Column {
    id: root
    property var stops: ({})
    property string currentStep: ""
    property bool editable: true
    property bool compact: false
    signal stopToggled(string step, bool ownTurn)
    readonly property var phaseSteps: [
        "untap", "upkeep", "draw", "main1", "begin_combat",
        "declare_attackers", "declare_blockers", "combat_damage",
        "end_combat", "main2", "end", "cleanup"
    ]

    function stepLabel(step) {
        switch (step) {
        case "untap": return qsTranslate("RulesTable", "Untap")
        case "upkeep": return qsTranslate("RulesTable", "Upkeep")
        case "draw": return qsTranslate("RulesTable", "Draw")
        case "main1": return qsTranslate("RulesTable", "First main phase")
        case "begin_combat": return qsTranslate("RulesTable", "Beginning of combat")
        case "declare_attackers": return qsTranslate("RulesTable", "Declare attackers")
        case "declare_blockers": return qsTranslate("RulesTable", "Declare blockers")
        case "combat_damage": return qsTranslate("RulesTable", "Combat damage")
        case "end_combat": return qsTranslate("RulesTable", "End of combat")
        case "main2": return qsTranslate("RulesTable", "Second main phase")
        case "end": return qsTranslate("RulesTable", "End step")
        case "cleanup": return qsTranslate("RulesTable", "Cleanup")
        default: return step.length > 0 ? step : qsTranslate("RulesTable", "Waiting for Forge")
        }
    }

    width: parent ? parent.width : implicitWidth
    spacing: Theme.size(3)

    Row {
        width: parent.width
        height: Theme.size(22)
        Text {
            width: parent.width - Theme.size(root.compact ? 56 : 144)
            textFormat: Text.PlainText
            text: qsTr("Stops")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(root.compact ? 9 : 13)
        }
        Repeater {
            model: [qsTr("You"), qsTr("Others")]
            delegate: Text {
                required property string modelData
                width: Theme.size(root.compact ? 28 : 72)
                textFormat: Text.PlainText
                text: modelData
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(root.compact ? 8 : 12)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }
    }

    Repeater {
        model: root.phaseSteps

        delegate: Rectangle {
            id: phaseItem
            required property string modelData
            required property int index

            objectName: "rulesPhaseItem" + index
            width: parent ? parent.width : 0
            height: Theme.size(root.compact ? 30 : 34)
            radius: Theme.radiusSmall
            color: root.currentStep
                   === modelData ? Theme.primaryMuted : "transparent"
            border.width: root.currentStep
                          === modelData ? 1 : 0
            border.color: Theme.primary

            Text {
                textFormat: Text.PlainText
                anchors.fill: parent
                anchors.leftMargin: Theme.size(4)
                anchors.rightMargin: Theme.size(root.compact ? 56 : 144)
                text: root.stepLabel(
                          phaseItem.modelData)
                color: root.currentStep
                       === phaseItem.modelData
                       ? Theme.primary : Theme.textSecondary
                font.pixelSize: Theme.fontSize(root.compact ? 9 : 13)
                font.weight: root.currentStep
                             === phaseItem.modelData
                             ? Font.DemiBold : Font.Normal
                horizontalAlignment: root.compact ? Text.AlignHCenter : Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            Row {
                anchors.right: parent.right
                height: parent.height
                Repeater {
                    model: [true, false]
                    delegate: Rectangle {
                        id: stopControl
                        required property bool modelData
                        readonly property bool selected: root.stops[(modelData ? "own:" : "other:") + phaseItem.modelData] === true
                        readonly property bool available: root.editable && phaseItem.modelData !== "untap"
                        objectName: "rulesPhaseStop-" + (modelData ? "own-" : "other-")
                            + phaseItem.modelData
                        width: Theme.size(root.compact ? 28 : 72)
                        height: parent.height
                        color: selected ? Theme.primaryMuted : "transparent"
                        radius: Theme.radiusSmall
                        border.width: activeFocus ? 1 : 0
                        border.color: Theme.primary
                        activeFocusOnTab: available
                        Accessible.role: Accessible.CheckBox
                        Accessible.checkable: true
                        Accessible.checked: selected
                        Accessible.name: modelData
                            ? qsTr("Stop at %1 on your turns").arg(root.stepLabel(phaseItem.modelData))
                            : qsTr("Stop at %1 on other players' turns").arg(root.stepLabel(phaseItem.modelData))
                        function toggle() {
                            if (available)
                                root.stopToggled(phaseItem.modelData, modelData)
                        }
                        Accessible.onToggleAction: toggle()
                        Keys.onSpacePressed: toggle()
                        Keys.onReturnPressed: toggle()
                        Rectangle {
                            anchors.centerIn: parent
                            width: Theme.size(10)
                            height: width
                            radius: width / 2
                            color: stopControl.selected ? Theme.primary : "transparent"
                            border.width: 1
                            border.color: stopControl.selected ? Theme.primary : Theme.textMuted
                            opacity: stopControl.available ? 1 : 0.25
                        }
                        TapHandler {
                            enabled: stopControl.available
                            onTapped: stopControl.toggle()
                        }
                        HoverHandler { id: stopHover }
                        ToolTip.visible: stopHover.hovered
                        ToolTip.text: stopControl.Accessible.name
                        ToolTip.delay: 350
                    }
                }
            }
        }
    }
}
