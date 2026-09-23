// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root

    readonly property var appWindow: ApplicationWindow.window
    property bool limitedOnly: false
    property var wsModel
    property var cardCatalogModel
    property var deckLibraryModel
    readonly property var hub: wsModel ? wsModel : ws
    readonly property var catalog: cardCatalogModel ? cardCatalogModel : cardCatalog
    readonly property var decks: deckLibraryModel ? deckLibraryModel
                                : (typeof deckLibrary !== "undefined" ? deckLibrary : null)
    readonly property var cubeDecks: {
        if (!root.decks)
            return []
        void root.decks.count
        void root.decks.currentDeckId
        return root.decks.matchDecks("cube", true)
    }
    readonly property var selectedCube: cubeSelector.currentIndex >= 0
                                       ? root.cubeDecks[cubeSelector.currentIndex] || ({}) : ({})
    readonly property bool cubeReady: !!root.selectedCube.deckId
                                     && root.selectedCube.exactPrintings === true
                                     && Number(root.selectedCube.mainCount) >= capField.numberValue() * 45

    readonly property var formatOptions: [
        {"label": I18n.tournamentFormatLabel("Standard"),
         "value": "Standard"},
        {"label": I18n.tournamentFormatLabel("Pioneer"),
         "value": "Pioneer"},
        {"label": I18n.tournamentFormatLabel("Modern"),
         "value": "Modern"},
        {"label": I18n.tournamentFormatLabel("Legacy"),
         "value": "Legacy"},
        {"label": I18n.tournamentFormatLabel("Vintage"),
         "value": "Vintage"},
        {"label": I18n.tournamentFormatLabel("Pauper"),
         "value": "Pauper"},
        {"label": I18n.tournamentFormatLabel("Duel Commander"),
         "value": "Duel Commander"}
    ]
    readonly property var eventOptions: limitedOnly ? [
        {"label": qsTr("Set sealed"), "value": "set_sealed"},
        {"label": qsTr("Set draft"), "value": "set_draft"}
    ] : [
        {"label": qsTr("Constructed"), "value": "constructed"},
        {"label": qsTr("Set sealed"), "value": "set_sealed"},
        {"label": qsTr("Set draft"), "value": "set_draft"},
        {"label": qsTr("Cube draft"), "value": "cube_draft"}
    ]
    readonly property bool isLimited: eventSelector.currentValue !== "constructed"
    readonly property bool isCube: eventSelector.currentValue === "cube_draft"
    readonly property bool isDraft: eventSelector.currentValue === "set_draft" || isCube
    property var limitedSets: []
    property string matchMode: "bo3"
    property string rulesMode: "manual"
    readonly property bool rulesAvailable: rulesMode !== "forge" || root.hub.forgeRulesAvailable === true

    background: AppBackground { }
    Component.onCompleted: limitedSets = root.catalog.limitedSets()

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: Theme.size(22)
        anchors.bottomMargin: Theme.size(28)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        spacing: Theme.size(16)

        ScreenHeader {
            Layout.fillWidth: true
            title: root.limitedOnly ? qsTr("Create Limited tournament") : qsTr("Create tournament")
            subtitle: root.limitedOnly
                      ? qsTr("Open pools, build 40-card decks, then play Swiss rounds with standings")
                      : qsTr("Individual Swiss · choose manual tabletop or Forge rules")
            onBackRequested: root.appWindow.popScreen()
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.isLimited
            Item { Layout.fillWidth: true }
            AppButton {
                compact: true
                variant: "ghost"
                text: qsTr("Pack simulator")
                onClicked: root.appWindow.pushScreen("screens/LimitedHub.qml")
            }
        }

        Flickable {
            id: formBody
            objectName: root.limitedOnly ? "limitedRoomCreateBody" : "tournamentCreateBody"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: Math.max(height, formCard.height)
            function finishBoundaryScroll() {
                // Native wheel gestures can retain motion after reaching the
                // boundary and consume the next press on the submit button.
                if (moving && !dragging && !flicking && (atYBeginning || atYEnd))
                    cancelFlick()
            }
            onAtYBeginningChanged: if (atYBeginning) Qt.callLater(finishBoundaryScroll)
            onAtYEndChanged: if (atYEnd) Qt.callLater(finishBoundaryScroll)
            ScrollBar.vertical: ScrollBar {
                policy: formBody.contentHeight > formBody.height
                        ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            }

            Surface {
                id: formCard
                objectName: root.limitedOnly ? "limitedRoomCreateCard" : "tournamentCreateCard"
                width: Math.min(Theme.size(720), formBody.width - Theme.size(48))
                implicitHeight: form.implicitHeight + Theme.size(60)
                height: implicitHeight
                x: Math.max(0, Math.round((formBody.width - width) / 2))
                elevated: true

                ColumnLayout {
                    id: form
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.size(30)
                    spacing: Theme.size(10)

                    Text {
                        textFormat: Text.PlainText
                        text: qsTr("EVENT NAME")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(11)
                        font.weight: Font.Bold
                        font.letterSpacing: 1.1
                    }

                    AppTextField {
                        id: nameField
                        objectName: "tournamentNameField"
                        Layout.fillWidth: true
                        placeholderText: root.limitedOnly ? qsTr("Friday Limited tournament") : qsTr("Saturday Swiss")
                        maximumLength: 128
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.topMargin: Theme.size(10)
                        text: qsTr("EVENT TYPE")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(11)
                        font.weight: Font.Bold
                        font.letterSpacing: 1.1
                    }

                    AppComboBox {
                        id: eventSelector
                        objectName: root.limitedOnly ? "limitedEventTypeSelector" : "tournamentEventTypeSelector"
                        Layout.fillWidth: true
                        model: root.eventOptions
                        textRole: "label"
                        valueRole: "value"
                        onActivated: {
                            // Keep a valid in-range cap across event-type switches;
                            // clamp out-of-range values instead of discarding input.
                            var parsed = capField.numberValue()
                            if (isNaN(parsed))
                                parsed = root.isDraft ? 8 : 32
                            parsed = Math.max(
                                root.isLimited ? 2 : 4,
                                Math.min(parsed, root.isDraft ? 8
                                                : (root.isLimited ? 64 : 512)))
                            capField.text = String(parsed)
                        }
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.topMargin: Theme.size(10)
                        visible: !root.isLimited
                        text: qsTr("FORMAT LABEL")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(11)
                        font.weight: Font.Bold
                        font.letterSpacing: 1.1
                    }

                    AppComboBox {
                        id: formatSelector
                        objectName: "tournamentFormatSelector"
                        Layout.fillWidth: true
                        model: root.formatOptions
                        textRole: "label"
                        valueRole: "value"
                        currentIndex: 0
                        visible: !root.isLimited
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: root.isLimited
                              ? qsTr("The server manages pools and drafting. Each match uses the gameplay rules selected below.")
                              : qsTr("The format names the card pool. Matches follow the gameplay rules selected below.")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(11)
                        wrapMode: Text.WordWrap
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.size(10)
                        visible: root.isLimited && !root.isCube
                        spacing: Theme.size(7)

                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("LIMITED SET")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(11)
                            font.weight: Font.Bold
                        }

                        LimitedSetPicker {
                            id: setPicker
                            Layout.fillWidth: true
                            sets: root.limitedSets
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            visible: setPicker.hasSelection
                            text: !setPicker.hasSelection ? ""
                                  : setPicker.selectedSet.authentic
                                    ? qsTr("%1 boosters · exact generated collation")
                                      .arg(setPicker.selectedSet.boosterKind
                                           === "play" ? qsTr("Play") : qsTr("Draft"))
                                    : qsTr("Approximate rarity collation; this is shown to every participant.")
                            color: setPicker.hasSelection
                                   && setPicker.selectedSet.authentic
                                   ? Theme.success : Theme.warning
                            font.pixelSize: Theme.fontSize(11)
                            wrapMode: Text.WordWrap
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.isCube
                        spacing: Theme.size(8)
                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("CUBE POOL")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(11)
                            font.weight: Font.Bold
                        }
                        AppComboBox {
                            id: cubeSelector
                            objectName: "tournamentCubeSelector"
                            Layout.fillWidth: true
                            model: root.cubeDecks
                            textRole: "deckName"
                            valueRole: "deckId"
                        }
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: qsTr("Select a saved Cube with exact printings and at least %1 cards (%2 per seat).")
                                  .arg(capField.numberValue() * 45).arg(45)
                            color: root.cubeReady ? Theme.textMuted : Theme.warning
                            font.pixelSize: Theme.fontSize(11)
                            wrapMode: Text.WordWrap
                        }
                        AppButton {
                            compact: true
                            text: qsTr("Open deck library")
                            onClicked: root.appWindow.pushScreen("screens/DeckLibrary.qml")
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.size(14)
                        spacing: Theme.size(18)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.size(7)
                            Text {
                                textFormat: Text.PlainText
                                text: qsTr("MATCH")
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSize(11)
                                font.weight: Font.Bold
                            }
                            SegmentedControl {
                                Layout.fillWidth: true
                                options: [qsTr("BO 1"), qsTr("BO 3")]
                                currentIndex: root.matchMode === "bo3" ? 1 : 0
                                onActivated: index => root.matchMode = index === 1
                                                               ? "bo3" : "bo1"
                            }
                        }

                        ColumnLayout {
                            Layout.preferredWidth: Theme.size(170)
                            spacing: Theme.size(7)
                            Text {
                                textFormat: Text.PlainText
                                text: qsTr("ROUND MINUTES")
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSize(11)
                                font.weight: Font.Bold
                            }
                            AppTextField {
                                id: minutesField
                                objectName: "tournamentRoundMinutesField"
                                Layout.fillWidth: true
                                text: "50"
                                inputMethodHints: Qt.ImhDigitsOnly
                                validator: IntValidator { bottom: 40; top: 240 }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.size(10)
                        spacing: Theme.size(18)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.size(7)
                            Text {
                                textFormat: Text.PlainText
                                text: qsTr("PLAYER CAP")
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSize(11)
                                font.weight: Font.Bold
                            }
                            AppTextField {
                                id: capField
                                objectName: "tournamentPlayerCapField"
                                Layout.fillWidth: true
                                text: root.limitedOnly ? "8" : "32"
                                inputMethodHints: Qt.ImhDigitsOnly
                                validator: IntValidator {
                                    bottom: root.isLimited ? 2 : 4
                                    top: root.isDraft ? 8 : (root.isLimited ? 64 : 512)
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.size(10)
                        spacing: Theme.size(7)
                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("GAMEPLAY RULES")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(11)
                            font.weight: Font.Bold
                        }
                        SegmentedControl {
                            objectName: "tournamentRulesMode"
                            Layout.fillWidth: true
                            options: [qsTr("Manual tabletop"), qsTr("Forge rules")]
                            currentIndex: root.rulesMode === "forge" ? 1 : 0
                            onActivated: index => root.rulesMode = index === 1 ? "forge" : "manual"
                        }
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            visible: root.rulesMode === "forge"
                            text: root.rulesAvailable
                                  ? qsTr("Every paired match uses server-hosted Forge rules. The rules mode is fixed for this event.")
                                  : qsTr("Forge rules are unavailable on this server")
                            color: root.rulesAvailable ? Theme.textMuted : Theme.warning
                            font.pixelSize: Theme.fontSize(11)
                            wrapMode: Text.WordWrap
                        }
                    }

                    InfoBanner {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.size(10)
                        tone: "success"
                        message: root.isCube
                                 ? qsTr("Draft the Cube, build decks, then play Swiss rounds with standings")
                                 : root.isDraft
                                 ? qsTr("Set draft starts with at least two checked-in players, three packs each, and passes left, right, then left. Capacity is two to eight seats.")
                                 : root.isLimited
                                   ? qsTr("Set sealed gives every player exactly six boosters before deck building. Two checked-in players are required to start.")
                                   : qsTr("The server chooses the Swiss round count from checked-in attendance. Four checked-in players are required to start.")
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.size(18)
                        Item { Layout.fillWidth: true }
                        AppButton {
                            objectName: root.limitedOnly ? "limitedRoomCreateSubmitButton" : "tournamentCreateSubmitButton"
                            variant: "primary"
                            text: root.isLimited ? qsTr("Create Limited tournament") : qsTr("Create tournament")
                            enabled: root.hub.connected && !root.hub.inRoom && root.rulesAvailable
                                     && nameField.text.trim().length > 0
                                     && formatSelector.currentIndex >= 0
                                     && minutesField.acceptableInput
                                     && capField.acceptableInput
                                     && (root.isCube ? root.cubeReady
                                         : (!root.isLimited || setPicker.hasSelection))
                            onClicked: {
                                if (!root.isLimited) {
                                    root.hub.createTournament(nameField.text.trim(),
                                                               formatSelector.currentValue,
                                                               root.matchMode,
                                                               minutesField.numberValue(),
                                                               capField.numberValue(), root.rulesMode)
                                    return
                                }
                                const product = root.isCube
                                                ? root.decks.cubeProduct(root.selectedCube.deckId)
                                                : root.catalog.limitedProduct(setPicker.selectedSet.productId)
                                root.hub.createLimitedTournament(
                                            nameField.text.trim(),
                                            eventSelector.currentValue,
                                            root.matchMode,
                                            minutesField.numberValue(),
                                            capField.numberValue(),
                                            product, root.rulesMode)
                            }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: root.hub
        function onLastErrorChanged() {
            if (root.hub.lastError)
                root.appWindow.showBanner(I18n.status(root.hub.lastError))
        }
    }
}
