// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import "../components"

Page {
    id: root
    required property var service
    readonly property var appWindow: ApplicationWindow.window
    property bool timelineOpen: true
    property var cachedPrintings: ({})
    function cacheVisibleCards() {
        const snapshot = root.service.frame.snapshot || ({})
        const requests = []
        const cards = []
        for (const zone of snapshot.zones || [])
            for (const card of zone.cards || []) cards.push(card)
        for (const card of snapshot.stack || []) cards.push(card)
        for (const card of cards) {
            const identity = card.identity
            if (!identity || !identity.name) continue
            const key = JSON.stringify(identity)
            if (cachedPrintings[key]) continue
            cachedPrintings[key] = true
            requests.push(identity)
        }
        if (requests.length) cardCatalog.cacheCardsIncrementally(requests)
    }
    Timer { id: artRefresh; interval: 120; onTriggered: root.cacheVisibleCards() }
    Connections { target: root.service; function onPositionChanged() { artRefresh.restart() } }
    Component.onCompleted: artRefresh.start()
    function elapsedLabel(ms) {
        const seconds = Math.floor(Number(ms || 0) / 1000)
        return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0")
    }
    function eventText(event) {
        let text = event.text || ""
        if (event.kind === "Decision") text = qsTr("Waiting for a decision")
        else if (text === event.kind || !text.length) {
            switch (event.kind) {
            case "CardChangeZone": text = qsTr("Card changes zone"); break
            case "CardTapped": text = qsTr("Card tap state changes"); break
            case "CardCounters": text = qsTr("Card counters change"); break
            case "CardStatsChanged": text = qsTr("Card characteristics change"); break
            case "ManaPool": text = qsTr("Mana pool changes"); break
            case "CardAttachment": text = qsTr("Attachment changes"); break
            case "TokenCreated": text = qsTr("Token created"); break
            case "CombatEnded": text = qsTr("Combat ends"); break
            case "GameFinished": text = qsTr("Game finished"); break
            default: text = qsTr("Game state changes")
            }
        }
        const actor = event.actorSeat >= 0 ? board.matchUi.playerName(event.actorSeat) : ""
        return actor.length && !text.startsWith(actor) ? actor + ": " + text : text
    }
    background: AppBackground { variant: "playmat" }
    Component.onDestruction: service.pause()
    QtObject {
        id: replayRoom
        property string roomId: "replay"
        property string roomName: root.service.metadata.roomName || ""
        property string format: root.service.metadata.format || "modern"
        property string role: "spectator"
        property string phase: "started"
        property int maxSeats: 2
        property bool host: false
        property bool spectatorsSeeHands: true
        property string hostingMode: "server"
        property var players: root.service.metadata.players || []
        property int seatIndex: -1
    }
    QtObject {
        id: replayMatch
        property int gameNumber: root.service.frame.gameNumber || 1
        property var score: []
        property var result: ({})
        property var sideboard: ({})
        property bool sideboarding: false
    }
    FileDialog {
        id: exportDialog
        title: qsTr("Export Forge replay")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "hpr"
        nameFilters: [qsTr("Hexproof replay (*.hpr)")]
        onAccepted: root.service.exportFile(selectedFile)
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Theme.size(10)
            AppButton { text: qsTr("Back"); onClicked: { root.service.pause(); root.appWindow.popScreen() } }
            Text {
                textFormat: Text.PlainText
                text: root.service.session.gameOver
                    ? qsTr("Replay · Game %1 · %2").arg(replayMatch.gameNumber)
                        .arg(root.service.session.winnerSeat >= 0
                             ? qsTr("%1 wins").arg(board.matchUi.playerName(root.service.session.winnerSeat))
                             : qsTr("Draw"))
                    : qsTr("Replay · Game %1 · Turn %2 · %3")
                    .arg(replayMatch.gameNumber).arg(root.service.session.turn)
                    .arg(board.stepLabel(root.service.session.step))
                color: Theme.text
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            AppButton { objectName: "forgeReplayFlip"; text: qsTr("Flip table"); onClicked: board.spectatedHandSeat = 1 - board.spectatedHandSeat }
            AppButton { objectName: "forgeReplayToggleTimeline"; text: qsTr("Timeline"); onClicked: root.timelineOpen = !root.timelineOpen }
            AppButton { text: qsTr("Export"); onClicked: exportDialog.open() }
        }
        Text {
            textFormat: Text.PlainText
            visible: root.service.metadata.complete === false || root.service.error.length > 0
            text: root.service.error || qsTr("This recording is incomplete. Some events may be missing.")
            color: Theme.textSecondary
            Layout.leftMargin: Theme.size(14)
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0
            RulesTable {
                id: board
                objectName: "forgeReplayBoard"
                Layout.fillWidth: true
                Layout.fillHeight: true
                replayMode: true
                replayFrame: root.service.frame
                wsModel: ws
                cardCatalogModel: cardCatalog
                gameTableModel: gameTable
                sideboardTableModel: sideboardTable
                preferencesModel: preferences
                roomSession: replayRoom
                gameSession: replayMatch
                rulesSession: root.service.session
            }
            Rectangle {
                visible: root.timelineOpen
                Layout.preferredWidth: Math.min(Theme.size(300), root.width * 0.26)
                Layout.fillHeight: true
                color: Theme.withAlpha(Theme.surface, 0.94)
                ListView {
                    id: events
                    anchors.fill: parent
                    anchors.margins: Theme.size(8)
                    clip: true
                    model: root.service.events
                    currentIndex: root.service.position
                    highlightMoveDuration: 0
                    ScrollBar.vertical: ScrollBar { }
                    delegate: ItemDelegate {
                        required property var modelData
                        required property int index
                        width: events.width
                        height: label.implicitHeight + Theme.size(18)
                        highlighted: index === root.service.position
                        background: Rectangle {
                            color: index === root.service.position ? Theme.withAlpha(Theme.accent, 0.12) : "transparent"
                            radius: Theme.size(6)
                        }
                        onClicked: { root.service.pause(); root.service.seek(index) }
                        contentItem: Text {
                            id: label
                            textFormat: Text.PlainText
                            wrapMode: Text.WordWrap
                            text: root.elapsedLabel(modelData.elapsedMs) + " · "
                                + qsTr("Game %1 · Turn %2 · %3").arg(modelData.gameNumber).arg(modelData.turn)
                                .arg(board.matchUi.playerName(modelData.activeSeat)) + "\n" + root.eventText(modelData)
                            color: index === root.service.position ? Theme.accent : Theme.textSecondary
                            font.pixelSize: Theme.fontSize(11)
                        }
                    }
                }
            }
        }
        Slider {
            objectName: "forgeReplayTimeline"
            Layout.fillWidth: true
            Layout.leftMargin: Theme.size(14)
            Layout.rightMargin: Theme.size(14)
            from: 0
            to: Math.max(1, root.service.count - 1)
            stepSize: 1
            value: root.service.position
            onMoved: { root.service.pause(); root.service.seek(Math.round(value)) }
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: Theme.size(10)
            AppButton { text: qsTr("Previous turn"); onClicked: root.service.nextTurn(-1) }
            AppButton { objectName: "forgeReplayPrevious"; text: qsTr("Previous"); onClicked: root.service.step(-1) }
            AppButton { objectName: "forgeReplayPlay"; text: root.service.playing ? qsTr("Pause") : qsTr("Play"); onClicked: root.service.togglePlaying() }
            AppButton { objectName: "forgeReplayNext"; text: qsTr("Next"); onClicked: root.service.step(1) }
            AppButton { objectName: "forgeReplayNextTurn"; text: qsTr("Next turn"); onClicked: root.service.nextTurn(1) }
            AppComboBox {
                model: ["0.5×", "1×", "2×", "4×", "8×"]
                currentIndex: 1
                onActivated: root.service.speed = [0.5, 1, 2, 4, 8][currentIndex]
            }
            Text {
                textFormat: Text.PlainText
                text: (root.service.position + 1) + " / " + root.service.count
                color: Theme.textMuted
            }
        }
    }
}
