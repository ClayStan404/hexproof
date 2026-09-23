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
    property bool located: false
    property string objectKind: "card"
    readonly property string objectId: card.cardId || card.objectId || ""
    readonly property bool publicFace: card.visibleIdentity !== false && !card.faceDown && !!card.name
    readonly property string displayName: {
        if (!publicFace)
            return ""
        if (typeof tableController.cardDisplayName === "function")
            return tableController.cardDisplayName(card.name)
        return card.name
    }
    readonly property var combat: tableController.combatInteraction
    readonly property string persistentSummary: persistentState.boardSummary
    RulesCardPersistentState {
        id: persistentState
        card: root.card
        rulesSession: root.tableController.rulesSession
        cardCatalogModel: root.tableController.cardCatalogModel
    }
    readonly property bool nativeSelected: objectKind === "card"
        && tableController.interaction.nativeObjectSelected(objectKind, objectId)
    readonly property string combatObjectId: combat && combat.active && objectKind === "card"
        && card && typeof card.stackActivateId === "function"
        ? (card.stackActivateId() || objectId) : objectId
    readonly property bool actionable: combat && combat.active && objectKind === "card"
        ? combat.actionable(combatObjectId) : tableController.interaction.objectActionable(objectKind, objectId)
    readonly property bool combatDestination: combat && combat.active && objectKind === "card"
        && combat.targetActionable(objectId)
    readonly property bool combatHovered: combatDestination && combat.hoveredTarget
        && combat.hoveredTarget.objectId === objectId
    readonly property bool selected: located || (combat && combat.active && objectKind === "card"
        ? combat.selected(objectId) : tableController.interaction.objectSelected(objectKind, objectId))
    readonly property string combatLabel: combat && combat.active ? combat.labelFor(objectId) : ""
    readonly property bool previewActive: pointerEnabled && visible && (hover.hovered || activeFocus)
        && !(combat && combat.canAct && combat.chosenSource)
    readonly property bool abilityActionable: objectKind === "card" && !fullFace
        && (!combat || !combat.active)
        && tableController.interaction.actionsForCard(objectId).some(action => action.kind === "activateAbility")
    readonly property bool showAbilityHint: abilityActionable && previewActive
    readonly property string interactionLabel: showAbilityHint ? qsTr("Activate ability")
        : combatLabel || (card.attacking === true ? qsTr("Attacking") : "")
    signal activated()

    function activate() {
        if (combat && combat.active && objectKind === "card" && combat.activate(combatObjectId)) return
        tableController.interaction.activateObject(objectKind, objectId, publicFace ? card.name : "")
        activated()
    }
    onPreviewActiveChanged: {
        if (previewActive) tableController.previewCard(objectId, root)
        else tableController.endCardPreview(root)
    }
    Component.onDestruction: {
        if (previewActive) tableController.endCardPreview(root)
        if (combat && objectKind === "card" && hover.hovered) combat.hoverCard(objectId, false)
    }
    width: 180 * unit
    height: width * (fullFace ? 1.394 : 0.93)
    radius: 8 * unit
    antialiasing: true
    color: combatHovered ? Theme.primary : selected ? Theme.accent
                    : combatDestination ? (combat.attacking ? "#e1bd7f" : "#7ebcca")
                    : actionable ? Theme.primary
                    : activeFocus ? Theme.warning
                    : Theme.borderStrong
    border.width: 0
    readonly property int strokeWidth: combatHovered ? 4 : selected || activeFocus || combatDestination ? 3 : actionable ? 2 : 1
    activeFocusOnTab: pointerEnabled
    Keys.onReturnPressed: activate()
    Keys.onSpacePressed: activate()
    Accessible.role: Accessible.Button
    Accessible.name: publicFace ? displayName : qsTr("Hidden card")
    Accessible.description: abilityActionable ? qsTr("Activate ability") : combatLabel
    Accessible.onPressAction: activate()

    Rectangle {
        anchors.fill: parent
        anchors.margins: root.strokeWidth
        radius: Math.max(0, root.radius - root.strokeWidth)
        antialiasing: true
        color: Theme.withAlpha(Theme.surface, 0.92)
    }

    Item {
        anchors.fill: parent
        anchors.margins: 3 * root.unit
        clip: true
        Image {
            id: art
            // Clip in scene coordinates: the cached image provider supplies a
            // complete thumbnail and does not implement Image.sourceClipRect.
            readonly property bool cropArt: root.publicFace && !root.fullFace
            width: cropArt ? Math.max(parent.width / 0.84, parent.height / (1.394 * 0.43)) : parent.width
            height: cropArt ? width * 1.394 : parent.height
            x: (parent.width - width) / 2
            y: cropArt ? -height * 0.14 : 0
            source: root.publicFace ? root.tableController.cardImage(root.card.name, root.card.setCode, root.card.collectorNumber)
                                    : root.tableController.cardBackSource
            sourceSize.width: 320
            sourceSize.height: 448
            fillMode: root.fullFace ? Image.PreserveAspectFit : Image.PreserveAspectCrop
            asynchronous: true
            opacity: root.card.tapped ? 0.5 : 1
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
        Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            visible: root.card.tapped === true
            text: "↷"
            color: "white"
            font.pixelSize: 42 * root.unit
        }
        Rectangle {
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
            anchors.bottomMargin: root.card.power || root.card.toughness ? 34 * root.unit : 6 * root.unit
            visible: !root.fullFace || root.persistentSummary.length > 0
            text: [root.persistentSummary, [root.card.countersSummary || "",
                   root.card.damage > 0 ? qsTr("%1 dmg").arg(root.card.damage) : "",
                   root.card.attachedTo ? qsTr("Attached") : ""].filter(v => v.length).join(" · ")]
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
        }
    }
    Rectangle {
        objectName: "forgeCardNativeSelection-" + root.objectId
        visible: root.nativeSelected
        anchors.top: parent.top
        anchors.left: parent.left
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
    Rectangle {
        visible: root.interactionLabel.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -14 * root.unit
        width: hint.implicitWidth + 14 * root.unit
        height: 19 * root.unit
        radius: 4 * root.unit
        color: root.showAbilityHint ? Theme.primary : "#e1bf82"
        Text {
            id: hint
            objectName: "forgeCardInteractionHint-" + root.objectId
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: root.interactionLabel
            color: "#19232b"
            font.pixelSize: 9 * root.unit
            font.weight: Font.Bold
        }
    }
    HoverHandler {
        id: hover
        enabled: root.pointerEnabled
        cursorShape: root.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onHoveredChanged: if (root.combat && root.objectKind === "card") root.combat.hoverCard(root.objectId, hovered)
    }
    TapHandler { enabled: root.pointerEnabled; acceptedButtons: Qt.LeftButton; onTapped: root.activate() }
    TapHandler { enabled: root.pointerEnabled; acceptedButtons: Qt.RightButton; onTapped: root.tableController.openCardDetails(root.objectId) }
}
