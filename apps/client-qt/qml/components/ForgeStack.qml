// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic

Rectangle {
    id: root
    required property var tableController
    property real unit: 1
    property bool collapsed: false
    property real defaultX: 0
    property real defaultY: 0
    property rect movementBounds: Qt.rect(0, 0, parent ? parent.width : 0, parent ? parent.height : 0)
    property point storedPosition: Qt.point(-1, -1)
    readonly property real headerHeight: 40 * unit
    readonly property real maximumX: Math.max(movementBounds.x, movementBounds.x + movementBounds.width - width)
    readonly property real maximumY: Math.max(movementBounds.y, movementBounds.y + movementBounds.height - height)
    x: Math.max(movementBounds.x, Math.min(maximumX, storedPosition.x < 0 ? defaultX
        : movementBounds.x + storedPosition.x * movementBounds.width))
    y: Math.max(movementBounds.y, Math.min(maximumY, storedPosition.y < 0 ? defaultY
        : movementBounds.y + storedPosition.y * movementBounds.height))
    implicitHeight: headerHeight + column.height + 7 * unit
    readonly property int count: entries.count
    readonly property Item scrollArea: viewport
    property Item focusedItem: null
    property string activeObjectId: ""
    property int activeTargetIndex: 0
    property int revision: 0
    property string locatedId: ""
    readonly property bool relationsEnabled: visible && !collapsed
        && tableController.roomConnected && !tableController.sideboarding
    readonly property var activeEntry: {
        void revision
        return relationsEnabled ? entryFor(activeObjectId) || entries.itemAt(0) : null
    }
    readonly property var currentTarget: activeEntry && activeEntry.targets.length > 0
        ? activeEntry.targets[Math.min(activeTargetIndex, activeEntry.targets.length - 1)] : null
    signal targetRequested(var target)

    function resetPosition() { storedPosition = Qt.point(-1, -1) }
    function moveTo(nextX, nextY) {
        const boundedX = Math.max(movementBounds.x, Math.min(maximumX, nextX))
        const boundedY = Math.max(movementBounds.y, Math.min(maximumY, nextY))
        // Normalize against the viewport so a dragged header stays in place
        // when collapse changes the panel's dimensions.
        storedPosition = Qt.point(
            movementBounds.width > 0 ? (boundedX - movementBounds.x) / movementBounds.width : 0,
            movementBounds.height > 0 ? (boundedY - movementBounds.y) / movementBounds.height : 0)
    }
    function entryFor(id) {
        for (let i = 0; i < entries.count; ++i) {
            const entry = entries.itemAt(i) as StackEntry
            if (entry && entry.objectId === id) return entry
        }
        return null
    }
    function clearSelection() { activeObjectId = ""; activeTargetIndex = 0 }
    function revealFocusedItem() {
        const item = focusedItem
        if (!item || !item.activeFocus || collapsed || viewport.height <= 0) return
        const y = item.mapToItem(column, 0, 0).y
        if (y < viewport.contentY) viewport.contentY = y
        else if (y + item.height > viewport.contentY + viewport.height)
            viewport.contentY = y + item.height - viewport.height
    }
    function reveal(id) {
        const entry = entryFor(id)
        if (!entry) return false
        viewport.contentY = Math.max(0, Math.min(entry.y, viewport.contentHeight - viewport.height))
        return true
    }
    function pointFor(id, target) {
        void revision
        void root.x; void root.y; void root.width; void root.height
        const entry = entryFor(id)
        if (!visible || collapsed || !entry || viewport.height <= 0) return Qt.point(0, 0)
        const y = entry.y + 24 * unit
        if (y < viewport.contentY || y > viewport.contentY + viewport.height) return Qt.point(0, 0)
        return entry.mapToItem(target, 0, 24 * unit)
    }
    Timer {
        id: refresh
        interval: 0
        onTriggered: {
            root.revision++
            if (!root.count) root.collapsed = false
        }
    }
    Connections {
        target: root.tableController.rulesSession
        function onSnapshotChanged() { refresh.restart() }
    }
    onRelationsEnabledChanged: if (!relationsEnabled) clearSelection()
    color: Theme.withAlpha(Theme.surface, 0.96)
    radius: 10 * unit
    antialiasing: true
    border.width: 1
    border.color: Theme.borderStrong
    visible: count > 0
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onWheel: wheel => { wheel.accepted = true }
        TapHandler { acceptedButtons: Qt.AllButtons; gesturePolicy: TapHandler.WithinBounds }
    }
    Item {
        id: dragHandle
        objectName: "forgeStackDragHandle"
        x: 10 * root.unit
        width: root.width - x - stackToggle.width - 10 * root.unit
        height: root.headerHeight
        Text {
            anchors.fill: parent
            textFormat: Text.PlainText
            text: qsTr("Stack · %1").arg(root.count)
            color: Theme.accent
            font.pixelSize: 12 * root.unit
            font.weight: Font.DemiBold
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        HoverHandler {
            id: dragHover
            cursorShape: stackDrag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        }
        ToolTip.visible: dragHover.hovered
        ToolTip.delay: 800
        ToolTip.text: qsTranslate("BattlefieldViewControls", "Drag to move; right-click to reset position")
        TapHandler {
            acceptedButtons: Qt.RightButton
            gesturePolicy: TapHandler.WithinBounds
            onTapped: root.resetPosition()
        }
        DragHandler {
            id: stackDrag
            target: null
            acceptedButtons: Qt.LeftButton
            dragThreshold: 0
            property point origin: Qt.point(0, 0)
            onActiveChanged: if (active) origin = Qt.point(root.x, root.y)
            onTranslationChanged: if (active) root.moveTo(origin.x + translation.x, origin.y + translation.y)
        }
    }
    AppButton {
        id: stackToggle
        objectName: "forgeStackToggle"
        x: root.width - width - 5 * root.unit
        y: 4 * root.unit
        width: 32 * root.unit; height: 32 * root.unit
        compact: true
        variant: "ghost"
        text: root.collapsed ? "+" : "−"
        accessibleName: qsTr("Stack · %1").arg(root.count)
        checkable: true
        checked: !root.collapsed
        onClicked: root.collapsed = !root.collapsed
    }
    component StackEntry: Rectangle {
        id: entry
        required property int index
        required property string objectId
        required property int controllerSeat
        required property string sourceId
        required property string name
        required property string setCode
        required property string collectorNumber
        required property string rulesText
        required property var targets
        readonly property bool visibleIdentity: name.length > 0
        readonly property bool faceDown: !visibleIdentity
        readonly property var artCard: {
            const source = root.tableController.rulesSession.cardForInspection(sourceId)
            if (source && source.visibleIdentity === true && source.name
                    && !String(source.name).includes("'s Effect"))
                return source
            const cleaned = String(name || "").replace(/ \(\d+\)'s Effect$/, "").replace(/'s Effect$/, "")
            return {name: cleaned, setCode: setCode, collectorNumber: collectorNumber,
                visibleIdentity: cleaned.length > 0, faceDown: cleaned.length === 0,
                cardId: objectId, tapped: false}
        }
        objectName: "forgeStackEntry-" + objectId
        width: column.width
        height: Math.max(138 * root.unit, details.height + 18 * root.unit)
        radius: 7 * root.unit
        antialiasing: true
        readonly property int strokeWidth: objectId === root.locatedId ? 3 : 1
        color: objectId === root.locatedId ? Theme.accent : index === 0 ? Theme.warning : Theme.borderStrong
        border.width: 0

        Rectangle {
            anchors.fill: parent
            anchors.margins: entry.strokeWidth
            radius: Math.max(0, parent.radius - entry.strokeWidth)
            antialiasing: true
            color: Theme.withAlpha(Theme.surfaceElevated, 0.94)
        }

        ForgeCard {
            id: stackCard
            objectName: "forgeStackCard-" + entry.objectId
            x: 7 * root.unit
            y: 7 * root.unit
            width: 86 * root.unit
            height: 120 * root.unit
            tableController: root.tableController
            card: entry.artCard
            objectKind: "spell"
            exclusiveTap: true
            unit: root.unit
            fullFace: true
            located: entry.objectId === root.locatedId
            onActiveFocusChanged: if (activeFocus) {
                root.focusedItem = stackCard
                root.revealFocusedItem()
            }
        }
        Column {
            id: details
            x: 104 * root.unit
            y: 9 * root.unit
            width: parent.width - x - 8 * root.unit
            spacing: 5 * root.unit
            Text {
                objectName: "forgeStackName-" + entry.objectId
                textFormat: Text.PlainText
                width: parent.width
                text: {
                    if (!entry.visibleIdentity)
                        return entry.rulesText && entry.rulesText !== "Face-down spell"
                                ? entry.rulesText : qsTr("Face-down spell")
                    const effect = /^(.*) \(\d+\)'s Effect$/.exec(entry.name)
                            || /^(.*)'s Effect$/.exec(entry.name)
                    const catalog = root.tableController.cardCatalogModel
                    if (effect && catalog && catalog.language === "zh"
                            && typeof root.tableController.cardDisplayName === "function")
                        return qsTr("%1's effect").arg(root.tableController.cardDisplayName(effect[1]))
                    return typeof root.tableController.cardDisplayName === "function"
                            ? root.tableController.cardDisplayName(entry.name) : entry.name
                }
                color: Theme.text
                font.pixelSize: 13 * root.unit
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Text {
                textFormat: Text.PlainText
                width: parent.width
                text: root.tableController.matchUi.playerName(entry.controllerSeat)
                color: Theme.textSecondary
                font.pixelSize: 10 * root.unit
                elide: Text.ElideRight
            }
            Text {
                objectName: "forgeStackRules-" + entry.objectId
                textFormat: Text.PlainText
                width: parent.width
                visible: text.length > 0
                text: {
                    const catalog = root.tableController.cardCatalogModel
                    if (catalog) {
                        void catalog.imageRevision
                        void catalog.language
                    }
                    const effect = /^(.*) \(\d+\)'s Effect$/.exec(entry.name)
                            || /^(.*)'s Effect$/.exec(entry.name)
                    const cardName = effect ? effect[1]
                            : (entry.artCard && entry.artCard.name) || entry.name
                    return typeof root.tableController.stackAbilityText === "function"
                            ? root.tableController.stackAbilityText(cardName, entry.rulesText)
                            : entry.rulesText
                }
                color: Theme.textMuted
                font.pixelSize: 10 * root.unit
                wrapMode: Text.WordWrap
                maximumLineCount: 4
                elide: Text.ElideRight
            }
            Repeater {
                model: entry.targets
                delegate: Button {
                    id: targetButton
                    required property var modelData
                    required property int index
                    readonly property bool relationSelected: !!root.activeEntry && root.activeEntry === entry
                        && Math.min(root.activeTargetIndex, entry.targets.length - 1) === index
                    objectName: "forgeStackTarget-" + entry.objectId + "-" + index
                    width: details.width
                    height: 27 * root.unit
                    padding: 4 * root.unit
                    text: qsTr("Target: %1").arg(modelData.label || (modelData.kind === "player"
                        ? qsTr("Seat %1").arg(modelData.seat + 1)
                        : modelData.kind === "spell" ? qsTr("Face-down spell") : qsTr("Hidden card")))
                    enabled: root.relationsEnabled
                    onActiveFocusChanged: if (activeFocus) {
                        root.focusedItem = targetButton
                        root.revealFocusedItem()
                    }
                    onClicked: {
                        root.activeObjectId = entry.objectId
                        root.activeTargetIndex = index
                        root.targetRequested(modelData)
                    }
                    ToolTip.visible: hovered
                    ToolTip.text: text
                    contentItem: Text {
                        textFormat: Text.PlainText
                        text: targetButton.text
                        color: Theme.text
                        font.pixelSize: 10 * root.unit
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    background: Rectangle {
                        radius: 4 * root.unit
                        color: targetButton.hovered ? "#3a535b" : "#29404a"
                        border.color: targetButton.relationSelected || targetButton.activeFocus ? "#e5bd73" : "#506d75"
                    }
                }
            }
        }
    }
    Flickable {
        id: viewport
        objectName: "forgeStackViewport"
        anchors.fill: parent
        anchors.margins: 7 * root.unit
        anchors.topMargin: root.headerHeight
        visible: !root.collapsed
        contentWidth: width
        contentHeight: column.height
        onHeightChanged: Qt.callLater(root.revealFocusedItem)
        onContentHeightChanged: Qt.callLater(root.revealFocusedItem)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: column
            x: 3 * root.unit
            width: viewport.width - 9 * root.unit
            spacing: 7 * root.unit
            Repeater {
                id: entries
                model: root.tableController.rulesSession.stack
                onCountChanged: viewport.contentY = 0
                onItemAdded: refresh.restart()
                onItemRemoved: refresh.restart()
                delegate: StackEntry {}
            }
        }
    }
}
