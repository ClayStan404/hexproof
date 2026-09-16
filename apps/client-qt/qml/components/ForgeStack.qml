// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic

Rectangle {
    id: root
    required property var tableController
    property real unit: 1
    readonly property int count: entries.count
    readonly property Item scrollArea: viewport
    property string activeObjectId: ""
    property int activeTargetIndex: 0
    property int revision: 0
    property string locatedId: ""
    readonly property bool relationsEnabled: tableController.roomConnected && !tableController.sideboarding
    readonly property var activeEntry: {
        void revision
        return relationsEnabled ? entryFor(activeObjectId) || entries.itemAt(0) : null
    }
    readonly property var currentTarget: activeEntry && activeEntry.targets.length > 0
        ? activeEntry.targets[Math.min(activeTargetIndex, activeEntry.targets.length - 1)] : null
    signal targetRequested(var target)

    function entryFor(id) {
        for (let i = 0; i < entries.count; ++i) {
            const entry = entries.itemAt(i) as StackEntry
            if (entry && entry.objectId === id) return entry
        }
        return null
    }
    function clearSelection() { activeObjectId = ""; activeTargetIndex = 0 }
    function reveal(id) {
        const entry = entryFor(id)
        if (!entry) return false
        viewport.contentY = Math.max(0, Math.min(entry.y, viewport.contentHeight - viewport.height))
        return true
    }
    function pointFor(id, target) {
        void revision
        const entry = entryFor(id)
        if (!visible || !entry || viewport.height <= 0) return Qt.point(0, 0)
        const y = entry.y + 24 * unit
        if (y < viewport.contentY || y > viewport.contentY + viewport.height) return Qt.point(0, 0)
        return entry.mapToItem(target, 0, 24 * unit)
    }
    Timer { id: refresh; interval: 0; onTriggered: root.revision++ }
    Connections {
        target: root.tableController.rulesSession
        function onSnapshotChanged() { refresh.restart() }
    }
    onRelationsEnabledChanged: if (!relationsEnabled) clearSelection()
    color: "#f2132029"
    radius: 10 * unit
    border.color: "#53616a"
    visible: count > 0
    Text {
        textFormat: Text.PlainText
        x: 13 * root.unit
        y: 10 * root.unit
        text: qsTr("Stack · %1").arg(root.count)
        color: "#e4d3ac"
        font.pixelSize: 12 * root.unit
        font.weight: Font.DemiBold
    }
    component StackEntry: Rectangle {
        id: entry
        required property int index
        required property string objectId
        required property int controllerSeat
        required property string name
        required property string setCode
        required property string collectorNumber
        required property string rulesText
        required property var targets
        readonly property bool visibleIdentity: name.length > 0
        readonly property bool faceDown: !visibleIdentity
        objectName: "forgeStackEntry-" + objectId
        width: column.width
        height: Math.max(138 * root.unit, details.height + 18 * root.unit)
        radius: 7 * root.unit
        color: "#22323f"
        border.width: objectId === root.locatedId ? 3 : 1
        border.color: objectId === root.locatedId ? "#e5bd73" : index === 0 ? "#b39a6f" : "#465460"
        ForgeCard {
            objectName: "forgeStackCard-" + entry.objectId
            x: 7 * root.unit
            y: 7 * root.unit
            width: 86 * root.unit
            height: 120 * root.unit
            tableController: root.tableController
            card: entry
            objectKind: "spell"
            unit: root.unit
            fullFace: true
            located: entry.objectId === root.locatedId
            onActiveFocusChanged: if (activeFocus) viewport.contentY = Math.max(0, Math.min(entry.y, viewport.contentHeight - viewport.height))
        }
        Column {
            id: details
            x: 104 * root.unit
            y: 9 * root.unit
            width: parent.width - x - 8 * root.unit
            spacing: 5 * root.unit
            Text {
                textFormat: Text.PlainText
                width: parent.width
                text: entry.visibleIdentity ? entry.name
                    : entry.rulesText && entry.rulesText !== "Face-down spell" ? entry.rulesText : qsTr("Face-down spell")
                color: "#f0eee6"
                font.pixelSize: 13 * root.unit
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Text {
                textFormat: Text.PlainText
                width: parent.width
                text: root.tableController.matchUi.playerName(entry.controllerSeat)
                color: "#a7b7c4"
                font.pixelSize: 10 * root.unit
                elide: Text.ElideRight
            }
            Text {
                textFormat: Text.PlainText
                width: parent.width
                text: entry.rulesText
                color: "#b6c6cc"
                font.pixelSize: 10 * root.unit
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Repeater {
                model: entry.targets
                delegate: Button {
                    id: targetButton
                    required property var modelData
                    required property int index
                    readonly property bool relationSelected: !!root.activeEntry && root.activeEntry === entry
                        && Math.min(root.activeTargetIndex, entry.targets.length - 1) === index
                    objectName: "forgeStackTarget-" + entry.objectId + "-" + index
                    width: details.width
                    height: 27 * root.unit
                    padding: 4 * root.unit
                    text: qsTr("Target: %1").arg(modelData.label || (modelData.kind === "player"
                        ? qsTr("Seat %1").arg(modelData.seat + 1)
                        : modelData.kind === "spell" ? qsTr("Face-down spell") : qsTr("Hidden card")))
                    enabled: root.relationsEnabled
                    onActiveFocusChanged: if (activeFocus) {
                        const y = mapToItem(column, 0, 0).y
                        if (y < viewport.contentY) viewport.contentY = y
                        else if (y + height > viewport.contentY + viewport.height)
                            viewport.contentY = y + height - viewport.height
                    }
                    onClicked: {
                        root.activeObjectId = entry.objectId
                        root.activeTargetIndex = index
                        root.targetRequested(modelData)
                    }
                    ToolTip.visible: hovered
                    ToolTip.text: text
                    contentItem: Text {
                        textFormat: Text.PlainText
                        text: targetButton.text
                        color: "#d7dfdc"
                        font.pixelSize: 10 * root.unit
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    background: Rectangle {
                        radius: 4 * root.unit
                        color: targetButton.hovered ? "#3a535b" : "#29404a"
                        border.color: targetButton.relationSelected || targetButton.activeFocus ? "#e5bd73" : "#506d75"
                    }
                }
            }
        }
    }
    Flickable {
        id: viewport
        objectName: "forgeStackViewport"
        anchors.fill: parent
        anchors.margins: 7 * root.unit
        anchors.topMargin: 33 * root.unit
        contentWidth: width
        contentHeight: column.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: column
            x: 3 * root.unit
            width: viewport.width - 9 * root.unit
            spacing: 7 * root.unit
            Repeater {
                id: entries
                model: root.tableController.rulesSession.stack
                onCountChanged: viewport.contentY = 0
                onItemAdded: refresh.restart()
                onItemRemoved: refresh.restart()
                delegate: StackEntry {}
            }
        }
    }
}
