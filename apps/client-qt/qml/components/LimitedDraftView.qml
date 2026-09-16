// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "TournamentLobby"
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root
    implicitWidth: Theme.size(1100)
    implicitHeight: Theme.size(660)
    Layout.minimumWidth: 0
    Layout.minimumHeight: 0
    required property var limitedModel
    required property var tournamentModel
    required property var wsModel
    required property var cardCatalogModel
    property string selectedInstanceId: ""
    property var selectedInstanceIds: []
    property string pendingPickId: ""
    property int metadataRevision: 0
    property var cachedArtKeys: ({})
    property alias filters: pickFilters
    property alias inspectedCard: preview.card
    property alias hoverPreviewVisible: preview.visible
    property alias commanderPlan: draftCommanderPlan
    property var draftStore: typeof limitedDeckDrafts !== "undefined" ? limitedDeckDrafts : null
    readonly property string participantId: tournamentModel.participantId || ""
    readonly property int horizontalColumnsMinimumWidth: Theme.size(620)
    readonly property bool compactColumns: width < horizontalColumnsMinimumWidth
    readonly property bool compactTabs: compactColumns && height < Theme.size(560)
    property int compactPaneIndex: 0
    readonly property bool twoPlayer: limitedModel.participants.length === 2
    readonly property var enrichedPicks: {
        void metadataRevision
        if (!visible) return []
        return cardCatalogModel && typeof cardCatalogModel.enrichLimitedCards === "function"
                ? cardCatalogModel.enrichLimitedCards(limitedModel.pool || []) : limitedModel.pool || []
    }
    readonly property var visiblePickedCards: pickFilters.filter(enrichedPicks)
    readonly property var enrichedPack: {
        void metadataRevision
        if (!visible) return []
        return cardCatalogModel && typeof cardCatalogModel.enrichLimitedCards === "function"
                ? cardCatalogModel.enrichLimitedCards(limitedModel.currentPack || []) : limitedModel.currentPack || []
    }
    readonly property bool multiPick: limitedModel.eventType === "commander_cube"
    readonly property var ownDraftSeat: (limitedModel.participants || []).find(seat => seat.participantId === participantId) || ({})
    readonly property bool manualDraftControl: !ownDraftSeat.autoDraft && !ownDraftSeat.withdrawn
    readonly property int requiredPicks: Math.min(Number(limitedModel.picksRequired) || (multiPick ? 2 : 1), limitedModel.currentPack.length)
    readonly property var packGroups: {
        const parts = limitedModel.currentPacks || []
        if (!parts.length) return [{packId: "", cards: limitedModel.currentPack, picksRequired: requiredPicks}]
        return parts
    }
    readonly property bool pairedPacks: packGroups.length === 2
    readonly property string packLabel: Number(limitedModel.packsThisBatch) > 1
        ? qsTranslate("TournamentLobby", "Draft packs %1–%2 of %3")
            .arg(limitedModel.packRound - limitedModel.packsThisBatch + 1).arg(limitedModel.packRound).arg(limitedModel.packsPerPlayer)
        : qsTranslate("TournamentLobby", "Draft pack %1").arg(limitedModel.packRound)
    readonly property var selection: multiPick ? selectedInstanceIds : selectedInstanceId ? [selectedInstanceId] : []
    readonly property bool canConfirm: manualDraftControl && pendingPickId === "" && wsModel.connected !== false
        && requiredPicks > 0 && selection.length === requiredPicks
        && selection.every(id => limitedModel.currentPack.some(card => card.instanceId === id))
        && packGroups.every(part => selectedInPack(part).length === part.picksRequired)
    CardFilterState { id: pickFilters }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.size(8)

        SegmentedControl {
            objectName: "limitedDraftWorkspaceTabs"
            Layout.fillWidth: true
            visible: root.compactTabs
            implicitHeight: Theme.size(36)
            options: [root.packLabel,
                      qsTranslate("TournamentLobby", "Your picks") + " · " + root.limitedModel.pool.length]
            currentIndex: root.compactPaneIndex
            onActivated: index => {
                root.hideCardPreview()
                root.compactPaneIndex = index
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            columns: root.compactColumns ? 1 : 2
            columnSpacing: Theme.size(16)
            rowSpacing: Theme.size(12)
            ColumnLayout {
                objectName: "limitedDraftPackColumn"
                visible: !root.compactTabs || root.compactPaneIndex === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                Layout.minimumHeight: 0
                Layout.preferredHeight: root.compactColumns && !root.compactTabs ? root.height * 0.58 : root.height
                spacing: Theme.size(10)
                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Text {
                            textFormat: Text.PlainText
                            objectName: "limitedDraftPackHeader"
                            Layout.fillWidth: true
                            text: root.packLabel
                                  + " · " + qsTranslate("TournamentLobby", "%1 cards remaining").arg(root.limitedModel.currentPack.length)
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(19)
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: (root.limitedModel.direction > 0 ? "◀  " : "▶  ")
                                  + qsTranslate("TournamentLobby", "Pass to %1").arg(seatMap.outgoingName)
                                  + " · " + qsTranslate("TournamentLobby", "Receive from %1").arg(seatMap.incomingName)
                            color: Theme.accent
                            font.pixelSize: Theme.fontSize(11)
                            elide: Text.ElideRight
                        }
                    }
                    AppButton {
                        compact: true
                        text: qsTranslate("TournamentLobby", "Draft seats")
                        onClicked: seatsPopup.open()
                    }
                }
                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 0
                    columns: root.pairedPacks && width >= Theme.size(540) ? 2 : 1
                    columnSpacing: Theme.size(12)
                    rowSpacing: Theme.size(10)
                    Repeater {
                        model: root.packGroups.length
                        delegate: ColumnLayout {
                            id: packPane
                            required property int index
                            readonly property var pack: root.packGroups[index] || ({cards: [], picksRequired: 0})
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumWidth: 0
                            Layout.minimumHeight: 0
                            Text {
                                objectName: "limitedPackSelectionCount-" + packPane.index
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                visible: root.pairedPacks
                                text: qsTranslate("TournamentLobby", "Pack %1 · %2/%3 selected")
                                    .arg(packPane.index === 0 ? "A" : "B")
                                    .arg(root.selectedInPack(packPane.pack).length).arg(packPane.pack.picksRequired)
                                color: Theme.accent
                                font.pixelSize: Theme.fontSize(13)
                            }
                            CardArtGrid {
                                id: packGrid
                                objectName: packPane.index === 0 ? "limitedCurrentPackGrid" : "limitedCurrentPackGrid-2"
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 0
                                cards: root.enrichedPack.filter(card => packPane.pack.cards.some(value => value.instanceId === card.instanceId))
                                catalogModel: root.cardCatalogModel
                                cardObjectPrefix: "limitedDraftPackCard-"
                                doubleClickEnabled: true
                                maximumCardWidth: root.compactTabs
                                    ? Math.max(1, (height - Theme.size(26)) * 63 / 88) : Theme.size(250)
                                preferredCardWidth: root.pairedPacks ? Theme.size(110)
                                    : root.compactTabs ? Math.min(Theme.size(130), maximumCardWidth)
                                    : Math.max(Theme.size(130), Math.min(Theme.size(220),
                                    (height / 2 - Theme.size(26)) * 63 / 88))
                                selectedKey: root.selectedInstanceId
                                selectedKeys: root.selectedInstanceIds
                                enabled: root.manualDraftControl && root.pendingPickId === ""
                                emptyText: qsTranslate("TournamentLobby", "Waiting for the next pack…")
                                onCardActivated: card => root.selectCard(card.instanceId)
                                onCardDoubleActivated: card => root.confirmCard(card.instanceId)
                                onCardInspected: (card, sourceItem) => root.inspectCard(card, sourceItem)
                                onCardInspectionEnded: sourceItem => root.hideCardPreview(sourceItem)
                                onMovingChanged: if (moving) root.hideCardPreview()
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: root.ownDraftSeat.withdrawn ? qsTranslate("TournamentLobby", "You have withdrawn from this draft.")
                              : !root.manualDraftControl ? qsTranslate("TournamentLobby", "Automatic drafting is active. Reclaim your seat to choose cards.")
                              : root.pendingPickId ? qsTranslate("TournamentLobby", "Confirming pick…")
                              : root.multiPick ? qsTranslate("TournamentLobby", "Select %1 cards before passing · %2 selected")
                                .arg(root.requiredPicks).arg(root.selection.length)
                              : qsTranslate("TournamentLobby", "Click a card to select it")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(11)
                        elide: Text.ElideRight
                    }
                    AppButton {
                        objectName: "limitedConfirmPickButton"
                        compact: root.compactTabs
                        variant: "primary"
                        text: qsTranslate("TournamentLobby", "Confirm pick")
                        enabled: root.canConfirm
                        onClicked: root.confirmPick()
                    }
                }
            }
            Surface {
                objectName: "limitedDraftSideColumn"
                visible: !root.compactTabs || root.compactPaneIndex === 1
                Layout.fillWidth: root.compactColumns
                Layout.preferredWidth: Theme.size(310)
                Layout.maximumWidth: root.compactColumns ? root.width : Theme.size(350)
                Layout.minimumWidth: 0
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                Layout.preferredHeight: root.compactColumns && !root.compactTabs ? root.height * 0.4 : root.height
                color: Theme.surfaceMuted
                Flickable {
                    id: picksScroll
                    objectName: "limitedDraftPicksScroll"
                    anchors.fill: parent
                    anchors.margins: Theme.size(10)
                    contentWidth: width
                    contentHeight: picksContent.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { }
                    onMovingChanged: if (moving) root.hideCardPreview()
                    ColumnLayout {
                        id: picksContent
                        width: picksScroll.width
                        height: Math.max(picksScroll.height, implicitHeight)
                        spacing: Theme.size(8)
                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                Layout.fillWidth: true
                                Text {
                                    textFormat: Text.PlainText
                                    text: qsTranslate("TournamentLobby", "Your picks")
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSize(20)
                                    font.bold: true
                                }
                                Text {
                                    textFormat: Text.PlainText
                                    objectName: "limitedPickedCount"
                                    text: qsTranslate("TournamentLobby", "%1 cards").arg(root.limitedModel.pool.length)
                                    color: Theme.accent
                                }
                            }
                            CardManaCurve { cards: root.enrichedPicks }
                        }
                        CardFilterBar {
                            Layout.fillWidth: true
                            filters: pickFilters
                        }
                        CommanderDraftPlan {
                            id: draftCommanderPlan
                            objectName: "limitedDraftCommanderPlan"
                            Layout.fillWidth: true
                            visible: root.multiPick
                            active: root.visible && root.multiPick
                            cards: root.enrichedPicks
                            packCards: root.enrichedPack
                            catalogModel: root.cardCatalogModel
                            draftStore: root.draftStore
                            server: root.wsModel.serverUrl || ""
                            eventId: root.limitedModel.tournamentId || ""
                            participantId: root.participantId
                            onPreviewDismissed: root.hideCardPreview()
                        }
                        CardMetadataNotice {
                            Layout.fillWidth: true
                            cards: root.enrichedPicks
                        }
                        CompactCardList {
                            id: pickedCards
                            objectName: "limitedPickedCardGrid"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: Theme.size(120)
                            cards: root.visiblePickedCards
                            cardObjectPrefix: "limitedDraftPickedCard-"
                            emptyText: root.limitedModel.pool.length ? qsTranslate("TournamentLobby", "No cards match the current filters.")
                                                                    : qsTranslate("TournamentLobby", "Cards you draft will remain visible here.")
                            onCardInspected: (card, sourceItem) => root.inspectCard(card, sourceItem)
                            onCardInspectionEnded: sourceItem => root.hideCardPreview(sourceItem)
                            onMovingChanged: if (moving) root.hideCardPreview()
                            ScrollChainHandler {
                                innerFlickable: pickedCards
                                outerFlickable: picksScroll
                            }
                        }
                    }
                }
            }
        }
    }

    Popup {
        id: seatsPopup
        parent: Overlay.overlay
        width: Math.min(Theme.size(520), parent ? parent.width - Theme.size(24) : 520)
        height: Theme.size(270)
        x: parent ? (parent.width - width) / 2 : 0
        y: parent ? Math.max(0, (parent.height - height) / 2) : 0
        modal: true
        focus: true
        background: Surface { elevated: true }
        LimitedDraftSeatMap {
            id: seatMap
            objectName: "limitedDraftSeatMap"
            anchors.fill: parent
            participants: root.limitedModel.participants
            participantId: root.participantId
            direction: root.limitedModel.direction
        }
    }
    CardHoverPreview {
        id: preview
        objectName: "limitedDraftCardHoverPreview"
        artObjectName: "limitedDraftCardHoverPreviewArt"
        catalogModel: root.cardCatalogModel
    }
    Connections {
        target: root.limitedModel
        function onSnapshotChanged() {
            const inspectedId = preview.card.instanceId
            if (preview.visible && !root.limitedModel.currentPack.concat(root.limitedModel.pool)
                    .some(card => card.instanceId === inspectedId))
                root.hideCardPreview()
            if (!root.limitedModel.currentPack.some(card => card.instanceId === root.selectedInstanceId))
                root.selectedInstanceId = ""
            root.selectedInstanceIds = root.selectedInstanceIds.filter(
                id => root.limitedModel.currentPack.some(card => card.instanceId === id))
            if (!root.limitedModel.currentPack.some(card => card.instanceId === root.pendingPickId))
                root.pendingPickId = ""
        }
    }
    Connections {
        target: root.wsModel
        ignoreUnknownSignals: true
        function onCommandFailed(requestId, commandType, code, message) {
            if (commandType === "limited.pick") root.pendingPickId = ""
        }
        function onConnectedChanged() {
            if (!root.wsModel.connected) root.pendingPickId = ""
        }
    }
    Connections {
        target: root.cardCatalogModel
        ignoreUnknownSignals: true
        function onCatalogChanged() { root.metadataRevision++ }
        function onLanguageChanged() {
            root.cachedArtKeys = ({})
            root.metadataRevision++
        }
    }
    Component.onCompleted: cacheVisibleCards()
    onVisibleChanged: {
        if (!visible) hideCardPreview()
        else cacheVisibleCards()
    }
    onEnrichedPackChanged: cacheVisibleCards()
    onEnrichedPicksChanged: cacheVisibleCards()
    function confirmPick() {
        if (!canConfirm) return
        const ids = selection.slice()
        pendingPickId = ids[0]
        selectedInstanceId = ""
        selectedInstanceIds = []
        hideCardPreview()
        if (multiPick) wsModel.pickLimitedCards(ids)
        else wsModel.pickLimitedCard(ids[0])
    }
    function selectCard(instanceId) {
        if (!manualDraftControl || pendingPickId !== "" || !limitedModel.currentPack.some(card => card.instanceId === instanceId)) return
        if (!multiPick) {
            selectedInstanceId = instanceId
            return
        }
        const ids = selectedInstanceIds.slice()
        const index = ids.indexOf(instanceId)
        if (index >= 0) ids.splice(index, 1)
        else {
            const part = packGroups.find(value => value.cards.some(card => card.instanceId === instanceId))
            if (!part || part.picksRequired < 1) return
            const inPack = selectedInPack(part)
            if (inPack.length >= part.picksRequired) ids.splice(ids.indexOf(inPack[0]), 1)
            ids.push(instanceId)
        }
        selectedInstanceIds = ids
    }
    function selectedInPack(part) {
        return selection.filter(id => part.cards.some(card => card.instanceId === id))
    }
    function confirmCard(instanceId) {
        if (!manualDraftControl || pendingPickId !== "" || !limitedModel.currentPack.some(card => card.instanceId === instanceId)) return
        if (multiPick) {
            if (selectedInstanceIds.indexOf(instanceId) < 0) selectCard(instanceId)
        } else selectedInstanceId = instanceId
        confirmPick()
    }
    function inspectCard(card, item) { preview.inspect(card, item) }
    function hideCardPreview(item) { preview.hide(item) }
    function cacheVisibleCards() {
        if (!visible || !cardCatalogModel || typeof cardCatalogModel.cacheCardsIncrementally !== "function") return
        const fresh = (limitedModel.currentPack || []).concat(limitedModel.pool || []).filter(card => {
            const key = JSON.stringify([card.name, card.setCode || "", card.collectorNumber || ""])
            if (cachedArtKeys[key]) return false
            cachedArtKeys[key] = true
            return true
        })
        if (fresh.length) cardCatalogModel.cacheCardsIncrementally(fresh)
    }
}
