// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root
    required property var panel
    property var inspectedCard: ({})
    readonly property var reviewCards: panel.rulesSession
        ? panel.rulesSession.publicReviewCards || []
        : panel.gameTableModel.publicReviewCards || []
    readonly property var filteredCards: reviewCards.filter(card =>
        (seatPicker.currentIndex === 0 || card.seat === seatPicker.currentIndex - 1)
        && (zonePicker.currentIndex === 0 || card.zone === ["", "battlefield", "graveyard", "exile", "command"][zonePicker.currentIndex]))
    objectName: "sideboardBoardReview"
    parent: Overlay.overlay
    width: Math.min(Theme.size(1250), parent.width - Theme.size(32))
    height: Math.min(Theme.size(850), parent.height - Theme.size(32))
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    modal: true
    focus: true
    padding: Theme.size(16)
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Surface { elevated: true }
    onOpened: inspectedCard = filteredCards.length ? filteredCards[0] : ({})
    contentItem: ColumnLayout {
        spacing: Theme.size(10)
        Text {
            textFormat: Text.PlainText
            text: qsTr("Previous game · public cards")
            color: Theme.text
            font.pixelSize: Theme.fontSize(20)
            font.bold: true
        }
        RowLayout {
            Layout.fillWidth: true
            ComboBox {
                id: seatPicker
                objectName: "sideboardReviewSeat"
                Layout.fillWidth: true
                model: {
                    const names = [qsTr("All players")]
                    const count = root.panel.roomSession.maxSeats || 2
                    for (let seat = 0; seat < count; ++seat)
                        names.push(root.panel.displayName(seat))
                    return names
                }
            }
            ComboBox {
                id: zonePicker
                objectName: "sideboardReviewZone"
                Layout.fillWidth: true
                model: [qsTr("All public zones"), qsTr("Battlefield"), qsTr("Graveyard"), qsTr("Exile"), qsTr("Command zone")]
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            GridView {
                id: cards
                objectName: "sideboardReviewCards"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                Layout.minimumHeight: 0
                Layout.preferredWidth: root.availableWidth * 0.7
                clip: true
                cellWidth: Math.max(Theme.size(110), width / Math.max(1, Math.floor(width / Theme.size(130))))
                cellHeight: Theme.size(200)
                model: root.filteredCards
                ScrollBar.vertical: ScrollBar {}
                delegate: Item {
                    id: entry
                    required property var modelData
                    width: cards.cellWidth
                    height: cards.cellHeight
                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.size(5)
                        spacing: Theme.size(4)
                        Image {
                            width: parent.width
                            height: Math.max(1, entry.height - Theme.size(55))
                            source: root.panel.cardImageSource(entry.modelData)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        Text {
                            textFormat: Text.PlainText
                            width: parent.width
                            text: entry.modelData.name
                            color: Theme.text
                            elide: Text.ElideRight
                            font.pixelSize: Theme.fontSize(11)
                        }
                        Text {
                            textFormat: Text.PlainText
                            width: parent.width
                            text: root.panel.displayName(entry.modelData.seat)
                            color: Theme.textMuted
                            elide: Text.ElideRight
                            font.pixelSize: Theme.fontSize(10)
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: root.inspectedCard = entry.modelData
                        onClicked: root.inspectedCard = entry.modelData
                    }
                }
                Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: qsTr("No visible cards in this zone")
                    color: Theme.textMuted
                    visible: cards.count === 0
                }
            }
            ColumnLayout {
                objectName: "sideboardReviewPreview"
                Layout.minimumWidth: 0
                Layout.preferredWidth: Math.min(Theme.size(320), root.availableWidth * 0.3)
                Layout.maximumWidth: Layout.preferredWidth
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 0
                    Layout.minimumHeight: 0
                    Image {
                        objectName: "sideboardReviewPreviewImage"
                        anchors.fill: parent
                        source: root.panel.cardImageSource(root.inspectedCard)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                }
                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    textFormat: Text.PlainText
                    text: root.inspectedCard.name || ""
                    color: Theme.text
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fontSize(14)
                }
            }
        }
        AppButton {
            objectName: "sideboardReviewClose"
            Layout.alignment: Qt.AlignRight
            text: qsTr("Back to sideboarding")
            onClicked: root.close()
        }
    }
}
