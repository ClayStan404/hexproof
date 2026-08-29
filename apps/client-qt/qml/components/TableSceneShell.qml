// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "Table"

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property var tableController
    required property var gameLogModel

    property alias battlefieldView: battlefieldView
    property alias chatInput: gameLogRail.chatInput

    property alias librarySearchPopup: editorPopups.librarySearchPopup
    property alias shuffleLibraryReminder: editorPopups.shuffleLibraryReminder
    property alias publicZoneBrowser: editorPopups.publicZoneBrowser
    property alias lifeEditor: editorPopups.lifeEditor
    property alias drawCardsEditor: editorPopups.drawCardsEditor
    property alias libraryTopCountEditor: editorPopups.libraryTopCountEditor
    property alias libraryMoveCardsEditor: editorPopups.libraryMoveCardsEditor
    property alias counterLabelEditor: editorPopups.counterLabelEditor
    property alias playerCounterValueEditor: editorPopups.playerCounterValueEditor
    property alias cardCounterEditor: editorPopups.cardCounterEditor
    property alias cardFacePicker: editorPopups.cardFacePicker
    property alias libraryPositionEditor: editorPopups.libraryPositionEditor
    property alias handLibraryPositionEditor: editorPopups.handLibraryPositionEditor
    property alias tokenPicker: editorPopups.tokenPicker
    property alias commanderDamagePopup: editorPopups.commanderDamagePopup

    property alias diceRollPopup: tableDialogs.diceRollPopup
    property alias leaveRoomConfirmation: tableDialogs.leaveRoomConfirmation
    property alias libraryAccessConfirmation: tableDialogs.libraryAccessConfirmation
    property alias publicZoneMoveConfirmation: tableDialogs.publicZoneMoveConfirmation
    property alias concedeConfirmation: tableDialogs.concedeConfirmation
    property alias shuffleConfirmation: tableDialogs.shuffleConfirmation
    property alias mulliganConfirmation: tableDialogs.mulliganConfirmation
    property alias discardHandConfirmation:
        tableDialogs.discardHandConfirmation
    property alias drawConfirmation: tableDialogs.drawConfirmation
    property alias restartConfirmation: tableDialogs.restartConfirmation
    property alias rulesWarningDialog: tableDialogs.rulesWarningDialog
    property alias combatDeclarationPopup:
        tableDialogs.combatDeclarationPopup
    property alias gameResultPopup: tableDialogs.gameResultPopup
    property alias landPlayPopup: tableDialogs.landPlayPopup

    property alias ownLibraryMenu: tableMenus.ownLibraryMenu
    property alias opponentLibraryMenu: tableMenus.opponentLibraryMenu
    property alias battlefieldAreaMenu: tableMenus.battlefieldAreaMenu
    property alias handAreaMenu: tableMenus.handAreaMenu
    property alias handCardMenu: tableMenus.handCardMenu
    property alias cardToolsMenu: tableMenus.cardToolsMenu
    property alias tableSettingsPopup: tableSettingsPopup
    property alias shortcutHelp: shortcutHelp

    function requestPaint() {
        relationLayer.requestPaint()
    }

    readonly property var modalPopups: [
        librarySearchPopup,
        shuffleLibraryReminder,
        publicZoneBrowser,
        lifeEditor,
        drawCardsEditor,
        libraryTopCountEditor,
        libraryMoveCardsEditor,
        counterLabelEditor,
        playerCounterValueEditor,
        cardCounterEditor,
        cardFacePicker,
        diceRollPopup,
        libraryPositionEditor,
        handLibraryPositionEditor,
        tokenPicker,
        commanderDamagePopup,
        leaveRoomConfirmation,
        concedeConfirmation,
        shuffleConfirmation,
        mulliganConfirmation,
        discardHandConfirmation,
        drawConfirmation,
        restartConfirmation,
        rulesWarningDialog,
        combatDeclarationPopup,
        libraryAccessConfirmation,
        publicZoneMoveConfirmation,
        tableSettingsPopup,
        gameResultPopup,
        landPlayPopup,
        shortcutHelp
    ]
    readonly property bool modalOpen: modalPopups.some(popup => popup.opened)

    anchors.fill: parent

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            TableActionRail {
                tableController: root.tableController
                leaveRoomConfirmation: root.leaveRoomConfirmation
            }

            SharedZonesView {
                objectName: "sharedZonesView"
                Layout.minimumWidth: root.tableController.sharedZoneRailWidth
                Layout.preferredWidth: root.tableController.sharedZoneRailWidth
                Layout.maximumWidth: root.tableController.sharedZoneRailWidth
                Layout.fillHeight: true
                visible: root.tableController.showSharedColumn
                tableController: root.tableController
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                BattlefieldView {
                    id: battlefieldView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    tableController: root.tableController
                    areaMenu: root.battlefieldAreaMenu
                    cardMenu: root.cardToolsMenu
                    publicZoneBrowserPopup: root.publicZoneBrowser
                }

                TableHandArea {
                    tableController: root.tableController
                }
            }

            TableGameLogRail {
                id: gameLogRail
                tableController: root.tableController
                gameLogModel: root.gameLogModel
            }
        }
    }

    TableRelationLayer {
        id: relationLayer
        anchors.fill: parent
        tableController: root.tableController
        arrows: root.tableController.tableArrows
        cardPoints: root.tableController.battlefieldCardPoints
        seatPoints: root.tableController.battlefieldSeatPoints
        localSeat: root.tableController.roomSession.seatIndex
    }

    TableAttachmentStackLayer {
        tableController: root.tableController
    }

    TableOpponentZonePanelLayer {
        objectName: "opponentZonePanelLayer"
        anchors.fill: parent
        z: 3000
        visible: !root.tableController.gameSession.sideboarding
        tableController: root.tableController
        publicZoneBrowserPopup: root.publicZoneBrowser
    }

    TableOverlayLayer {
        tableController: root.tableController
    }

    BattlefieldViewControls {
        tableController: root.tableController
        logRail: gameLogRail
    }

    TableEditorPopups {
        id: editorPopups
        tableController: root.tableController
    }

    TableDialogs {
        id: tableDialogs
        tableController: root.tableController
    }

    TableMenus {
        id: tableMenus
        anchors.fill: parent
        tableController: root.tableController
        drawCardsEditorPopup: root.drawCardsEditor
        publicZoneBrowserPopup: root.publicZoneBrowser
        libraryTopCountEditorPopup: root.libraryTopCountEditor
        tokenPickerPopup: root.tokenPicker
        handLibraryPositionEditorPopup: root.handLibraryPositionEditor
        cardCounterEditorPopup: root.cardCounterEditor
        libraryPositionEditorPopup: root.libraryPositionEditor
        discardHandConfirmation: root.discardHandConfirmation
    }

    TableSettingsPopup {
        id: tableSettingsPopup
        objectName: "tableSettingsPopup"
        onSettingsRequested: function(showPlayers, showShared,
                                      showInspector, counterCount,
                                      showGameLog) {
            root.tableController.sessionUi.applyTableSettings(
                        showPlayers, showShared, showInspector,
                        counterCount, showGameLog)
        }
    }

    TableShortcutHelp {
        id: shortcutHelp
    }

    TableShortcuts {
        tableRoot: root.tableController
        drawCardsEditor: root.drawCardsEditor
        libraryTopCountEditor: root.libraryTopCountEditor
        tokenPicker: root.tokenPicker
        concedeConfirmation: root.concedeConfirmation
        shuffleConfirmation: root.shuffleConfirmation
        mulliganConfirmation: root.mulliganConfirmation
        shortcutHelp: root.shortcutHelp
    }

    SideboardPanel {
        objectName: "sideboardPanel"
        anchors.fill: parent
        visible: root.tableController.gameSession.sideboarding === true
        wsModel: root.tableController.wsModel
        gameTableModel: root.tableController.gameTableModel
        tableModel: root.tableController.sideboardTableModel
        cardCatalogModel: root.tableController.cardCatalogModel
    }
}
