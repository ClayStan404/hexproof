// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root

    required property var wsModel
    required property var cardCatalogModel
    readonly property var rulesSession: wsModel.rulesSession
    readonly property var roomSession: wsModel.roomSession
    readonly property url cardBackSource:
        Qt.resolvedUrl("../assets/card-back.jpg")
    readonly property int localSeat:
        roomSession.role === "player" ? roomSession.seatIndex : -1
    readonly property bool compactLayout: Theme.isCompactWidth(width)
    readonly property real actionRailWidth:
        Theme.size(compactLayout ? 120 : 144)
    readonly property real sharedZoneRailWidth: Theme.size(92)
    readonly property real stateRailWidth:
        Theme.size(compactLayout ? 148 : 176)
    readonly property real battlefieldCardWidth: Theme.size(80)
    readonly property real battlefieldCardHeight:
        Math.round(battlefieldCardWidth * 88 / 63)
    readonly property real handAreaHeight: Theme.size(176)
    readonly property real handCardWidth: Theme.size(86)
    readonly property real handCardHeight:
        Math.round(handCardWidth * 88 / 63)
    readonly property real zoneDockWidth:
        Math.min(Theme.size(270), width * 0.35)

    function zoneLabel(zone) {
        switch (zone) {
        case "library": return qsTr("Library")
        case "hand": return qsTr("Hand")
        case "battlefield": return qsTr("Battlefield")
        case "graveyard": return qsTr("Graveyard")
        case "exile": return qsTr("Exile")
        case "command": return qsTr("Command zone")
        default: return zone
        }
    }

    function stepLabel(step) {
        switch (step) {
        case "untap": return qsTr("Untap")
        case "upkeep": return qsTr("Upkeep")
        case "draw": return qsTr("Draw")
        case "main1": return qsTr("First main phase")
        case "begin_combat": return qsTr("Beginning of combat")
        case "declare_attackers": return qsTr("Declare attackers")
        case "declare_blockers": return qsTr("Declare blockers")
        case "combat_damage": return qsTr("Combat damage")
        case "end_combat": return qsTr("End of combat")
        case "main2": return qsTr("Second main phase")
        case "end": return qsTr("End step")
        case "cleanup": return qsTr("Cleanup")
        default: return step.length > 0 ? step : qsTr("Waiting for Forge")
        }
    }

    function cardImage(name, setCode, collectorNumber) {
        if (!name || !cardCatalogModel
                || typeof cardCatalogModel.tableImageSource !== "function")
            return ""
        void cardCatalogModel.imageRevision
        return cardCatalogModel.tableImageSource(
                    name, setCode || "", collectorNumber || "")
    }

    function promptOptionLabel(kind, responseId, label) {
        if (kind === "diceRolled" && responseId === "$ack")
            return qsTr("Roll dice")
        switch (responseId) {
        case "$ack": return qsTr("Continue")
        case "$pass": return qsTr("Pass priority")
        case "$pass-stack": return qsTr("Resolve current stack")
        case "$keep": return qsTr("Keep hand")
        case "$mulligan": return qsTr("Take a mulligan")
        case "$pay": return qsTr("Confirm payment")
        case "$auto-pay": return qsTr("Auto-pay")
        case "$cancel": return qsTr("Cancel")
        default: return label
        }
    }

    function promptTitle(kind, title) {
        if (kind === "diceRolled")
            return qsTr("Roll to determine the first player")
        return title
    }

    function promptDetail(kind, detail) {
        if (kind === "diceRolled")
            return qsTr("Forge will roll to determine who plays first.")
        return detail
    }

    function handCardActions(cardId) {
        if (localSeat < 0 || !rulesSession.promptPending
                || rulesSession.promptKind !== "chooseAction"
                || typeof rulesSession.castActionsForCard !== "function") {
            return []
        }
        return rulesSession.castActionsForCard(cardId)
    }

    function canDragHandCard(cardId) {
        return !cardActionPicker.opened
                && handCardActions(cardId).length > 0
    }

    function playDraggedHandCard(cardId, cardName) {
        const actions = handCardActions(cardId)
        if (actions.length === 0)
            return false
        if (actions.length === 1) {
            wsModel.respondRulesPrompt(
                        rulesSession.promptId, actions[0].responseId)
        } else {
            cardActionPicker.showFor(cardId, cardName, actions)
        }
        return true
    }

    function playDraggedHandCardSource(source) {
        if (!source)
            return false
        return playDraggedHandCard(source.cardId, source.name)
    }

    function openConcedeConfirmation() {
        rulesConcedeConfirmation.open()
    }

    background: Rectangle { color: Theme.surfaceMuted }

    RowLayout {
        objectName: "rulesGameLayout"
        anchors.fill: parent
        spacing: 0

        RulesTableActionRail {
            tableController: root
        }

        RulesStackRail {
            visible: !root.compactLayout
            tableController: root
        }

        ColumnLayout {
            objectName: "rulesPlayArea"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Item {
                objectName: "rulesBattlefieldHost"
                Layout.fillWidth: true
                Layout.fillHeight: true

                RulesBattlefieldView {
                    anchors.fill: parent
                    tableController: root
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    visible: !root.rulesSession.active
                    text: qsTr("Waiting for the first rules snapshot…")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(12)
                }

                RulesPromptPanel {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Theme.size(10)
                    z: 500
                    tableController: root
                }
            }

            RulesHandArea {
                tableController: root
            }
        }

        RulesStateRail {
            visible: !root.compactLayout
            tableController: root
        }
    }

    Popup {
        id: cardActionPicker

        property string cardId: ""
        property string cardName: ""
        property var actions: []

        objectName: "rulesCardActionPicker"
        parent: Overlay.overlay
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: Math.min(Theme.size(460), parent.width - Theme.size(48))
        padding: Theme.size(20)
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

        function showFor(cardId, cardName, actions) {
            this.cardId = cardId
            this.cardName = cardName
            this.actions = actions
            open()
        }

        function submit(responseId) {
            const currentActions = root.handCardActions(cardId)
            for (let index = 0; index < currentActions.length; ++index) {
                if (currentActions[index].responseId !== responseId)
                    continue
                const promptId = root.rulesSession.promptId
                close()
                root.wsModel.respondRulesPrompt(promptId, responseId)
                return
            }
            close()
        }

        contentItem: ColumnLayout {
            spacing: Theme.size(12)

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: cardActionPicker.cardName.length > 0
                      ? qsTr("Choose how to play %1")
                        .arg(cardActionPicker.cardName)
                      : qsTr("Choose how to play this card")
                color: Theme.text
                font.pixelSize: Theme.fontSize(17)
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: cardActionPicker.actions

                delegate: AppButton {
                    required property var modelData

                    objectName: "rulesCardAction-" + modelData.responseId
                    Layout.fillWidth: true
                    text: modelData.label
                    onClicked: cardActionPicker.submit(modelData.responseId)
                }
            }

            AppButton {
                Layout.alignment: Qt.AlignRight
                compact: true
                variant: "ghost"
                text: qsTr("Cancel")
                onClicked: cardActionPicker.close()
            }
        }

        Connections {
            target: root.rulesSession

            function onPromptChanged() {
                cardActionPicker.close()
            }
        }
    }

    ConfirmDialog {
        id: rulesConcedeConfirmation

        objectName: "rulesConcedeConfirmation"
        titleText: qsTr("Concede this Forge game?")
        message: qsTr("Forge will apply the concession immediately. This cannot be undone.")
        confirmText: qsTr("Concede")
        dangerous: true
        onConfirmed: root.wsModel.concede()
    }
}
