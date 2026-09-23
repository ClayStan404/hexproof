// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Surface {
    id: root

    required property var tableController
    property bool externalCardChoices: false
    property bool externalDamageChoices: false
    readonly property var rulesSession: tableController.rulesSession
    readonly property var interaction: tableController.interaction || null
    readonly property bool waitingForDecision:
        rulesSession.active
        && !rulesSession.promptPending
        && !rulesSession.gameOver

    readonly property bool showsActionOptions:
        rulesSession.promptPending
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
        && rulesSession.promptKind !== "chooseCardName"
        && rulesSession.promptKind !== "chooseColor"
        && rulesSession.promptKind !== "chooseFromSelection"

    function isFixedAction(responseId) {
        return responseId.startsWith("$")
    }

    objectName: "rulesPromptPanel"
    implicitHeight: promptContent.implicitHeight + Theme.size(22)
                    + (fixedActions.visible ? fixedActions.height + Theme.size(7) : 0)
    visible: rulesSession.promptPending
             || rulesSession.gameOver
             || waitingForDecision
    color: "transparent"
    radius: 0
    border.width: 0
    border.color: "transparent"

    Flow {
        id: fixedActions
        objectName: "rulesFixedPromptActions"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.size(11)
        spacing: Theme.size(7)
        visible: root.showsActionOptions && implicitHeight > 0
        enabled: !root.tableController.rulesResponsePending
        z: 1

        Repeater {
            model: root.rulesSession.promptOptions
            delegate: AppButton {
                required property string responseId
                required property string label
                objectName: root.isFixedAction(responseId)
                            ? "rulesPromptOption-" + responseId : ""
                visible: root.isFixedAction(responseId)
                compact: true
                text: root.tableController.promptOptionLabel(
                          root.rulesSession.promptKind, responseId, label)
                onClicked: root.tableController.wsModel.respondRulesPrompt(
                               root.rulesSession.promptId, responseId)
            }
        }
    }

    Flickable {
        id: promptScroll
        objectName: "rulesPromptScroll"
        anchors.fill: parent
        anchors.margins: Theme.size(11)
        anchors.topMargin: Theme.size(11) + (fixedActions.visible
                           ? fixedActions.height + Theme.size(7) : 0)
        contentWidth: width
        contentHeight: promptContent.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    }

    Connections {
        target: root.rulesSession
        function onPromptChanged() {
            promptScroll.contentY = 0
            actionOptions.contentX = 0
        }
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
                        objectName: "rulesPromptTitleTooltip"
                        enabled: false
                        x: parent ? root.mapToItem(parent, 0, 0).x : 0
                        y: parent ? parent.height + Theme.size(6) : 0
                        background: Rectangle {
                            color: Theme.surfaceElevated
                            border.color: Theme.borderStrong
                            radius: Theme.radiusSmall
                        }
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
                    // Notices can contain a full advisory card list. Keep it
                    // scrollable in promptScroll instead of hiding later lines.
                    maximumLineCount: rulesSession.promptKind === "acknowledge" ? 2147483647 : 4
                    elide: Text.ElideRight

                    HoverHandler { id: detailHover }
                    ToolTip {
                        objectName: "rulesPromptDetailTooltip"
                        enabled: false
                        x: parent ? root.mapToItem(parent, 0, 0).x : 0
                        y: parent ? parent.height + Theme.size(6) : 0
                        background: Rectangle {
                            color: Theme.surfaceElevated
                            border.color: Theme.borderStrong
                            radius: Theme.radiusSmall
                        }
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
                Layout.preferredHeight: Theme.size(72)
                                        + (contentWidth > width ? Theme.size(14) : 0)
                orientation: ListView.Horizontal
                spacing: Theme.size(7)
                clip: true
                model: rulesSession.promptOptions
                enabled: !root.tableController.rulesResponsePending
                visible: root.showsActionOptions && contentWidth > spacing * count

                delegate: AppButton {
                    id: actionButton
                    required property var model
                    required property int index
                    required property string responseId
                    required property string label
                    readonly property bool onTable: root.interaction !== null
                        && root.interaction.actionOnTable(model.cardId || "", model.kind || "")

                    objectName: root.isFixedAction(responseId)
                                ? "" : "rulesPromptOption-" + responseId
                    visible: !root.isFixedAction(responseId) && !onTable
                    width: !root.isFixedAction(responseId) && !onTable
                           ? Math.min(Theme.size(260), actionOptions.width) : 0
                    height: Theme.size(72)
                    compact: true
                    contentItem: Text {
                        id: actionLabel
                        textFormat: Text.PlainText
                        text: actionButton.text
                        color: actionButton.foregroundColor
                        font.pixelSize: Theme.fontSize(11)
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                    }
                    ToolTip {
                        x: parent ? root.mapToItem(parent, 0, 0).x : 0
                        y: parent ? parent.height + Theme.size(6) : 0
                        enabled: false
                        background: Rectangle {
                            color: Theme.surfaceElevated
                            border.color: Theme.borderStrong
                            radius: Theme.radiusSmall
                        }
                        objectName: "rulesPromptActionTooltip-" + actionButton.responseId
                        visible: actionButton.hovered && actionLabel.truncated
                        delay: 500
                        width: Math.min(Theme.size(480), root.width)
                        contentItem: Text {
                            textFormat: Text.PlainText
                            text: actionButton.text
                            color: Theme.text
                            wrapMode: Text.Wrap
                        }
                    }
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

            Text {
                objectName: "rulesDirectActionHint"
                textFormat: Text.PlainText
                Layout.fillWidth: true
                visible: root.interaction !== null && root.showsActionOptions
                    && (rulesSession.promptKind === "chooseAction"
                        || rulesSession.promptKind === "payManaCost")
                text: rulesSession.promptKind === "payManaCost"
                    ? qsTr("Click highlighted mana sources to pay.")
                    : qsTr("Click a highlighted card to play it or use an ability. Right-click to inspect.")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(10)
                wrapMode: Text.WordWrap
            }
        }

        RulesPromptContext {
            Layout.fillWidth: true
            promptId: rulesSession.promptId
            previewBoundary: root
            contextEnabled: root.interaction === null || root.interaction.contextActive
            expandedCard: ["chooseBoolean", "chooseFromSelection", "chooseColor", "chooseNumber"].includes(rulesSession.promptKind)
            cardHeight: typeof root.tableController.height === "number"
                ? Math.min(Theme.size(280), Math.max(Theme.size(100), root.tableController.height - Theme.size(400)))
                : Theme.size(280)
            cardCatalogModel: root.tableController.cardCatalogModel
            sourceCardModel: rulesSession.promptContextCards
            targetModel: rulesSession.promptContextTargets
            contextText: rulesSession.promptContextText
        }

        RulesCardSelectionPrompt {
            Layout.fillWidth: true
            visible: !root.externalCardChoices && rulesSession.promptPending
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
            cancellable: rulesSession.promptKind === "chooseCards"
                         && rulesSession.promptCancellable
            confirmationText: rulesSession.promptKind === "mulliganPutBack"
                              ? qsTr("Put on library bottom")
                              : qsTr("Confirm cards")
        }

        RulesRevealPrompt {
            Layout.fillWidth: true
            visible: !root.externalCardChoices && rulesSession.promptPending
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
            visible: !root.externalCardChoices && rulesSession.promptPending
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
            visible: !root.externalCardChoices && rulesSession.promptPending
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
            visible: !root.externalCardChoices && rulesSession.promptPending
                     && rulesSession.promptSupported
                     && rulesSession.promptKind === "chooseDamageAssignmentOrder"
            enabled: !root.tableController.rulesResponsePending
            wsModel: root.tableController.wsModel
            cardCatalogModel: root.tableController.cardCatalogModel
            orderModel: visible ? rulesSession.promptDamageTargets : null
            promptId: rulesSession.promptId
            damageOrder: true
        }

        RulesDamageAssignmentPrompt {
            Layout.fillWidth: true
            visible: !root.externalDamageChoices && rulesSession.promptPending
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
            assignmentMode: rulesSession.promptDamageAssignmentMode === undefined
                            ? "ordered" : rulesSession.promptDamageAssignmentMode
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
            interaction: root.interaction
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
            selectionState: root.tableController.combatInteraction || null
            boardSelection: !!selectionState && root.tableController.roomSession.maxSeats <= 2
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
            selectionState: root.tableController.combatInteraction || null
            boardSelection: !!selectionState && root.tableController.roomSession.maxSeats <= 2
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
            promptKind: rulesSession.promptKind
            promptTitle: rulesSession.promptTitle
            promptDetail: rulesSession.promptDetail
            minimumTotal: rulesSession.promptMinChoiceTotal
            maximumTotal: rulesSession.promptMaxChoiceTotal
        }

        RulesCardNamePrompt {
            Layout.fillWidth: true
            visible: rulesSession.promptPending
                     && rulesSession.promptSupported
                     && rulesSession.promptKind === "chooseCardName"
            enabled: !root.tableController.rulesResponsePending
            wsModel: root.tableController.wsModel
            cardCatalogModel: root.tableController.cardCatalogModel
            promptId: rulesSession.promptId
            cancellable: rulesSession.promptCancellable
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
