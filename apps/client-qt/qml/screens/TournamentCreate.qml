// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root

    readonly property var appWindow: ApplicationWindow.window
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
    readonly property var eventOptions: [
        {"label": qsTr("Constructed"), "value": "constructed"},
        {"label": qsTr("Set sealed"), "value": "set_sealed"},
        {"label": qsTr("Set draft"), "value": "set_draft"}
    ]
    readonly property bool isLimited: eventSelector.currentValue !== "constructed"
    readonly property bool isDraft: eventSelector.currentValue === "set_draft"
    property var limitedSets: []
    property string matchMode: "bo3"

    background: AppBackground { }
    Component.onCompleted: limitedSets = cardCatalog.limitedSets()

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: Theme.size(22)
        anchors.bottomMargin: Theme.size(28)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        spacing: Theme.size(16)

        ScreenHeader {
            Layout.fillWidth: true
            title: qsTr("Create tournament")
            subtitle: qsTr("Individual Swiss · manual tabletop rules enforcement")
            onBackRequested: root.appWindow.popScreen()
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            Surface {
                width: Math.min(Theme.size(720), parent.width - Theme.size(48))
                height: form.implicitHeight + Theme.size(60)
                anchors.horizontalCenter: parent.horizontalCenter
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
                        Layout.fillWidth: true
                        placeholderText: qsTr("Saturday Swiss")
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
                        objectName: "tournamentEventTypeSelector"
                        Layout.fillWidth: true
                        model: root.eventOptions
                        textRole: "label"
                        valueRole: "value"
                        onActivated: {
                            capField.text = root.isDraft ? "8" : "32"
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
                              ? qsTr("Limited pools and drafting are server-authoritative. Tabletop game rules remain manual.")
                              : qsTr("This is an announced label. Hexproof does not enforce deck legality or game rules.")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(11)
                        wrapMode: Text.WordWrap
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.size(10)
                        visible: root.isLimited
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
                                Layout.fillWidth: true
                                text: "32"
                                enabled: !root.isDraft
                                inputMethodHints: Qt.ImhDigitsOnly
                                validator: IntValidator {
                                    bottom: root.isDraft ? 8 : 4
                                    top: root.isDraft ? 8 : (root.isLimited ? 64 : 512)
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.size(7)
                            Text {
                                textFormat: Text.PlainText
                                text: qsTr("SWISS ROUNDS")
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSize(11)
                                font.weight: Font.Bold
                            }
                            AppTextField {
                                id: roundsField
                                Layout.fillWidth: true
                                text: "0"
                                inputMethodHints: Qt.ImhDigitsOnly
                                validator: IntValidator { bottom: 0; top: 20 }
                            }
                        }
                    }

                    InfoBanner {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.size(10)
                        tone: "success"
                        message: root.isDraft
                                 ? qsTr("Set draft requires exactly eight checked-in players, three packs each, and passes left, right, then left.")
                                 : root.isLimited
                                   ? qsTr("Set sealed gives every player exactly six boosters before deck building.")
                                   : qsTr("Use 0 rounds for the recommended Swiss count based on checked-in attendance. Four checked-in players are required to start.")
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.size(18)
                        Item { Layout.fillWidth: true }
                        AppButton {
                            variant: "primary"
                            text: qsTr("Create tournament")
                            enabled: nameField.text.trim().length > 0
                                     && formatSelector.currentIndex >= 0
                                     && minutesField.acceptableInput
                                     && capField.acceptableInput
                                     && roundsField.acceptableInput
                                     && (!root.isLimited
                                         || setPicker.hasSelection)
                            onClicked: {
                                if (!root.isLimited) {
                                    ws.createTournament(nameField.text.trim(),
                                                        formatSelector.currentValue,
                                                        root.matchMode,
                                                        Number(minutesField.text),
                                                        Number(capField.text),
                                                        Number(roundsField.text))
                                    return
                                }
                                const selectedSet = setPicker.selectedSet
                                const product = cardCatalog.limitedProduct(selectedSet.productId)
                                ws.createLimitedTournament(
                                            nameField.text.trim(),
                                            eventSelector.currentValue,
                                            root.matchMode,
                                            Number(minutesField.text),
                                            Number(capField.text),
                                            Number(roundsField.text),
                                            product)
                            }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: ws
        function onLastErrorChanged() {
            if (ws.lastError)
                root.appWindow.showBanner(I18n.status(ws.lastError))
        }
    }
}
