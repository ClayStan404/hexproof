// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root
    readonly property var appWindow: ApplicationWindow.window
    property var simulator: draftSimulator
    property var catalog: cardCatalog
    property var library: deckLibrary
    readonly property var session: simulator.state
    property var sets: []
    property var cubes: []
    readonly property bool cubeMode: sourceSelector.currentIndex === 1
    readonly property var selectedCube: cubeSelector.currentIndex >= 0
        ? cubes[cubeSelector.currentIndex] || ({}) : ({})
    readonly property int seats: seatSelector.currentIndex + 2
    readonly property bool sourceReady: cubeMode
        ? !!selectedCube.deckId && selectedCube.mainCount >= seats * 45 : setPicker.hasSelection

    background: AppBackground { }
    Component.onCompleted: reloadSources()

    // These commands are confined to the local simulator. Online models are never used.
    QtObject {
        id: localCommands
        readonly property bool connected: true
        readonly property string serverUrl: "local-draft"
        readonly property string participantId: "0"
        function pickLimitedCard(instanceId) { root.simulator.pick(instanceId) }
        function submitLimitedDeck(name, ids, lands) {
            root.simulator.saveDeck(qsTr("Draft practice — %1").arg(root.session.product.name), ids, lands)
        }
    }
    QtObject {
        id: constructionStore
        function loadDraft(server, eventId, participantId) { return root.simulator.constructionDraft }
        function saveDraft(server, eventId, participantId, value) { root.simulator.constructionDraft = value }
        function removeDraft(server, eventId, participantId) { root.simulator.constructionDraft = ({}) }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pageMargin
        spacing: Theme.size(10)

        ScreenHeader {
            Layout.fillWidth: true
            title: qsTr("Draft practice")
            subtitle: root.session.active ? root.session.product.name
                : qsTr("Practice offline with automated seats, then build and save your deck")
            onBackRequested: root.appWindow.popScreen()
        }
        RowLayout {
            Layout.fillWidth: true
            visible: root.session.active
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTr("Local practice · Progress lasts until you close the app")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(11)
                wrapMode: Text.WordWrap
            }
            AppButton {
                objectName: "newDraftPracticeButton"
                compact: true
                text: qsTr("New draft")
                onClicked: restartDialog.open()
            }
        }
        InfoBanner {
            Layout.fillWidth: true
            message: root.simulator.lastError
        }

        ScrollView {
            id: setupScroll
            objectName: "draftPracticeSetup"
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.session.active
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: setupScroll.availableWidth
                spacing: Theme.size(16)

                Surface {
                    Layout.fillWidth: true
                    implicitHeight: setupControls.implicitHeight + Theme.size(40)
                    elevated: true
                    ColumnLayout {
                        id: setupControls
                        anchors.fill: parent
                        anchors.margins: Theme.size(20)
                        spacing: Theme.size(12)
                        SegmentedControl {
                            id: sourceSelector
                            objectName: "draftPracticeSourceSelector"
                            Layout.fillWidth: true
                            options: [qsTr("Set draft"), qsTr("Cube draft")]
                            onActivated: index => currentIndex = index
                        }
                        LimitedSetPicker {
                            id: setPicker
                            Layout.fillWidth: true
                            visible: !root.cubeMode
                            sets: root.sets
                        }
                        AppComboBox {
                            id: cubeSelector
                            objectName: "draftPracticeCubeSelector"
                            Layout.fillWidth: true
                            visible: root.cubeMode
                            model: root.cubes
                            textRole: "deckName"
                            valueRole: "deckId"
                        }
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: root.cubeMode
                                ? qsTr("Choose a saved Cube with at least %1 cards, 45 per seat.").arg(root.seats * 45)
                                : setPicker.hasSelection && !setPicker.selectedSet.authentic
                                  ? qsTr("Approximate rarity collation — not an exact retail pack.")
                                  : qsTr("Three boosters per seat, passing left, right, then left.")
                            color: !root.sourceReady || (!root.cubeMode && setPicker.hasSelection && !setPicker.selectedSet.authentic)
                                ? Theme.warning : Theme.textSecondary
                            font.pixelSize: Theme.fontSize(12)
                            wrapMode: Text.WordWrap
                        }
                        AppButton {
                            visible: root.cubeMode
                            text: qsTr("Open deck library")
                            onClicked: root.appWindow.pushScreen("screens/DeckLibrary.qml")
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("Seats (including you)")
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(12)
                        }
                        AppComboBox {
                            id: seatSelector
                            objectName: "draftPracticeSeatSelector"
                            Layout.fillWidth: true
                            model: [2, 3, 4, 5, 6, 7, 8]
                            currentIndex: 6
                        }
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: qsTr("You pick one card at a time. Bots use basic rarity, color and mana-curve preferences; they do not evaluate card strength or synergies. There is no pick timer.")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(12)
                            wrapMode: Text.WordWrap
                        }
                        AppButton {
                            objectName: "startDraftPracticeButton"
                            Layout.fillWidth: true
                            variant: "primary"
                            text: qsTr("Start practice")
                            enabled: root.sourceReady
                            onClicked: {
                                const product = root.cubeMode ? root.library.cubeProduct(root.selectedCube.deckId)
                                    : root.catalog.limitedProduct(setPicker.selectedSet.productId)
                                root.simulator.start(product, root.seats)
                            }
                        }
                    }
                }
            }
        }
        LimitedDraftView {
            objectName: "draftPracticeDraftView"
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.session.stage === "draft"
            limitedModel: root.session
            tournamentModel: localCommands
            wsModel: localCommands
            cardCatalogModel: root.catalog
            draftStore: null
        }
        LimitedDeckBuilder {
            objectName: "draftPracticeDeckBuilder"
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.session.stage === "deck_building"
            limitedModel: root.session
            wsModel: localCommands
            cardCatalogModel: root.catalog
            participantId: "0"
            draftStore: constructionStore
            localPractice: true
        }
    }
    ConfirmDialog {
        id: restartDialog
        objectName: "restartDraftPracticeDialog"
        titleText: qsTr("Start a new draft?")
        message: qsTr("This ends the current practice and discards unsaved picks and deck edits. Decks already saved to your library remain available.")
        confirmText: qsTr("New draft")
        onConfirmed: root.simulator.reset()
    }
    Connections {
        target: root.catalog
        function onCatalogChanged() { root.reloadSources() }
    }
    Connections {
        target: root.library
        function onCountChanged() { root.reloadSources() }
    }
    function reloadSources() {
        sets = catalog.limitedSets()
        cubes = library.matchDecks("cube", true)
    }
}
