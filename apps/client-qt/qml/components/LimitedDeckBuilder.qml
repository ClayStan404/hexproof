// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "TournamentLobby"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    required property var limitedModel
    required property var wsModel
    required property var cardCatalogModel
    property var selectedCards: ({})
    property int selectionRevision: 0
    property var basics: ({"Plains": 0, "Island": 0, "Swamp": 0,
                           "Mountain": 0, "Forest": 0, "Wastes": 0})
    property int basicsRevision: 0
    property bool restoredSubmittedDeck: false
    readonly property var basicNames: ["Plains", "Island", "Swamp",
                                       "Mountain", "Forest", "Wastes"]
    readonly property int selectedCount: countSelected() + countBasics()

    Component.onCompleted: {
        restoreSubmission()
        cachePoolCards()
    }

    Connections {
        target: root.limitedModel
        function onSnapshotChanged() {
            root.restoreSubmission()
            root.cachePoolCards()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.size(10)

        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(2)
                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Build your limited deck")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(18)
                    font.weight: Font.DemiBold
                }
                Text {
                    textFormat: Text.PlainText
                    text: qsTr("%1 main · %2 unselected sideboard · unlimited basic lands")
                          .arg(root.selectedCount)
                          .arg(Math.max(0, root.limitedModel.pool.length - root.countSelected()))
                    color: root.selectedCount >= 40 ? Theme.success : Theme.warning
                    font.pixelSize: Theme.fontSize(11)
                }
            }

            StatusPill {
                visible: root.limitedModel.deckSubmitted
                text: qsTr("Deck submitted")
                statusColor: Theme.success
            }

            AppButton {
                variant: "primary"
                text: root.limitedModel.deckSubmitted
                      ? qsTr("Update deck") : qsTr("Submit deck")
                enabled: root.selectedCount >= 40
                         && root.limitedModel.pool.length > 0
                onClicked: root.submit()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(6)

            Repeater {
                model: root.basicNames

                delegate: Surface {
                    id: basicControl
                    required property string modelData
                    Layout.fillWidth: true
                    implicitHeight: Theme.size(50)
                    color: Theme.surfaceMuted

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.size(6)
                        spacing: Theme.size(4)
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: basicControl.modelData + " "
                                  + root.basicValue(basicControl.modelData)
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSize(10)
                            elide: Text.ElideRight
                        }
                        AppButton {
                            compact: true
                            text: "−"
                            enabled: root.basicValue(basicControl.modelData) > 0
                            onClicked: root.adjustBasic(basicControl.modelData, -1)
                        }
                        AppButton {
                            compact: true
                            text: "+"
                            onClicked: root.adjustBasic(basicControl.modelData, 1)
                        }
                    }
                }
            }
        }

        Surface {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.surfaceMuted

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                visible: root.limitedModel.pool.length === 0
                text: qsTr("Only the participant can see and build from this pool.")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(13)
            }

            ScrollView {
                anchors.fill: parent
                anchors.margins: Theme.size(10)
                visible: root.limitedModel.pool.length > 0
                contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                Flow {
                    width: parent.width
                    spacing: Theme.size(8)

                    Repeater {
                        model: root.limitedModel.pool

                        delegate: Rectangle {
                            id: poolCard
                            required property var modelData
                            width: Theme.size(116)
                            height: Theme.size(168)
                            radius: Theme.radiusSmall
                            color: Theme.surfaceElevated
                            border.width: root.cardSelected(modelData.instanceId) ? 3 : 1
                            border.color: root.cardSelected(modelData.instanceId)
                                          ? Theme.primary : Theme.border
                            opacity: root.cardSelected(modelData.instanceId) ? 1.0 : 0.68
                            clip: true

                            Image {
                                anchors.fill: parent
                                anchors.margins: Theme.size(2)
                                asynchronous: true
                                fillMode: Image.PreserveAspectFit
                                source: root.cardImageSource(poolCard.modelData)
                            }

                            TapHandler {
                                onTapped: root.toggleCard(poolCard.modelData.instanceId)
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Theme.size(5)
                                width: Theme.size(24)
                                height: width
                                radius: width / 2
                                color: root.cardSelected(poolCard.modelData.instanceId)
                                       ? Theme.primary : Theme.surfaceElevated
                                Text {
                                    textFormat: Text.PlainText
                                    anchors.centerIn: parent
                                    text: root.cardSelected(poolCard.modelData.instanceId) ? "✓" : "+"
                                    color: root.cardSelected(poolCard.modelData.instanceId)
                                           ? Theme.primaryInk : Theme.text
                                    font.pixelSize: Theme.fontSize(11)
                                    font.weight: Font.Bold
                                }
                            }
                        }
                    }
                }
            }
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.limitedModel.allDecksSubmitted
                  ? qsTr("Every deck is submitted. The organizer can publish round one.")
                  : qsTr("Waiting for all participants: %1")
                    .arg(root.submissionProgress())
            color: root.limitedModel.allDecksSubmitted ? Theme.success : Theme.textMuted
            font.pixelSize: Theme.fontSize(11)
        }
    }

    function cardSelected(instanceId) {
        const revision = selectionRevision
        return !!selectedCards[instanceId] || revision < 0
    }

    function cardImageSource(card) {
        if (!card || !card.name)
            return ""
        void root.cardCatalogModel.imageRevision
        return root.cardCatalogModel.tableImageSource(
                    card.name, card.setCode || "", card.collectorNumber || "")
    }

    function cachePoolCards() {
        if (root.cardCatalogModel
                && typeof root.cardCatalogModel.cacheCardsIncrementally
                   === "function") {
            root.cardCatalogModel.cacheCardsIncrementally(
                        root.limitedModel.pool || [])
        }
    }

    function toggleCard(instanceId) {
        const changed = Object.assign({}, selectedCards)
        if (changed[instanceId])
            delete changed[instanceId]
        else
            changed[instanceId] = true
        selectedCards = changed
        selectionRevision++
    }

    function countSelected() {
        const revision = selectionRevision
        return Object.keys(selectedCards).length + (revision < 0 ? 0 : 0)
    }

    function basicValue(name) {
        const revision = basicsRevision
        return Number(basics[name] || 0) + (revision < 0 ? 0 : 0)
    }

    function countBasics() {
        let total = 0
        for (let index = 0; index < basicNames.length; ++index)
            total += basicValue(basicNames[index])
        return total
    }

    function adjustBasic(name, amount) {
        const changed = Object.assign({}, basics)
        changed[name] = Math.max(0, Number(changed[name] || 0) + amount)
        basics = changed
        basicsRevision++
    }

    function submit() {
        const ids = Object.keys(selectedCards)
        const lands = []
        for (let index = 0; index < basicNames.length; ++index) {
            const count = basicValue(basicNames[index])
            if (count > 0)
                lands.push({"name": basicNames[index], "count": count})
        }
        wsModel.submitLimitedDeck(qsTr("Limited deck"), ids, lands)
    }

    function submissionProgress() {
        let submitted = 0
        for (let index = 0; index < limitedModel.participants.length; ++index) {
            if (limitedModel.participants[index].deckSubmitted)
                submitted++
        }
        return submitted + " / " + limitedModel.participants.length
    }

    function restoreSubmission() {
        if (restoredSubmittedDeck || !limitedModel.deckSubmitted)
            return
        const restoredCards = {}
        for (let index = 0; index < limitedModel.mainboardInstanceIds.length; ++index)
            restoredCards[limitedModel.mainboardInstanceIds[index]] = true
        const restoredBasics = {"Plains": 0, "Island": 0, "Swamp": 0,
                                "Mountain": 0, "Forest": 0, "Wastes": 0}
        for (let index = 0; index < limitedModel.basicLands.length; ++index) {
            const land = limitedModel.basicLands[index]
            if (restoredBasics[land.name] !== undefined)
                restoredBasics[land.name] = Number(land.count || 0)
        }
        selectedCards = restoredCards
        basics = restoredBasics
        selectionRevision++
        basicsRevision++
        restoredSubmittedDeck = true
    }
}
