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
        function onModelReset() { root.resetSelection() }
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
                activeFocusOnTab: true
                Keys.onSpacePressed: root.toggleCard(cardId)
                Keys.onReturnPressed: root.toggleCard(cardId)

                required property string cardId
                required property string name
                required property string setCode
                required property string collectorNumber
                required property bool token
                readonly property bool selected: root.selectedIds[cardId] === true

                width: Theme.size(88)
                height: cardList.itemHeight
                radius: Theme.radiusSmall
                color: Theme.surfaceMuted
                border.width: selected ? 3 : 1
                border.color: selected || activeFocus ? Theme.primary : Theme.border
                clip: true

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
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.size(5)
                    width: Theme.size(24)
                    height: width
                    radius: width / 2
                    visible: cardTile.selected
                    color: Theme.primary

                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: "✓"
                        color: Theme.primaryInk
                        font.pixelSize: Theme.fontSize(12)
                        font.weight: Font.Bold
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
                Layout.fillWidth: true
                text: root.minimumSelections === root.maximumSelections
                      ? qsTr("Selected %1 of %2")
                        .arg(root.selectedCount).arg(root.maximumSelections)
                      : qsTr("Selected %1 · choose %2–%3")
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
