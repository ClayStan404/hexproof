// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "TournamentLobby"
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root
    property var cards: []
    property var packCards: []
    property var catalogModel: null
    property bool active: false
    property var draftStore: null
    property string server: ""
    property string eventId: ""
    property string participantId: ""
    property var selectedIds: []
    property string restoredScope: ""
    property bool initialized: false
    property bool showAll: false
    property alias searchText: search.text
    property alias inspectedCard: candidatePreview.card
    property alias hoverPreviewVisible: candidatePreview.visible
    readonly property string storageEvent: eventId ? JSON.stringify(["commander-draft-plan", eventId]) : ""
    readonly property string scope: server && storageEvent && participantId
        ? JSON.stringify([server, storageEvent, participantId]) : ""
    readonly property var selectedCards: selectedIds.map(id => cards.find(card => card.instanceId === id)).filter(Boolean)
    readonly property bool identityKnown: selectedCards.length > 0 && selectedCards.every(card => knownIdentity(card))
    readonly property var identityColors: ["W", "U", "B", "R", "G"].filter(color =>
        selectedCards.some(card => knownIdentity(card) && String(card.colors).includes(color)))
    readonly property var poolGuide: guidance(cards)
    readonly property var packGuide: guidance(packCards)
    readonly property var visibleCards: cards.filter(card => {
        if (!showAll && !possibleCommander(card) && selectedIds.indexOf(card.instanceId) < 0) return false
        const query = search.text.trim().toLowerCase()
        return !query || [card.name, card.displayName, card.typeLine, card.setCode, card.collectorNumber]
            .some(value => String(value || "").toLowerCase().includes(query))
    })
    signal cardInspected(var card, var sourceItem)
    signal cardInspectionEnded(var sourceItem)
    signal previewDismissed()
    onCardInspected: (card, sourceItem) => {
        candidatePreview.inspect(card, sourceItem)
        positionPreview()
    }
    onCardInspectionEnded: sourceItem => candidatePreview.hide(sourceItem)
    onPreviewDismissed: candidatePreview.hide()
    implicitHeight: planContent.implicitHeight

    ColumnLayout {
        id: planContent
        width: root.width
        spacing: Theme.size(5)
        AppButton {
            objectName: "commanderDraftPlanButton"
            Layout.fillWidth: true
            compact: true
            text: qsTranslate("TournamentLobby", "Commander plan · %1 / 2").arg(root.selectedIds.length)
            onClicked: { root.previewDismissed(); picker.open() }
        }
        Text {
            textFormat: Text.PlainText
            objectName: "commanderDraftPlanNames"
            Layout.fillWidth: true
            visible: root.selectedCards.length > 0
            text: root.selectedCards.map(card => "★ " + (card.displayName || card.name)).join(" / ")
            color: Theme.accent
            font.pixelSize: Theme.fontSize(11)
            wrapMode: Text.WordWrap
        }
        RowLayout {
            visible: root.identityKnown
            Layout.fillWidth: true
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: qsTranslate("TournamentLobby", "Planned color identity")
                font.pixelSize: Theme.fontSize(11)
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
            }
            Repeater {
                model: root.identityColors.length ? root.identityColors : ["C"]
                delegate: CardManaSymbol { required property string modelData; symbol: modelData }
            }
        }
        Text {
            textFormat: Text.PlainText
            objectName: "commanderDraftIdentityGuide"
            Layout.fillWidth: true
            visible: root.selectedCards.length > 0
            text: !root.identityKnown
                ? qsTranslate("TournamentLobby", "Color identity is incomplete. Choose Piper colors during deck building; check missing card data manually.")
                : qsTranslate("TournamentLobby", "Outside planned identity: %1 picked · %2 in pack").arg(root.poolGuide.outside).arg(root.packGuide.outside)
                    + ((root.poolGuide.unknown + root.packGuide.unknown) > 0
                        ? "\n" + qsTranslate("TournamentLobby", "%1 cards have unknown identity.").arg(root.poolGuide.unknown + root.packGuide.unknown) : "")
            color: !root.identityKnown || root.poolGuide.outside ? Theme.warning : Theme.textMuted
            font.pixelSize: Theme.fontSize(10)
            wrapMode: Text.WordWrap
        }
    }

    Popup {
        id: picker
        objectName: "commanderDraftPlanPicker"
        parent: Overlay.overlay
        width: Math.min(Theme.size(560), parent ? Math.max(0, parent.width - Theme.size(24)) : Theme.size(560))
        height: Math.min(Theme.size(620), parent ? Math.max(0, parent.height - Theme.size(24)) : Theme.size(620))
        x: parent ? (parent.width - width) / 2 : 0
        y: parent ? Math.max(0, (parent.height - height) / 2) : 0
        modal: true
        focus: true
        padding: Theme.size(14)
        background: Surface { elevated: true }
        onClosed: root.previewDismissed()
        onXChanged: root.positionPreview()
        onWidthChanged: root.positionPreview()
        contentItem: ColumnLayout {
            spacing: Theme.size(8)
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTranslate("TournamentLobby", "Commander plan · %1 / 2").arg(root.selectedIds.length)
                font.pixelSize: Theme.fontSize(20)
                font.bold: true
                color: Theme.text
                wrapMode: Text.WordWrap
            }
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTranslate("TournamentLobby", "Mark up to two drafted cards for planning only. Confirm commanders and partner rules when building your deck. Picks are never restricted by this guide.")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(11)
                wrapMode: Text.WordWrap
            }
            SegmentedControl {
                objectName: "commanderDraftCandidateMode"
                Layout.fillWidth: true
                options: [qsTranslate("TournamentLobby", "Possible commanders"), qsTranslate("TournamentLobby", "All drafted cards")]
                currentIndex: root.showAll ? 1 : 0
                onActivated: index => { root.previewDismissed(); root.showAll = index === 1 }
            }
            AppTextField {
                id: search
                objectName: "commanderDraftPlanSearch"
                Layout.fillWidth: true
                placeholderText: qsTranslate("TournamentLobby", "Search cards...")
                onTextChanged: root.previewDismissed()
            }
            ListView {
                id: candidateList
                objectName: "commanderDraftPlanCandidates"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                clip: true
                spacing: Theme.size(8)
                model: root.visibleCards
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { }
                onMovingChanged: if (moving) root.previewDismissed()
                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    width: parent.width
                    visible: candidateList.count === 0
                    text: root.cards.length === 0 ? qsTranslate("TournamentLobby", "Draft cards before marking commanders.")
                        : qsTranslate("TournamentLobby", "No matching candidates. Use All drafted cards for house rules.")
                    color: Theme.textMuted
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
                delegate: ColumnLayout {
                    id: row
                    required property var modelData
                    readonly property bool marked: root.selectedIds.indexOf(modelData.instanceId) >= 0
                    width: candidateList.width - Theme.size(10)
                    spacing: Theme.size(3)
                    RowLayout {
                        Layout.fillWidth: true
                        CardListRow {
                            id: cardRow
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            card: row.modelData
                            highlighted: row.marked || hover.hovered
                            TapHandler { onTapped: root.toggle(row.modelData.instanceId) }
                            HoverHandler {
                                id: hover
                                onHoveredChanged: {
                                    if (hovered) root.cardInspected(row.modelData, cardRow)
                                    else root.cardInspectionEnded(cardRow)
                                }
                            }
                        }
                        AppButton {
                            objectName: "commanderDraftMark-" + row.modelData.instanceId
                            compact: true
                            implicitWidth: Theme.size(40)
                            text: row.marked ? "★" : "☆"
                            variant: row.marked ? "primary" : "secondary"
                            enabled: row.marked || root.selectedIds.length < 2
                            Accessible.name: (row.marked ? qsTranslate("TournamentLobby", "Unmark planned commander")
                                : qsTranslate("TournamentLobby", "Mark planned commander")) + ": " + (row.modelData.displayName || row.modelData.name)
                            Accessible.checkable: true
                            Accessible.checked: row.marked
                            onClicked: root.toggle(row.modelData.instanceId)
                        }
                    }
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: root.candidateHint(row.modelData)
                        font.pixelSize: Theme.fontSize(10)
                        color: Theme.textMuted
                        wrapMode: Text.WordWrap
                    }
                }
            }
            AppButton {
                objectName: "commanderDraftPlanDone"
                Layout.fillWidth: true
                text: qsTranslate("TournamentLobby", "Done")
                variant: "primary"
                onClicked: picker.close()
            }
        }
    }
    CardHoverPreview {
        id: candidatePreview
        objectName: "commanderDraftPlanPreview"
        artObjectName: "commanderDraftPlanPreviewArt"
        // Popup candidates live in the overlay. Keep their preview above the
        // modal scrim instead of behind it in the underlying draft workspace.
        parent: picker.parent || root
        catalogModel: root.catalogModel
        onWidthChanged: root.positionPreview()
    }

    function positionPreview() {
        if (!candidatePreview || !candidatePreview.visible || !picker.parent) return
        // Avoid covering the mark/unmark controls beside the hovered row. On
        // compact screens the left preview may overlap names, but not actions.
        const right = picker.x + picker.width + Theme.size(12)
        candidatePreview.x = right + candidatePreview.width <= picker.parent.width
            ? right : Math.max(0, picker.x - candidatePreview.width - Theme.size(12))
    }

    function possibleCommander(card) {
        const type = String(card.typeLine || "")
        if (!type) return true
        return (/legendary/i.test(type) && /creature|background/i.test(type))
            || /can be your commander/i.test(String(card.oracleText || ""))
    }
    function candidateHint(card) {
        if (!card.typeLine) return qsTranslate("TournamentLobby", "Commander eligibility is unknown; check this card manually.")
        if (/(^|\n)(partner\b|friends forever\b|choose a background\b|doctor's companion\b)/i.test(String(card.oracleText || "")))
            return qsTranslate("TournamentLobby", "Has a two-commander ability; check the exact pairing rules.")
        return String(card.typeLine || "")
    }
    function knownIdentity(card) {
        return String(card.name || "").trim().toLowerCase() !== "the prismatic piper"
            && typeof card.colors === "string" && /^[WUBRG]*$/.test(card.colors)
    }
    function guidance(source) {
        if (!identityKnown) return {outside: 0, unknown: source.length}
        let outside = 0, unknown = 0
        for (const card of source) {
            if (!knownIdentity(card)) { unknown++; continue }
            if (String(card.colors).split("").some(color => identityColors.indexOf(color) < 0)) outside++
        }
        return {outside: outside, unknown: unknown}
    }
    function sanitize(ids) {
        // The native draft store returns a QVariantList, not a JavaScript Array.
        if (!ids || typeof ids === "string" || typeof ids.length !== "number") return []
        const seen = new Set()
        const result = []
        for (const id of ids) {
            if (seen.has(id) || !cards.some(card => card.instanceId === id)) continue
            seen.add(id)
            result.push(id)
            if (result.length === 2) break
        }
        return result
    }
    function toggle(id) {
        if (!active || !cards.some(card => card.instanceId === id)) return
        if (selectedIds.indexOf(id) >= 0) selectedIds = selectedIds.filter(value => value !== id)
        else if (selectedIds.length < 2) selectedIds = selectedIds.concat([id])
        else return
        save()
    }
    function save() {
        if (draftStore && scope && active) draftStore.saveDraft(server, storageEvent, participantId, {plannedCommanderIds: selectedIds})
    }
    function restore() {
        if (!initialized || !active) return
        if (restoredScope !== scope) {
            selectedIds = []
            if (!cards.length) return
            const draft = draftStore && scope ? draftStore.loadDraft(server, storageEvent, participantId) : ({})
            selectedIds = sanitize(draft.plannedCommanderIds)
            restoredScope = scope
        } else if (cards.length) {
            const ids = sanitize(selectedIds)
            if (JSON.stringify(ids) !== JSON.stringify(selectedIds)) { selectedIds = ids; save() }
        }
    }
    onScopeChanged: {
        picker.close()
        candidatePreview.hide()
        selectedIds = []
        restoredScope = ""
        if (initialized) Qt.callLater(restore)
    }
    onCardsChanged: if (initialized) Qt.callLater(restore)
    onDraftStoreChanged: {
        restoredScope = ""
        if (initialized) Qt.callLater(restore)
    }
    onActiveChanged: {
        if (!active) picker.close()
        else if (initialized) Qt.callLater(restore)
    }
    Component.onCompleted: { initialized = true; restore() }
}
