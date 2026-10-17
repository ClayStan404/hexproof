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
    readonly property RulesTargetSelectionPrompt targetPrompt:
        promptFamily.familyItem as RulesTargetSelectionPrompt
    readonly property RulesCombatAssignmentPrompt combatPrompt:
        promptFamily.familyItem as RulesCombatAssignmentPrompt
    readonly property string targetInstruction: rulesSession.promptKind === "chooseBoardTargets"
        ? RulesText.targetInstruction(rulesSession.promptDetail) : ""
    // The board instructions and primary action already explain declaration.
    // Keep any specific engine error, rather than hiding arbitrary detail text.
    readonly property bool redundantCombatDetail: combatPrompt !== null && combatPrompt.boardSelection
        && ((rulesSession.promptKind === "chooseAttackers"
             && rulesSession.promptDetail === "Assign each attacking creature to a legal defender.")
            || (rulesSession.promptKind === "chooseBlockers"
                && rulesSession.promptDetail === "Assign each blocker to the attackers it can legally block."))
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

    // Read from the loaded family, so a replaced combat declaration cannot
    // leave the flag behind.
    readonly property bool combatListShown: {
        const combat = promptFamily.familyItem as RulesCombatAssignmentPrompt
        return combat !== null && combat.listShown
    }
    readonly property Component activeFamily: {
        if (!rulesSession.promptPending || !rulesSession.promptSupported)
            return null
        const kind = rulesSession.promptKind
        const cardsOutside = externalCardChoices
        const damageOutside = externalDamageChoices
        switch (kind) {
        case "mulliganPutBack":
        case "chooseCards":
            return cardsOutside ? null : cardSelectionFamily
        case "revealCards":
            return cardsOutside ? null : revealFamily
        case "reorder":
            return cardsOutside ? null : reorderFamily
        case "scry":
            return cardsOutside ? null : scryFamily
        case "chooseDamageAssignmentOrder":
            return cardsOutside ? null : damageOrderFamily
        case "chooseCombatDamageAssignment":
            return damageOutside ? null : damageAssignmentFamily
        case "chooseBoardTargets":
            return targetFamily
        case "chooseAttackers":
            return attackerFamily
        case "chooseBlockers":
            return blockerFamily
        case "chooseBoolean":
        case "chooseColor":
        case "chooseFromSelection":
            return scalarFamily
        case "chooseCardName":
            return cardNameFamily
        case "chooseNumber":
            return numberFamily
        default:
            return null
        }
    }

    function isFixedAction(responseId) {
        return responseId.startsWith("$")
    }

    objectName: "rulesPromptPanel"
    readonly property real controlsHeight: Theme.size(22)
        + (fixedActions.visible ? fixedActions.height + Theme.size(7) : 0)
        + (targetFooter.visible ? targetFooter.height + Theme.size(7) : 0)
        + (combatFooter.visible ? combatFooter.height + Theme.size(4) : 0)
    readonly property real minimumHeight: controlsHeight + Theme.size(48)
    implicitHeight: promptContent.implicitHeight + controlsHeight
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
            // Only fixed actions build a button; the other rows stay empty.
            delegate: Loader {
                id: fixedSlot
                required property string responseId
                required property string label
                required property string cardId
                active: root.isFixedAction(responseId)
                visible: active
                sourceComponent: AppButton {
                    objectName: "rulesPromptOption-" + fixedSlot.responseId
                    compact: true
                    text: root.tableController.promptOptionLabel(
                              root.rulesSession.promptKind, fixedSlot.responseId,
                              fixedSlot.label, fixedSlot.cardId)
                    onClicked: root.tableController.wsModel.respondRulesPrompt(
                                   root.rulesSession.promptId, fixedSlot.responseId)
                }
            }
        }
    }

    Loader {
        id: targetFooter
        objectName: "rulesTargetSelectionFooter"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.size(11)
        readonly property Item footerItem: item as Item
        height: footerItem ? footerItem.implicitHeight : 0
        visible: item !== null
        sourceComponent: root.targetPrompt ? root.targetPrompt.controlsComponent : null
        z: 1
    }

    Loader {
        id: combatFooter
        objectName: "rulesCombatSelectionFooter"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.size(11)
        readonly property Item footerItem: item as Item
        height: footerItem ? footerItem.implicitHeight : 0
        visible: item !== null
        sourceComponent: root.combatPrompt ? root.combatPrompt.controlsComponent : null
        z: 1
    }

    Flickable {
        id: promptScroll
        objectName: "rulesPromptScroll"
        anchors.fill: parent
        anchors.margins: Theme.size(11)
        anchors.topMargin: Theme.size(11) + (fixedActions.visible
                           ? fixedActions.height + Theme.size(7) : 0)
        anchors.bottomMargin: Theme.size(11) + (targetFooter.visible
                              ? targetFooter.height + Theme.size(7) : 0)
                              + (combatFooter.visible ? combatFooter.height + Theme.size(4) : 0)
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
            // Option rows are reused across decisions. A focused button would
            // otherwise keep focus while it changes to another action.
            for (let item = root.Window.activeFocusItem; item; item = item.parent) {
                if (item === fixedActions || item === actionOptions) {
                    root.Window.activeFocusItem.focus = false
                    break
                }
            }
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
            visible: root.combatPrompt === null || (!root.redundantCombatDetail && promptDetail.text.length > 0)
            spacing: Theme.size(10)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(2)

                Text {
                    id: promptTitle
                    textFormat: Text.PlainText
                    objectName: "rulesPromptTitle"
                    visible: root.combatPrompt === null
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
                    maximumLineCount: 6
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
                    visible: rulesSession.promptKind !== "payManaCost"
                             && !root.redundantCombatDetail
                             && !rulesSession.gameOver
                             && (rulesSession.promptPending
                                 || root.waitingForDecision)
                    text: root.waitingForDecision
                          ? qsTr("Forge is waiting for another player to respond.")
                          : rulesSession.promptSupported
                          ? root.tableController.promptDetail(
                                rulesSession.promptKind,
                                root.targetInstruction || rulesSession.promptDetail)
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

                // Fixed actions and actions shown on the table build no button.
                // Roles are required properties: an inserted row's `model` object
                // can still be empty while these bindings first run.
                delegate: Loader {
                    id: actionSlot
                    required property int index
                    required property string responseId
                    required property string label
                    required property string kind
                    required property string cardId
                    readonly property bool onTable: root.interaction !== null
                        && root.interaction.actionOnTable(cardId, kind)
                    readonly property bool shown: !root.isFixedAction(responseId) && !onTable

                    active: shown
                    visible: shown
                    width: shown ? Math.min(Theme.size(260), actionOptions.width) : 0
                    height: Theme.size(72)
                    sourceComponent: AppButton {
                        id: actionButton
                        objectName: "rulesPromptOption-" + actionSlot.responseId
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
                            objectName: "rulesPromptActionTooltip-" + actionSlot.responseId
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
                                actionOptions.positionViewAtIndex(actionSlot.index, ListView.Contain)
                        }
                        text: root.tableController.promptOptionLabel(rulesSession.promptKind,
                            actionSlot.responseId, actionSlot.label, actionSlot.cardId)
                        onClicked: root.tableController.wsModel.respondRulesPrompt(
                                       rulesSession.promptId, actionSlot.responseId)
                    }
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
            previewAvoidItems: targetFooter.visible ? [targetFooter]
                               : combatFooter.visible ? [combatFooter] : []
            showContextText: rulesSession.promptKind !== "chooseBoardTargets"
            contextEnabled: (root.interaction === null || root.interaction.contextActive)
                            && rulesSession.promptKind !== "payManaCost"
            expandedCard: ["chooseBoolean", "chooseFromSelection", "chooseColor", "chooseNumber"].includes(rulesSession.promptKind)
            cardHeight: typeof root.tableController.height === "number"
                ? Math.min(Theme.size(280), Math.max(Theme.size(100), root.tableController.height - Theme.size(400)))
                : Theme.size(280)
            cardCatalogModel: root.tableController.cardCatalogModel
            sourceCardModel: rulesSession.promptContextCards
            targetModel: rulesSession.promptContextTargets
            contextText: rulesSession.promptContextText
        }

        Loader {
            id: promptFamily
            Layout.fillWidth: true
            readonly property Item familyItem: item as Item
            Layout.preferredHeight: familyItem ? familyItem.implicitHeight : 0
            visible: familyItem !== null
            sourceComponent: root.activeFamily
            onFamilyItemChanged: if (familyItem) familyItem.width = width
            onWidthChanged: if (familyItem) familyItem.width = width
        }
    }

    Component {
        id: cardSelectionFamily
        RulesCardSelectionPrompt {
            enabled: !root.tableController.rulesResponsePending
            wsModel: root.tableController.wsModel
            cardCatalogModel: root.tableController.cardCatalogModel
            cardModel: root.rulesSession.promptCards
            promptId: root.rulesSession.promptId
            minimumSelections: root.rulesSession.promptMinCardSelections
            maximumSelections: root.rulesSession.promptMaxCardSelections
            cancellable: root.rulesSession.promptKind === "chooseCards"
                         && root.rulesSession.promptCancellable
            confirmationText: root.rulesSession.promptKind === "mulliganPutBack"
                              ? qsTr("Put on library bottom")
                              : qsTr("Confirm cards")
        }
    }
    Component {
        id: revealFamily
        RulesRevealPrompt {
            enabled: !root.tableController.rulesResponsePending
            wsModel: root.tableController.wsModel
            cardCatalogModel: root.tableController.cardCatalogModel
            cardModel: root.rulesSession.promptCards
            promptId: root.rulesSession.promptId
        }
    }
    Component {
        id: reorderFamily
        RulesOrderPrompt {
            enabled: !root.tableController.rulesResponsePending
            wsModel: root.tableController.wsModel
            cardCatalogModel: root.tableController.cardCatalogModel
            orderModel: root.rulesSession.promptOrderItems
            promptId: root.rulesSession.promptId
        }
    }
    Component {
        id: scryFamily
        RulesScryPrompt {
            enabled: !root.tableController.rulesResponsePending
            wsModel: root.tableController.wsModel
            cardCatalogModel: root.tableController.cardCatalogModel
            cardModel: root.rulesSession.promptCards
            destinations: root.rulesSession.promptScryDestinations
            promptId: root.rulesSession.promptId
        }
    }
    Component {
        id: damageOrderFamily
        RulesOrderPrompt {
            enabled: !root.tableController.rulesResponsePending
            wsModel: root.tableController.wsModel
            cardCatalogModel: root.tableController.cardCatalogModel
            orderModel: root.rulesSession.promptDamageTargets
            promptId: root.rulesSession.promptId
            damageOrder: true
        }
    }
    Component {
        id: damageAssignmentFamily
        RulesDamageAssignmentPrompt {
            enabled: !root.tableController.rulesResponsePending
            wsModel: root.tableController.wsModel
            cardCatalogModel: root.tableController.cardCatalogModel
            targetModel: root.rulesSession.promptDamageTargets
            damageSource: root.rulesSession.promptDamageSource
            promptId: root.rulesSession.promptId
            totalDamage: root.rulesSession.promptTotalDamage
            deathtouch: root.rulesSession.promptDamageDeathtouch
            assignmentMode: root.rulesSession.promptDamageAssignmentMode === undefined
                            ? "ordered" : root.rulesSession.promptDamageAssignmentMode
        }
    }
    Component {
        id: targetFamily
        RulesTargetSelectionPrompt {
            externalControls: true
            enabled: !root.tableController.rulesResponsePending
            wsModel: root.tableController.wsModel
            cardCatalogModel: root.tableController.cardCatalogModel
            targetModel: root.rulesSession.promptTargets
            interaction: root.interaction
            promptId: root.rulesSession.promptId
            minimumSelections: root.rulesSession.promptMinSelections
            maximumSelections: root.rulesSession.promptMaxSelections
            cancellable: root.rulesSession.promptCancellable
        }
    }
    Component {
        id: attackerFamily
        RulesCombatAssignmentPrompt {
            id: attackerAssignments
            externalControls: true
            enabled: !root.tableController.rulesResponsePending
            wsModel: root.tableController.wsModel
            cardCatalogModel: root.tableController.cardCatalogModel
            sourceModel: root.rulesSession.promptCombat
            promptId: root.rulesSession.promptId
            assignmentKind: "attackers"
            selectionState: root.tableController.combatInteraction || null
            boardSelection: !!selectionState && root.tableController.roomSession.maxSeats <= 2
        }
    }
    Component {
        id: blockerFamily
        RulesCombatAssignmentPrompt {
            id: blockerAssignments
            externalControls: true
            enabled: !root.tableController.rulesResponsePending
            wsModel: root.tableController.wsModel
            cardCatalogModel: root.tableController.cardCatalogModel
            sourceModel: root.rulesSession.promptCombat
            promptId: root.rulesSession.promptId
            assignmentKind: "blockers"
            selectionState: root.tableController.combatInteraction || null
            boardSelection: !!selectionState && root.tableController.roomSession.maxSeats <= 2
        }
    }
    Component {
        id: scalarFamily
        RulesScalarChoicePrompt {
            enabled: !root.tableController.rulesResponsePending
            wsModel: root.tableController.wsModel
            choiceModel: root.rulesSession.promptChoices
            promptId: root.rulesSession.promptId
            promptKind: root.rulesSession.promptKind
            promptTitle: root.rulesSession.promptTitle
            promptDetail: root.rulesSession.promptDetail
            englishRulesText: root.tableController.promptRulesText("en")
            localizedRulesText: root.tableController.promptRulesText("")
            minimumTotal: root.rulesSession.promptMinChoiceTotal
            maximumTotal: root.rulesSession.promptMaxChoiceTotal
        }
    }
    Component {
        id: cardNameFamily
        RulesCardNamePrompt {
            enabled: !root.tableController.rulesResponsePending
            wsModel: root.tableController.wsModel
            cardCatalogModel: root.tableController.cardCatalogModel
            promptId: root.rulesSession.promptId
            cancellable: root.rulesSession.promptCancellable
        }
    }
    Component {
        id: numberFamily
        RulesNumberPrompt {
            enabled: !root.tableController.rulesResponsePending
            wsModel: root.tableController.wsModel
            promptId: root.rulesSession.promptId
            minimum: root.rulesSession.promptMinNumber
            maximum: root.rulesSession.promptMaxNumber
        }
    }
}
