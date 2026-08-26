// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root

    readonly property var appWindow: ApplicationWindow.window
    readonly property var eventOptions: [
        {"label": qsTr("Set sealed"), "value": "set_sealed"},
        {"label": qsTr("Set draft"), "value": "set_draft"}
    ]
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
            title: qsTr("Create limited room")
            subtitle: qsTr("Open pools, build 40-card decks, then play private casual tables")
            onBackRequested: root.appWindow.popScreen()
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(8)

            Item { Layout.fillWidth: true }

            AppButton {
                compact: true
                variant: "ghost"
                text: qsTr("Pack simulator")
                onClicked: root.appWindow.pushScreen("screens/LimitedHub.qml")
            }

        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            Surface {
                width: Math.min(Theme.size(680), parent.width - Theme.size(48))
                height: form.implicitHeight + Theme.size(60)
                anchors.horizontalCenter: parent.horizontalCenter
                elevated: true

                ColumnLayout {
                    id: form
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.size(30)
                    spacing: Theme.size(11)

                    Text {
                        textFormat: Text.PlainText
                        text: qsTr("ROOM NAME")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(11)
                        font.weight: Font.Bold
                    }

                    AppTextField {
                        id: nameField
                        Layout.fillWidth: true
                        placeholderText: qsTr("Friday limited room")
                        maximumLength: 128
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.topMargin: Theme.size(8)
                        text: qsTr("LIMITED MODE")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(11)
                        font.weight: Font.Bold
                    }

                    AppComboBox {
                        id: eventSelector
                        Layout.fillWidth: true
                        model: root.eventOptions
                        textRole: "label"
                        valueRole: "value"
                        onActivated: playerCapField.text = "8"
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.topMargin: Theme.size(8)
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
                                ? qsTr("Uses the installed %1 booster definition.")
                                  .arg(setPicker.selectedSet.productName)
                                : qsTr("Approximate rarity collation; every player will see this warning.")
                        color: setPicker.hasSelection
                               && setPicker.selectedSet.authentic
                               ? Theme.success : Theme.warning
                        font.pixelSize: Theme.fontSize(11)
                        wrapMode: Text.WordWrap
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.size(10)
                        spacing: Theme.size(18)

                        ColumnLayout {
                            Layout.fillWidth: true
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
                            Layout.preferredWidth: Theme.size(180)
                            Text {
                                textFormat: Text.PlainText
                                text: qsTr("PLAYER CAP")
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSize(11)
                                font.weight: Font.Bold
                            }
                            AppTextField {
                                id: playerCapField
                                Layout.fillWidth: true
                                text: "8"
                                enabled: !root.isDraft
                                inputMethodHints: Qt.ImhDigitsOnly
                                validator: IntValidator {
                                    bottom: root.isDraft ? 8 : 2
                                    top: root.isDraft ? 8 : 64
                                }
                            }
                        }
                    }

                    InfoBanner {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.size(8)
                        tone: "success"
                        message: root.isDraft
                                 ? qsTr("The room starts with exactly eight checked-in players and runs a three-pack left/right/left draft.")
                                 : qsTr("Every checked-in player receives exactly six boosters and proceeds directly to deck building.")
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.size(16)
                        Item { Layout.fillWidth: true }
                        AppButton {
                            variant: "primary"
                            text: qsTr("Create limited room")
                            enabled: ws.connected && !ws.inRoom
                                     && nameField.text.trim().length > 0
                                     && playerCapField.acceptableInput
                                     && setPicker.hasSelection
                            onClicked: {
                                const selectedSet = setPicker.selectedSet
                                ws.createCasualLimitedEvent(
                                            nameField.text.trim(), eventSelector.currentValue,
                                            root.matchMode, Number(playerCapField.text),
                                            cardCatalog.limitedProduct(selectedSet.productId))
                            }
                        }
                    }
                }
            }
        }
    }
}
