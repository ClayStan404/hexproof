// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
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

    Flickable {
        id: promptScroll
        objectName: "rulesPromptScroll"
        anchors.fill: parent
        anchors.margins: Theme.size(11)
        contentWidth: width
        contentHeight: promptContent.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    }

    Connections {
        target: root.rulesSession
        function onPromptChanged() { promptScroll.contentY = 0 }
    }

    ColumnLayout {
        id: promptContent
        parent: promptScroll.contentItem
        width: promptScroll.width
        spacing: Theme.size(7)

        RowLayout {
            visible: root.tableController.rulesResponsePending
            BusyIndicator {
                Layout.preferredWidth: Theme.size(18)
                Layout.preferredHeight: Theme.size(18)
                running: parent.visible
            }
            Text {
                text: root.tableController.stepLabel("")
                textFormat: Text.PlainText
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(9)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.size(10)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(2)

                Text {
                    id: promptTitle
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
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight

                    HoverHandler { id: titleHover }
                    ToolTip {
                        visible: titleHover.hovered && promptTitle.truncated
                        contentItem: Text {
                            text: promptTitle.text
                            textFormat: Text.PlainText
                            color: Theme.text
                            wrapMode: Text.Wrap
                        }
                        width: Math.min(root.width, Theme.size(560))
                    }
                }

                Text {
                    id: promptDetail
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
                    wrapMode: Text.WordWrap
                    maximumLineCount: 4
                    elide: Text.ElideRight

                    HoverHandler { id: detailHover }
                    ToolTip {
                        visible: detailHover.hovered && promptDetail.truncated
                        contentItem: Text {
                            text: promptDetail.text
                            textFormat: Text.PlainText
                            color: Theme.text
                            wrapMode: Text.Wrap
                        }
                        width: Math.min(root.width, Theme.size(560))
                    }
                }
            }

            ListView {
                id: actionOptions
                objectName: "rulesPromptOptions"
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.size(38)
                                        + (contentWidth > width ? Theme.size(14) : 0)
                orientation: ListView.Horizontal
                spacing: Theme.size(7)
                clip: true
                model: rulesSession.promptOptions
                enabled: !root.tableController.rulesResponsePending
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
                    required property int index
                    required property string responseId
                    required property string label

                    objectName: "rulesPromptOption-" + responseId
                    compact: true
                    onActiveFocusChanged: {
                        if (activeFocus)
                            actionOptions.positionViewAtIndex(index, ListView.Contain)
                    }
                    text: root.tableController.promptOptionLabel(
                              rulesSession.promptKind, responseId, label)
                    onClicked: root.tableController.wsModel.respondRulesPrompt(
                                   rulesSession.promptId, responseId)
                }

                ScrollBar.horizontal: ScrollBar {
                    id: actionScrollBar
                    objectName: "rulesPromptOptionsScrollBar"
                    policy: actionOptions.contentWidth > actionOptions.width
                            ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                    active: true
                }

                WheelHandler {
                    onWheel: event => {
                        const delta = event.angleDelta.x || event.angleDelta.y
                        actionOptions.contentX = Math.max(0, Math.min(
                            actionOptions.contentWidth - actionOptions.width,
                            actionOptions.contentX - delta))
                        event.accepted = true
                    }
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
            enabled: !root.tableController.rulesResponsePending
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
            enabled: !root.tableController.rulesResponsePending
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
            enabled: !root.tableController.rulesResponsePending
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
            enabled: !root.tableController.rulesResponsePending
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
            enabled: !root.tableController.rulesResponsePending
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
            enabled: !root.tableController.rulesResponsePending
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
            enabled: !root.tableController.rulesResponsePending
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
            enabled: !root.tableController.rulesResponsePending
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
            enabled: !root.tableController.rulesResponsePending
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
            enabled: !root.tableController.rulesResponsePending
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
            enabled: !root.tableController.rulesResponsePending
            wsModel: root.tableController.wsModel
            promptId: rulesSession.promptId
            minimum: rulesSession.promptMinNumber
            maximum: rulesSession.promptMaxNumber
        }
    }
}
