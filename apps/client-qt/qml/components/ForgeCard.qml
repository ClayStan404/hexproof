// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
import QtQuick

Rectangle {
    id: root
    required property var tableController
    required property var card
    property real unit: 1
    property bool fullFace: false
    property bool pointerEnabled: true
    property bool exclusiveTap: false
    property bool hoverPreview: true
    property bool tabStop: pointerEnabled
    property bool located: false
    property string objectKind: "card"
    property real attachmentStripHeight: 0
    // +1 keeps the label below the face. Opponent creature rows pass -1 so
    // the label sits on the outer side, away from the center phase strip.
    property int hintSide: 1
    readonly property string objectId: card.cardId || card.objectId || ""
    readonly property bool publicFace: card.visibleIdentity !== false && !card.faceDown && !!card.name
    ForgeArtStamp {
        id: artStamp
        catalog: root.tableController.cardCatalogModel
        name: root.card && root.card.name ? root.card.name : ""
    }
    readonly property var artCatalog: tableController.cardCatalogModel
    readonly property string artIdentity: publicFace && !fullFace
        ? card.name + "\u001f" + (card.setCode || "") + "\u001f" + (card.collectorNumber || "") : ""
    property string resolvedArtFrame: "full"
    property string resolvedArtCropSource: ""
    readonly property string artFrame: publicFace && !fullFace ? resolvedArtFrame : "full"
    readonly property bool usingArtCrop: publicFace && !fullFace
        && artCrop.source.toString().length > 0 && artCrop.status === Image.Ready
    function refreshArtFrame() {
        resolvedArtFrame = "full"
        resolvedArtCropSource = ""
        // Lane model roles can change one by one during a snapshot update.
        // Query only after the final visible face and printing are coherent.
        Qt.callLater(resolveArtFrame)
    }
    function resolveArtFrame() {
        if (!publicFace || fullFace || !artCatalog)
            return
        if (typeof artCatalog.cardArtFrame === "function")
            resolvedArtFrame = artCatalog.cardArtFrame(card.name, card.setCode || "", card.collectorNumber || "")
        if (typeof artCatalog.tableArtCropSource === "function")
            resolvedArtCropSource = artCatalog.tableArtCropSource(card.name, card.setCode || "", card.collectorNumber || "")
    }
    onArtIdentityChanged: refreshArtFrame()
    onArtCatalogChanged: refreshArtFrame()
    Connections {
        target: artStamp
        function onStampChanged() { root.refreshArtFrame() }
    }
    readonly property rect artRegion: {
        switch (artFrame) {
        case "planeswalker": return Qt.rect(0.08, 0.14, 0.84, 0.34)
        case "saga": return Qt.rect(0.51, 0.22, 0.40, 0.53)
        case "class": return Qt.rect(0.11, 0.13, 0.36, 0.64)
        case "battle": return Qt.rect(0.12, 0.14, 0.82, 0.40)
        case "flip": return Qt.rect(0.08, 0.32, 0.84, 0.33)
        case "flip-back": return Qt.rect(0.08, 0.35, 0.84, 0.33)
        default: return Qt.rect(0.08, 0.14, 0.84, 0.43)
        }
    }
    readonly property int artRotation: artFrame === "battle" ? 90 : artFrame === "flip-back" ? 180 : 0
    readonly property string displayName: {
        void artStamp.stamp
        const catalog = tableController.cardCatalogModel
        if (!publicFace)
            return ""
        if (catalog && typeof catalog.cardDisplayName === "function") {
            void catalog.language
            return catalog.cardDisplayName(card.name)
        }
        return card.name
    }
    readonly property var combat: tableController.combatInteraction
    readonly property string persistentSummary: persistentState.boardSummary
    readonly property string loyaltyName: qsTranslate("RulesCounters", "Loyalty")
    property real markPulse: 1
    property bool marksReady: false
    property int primedDamage: 0
    property string primedMarks: ""
    function noteMarks() {
        const damage = card && card.damage ? Number(card.damage) : 0
        const marks = (otherCounters || "") + "\n" + (loyaltyAmount || "")
        if (marksReady && Theme.motionEnabled && !Theme.motionSnap
                && (damage !== primedDamage || marks !== primedMarks))
            markPulseAnim.restart()
        primedDamage = damage
        primedMarks = marks
    }
    property real arrivalOpacity: 1
    // Darkens the art of a tapped permanent. Stats and counters stay above it.
    readonly property real tappedShade: 0.4
    readonly property bool faceTapped: !!(card && card.tapped)
    property bool tapReady: false
    property real tapShade: 0
    function applyTapShade() {
        const target = faceTapped ? 1 : 0
        if (tapReady && Theme.motionEnabled && !Theme.motionSnap && tapShade !== target) {
            tapShadeAnim.to = target
            tapShadeAnim.restart()
        } else {
            tapShadeAnim.stop()
            tapShade = target
        }
    }
    onFaceTappedChanged: applyTapShade()
    NumberAnimation {
        id: tapShadeAnim
        target: root
        property: "tapShade"
        duration: Theme.motionFast
        easing.type: Easing.OutCubic
    }
    Component.onCompleted: {
        refreshArtFrame()
        applyTapShade()
        tapReady = true
        noteMarks()
        marksReady = true
        // Only objects that just arrived fade in. Table entry, reconnects and
        // zone browsers show existing cards at once.
        const presentation = tableController.presentation
        const delay = Theme.motionEnabled && !Theme.motionSnap && presentation
                && typeof presentation.arrivalDelay === "function" ? presentation.arrivalDelay(objectId) : -1
        if (delay >= 0) {
            arrivalOpacity = 0
            arrivalWait.interval = Math.max(1, delay)
            arrivalWait.start()
        }
    }
    Timer {
        id: arrivalWait
        onTriggered: arrivalFade.restart()
    }
    NumberAnimation {
        id: arrivalFade
        target: root
        property: "arrivalOpacity"
        to: 1
        duration: Theme.motionFast
        easing.type: Easing.OutCubic
    }
    Connections {
        target: Theme
        function onMotionEpochChanged() {
            arrivalWait.stop()
            arrivalFade.stop()
            root.arrivalOpacity = 1
            tapShadeAnim.stop()
            root.tapShade = root.faceTapped ? 1 : 0
            artFadeAnim.stop()
            art.artFade = 1
            markPulseAnim.stop()
            root.markPulse = 1
            blockedShake.stop()
            blockedShift.x = 0
        }
    }
    readonly property int markWatchDamage: card ? Number(card.damage) || 0 : 0
    readonly property string markWatchText: (otherCounters || "") + "\n" + (loyaltyAmount || "")
    onMarkWatchDamageChanged: noteMarks()
    onMarkWatchTextChanged: noteMarks()
    SequentialAnimation {
        id: markPulseAnim
        NumberAnimation { target: root; property: "markPulse"; to: 1.12; duration: Theme.motionNormal / 2; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "markPulse"; to: 1; duration: Theme.motionNormal / 2; easing.type: Easing.OutCubic }
    }
    readonly property string loyaltyAmount: {
        const prefix = loyaltyName + " × "
        const part = (card.countersSummary || "").split(" · ").find(item => item.indexOf(prefix) === 0)
        return part ? part.slice(prefix.length) : ""
    }
    readonly property string otherCounters: (card.countersSummary || "").split(" · ")
        .filter(item => item.length && item.indexOf(loyaltyName + " × ") !== 0).join(" · ")
    RulesCardPersistentState {
        id: persistentState
        card: root.card
        rulesSession: root.tableController.rulesSession
        cardCatalogModel: root.tableController.cardCatalogModel
    }
    // A closed pile labels the exact member that a click would activate. The
    // latest undoable source can be behind a same-name tapped front.
    readonly property var interactionCard: card && !fullFace && card.stackFront === true
        && card.fanned !== true && (card.stackSize || 1) > 1
        && (!combat || !combat.active)
        && ["chooseAction", "payManaCost"].includes(tableController.rulesSession.promptKind)
        && typeof card.stackInteractionCard === "function" ? card.stackInteractionCard() : card
    readonly property bool summarized: !!(card && typeof card.hintKey === "string")
    readonly property string hintKey: summarized ? interactionCard.hintKey : ""
    readonly property int offeredActionCount: summarized && interactionCard.actionCount ? Number(interactionCard.actionCount) : 0
    readonly property int offeredTargetCount: summarized && card.targetCount ? Number(card.targetCount) : 0
    readonly property bool nativeSelected: objectKind === "card" && summarized
        ? card.nativeTargetSelected === true
        : tableController.interaction.nativeObjectSelected(objectKind, objectId)
    readonly property string combatObjectId: combat && combat.active && objectKind === "card"
        && card && typeof card.stackActivateId === "function"
        ? (card.stackActivateId() || objectId) : objectId
    readonly property bool offered: combat && combat.active && objectKind === "card"
        ? combat.offered(combatObjectId)
        : objectKind === "card" && summarized
          ? tableController.interaction.contextActive
            && (offeredActionCount > 0 || offeredTargetCount === 1)
          : tableController.interaction.objectOffered(objectKind, objectId)
    readonly property bool actionable: offered && (combat && combat.active && objectKind === "card"
        ? combat.canAct : tableController.interaction.canRespond)
    readonly property bool waiting: offered && tableController.interaction.waitingForResponse
    // A closed pile shows the marks of the members hidden behind its front.
    readonly property var pileMemberIds: card && card.stackFront === true && card.fanned !== true
        && card.stackSize > 1 && card.memberIds ? card.memberIds : [objectId]
    readonly property bool submitted: objectId.length > 0
        && tableController.interaction.submittedKind === objectKind
        && pileMemberIds.indexOf(tableController.interaction.submittedId) >= 0
    readonly property bool combatDestination: combat && combat.active && objectKind === "card"
        && combat.targetActionable(objectId)
    readonly property bool combatHovered: combatDestination && combat.hoveredTarget
        && combat.hoveredTarget.objectId === objectId
    readonly property bool selected: located || (combat && combat.active && objectKind === "card"
        ? combat.selected(objectId) : tableController.interaction.objectSelected(objectKind, objectId))
    readonly property string combatLabel: combat && combat.active ? combat.labelFor(objectId) : ""
    readonly property bool pointerPreviewActive: hover.hovered
    readonly property bool previewActive: pointerEnabled && visible && (hover.hovered || activeFocus)
        && !(combat && combat.canAct && combat.chosenSource)
    readonly property bool abilityActionable: objectKind === "card" && !fullFace
        && (!combat || !combat.active)
        && tableController.interaction.canRespond
        && (hintKey === "activate" || hintKey === "pay")
    readonly property bool undoingMana: objectKind === "card" && !fullFace
        && (!combat || !combat.active)
        && ["chooseAction", "payManaCost"].includes(tableController.rulesSession.promptKind)
        && tableController.interaction.canRespond
        && hintKey === "undo"
    readonly property bool payingMana: abilityActionable
        && tableController.rulesSession.promptKind === "payManaCost"
        && !undoingMana
    // The outline keeps the payment color while an answer is in flight. The
    // hint labels above stay on the actionable properties, so they hide.
    readonly property bool offeredUndo: objectKind === "card" && !fullFace
        && (!combat || !combat.active)
        && tableController.interaction.contextActive
        && ["chooseAction", "payManaCost"].includes(tableController.rulesSession.promptKind)
        && hintKey === "undo"
    readonly property bool offeredPayment: objectKind === "card" && !fullFace
        && (!combat || !combat.active)
        && tableController.rulesSession.promptKind === "payManaCost"
        && hintKey === "pay"
    readonly property bool showAbilityHint: abilityActionable && previewActive && !payingMana && !undoingMana
    readonly property string attackLabel: {
        if (!card || card.attacking !== true)
            return ""
        const seat = card.attackingSeat
        if (seat >= 0 && !card.attackingTarget) {
            if (seat === tableController.localSeat)
                return qsTr("Attacking you")
            const name = tableController.matchUi && typeof tableController.matchUi.playerName === "function"
                ? tableController.matchUi.playerName(seat) : ""
            return name ? qsTr("Attacking %1").arg(name) : qsTr("Attacking a player")
        }
        if (card.attackingTarget) {
            const other = tableController.rulesSession.cardForInspection(card.attackingTarget)
            const name = other && other.visibleIdentity && !other.faceDown && other.name
                ? (typeof tableController.cardDisplayName === "function"
                   ? tableController.cardDisplayName(other.name) : other.name)
                : qsTr("a permanent")
            return qsTr("Attacking %1").arg(name)
        }
        return qsTr("Attacking")
    }
    readonly property bool attackTarget: !!(card && card.attackedByIds && card.attackedByIds.length)
    readonly property string interactionLabel: undoingMana ? qsTr("Undo mana")
        : payingMana ? qsTr("Tap for mana")
        : showAbilityHint ? qsTr("Activate ability")
        : combatLabel || [attackLabel, persistentState.relationshipBadge].filter(value => value.length).join(" · ")
    readonly property bool opponentChanged: {
        const ids = tableController.presentation ? tableController.presentation.opponentChangeIds : []
        return !!objectId && !!ids && ids.indexOf(objectId) >= 0
    }
    readonly property string queuedPaymentLabel: {
        const queue = tableController.interaction ? tableController.interaction.paymentQueue : []
        if (!objectId || !queue || !queue.length)
            return ""
        return pileMemberIds.map(id => queue.indexOf(id)).filter(index => index >= 0)
            .sort((left, right) => left - right).map(index => String(index + 1)).join(" ")
    }
    signal activated()

    // Public readout geometry only. The table clips relationship strokes at
    // these painted regions without moving the card or duplicating its text.
    function readoutRects(target) {
        if (!visible) return []
        void x; void y; void width; void height; void blockedShift.x; void markPulse
        const body = faceBody.mapToItem(target, 0, 0, faceBody.width, faceBody.height)
        const result = []
        function add(item, clipped, textHeight) {
            if (!item.visible || item.width <= 0 || item.height <= 0) return
            void item.x; void item.y; void item.scale
            const height = textHeight === undefined ? item.height : textHeight
            const rect = item.mapToItem(target, 0, item.height - height, item.width, height)
            const left = clipped ? Math.max(rect.x, body.x) : rect.x
            const top = clipped ? Math.max(rect.y, body.y) : rect.y
            const right = clipped ? Math.min(rect.x + rect.width, body.x + body.width) : rect.x + rect.width
            const bottom = clipped ? Math.min(rect.y + rect.height, body.y + body.height) : rect.y + rect.height
            if (right > left && bottom > top) result.push(Qt.rect(left, top, right - left, bottom - top))
        }
        add(cardNameLabel, true)
        add(powerBadge, true)
        // The state label fills spare card height; only its bottom-aligned
        // painted lines and background exclude strokes, not that empty space.
        add(stateBackdrop, true)
        if (cardStateLabel.text.length)
            add(cardStateLabel, true, Math.min(cardStateLabel.implicitHeight, cardStateLabel.height))
        add(loyaltyBadge, true)
        add(paymentQueueBadge, false)
        add(interactionHint, false)
        return result
    }

    function activationIntent() {
        const session = tableController.rulesSession
        const interaction = tableController.interaction
        const choice = card && typeof card.stackChoice === "function" ? card.stackChoice() : null
        const chosenId = choice ? (choice.id || objectId) : objectId
        return {gameId:session.gameId, promptId:session.promptId, promptKind:session.promptKind,
            paymentId:session.promptPaymentId, localSeat:tableController.localSeat,
            waiting:interaction.waitingForResponse, chosenId:chosenId, fan:choice && choice.fan,
            actions:JSON.stringify(interaction.offeredActionsForCard(chosenId))}
    }
    function intentStillCurrent(intent) {
        const current = activationIntent()
        return intent.gameId === current.gameId && intent.promptId === current.promptId
            && intent.promptKind === current.promptKind && intent.paymentId === current.paymentId
            && intent.localSeat === current.localSeat && intent.waiting === current.waiting
            && intent.actions === current.actions
    }
    function activate(intent) {
        Theme.finishMotion()
        // A pointer press belongs to its decision. The game can advance before
        // release, but that must not reinterpret a mana click as a new undo.
        if (intent && !intentStillCurrent(intent))
            return
        const choice = intent || activationIntent()
        if (choice.fan) {
            SoundEffects.play("select")
            card.openFan()
            activated()
            return
        }
        const chosenId = choice.chosenId
        if (combat && combat.active && objectKind === "card" && combat.activate(chosenId)) return
        if (!tableController.interaction.activateObject(objectKind, chosenId, publicFace ? card.name : "") && waiting) {
            if (Theme.motionEnabled)
                blockedShake.restart()
            tableController.interaction.responseBlocked(objectKind, objectId)
        }
        activated()
    }
    onActiveFocusChanged: {
        // Gaining keyboard focus while already hovered does not change the
        // combined previewActive value. It is still a new inspection intent.
        if (activeFocus && previewActive && hover.hovered)
            tableController.previewCard(objectId, root, true)
    }
    onPreviewActiveChanged: {
        if (previewActive) tableController.previewCard(objectId, root, activeFocus)
        else tableController.endCardPreview(root)
    }
    Component.onDestruction: {
        if (previewActive) tableController.endCardPreview(root)
        if (combat && objectKind === "card" && hover.hovered) combat.hoverCard(objectId, false)
    }
    width: 180 * unit
    height: width * (fullFace ? 1.394 : 0.93)
    radius: 4 * unit
    antialiasing: true
    readonly property color strokeColor: combatHovered ? Theme.primary : selected ? Theme.accent
                    : offeredUndo ? "#7ebcca"
                    : offeredPayment ? "#e1bd7f"
                    : combatDestination ? (combat.attacking ? "#e1bd7f" : "#7ebcca")
                    : attackTarget ? "#d4654f"
                    : offered ? Theme.withAlpha(Theme.primary, 0.45)
                    : activeFocus ? Theme.warning
                    : Theme.borderStrong
    // Battlefield art and its state outline share the stable interaction
    // footprint, regardless of which printing or fallback image is available.
    color: "transparent"
    border.width: 0
    readonly property real strokeWidth: (combatHovered || selected || activeFocus ? 2
        : offered || offeredUndo || offeredPayment || combatDestination || attackTarget ? 1 : 0) * unit
    transform: Translate { id: blockedShift }
    activeFocusOnTab: tabStop
    Keys.onPressed: event => {
        // Standard context-menu keys mirror right-click inspection. They must
        // not activate the card or submit an engine response.
        if (event.key === Qt.Key_Menu
                || (event.key === Qt.Key_F10 && event.modifiers === Qt.ShiftModifier)) {
            tableController.openCardDetails(objectId, root)
            event.accepted = true
        }
    }
    Keys.onReturnPressed: function(event) {
        if (card && card.stackSize > 1 && card.stackFront && !card.fanned && card.openFan) {
            Theme.finishMotion()
            card.openFan()
            event.accepted = true
            return
        }
        activate()
        event.accepted = true
    }
    Keys.onLeftPressed: event => { event.accepted = !!(card && card.focusNeighbor && card.focusNeighbor(-1)) }
    Keys.onRightPressed: event => { event.accepted = !!(card && card.focusNeighbor && card.focusNeighbor(1)) }
    Keys.onEscapePressed: event => {
        Theme.finishMotion()
        if (tableController.interaction && tableController.interaction.dismissQueuedPayment(objectId)) {
            event.accepted = true
        } else if (card && card.fanned === true && card.closeFan) {
            card.closeFan()
            event.accepted = true
        } else {
            event.accepted = false
        }
    }
    Keys.onSpacePressed: activate()
    Accessible.role: Accessible.Button
    Accessible.name: publicFace ? displayName : qsTr("Hidden card")
    Accessible.description: [interactionLabel, persistentState.detailSummary].filter(v => v.length).join("\n")
    Accessible.onPressAction: activate()

    Rectangle {
        id: changeMark
        objectName: "forgeCardOpponentChange-" + root.objectId
        anchors.fill: faceBody
        radius: root.radius
        color: "transparent"
        border.width: 2 * root.unit
        border.color: "#f3f1e9"
        visible: root.opponentChanged && opacity > 0
        opacity: 0
        z: 25
        // Fades over the highlight window instead of switching off.
        NumberAnimation {
            id: changeFade
            target: changeMark
            property: "opacity"
            from: 0.9
            to: 0
            duration: 1500
            easing.type: Easing.InQuad
        }
    }
    onOpponentChangedChanged: {
        if (opponentChanged) {
            changeFade.restart()
        } else {
            changeFade.stop()
            changeMark.opacity = 0
        }
    }
    Rectangle {
        id: paymentQueueBadge
        visible: root.queuedPaymentLabel.length > 0
        z: 30
        anchors.left: faceBody.left
        anchors.top: faceBody.top
        anchors.margins: 4 * root.unit
        width: queueNumber.implicitWidth + 10 * root.unit
        height: 18 * root.unit
        radius: 9 * root.unit
        color: Theme.primary
        Text {
            id: queueNumber
            objectName: root.queuedPaymentLabel.length > 0 ? "forgeCardPaymentQueue-" + root.objectId : ""
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.queuedPaymentLabel
            color: Theme.primaryInk
            font.pixelSize: 11 * root.unit
            font.weight: Font.Bold
        }
    }

    Item {
        id: faceBody
        objectName: "forgeCardFace-" + root.objectId
        readonly property bool cropped: root.publicFace && !root.fullFace && root.artFrame !== "full"
        readonly property real imageAspect: art.implicitWidth > 0 && art.implicitHeight > 0
            ? art.implicitWidth / art.implicitHeight : 1 / 1.394
        width: !root.fullFace ? root.width : Math.min(root.width, root.height * imageAspect)
        height: !root.fullFace ? root.height : Math.min(root.height, root.width / imageAspect)
        anchors.centerIn: parent
        clip: true
        opacity: root.arrivalOpacity
        Rectangle {
            anchors.fill: parent
            // An unavailable image still needs a readable placeholder. Loaded
            // art has neither a backing tile nor a permanent neutral border.
            visible: art.status !== Image.Ready && !root.usingArtCrop
            color: Theme.surface
        }
        Item {
            id: artPlacement
            visible: !root.usingArtCrop
            // Crop the oriented full thumbnail in scene coordinates. The
            // image provider deliberately keeps a complete inspection image.
            readonly property bool cropArt: faceBody.cropped
            readonly property real imageAspect: faceBody.imageAspect
            readonly property real orientedAspect: root.artRotation === 90 ? 1 / imageAspect : imageAspect
            width: cropArt ? Math.max(parent.width / root.artRegion.width,
                                     parent.height * orientedAspect / root.artRegion.height) : parent.width
            height: cropArt ? width / orientedAspect : parent.height
            x: cropArt ? (parent.width - width * root.artRegion.width) / 2 - width * root.artRegion.x : 0
            y: cropArt ? (parent.height - height * root.artRegion.height) / 2 - height * root.artRegion.y : 0
            Image {
                id: art
                objectName: "forgeCardArt-" + root.objectId
                anchors.centerIn: parent
                width: artPlacement.cropArt && root.artRotation === 90 ? parent.height : parent.width
                height: artPlacement.cropArt && root.artRotation === 90 ? parent.width : parent.height
                rotation: artPlacement.cropArt ? root.artRotation : 0
                source: {
                    void artStamp.stamp
                    return root.publicFace
                            ? root.tableController.cardImage(root.card.name, root.card.setCode, root.card.collectorNumber)
                            : root.tableController.cardBackSource
                }
                sourceSize.width: 320
                sourceSize.height: 448
                fillMode: root.fullFace || artPlacement.cropArt ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                asynchronous: true
                property real artFade: 1
                opacity: artFade
                onSourceChanged: {
                    if (!(Theme.motionEnabled && !Theme.motionSnap) || source === "") {
                        artFade = 1
                        return
                    }
                    artFade = 0
                }
                onStatusChanged: {
                    if (status !== Image.Ready)
                        return
                    if (!(Theme.motionEnabled && !Theme.motionSnap)) {
                        artFade = 1
                        return
                    }
                    artFadeAnim.restart()
                }
                NumberAnimation {
                    id: artFadeAnim
                    target: art
                    property: "artFade"
                    to: 1
                    duration: Theme.motionFast
                    easing.type: Easing.OutCubic
                }
            }
        }
        Image {
            id: artCrop
            objectName: "forgeCardArtCrop-" + root.objectId
            anchors.fill: parent
            source: root.publicFace && !root.fullFace ? root.resolvedArtCropSource : ""
            sourceSize.width: 320
            sourceSize.height: 448
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            // Keep the complete local image painted until this optional asset
            // is decoded. Missing or corrupt crops leave that fallback intact.
            visible: root.usingArtCrop
        }
        Rectangle {
            anchors.fill: parent
            visible: !root.fullFace
            gradient: Gradient {
                GradientStop { position: 0; color: "#d5101a22" }
                GradientStop { position: 0.4; color: "#08101a22" }
                GradientStop { position: 1; color: "#ed101a22" }
            }
        }
        Rectangle {
            objectName: "forgeCardTappedShade-" + root.objectId
            anchors.fill: parent
            color: "#000000"
            opacity: root.tappedShade * root.tapShade
            visible: opacity > 0
        }
        Canvas {
            id: tapMark
            objectName: "forgeCardTappedMark-" + root.objectId
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.62
            height: width
            visible: root.tapShade > 0.01
            opacity: root.tapShade
            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                if (width <= 1 || height <= 1)
                    return
                ctx.fillStyle = "rgba(16,24,32,0.92)"
                ctx.beginPath()
                ctx.arc(width / 2, height / 2, width / 2 - 0.5, 0, Math.PI * 2)
                ctx.fill()
                ctx.strokeStyle = "#f3f1e9"
                ctx.fillStyle = "#f3f1e9"
                ctx.lineWidth = Math.max(2, width * 0.08)
                ctx.lineCap = "round"
                const radius = width * 0.28
                const end = Math.PI * 0.2
                ctx.beginPath()
                ctx.arc(width / 2, height / 2, radius, Math.PI * 0.95, end)
                ctx.stroke()
                const tx = -Math.sin(end)
                const ty = Math.cos(end)
                const px = -ty
                const py = tx
                const tip = width * 0.2
                const ax = width / 2 + Math.cos(end) * radius
                const ay = height / 2 + Math.sin(end) * radius
                ctx.beginPath()
                ctx.moveTo(ax + tx * tip, ay + ty * tip)
                ctx.lineTo(ax - tx * tip * 0.35 + px * tip * 0.62, ay - ty * tip * 0.35 + py * tip * 0.62)
                ctx.lineTo(ax - tx * tip * 0.35 - px * tip * 0.62, ay - ty * tip * 0.35 - py * tip * 0.62)
                ctx.closePath()
                ctx.fill()
            }
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onVisibleChanged: if (visible) requestPaint()
        }
        Text {
            id: cardNameLabel
            textFormat: Text.PlainText
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 7 * root.unit
            anchors.leftMargin: (root.nativeSelected ? 30 : 7) * root.unit
            objectName: "forgeCardName-" + root.objectId
            visible: !root.fullFace || art.status !== Image.Ready
            text: root.publicFace ? root.displayName : qsTr("Hidden card")
            color: "#f3f1e9"
            font.pixelSize: 12 * root.unit
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        Rectangle {
            id: powerBadge
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 4 * root.unit
            visible: !root.fullFace && (!!root.card.power || !!root.card.toughness)
            width: powerLabel.implicitWidth + 12 * root.unit
            height: 25 * root.unit
            radius: 5 * root.unit
            color: "#e2e5df"
            Text {
                id: powerLabel
                objectName: "forgeCardStats-" + root.objectId
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: (root.card.power || "") + " / " + (root.card.toughness || "")
                color: "#18212a"
                font.pixelSize: 14 * root.unit
                font.weight: Font.Bold
            }
        }
        Rectangle {
            id: stateBackdrop
            visible: cardStateLabel.visible && cardStateLabel.text.length > 0
            x: cardStateLabel.x - 3 * root.unit
            y: cardStateLabel.y + cardStateLabel.height
               - Math.min(cardStateLabel.implicitHeight, cardStateLabel.height) - 2 * root.unit
            width: cardStateLabel.width + 6 * root.unit
            height: Math.min(cardStateLabel.implicitHeight, cardStateLabel.height) + 4 * root.unit
            radius: 3 * root.unit
            color: "#e6101a22"
        }
        Text {
            id: cardStateLabel
            objectName: "forgeCardState-" + root.objectId
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 6 * root.unit
            anchors.bottomMargin: root.card.power || root.card.toughness || root.loyaltyAmount.length
                                  ? 34 * root.unit : 6 * root.unit
            visible: !root.fullFace || root.persistentSummary.length > 0
            text: [root.persistentSummary, [root.otherCounters,
                   root.card.damage > 0 ? qsTr("%1 dmg").arg(root.card.damage) : ""].filter(v => v.length).join(" · ")]
                   .filter(v => v.length).join("\n")
            // Wrapped/elided text can recalculate implicitHeight from height.
            // Bound it only by the available card space to avoid that cycle.
            height: Math.max(0, parent.height - anchors.bottomMargin
                - cardNameLabel.y - cardNameLabel.height - 5 * root.unit)
            verticalAlignment: Text.AlignBottom
            wrapMode: Text.Wrap
            maximumLineCount: 2
            clip: true
            color: "#e9c785"
            font.pixelSize: 10 * root.unit
            elide: Text.ElideRight
            scale: root.markPulse
            transformOrigin: Item.Bottom
        }
        Rectangle {
            id: loyaltyBadge
            objectName: "forgeCardLoyalty-" + root.objectId
            visible: root.loyaltyAmount.length > 0
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 4 * root.unit
            anchors.bottomMargin: root.card.power || root.card.toughness ? 32 * root.unit : 4 * root.unit
            width: Math.max(28 * root.unit, loyaltyNumber.implicitWidth + 14 * root.unit)
            height: 25 * root.unit
            radius: height / 2
            color: "#1c2430"
            border.width: 2
            border.color: "#e9c785"
            scale: root.markPulse
            transformOrigin: Item.Center
            Text {
                id: loyaltyNumber
                objectName: "forgeCardLoyaltyValue-" + root.objectId
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: root.loyaltyAmount
                color: "#f3f1e9"
                font.pixelSize: 14 * root.unit
                font.weight: Font.Bold
            }
        }
    }
    Rectangle {
        objectName: "forgeCardStateOutline-" + root.objectId
        anchors.fill: faceBody
        radius: root.radius
        antialiasing: true
        color: "transparent"
        border.width: root.strokeWidth
        border.color: root.waiting ? Theme.withAlpha(root.strokeColor, root.strokeColor.a * 0.5) : root.strokeColor
        visible: root.strokeWidth > 0
    }
    Rectangle {
        objectName: "forgeCardNativeSelection-" + root.objectId
        visible: root.nativeSelected
        anchors.top: faceBody.top
        anchors.left: faceBody.left
        anchors.margins: 4 * root.unit
        width: 24 * root.unit
        height: width
        radius: width / 2
        color: Theme.accent
        Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "✓"
            color: Theme.primaryInk
            font.pixelSize: 16 * root.unit
            font.weight: Font.Bold
        }
    }
    // A closed pile's front already labels the pile. A buried member's label
    // would repeat underneath it; the member stays clickable through its strip.
    readonly property bool behindPileFront: !!card && card.stackFront === false && card.fanned !== true
        && (card.stackSize || 1) > 1
    Rectangle {
        id: interactionHint
        visible: root.interactionLabel.length > 0 && !root.behindPileFront
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        // A host's label follows its named attachment strips, instead of
        // covering the first strip. The lane reserves this lasting depth.
        // Opponent rows draw it above the face so it cannot cover the phase strip.
        anchors.bottomMargin: root.hintSide < 0 ? parent.height + 2 * root.unit
                : root.attachmentStripHeight > 0
                    ? -root.attachmentStripHeight - height - 2 * root.unit : -14 * root.unit
        width: Math.min(root.width, hint.implicitWidth + 14 * root.unit)
        height: 19 * root.unit
        radius: 4 * root.unit
        color: root.undoingMana ? "#3d6d86" : root.showAbilityHint ? Theme.primary : "#e1bf82"
        Text {
            id: hint
            objectName: "forgeCardInteractionHint-" + root.objectId
            textFormat: Text.PlainText
            anchors.centerIn: parent
            width: parent.width - 8 * root.unit
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.interactionLabel
            color: "#19232b"
            font.pixelSize: 9 * root.unit
            font.weight: Font.Bold
        }
    }
    Rectangle {
        objectName: "forgeCardSubmitted-" + root.objectId
        anchors.fill: faceBody
        radius: root.radius
        color: "transparent"
        border.width: 1.5 * root.unit
        border.color: Theme.primary
        visible: root.submitted
        SequentialAnimation on opacity {
            running: root.submitted && Theme.motionEnabled
            loops: Animation.Infinite
            NumberAnimation { to: 0.35; duration: Theme.motionSlow; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 1; duration: Theme.motionSlow; easing.type: Easing.InOutQuad }
        }
    }
    SequentialAnimation {
        id: blockedShake
        NumberAnimation { target: blockedShift; property: "x"; to: -4 * root.unit; duration: 40 }
        NumberAnimation { target: blockedShift; property: "x"; to: 4 * root.unit; duration: 60 }
        NumberAnimation { target: blockedShift; property: "x"; to: 0; duration: 40 }
    }
    HoverHandler {
        id: hover
        enabled: root.pointerEnabled && root.hoverPreview
        cursorShape: root.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onHoveredChanged: if (root.combat && root.objectKind === "card") root.combat.hoverCard(root.objectId, hovered)
    }
    TapHandler {
        id: activationTap
        property var intent: null
        enabled: root.pointerEnabled
        acceptedButtons: Qt.LeftButton
        gesturePolicy: root.exclusiveTap ? TapHandler.WithinBounds : TapHandler.DragThreshold
        onPressedChanged: if (pressed) intent = root.activationIntent()
        onTapped: root.activate(intent)
    }
    TapHandler {
        enabled: root.pointerEnabled
        acceptedButtons: Qt.RightButton
        gesturePolicy: root.exclusiveTap ? TapHandler.WithinBounds : TapHandler.DragThreshold
        onTapped: root.tableController.openCardDetails(root.objectId, root)
    }
}
