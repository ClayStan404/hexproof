// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "BattlefieldView"

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Surface {
    id: root

    required property var tableController
    required property var publicZoneBrowserPopup
    required property var seatData
    required property real availableWidth
    required property real availableHeight
    required property int panelSlot
    required property var battlefieldBounds
    property bool isOwn: false
    property bool expanded: false

    readonly property bool hasSeatData:
        seatData !== null && seatData !== undefined
        && seatData.seat !== undefined
    readonly property int seatIndex: hasSeatData ? seatData.seat : -1
    readonly property string seatDisplayName:
        hasSeatData && seatData.displayName !== undefined
        ? seatData.displayName : ""
    readonly property int libraryCount:
        hasSeatData && seatData.libraryCount !== undefined
        ? seatData.libraryCount : 0
    readonly property var storedPosition:
        hasSeatData
        ? tableController.sharedZones.opponentZonePanelPosition(seatIndex)
        : ({})
    readonly property real maximumX: Math.max(0, availableWidth - width)
    readonly property real maximumY: Math.max(0, availableHeight - height)
    readonly property bool hasBattlefieldBounds:
        battlefieldBounds !== null && battlefieldBounds !== undefined
        && Number.isFinite(battlefieldBounds.x)
        && Number.isFinite(battlefieldBounds.y)
        && Number.isFinite(battlefieldBounds.width)
        && Number.isFinite(battlefieldBounds.height)
    readonly property real defaultX: Math.max(
                                         0,
                                         Math.min(
                                             maximumX,
                                             hasBattlefieldBounds
                                             ? battlefieldBounds.x
                                               + battlefieldBounds.width
                                               - width - Theme.size(8)
                                             : maximumX - Theme.size(8)))
    readonly property real defaultY: Math.max(
                                         0,
                                         Math.min(
                                             maximumY,
                                             hasBattlefieldBounds
                                             ? battlefieldBounds.y
                                               + battlefieldBounds.height
                                               - height - Theme.size(8)
                                             : Theme.size(8)
                                               + panelSlot
                                               * (height + Theme.size(8))))
    readonly property real resolvedX:
        Number.isFinite(storedPosition.x)
        ? storedPosition.x * maximumX : defaultX
    readonly property real resolvedY:
        Number.isFinite(storedPosition.y)
        ? storedPosition.y * maximumY : defaultY
    property real dragOriginX: 0
    property real dragOriginY: 0
    property real draggedX: resolvedX
    property real draggedY: resolvedY
    property bool dragStarted: false

    objectName: "opponentZoneDock" + seatIndex
    width: Math.min(
               Theme.size(174),
               Math.max(Theme.size(158),
                        availableWidth - Theme.size(12)))
    height: Math.min(Theme.size(166),
                     Math.max(Theme.size(128),
                              availableHeight - Theme.size(12)))
    x: panelDrag.active ? draggedX : resolvedX
    y: panelDrag.active ? draggedY : resolvedY
    z: panelDrag.active ? 1000 : 100 + panelSlot
    visible: hasSeatData && !isOwn && expanded
    color: Theme.surfaceElevated
    border.width: 1
    border.color: Theme.borderStrong

    GridLayout {
        anchors.fill: parent
        anchors.margins: Theme.size(6)
        columns: 2
        rows: 3
        columnSpacing: Theme.size(6)
        rowSpacing: Theme.size(6)

        RowLayout {
            objectName: "opponentZonePanelHeader" + root.seatIndex
            Layout.row: 0
            Layout.column: 0
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.size(15)
            spacing: Theme.size(2)

            Item {
                id: panelDragHandle
                objectName: "opponentZonePanelDragHandle" + root.seatIndex
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.size(15)

                Text {
                    textFormat: Text.PlainText
                    objectName: "opponentDisplayName" + root.seatIndex
                    anchors.fill: parent
                    text: root.seatDisplayName
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(10)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    hoverEnabled: true
                    cursorShape: panelDrag.active
                                 ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                }

                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped:
                        root.tableController.sharedZones.resetOpponentZonePanelPosition(
                            root.seatIndex)
                }

                ToolTip.visible: panelDragHandleHover.hovered
                ToolTip.text: qsTranslate(
                                  "BattlefieldViewControls",
                                  "Drag to move; right-click to reset position")

                HoverHandler {
                    id: panelDragHandleHover
                }

                DragHandler {
                    id: panelDrag
                    target: null
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
                        root.tableController.sharedZones.setOpponentZonePanelPosition(
                                    root.seatIndex,
                                    root.maximumX > 0
                                    ? root.draggedX / root.maximumX : 0,
                                    root.maximumY > 0
                                    ? root.draggedY / root.maximumY : 0)
                    }
                    onTranslationChanged: {
                        if (!active)
                            return
                        root.draggedX = Math.max(
                                    0, Math.min(
                                        root.maximumX,
                                        root.dragOriginX + translation.x))
                        root.draggedY = Math.max(
                                    0, Math.min(
                                        root.maximumY,
                                        root.dragOriginY + translation.y))
                    }
                }
            }

            Repeater {
                model: root.hasSeatData && !root.isOwn
                       && root.seatData.counters
                       ? root.seatData.counters.slice(
                             0, Math.max(
                                 0, Math.min(
                                     7,
                                     root.seatData.counterCount !== undefined
                                     ? root.seatData.counterCount : 0)))
                       : []

                delegate: PlayerCounterPip {
                    required property var modelData
                    required property int index
                    objectName: "playerCounterPip" + root.seatIndex
                                + "-" + index
                    Layout.preferredWidth: Theme.size(11)
                    Layout.preferredHeight: Theme.size(11)
                    counterKey: modelData.key
                    label: modelData.label
                    value: root.hasSeatData
                           ? root.tableController.gameValues.displayedCounterValue(
                                 root.seatIndex, modelData) : 0
                    editable: false
                    pipColor: [
                        "#FFF196", "#9696FF", "#969696", "#FA9696",
                        "#96FF96", "#F2F6F2", "#FF961E"
                    ][index]
                }
            }
        }

        Item {
            id: libraryPile
            Layout.row: 1
            Layout.column: 0
            Layout.minimumWidth: Theme.size(60)
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                radius: Theme.radiusMedium
                border.width: libraryMouse.containsMouse ? 1 : 0
                border.color: Theme.primary

                Image {
                    objectName: "opponentLibraryCardBack" + root.seatIndex
                    anchors.fill: parent
                    visible: root.libraryCount > 0
                    source: root.tableController.cardBackSource
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height * 63 / 88)
                    height: width * 88 / 63
                    visible: root.libraryCount <= 0
                    color: "transparent"
                    radius: Theme.radiusSmall
                    border.width: 1
                    border.color: Theme.border
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Theme.size(4)
                    width: libraryLabel.implicitWidth + Theme.size(12)
                    height: Theme.size(20)
                    radius: height / 2
                    color: Theme.badgeBackground
                    border.width: 1
                    border.color: Theme.badgeBorder

                    Text {
                        textFormat: Text.PlainText
                        id: libraryLabel
                        anchors.centerIn: parent
                        text: qsTr("Library") + " "
                              + root.libraryCount
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(9)
                        font.weight: Font.DemiBold
                    }
                }
            }

            MouseArea {
                id: libraryMouse
                objectName: !root.isOwn
                            ? "searchLibraryButton" + root.seatIndex
                            : "inactiveOpponentLibrary"
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                enabled: root.hasSeatData && root.tableController.canAct
                         && root.libraryCount > 0
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: function(mouse) {
                    if (!root.hasSeatData
                            || mouse.button !== Qt.RightButton)
                        return
                    const menu = root.tableController.opponentLibraryMenu
                    const position = libraryMouse.mapToItem(
                                       root.tableController,
                                       mouse.x, mouse.y)
                    menu.sourceSeat = root.seatIndex
                    menu.sourceLibraryCount = root.libraryCount
                    menu.x = position.x
                    menu.y = position.y
                    menu.open()
                }
                ToolTip.visible: containsMouse
                ToolTip.text: qsTr("Right-click for library actions")
            }
        }

        BattlefieldOpponentPublicZonePile {
            Layout.row: 1
            Layout.column: 1
            tableController: root.tableController
            publicZoneBrowserPopup: root.publicZoneBrowserPopup
            seatData: root.seatData
            isOwn: root.isOwn
            zoneName: "graveyard"
            zoneLabel: qsTr("GY")
            objectNamePrefix: "graveyard"
        }

        BattlefieldOpponentPublicZonePile {
            Layout.row: 2
            Layout.column: 0
            Layout.columnSpan: root.tableController.isCommanderFormat ? 1 : 2
            tableController: root.tableController
            publicZoneBrowserPopup: root.publicZoneBrowserPopup
            seatData: root.seatData
            isOwn: root.isOwn
            zoneName: "exile"
            zoneLabel: qsTr("Exile")
            objectNamePrefix: "exile"
        }

        Item {
            id: commandPile
            Layout.row: 2
            Layout.column: 1
            readonly property var cardsModel:
                root.hasSeatData ? root.seatData.commandZoneModel : null
            readonly property int cardCount:
                root.tableController.zoneState.modelCardCount(cardsModel)
            readonly property var topCard:
                root.hasSeatData
                ? root.tableController.zoneState.zoneCardAt(
                      root.seatIndex, "command", 0)
                : ({})
            visible: root.hasSeatData
                     && root.tableController.isCommanderFormat
            Layout.minimumWidth: visible ? Theme.size(68) : 0
            Layout.fillWidth: visible
            Layout.fillHeight: true

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                radius: Theme.radiusMedium
                clip: true
                border.width: commandMouse.containsMouse ? 1 : 0
                border.color: Theme.primary

                Repeater {
                    model: commandPile.cardsModel

                    delegate: Image {
                        required property var cardData
                        required property int index
                        visible: index < 2
                        objectName: index === 0
                                    ? "opponentCommanderCard"
                                      + root.seatIndex
                                    : "opponentCommanderCard"
                                      + root.seatIndex + "-" + index
                        width: (parent ? parent.width : 0)
                               * (commandPile.cardCount > 1 ? 0.72 : 1)
                        height: parent ? parent.height : 0
                        x: parent && commandPile.cardCount > 1
                           ? index * parent.width * 0.28 : 0
                        source:
                            root.tableController.presentation.tableCardImageSource(
                                cardData)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height * 63 / 88)
                    height: width * 88 / 63
                    visible: !commandPile.topCard.id
                    color: "transparent"
                    radius: Theme.radiusSmall
                    border.width: 1
                    border.color: Theme.border
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Theme.size(4)
                    width: Math.min(parent.width - Theme.size(4),
                                    commandLabel.implicitWidth + Theme.size(10))
                    height: Theme.size(28)
                    radius: height / 2
                    color: Theme.badgeBackground
                    border.width: 1
                    border.color: Theme.badgeBorder

                    Text {
                        textFormat: Text.PlainText
                        id: commandLabel
                        anchors.centerIn: parent
                        text: qsTr("Command") + " " + commandPile.cardCount
                              + "\n" + qsTr("Tax") + " "
                              + (root.hasSeatData
                                 ? root.tableController.gameValues.commanderTaxSummary(
                                       root.seatData) : "")
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(8)
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            MouseArea {
                id: commandMouse
                objectName: !root.isOwn
                            ? "commandZoneButton" + root.seatIndex
                            : "inactiveOpponentCommand"
                anchors.fill: parent
                enabled: root.hasSeatData
                         && root.tableController.isCommanderFormat
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.tableController.presentation.inspectCard(
                               commandPile.topCard, commandPile)
                onExited: root.tableController.presentation.hideCardPreview(
                              commandPile)
                onClicked: {
                    if (root.hasSeatData) {
                        root.publicZoneBrowserPopup.showZone(
                                    root.seatDisplayName, root.seatIndex,
                                    "command")
                    }
                }
            }
        }
    }
}
