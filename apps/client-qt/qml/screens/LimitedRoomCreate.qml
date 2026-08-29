// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root

    readonly property var appWindow: ApplicationWindow.window
    property var wsModel
    property var cardCatalogModel
    readonly property var hub: wsModel ? wsModel : ws
    readonly property var catalog: cardCatalogModel ? cardCatalogModel : cardCatalog

    readonly property var eventOptions: [
        {"label": qsTr("Set sealed"), "value": "set_sealed"},
        {"label": qsTr("Set draft"), "value": "set_draft"}
    ]
    readonly property bool isDraft: eventSelector.currentValue === "set_draft"
    property var limitedSets: []
    property string matchMode: "bo3"

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
            title: qsTr("Create Limited tournament")
            subtitle: qsTr("Open pools, build 40-card decks, then play Swiss rounds with standings")
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

        Flickable {
            id: formBody
            objectName: "limitedRoomCreateBody"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: Math.max(height, formCard.height)
            ScrollBar.vertical: ScrollBar {
                policy: formBody.contentHeight > formBody.height
                        ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            }

            Surface {
                id: formCard
                objectName: "limitedRoomCreateCard"
                width: Math.min(Theme.size(680), formBody.width - Theme.size(48))
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
                    spacing: Theme.size(11)

                    Text {
                        textFormat: Text.PlainText
                        text: qsTr("EVENT NAME")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(11)
                        font.weight: Font.Bold
                    }

                    AppTextField {
                        id: nameField
                        Layout.fillWidth: true
                        placeholderText: qsTr("Friday Limited tournament")
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
                                    bottom: root.isDraft ? 8 : 4
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
                                 ? qsTr("Eight checked-in players draft three packs, then play three Swiss rounds with standings.")
                                 : qsTr("Players receive six boosters, build decks, then play the recommended number of Swiss rounds.")
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.size(16)
                        Item { Layout.fillWidth: true }
                        AppButton {
                            objectName: "limitedRoomCreateSubmitButton"
                            variant: "primary"
                            text: qsTr("Create Limited tournament")
                            enabled: root.hub.connected && !root.hub.inRoom
                                     && nameField.text.trim().length > 0
                                     && playerCapField.acceptableInput
                                     && setPicker.hasSelection
                            onClicked: {
                                const selectedSet = setPicker.selectedSet
                                root.hub.createLimitedTournament(
                                            nameField.text.trim(),
                                            eventSelector.currentValue,
                                            root.matchMode, 50,
                                            Number(playerCapField.text), 0,
                                            root.catalog.limitedProduct(
                                                selectedSet.productId))
                            }
                        }
                    }
                }
            }
        }
    }
}
