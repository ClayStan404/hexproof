// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "TokenPresentation.js" as TokenPresentation

AppPopup {
    id: root

    required property var tableController
    property int viewedSeat: -1
    property string selectedId: ""
    readonly property var seatData: (tableController.battlefieldSeats || [])
                                   .find(seat => seat.seat === viewedSeat) || ({})
    readonly property var emblems: seatData.emblems || []
    readonly property var selectedEmblem: emblems.find(emblem => emblem.id === selectedId)
                                         || emblems[0] || ({})
    readonly property bool canRemove: tableController.canAct === true
                                      && viewedSeat === tableController.roomSession.seatIndex
    readonly property var catalogModel: tableController.cardCatalogModel
    readonly property string cardLanguage: catalogModel && catalogModel.language || "en"
    readonly property var selectedDetails: TokenPresentation.details(catalogModel, facePreview.viewedCard)

    width: Math.min(Theme.size(1040), parent.width - Theme.size(32))
    height: Math.min(Theme.size(680), parent.height - Theme.size(32))
    padding: Theme.size(20)

    function showSeat(seat) {
        viewedSeat = seat
        selectedId = ""
        facePreview.resetFace()
        root.open()
    }

    function displayName(emblem) {
        return TokenPresentation.details(catalogModel, emblem).displayName
    }

    function cacheEmblems() {
        if (!catalogModel) return
        const visibleEmblems = emblems.slice(0, 60)
        if (selectedEmblem.name && !visibleEmblems.some(emblem => emblem.id === selectedEmblem.id)) {
            visibleEmblems.pop()
            visibleEmblems.push(selectedEmblem)
        }
        for (const emblem of visibleEmblems)
            catalogModel.cacheToken(Object.assign({}, emblem, {kind: "emblem"}))
    }
    function prioritizeSelectedEmblem(useViewedFace) {
        const card = useViewedFace ? facePreview.viewedCard : selectedEmblem
        if (card.name && card.faceDown !== true && card.visibleIdentity !== false)
            TokenPresentation.prioritize(catalogModel, Object.assign({}, card, {kind: "emblem"}))
    }
    onOpened: {
        cacheEmblems()
        prioritizeSelectedEmblem()
    }
    onClosed: facePreview.resetFace()
    onEmblemsChanged: if (opened) cacheEmblems()
    onCardLanguageChanged: {
        if (opened) {
            cacheEmblems()
            prioritizeSelectedEmblem(true)
            rulesScroll.contentY = 0
        }
    }
    onSelectedEmblemChanged: {
        if (opened) prioritizeSelectedEmblem()
        rulesScroll.contentY = 0
    }

    CardFacePreviewController {
        id: facePreview
        catalogModel: root.catalogModel
        card: root.selectedEmblem
        tokenArt: true
        active: root.opened
    }

    Connections {
        target: facePreview
        function onViewedCardChanged() { rulesScroll.contentY = 0 }
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(12)
        AppPopupHeader {
            titleText: qsTr("%1 · Emblems").arg(root.seatData.displayName || qsTr("Player"))
            subtitleText: qsTr("Command zone · Emblems are not battlefield permanents.")
            showClose: true
            closeObjectName: "closeEmblemBrowserButton"
            onCloseRequested: root.close()
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.size(16)
            ListView {
                id: emblemList
                objectName: "emblemBrowserList"
                Layout.preferredWidth: Math.min(Theme.size(250), root.availableWidth * 0.36)
                Layout.fillHeight: true
                model: root.emblems
                clip: true
                spacing: Theme.size(8)
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: ColumnLayout {
                    id: emblemRow
                    required property var modelData
                    width: emblemList.width
                    spacing: Theme.size(4)
                    AppButton {
                        objectName: "selectEmblem" + emblemRow.modelData.id
                        Layout.fillWidth: true
                        implicitHeight: Math.max(Theme.size(54), emblemName.implicitHeight + Theme.size(16))
                        variant: root.selectedEmblem.id === emblemRow.modelData.id ? "highlight" : "secondary"
                        accessibleName: root.displayName(emblemRow.modelData)
                        contentItem: Text {
                            textFormat: Text.PlainText
                            id: emblemName
                            text: root.displayName(emblemRow.modelData)
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(13)
                            verticalAlignment: Text.AlignVCenter
                            wrapMode: Text.WordWrap
                        }
                        onClicked: root.selectedId = emblemRow.modelData.id
                    }
                    AppButton {
                        objectName: "removeEmblem" + emblemRow.modelData.id
                        Layout.fillWidth: true
                        visible: root.canRemove
                        enabled: root.canRemove
                        compact: true
                        variant: "ghost"
                        text: qsTr("Remove emblem")
                        onClicked: {
                            if (root.canRemove)
                                root.tableController.wsModel.removeEmblem(emblemRow.modelData.id)
                        }
                    }
                }
            }
            Item {
                id: emblemDetailBody
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                ScrollView {
                    id: artScroll
                    objectName: "emblemArtScroll"
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: rulesScroll.top
                    anchors.bottomMargin: Theme.size(12)
                    contentWidth: availableWidth
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    CardFacePreviewGallery {
                        controller: facePreview
                        artObjectName: "emblemBrowserArt"
                        columns: facePreview.displayFaces.length > 1
                                 && artScroll.availableWidth >= Theme.size(368) ? 2 : 1
                        width: Math.min(artScroll.availableWidth,
                            Math.max(1, artScroll.availableHeight - Theme.size(12)) * 63 / 88 * columns
                            + (columns - 1) * Theme.size(8))
                    }
                }
                Flickable {
                    id: rulesScroll
                    objectName: "emblemRulesScroll"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: Math.min(Theme.size(200), emblemDetailBody.height * 0.42)
                    contentWidth: width
                    contentHeight: rulesText.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    clip: true
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    Text {
                        id: rulesText
                        objectName: "emblemRulesText"
                        textFormat: Text.PlainText
                        width: rulesScroll.width - Theme.size(16)
                        text: facePreview.displayFaces.map(face => face.fallbackText).join("\n\n")
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(13)
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}
