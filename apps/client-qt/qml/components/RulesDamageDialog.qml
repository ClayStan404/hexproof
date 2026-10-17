// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

RulesDecisionDialog {
    id: root
    requested: tableController.interaction.contextActive
        && session.promptKind === "chooseCombatDamageAssignment"

    objectName: "rulesDamageDialog"
    width: Math.min(Theme.size(1080), parent ? parent.width - Theme.size(40) : 0)
    height: Math.min(Theme.size(320), parent ? parent.height - Theme.size(40) : 0)
    x: parent ? (parent.width - width) / 2 : 0
    y: parent ? (parent.height - height) / 2 : 0
    padding: Theme.size(18)
    background: Surface { color: Theme.surfaceElevated; border.color: Theme.primary }

    contentItem: ColumnLayout {
        spacing: Theme.size(12)
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(12)
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.tableController.promptTitle(root.session.promptKind, root.session.promptTitle)
                color: Theme.text
                font.pixelSize: Theme.fontSize(20)
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            AppButton {
                objectName: "rulesDamageViewBattlefield"
                text: qsTranslate("RulesDecisionDialog", "View battlefield")
                enabled: !root.tableController.rulesResponsePending
                onClicked: root.inspectBattlefield()
            }
        }
        Text {
            objectName: "rulesDamageSourceName"
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.session.promptDamageSource.label || root.session.promptDamageSource.name || ""
            visible: text.length > 0
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(14)
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        Loader {
            objectName: "rulesDamageContent"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            active: root.requested
            enabled: !root.tableController.rulesResponsePending
            sourceComponent: Component {
                RulesDamageAssignmentPrompt {
                    expandedView: true
                    wsModel: root.tableController.wsModel
                    cardCatalogModel: root.tableController.cardCatalogModel
                    targetModel: root.session.promptDamageTargets
                    damageSource: root.session.promptDamageSource
                    promptId: root.session.promptId
                    totalDamage: root.session.promptTotalDamage
                    deathtouch: root.session.promptDamageDeathtouch
                    assignmentMode: root.session.promptDamageAssignmentMode
                }
            }
        }
    }
}
