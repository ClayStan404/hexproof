// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "TournamentLobby"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: scoreEditor

    required property var wsModel

    property var pairing: ({})
    property bool correction: false
    property bool prefilledFromTable: false

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(540), parent.width - Theme.size(48))
    padding: Theme.size(24)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    Overlay.modal: Rectangle { color: "#A6050B09" }

    background: Rectangle {
        color: Theme.surfaceElevated
        radius: Theme.radiusLarge
        border.width: 1
        border.color: Theme.borderStrong
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(16)

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: scoreEditor.correction ? qsTranslate("TournamentLobby", "Correct result")
                                         : qsTranslate("TournamentLobby", "Report result")
            color: Theme.text
            font.pixelSize: Theme.fontSize(20)
            font.weight: Font.DemiBold
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: (scoreEditor.pairing.playerAName || "") + "  vs  "
                  + (scoreEditor.pairing.playerBName || "")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSize(13)
            elide: Text.ElideRight
        }

        Text {
            textFormat: Text.PlainText
            objectName: "scorePrefillHint"
            Layout.fillWidth: true
            visible: scoreEditor.prefilledFromTable
            text: qsTranslate("TournamentLobby", "Prefills from the finished tabletop match. Edit before submitting.")
            color: Theme.accent
            font.pixelSize: Theme.fontSize(12)
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(12)

            ColumnLayout {
                Layout.fillWidth: true
                Text { textFormat: Text.PlainText; text: scoreEditor.pairing.playerAName || qsTranslate("TournamentLobby", "Player A"); color: Theme.textMuted; font.pixelSize: Theme.fontSize(11); elide: Text.ElideRight }
                AppTextField { id: playerAWinsField; objectName: "playerAWinsField"; Layout.fillWidth: true; inputMethodHints: Qt.ImhDigitsOnly; validator: IntValidator { bottom: 0; top: 20 } }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Text { textFormat: Text.PlainText; text: scoreEditor.pairing.playerBName || qsTranslate("TournamentLobby", "Player B"); color: Theme.textMuted; font.pixelSize: Theme.fontSize(11); elide: Text.ElideRight }
                AppTextField { id: playerBWinsField; objectName: "playerBWinsField"; Layout.fillWidth: true; inputMethodHints: Qt.ImhDigitsOnly; validator: IntValidator { bottom: 0; top: 20 } }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Text { textFormat: Text.PlainText; text: qsTranslate("TournamentLobby", "Drawn games"); color: Theme.textMuted; font.pixelSize: Theme.fontSize(11) }
                AppTextField { id: drawnGamesField; objectName: "drawnGamesField"; Layout.fillWidth: true; inputMethodHints: Qt.ImhDigitsOnly; validator: IntValidator { bottom: 0; top: 20 } }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            AppButton {
                compact: true
                variant: "ghost"
                text: qsTranslate("TournamentLobby", "Cancel")
                onClicked: scoreEditor.close()
            }
            AppButton {
                compact: true
                variant: "primary"
                text: scoreEditor.correction ? qsTranslate("TournamentLobby", "Save correction")
                                             : qsTranslate("TournamentLobby", "Submit report")
                enabled: playerAWinsField.acceptableInput
                         && playerBWinsField.acceptableInput
                         && drawnGamesField.acceptableInput
                         && playerAWinsField.numberValue()
                            + playerBWinsField.numberValue()
                            + drawnGamesField.numberValue() <= 20
                onClicked: {
                    if (scoreEditor.correction) {
                        scoreEditor.wsModel.correctTournamentResult(
                                    scoreEditor.pairing.pairingId,
                                    playerAWinsField.numberValue(),
                                    playerBWinsField.numberValue(),
                                    drawnGamesField.numberValue())
                    } else {
                        scoreEditor.wsModel.reportTournamentResult(
                                    scoreEditor.pairing.pairingId,
                                    playerAWinsField.numberValue(),
                                    playerBWinsField.numberValue(),
                                    drawnGamesField.numberValue())
                    }
                    scoreEditor.close()
                }
            }
        }
    }

    function winsForName(tabletop, name) {
        const seats = tabletop && tabletop.seats ? tabletop.seats : []
        for (let index = 0; index < seats.length; ++index) {
            if (seats[index].displayName === name)
                return Number(seats[index].wins || 0)
        }
        return null
    }

    function mappedTabletopScore(value, tabletop) {
        if (!tabletop || !tabletop.seats)
            return null
        const playerAWins = winsForName(tabletop, value.playerAName)
        const playerBWins = winsForName(tabletop, value.playerBName)
        if (playerAWins === null || playerBWins === null)
            return null
        return {
            "playerAWins": playerAWins,
            "playerBWins": playerBWins,
            "drawnGames": Number(tabletop.drawnGames || 0)
        }
    }

    function openFor(value, correcting, tabletop) {
        pairing = value
        correction = correcting
        let playerAWins = Number(value.playerAWins || 0)
        let playerBWins = Number(value.playerBWins || 0)
        let drawnGames = Number(value.drawnGames || 0)
        const canPrefill = !correcting
                           && (!value.status || value.status === "open")
                           && playerAWins === 0 && playerBWins === 0
                           && drawnGames === 0
        const mapped = canPrefill ? mappedTabletopScore(value, tabletop) : null
        prefilledFromTable = mapped !== null
        if (mapped) {
            playerAWins = mapped.playerAWins
            playerBWins = mapped.playerBWins
            drawnGames = mapped.drawnGames
        }
        playerAWinsField.text = String(playerAWins)
        playerBWinsField.text = String(playerBWins)
        drawnGamesField.text = String(drawnGames)
        open()
    }
}
