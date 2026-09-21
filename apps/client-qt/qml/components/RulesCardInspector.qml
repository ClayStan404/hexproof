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
    property string previewCardId: ""
    property var previewSource: null
    property string inspectedGameId: ""
    property bool showEmptyCloseButton: false
    property bool preferVertical: false
    signal cleared()
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
    readonly property bool horizontalLayout: !preferVertical && (width >= Theme.size(500) || height < Theme.size(440))
    readonly property var attachment: {
        void rulesSession.snapshotRevision
        return card.attachedTo ? currentCard(card.attachedTo) : ({})
    }
    readonly property string exiledSummary: {
        void rulesSession.snapshotRevision
        if (!(card.exiledCardCount > 0)) return ""
        const names = (card.exiledCardIds || []).map(id => currentCard(id))
            .filter(linked => linked.visibleIdentity === true && !!linked.name)
            .map(linked => {
                if (!cardCatalogModel || typeof cardCatalogModel.cardDisplayName !== "function")
                    return linked.name
                void cardCatalogModel.language
                void cardCatalogModel.imageRevision
                return cardCatalogModel.cardDisplayName(linked.name)
            })
        const hidden = card.exiledCardCount - names.length
        if (hidden > 0) names.push(qsTr("%1 hidden card(s)").arg(hidden))
        return qsTr("Exiled with this card: %1").arg(names.join(", "))
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

    function showCard(id) {
        if (Object.keys(currentCard(id)).length === 0)
            return false
        inspectedGameId = rulesSession.gameId
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
        previewSource = source || null
        previewCardId = id
        stateScroll.contentY = 0
        return true
    }

    function hidePreview(source) {
        if (source && previewSource && source !== previewSource)
            return
        previewCardId = ""
        previewSource = null
    }

    function clear() {
        pinnedCardId = ""
        previewCardId = ""
        previewSource = null
        inspectedGameId = ""
        cleared()
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
        if (card.attachedTo) {
            const target = attachment.visibleIdentity === true && attachment.faceDown !== true
                           && attachment.name ? attachment.name : qsTr("another object")
            lines.push(qsTr("Attached to %1").arg(target))
        }
        if (card.rulesText)
            lines.push("", card.rulesText)
        if (exiledSummary.length)
            lines.push(exiledSummary)
        return lines.join("\n")
    }

    onCurrentSnapshotRevisionChanged: validateSelection()
    onCurrentGameIdChanged: validateSelection()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.size(12)
        spacing: Theme.size(8)

        RowLayout {
            Layout.fillWidth: true
            Text {
                objectName: "rulesCardInspectorTitle"
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: !root.hasCard ? qsTr("Card preview")
                      : root.hasIdentity ? root.displayName
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
                objectName: "clearRulesCardInspectorButton"
                visible: root.hasCard || root.showEmptyCloseButton
                text: qsTr("Close")
                compact: true
                onClicked: root.clear()
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
            visible: root.hasCard
            columns: root.horizontalLayout ? 2 : 1
            columnSpacing: Theme.size(12)
            rowSpacing: Theme.size(8)

            Item {
                id: artwork
                Layout.minimumWidth: 0
                Layout.preferredWidth: root.horizontalLayout
                                       ? Math.min(body.width * 0.5, body.height * 63 / 88)
                                       : body.width
                Layout.maximumWidth: root.horizontalLayout ? Layout.preferredWidth : Infinity
                Layout.fillWidth: !root.horizontalLayout
                Layout.preferredHeight: root.horizontalLayout ? body.height
                                        : Math.min(body.width * 88 / 63, body.height * 0.72)
                Layout.maximumHeight: Layout.preferredHeight
                Layout.fillHeight: root.horizontalLayout
                visible: root.hasIdentity || root.card.faceDown === true

                Image {
                    id: art
                    objectName: "rulesCardInspectorArt"
                    anchors.fill: parent
                    asynchronous: true
                    smooth: true
                    fillMode: Image.PreserveAspectFit
                    source: {
                        if (!root.hasCard)
                            return ""
                        if (!root.hasIdentity)
                            return root.cardBackSource
                        if (!root.cardCatalogModel
                                || typeof root.cardCatalogModel.imageSource !== "function")
                            return ""
                        void root.cardCatalogModel.imageRevision
                        return root.cardCatalogModel.imageSource(
                                    root.card.name, root.card.setCode || "",
                                    root.card.collectorNumber || "")
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    visible: art.status !== Image.Ready
                    color: Theme.surfaceMuted
                    radius: Theme.radiusMedium
                    border.color: Theme.borderStrong
                    Text {
                        objectName: "rulesCardInspectorArtFallback"
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        width: parent.width - Theme.size(16)
                        text: root.hasIdentity ? root.displayName : qsTr("Face-down card")
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(15)
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
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
                        textFormat: Text.PlainText
                        width: parent.width
                        text: qsTr("Current game state")
                        color: Theme.primary
                        font.pixelSize: Theme.fontSize(11)
                        font.weight: Font.DemiBold
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
