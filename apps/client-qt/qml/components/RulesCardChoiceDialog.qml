// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root
    required property var tableController
    readonly property var session: tableController.rulesSession
    readonly property bool requested: tableController.interaction.contextActive
        && ["chooseCards", "mulliganPutBack", "revealCards", "scry", "reorder",
            "chooseDamageAssignmentOrder"].includes(session.promptKind)

    objectName: "rulesCardChoiceDialog"
    parent: Overlay.overlay
    width: Math.min(Theme.size(1080), parent ? parent.width - Theme.size(40) : 0)
    height: Math.min(Theme.size(["scry", "reorder", "chooseDamageAssignmentOrder"]
        .includes(session.promptKind) ? 520 : 780), parent ? parent.height - Theme.size(40) : 0)
    x: parent ? (parent.width - width) / 2 : 0
    y: parent ? (parent.height - height) / 2 : 0
    padding: Theme.size(18)
    modal: true
    focus: true
    closePolicy: Popup.NoAutoClose
    visible: requested
    background: Surface { color: Theme.surfaceElevated; border.color: Theme.primary }

    contentItem: ColumnLayout {
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
        Text {
            id: detail
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.tableController.promptDetail(root.session.promptKind, root.session.promptDetail)
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
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            active: root.requested
            enabled: !root.tableController.rulesResponsePending
            sourceComponent: root.session.promptKind === "revealCards" ? reveal
                : root.session.promptKind === "scry" ? scry
                : ["reorder", "chooseDamageAssignmentOrder"].includes(root.session.promptKind)
                    ? order : selection
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
