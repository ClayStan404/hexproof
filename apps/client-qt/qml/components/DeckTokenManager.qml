// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "TokenPresentation.js" as TokenPresentation

Popup {
    id: root

    required property var deckLibraryModel
    required property var catalogModel
    readonly property string cardLanguage: catalogModel && catalogModel.language || "en"
    readonly property var currentTokens: deckLibraryModel.currentTokens
    property alias detailsPopup: detailsPopup
    signal addRequested()
    onOpened: cacheDisplayedTokens()
    onCardLanguageChanged: if (opened) cacheDisplayedTokens()
    onCurrentTokensChanged: if (opened) Qt.callLater(cacheDisplayedTokens)

    function cacheDisplayedTokens() {
        if (!opened || !catalogModel || typeof catalogModel.cacheToken !== "function") return
        for (const token of currentTokens.slice(0, 60)) catalogModel.cacheToken(token)
    }

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(1040), parent.width - Theme.size(48))
    height: Math.min(Theme.size(720), parent.height - Theme.size(56))
    padding: Theme.size(24)
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

    contentItem: ColumnLayout {
        spacing: Theme.size(14)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(12)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(3)

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Deck tokens and emblems")
                    elide: Text.ElideRight
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(22)
                    font.weight: Font.DemiBold
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Saved tokens and emblems appear first in the in-game picker. Click art for rules.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(13)
                    wrapMode: Text.WordWrap
                }
            }

            StatusPill {
                text: qsTr("%1 saved").arg(
                          root.deckLibraryModel.currentTokens.length)
                statusColor: Theme.primary
            }

            AppButton {
                objectName: "managerAddDeckTokenButton"
                variant: "primary"
                text: qsTr("Add")
                enabled: root.catalogModel.tokenCatalogInstalled
                onClicked: root.addRequested()
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

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.divider
        }

        GridView {
            id: tokenGrid
            objectName: "managedDeckTokenGrid"
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.deckLibraryModel.currentTokens.length > 0
            model: root.deckLibraryModel.currentTokens
            cellWidth: Theme.size(240)
            cellHeight: Theme.size(330)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Item {
                id: tokenCell
                required property var modelData
                readonly property var details: TokenPresentation.details(root.catalogModel, modelData)
                width: tokenGrid.cellWidth
                height: tokenGrid.cellHeight

                Surface {
                    anchors.fill: parent
                    anchors.margins: Theme.size(5)
                    radius: Theme.radiusMedium
                    color: Theme.surfaceMuted

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.size(10)
                        spacing: Theme.size(6)

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Image {
                                id: managedTokenImage
                                objectName: "managedDeckTokenImage"
                                anchors.centerIn: parent
                                width: Math.min(parent.width, Theme.size(160))
                                height: Math.min(parent.height, Theme.size(224))
                                source: {
                                    void root.cardLanguage
                                    return root.catalogModel
                                        && (root.catalogModel.imageRevision
                                            === undefined
                                            || root.catalogModel.imageRevision >= 0)
                                        ? root.catalogModel.tokenImageSource(
                                              tokenCell.modelData.name,
                                              tokenCell.modelData.setCode,
                                              tokenCell.modelData.collectorNumber)
                                        : ""
                                }
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                smooth: true
                                HoverHandler {
                                    onHoveredChanged: {
                                        if (hovered) preview.inspect(tokenCell.modelData, managedTokenImage)
                                        else preview.hide(managedTokenImage)
                                    }
                                }
                                TapHandler {
                                    acceptedButtons: Qt.LeftButton
                                    onTapped: {
                                        preview.hide()
                                        detailsPopup.showCard(tokenCell.modelData)
                                    }
                                }
                            }

                            AppButton {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                compact: true
                                variant: "ghost"
                                text: "×"
                                accessibleName: qsTr("Remove %1").arg(
                                                    tokenCell.details.displayName)
                                onClicked: root.deckLibraryModel.removeToken(
                                               tokenCell.modelData.name,
                                               tokenCell.modelData.setCode,
                                               tokenCell.modelData.collectorNumber)
                            }
                        }

                        Text {
                            textFormat: Text.PlainText
                            objectName: "managedDeckTokenName"
                            Layout.fillWidth: true
                            text: tokenCell.details.displayName
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(13)
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            TapHandler {
                                acceptedButtons: Qt.LeftButton
                                onTapped: {
                                    preview.hide()
                                    detailsPopup.showCard(tokenCell.modelData)
                                }
                            }
                        }

                        Text {
                            textFormat: Text.PlainText
                            objectName: "managedDeckTokenDetails"
                            Layout.fillWidth: true
                            text: root.tokenDetails(tokenCell.modelData)
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSize(10)
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            TapHandler {
                                acceptedButtons: Qt.LeftButton
                                onTapped: {
                                    preview.hide()
                                    detailsPopup.showCard(tokenCell.modelData)
                                }
                            }
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: tokenCell.modelData.setCode + " #"
                                  + tokenCell.modelData.collectorNumber
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(10)
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.deckLibraryModel.currentTokens.length === 0
            spacing: Theme.size(12)

            Item { Layout.fillHeight: true }

            Text {
                textFormat: Text.PlainText
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("No deck tokens or emblems saved")
                color: Theme.text
                font.pixelSize: Theme.fontSize(17)
                font.weight: Font.DemiBold
            }

            Text {
                textFormat: Text.PlainText
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: Theme.size(480)
                text: root.catalogModel.tokenCatalogInstalled
                      ? qsTr("Add the tokens and emblems this deck commonly creates.")
                      : qsTr("Install the card database to choose tokens and emblems.")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            AppButton {
                Layout.alignment: Qt.AlignHCenter
                variant: "primary"
                text: qsTr("Add")
                enabled: root.catalogModel.tokenCatalogInstalled
                onClicked: root.addRequested()
            }

            Item { Layout.fillHeight: true }
        }
    }

    onClosed: {
        preview.hide()
        detailsPopup.close()
    }
    TokenDetailsPopup {
        id: detailsPopup
        catalogModel: root.catalogModel
    }
    Item {
        parent: root.contentItem ? root.contentItem.parent : null
        anchors.fill: parent
        anchors.margins: Theme.size(12)
        visible: root.opened
        enabled: false
        z: 1000
        // Keep the preview outside the manager's ColumnLayout.
        CardHoverPreview {
            id: preview
            objectName: "managedTokenArtPreview"
            catalogModel: root.catalogModel
            tokenArt: true
        }
    }

    function tokenDetails(token) {
        return TokenPresentation.summary(catalogModel, token, false)
    }
}
