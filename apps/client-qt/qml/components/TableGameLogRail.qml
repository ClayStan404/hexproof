// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "Table"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Surface {
    id: root

    required property var tableController
    property alias chatInput: chatInputField
    property bool floating: false
    property real floatingDefaultY: Theme.size(52)
    property real floatingDefaultWidth: Theme.size(240)
    property real floatingDefaultHeight: Theme.size(400)
    property Item floatingAvoidItem: null
    property real storedNX: -1
    property real storedNY: -1
    property real storedNW: -1
    property real storedNH: -1
    property real dragOriginX: 0
    property real dragOriginY: 0
    property real draggedX: 0
    property real draggedY: 0
    property bool dragStarted: false
    property real resizeOriginW: 0
    property real resizeOriginH: 0
    property real resizedW: 0
    property real resizedH: 0
    property bool resizeStarted: false
    readonly property var sourceEntries:
        tableController.tableGameLog ? tableController.tableGameLog : []
    readonly property var catalogModel: tableController.cardCatalogModel || null
    readonly property var publicSeats: tableController.gameTableModel
                                       ? tableController.gameTableModel.seats : []
    readonly property real floatingEdge: Theme.size(12)
    readonly property real maximumX: parent
        ? Math.max(0, parent.width - width - floatingEdge) : 0
    readonly property real maximumY: parent
        ? Math.max(0, parent.height - height - floatingEdge) : 0
    readonly property bool hasCustomPosition: storedNX >= 0 && storedNY >= 0
    readonly property real defaultX: {
        if (!parent)
            return floatingEdge
        let rightEdge = parent.width - Theme.size(16)
        if (floatingAvoidItem && floatingAvoidItem.visible)
            rightEdge = Math.min(rightEdge, floatingAvoidItem.x - Theme.size(8))
        return Math.max(floatingEdge, rightEdge - width)
    }
    readonly property real defaultY: Math.max(
        floatingEdge, Math.min(floatingDefaultY, maximumY))
    readonly property real restingX: Math.max(
        floatingEdge,
        Math.min(hasCustomPosition ? storedNX * maximumX : defaultX, maximumX))
    readonly property real restingY: Math.max(
        floatingEdge,
        Math.min(hasCustomPosition ? storedNY * maximumY : defaultY, maximumY))
    readonly property real minimumFloatingWidth: Theme.size(220)
    readonly property real minimumFloatingHeight: Theme.size(240)
    readonly property bool hasCustomWidth: storedNW > 0
    readonly property bool hasCustomHeight: storedNH > 0
    readonly property real defaultWidth: {
        if (!parent)
            return floatingDefaultWidth
        const maxW = Math.max(minimumFloatingWidth,
                              parent.width - floatingEdge * 2)
        return Math.max(minimumFloatingWidth,
                        Math.min(floatingDefaultWidth, maxW))
    }
    readonly property real defaultHeight: {
        if (!parent)
            return floatingDefaultHeight
        const maxH = Math.max(minimumFloatingHeight,
                              parent.height - floatingEdge * 2)
        return Math.max(minimumFloatingHeight,
                        Math.min(floatingDefaultHeight, maxH))
    }
    readonly property real restingWidth: {
        if (!parent)
            return defaultWidth
        const raw = hasCustomWidth ? storedNW * parent.width : defaultWidth
        const maxW = Math.max(minimumFloatingWidth,
                              parent.width - floatingEdge * 2)
        return Math.max(minimumFloatingWidth, Math.min(raw, maxW))
    }
    readonly property real restingHeight: {
        if (!parent)
            return defaultHeight
        const raw = hasCustomHeight ? storedNH * parent.height : defaultHeight
        const maxH = Math.max(minimumFloatingHeight,
                              parent.height - floatingEdge * 2)
        return Math.max(minimumFloatingHeight, Math.min(raw, maxH))
    }
    property int catalogRevision: 0
    property int synchronizationGeneration: 0

    objectName: "gameLogRail"
    Layout.minimumWidth: root.floating ? implicitWidth : root.tableController.gameLogRailWidth
    Layout.preferredWidth: root.floating ? implicitWidth : root.tableController.gameLogRailWidth
    Layout.maximumWidth: root.floating ? implicitWidth : root.tableController.gameLogRailWidth
    Layout.fillHeight: !root.floating
    visible: root.tableController.showGameLogRail
             && (!root.floating || root.tableController.sideboarding !== true)
    color: root.floating
           ? (Theme.useGlass ? "transparent"
                             : Theme.withAlpha(Theme.surface, 0.92))
           : Theme.tableRailFill
    radius: root.floating ? Theme.radiusLarge : 0
    border.width: root.floating ? 1 : 0
    elevated: root.floating
    clip: root.floating
    z: root.floating ? 150 : 0

    function resetFloatingPosition() {
        storedNX = -1
        storedNY = -1
        storedNW = -1
        storedNH = -1
    }

    function clampFloatingWidth(value) {
        if (!parent)
            return value
        const maxW = Math.max(minimumFloatingWidth,
                              parent.width - root.x - floatingEdge)
        return Math.max(minimumFloatingWidth, Math.min(value, maxW))
    }

    function clampFloatingHeight(value) {
        if (!parent)
            return value
        const maxH = Math.max(minimumFloatingHeight,
                              parent.height - root.y - floatingEdge)
        return Math.max(minimumFloatingHeight, Math.min(value, maxH))
    }

    function hideFloatingPanel() {
        if (typeof tableController.setGameLogVisible === "function")
            tableController.setGameLogVisible(false)
        else
            tableController.showGameLogRail = false
    }

    Binding {
        when: root.floating
        target: root
        property: "x"
        value: logDrag.active ? root.draggedX : root.restingX
    }

    Binding {
        when: root.floating
        target: root
        property: "y"
        value: logDrag.active ? root.draggedY : root.restingY
    }

    Binding {
        when: root.floating
        target: root
        property: "width"
        value: sizeDrag.active ? root.resizedW : root.restingWidth
    }

    Binding {
        when: root.floating
        target: root
        property: "height"
        value: sizeDrag.active ? root.resizedH : root.restingHeight
    }

    ListModel {
        id: gameLogModel
    }

    Connections {
        target: root.catalogModel
        ignoreUnknownSignals: true
        function onCatalogChanged() { ++root.catalogRevision }
    }

    function localizedCardName(name) {
        const catalog = catalogModel
        if (!catalog || typeof catalog.cardDisplayName !== "function")
            return name
        void catalogRevision
        void catalog.language
        void catalog.imageRevision
        return catalog.cardDisplayName(name)
    }

    function actorName(seat) {
        for (const player of publicSeats) {
            if (Number(player.seat) === seat)
                return player.displayName || ""
        }
        return ""
    }

    function normalizedEntry(entry) {
        return {
            "entryId": String(entry && entry.id !== undefined
                              ? entry.id : ""),
            "kind": String(entry && entry.kind ? entry.kind : ""),
            "logText": String(entry && entry.text ? entry.text : ""),
            "seat": Number(entry && entry.seat !== undefined
                           ? entry.seat : -1)
        }
    }

    function entryMatches(index, entry) {
        const current = gameLogModel.get(index)
        const target = normalizedEntry(entry)
        return current.entryId === target.entryId
                && current.kind === target.kind
                && current.logText === target.logText
                && current.seat === target.seat
    }

    function nearLogEnd() {
        const maximumY = gameLogList.originY
                       + Math.max(0, gameLogList.contentHeight
                                  - gameLogList.height)
        return gameLogList.contentY >= maximumY - Theme.size(24)
    }

    function currentScrollState() {
        const state = {
            "initiallyEmpty": gameLogModel.count === 0,
            "pinned": nearLogEnd(),
            "index": -1,
            "offset": 0,
            "contentY": gameLogList.contentY
        }
        if (gameLogModel.count === 0)
            return state
        state.index = gameLogList.indexAt(
                    1, gameLogList.contentY + 1)
        if (state.index < 0)
            state.index = Math.max(0, gameLogList.currentIndex)
        const item = gameLogList.itemAtIndex(state.index)
        if (item)
            state.offset = item.y - gameLogList.contentY
        return state
    }

    function restoreAfterSync(state, rebuilt, generation) {
        Qt.callLater(function() {
            if (!gameLogList || generation !== synchronizationGeneration)
                return
            gameLogList.forceLayout()
            if (state.initiallyEmpty || state.pinned) {
                gameLogList.positionViewAtEnd()
                return
            }
            if (!rebuilt || gameLogModel.count === 0)
                return
            const index = Math.max(
                            0,
                            Math.min(state.index, gameLogModel.count - 1))
            gameLogList.positionViewAtIndex(index, ListView.Beginning)
            gameLogList.forceLayout()
            const item = gameLogList.itemAtIndex(index)
            const desiredY = item ? item.y - state.offset : state.contentY
            const maximumY = gameLogList.originY
                           + Math.max(0, gameLogList.contentHeight
                                      - gameLogList.height)
            gameLogList.contentY = Math.max(
                        gameLogList.originY,
                        Math.min(maximumY, desiredY))
        })
    }

    function synchronizeLog() {
        const target = sourceEntries ? sourceEntries : []
        const sharedCount = Math.min(gameLogModel.count, target.length)
        let prefixMatches = true
        for (let index = 0; index < sharedCount; ++index) {
            if (!entryMatches(index, target[index])) {
                prefixMatches = false
                break
            }
        }
        const appendOnly = prefixMatches
                         && target.length >= gameLogModel.count
        if (appendOnly && target.length === gameLogModel.count)
            return

        const scrollState = currentScrollState()
        if (!appendOnly) {
            gameLogList.model = null
            gameLogModel.clear()
            for (let index = 0; index < target.length; ++index)
                gameLogModel.append(normalizedEntry(target[index]))
            gameLogList.model = gameLogModel
        } else {
            for (let index = gameLogModel.count;
                 index < target.length; ++index) {
                gameLogModel.append(normalizedEntry(target[index]))
            }
        }
        const generation = ++synchronizationGeneration
        restoreAfterSync(scrollState, !appendOnly, generation)
    }

    onSourceEntriesChanged: synchronizeLog()
    Component.onCompleted: synchronizeLog()

    Rectangle {
        objectName: "gameLogColumnDivider"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: Theme.size(2)
        color: Theme.tableDivider
        visible: !root.floating
        z: 20
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.size(6)
        spacing: Theme.size(5)

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Theme.size(44)
            Layout.maximumHeight: Theme.size(44)
            Layout.alignment: Qt.AlignTop
            spacing: Theme.size(4)

            Item {
                id: logDragHandle
                objectName: "gameLogDragHandle"
                Layout.fillWidth: true
                Layout.fillHeight: true

                Text {
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: implicitHeight
                    text: qsTranslate("Table", "Game log")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(13)
                    font.weight: Font.DemiBold
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.NoWrap
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    hoverEnabled: root.floating
                    cursorShape: root.floating
                                 ? (logDrag.active ? Qt.ClosedHandCursor
                                                   : Qt.OpenHandCursor)
                                 : Qt.ArrowCursor
                }

                TapHandler {
                    enabled: root.floating
                    acceptedButtons: Qt.RightButton
                    onTapped: root.resetFloatingPosition()
                }

                HoverHandler {
                    id: logDragHover
                    enabled: root.floating
                }

                ToolTip.delay: 800
                ToolTip.visible: root.floating && logDragHover.hovered
                ToolTip.text: qsTranslate(
                                  "BattlefieldViewControls",
                                  "Drag to move; right-click to reset position")

                DragHandler {
                    id: logDrag
                    enabled: root.floating
                    target: null
                    dragThreshold: 0
                    acceptedButtons: Qt.LeftButton
                    onActiveChanged: {
                        if (active) {
                            root.dragStarted = true
                            root.dragOriginX = root.x
                            root.dragOriginY = root.y
                            root.draggedX = root.x
                            root.draggedY = root.y
                            return
                        }
                        if (!root.dragStarted)
                            return
                        root.dragStarted = false
                        root.storedNX = root.maximumX > 0
                                ? root.draggedX / root.maximumX : 0
                        root.storedNY = root.maximumY > 0
                                ? root.draggedY / root.maximumY : 0
                    }
                    onTranslationChanged: {
                        if (!active)
                            return
                        root.draggedX = Math.max(
                                    root.floatingEdge, Math.min(
                                        root.maximumX,
                                        root.dragOriginX + translation.x))
                        root.draggedY = Math.max(
                                    root.floatingEdge, Math.min(
                                        root.maximumY,
                                        root.dragOriginY + translation.y))
                    }
                }
            }

            AppButton {
                objectName: "closeGameLogButton"
                visible: root.floating
                compact: true
                variant: "ghost"
                text: "×"
                accessibleName: qsTr("Close")
                Layout.preferredWidth: Theme.size(32)
                implicitHeight: Theme.size(32)
                onClicked: root.hideFloatingPanel()
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: 1
            color: Theme.border
        }
        ListView {
            id: gameLogList
            objectName: "gameLog"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: Theme.size(64)
            Layout.alignment: Qt.AlignTop
            model: gameLogModel
            spacing: Theme.size(7)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {
                objectName: "gameLogScrollBar"
                policy: ScrollBar.AsNeeded
                interactive: true
            }
            delegate: Text {
                textFormat: Text.PlainText
                required property string logText
                required property string kind
                required property int seat
                width: ListView.view.width
                text: I18n.gameLog(kind, logText, root.localizedCardName,
                                   root.actorName(seat))
                color: kind === "chat"
                       ? Theme.primary : Theme.textMuted
                font.pixelSize: Theme.fontSize(10)
                font.weight: kind === "chat"
                             ? Font.Medium : Font.Normal
                wrapMode: Text.WordWrap
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Theme.size(36)
            Layout.maximumHeight: Theme.size(36)
            Layout.alignment: Qt.AlignBottom
            spacing: Theme.size(5)

            AppTextField {
                id: chatInputField
                objectName: "gameChatInput"
                Layout.fillWidth: true
                implicitHeight: Theme.size(36)
                leftPadding: Theme.size(5)
                rightPadding: Theme.size(5)
                enabled: root.tableController.canChat
                maximumLength: 500
                placeholderText: qsTranslate("Table", "Message…")
                selectByMouse: true
                font.pixelSize: Theme.fontSize(10)
                onAccepted: root.tableController.cardActions.submitChatMessage()
            }
            AppButton {
                objectName: "sendGameChatButton"
                compact: true
                implicitWidth: Theme.size(54)
                implicitHeight: Theme.size(36)
                leftPadding: Theme.size(5)
                rightPadding: Theme.size(5)
                text: qsTranslate("Table", "Send")
                enabled: root.tableController.canChat
                         && chatInputField.text.trim().length > 0
                onClicked: root.tableController.cardActions.submitChatMessage()
            }
        }
    }

    Item {
        id: sizeHandle
        objectName: "gameLogResizeHandle"
        visible: root.floating
        z: 30
        width: Theme.size(22)
        height: Theme.size(22)
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.size(2)

        Repeater {
            model: 3
            Rectangle {
                required property int index
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: Theme.size(10)
                height: 2
                rotation: -45
                transformOrigin: Item.BottomRight
                anchors.rightMargin: Theme.size(3 + index * 4)
                anchors.bottomMargin: Theme.size(3)
                color: Theme.textMuted
                opacity: 0.7
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            cursorShape: Qt.SizeFDiagCursor
        }

        HoverHandler {
            id: sizeHover
        }

        ToolTip.delay: 800
        ToolTip.visible: sizeHover.hovered
        ToolTip.text: qsTranslate("Table", "Drag to resize")

        DragHandler {
            id: sizeDrag
            target: null
            dragThreshold: 0
            acceptedButtons: Qt.LeftButton
            onActiveChanged: {
                if (active) {
                    root.resizeStarted = true
                    root.resizeOriginW = root.width
                    root.resizeOriginH = root.height
                    root.resizedW = root.width
                    root.resizedH = root.height
                    return
                }
                if (!root.resizeStarted)
                    return
                root.resizeStarted = false
                if (!root.parent)
                    return
                root.storedNW = root.parent.width > 0
                        ? root.resizedW / root.parent.width : -1
                root.storedNH = root.parent.height > 0
                        ? root.resizedH / root.parent.height : -1
            }
            onTranslationChanged: {
                if (!active)
                    return
                root.resizedW = root.clampFloatingWidth(
                            root.resizeOriginW + translation.x)
                root.resizedH = root.clampFloatingHeight(
                            root.resizeOriginH + translation.y)
            }
        }
    }
}
