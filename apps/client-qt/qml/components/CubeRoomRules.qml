// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "CubeRoom"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ScrollView {
    id: root
    required property bool commanderCube
    required property string matchMode
    property var draftSettings: ({packsPerPlayer: 3, packsPerBatch: 1, cardsPerPack: 20})
    contentWidth: availableWidth
    clip: true
    ColumnLayout {
        width: root.availableWidth
        spacing: Theme.size(16)
        Repeater {
            model: [
                root.commanderCube ? qsTranslate("CubeRoom", "Commander Cube rules") : qsTranslate("CubeRoom", "Cube rules"),
                root.commanderCube
                    ? qsTranslate("CubeRoom", "Draft: %1 packs of %3 cards per player. Open %2 pack(s) together and choose 2 cards from each before passing. The last 1 or 2 cards are collected automatically. Direction alternates each batch; an odd final pack is drafted alone.")
                        .arg(root.draftSettings.packsPerPlayer || 3).arg(root.draftSettings.packsPerBatch || 1)
                        .arg(root.draftSettings.cardsPerPack || 20)
                    : qsTranslate("CubeRoom", "Draft: 3 packs of 15 cards per player. Choose 1 card each pick. Passing direction alternates each pack."),
                root.commanderCube
                    ? qsTranslate("CubeRoom", "Build at least 60 cards including 1 or 2 commanders. Commander eligibility, pairing and color identity are reminders for your group's house rules.")
                    : qsTranslate("CubeRoom", "Build at least 40 cards. You may add basic lands from outside your drafted pool."),
                root.commanderCube
                    ? qsTranslate("CubeRoom", "Piper fallback: up to 2 copies of The Prismatic Piper are available outside the pool. Choose a color for each selected Piper. Only selected copies count toward your deck. Basic lands are also available.") : "",
                root.commanderCube
                    ? qsTranslate("CubeRoom", "Optional cards: add up to one outside copy each of Sol Ring, Command Tower, and Arcane Signet during deck building. Only selected copies enter your deck; unused copies stay outside the pool.") : "",
                qsTranslate("CubeRoom", "Keep your picks as the starting main deck, or rebuild from the pool. Draft-time commander plans are private hints, not final commander selections. Land suggestions never remove cards or restrict submission."),
                qsTranslate("CubeRoom", "A short disconnect preserves the seat and waits. Auto-draft only starts with explicit consent: enable it yourself, or the host may confirm it after a seat has been offline for over 3 minutes. Picks are random and pools stay private. Reclaim control when you return."),
                qsTranslate("CubeRoom", "During building, you may sit out while keeping your seat, pool and deck. At least 2 participating players must submit before free play begins. You can return later; once free play has started, submit a deck before rejoining."),
                root.commanderCube
                    ? qsTranslate("CubeRoom", "After everyone submits, players enter balanced EDH tables of up to 4 players (BO 1). Eight draft players split into two tables of four. Ready up at your table to start; later games use free invitations.")
                    : qsTranslate("CubeRoom", "With 2 participating players, submitting both decks opens your match room (%1) automatically. Larger groups choose opponents for free play. Ready up in the match room to start; there are no scheduled rounds or standings.").arg(root.matchMode === "bo3" ? qsTranslate("CubeRoom", "BO 3") : qsTranslate("CubeRoom", "BO 1")),
                qsTranslate("CubeRoom", "Leaving as host closes the room for everyone. Sitting out does not close the room.")
            ]
            delegate: Text {
                textFormat: Text.PlainText
                required property int index
                required property string modelData
                objectName: "cubeRule-" + index
                Layout.fillWidth: true
                visible: modelData.length > 0
                text: modelData
                color: index === 0 ? Theme.text : Theme.textSecondary
                font.pixelSize: Theme.fontSize(index === 0 ? 20 : 13)
                font.weight: index === 0 ? Font.DemiBold : Font.Normal
                wrapMode: Text.WordWrap
            }
        }
    }
}
