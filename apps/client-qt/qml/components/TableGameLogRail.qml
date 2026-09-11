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
    readonly property var sourceEntries:
        tableController.tableGameLog ? tableController.tableGameLog : []
    property int synchronizationGeneration: 0

    objectName: "gameLogRail"
    Layout.minimumWidth: root.tableController.gameLogRailWidth
    Layout.preferredWidth: root.tableController.gameLogRailWidth
    Layout.maximumWidth: root.tableController.gameLogRailWidth
    Layout.fillHeight: true
    visible: root.tableController.showGameLogRail
    color: Theme.surfaceMuted
    radius: 0
    border.width: 0

    ListModel {
        id: gameLogModel
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
        color: Theme.borderStrong
        z: 20
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.size(6)
        spacing: Theme.size(5)

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.size(44)
            text: qsTranslate("Table", "Game log")
            color: Theme.text
            font.pixelSize: Theme.fontSize(13)
            font.weight: Font.DemiBold
            verticalAlignment: Text.AlignVCenter
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.border
        }
        ListView {
            id: gameLogList
            objectName: "gameLog"
            Layout.fillWidth: true
            Layout.fillHeight: true
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
                width: ListView.view.width
                text: I18n.gameLog(kind, logText)
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
}
