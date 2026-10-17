// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    required property var wsModel
    required property var cardCatalogModel
    required property var cardModel
    required property int promptId
    property bool expandedView: false

    readonly property bool narrowLayout: width < Theme.size(490)

    implicitHeight: expandedView ? Theme.size(540) : cardList.count > 0
                    ? Theme.size(142) + (narrowLayout ? Theme.size(12) + acknowledgeButton.implicitHeight : 0)
                    : Math.max(Theme.size(48), revealLayout.implicitHeight)

    function acknowledge() {
        wsModel.respondRulesPrompt(promptId, "$ack")
    }
    onPromptIdChanged: preview.hide()
    onVisibleChanged: if (!visible) preview.hide()
    onExpandedViewChanged: if (expandedView) preview.hide()
    CardHoverPreview {
        id: preview
        objectName: "rulesRevealCardPreview"
        parent: root.Overlay.overlay
        catalogModel: root.cardCatalogModel
        artObjectName: "rulesRevealCardPreviewArt"
        avoidItems: [acknowledgeButton]
    }

    GridLayout {
        id: revealLayout
        anchors.fill: parent
        columns: root.expandedView || root.narrowLayout ? 1 : 2
        columnSpacing: Theme.size(12)
        rowSpacing: Theme.size(12)

        RulesHorizontalListView {
            id: cardList
            objectName: root.expandedView ? "" : "revealCardList"

            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: Theme.size(142)
            visible: count > 0 && !root.expandedView
            spacing: Theme.size(8)
            model: root.cardModel

            delegate: Rectangle {
                id: cardTile

                required property string cardId
                required property string name
                required property string setCode
                required property string collectorNumber
                required property bool token

                width: Theme.size(88)
                height: cardList.itemHeight
                radius: Theme.radiusSmall
                color: Theme.surfaceMuted
                border.width: 1
                border.color: Theme.border
                clip: true
                activeFocusOnTab: true
                function inspect() {
                    if (!root.visible || root.expandedView || !name) return
                    preview.tokenArt = token
                    preview.inspect({id:cardId, name:name, setCode:setCode, collectorNumber:collectorNumber}, cardTile)
                }
                onActiveFocusChanged: activeFocus ? inspect() : preview.hide(cardTile)
                onNameChanged: if (preview.sourceItem === cardTile) preview.hide()
                Component.onDestruction: preview.hide(cardTile)

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

                HoverHandler {
                    id: hover
                    onHoveredChanged: hovered ? cardTile.inspect() : preview.hide(cardTile)
                }
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
            readOnly: true
            candidatesName: "revealCardList"
            previewAvoidItems: [acknowledgeButton]
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: cardList.count === 0 && !root.expandedView
            text: qsTr("No cards to display")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(10)
            horizontalAlignment: Text.AlignHCenter
        }

        AppButton {
            id: acknowledgeButton
            objectName: "acknowledgeRevealButton"
            Layout.fillWidth: root.expandedView || root.narrowLayout
            Layout.preferredWidth: root.expandedView || root.narrowLayout ? -1 : Theme.size(150)
            compact: true
            variant: "primary"
            text: qsTr("Continue")
            onClicked: root.acknowledge()
        }
    }
}
