// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "TournamentLobby"
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root
    required property var cards
    required property var selectedIds
    property var fallbackCards: []
    property var selectedColors: []
    property var advice: []
    property bool showAll: false
    property alias filters: candidateFilters
    signal toggleRequested(string instanceId)
    signal colorRequested(string instanceId, string color)
    signal cardInspected(var card, var sourceItem)
    signal cardInspectionEnded(var sourceItem)
    readonly property var visibleCards: candidateFilters.filter(cards.filter(card =>
        showAll || selection.possibleCommander(card) || selectedIds.indexOf(card.instanceId) >= 0))
    parent: Overlay.overlay
    objectName: "limitedCommanderPicker"
    width: Math.min(Theme.size(560), parent ? parent.width - Theme.size(24) : 560)
    height: Math.min(Theme.size(640), parent ? parent.height - Theme.size(24) : 640)
    x: parent ? (parent.width - width) / 2 : 0
    y: parent ? (parent.height - height) / 2 : 0
    modal: true
    focus: true
    padding: Theme.size(16)
    background: Surface { elevated: true }
    LimitedCommanderSelection { id: selection }
    CardFilterState { id: candidateFilters }
    component CommanderRow: ColumnLayout {
        id: row
        required property var modelData
        readonly property bool chosen: root.selectedIds.indexOf(modelData.instanceId) >= 0
        readonly property string chosenColor: selection.colorFor(modelData.instanceId, root.selectedColors)
        Layout.fillWidth: true
        spacing: Theme.size(4)
        RowLayout {
            Layout.fillWidth: true
            CardListRow {
                id: cardRow
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                card: selection.withColor(row.modelData, root.selectedColors)
                highlighted: row.chosen || hover.hovered
                TapHandler {
                    enabled: selection.canSelect(row.modelData.instanceId, root.selectedIds, root.cards.concat(root.fallbackCards))
                    onTapped: root.toggleRequested(row.modelData.instanceId)
                }
                HoverHandler {
                    id: hover
                    onHoveredChanged: {
                        if (hovered) root.cardInspected(row.modelData, cardRow)
                        else root.cardInspectionEnded(cardRow)
                    }
                }
            }
            AppButton {
                objectName: "limitedCommanderToggle-" + row.modelData.instanceId
                compact: true
                implicitWidth: Theme.size(40)
                text: row.chosen ? "−" : "+"
                variant: row.chosen ? "primary" : "secondary"
                enabled: selection.canSelect(row.modelData.instanceId, root.selectedIds, root.cards.concat(root.fallbackCards))
                onClicked: root.toggleRequested(row.modelData.instanceId)
                Accessible.name: (row.chosen ? qsTranslate("TournamentLobby", "Remove commander")
                                            : qsTranslate("TournamentLobby", "Choose commander"))
                    + ": " + (row.modelData.displayName || row.modelData.name)
            }
        }
        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: (row.modelData.setCode || "") + " #" + (row.modelData.collectorNumber || "")
            color: row.chosen ? Theme.accent : Theme.textMuted
            font.pixelSize: Theme.fontSize(10)
        }
        ColumnLayout {
            visible: row.chosen && selection.isPiper(row.modelData)
            Layout.fillWidth: true
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: row.chosenColor
                    ? qsTranslate("TournamentLobby", "Chosen commander color: %1").arg(row.chosenColor)
                    : qsTranslate("TournamentLobby", "Choose this Piper's commander color")
                color: row.chosenColor ? Theme.textSecondary : Theme.warning
                font.pixelSize: Theme.fontSize(11)
                wrapMode: Text.WordWrap
            }
            RowLayout {
                spacing: Theme.size(6)
                Repeater {
                    model: ["W", "U", "B", "R", "G"]
                    delegate: AppButton {
                        id: colorButton
                        required property string modelData
                        objectName: "limitedCommanderColor-" + row.modelData.instanceId + "-" + modelData
                        compact: true
                        implicitWidth: Theme.size(42)
                        variant: row.chosenColor === modelData ? "primary" : "secondary"
                        Accessible.name: qsTranslate("TournamentLobby", "Chosen commander color: %1").arg(modelData)
                        Accessible.checkable: true
                        Accessible.checked: row.chosenColor === modelData
                        contentItem: Item {
                            implicitWidth: Theme.size(22)
                            implicitHeight: Theme.size(22)
                            CardManaSymbol {
                                anchors.centerIn: parent
                                symbol: colorButton.modelData
                            }
                        }
                        onClicked: root.colorRequested(row.modelData.instanceId, modelData)
                    }
                }
            }
        }
    }
    contentItem: ColumnLayout {
        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTranslate("TournamentLobby", "Commanders · %1 / 2").arg(root.selectedIds.length)
            font.pixelSize: Theme.fontSize(20)
            font.bold: true
            color: Theme.text
        }
        SegmentedControl {
            objectName: "limitedCommanderCandidateMode"
            Layout.fillWidth: true
            options: [qsTranslate("TournamentLobby", "Possible commanders"), qsTranslate("TournamentLobby", "All drafted cards")]
            currentIndex: root.showAll ? 1 : 0
            onActivated: index => root.showAll = index === 1
        }
        CardFilterBar {
            objectName: "limitedCommanderFilters"
            Layout.fillWidth: true
            filters: candidateFilters
        }
        ScrollView {
            objectName: "limitedCommanderScroll"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            contentWidth: availableWidth
            clip: true
            ColumnLayout {
                width: parent.width
                spacing: Theme.size(8)
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTranslate("TournamentLobby", "From your drafted cards")
                    color: Theme.text
                    font.bold: true
                    wrapMode: Text.WordWrap
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    visible: root.visibleCards.length === 0
                    text: qsTranslate("TournamentLobby", "No matching candidates. Use All drafted cards for house rules.")
                    wrapMode: Text.WordWrap
                    color: Theme.textMuted
                }
                Repeater {
                    model: root.visibleCards
                    delegate: CommanderRow { }
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    visible: root.fallbackCards.length > 0
                    text: qsTranslate("TournamentLobby", "Optional Piper fallback")
                    color: Theme.text
                    font.bold: true
                    wrapMode: Text.WordWrap
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    visible: root.fallbackCards.length > 0
                    text: qsTranslate("TournamentLobby", "You may add up to two extra Pipers as commanders, even if you did not draft them. Choose one color for each. They cannot go in the ordinary deck or sideboard; removing one returns it to this fallback section.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(11)
                    wrapMode: Text.WordWrap
                }
                Repeater {
                    model: root.fallbackCards
                    delegate: CommanderRow { }
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTranslate("TournamentLobby", "Choose up to two commanders from your drafted cards; choosing one adds it to your main deck. Eligibility and partner rules are reminders only. Use All drafted cards for house rules.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(11)
                    wrapMode: Text.WordWrap
                }
                InfoBanner {
                    Layout.fillWidth: true
                    tone: "warning"
                    message: root.advice.join("\n")
                }
            }
        }
        AppButton {
            objectName: "limitedCommanderDone"
            Layout.fillWidth: true
            variant: "primary"
            text: qsTranslate("TournamentLobby", "Done")
            onClicked: root.close()
        }
    }
}
