// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts

AppPopup {
    id: root

    property var cardCatalogModel: null
    property var deckLibraryModel: null
    property string participantName: ""
    property var deck: ({})

    readonly property var mainboardCards: root.deck.mainboard || []
    readonly property var sideboardCards: root.deck.sideboard || []
    readonly property int mainboardCount: root.cardCount(root.mainboardCards)
    readonly property int sideboardCount: root.cardCount(root.sideboardCards)
    readonly property bool canExport: root.mainboardCount + root.sideboardCount > 0
    readonly property var mainboardGroups: root.groupCards(root.mainboardCards, true)
    readonly property var sideboardGroups: root.groupCards(root.sideboardCards, false)

    width: parent ? Math.min(Theme.size(1180), parent.width - Theme.size(32)) : Theme.size(960)
    height: parent ? Math.min(Theme.size(820), parent.height - Theme.size(32)) : Theme.size(720)

    contentItem: ColumnLayout {
        spacing: Theme.size(12)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(10)

            AppPopupHeader {
                Layout.fillWidth: true
                titleText: qsTr("%1's decklist").arg(root.participantName)
                subtitleText: root.subtitleText()
            }

            AppButton {
                objectName: "tournamentDecklistExportButton"
                compact: true
                variant: "highlight"
                text: qsTr("Export")
                enabled: root.canExport
                disabledReason: qsTr("This participant has no recorded cards.")
                onClicked: exportMenu.popup(this, 0, height + Theme.size(4))
            }

            AppButton {
                objectName: "tournamentDecklistCloseButton"
                compact: true
                variant: "ghost"
                text: "×"
                accessibleName: qsTr("Close")
                Layout.preferredWidth: Theme.size(40)
                onClicked: root.close()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.divider
        }

        Flickable {
            id: decklistScroll
            objectName: "tournamentDecklistScroll"
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: decklistContent.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: AppScrollBar {
                objectName: "tournamentDecklistScrollBar"
                prominent: true
            }

            ColumnLayout {
                id: decklistContent
                width: decklistScroll.width
                spacing: Theme.size(18)

                ZoneSection {
                    Layout.fillWidth: true
                    title: qsTr("Mainboard · %1").arg(root.mainboardCount)
                    groups: root.mainboardGroups
                    emptyText: qsTr("No mainboard cards were recorded.")
                }

                ZoneSection {
                    Layout.fillWidth: true
                    visible: root.sideboardCount > 0 || root.sideboardCards.length > 0
                    title: qsTr("Sideboard · %1").arg(root.sideboardCount)
                    groups: root.sideboardGroups
                    emptyText: qsTr("No sideboard cards were recorded.")
                }
            }
        }
    }

    Item {
        parent: root.contentItem ? root.contentItem.parent : null
        anchors.fill: parent
        anchors.margins: Theme.size(12)
        visible: root.opened
        enabled: false
        z: 1000

        CardHoverPreview {
            id: cardPreview
            catalogModel: root.cardCatalogModel
            artObjectName: "tournamentDecklistHoverPreviewArt"
        }
    }

    AppMenu {
        id: exportMenu
        objectName: "tournamentDecklistExportMenu"

        AppMenuItem {
            objectName: "tournamentDecklistCopyMenuItem"
            text: qsTr("Copy list")
            enabled: root.canExport
            onTriggered: root.copyDecklist()
        }
        AppMenuItem {
            objectName: "tournamentDecklistSaveMenuItem"
            text: qsTr("Save as file")
            enabled: root.canExport
            onTriggered: {
                exportFileDialog.selectedFile = root.deckLibraryModel
                        ? root.deckLibraryModel.suggestedPublishedDeckUrl(
                              root.participantName, root.deck.name || "")
                        : ""
                exportFileDialog.open()
            }
        }
    }

    FileDialog {
        id: exportFileDialog
        objectName: "tournamentDecklistExportFileDialog"
        title: qsTr("Save deck list")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "txt"
        nameFilters: [
            qsTr("Deck lists") + " (*.txt)",
            qsTr("All files") + " (*)"
        ]
        onAccepted: root.saveDecklist(selectedFile)
    }

    component ZoneSection: ColumnLayout {
        required property string title
        required property var groups
        required property string emptyText

        spacing: Theme.size(10)

        Text {
            textFormat: Text.PlainText
            text: title
            color: Theme.text
            font.pixelSize: Theme.fontSize(16)
            font.weight: Font.DemiBold
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: groups.length === 0
            text: emptyText
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize(13)
        }

        Repeater {
            model: groups

            delegate: ColumnLayout {
                id: groupColumn
                required property var modelData
                Layout.fillWidth: true
                spacing: Theme.size(6)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.size(8)

                    Text {
                        textFormat: Text.PlainText
                        text: groupColumn.modelData.label
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(12)
                        font.weight: Font.DemiBold
                    }
                    StatusPill {
                        text: String(groupColumn.modelData.count)
                        statusColor: Theme.accent
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Theme.border
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.size(10)

                    Repeater {
                        model: groupColumn.modelData.cards

                        delegate: DecklistCard {
                            required property var modelData
                            card: modelData
                            commanderCard: groupColumn.modelData.key === "Commander"
                        }
                    }
                }
            }
        }
    }

    component DecklistCard: Item {
        id: cardTile

        required property var card
        property bool commanderCard: false

        readonly property string displayName: {
            if (!cardTile.card || !cardTile.card.name)
                return qsTr("Unknown card")
            if (root.cardCatalogModel
                    && typeof root.cardCatalogModel.cardDisplayName === "function")
                return root.cardCatalogModel.cardDisplayName(cardTile.card.name)
            return cardTile.card.name
        }
        readonly property string imageSource: {
            if (!root.cardCatalogModel || !cardTile.card || !cardTile.card.name)
                return ""
            void root.cardCatalogModel.imageRevision
            return root.cardCatalogModel.imageSource(
                        cardTile.card.name, cardTile.card.setCode || "",
                        cardTile.card.collectorNumber || "")
        }

        width: Theme.size(126)
        height: Theme.size(186)

        Surface {
            anchors.fill: parent
            radius: Theme.radiusMedium
            color: cardHover.hovered ? Theme.surfaceHover : Theme.surfaceMuted
            border.width: cardTile.commanderCard || cardHover.hovered ? 2 : 1
            border.color: cardTile.commanderCard ? Theme.accent
                          : (cardHover.hovered ? Theme.primary : Theme.border)
            clip: true

            Image {
                id: art
                anchors.fill: parent
                anchors.margins: Theme.size(4)
                anchors.bottomMargin: Theme.size(36)
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                source: cardTile.imageSource
            }

            Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: art.verticalCenter
                anchors.margins: Theme.size(8)
                visible: art.status !== Image.Ready
                text: cardTile.displayName
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(11)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Theme.size(7)
                implicitWidth: countLabel.implicitWidth + Theme.size(10)
                implicitHeight: Theme.size(22)
                radius: height / 2
                color: Theme.backgroundRaised
                border.width: 1
                border.color: Theme.borderStrong

                Text {
                    id: countLabel
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: (cardTile.card && cardTile.card.count
                           ? cardTile.card.count : 1) + "×"
                    color: Theme.accent
                    font.pixelSize: Theme.fontSize(11)
                    font.weight: Font.Bold
                }
            }

            Text {
                textFormat: Text.PlainText
                visible: cardTile.commanderCard
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.size(7)
                text: qsTr("CMDR")
                color: Theme.accent
                font.pixelSize: Theme.fontSize(9)
                font.weight: Font.DemiBold
            }

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Theme.size(7)
                spacing: Theme.size(1)

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: cardTile.displayName
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(11)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: cardTile.card && cardTile.card.setCode
                          ? String(cardTile.card.setCode).toUpperCase()
                            + (cardTile.card.collectorNumber
                               ? " #" + cardTile.card.collectorNumber : "")
                          : ""
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(9)
                    elide: Text.ElideRight
                }
            }
        }

        HoverHandler {
            id: cardHover
            onHoveredChanged: {
                if (hovered)
                    cardPreview.inspect(cardTile.card, cardTile)
                else
                    cardPreview.hide(cardTile)
            }
        }
    }

    function showDeck(displayName, value) {
        participantName = displayName
        deck = value || ({})
        cardPreview.hide()
        open()
    }

    function cardCount(cards) {
        let count = 0
        const values = cards || []
        for (let index = 0; index < values.length; ++index)
            count += Number(values[index].count || 0)
        return count
    }

    function commanderNames() {
        if (root.deck && root.deck.commanders && root.deck.commanders.length > 0)
            return root.deck.commanders
        if (root.deck && root.deck.commander)
            return [root.deck.commander]
        return []
    }

    function subtitleText() {
        const parts = []
        if (root.deck && root.deck.name)
            parts.push(root.deck.name)
        const commanders = root.commanderNames()
        if (commanders.length > 0)
            parts.push(qsTr("Commander: %1").arg(commanders.join(" / ")))
        parts.push(qsTr("%1 main · %2 side").arg(root.mainboardCount).arg(root.sideboardCount))
        return parts.join(" · ")
    }

    function typeLineFor(card) {
        if (card && card.typeLine)
            return String(card.typeLine)
        if (root.cardCatalogModel && card && card.name
                && typeof root.cardCatalogModel.cardTypeLine === "function") {
            return root.cardCatalogModel.cardTypeLine(
                        card.name, card.setCode || "", card.collectorNumber || "")
        }
        return ""
    }

    function categoryKey(typeLine) {
        let type = String(typeLine || "").toLocaleLowerCase()
        const faceSeparator = type.indexOf(" // ")
        if (faceSeparator >= 0)
            type = type.slice(0, faceSeparator)
        const separators = ["—", "–", "～", "〜"]
        for (let index = 0; index < separators.length; ++index) {
            const position = type.indexOf(separators[index])
            if (position >= 0)
                type = type.slice(0, position)
        }
        const contains = function(terms) {
            for (let index = 0; index < terms.length; ++index) {
                if (type.indexOf(terms[index]) >= 0)
                    return true
            }
            return false
        }
        if (contains(["land", "地"]))
            return "Lands"
        if (contains(["creature", "生物"]))
            return "Creatures"
        if (contains(["planeswalker", "鹏洛客", "旅法师"]))
            return "Planeswalkers"
        if (contains(["artifact", "神器"]))
            return "Artifacts"
        if (contains(["enchantment", "结界"]))
            return "Enchantments"
        if (contains(["instant", "sorcery", "瞬间", "法术"]))
            return "Spells"
        return "Other"
    }

    function categoryLabel(key) {
        switch (key) {
        case "Commander":
            return qsTr("Commander")
        case "Creatures":
            return qsTr("Creatures")
        case "Planeswalkers":
            return qsTr("Planeswalkers")
        case "Artifacts":
            return qsTr("Artifacts")
        case "Enchantments":
            return qsTr("Enchantments")
        case "Spells":
            return qsTr("Spells")
        case "Lands":
            return qsTr("Lands")
        default:
            return qsTr("Other")
        }
    }

    function groupCards(cards, includeCommanders) {
        const order = ["Commander", "Creatures", "Planeswalkers", "Artifacts",
                       "Enchantments", "Spells", "Lands", "Other"]
        const buckets = {}
        for (let index = 0; index < order.length; ++index)
            buckets[order[index]] = []
        const commanderKeys = {}
        if (includeCommanders) {
            const commanders = root.commanderNames()
            for (let index = 0; index < commanders.length; ++index)
                commanderKeys[String(commanders[index]).trim().toLocaleLowerCase()] = true
        }
        const values = cards || []
        for (let index = 0; index < values.length; ++index) {
            const card = values[index]
            if (!card)
                continue
            const name = String(card.name || "").trim().toLocaleLowerCase()
            const key = includeCommanders && commanderKeys[name]
                        ? "Commander" : root.categoryKey(root.typeLineFor(card))
            buckets[key].push(card)
        }
        const result = []
        for (let index = 0; index < order.length; ++index) {
            const key = order[index]
            const grouped = buckets[key]
            if (grouped.length === 0)
                continue
            result.push({
                            key: key,
                            label: root.categoryLabel(key),
                            cards: grouped,
                            count: root.cardCount(grouped)
                        })
        }
        return result
    }

    function notify(message) {
        const window = ApplicationWindow.window
        if (window && typeof window.showBanner === "function")
            window.showBanner(message)
    }

    function copyDecklist() {
        if (!root.deckLibraryModel
                || typeof root.deckLibraryModel.copyPublishedDeckText !== "function") {
            notify(qsTr("Deck list export is unavailable."))
            return
        }
        if (root.deckLibraryModel.copyPublishedDeckText(root.deck))
            notify(qsTr("Deck list copied"))
        else
            notify(I18n.status(root.deckLibraryModel.lastError))
    }

    function saveDecklist(fileUrl) {
        if (!root.deckLibraryModel
                || typeof root.deckLibraryModel.savePublishedDeckText !== "function") {
            notify(qsTr("Deck list export is unavailable."))
            return
        }
        if (root.deckLibraryModel.savePublishedDeckText(root.deck, fileUrl))
            notify(qsTr("Deck list saved"))
        else
            notify(I18n.status(root.deckLibraryModel.lastError))
    }

    onClosed: cardPreview.hide()
}
