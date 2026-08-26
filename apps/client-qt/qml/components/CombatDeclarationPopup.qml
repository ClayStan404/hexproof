// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "Table"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    property string declarationKind: ""
    property var cards: []
    property string targetCardId: ""
    property int targetSeat: -1
    property string targetLabel: ""
    property var tapSelections: ({})
    readonly property bool attackMode: declarationKind === "attack"
    readonly property bool hasWarnings: cards.some(function(card) {
        return card.tapped === true || card.assistCreature !== true
    })
    signal declarationRequested(string kind, var sourceCardIds,
                                string targetCardId, int targetSeat,
                                var tappedSourceCardIds)

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(560), parent.width - Theme.size(48))
    height: Math.min(implicitHeight, parent.height - Theme.size(56))
    implicitHeight: Math.min(Theme.size(620), contentColumn.implicitHeight
                             + topPadding + bottomPadding)
    padding: Theme.size(22)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    Overlay.modal: Rectangle { color: "#A6050B09" }

    background: Rectangle {
        color: Theme.surfaceElevated
        radius: Theme.radiusLarge
        border.width: 1
        border.color: Theme.borderStrong
    }

    function showFor(kind, sourceCards, targetId, seat, label) {
        declarationKind = kind
        cards = sourceCards ? sourceCards.slice() : []
        targetCardId = targetId ? targetId : ""
        targetSeat = seat !== undefined ? seat : -1
        targetLabel = label ? label : ""
        const selections = ({})
        if (kind === "attack") {
            for (let index = 0; index < cards.length; ++index)
                selections[cards[index].id] = cards[index].tapped !== true
        }
        tapSelections = selections
        open()
    }

    function sourceCardIds() {
        const result = []
        for (let index = 0; index < cards.length; ++index)
            result.push(cards[index].id)
        return result
    }

    function tappedSourceCardIds() {
        const result = []
        if (!attackMode)
            return result
        for (let index = 0; index < cards.length; ++index) {
            if (tapSelections[cards[index].id] === true)
                result.push(cards[index].id)
        }
        return result
    }

    function setTapSelected(cardId, selected) {
        const next = Object.assign({}, tapSelections)
        next[cardId] = selected
        tapSelections = next
    }

    onClosed: {
        declarationKind = ""
        cards = []
        targetCardId = ""
        targetSeat = -1
        targetLabel = ""
        tapSelections = ({})
    }

    contentItem: ColumnLayout {
        id: contentColumn
        spacing: Theme.size(14)

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.attackMode
                  ? qsTr("Declare attackers") : qsTr("Declare blockers")
            color: Theme.text
            font.pixelSize: Theme.fontSize(20)
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: (root.attackMode ? qsTr("Attack") : qsTr("Block"))
                  + " · " + root.targetLabel
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(12)
            wrapMode: Text.WordWrap
        }

        Surface {
            Layout.fillWidth: true
            visible: root.hasWarnings
            implicitHeight: warningText.implicitHeight + Theme.size(18)
            color: Qt.rgba(Theme.warning.r, Theme.warning.g,
                           Theme.warning.b, 0.14)
            border.color: Theme.warning

            Text {
                textFormat: Text.PlainText
                id: warningText
                anchors.fill: parent
                anchors.margins: Theme.size(9)
                text: qsTr("Some selected cards are tapped or are not printed as creatures. Card effects may still allow this declaration, so you can continue.")
                color: Theme.text
                font.pixelSize: Theme.fontSize(10)
                wrapMode: Text.WordWrap
            }
        }

        ListView {
            id: combatCards
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(
                                        Theme.size(300),
                                        contentHeight)
            Layout.minimumHeight: Math.min(
                                      Theme.size(100),
                                      contentHeight)
            model: root.cards
            spacing: Theme.size(6)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Surface {
                id: combatCardRow
                required property var modelData
                required property int index
                width: ListView.view.width
                height: Theme.size(68)
                color: Theme.surfaceMuted

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.size(9)
                    spacing: Theme.size(10)

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.size(2)

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: combatCardRow.modelData.name
                                  ? combatCardRow.modelData.name
                                  : qsTr("Card")
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(12)
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: combatCardRow.modelData.tapped === true
                                  ? qsTr("Tapped — review before continuing")
                                  : (combatCardRow.modelData.assistCreature === true
                                     ? combatCardRow.modelData.assistTypeLine
                                     : qsTr("Printed type is not Creature — review before continuing"))
                            color: combatCardRow.modelData.tapped === true
                                   || combatCardRow.modelData.assistCreature !== true
                                   ? Theme.warning : Theme.textMuted
                            font.pixelSize: Theme.fontSize(9)
                            elide: Text.ElideRight
                        }
                    }

                    CheckBox {
                        visible: root.attackMode
                        enabled: combatCardRow.modelData.tapped !== true
                        text: qsTr("Tap")
                        checked: root.tapSelections[
                                     combatCardRow.modelData.id] === true
                        onClicked: root.setTapSelected(
                                       combatCardRow.modelData.id,
                                       checked)
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Clear this for vigilance or another effect that keeps the attacker untapped.")
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(10)

            Item { Layout.fillWidth: true }

            AppButton {
                objectName: "cancelCombatDeclarationButton"
                compact: true
                variant: "ghost"
                text: qsTr("Cancel")
                onClicked: root.close()
            }

            AppButton {
                objectName: "confirmCombatDeclarationButton"
                compact: true
                variant: "primary"
                text: root.attackMode
                      ? qsTr("Declare attack") : qsTr("Declare block")
                enabled: root.cards.length > 0
                onClicked: {
                    const kind = root.declarationKind
                    const sourceIds = root.sourceCardIds()
                    const targetId = root.targetCardId
                    const seat = root.targetSeat
                    const tappedIds = root.tappedSourceCardIds()
                    root.close()
                    root.declarationRequested(
                                kind, sourceIds, targetId,
                                seat, tappedIds)
                }
            }
        }
    }
}
