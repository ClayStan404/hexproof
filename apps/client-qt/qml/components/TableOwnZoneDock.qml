// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "Table"

import QtQuick
import QtQuick.Layouts

Surface {
    id: root

    required property var tableController

    objectName: "ownZoneDock"
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Theme.size(4)
    width: visible
           ? Math.min(parent.width - Theme.size(8), Math.max(
                 Theme.size(tableController.isCommanderFormat ? 244 : 190), Math.min(
                 Theme.size(
                     (tableController.hasPartnerCommanders
                      ? 430
                      : (tableController.isCommanderFormat ? 380 : 270))
                     + tableController.visibleCounterCount
                       * (tableController.isCommanderFormat ? 14 : 12)),
                 parent.width
                 * (tableController.hasPartnerCommanders
                    ? 0.52
                    : (tableController.isCommanderFormat ? 0.46 : 0.40)))))
           : 0
    visible: tableController.roomSession.role === "player"
    z: 180
    color: Theme.surfaceElevated
    border.width: 1
    border.color: Theme.borderStrong

    readonly property int pileFloor: Theme.size(
                                         tableController.hasPartnerCommanders ? 80 : 54)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.size(8)
        spacing: Theme.size(4)

        TableOwnPlayerStatus {
            Layout.maximumHeight: Math.max(
                                      Theme.size(60),
                                      root.height - root.pileFloor - Theme.size(20))
            tableController: root.tableController
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: root.pileFloor
            spacing: Theme.size(4)

            TableOwnLibraryPile {
                tableController: root.tableController
            }

            TableOwnPublicZonePile {
                tableController: root.tableController
                zoneKey: "graveyard"
            }

            TableOwnPublicZonePile {
                tableController: root.tableController
                zoneKey: "exile"
            }

            TableOwnCommandZonePile {
                tableController: root.tableController
            }
        }
    }
}
