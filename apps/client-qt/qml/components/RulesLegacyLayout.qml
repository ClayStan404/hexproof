// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "RulesTable"

import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root
    required property var tableController
    property alias inspectionDock: inspectionDock
    property alias decisionDock: decisionDock
    objectName: "rulesGameLayout"
    anchors.fill: parent
    spacing: 0

    RulesTableActionRail {
        tableController: root.tableController
    }

    RulesStackRail {
        visible: root.tableController.stackTargetsVisible
        tableController: root.tableController
    }

    ColumnLayout {
        objectName: "rulesPlayArea"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumWidth: 0
        Layout.minimumHeight: 0
        spacing: 0

        InfoBanner {
            objectName: "rulesErrorBanner"
            Layout.fillWidth: true
            message: I18n.status(root.tableController.wsModel.lastError || "")
        }

        Loader {
            objectName: "rulesSideboardLoader"
            Layout.fillWidth: true
            Layout.fillHeight: true
            active: root.tableController.sideboarding
            visible: active
            sourceComponent: Component {
                SideboardPanel {
                    objectName: "rulesSideboardPanel"
                    enabled: root.tableController.roomConnected
                    wsModel: root.tableController.wsModel
                    gameTableModel: root.tableController.gameTableModel
                    tableModel: root.tableController.sideboardTableModel
                    cardCatalogModel: root.tableController.cardCatalogModel
                }
            }
        }

        RowLayout {
            objectName: "rulesWorkspace"
            visible: !root.tableController.sideboarding
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            Layout.minimumHeight: 0
            spacing: 0

            Item {
                objectName: "rulesBattlefieldHost"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                Layout.minimumHeight: 0

                RulesBattlefieldView {
                    anchors.fill: parent
                    tableController: root.tableController
                }

                Text {
                    textFormat: Text.PlainText
                    objectName: "rulesSnapshotStatus"
                    anchors.centerIn: parent
                    visible: !root.tableController.rulesSession.active
                    width: parent.width - Theme.size(32)
                    text: root.tableController.matchUi.matchFinished
                          ? qsTr("The match is complete. Review the public log or return to the room.")
                          : qsTr("Waiting for the first rules snapshot…")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(12)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }

            RulesInspectionDock {
                id: inspectionDock
                tableController: root.tableController
                visible: root.tableController.persistentInspectionDock || opened
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                Layout.minimumWidth: 0
                Layout.preferredWidth: root.tableController.inspectionDockWidth
                Layout.maximumWidth: root.tableController.inspectionDockWidth
            }
        }

        RulesDecisionDock {
            id: decisionDock
            tableController: root.tableController
            visible: !root.tableController.sideboarding
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.minimumHeight: 0
            Layout.preferredHeight: expanded
                                    ? Math.min(implicitHeight, root.tableController.maximumDecisionHeight)
                                    : implicitHeight
            Layout.maximumHeight: Layout.preferredHeight
        }

        RulesHandArea {
            visible: !root.tableController.sideboarding
            tableController: root.tableController
        }
    }
}
