// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    property var cardCatalogModel: null
    property var faces: []
    property string cardName: ""
    signal faceSelected(string faceName)

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(720), parent.width - Theme.size(48))
    height: Math.min(Theme.size(560), parent.height - Theme.size(56))
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

    function prioritizeFaceImages(availableFaces) {
        if (!cardCatalogModel)
            return
        const requestedFaces = availableFaces ? availableFaces : []
        if (typeof cardCatalogModel.prioritizeCards === "function") {
            cardCatalogModel.prioritizeCards(requestedFaces)
        } else if (typeof cardCatalogModel.cacheCards === "function") {
            cardCatalogModel.cacheCards(requestedFaces)
        }
    }

    function showFor(card, availableFaces) {
        cardName = card && card.name ? card.name : ""
        faces = availableFaces ? availableFaces : []
        prioritizeFaceImages(faces)
        open()
    }

    function choose(faceName) {
        close()
        faceSelected(faceName)
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(14)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(10)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(3)

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Choose card face")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(20)
                    font.weight: Font.DemiBold
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: root.cardName
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(11)
                    elide: Text.ElideRight
                }
            }

            AppButton {
                compact: true
                variant: "ghost"
                text: "×"
                accessibleName: qsTr("Close")
                Layout.preferredWidth: Theme.size(40)
                onClicked: root.close()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.size(18)

            Repeater {
                model: root.faces

                delegate: Surface {
                    id: faceCard
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: faceMouse.containsMouse
                           ? Theme.primaryMuted : Theme.surfaceMuted
                    border.color: faceMouse.containsMouse
                                  ? Theme.primary : Theme.border

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.size(12)
                        spacing: Theme.size(8)

                        Image {
                            id: faceArt
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            source: root.cardCatalogModel
                                    && (root.cardCatalogModel.imageRevision
                                        === undefined
                                        || root.cardCatalogModel.imageRevision
                                           >= 0)
                                    ? root.cardCatalogModel.imageSource(
                                          faceCard.modelData.name,
                                          faceCard.modelData.setCode,
                                          faceCard.modelData.collectorNumber)
                                    : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            smooth: true
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: faceCard.modelData.displayName
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(13)
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: faceMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.choose(
                            faceCard.modelData.faceName
                            ? faceCard.modelData.faceName : "")
                    }
                }
            }
        }
    }
}
