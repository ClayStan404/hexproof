// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "TournamentLobby"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var limitedModel
    Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: qsTranslate("TournamentLobby", "Player progress")
        color: Theme.text
        font.pixelSize: Theme.fontSize(18)
    }
    Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: qsTranslate("TournamentLobby", "Packs, picks, and decks remain private to each participant.")
        color: Theme.textMuted
        wrapMode: Text.WordWrap
    }
    ListView {
        objectName: "limitedEventProgressList"
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: root.limitedModel.participants
        spacing: Theme.size(8)
        ScrollBar.vertical: ScrollBar { }
        delegate: Surface {
            id: progressRow
            required property var modelData
            width: ListView.view.width
            height: Theme.size(64)
            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.size(12)
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: progressRow.modelData.displayName
                    color: Theme.text
                    elide: Text.ElideRight
                }
                Text {
                    textFormat: Text.PlainText
                    text: root.limitedModel.stage === "draft"
                          ? qsTranslate("TournamentLobby", "%1 cards picked").arg(progressRow.modelData.picked)
                          : (progressRow.modelData.deckSubmitted ? qsTranslate("TournamentLobby", "Deck submitted") : qsTranslate("TournamentLobby", "Building deck"))
                    color: progressRow.modelData.deckSubmitted ? Theme.success : Theme.textSecondary
                }
            }
        }
    }
}
