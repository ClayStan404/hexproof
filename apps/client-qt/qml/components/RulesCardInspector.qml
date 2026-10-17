// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Surface {
    id: root

    required property var rulesSession
    required property var cardCatalogModel
    required property url cardBackSource
    property string pinnedCardId: ""
    property var pinnedSource: null
    property string previewCardId: ""
    property var previewSource: null
    property bool previewSourceActive: false
    property bool previewHeld: false
    property bool previewNeedsInspection: false
    property string inspectedGameId: ""
    property bool showEmptyCloseButton: false
    property bool preferVertical: false
    signal cleared()
    signal dismissed(var returnSource)
    readonly property var currentSnapshotRevision: rulesSession.snapshotRevision
    readonly property string currentGameId: rulesSession.gameId
    readonly property string cardId: previewCardId || pinnedCardId
    readonly property bool pinned: pinnedCardId.length > 0
    readonly property var card: {
        void rulesSession.snapshotRevision
        return inspectedGameId === rulesSession.gameId ? currentCard(cardId) : ({})
    }
    readonly property bool hasCard: Object.keys(card).length > 0
    readonly property bool hasIdentity: card.visibleIdentity === true
                                       && card.faceDown !== true && !!card.name
    readonly property string displayName: {
        if (!hasIdentity)
            return ""
        if (!cardCatalogModel || typeof cardCatalogModel.cardDisplayName !== "function")
            return card.name
        void cardCatalogModel.language
        void cardCatalogModel.imageRevision
        return cardCatalogModel.cardDisplayName(card.name)
    }
    readonly property bool horizontalLayout: !preferVertical && localFacePreview.displayFaces.length <= 1
        && (width >= Theme.size(500) || height < Theme.size(440))
    readonly property real availableBodyHeight: Math.max(0,
        height - Theme.size(24) - titleRow.implicitHeight - Theme.size(8))
    property alias facePreview: localFacePreview
    readonly property string exiledSummary: persistentState.exiledSummary
    readonly property string persistentSummary: persistentState.detailSummary
    RulesCardPersistentState {
        id: persistentState
        card: root.card
        rulesSession: root.rulesSession
        cardCatalogModel: root.cardCatalogModel
    }
    CardFacePreviewController {
        id: localFacePreview
        catalogModel: root.cardCatalogModel
        card: Object.assign({}, root.card, {id:root.cardId})
        sourceItem: root.previewSource
        identityVisible: root.hasIdentity
        active: root.hasCard
    }
    Timer {
        id: previewDeparture
        interval: 350
        onTriggered: if (!root.previewSourceActive && !root.previewHeld) root.hidePreview()
    }
    onPreviewHeldChanged: {
        if (previewHeld) previewDeparture.stop()
        else if (!previewSourceActive && previewCardId.length) previewDeparture.restart()
    }
    onHasIdentityChanged: {
        if (!hasIdentity) {
            // card is a snapshot binding; clear its selection after this
            // update finishes rather than writing a dependency mid-evaluation.
            if (previewCardId.length) Qt.callLater(() => {
                if (!root.hasIdentity && root.previewCardId.length) root.hidePreview()
            })
        }
    }

    objectName: "rulesCardInspector"
    implicitWidth: Theme.size(400)
    implicitHeight: Theme.size(540)
    color: Theme.surfaceElevated
    radius: 0
    border.width: 0
    clip: true

    function currentCard(id) {
        return id && typeof rulesSession.cardForInspection === "function"
                ? rulesSession.cardForInspection(id) : ({})
    }

    function showCard(id, source) {
        if (Object.keys(currentCard(id)).length === 0)
            return false
        pinnedSource = source || (previewCardId === id ? previewSource : null)
        inspectedGameId = rulesSession.gameId
        previewDeparture.stop()
        previewSourceActive = false
        previewHeld = false
        pinnedCardId = id
        previewCardId = ""
        previewSource = null
        stateScroll.contentY = 0
        return true
    }

    function previewCard(id, source) {
        if (Object.keys(currentCard(id)).length === 0)
            return false
        inspectedGameId = rulesSession.gameId
        previewDeparture.stop()
        previewSourceActive = true
        previewSource = source || null
        previewCardId = id
        stateScroll.contentY = 0
        return true
    }

    function hidePreview(source) {
        if (source && previewSource && source !== previewSource)
            return
        if (source && previewCardId.length && (localFacePreview.displayFaces.length > 1 || previewNeedsInspection)
                && source.previewEnabled !== false && source.visible !== false) {
            previewSourceActive = false
            if (!previewHeld) previewDeparture.restart()
            return
        }
        previewDeparture.stop()
        previewSourceActive = false
        previewHeld = false
        previewCardId = ""
        previewSource = null
    }

    function clear() {
        previewDeparture.stop()
        previewSourceActive = false
        previewHeld = false
        localFacePreview.resetFace()
        pinnedCardId = ""
        pinnedSource = null
        previewCardId = ""
        previewSource = null
        inspectedGameId = ""
        cleared()
    }

    function dismiss() {
        const source = pinnedSource || previewSource
        clear()
        dismissed(source)
    }

    function validateSelection() {
        if (rulesSession.gameId !== inspectedGameId) {
            clear()
            return
        }
        if (pinnedCardId && Object.keys(currentCard(pinnedCardId)).length === 0)
            pinnedCardId = ""
        if (previewCardId && Object.keys(currentCard(previewCardId)).length === 0)
            hidePreview()
    }

    function stateLines() {
        if (!hasCard)
            return ""
        const lines = []
        if (card.controllerSeat >= 0)
            lines.push(qsTr("Controller: Seat %1").arg(card.controllerSeat + 1))
        if (card.ownerSeat >= 0)
            lines.push(qsTr("Owner: Seat %1").arg(card.ownerSeat + 1))
        if (card.power || card.toughness)
            lines.push(qsTr("Power / toughness: %1 / %2").arg(card.power || "—")
                       .arg(card.toughness || "—"))
        if (card.zone === "battlefield") {
            lines.push(qsTr("Damage marked: %1").arg(card.damage || 0))
            lines.push(qsTr("Counters: %1").arg(card.countersSummary || qsTr("None")))
            lines.push(card.tapped ? qsTr("Tapped") : qsTr("Untapped"))
            if (card.attacking)
                lines.push(qsTr("Attacking"))
        }
        if (card.rulesText)
            lines.push("", card.rulesText)
        if (persistentSummary.length)
            lines.push(persistentSummary)
        return lines.join("\n")
    }

    onCurrentSnapshotRevisionChanged: validateSelection()
    onCurrentGameIdChanged: validateSelection()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.size(12)
        spacing: Theme.size(8)

        GridLayout {
            id: titleRow
            Layout.fillWidth: true
            columns: width >= closeButton.implicitWidth + Theme.size(148) ? 2 : 1
            columnSpacing: Theme.size(8)
            rowSpacing: Theme.size(8)
            Text {
                objectName: "rulesCardInspectorTitle"
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: !root.hasCard ? qsTr("Card preview")
                      : root.hasIdentity ? localFacePreview.displayName
                      : root.card.zone === "stack" && root.card.faceDown !== true
                        ? qsTr("Stack ability") : qsTr("Face-down card")
                color: Theme.text
                font.pixelSize: Theme.fontSize(14)
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            AppButton {
                id: closeButton
                objectName: "clearRulesCardInspectorButton"
                Layout.alignment: Qt.AlignRight
                visible: root.hasCard || root.showEmptyCloseButton
                text: qsTr("Close")
                compact: true
                onClicked: root.dismiss()
            }
        }

        Text {
            objectName: "rulesCardInspectorEmptyHint"
            textFormat: Text.PlainText
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.hasCard
            text: qsTr("Hover a card to see its image and current state. Right-click to keep it here.")
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize(12)
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        GridLayout {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            Layout.minimumHeight: 0
            Layout.preferredHeight: 0
            visible: root.hasCard
            columns: root.horizontalLayout ? 2 : 1
            columnSpacing: Theme.size(12)
            rowSpacing: Theme.size(8)

            Item {
                id: artwork
                Layout.minimumWidth: 0
                Layout.preferredWidth: root.horizontalLayout
                                       ? Math.min((root.width - Theme.size(24)) * 0.5,
                                                  root.availableBodyHeight * 63 / 88)
                                       : root.width - Theme.size(24)
                Layout.maximumWidth: root.horizontalLayout ? Layout.preferredWidth : Infinity
                Layout.fillWidth: !root.horizontalLayout
                Layout.preferredHeight: root.horizontalLayout ? root.availableBodyHeight
                                        : Math.min(naturalGalleryHeight, root.availableBodyHeight * 0.72)
                Layout.maximumHeight: Layout.preferredHeight
                Layout.fillHeight: root.horizontalLayout
                visible: root.hasIdentity || root.card.faceDown === true
                readonly property real naturalGalleryHeight: {
                    const count = Math.max(1, localFacePreview.displayFaces.length)
                    const availableWidth = Math.max(0, root.width - Theme.size(24))
                    const columns = count > 1 && availableWidth >= 2 * gallery.minimumFaceWidth + gallery.gap ? 2 : 1
                    const rows = Math.ceil(count / columns)
                    const faceWidth = Math.max(0, (availableWidth - (columns - 1) * gallery.gap) / columns)
                    return rows * faceWidth * 88 / 63 + (rows - 1) * gallery.gap
                }
                readonly property var gallerySize: gallery.fittedSize(Theme.size(320), width, height)

                CardFacePreviewGallery {
                    id: gallery
                    objectName: "rulesCardInspectorGallery"
                    controller: localFacePreview
                    artObjectName: "rulesCardInspectorArt"
                    fallbackObjectName: "rulesCardInspectorArtFallback"
                    anchors.centerIn: parent
                    width: artwork.gallerySize.width
                    height: artwork.gallerySize.height
                    columns: artwork.gallerySize.columns
                    visible: root.hasIdentity
                }
                Image {
                    id: hiddenArt
                    objectName: !root.hasIdentity ? "rulesCardInspectorArt" : ""
                    width: parent.width
                    height: parent.height
                    asynchronous: true
                    smooth: true
                    fillMode: Image.PreserveAspectFit
                    visible: !root.hasIdentity
                    source: root.hasCard && !root.hasIdentity ? root.cardBackSource : ""
                }
                Rectangle {
                    width: parent.width
                    height: parent.height
                    visible: !root.hasIdentity && hiddenArt.status !== Image.Ready
                    color: Theme.surfaceMuted
                    radius: Theme.radiusMedium
                    border.color: Theme.borderStrong
                    Text {
                        objectName: !root.hasIdentity ? "rulesCardInspectorArtFallback" : ""
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        width: parent.width - Theme.size(16)
                        height: parent.height - Theme.size(16)
                        text: qsTr("Face-down card")
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(15)
                        fontSizeMode: Text.Fit
                        minimumPixelSize: Theme.fontSize(9)
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        clip: true
                    }
                }
            }

            Flickable {
                id: stateScroll
                objectName: "rulesCardInspectorScroll"
                Layout.minimumWidth: 0
                Layout.minimumHeight: 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: stateColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Column {
                    id: stateColumn
                    width: stateScroll.width - Theme.size(12)
                    spacing: Theme.size(7)
                    Text {
                        objectName: "rulesCardInspectorStateHeading"
                        textFormat: Text.PlainText
                        width: parent.width
                        text: qsTr("Current game state")
                        color: Theme.primary
                        font.pixelSize: Theme.fontSize(11)
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                    }
                    Text {
                        objectName: "rulesCardInspectorState"
                        textFormat: Text.PlainText
                        width: parent.width
                        text: root.stateLines()
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(11)
                        lineHeight: 1.2
                        wrapMode: Text.Wrap
                    }
                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        visible: root.hasIdentity
                        text: qsTr("The image shows the printed card.")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(9)
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}
