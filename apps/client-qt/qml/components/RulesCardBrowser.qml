// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: root

    required property var cardModel
    required property var cardCatalogModel
    required property int promptId
    property var selectedIds: ({})
    property bool readOnly: false
    property string candidatesName: "rulesCardCandidates"
    property int modelRevision: 0
    property alias filterText: search.text
    property alias grid: cards
    readonly property var allCards: {
        void modelRevision
        void promptId
        if (!cardModel) return []
        if (typeof cardModel.items === "function") return cardModel.items()
        const result = []
        for (let i = 0; i < cardModel.count; ++i) result.push(cardModel.get(i))
        return result
    }
    readonly property var matchingCards: {
        const query = search.text.trim().toLocaleLowerCase()
        return allCards.filter(card => (!selectedOnly.checked || selectedIds[card.cardId] === true)
            && (!query || card.name.toLocaleLowerCase().includes(query)))
    }
    signal cardToggled(string cardId)

    spacing: Theme.size(10)
    implicitHeight: Theme.size(480)

    function resetFilter() {
        if (search) search.clear()
        if (selectedOnly) selectedOnly.checked = false
        if (cards) cards.positionViewAtBeginning()
    }
    onPromptIdChanged: resetFilter()
    Connections {
        target: root.cardModel
        ignoreUnknownSignals: true
        function onModelReset() { root.modelRevision++ }
        function onRowsInserted() { root.modelRevision++ }
        function onRowsRemoved() { root.modelRevision++ }
        function onDataChanged() { root.modelRevision++ }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.size(8)
        AppTextField {
            id: search
            objectName: "rulesCardFilter"
            Layout.fillWidth: true
            implicitHeight: Theme.size(42)
            placeholderText: qsTr("Filter by card name")
            Accessible.name: placeholderText
            maximumLength: 160
            onTextChanged: if (cards) cards.positionViewAtBeginning()
            Keys.onDownPressed: {
                cards.currentIndex = cards.count > 0 ? 0 : -1
                cards.forceActiveFocus()
            }
        }
        AppButton {
            objectName: "rulesClearCardFilter"
            compact: true
            text: qsTr("Clear filter")
            enabled: search.text.length > 0
            onClicked: { search.clear(); search.forceActiveFocus() }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("Showing %1 of %2 cards").arg(root.matchingCards.length).arg(root.allCards.length)
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(11)
            wrapMode: Text.Wrap
        }
        AppToggle {
            id: selectedOnly
            objectName: "rulesSelectedCardsOnly"
            visible: !root.readOnly
            text: qsTr("Selected only")
            font.pixelSize: Theme.fontSize(11)
            onCheckedChanged: if (cards) cards.positionViewAtBeginning()
        }
    }
    GridView {
        id: cards
        objectName: root.candidatesName
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: Theme.size(140)
        readonly property int columns: Math.max(1, Math.floor((width - Theme.size(14)) / Theme.size(156)))
        cellWidth: Math.max(0, (width - Theme.size(14)) / columns)
        cellHeight: Math.min(Theme.size(238), cellWidth * 1.4 + Theme.size(38))
        model: root.matchingCards
        clip: true
        activeFocusOnTab: true
        boundsBehavior: Flickable.StopAtBounds
        keyNavigationEnabled: true
        currentIndex: -1
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Home) {
                currentIndex = count > 0 ? 0 : -1
                positionViewAtBeginning()
                event.accepted = true
            } else if (event.key === Qt.Key_End) {
                currentIndex = count - 1
                positionViewAtEnd()
                event.accepted = true
            }
        }
        Keys.onSpacePressed: if (currentIndex >= 0 && currentIndex < count && !root.readOnly)
            root.cardToggled(root.matchingCards[currentIndex].cardId)
        Keys.onReturnPressed: if (currentIndex >= 0 && currentIndex < count && !root.readOnly)
            root.cardToggled(root.matchingCards[currentIndex].cardId)
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        delegate: Rectangle {
            id: cardTile
            required property var modelData
            required property int index
            readonly property string cardId: modelData.cardId
            readonly property string name: modelData.name
            readonly property string setCode: modelData.setCode || ""
            readonly property string collectorNumber: modelData.collectorNumber || ""
            readonly property bool selected: root.selectedIds[cardId] === true
            objectName: (root.readOnly ? "rulesRevealedCard-" : "rulesCardCandidate-") + cardId
            width: cards.cellWidth - Theme.size(10)
            height: cards.cellHeight - Theme.size(10)
            radius: Theme.radiusSmall
            color: Theme.surfaceMuted
            border.width: selected ? 3 : 1
            border.color: selected || (cards.activeFocus && cards.currentIndex === index) ? Theme.primary : Theme.border
            Accessible.role: root.readOnly ? Accessible.StaticText : Accessible.Button
            Accessible.name: name + (selected ? " · " + qsTr("Selected") : "")
            Accessible.onPressAction: if (!root.readOnly) root.cardToggled(cardId)
            Image {
                id: art
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: caption.top
                anchors.margins: Theme.size(5)
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                source: {
                    if (!root.cardCatalogModel || !cardTile.name
                        || typeof root.cardCatalogModel.tableImageSource !== "function") return ""
                    void root.cardCatalogModel.imageRevision
                    return root.cardCatalogModel.tableImageSource(cardTile.name, cardTile.setCode, cardTile.collectorNumber)
                }
            }
            Text {
                textFormat: Text.PlainText
                anchors.centerIn: art
                width: art.width
                visible: art.status !== Image.Ready
                text: cardTile.name
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(12)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
            Text {
                id: caption
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Theme.size(6)
                height: Theme.size(32)
                text: cardTile.name
                color: Theme.text
                font.pixelSize: Theme.fontSize(10)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Text {
                textFormat: Text.PlainText
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Theme.size(6)
                visible: cardTile.selected
                text: "✓"
                color: Theme.primary
                font.pixelSize: Theme.fontSize(22)
                font.weight: Font.Bold
            }
            TapHandler {
                onTapped: {
                    cards.currentIndex = cardTile.index
                    if (!root.readOnly) root.cardToggled(cardTile.cardId)
                }
            }
            HoverHandler { id: hover }
            ToolTip.visible: hover.hovered
            ToolTip.delay: 350
            ToolTip.text: [cardTile.name, cardTile.setCode,
                cardTile.collectorNumber ? "#" + cardTile.collectorNumber : ""].filter(part => part.length > 0).join(" · ")
        }
        Text {
            textFormat: Text.PlainText
            objectName: "rulesCardFilterEmpty"
            anchors.centerIn: parent
            width: parent.width
            visible: cards.count === 0
            text: root.allCards.length === 0 ? qsTr("No cards to display") : qsTr("No cards match this filter")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(14)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }
    }
}
