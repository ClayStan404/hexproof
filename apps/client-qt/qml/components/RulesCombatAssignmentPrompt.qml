// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    required property var wsModel
    required property var cardCatalogModel
    required property var sourceModel
    required property int promptId
    required property string assignmentKind
    property var selectionState: null
    property bool boardSelection: false
    property bool showDetails: false
    property var assignments: selectionState ? selectionState.assignments : ({})
    readonly property var chosenSource: boardSelection && selectionState ? selectionState.chosenSource : null
    readonly property int assignedCount: Object.keys(assignments).length
    readonly property bool validSelection: sourceModel
                                                   && sourceModel.validAssignments(assignments)
    readonly property bool canSubmit: validSelection && (!boardSelection || !chosenSource)

    readonly property bool narrowLayout: width < Theme.size(490)

    implicitHeight: !combatList.visible ? selectionControls.implicitHeight
                    : narrowLayout || boardSelection ? Theme.size(162) + selectionControls.implicitHeight
                    : Math.max(Theme.size(150), selectionControls.implicitHeight)

    function resetAssignments() {
        if (selectionState) selectionState.resetAssignments()
        else assignments = ({})
    }

    function choiceOptions(validTargets) {
        const result = [{"responseId": "",
                         "label": assignmentKind === "attackers"
                                  ? qsTr("Do not attack") : qsTr("Do not block")}]
        for (const target of validTargets) {
            const choice = Object.assign({}, target)
            if (assignmentKind === "blockers" && target.mustReceiveIfAble) {
                choice.label = qsTr("%1 · must be blocked if able").arg(target.label)
            }
            result.push(choice)
        }
        return result
    }

    function choiceIndex(sourceId, choices) {
        const selected = assignments[sourceId] || ""
        for (let index = 0; index < choices.length; ++index) {
            if (choices[index].responseId === selected)
                return index
        }
        return -1
    }

    function setAssignment(sourceId, targetId) {
        if (selectionState) { selectionState.setAssignment(sourceId, targetId); return }
        const next = Object.assign({}, assignments)
        if (!targetId)
            delete next[sourceId]
        else
            next[sourceId] = targetId
        assignments = next
    }

    function selectedTargets(sourceId) {
        const selected = assignments[sourceId]
        return Array.isArray(selected) ? selected : selected ? [selected] : []
    }

    function toggleAssignment(sourceId, targetId, maximum) {
        if (selectionState) { selectionState.toggleAssignment(sourceId, targetId, maximum); return }
        const selected = selectedTargets(sourceId).slice()
        const index = selected.indexOf(targetId)
        if (index >= 0)
            selected.splice(index, 1)
        else if (selected.length < maximum)
            selected.push(targetId)
        else
            return
        const next = Object.assign({}, assignments)
        if (selected.length)
            next[sourceId] = selected
        else
            delete next[sourceId]
        assignments = next
    }

    function focusAssignment(index) {
        if (index < 0 || index >= combatList.count)
            return false
        combatList.positionViewAtIndex(index, ListView.Contain)
        combatList.forceLayout()
        const tile = combatList.itemAtIndex(index)
        if (!tile)
            return false
        tile.forceActiveFocus(Qt.TabFocusReason)
        return true
    }

    function submitAssignments() {
        if (!canSubmit || (selectionState && !selectionState.canAct))
            return
        const result = []
        for (const sourceId of Object.keys(assignments)) {
            for (const targetId of selectedTargets(sourceId))
                result.push({"sourceId": sourceId, "targetId": targetId})
        }
        wsModel.respondRulesPromptWithAssignments(promptId, result)
    }

    onPromptIdChanged: { resetAssignments(); showDetails = false }

    GridLayout {
        anchors.fill: parent
        columns: root.narrowLayout || root.boardSelection ? 1 : 2
        columnSpacing: Theme.size(12)
        rowSpacing: Theme.size(12)

        RulesHorizontalListView {
            id: combatList
            objectName: "rulesCombatCandidates-" + root.assignmentKind
            visible: !root.boardSelection || root.showDetails

            Layout.fillWidth: true
            Layout.preferredHeight: Theme.size(150)
            Layout.fillHeight: true
            spacing: Theme.size(8)
            model: !root.boardSelection || root.showDetails ? root.sourceModel : null

            delegate: Rectangle {
                id: combatTile

                required property int index
                onActiveFocusChanged: {
                    if (activeFocus) {
                        const control = maxAssignments > 1 ? multiAssignmentButton : assignmentBox
                        control.forceActiveFocus(Qt.TabFocusReason)
                    }
                }
                required property string responseId
                required property string label
                required property string name
                required property string setCode
                required property string collectorNumber
                required property bool token
                required property var validTargets
                required property bool mustAssignIfAble
                required property int maxAssignments
                readonly property var choiceModel: root.choiceOptions(validTargets)

                width: Theme.size(228)
                height: combatList.itemHeight
                radius: Theme.radiusSmall
                color: Theme.surfaceMuted
                border.width: mustAssignIfAble ? 2 : 1
                border.color: mustAssignIfAble ? Theme.warning : Theme.border

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.size(6)
                    spacing: Theme.size(7)

                    Rectangle {
                        Layout.preferredWidth: Theme.size(82)
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
                                if (!root.cardCatalogModel || !combatTile.name
                                        || typeof root.cardCatalogModel.tableImageSource
                                        !== "function") {
                                    return ""
                                }
                                void root.cardCatalogModel.imageRevision
                                return root.cardCatalogModel.tableImageSource(
                                            combatTile.name, combatTile.setCode,
                                            combatTile.collectorNumber)
                            }
                        }

                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            width: parent.width - Theme.size(8)
                            visible: art.status !== Image.Ready
                            text: combatTile.label
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSize(9)
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
                            text: combatTile.label
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(10)
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            visible: combatTile.mustAssignIfAble
                            text: root.assignmentKind === "attackers"
                                  ? qsTr("Must attack if able") : ""
                            color: Theme.warning
                            font.pixelSize: Theme.fontSize(9)
                        }

                        ComboBox {
                            id: assignmentBox
                            objectName: "rulesCombatAssignment-" + combatTile.responseId

                            Layout.fillWidth: true
                            visible: combatTile.maxAssignments <= 1
                            Keys.onTabPressed: event => { event.accepted = root.focusAssignment(combatTile.index + 1) }
                            Keys.onBacktabPressed: event => { event.accepted = root.focusAssignment(combatTile.index - 1) }
                            model: combatTile.choiceModel
                            textRole: "label"
                            valueRole: "responseId"
                            currentIndex: root.choiceIndex(combatTile.responseId,
                                                           combatTile.choiceModel)
                            displayText: currentIndex >= 0 ? currentText
                                                          : qsTr("Choose target")
                            enabled: combatTile.maxAssignments > 0 && combatTile.choiceModel.length > 1
                            onActivated: root.setAssignment(combatTile.responseId,
                                                            currentValue)
                        }

                        AppButton {
                            id: multiAssignmentButton
                            property alias targetPopup: blockerTargetsPopup
                            objectName: "rulesCombatMultiAssignment-" + combatTile.responseId
                            compact: true
                            Layout.fillWidth: true
                            visible: combatTile.maxAssignments > 1
                            text: qsTr("Block %1 / %2").arg(root.selectedTargets(combatTile.responseId).length)
                                                     .arg(combatTile.maxAssignments)
                            Keys.onTabPressed: event => { event.accepted = root.focusAssignment(combatTile.index + 1) }
                            Keys.onBacktabPressed: event => { event.accepted = root.focusAssignment(combatTile.index - 1) }
                            onClicked: blockerTargetsPopup.open()

                            Popup {
                                id: blockerTargetsPopup
                                objectName: "rulesCombatBlockerTargets-" + combatTile.responseId
                                parent: Overlay.overlay
                                property point anchorPosition: Qt.point(0, 0)
                                property point promptPosition: Qt.point(0, 0)
                                x: {
                                    const left = root.narrowLayout
                                                 ? Math.max(margins, promptPosition.x) : margins
                                    const right = root.narrowLayout
                                                  ? Math.min(parent ? parent.width - margins : width,
                                                             promptPosition.x + root.width)
                                                  : (parent ? parent.width : width) - margins
                                    return Math.max(left, Math.min(anchorPosition.x, right - width))
                                }
                                y: {
                                    const below = anchorPosition.y + multiAssignmentButton.height
                                    const bottom = (parent ? parent.height : height) - margins
                                    return Math.max(margins, below + height <= bottom
                                                    ? below : anchorPosition.y - height)
                                }
                                width: Math.min(Theme.size(300),
                                                root.narrowLayout ? root.width : Theme.size(300),
                                                parent ? parent.width - margins * 2 : Theme.size(300))
                                height: Math.min(Theme.size(300),
                                                 parent ? parent.height - margins * 2 : Theme.size(300),
                                                 blockerTargetsList.contentHeight + padding * 2)
                                margins: Theme.size(8)
                                padding: Theme.size(6)
                                focus: true
                                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                                onAboutToShow: {
                                    anchorPosition = multiAssignmentButton.mapToItem(parent, 0, 0)
                                    promptPosition = root.mapToItem(parent, 0, 0)
                                }
                                onOpened: blockerTargetsList.forceActiveFocus(Qt.PopupFocusReason)
                                background: Rectangle {
                                    color: Theme.surfaceElevated
                                    radius: Theme.radiusSmall
                                    border.color: Theme.borderStrong
                                }

                                contentItem: ListView {
                                    id: blockerTargetsList
                                    objectName: "rulesCombatBlockerTargetList-" + combatTile.responseId
                                    clip: true
                                    model: blockerTargetsPopup.visible ? combatTile.validTargets : []
                                    boundsBehavior: Flickable.StopAtBounds
                                    ScrollBar.vertical: ScrollBar {}
                                    delegate: CheckDelegate {
                                        id: blockerTargetRow
                                        required property var modelData
                                        required property int index
                                        readonly property string targetId: modelData ? modelData.responseId : ""
                                        readonly property string sourceId: combatTile ? combatTile.responseId : ""
                                        readonly property int capacity: combatTile ? combatTile.maxAssignments : 0
                                        readonly property bool assigned: targetId !== "" && root.selectedTargets(sourceId).indexOf(targetId) >= 0
                                        objectName: "rulesCombatBlockerTarget-" + sourceId + "-" + targetId
                                        width: blockerTargetsList.width
                                        focus: ListView.isCurrentItem
                                        highlighted: ListView.isCurrentItem
                                        text: modelData ? modelData.label : ""
                                        palette.base: Theme.surface
                                        palette.text: Theme.text
                                        palette.mid: Theme.borderStrong
                                        palette.light: Theme.surfaceHover
                                        palette.midlight: Theme.highlightPressed
                                        palette.highlight: Theme.primary
                                        checked: assigned
                                        enabled: targetId !== "" && (assigned || root.selectedTargets(sourceId).length < capacity)
                                        onClicked: {
                                            blockerTargetsList.currentIndex = index
                                            root.toggleAssignment(sourceId, targetId, capacity)
                                        }
                                        contentItem: Text {
                                            textFormat: Text.PlainText
                                            text: blockerTargetRow.text
                                            font: blockerTargetRow.font
                                            color: blockerTargetRow.enabled ? Theme.text : Theme.textSecondary
                                            wrapMode: Text.Wrap
                                            rightPadding: blockerTargetRow.indicator.width + blockerTargetRow.spacing
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        ColumnLayout {
            id: selectionControls

            Layout.fillWidth: root.narrowLayout || root.boardSelection
            Layout.preferredWidth: root.narrowLayout || root.boardSelection ? -1 : Theme.size(184)
            spacing: Theme.size(8)

            Text {
                objectName: "rulesCombatInstruction-" + root.assignmentKind
                textFormat: Text.PlainText
                Layout.fillWidth: true
                visible: root.boardSelection
                text: root.chosenSource
                      ? root.assignmentKind === "attackers"
                        ? qsTr("%1: choose a highlighted player or permanent to attack.").arg(root.chosenSource.label)
                        : qsTr("%1: choose a highlighted creature to block.").arg(root.chosenSource.label)
                      : root.assignmentKind === "attackers"
                        ? qsTr("Select a creature, then the player or permanent to attack.")
                        : qsTr("Select a blocking creature, then the attacking creature.")
                color: root.chosenSource ? Theme.accent : Theme.textSecondary
                font.pixelSize: Theme.fontSize(11)
                wrapMode: Text.Wrap
            }

            Flow {
                Layout.fillWidth: true
                visible: root.boardSelection
                spacing: Theme.size(6)

                AppButton {
                    objectName: "rulesCombatCancelSelection-" + root.assignmentKind
                    visible: !!root.chosenSource
                    compact: true
                    text: qsTr("Cancel selection")
                    onClicked: root.selectionState.cancelSelection()
                }
                AppButton {
                    objectName: "rulesCombatRemoveAssignment-" + root.assignmentKind
                    visible: !!root.chosenSource && root.selectedTargets(root.chosenSource.responseId).length > 0
                    compact: true
                    text: root.assignmentKind === "attackers" ? qsTr("Do not attack") : qsTr("Do not block")
                    onClicked: root.selectionState.clearSelectedAssignment()
                }
                AppButton {
                    objectName: "rulesCombatClear-" + root.assignmentKind
                    visible: !root.chosenSource
                    enabled: root.assignedCount > 0
                    compact: true
                    text: qsTr("Clear assignments")
                    onClicked: root.resetAssignments()
                }
                AppButton {
                    objectName: "rulesCombatDetails-" + root.assignmentKind
                    compact: true
                    text: root.showDetails ? qsTr("Hide assignments") : qsTr("Assignment list")
                    onClicked: {
                        root.selectionState.cancelSelection()
                        root.showDetails = !root.showDetails
                    }
                }
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.assignmentKind === "attackers"
                      ? qsTr("%1 attacker(s) assigned").arg(root.assignedCount)
                      : qsTr("%1 blocker(s) assigned").arg(root.assignedCount)
                color: root.validSelection ? Theme.success : Theme.textSecondary
                font.pixelSize: Theme.fontSize(11)
                horizontalAlignment: Text.AlignHCenter
            }

            AppButton {
                objectName: "rulesConfirmCombat-" + root.assignmentKind
                Layout.fillWidth: true
                compact: true
                variant: "primary"
                text: root.assignmentKind === "attackers"
                      ? qsTr("Declare attackers") : qsTr("Declare blockers")
                enabled: root.canSubmit
                disabledReason: root.chosenSource ? qsTr("Choose a target or cancel the selection")
                                                 : qsTr("Resolve invalid combat assignments")
                onClicked: root.submitAssignments()
            }
        }
    }
}
