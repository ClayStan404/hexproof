// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root
    objectName: "rulesCardSelectionPrompt"

    required property var wsModel
    required property var cardCatalogModel
    required property var cardModel
    required property int promptId
    required property int minimumSelections
    required property int maximumSelections
    required property string confirmationText
    property bool expandedView: false
    property bool cancellable: false
    property var selectedIds: ({})
    property int modelRevision: 0
    readonly property var allCards: {
        void modelRevision
        void promptId
        if (!cardModel) return []
        return typeof cardModel.items === "function" ? cardModel.items()
            : Array.from({length: cardModel.count}, (_, i) => cardModel.get(i))
    }
    readonly property var selectableIds: {
        const result = {}
        for (const card of allCards)
            if (card.readOnly !== true) result[card.cardId] = true
        return result
    }
    readonly property var nativeSelectedIds: {
        const result = {}
        for (const card of allCards)
            if (card.nativeSelected === true && card.readOnly !== true) result[card.cardId] = true
        return result
    }
    readonly property int nativeSelectedCount: Object.keys(nativeSelectedIds).length
    readonly property int selectedCount: Object.keys(selectedIds).length
    readonly property bool validSelection: selectedCount >= minimumSelections
                                                   && selectedCount <= maximumSelections

    readonly property bool narrowLayout: width < Theme.size(490)

    implicitHeight: expandedView ? Theme.size(540) : narrowLayout
                    ? Theme.size(154) + selectionControls.implicitHeight
                    : Math.max(Theme.size(142), selectionControls.implicitHeight)

    function resetSelection() {
        selectedIds = ({})
    }

    function toggleCard(cardId) {
        if (selectableIds[cardId] !== true) return
        const next = Object.assign({}, selectedIds)
        if (next[cardId] === true) {
            delete next[cardId]
        } else if (selectedCount < maximumSelections) {
            next[cardId] = true
        }
        selectedIds = next
    }

    function submitSelection() {
        if (!validSelection)
            return
        wsModel.respondRulesPromptWithCards(promptId, "$submit",
                                           Object.keys(selectedIds))
    }

    onPromptIdChanged: resetSelection()
    Connections {
        target: root.cardModel
        ignoreUnknownSignals: true
        function onModelReset() { root.modelRevision++; root.resetSelection() }
        function onRowsInserted() { root.modelRevision++ }
        function onRowsRemoved() { root.modelRevision++ }
        function onDataChanged() { root.modelRevision++ }
    }

    GridLayout {
        anchors.fill: parent
        columns: root.expandedView || root.narrowLayout ? 1 : 2
        columnSpacing: Theme.size(12)
        rowSpacing: Theme.size(12)

        RulesHorizontalListView {
            id: cardList
            objectName: root.expandedView ? "" : "rulesCardCandidates"
            visible: !root.expandedView

            Layout.fillWidth: true
            Layout.preferredHeight: Theme.size(142)
            Layout.fillHeight: true
            spacing: Theme.size(8)
            model: root.cardModel

            delegate: Rectangle {
                id: cardTile

                objectName: "rulesCardCandidate-" + cardId
                activeFocusOnTab: selectable
                Keys.onSpacePressed: root.toggleCard(cardId)
                Keys.onReturnPressed: root.toggleCard(cardId)

                required property string cardId
                required property string name
                required property string setCode
                required property string collectorNumber
                required property bool token
                readonly property bool selected: root.selectedIds[cardId] === true
                readonly property bool nativeSelected: root.nativeSelectedIds[cardId] === true
                readonly property bool selectable: root.selectableIds[cardId] === true
                readonly property string selectionLabel: !selectable ? qsTranslate("RulesCardBrowser", "Not selectable") : nativeSelected
                    ? selected ? qsTr("Undo selection") : qsTr("Already selected")
                    : selected ? qsTr("Selected") : ""

                width: Theme.size(88)
                height: cardList.itemHeight
                radius: Theme.radiusSmall
                color: Theme.surfaceMuted
                border.width: selected || nativeSelected ? 3 : 1
                border.color: selected || activeFocus ? Theme.primary
                    : nativeSelected ? Theme.success : Theme.border
                clip: true
                Accessible.role: selectable ? Accessible.Button : Accessible.StaticText
                Accessible.name: name + (selectionLabel ? " · " + selectionLabel : "")
                Accessible.onPressAction: root.toggleCard(cardId)

                Image {
                    id: art

                    anchors.fill: parent
                    anchors.margins: Theme.size(3)
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    source: {
                        if (!root.cardCatalogModel || !cardTile.name
                                || typeof root.cardCatalogModel.tableImageSource
                                !== "function") {
                            return ""
                        }
                        void root.cardCatalogModel.imageRevision
                        return root.cardCatalogModel.tableImageSource(
                                    cardTile.name, cardTile.setCode,
                                    cardTile.collectorNumber)
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    width: parent.width - Theme.size(10)
                    visible: art.status !== Image.Ready
                    text: cardTile.name.length > 0
                          ? cardTile.name : qsTr("Unknown card")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(9)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.margins: Theme.size(5)
                    width: parent.width - Theme.size(8)
                    height: badgeText.implicitHeight + Theme.size(8)
                    radius: Theme.radiusSmall
                    visible: cardTile.selectionLabel.length > 0
                    color: cardTile.selected ? Theme.primary : cardTile.nativeSelected ? Theme.success : Theme.surfaceElevated

                    Text {
                        id: badgeText
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        width: parent.width - Theme.size(6)
                        text: cardTile.selectionLabel
                        color: cardTile.selectable ? Theme.primaryInk : Theme.textSecondary
                        font.pixelSize: Theme.fontSize(9)
                        font.weight: Font.Bold
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                    }
                }

                TapHandler {
                    onTapped: root.toggleCard(cardTile.cardId)
                }

                HoverHandler { id: hover }
                ToolTip.visible: hover.hovered
                ToolTip.delay: 350
                ToolTip.text: cardTile.name + " · " + cardTile.setCode
                              + " #" + cardTile.collectorNumber
            }
        }

        RulesCardBrowser {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.expandedView
            cardModel: root.expandedView ? root.cardModel : null
            cardCatalogModel: root.cardCatalogModel
            promptId: root.promptId
            selectedIds: root.selectedIds
            onCardToggled: cardId => root.toggleCard(cardId)
        }

        ColumnLayout {
            id: selectionControls

            Layout.fillWidth: root.expandedView || root.narrowLayout
            Layout.preferredWidth: root.expandedView || root.narrowLayout ? -1 : Theme.size(190)
            spacing: Theme.size(8)

            Text {
                textFormat: Text.PlainText
                objectName: "rulesPreviouslySelectedCards"
                Layout.fillWidth: true
                visible: root.nativeSelectedCount > 0
                text: qsTr("Already selected: %1. Select a marked card to undo it.").arg(root.nativeSelectedCount)
                color: Theme.success
                font.pixelSize: Theme.fontSize(11)
                wrapMode: Text.Wrap
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.minimumSelections === root.maximumSelections
                      ? (root.nativeSelectedCount > 0 ? qsTr("Next choice: %1 of %2") : qsTr("Selected %1 of %2"))
                        .arg(root.selectedCount).arg(root.maximumSelections)
                      : (root.nativeSelectedCount > 0 ? qsTr("Next choice: %1 · choose %2–%3") : qsTr("Selected %1 · choose %2–%3"))
                        .arg(root.selectedCount).arg(root.minimumSelections)
                        .arg(root.maximumSelections)
                color: root.validSelection ? Theme.success : Theme.textSecondary
                font.pixelSize: Theme.fontSize(11)
                horizontalAlignment: Text.AlignHCenter
            }

            AppButton {
                objectName: "rulesConfirmCards"
                Layout.fillWidth: true
                variant: "primary"
                text: root.confirmationText
                enabled: root.validSelection
                disabledReason: qsTr("Choose a valid number of cards")
                onClicked: root.submitSelection()
            }

            AppButton {
                objectName: "rulesCancelCards"
                Layout.fillWidth: true
                visible: root.cancellable
                text: qsTr("Cancel")
                onClicked: root.wsModel.respondRulesPrompt(root.promptId, "$cancel")
            }
        }
    }
}
