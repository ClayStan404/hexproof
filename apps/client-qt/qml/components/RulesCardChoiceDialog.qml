// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

RulesDecisionDialog {
    id: root
    requested: tableController.interaction.contextActive
        && ["chooseCards", "mulliganPutBack", "revealCards", "scry", "reorder",
            "chooseDamageAssignmentOrder"].includes(session.promptKind)
    // Forge asks for an order even when one optional opening ability is legal.
    // That ability is a "you may"; one card has no order to arrange.
    readonly property var openingAbilityCards: {
        void session.promptId
        if (session.promptKind !== "chooseCards"
                || session.promptTitle !== "Choose cards to activate from opening hand and their order"
                || session.promptMinCardSelections !== 0
                || !session.promptCards || typeof session.promptCards.items !== "function")
            return []
        return session.promptCards.items().filter(card => card && card.readOnly !== true)
    }
    readonly property bool singleOpeningAbility: openingAbilityCards.length === 1
    readonly property var openingAbilityCard: singleOpeningAbility ? openingAbilityCards[0] : null

    objectName: "rulesCardChoiceDialog"
    width: Math.min(Theme.size(singleOpeningAbility ? 480 : 1080), parent ? parent.width - Theme.size(40) : 0)
    height: Math.min(Theme.size(singleOpeningAbility ? 560
        : ["scry", "reorder", "chooseDamageAssignmentOrder"].includes(session.promptKind) ? 520 : 780),
        parent ? parent.height - Theme.size(40) : 0)
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
                objectName: "rulesChoiceTitle"
                Layout.fillWidth: true
                text: root.singleOpeningAbility
                      ? qsTr("Use %1's opening ability?")
                        .arg(root.tableController.cardDisplayName(root.openingAbilityCard.name || ""))
                      : root.tableController.promptTitle(root.session.promptKind, root.session.promptTitle)
                color: Theme.text
                font.pixelSize: Theme.fontSize(20)
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            AppButton {
                objectName: "rulesChoiceViewBattlefield"
                text: qsTranslate("RulesDecisionDialog", "View battlefield")
                enabled: !root.tableController.rulesResponsePending
                onClicked: root.inspectBattlefield()
            }
        }
        Text {
            id: detail
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.singleOpeningAbility
                  ? qsTr("You may reveal it from your opening hand, or leave it there.")
                  : root.tableController.promptDetail(root.session.promptKind, root.session.promptDetail)
            visible: text.length > 0
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(12)
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            HoverHandler { id: detailHover }
            ToolTip.visible: detailHover.hovered && truncated
            ToolTip.text: text
        }
        RulesPromptContext {
            Layout.fillWidth: true
            promptId: root.session.promptId
            contextEnabled: root.requested
            cardCatalogModel: root.tableController.cardCatalogModel
            sourceCardModel: root.session.promptContextCards
            targetModel: root.session.promptContextTargets
            contextText: root.session.promptContextText
        }
        Loader {
            objectName: "rulesChoiceContent"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            active: root.requested
            enabled: !root.tableController.rulesResponsePending
            sourceComponent: root.singleOpeningAbility ? opening
                : root.session.promptKind === "revealCards" ? reveal
                : root.session.promptKind === "scry" ? scry
                : ["reorder", "chooseDamageAssignmentOrder"].includes(root.session.promptKind)
                    ? order : selection
        }
    }
    Component {
        id: opening
        ColumnLayout {
            spacing: Theme.size(16)
            Image {
                objectName: "rulesOpeningAbilityArt"
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Theme.size(180)
                Layout.preferredHeight: Theme.size(250)
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                source: {
                    const card = root.openingAbilityCard
                    if (!card || !root.tableController.cardCatalogModel
                            || typeof root.tableController.cardCatalogModel.imageSource !== "function")
                        return ""
                    void root.tableController.cardCatalogModel.imageRevision
                    return root.tableController.cardCatalogModel.imageSource(
                                card.name || "", card.setCode || "", card.collectorNumber || "")
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.size(10)
                AppButton {
                    objectName: "rulesOpeningAbilitySkip"
                    Layout.fillWidth: true
                    text: qsTr("Leave it")
                    enabled: !root.tableController.rulesResponsePending
                    onClicked: root.tableController.wsModel.respondRulesPromptWithCards(
                                   root.session.promptId, "$submit", [])
                }
                AppButton {
                    objectName: "rulesOpeningAbilityUse"
                    Layout.fillWidth: true
                    variant: "highlight"
                    text: qsTr("Use it")
                    enabled: !root.tableController.rulesResponsePending
                    onClicked: root.tableController.wsModel.respondRulesPromptWithCards(
                                   root.session.promptId, "$submit",
                                   [root.openingAbilityCard.cardId])
                }
            }
        }
    }
    Component {
        id: scry
        RulesScryPrompt {
            expandedView: true
            wsModel: root.tableController.wsModel
            cardCatalogModel: root.tableController.cardCatalogModel
            cardModel: root.session.promptCards
            destinations: root.session.promptScryDestinations
            promptId: root.session.promptId
        }
    }
    Component {
        id: order
        RulesOrderPrompt {
            expandedView: true
            wsModel: root.tableController.wsModel
            cardCatalogModel: root.tableController.cardCatalogModel
            orderModel: damageOrder ? root.session.promptDamageTargets : root.session.promptOrderItems
            promptId: root.session.promptId
            damageOrder: root.session.promptKind === "chooseDamageAssignmentOrder"
        }
    }
    Component {
        id: selection
        RulesCardSelectionPrompt {
            expandedView: true
            wsModel: root.tableController.wsModel
            cardCatalogModel: root.tableController.cardCatalogModel
            cardModel: root.session.promptCards
            promptId: root.session.promptId
            minimumSelections: root.session.promptMinCardSelections
            maximumSelections: root.session.promptMaxCardSelections
            cancellable: root.session.promptKind === "chooseCards" && root.session.promptCancellable
            confirmationText: root.session.promptKind === "mulliganPutBack"
                ? qsTranslate("RulesPromptPanel", "Put on library bottom")
                : qsTranslate("RulesPromptPanel", "Confirm cards")
        }
    }
    Component {
        id: reveal
        RulesRevealPrompt {
            expandedView: true
            wsModel: root.tableController.wsModel
            cardCatalogModel: root.tableController.cardCatalogModel
            cardModel: root.session.promptCards
            promptId: root.session.promptId
        }
    }
}
