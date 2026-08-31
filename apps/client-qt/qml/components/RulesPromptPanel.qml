// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Surface {
    id: root

    required property var tableController
    readonly property var rulesSession: tableController.rulesSession
    readonly property bool waitingForDecision:
        rulesSession.active
        && !rulesSession.promptPending
        && !rulesSession.gameOver

    objectName: "rulesPromptPanel"
    implicitHeight: promptContent.implicitHeight + Theme.size(22)
    visible: rulesSession.promptPending
             || rulesSession.gameOver
             || waitingForDecision
    color: Theme.surfaceElevated
    border.color: rulesSession.promptPending ? Theme.primary : Theme.borderStrong

    ColumnLayout {
        id: promptContent
        anchors.fill: parent
        anchors.margins: Theme.size(11)
        spacing: Theme.size(7)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(10)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(2)

                Text {
                    textFormat: Text.PlainText
                    objectName: "rulesPromptTitle"
                    Layout.fillWidth: true
                    text: rulesSession.gameOver
                          ? (rulesSession.hasWinner
                             ? qsTr("Seat %1 wins the Forge game")
                               .arg(rulesSession.winnerSeat + 1)
                             : qsTr("The Forge game ended in a draw"))
                          : root.waitingForDecision
                            ? qsTr("Waiting for another player")
                          : root.tableController.promptTitle(
                                rulesSession.promptKind,
                                rulesSession.promptTitle)
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(12)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    textFormat: Text.PlainText
                    objectName: "rulesPromptDetail"
                    Layout.fillWidth: true
                    visible: !rulesSession.gameOver
                             && (rulesSession.promptPending
                                 || root.waitingForDecision)
                    text: root.waitingForDecision
                          ? qsTr("Forge is waiting for another player to respond.")
                          : rulesSession.promptSupported
                          ? root.tableController.promptDetail(
                                rulesSession.promptKind,
                                rulesSession.promptDetail)
                          : qsTr("This Forge decision is not supported by this Hexproof build: %1")
                            .arg(rulesSession.promptKind)
                    color: root.waitingForDecision
                           || rulesSession.promptSupported
                           ? Theme.textSecondary : Theme.warning
                    font.pixelSize: Theme.fontSize(9)
                    elide: Text.ElideRight
                }
            }

            ListView {
                objectName: "rulesPromptOptions"
                Layout.preferredWidth: Math.min(contentWidth, Theme.size(560))
                Layout.preferredHeight: Theme.size(38)
                orientation: ListView.Horizontal
                spacing: Theme.size(7)
                clip: true
                model: rulesSession.promptOptions
                visible: rulesSession.promptPending
                         && rulesSession.promptSupported
                         && rulesSession.promptKind !== "mulliganPutBack"
                         && rulesSession.promptKind !== "chooseCards"
                         && rulesSession.promptKind !== "revealCards"
                         && rulesSession.promptKind !== "reorder"
                         && rulesSession.promptKind !== "scry"
                         && rulesSession.promptKind !== "chooseBoardTargets"
                         && rulesSession.promptKind !== "chooseAttackers"
                         && rulesSession.promptKind !== "chooseBlockers"
                         && rulesSession.promptKind !== "chooseDamageAssignmentOrder"
                         && rulesSession.promptKind !== "chooseCombatDamageAssignment"
                         && rulesSession.promptKind !== "chooseBoolean"
                         && rulesSession.promptKind !== "chooseNumber"
                         && rulesSession.promptKind !== "chooseColor"
                         && rulesSession.promptKind !== "chooseFromSelection"

                delegate: AppButton {
                    required property string responseId
                    required property string label

                    objectName: "rulesPromptOption-" + responseId
                    compact: true
                    text: root.tableController.promptOptionLabel(
                              rulesSession.promptKind, responseId, label)
                    onClicked: root.tableController.wsModel.respondRulesPrompt(
                                   rulesSession.promptId, responseId)
                }
            }
        }

        RulesPromptContext {
            Layout.fillWidth: true
            cardCatalogModel: root.tableController.cardCatalogModel
            sourceCardModel: rulesSession.promptContextCards
            targetModel: rulesSession.promptContextTargets
            contextText: rulesSession.promptContextText
        }

        RulesCardSelectionPrompt {
            Layout.fillWidth: true
            visible: rulesSession.promptPending
                     && rulesSession.promptSupported
                     && (rulesSession.promptKind === "mulliganPutBack"
                         || rulesSession.promptKind === "chooseCards")
            wsModel: root.tableController.wsModel
            cardCatalogModel: root.tableController.cardCatalogModel
            cardModel: rulesSession.promptCards
            promptId: rulesSession.promptId
            minimumSelections: rulesSession.promptMinCardSelections
            maximumSelections: rulesSession.promptMaxCardSelections
            confirmationText: rulesSession.promptKind === "mulliganPutBack"
                              ? qsTr("Put on library bottom")
                              : qsTr("Confirm cards")
        }

        RulesRevealPrompt {
            Layout.fillWidth: true
            visible: rulesSession.promptPending
                     && rulesSession.promptSupported
                     && rulesSession.promptKind === "revealCards"
            wsModel: root.tableController.wsModel
            cardCatalogModel: root.tableController.cardCatalogModel
            cardModel: rulesSession.promptCards
            promptId: rulesSession.promptId
        }

        RulesOrderPrompt {
            Layout.fillWidth: true
            visible: rulesSession.promptPending
                     && rulesSession.promptSupported
                     && rulesSession.promptKind === "reorder"
            wsModel: root.tableController.wsModel
            cardCatalogModel: root.tableController.cardCatalogModel
            orderModel: rulesSession.promptOrderItems
            promptId: rulesSession.promptId
        }

        RulesScryPrompt {
            Layout.fillWidth: true
            visible: rulesSession.promptPending
                     && rulesSession.promptSupported
                     && rulesSession.promptKind === "scry"
            wsModel: root.tableController.wsModel
            cardCatalogModel: root.tableController.cardCatalogModel
            cardModel: rulesSession.promptCards
            destinations: rulesSession.promptScryDestinations
            promptId: rulesSession.promptId
        }

        RulesOrderPrompt {
            Layout.fillWidth: true
            visible: rulesSession.promptPending
                     && rulesSession.promptSupported
                     && rulesSession.promptKind === "chooseDamageAssignmentOrder"
            wsModel: root.tableController.wsModel
            cardCatalogModel: root.tableController.cardCatalogModel
            orderModel: rulesSession.promptDamageTargets
            promptId: rulesSession.promptId
            damageOrder: true
        }

        RulesDamageAssignmentPrompt {
            Layout.fillWidth: true
            visible: rulesSession.promptPending
                     && rulesSession.promptSupported
                     && rulesSession.promptKind === "chooseCombatDamageAssignment"
            wsModel: root.tableController.wsModel
            cardCatalogModel: root.tableController.cardCatalogModel
            targetModel: rulesSession.promptDamageTargets
            damageSource: rulesSession.promptDamageSource
            promptId: rulesSession.promptId
            totalDamage: rulesSession.promptTotalDamage
            deathtouch: rulesSession.promptDamageDeathtouch
        }

        RulesTargetSelectionPrompt {
            Layout.fillWidth: true
            visible: rulesSession.promptPending
                     && rulesSession.promptSupported
                     && rulesSession.promptKind === "chooseBoardTargets"
            wsModel: root.tableController.wsModel
            cardCatalogModel: root.tableController.cardCatalogModel
            targetModel: rulesSession.promptTargets
            promptId: rulesSession.promptId
            minimumSelections: rulesSession.promptMinSelections
            maximumSelections: rulesSession.promptMaxSelections
            cancellable: rulesSession.promptCancellable
        }

        RulesCombatAssignmentPrompt {
            Layout.fillWidth: true
            visible: rulesSession.promptPending
                     && rulesSession.promptSupported
                     && rulesSession.promptKind === "chooseAttackers"
            wsModel: root.tableController.wsModel
            cardCatalogModel: root.tableController.cardCatalogModel
            sourceModel: rulesSession.promptCombat
            promptId: rulesSession.promptId
            assignmentKind: "attackers"
        }

        RulesCombatAssignmentPrompt {
            Layout.fillWidth: true
            visible: rulesSession.promptPending
                     && rulesSession.promptSupported
                     && rulesSession.promptKind === "chooseBlockers"
            wsModel: root.tableController.wsModel
            cardCatalogModel: root.tableController.cardCatalogModel
            sourceModel: rulesSession.promptCombat
            promptId: rulesSession.promptId
            assignmentKind: "blockers"
        }

        RulesScalarChoicePrompt {
            Layout.fillWidth: true
            visible: rulesSession.promptPending
                     && rulesSession.promptSupported
                     && (rulesSession.promptKind === "chooseBoolean"
                         || rulesSession.promptKind === "chooseColor"
                         || rulesSession.promptKind === "chooseFromSelection")
            wsModel: root.tableController.wsModel
            choiceModel: rulesSession.promptChoices
            promptId: rulesSession.promptId
            minimumTotal: rulesSession.promptMinChoiceTotal
            maximumTotal: rulesSession.promptMaxChoiceTotal
        }

        RulesNumberPrompt {
            Layout.fillWidth: true
            visible: rulesSession.promptPending
                     && rulesSession.promptSupported
                     && rulesSession.promptKind === "chooseNumber"
            wsModel: root.tableController.wsModel
            promptId: rulesSession.promptId
            minimum: rulesSession.promptMinNumber
            maximum: rulesSession.promptMaxNumber
        }
    }
}
