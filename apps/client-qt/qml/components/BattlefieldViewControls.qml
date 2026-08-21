// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "Table"

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property var tableController
    required property Item logRail
    property bool panelOpen: false
    property bool panelPinned: false
    property real dragX: 0
    property real dragY: 0
    readonly property real controlSize: Theme.size(44)
    readonly property real edgeMargin: Theme.size(6)
    readonly property var preferences: tableController.preferencesModel
    readonly property real savedX:
        preferences ? Number(preferences.tableBattlefieldControlX) : -1
    readonly property real savedY:
        preferences ? Number(preferences.tableBattlefieldControlY) : -1
    readonly property bool hasSavedPosition:
        Number.isFinite(savedX) && Number.isFinite(savedY)
        && savedX >= 0 && savedY >= 0

    anchors.fill: parent
    z: 3500
    visible: tableController.usesEDHBattlefieldLayout
             && tableController.gameSession.sideboarding !== true
             && !tableController.tableModalOpen
    enabled: visible

    function bounded(value, minimum, maximum) {
        return Math.max(minimum, Math.min(maximum, value))
    }

    function defaultPosition() {
        if (logRail.visible && logRail.width > controlSize) {
            return Qt.point(logRail.x + logRail.width
                            - controlSize - edgeMargin,
                            logRail.y + edgeMargin)
        }
        return Qt.point(width - controlSize - edgeMargin,
                        (height - controlSize) / 2)
    }

    function restingX() {
        const position = hasSavedPosition
                       ? savedX * width - controlSize / 2
                       : defaultPosition().x
        return bounded(position, edgeMargin,
                       Math.max(edgeMargin,
                                width - controlSize - edgeMargin))
    }

    function restingY() {
        const position = hasSavedPosition
                       ? savedY * height - controlSize / 2
                       : defaultPosition().y
        return bounded(position, edgeMargin,
                       Math.max(edgeMargin,
                                height - controlSize - edgeMargin))
    }

    function togglePanel() {
        panelPinned = !panelPinned
        panelOpen = panelPinned || !panelOpen
        if (panelOpen)
            closeTimer.stop()
    }

    function scheduleClose() {
        if (!controlHover.hovered && !panelHover.hovered)
            closeTimer.restart()
    }

    function persistPosition(x, y) {
        if (!preferences || width <= 0 || height <= 0)
            return
        const normalizedX = bounded((x + controlSize / 2) / width, 0, 1)
        const normalizedY = bounded((y + controlSize / 2) / height, 0, 1)
        if (typeof preferences.setTableBattlefieldControlPosition === "function") {
            preferences.setTableBattlefieldControlPosition(normalizedX,
                                                           normalizedY)
        } else {
            preferences.tableBattlefieldControlX = normalizedX
            preferences.tableBattlefieldControlY = normalizedY
        }
    }

    function resetPosition() {
        if (!preferences)
            return
        if (typeof preferences.setTableBattlefieldControlPosition === "function") {
            preferences.setTableBattlefieldControlPosition(-1, -1)
        } else {
            preferences.tableBattlefieldControlX = -1
            preferences.tableBattlefieldControlY = -1
        }
        panelPinned = false
        panelOpen = false
    }

    onVisibleChanged: {
        if (!visible) {
            panelPinned = false
            panelOpen = false
        }
    }

    Surface {
        id: controlBall
        objectName: "battlefieldLayoutControlButton"
        signal clicked()
        signal resetRequested()
        readonly property string accessibleLabel:
            qsTr("Battlefield card size · %1%")
                .arg(Math.round(root.tableController
                                .battlefieldLayout.cardScale * 100))

        x: controlDrag.active ? root.dragX : root.restingX()
        y: controlDrag.active ? root.dragY : root.restingY()
        z: 2
        width: root.controlSize
        height: width
        radius: width / 2
        elevated: true
        interactive: true
        color: Theme.surfaceElevated
        border.width: root.panelOpen ? Theme.size(2) : 1
        border.color: root.panelOpen ? Theme.primary : Theme.borderStrong
        Accessible.role: Accessible.Button
        Accessible.name: accessibleLabel
        Accessible.description: qsTr("Drag to move; right-click to reset position")
        onClicked: root.togglePanel()
        onResetRequested: root.resetPosition()

        Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: Math.round(root.tableController
                             .battlefieldLayout.cardScale * 100) + "%"
            color: Theme.text
            font.pixelSize: Theme.fontSize(9)
            font.weight: Font.DemiBold
        }

        HoverHandler {
            id: controlHover

            onHoveredChanged: {
                if (hovered) {
                    root.panelOpen = true
                    closeTimer.stop()
                } else {
                    root.scheduleClose()
                }
            }
        }

        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: controlBall.clicked()
        }

        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: controlBall.resetRequested()
        }

        DragHandler {
            id: controlDrag
            target: null
            acceptedButtons: Qt.LeftButton
            property real startX: 0
            property real startY: 0

            onActiveChanged: {
                if (active) {
                    startX = controlBall.x
                    startY = controlBall.y
                    root.dragX = startX
                    root.dragY = startY
                    root.panelPinned = false
                    root.panelOpen = false
                } else {
                    root.persistPosition(root.dragX, root.dragY)
                }
            }
            onTranslationChanged: {
                if (!active)
                    return
                root.dragX = root.bounded(
                            startX + translation.x,
                            root.edgeMargin,
                            Math.max(root.edgeMargin,
                                     root.width - controlBall.width
                                     - root.edgeMargin))
                root.dragY = root.bounded(
                            startY + translation.y,
                            root.edgeMargin,
                            Math.max(root.edgeMargin,
                                     root.height - controlBall.height
                                     - root.edgeMargin))
            }
        }
    }

    Surface {
        id: controlsPanel
        objectName: "battlefieldLayoutControls"
        readonly property real preferredX:
            controlBall.x - width - Theme.size(6)

        x: preferredX >= root.edgeMargin
           ? preferredX
           : root.bounded(controlBall.x + controlBall.width + Theme.size(6),
                          root.edgeMargin,
                          Math.max(root.edgeMargin,
                                   root.width - width - root.edgeMargin))
        y: root.bounded(controlBall.y + controlBall.height / 2 - height / 2,
                        root.edgeMargin,
                        Math.max(root.edgeMargin,
                                 root.height - height - root.edgeMargin))
        z: 1
        visible: root.panelOpen
        elevated: true
        color: Theme.surfaceElevated
        opacity: 0.96
        radius: Theme.radiusMedium
        width: controlsRow.implicitWidth + Theme.size(12)
        height: controlsRow.implicitHeight + Theme.size(8)

        HoverHandler {
            id: panelHover

            onHoveredChanged: {
                if (hovered) {
                    closeTimer.stop()
                } else {
                    root.scheduleClose()
                }
            }
        }

        RowLayout {
            id: controlsRow
            anchors.centerIn: parent
            spacing: Theme.size(2)

            AppButton {
                objectName: "decreaseBattlefieldCardScaleButton"
                Layout.preferredWidth: Theme.size(32)
                compact: true
                variant: "ghost"
                text: "−"
                accessibleName: qsTr("Decrease battlefield card size")
                enabled: root.tableController.battlefieldLayout.cardScale > 0.5
                onClicked:
                    root.tableController.battlefieldLayout.adjustCardScale(-0.05)
            }
            AppButton {
                objectName: "resetBattlefieldCardScaleButton"
                Layout.preferredWidth: Theme.size(82)
                compact: true
                variant: root.tableController.battlefieldLayout
                             .automaticCardScaleEnabled
                         ? "ghost" : "highlight"
                text: root.tableController.battlefieldLayout
                           .automaticCardScaleEnabled
                      ? qsTr("Auto %1%").arg(
                            Math.round(root.tableController
                                       .battlefieldLayout.cardScale * 100))
                      : qsTr("%1%").arg(
                            Math.round(root.tableController
                                       .battlefieldLayout.cardScale * 100))
                accessibleName: qsTr("Reset battlefield card size to automatic")
                onClicked:
                    root.tableController.battlefieldLayout.resetCardScale()
            }
            AppButton {
                objectName: "increaseBattlefieldCardScaleButton"
                Layout.preferredWidth: Theme.size(32)
                compact: true
                variant: "ghost"
                text: "+"
                accessibleName: qsTr("Increase battlefield card size")
                enabled: root.tableController.battlefieldLayout.cardScale < 1.25
                onClicked:
                    root.tableController.battlefieldLayout.adjustCardScale(0.05)
            }
        }
    }

    Timer {
        id: closeTimer
        interval: 350
        onTriggered: {
            if (!controlHover.hovered && !panelHover.hovered) {
                root.panelPinned = false
                root.panelOpen = false
            }
        }
    }
}
