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
    readonly property url cardBackSource: Qt.resolvedUrl("../assets/card-back.jpg")

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
        return cardCatalogModel.tableImageSource(name, setCode || "",
                                                 collectorNumber || "")
    }

    function promptOptionLabel(responseId, label) {
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

    background: AppBackground { }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.size(18)
        spacing: Theme.size(12)

        Surface {
            Layout.fillWidth: true
            implicitHeight: Theme.size(72)
            color: Theme.surfaceElevated

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.size(20)
                anchors.rightMargin: Theme.size(14)
                spacing: Theme.size(18)

                ColumnLayout {
                    spacing: Theme.size(2)

                    Text {
                        textFormat: Text.PlainText
                        text: qsTr("Forge rules game")
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(18)
                        font.weight: Font.DemiBold
                    }

                    Text {
                        textFormat: Text.PlainText
                        text: root.rulesSession.active
                              ? qsTr("Turn %1 · %2")
                                .arg(root.rulesSession.turn)
                                .arg(root.stepLabel(root.rulesSession.step))
                              : qsTr("Waiting for the first rules snapshot…")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(11)
                    }
                }

                Item { Layout.fillWidth: true }

                StatusPill {
                    text: qsTr("Active · Seat %1")
                          .arg(root.rulesSession.activeSeat + 1)
                    statusColor: Theme.accent
                    visible: root.rulesSession.activeSeat >= 0
                }

                StatusPill {
                    text: qsTr("Priority · Seat %1")
                          .arg(root.rulesSession.prioritySeat + 1)
                    statusColor: Theme.primary
                    visible: root.rulesSession.prioritySeat >= 0
                }

                AppButton {
                    compact: true
                    text: qsTr("Leave room")
                    onClicked: root.wsModel.leaveRoom()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.size(12)

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.size(12)

                ListView {
                    id: playerList
                    Layout.fillWidth: true
                    implicitHeight: Theme.size(102)
                    orientation: ListView.Horizontal
                    spacing: Theme.size(10)
                    clip: true
                    model: root.rulesSession.players

                    delegate: Surface {
                        required property int seat
                        required property string name
                        required property string status
                        required property int life
                        required property string countersSummary
                        required property string manaSummary

                        width: Math.max(Theme.size(210),
                                        (playerList.width - Theme.size(10)) / 2)
                        height: playerList.height
                        color: seat === root.rulesSession.prioritySeat
                               ? Theme.primaryMuted : Theme.surface
                        border.color: seat === root.rulesSession.activeSeat
                                      ? Theme.accent : Theme.border

                        Column {
                            anchors.fill: parent
                            anchors.margins: Theme.size(14)
                            spacing: Theme.size(5)

                            Row {
                                width: parent.width
                                spacing: Theme.size(10)

                                Text {
                                    textFormat: Text.PlainText
                                    width: parent.width - lifeLabel.width
                                           - Theme.size(10)
                                    text: name + " · " + qsTr("Seat %1").arg(seat + 1)
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSize(13)
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                Text {
                                    textFormat: Text.PlainText
                                    id: lifeLabel
                                    text: qsTr("Life %1").arg(life)
                                    color: Theme.primary
                                    font.pixelSize: Theme.fontSize(16)
                                    font.weight: Font.Bold
                                }
                            }

                            Text {
                                textFormat: Text.PlainText
                                width: parent.width
                                text: [status, countersSummary, manaSummary]
                                      .filter(value => value.length > 0).join(" · ")
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSize(10)
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                Surface {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.backgroundRaised
                    clip: true

                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        visible: root.rulesSession.battlefieldCardCount === 0
                        text: qsTr("No permanents on the battlefield")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(12)
                    }

                    Flickable {
                        anchors.fill: parent
                        anchors.margins: Theme.size(14)
                        contentWidth: width
                        contentHeight: battlefieldFlow.implicitHeight
                        clip: true

                        Flow {
                            id: battlefieldFlow
                            width: parent.width
                            spacing: Theme.size(10)

                            Repeater {
                                id: battlefieldCards
                                model: root.rulesSession.battlefieldCards

                                delegate: Rectangle {
                                    required property string cardId
                                    required property string zone
                                    required property bool visibleIdentity
                                    required property string name
                                    required property string setCode
                                    required property string collectorNumber
                                    required property bool tapped
                                    required property bool faceDown
                                    required property bool attacking
                                    required property string power
                                    required property string toughness
                                    required property string countersSummary

                                    width: Theme.size(116)
                                    height: Theme.size(162)
                                    radius: Theme.radiusSmall
                                    color: Theme.surface
                                    border.width: attacking ? 3 : 1
                                    border.color: attacking ? Theme.error : Theme.borderStrong
                                    rotation: tapped ? 90 : 0

                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: Theme.size(3)
                                        asynchronous: true
                                        fillMode: Image.PreserveAspectFit
                                        source: visibleIdentity && !faceDown
                                                ? root.cardImage(name, setCode,
                                                                 collectorNumber)
                                                : root.cardBackSource
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: Theme.size(28)
                                        color: Theme.inactiveSelection

                                        Text {
                                            textFormat: Text.PlainText
                                            anchors.fill: parent
                                            anchors.margins: Theme.size(4)
                                            text: visibleIdentity && !faceDown
                                                  ? name : qsTr("Face-down card")
                                            color: Theme.text
                                            font.pixelSize: Theme.fontSize(9)
                                            elide: Text.ElideRight
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }

                                    ToolTip.visible: hover.hovered
                                    ToolTip.text: visibleIdentity && !faceDown
                                                  ? [name,
                                                     power.length > 0
                                                     ? power + "/" + toughness : "",
                                                     countersSummary]
                                                    .filter(value => value.length > 0)
                                                    .join(" · ")
                                                  : qsTr("Face-down card")
                                    HoverHandler { id: hover }
                                }
                            }
                        }
                    }
                }

                Surface {
                    Layout.fillWidth: true
                    implicitHeight: Theme.size(176)
                    color: Theme.surface
                    clip: true

                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        visible: root.rulesSession.visibleZoneCardCount === 0
                        text: qsTr("No visible cards outside the battlefield")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(11)
                    }

                    ListView {
                        id: visibleCards
                        anchors.fill: parent
                        anchors.margins: Theme.size(10)
                        orientation: ListView.Horizontal
                        spacing: Theme.size(8)
                        clip: true
                        model: root.rulesSession.zoneCards

                        delegate: Rectangle {
                            required property string zone
                            required property bool visibleIdentity
                            required property string name
                            required property string setCode
                            required property string collectorNumber
                            required property bool faceDown

                            width: Theme.size(96)
                            height: visibleCards.height
                            radius: Theme.radiusSmall
                            color: Theme.surfaceMuted
                            border.width: 1
                            border.color: Theme.border

                            Image {
                                anchors.fill: parent
                                anchors.margins: Theme.size(3)
                                asynchronous: true
                                fillMode: Image.PreserveAspectFit
                                source: visibleIdentity && !faceDown
                                        ? root.cardImage(name, setCode,
                                                         collectorNumber)
                                        : root.cardBackSource
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: Theme.size(30)
                                color: Theme.inactiveSelection

                                Text {
                                    textFormat: Text.PlainText
                                    anchors.fill: parent
                                    anchors.margins: Theme.size(4)
                                    text: root.zoneLabel(zone) + " · "
                                          + (visibleIdentity && !faceDown
                                             ? name : qsTr("Hidden card"))
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSize(8)
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.preferredWidth: Theme.size(270)
                Layout.fillHeight: true
                spacing: Theme.size(12)

                Surface {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.surface

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.size(14)
                        spacing: Theme.size(8)

                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("Zones")
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(14)
                            font.weight: Font.DemiBold
                        }

                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: Theme.size(5)
                            model: root.rulesSession.zones

                            delegate: Rectangle {
                                required property string zone
                                required property int ownerSeat
                                required property int count

                                width: ListView.view.width
                                height: Theme.size(38)
                                radius: Theme.radiusSmall
                                color: Theme.surfaceMuted

                                Text {
                                    textFormat: Text.PlainText
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.size(10)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("Seat %1 · %2")
                                          .arg(ownerSeat + 1)
                                          .arg(root.zoneLabel(zone))
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSize(10)
                                }

                                Text {
                                    textFormat: Text.PlainText
                                    anchors.right: parent.right
                                    anchors.rightMargin: Theme.size(10)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: count
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSize(11)
                                    font.weight: Font.Bold
                                }
                            }
                        }
                    }
                }

                Surface {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.size(200)
                    color: Theme.surfaceElevated

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.size(14)
                        spacing: Theme.size(8)

                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("Stack")
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(14)
                            font.weight: Font.DemiBold
                        }

                        ListView {
                            id: stackList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: Theme.size(5)
                            model: root.rulesSession.stack

                            delegate: Text {
                                textFormat: Text.PlainText
                                required property string name
                                required property int controllerSeat
                                required property string rulesText

                                width: ListView.view.width
                                text: name.length > 0
                                      ? name + " · "
                                        + qsTr("Seat %1").arg(controllerSeat + 1)
                                      : rulesText
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSize(10)
                                wrapMode: Text.Wrap
                            }
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            visible: stackList.count === 0
                            text: qsTr("The stack is empty")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(10)
                        }
                    }
                }
            }
        }

        Surface {
            Layout.fillWidth: true
            implicitHeight: promptContent.implicitHeight + Theme.size(24)
            color: root.rulesSession.promptPending
                   ? Theme.surfaceElevated : Theme.surface

            ColumnLayout {
                id: promptContent
                anchors.fill: parent
                anchors.margins: Theme.size(12)
                spacing: Theme.size(8)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.size(12)

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.size(3)

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: root.rulesSession.gameOver
                                  ? (root.rulesSession.hasWinner
                                     ? qsTr("Seat %1 wins the Forge game")
                                       .arg(root.rulesSession.winnerSeat + 1)
                                     : qsTr("The Forge game ended in a draw"))
                                  : root.rulesSession.promptPending
                                    ? root.rulesSession.promptTitle
                                    : qsTr("Waiting for Forge or another player…")
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(13)
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            visible: !root.rulesSession.gameOver
                                     && root.rulesSession.promptPending
                            text: root.rulesSession.promptSupported
                                  ? root.rulesSession.promptDetail
                                  : qsTr("This Forge decision is not supported by this Hexproof build: %1")
                                    .arg(root.rulesSession.promptKind)
                            color: root.rulesSession.promptSupported
                                   ? Theme.textSecondary : Theme.warning
                            font.pixelSize: Theme.fontSize(10)
                            elide: Text.ElideRight
                        }
                    }

                    ListView {
                        Layout.preferredWidth: Math.min(contentWidth, Theme.size(620))
                        Layout.preferredHeight: Theme.size(40)
                        orientation: ListView.Horizontal
                        spacing: Theme.size(8)
                        clip: true
                        model: root.rulesSession.promptOptions
                        visible: root.rulesSession.promptPending
                                 && root.rulesSession.promptSupported
                                 && root.rulesSession.promptKind !== "mulliganPutBack"
                                 && root.rulesSession.promptKind !== "chooseCards"
                                 && root.rulesSession.promptKind !== "reorder"
                                 && root.rulesSession.promptKind !== "chooseBoardTargets"
                                 && root.rulesSession.promptKind !== "chooseAttackers"
                                 && root.rulesSession.promptKind !== "chooseBlockers"
                                 && root.rulesSession.promptKind !== "chooseBoolean"
                                 && root.rulesSession.promptKind !== "chooseNumber"
                                 && root.rulesSession.promptKind !== "chooseColor"
                                 && root.rulesSession.promptKind !== "chooseFromSelection"

                        delegate: AppButton {
                            required property string responseId
                            required property string label

                            compact: true
                            text: root.promptOptionLabel(responseId, label)
                            onClicked: root.wsModel.respondRulesPrompt(
                                           root.rulesSession.promptId, responseId)
                        }
                    }

                    AppButton {
                        compact: true
                        visible: root.rulesSession.gameOver
                        text: qsTr("Return to room")
                        onClicked: root.wsModel.returnToRoom()
                    }
                }

                RulesCardSelectionPrompt {
                    Layout.fillWidth: true
                    visible: root.rulesSession.promptPending
                             && root.rulesSession.promptSupported
                             && (root.rulesSession.promptKind === "mulliganPutBack"
                                 || root.rulesSession.promptKind === "chooseCards")
                    wsModel: root.wsModel
                    cardCatalogModel: root.cardCatalogModel
                    cardModel: root.rulesSession.promptCards
                    promptId: root.rulesSession.promptId
                    minimumSelections: root.rulesSession.promptMinCardSelections
                    maximumSelections: root.rulesSession.promptMaxCardSelections
                    confirmationText: root.rulesSession.promptKind === "mulliganPutBack"
                                      ? qsTr("Put on library bottom")
                                      : qsTr("Confirm cards")
                }

                RulesOrderPrompt {
                    Layout.fillWidth: true
                    visible: root.rulesSession.promptPending
                             && root.rulesSession.promptSupported
                             && root.rulesSession.promptKind === "reorder"
                    wsModel: root.wsModel
                    cardCatalogModel: root.cardCatalogModel
                    orderModel: root.rulesSession.promptOrderItems
                    promptId: root.rulesSession.promptId
                }

                RulesTargetSelectionPrompt {
                    Layout.fillWidth: true
                    visible: root.rulesSession.promptPending
                             && root.rulesSession.promptSupported
                             && root.rulesSession.promptKind === "chooseBoardTargets"
                    wsModel: root.wsModel
                    cardCatalogModel: root.cardCatalogModel
                    targetModel: root.rulesSession.promptTargets
                    promptId: root.rulesSession.promptId
                    minimumSelections: root.rulesSession.promptMinSelections
                    maximumSelections: root.rulesSession.promptMaxSelections
                    cancellable: root.rulesSession.promptCancellable
                }

                RulesCombatAssignmentPrompt {
                    Layout.fillWidth: true
                    visible: root.rulesSession.promptPending
                             && root.rulesSession.promptSupported
                             && root.rulesSession.promptKind === "chooseAttackers"
                    wsModel: root.wsModel
                    cardCatalogModel: root.cardCatalogModel
                    sourceModel: root.rulesSession.promptCombat
                    promptId: root.rulesSession.promptId
                    assignmentKind: "attackers"
                }

                RulesCombatAssignmentPrompt {
                    Layout.fillWidth: true
                    visible: root.rulesSession.promptPending
                             && root.rulesSession.promptSupported
                             && root.rulesSession.promptKind === "chooseBlockers"
                    wsModel: root.wsModel
                    cardCatalogModel: root.cardCatalogModel
                    sourceModel: root.rulesSession.promptCombat
                    promptId: root.rulesSession.promptId
                    assignmentKind: "blockers"
                }

                RulesScalarChoicePrompt {
                    Layout.fillWidth: true
                    visible: root.rulesSession.promptPending
                             && root.rulesSession.promptSupported
                             && (root.rulesSession.promptKind === "chooseBoolean"
                                 || root.rulesSession.promptKind === "chooseColor"
                                 || root.rulesSession.promptKind === "chooseFromSelection")
                    wsModel: root.wsModel
                    choiceModel: root.rulesSession.promptChoices
                    promptId: root.rulesSession.promptId
                    minimumTotal: root.rulesSession.promptMinChoiceTotal
                    maximumTotal: root.rulesSession.promptMaxChoiceTotal
                }

                RulesNumberPrompt {
                    Layout.fillWidth: true
                    visible: root.rulesSession.promptPending
                             && root.rulesSession.promptSupported
                             && root.rulesSession.promptKind === "chooseNumber"
                    wsModel: root.wsModel
                    promptId: root.rulesSession.promptId
                    minimum: root.rulesSession.promptMinNumber
                    maximum: root.rulesSession.promptMaxNumber
                }
            }
        }
    }
}
