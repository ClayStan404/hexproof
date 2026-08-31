// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property var wsModel
    required property var cardCatalogModel
    required property var targetModel
    required property var damageSource
    required property int promptId
    required property int totalDamage
    required property bool deathtouch
    property var damageItems: []
    property var assignments: ({})
    property int visualRevision: 0
    readonly property int assignedDamage: assignmentTotal()
    readonly property int remainingDamage: totalDamage - assignedDamage
    readonly property bool validAssignment: remainingDamage === 0
                                                    && validDamageOrder()

    implicitHeight: Theme.size(184)

    function resetAssignments() {
        damageItems = targetModel && typeof targetModel.items === "function"
                      ? targetModel.items() : []
        const next = ({})
        for (const item of damageItems)
            next[item.responseId] = 0
        assignments = next
        visualRevision++
    }

    function assignedTo(targetId) {
        void visualRevision
        return assignments[targetId] || 0
    }

    function assignmentTotal() {
        void visualRevision
        let result = 0
        for (const item of damageItems)
            result += assignments[item.responseId] || 0
        return result
    }

    function validDamageOrder() {
        void visualRevision
        let laterDamage = 0
        for (let index = damageItems.length - 1; index >= 0; --index) {
            const item = damageItems[index]
            const assigned = assignments[item.responseId] || 0
            if (laterDamage > 0 && item.lethalDamage >= 0
                    && assigned < item.lethalDamage)
                return false
            laterDamage += assigned
        }
        return true
    }

    function setDamage(targetId, requestedDamage) {
        const index = damageItems.findIndex(item => item.responseId === targetId)
        if (index < 0 || requestedDamage < 0)
            return false
        for (let previous = 0; previous < index; ++previous) {
            const item = damageItems[previous]
            if (requestedDamage > 0 && item.lethalDamage >= 0
                    && assignedTo(item.responseId) < item.lethalDamage)
                return false
        }
        const current = assignedTo(targetId)
        if (assignmentTotal() - current + requestedDamage > totalDamage)
            return false
        const next = Object.assign({}, assignments)
        next[targetId] = requestedDamage
        if (requestedDamage < current) {
            const item = damageItems[index]
            if (item.lethalDamage >= 0 && requestedDamage < item.lethalDamage) {
                for (let later = index + 1; later < damageItems.length; ++later)
                    next[damageItems[later].responseId] = 0
            }
        }
        assignments = next
        visualRevision++
        return true
    }

    function adjustDamage(targetId, delta) {
        return setDamage(targetId, assignedTo(targetId) + delta)
    }

    function autoAssign() {
        const next = ({})
        let remaining = totalDamage
        for (let index = 0; index < damageItems.length; ++index) {
            const item = damageItems[index]
            let amount = 0
            if (remaining > 0) {
                if (index + 1 < damageItems.length && item.lethalDamage >= 0)
                    amount = Math.min(remaining, item.lethalDamage)
                else
                    amount = remaining
            }
            next[item.responseId] = amount
            remaining -= amount
        }
        assignments = next
        visualRevision++
    }

    function submitDamage() {
        if (!validAssignment)
            return
        const result = []
        for (const item of damageItems) {
            result.push({"targetId": item.responseId,
                         "damage": assignedTo(item.responseId)})
        }
        wsModel.respondRulesPromptWithDamage(promptId, result)
    }

    onPromptIdChanged: resetAssignments()
    onTargetModelChanged: resetAssignments()
    Component.onCompleted: resetAssignments()

    RowLayout {
        anchors.fill: parent
        spacing: Theme.size(10)

        ListView {
            id: targetList

            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: ListView.Horizontal
            spacing: Theme.size(8)
            clip: true
            model: root.targetModel

            delegate: Rectangle {
                id: damageTile

                required property int index
                required property string responseId
                required property string label
                required property string name
                required property string setCode
                required property string collectorNumber
                required property bool token
                required property int lethalDamage

                width: Theme.size(184)
                height: targetList.height
                radius: Theme.radiusSmall
                color: Theme.surfaceMuted
                border.width: 1
                border.color: root.assignedTo(responseId) > 0
                              ? Theme.primary : Theme.border

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.size(6)
                    spacing: Theme.size(6)

                    Rectangle {
                        Layout.preferredWidth: Theme.size(72)
                        Layout.fillHeight: true
                        radius: Theme.radiusSmall
                        color: Theme.surface
                        clip: true

                        Image {
                            id: art

                            anchors.fill: parent
                            anchors.margins: Theme.size(2)
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            source: {
                                if (!root.cardCatalogModel || !damageTile.name
                                        || typeof root.cardCatalogModel.tableImageSource
                                        !== "function") {
                                    return ""
                                }
                                void root.cardCatalogModel.imageRevision
                                return root.cardCatalogModel.tableImageSource(
                                            damageTile.name, damageTile.setCode,
                                            damageTile.collectorNumber)
                            }
                        }

                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            width: parent.width - Theme.size(8)
                            visible: art.status !== Image.Ready
                            text: damageTile.label
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSize(8)
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.size(5)

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: damageTile.label
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(9)
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: damageTile.lethalDamage >= 0
                                  ? qsTr("Lethal: %1").arg(damageTile.lethalDamage)
                                  : qsTr("Defender")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSize(8)
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.size(3)

                            AppButton {
                                compact: true
                                text: "−"
                                enabled: root.assignedTo(damageTile.responseId) > 0
                                onClicked: root.adjustDamage(damageTile.responseId, -1)
                            }

                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: String(root.assignedTo(damageTile.responseId))
                                color: Theme.text
                                font.pixelSize: Theme.fontSize(14)
                                font.weight: Font.Bold
                                horizontalAlignment: Text.AlignHCenter
                            }

                            AppButton {
                                compact: true
                                text: "+"
                                enabled: root.remainingDamage > 0
                                onClicked: root.adjustDamage(damageTile.responseId, 1)
                            }
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.preferredWidth: Theme.size(176)
            spacing: Theme.size(6)

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTr("%1 / %2 damage assigned")
                      .arg(root.assignedDamage).arg(root.totalDamage)
                color: root.validAssignment ? Theme.success : Theme.text
                font.pixelSize: Theme.fontSize(10)
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                visible: root.deathtouch
                text: qsTr("Deathtouch: 1 damage is lethal")
                color: Theme.warning
                font.pixelSize: Theme.fontSize(8)
                horizontalAlignment: Text.AlignHCenter
            }

            RowLayout {
                Layout.fillWidth: true

                AppButton {
                    Layout.fillWidth: true
                    compact: true
                    text: qsTr("Auto")
                    onClicked: root.autoAssign()
                }

                AppButton {
                    Layout.fillWidth: true
                    compact: true
                    text: qsTr("Reset")
                    onClicked: root.resetAssignments()
                }
            }

            AppButton {
                Layout.fillWidth: true
                compact: true
                variant: "primary"
                text: qsTr("Assign damage")
                enabled: root.validAssignment
                disabledReason: qsTr("Assign all available damage in order")
                onClicked: root.submitDamage()
            }
        }
    }
}
