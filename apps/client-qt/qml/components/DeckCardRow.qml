// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Surface {
    id: root

    required property var card
    property bool sideboard: false
    property bool sideboardEnabled: true
    property bool commanderEnabled: false
    property bool printingEnabled: false
    property bool incrementEnabled: true
    property Item dropTarget: null
    property var catalogModel: null
    signal moveRequested()
    signal incrementRequested()
    signal decrementRequested()
    signal commanderRequested()
    signal printingRequested()

    readonly property string resolvedImageSource: {
        const card = root.card
        if (!card)
            return ""
        if (card.imageSource && String(card.imageSource).length > 0)
            return String(card.imageSource)
        if (!root.catalogModel || typeof root.catalogModel.imageSource !== "function")
            return ""
        if (typeof root.catalogModel.imageRevision !== "undefined"
                && root.catalogModel.imageRevision === -1)
            return ""
        void root.catalogModel.imageRevision
        return root.catalogModel.imageSource(String(card.name || ""),
                                             String(card.setCode || ""),
                                             String(card.collectorNumber || ""))
    }
    readonly property string resolvedTypeLine: {
        const card = root.card
        if (!card)
            return ""
        if (card.typeLine && String(card.typeLine).length > 0)
            return String(card.typeLine)
        if (!root.catalogModel || typeof root.catalogModel.cardTypeLine !== "function")
            return ""
        if (typeof root.catalogModel.imageRevision !== "undefined"
                && root.catalogModel.imageRevision === -1)
            return ""
        void root.catalogModel.imageRevision
        return root.catalogModel.cardTypeLine(String(card.name || ""),
                                              String(card.setCode || ""),
                                              String(card.collectorNumber || ""))
    }
    readonly property string printingLabel: {
        const card = root.card
        if (card && card.setCode && String(card.setCode).length > 0)
            return String(card.setCode) + " · #" + String(card.collectorNumber || "")
        return qsTr("Select printing")
    }

    implicitHeight: Theme.size(sideboard ? 68 : 66)
    radius: Theme.radiusMedium
    color: dragArea.drag.active ? Theme.surfaceHover : Theme.surfaceMuted
    border.color: dragArea.drag.active ? Theme.primary : Theme.border
    z: dragArea.drag.active ? 100 : 0

    Drag.active: dragArea.drag.active
    Drag.source: root
    Drag.hotSpot.x: width / 2
    Drag.hotSpot.y: height / 2
    Drag.keys: ["application/x-hexproof-card"]
    Drag.mimeData: {
        "application/x-hexproof-card": root.card.name,
        "application/x-hexproof-sideboard": root.sideboard ? "true" : "false"
    }

    states: State {
        when: dragArea.drag.active
        ParentChange {
            target: root
            parent: Overlay.overlay
        }
        PropertyChanges {
            root.opacity: 0.94
            root.scale: 1.02
        }
    }

    transitions: Transition {
        NumberAnimation {
            properties: "opacity,scale"
            duration: Theme.motionFast
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.size(7)
        spacing: Theme.size(7)

        Text {
            textFormat: Text.PlainText
            text: "⋮⋮"
            color: dragArea.containsMouse ? Theme.primary : Theme.textMuted
            font.pixelSize: Theme.fontSize(13)
            font.letterSpacing: -3
            Layout.preferredWidth: Theme.size(16)
            horizontalAlignment: Text.AlignHCenter

            MouseArea {
                id: dragArea
                objectName: "dragHandle"
                property point lastScenePosition
                anchors.fill: parent
                anchors.margins: -Theme.size(7)
                hoverEnabled: true
                cursorShape: Qt.OpenHandCursor
                drag.target: root
                drag.axis: Drag.XAndYAxis
                onPressed: mouse => {
                    lastScenePosition = mapToItem(null, mouse.x, mouse.y)
                }
                onPositionChanged: mouse => {
                    lastScenePosition = mapToItem(null, mouse.x, mouse.y)
                }
                onReleased: {
                    const action = root.Drag.drop()
                    if (action !== Qt.IgnoreAction || root.dropTarget === null)
                        return
                    const point = root.dropTarget.mapFromItem(
                        null, lastScenePosition.x, lastScenePosition.y)
                    if (point.x >= 0 && point.y >= 0
                            && point.x <= root.dropTarget.width
                            && point.y <= root.dropTarget.height)
                        root.moveRequested()
                }
            }
        }

        Rectangle {
            id: thumbnail
            objectName: "cardThumbnail"
            Layout.preferredWidth: Theme.size(34)
            Layout.preferredHeight: Theme.size(46)
            radius: Theme.size(6)
            color: Theme.primaryMuted
            clip: true

            Image {
                id: cardImage
                objectName: "cardArt"
                anchors.fill: parent
                source: root.resolvedImageSource
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
            }

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: root.card.displayName.length > 0
                      ? root.card.displayName.charAt(0).toUpperCase() : "?"
                color: Theme.primary
                font.pixelSize: Theme.fontSize(14)
                font.weight: Font.Bold
                visible: cardImage.status !== Image.Ready
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.printingEnabled
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.printingRequested()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: Theme.size(sideboard ? 68 : 120)
            spacing: Theme.size(2)

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.card.displayName
                color: Theme.text
                font.pixelSize: Theme.fontSize(13)
                font.weight: Font.Medium
                elide: Text.ElideRight
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.resolvedTypeLine.length > 0
                      ? root.resolvedTypeLine : qsTr("Metadata pending")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(10)
                elide: Text.ElideRight
            }
        }

        AppButton {
            objectName: "printingButton"
            visible: !root.sideboard && root.printingEnabled
            compact: true
            variant: "ghost"
            text: root.printingLabel
            Layout.preferredWidth: Theme.size(144)
            Layout.minimumWidth: Theme.size(112)
            Layout.maximumWidth: Theme.size(160)
            ToolTip.visible: hovered
            ToolTip.delay: 500
            ToolTip.text: text
            onClicked: root.printingRequested()
        }

        AppButton {
            visible: !root.sideboard && root.commanderEnabled
            compact: true
            variant: "ghost"
            text: root.card.commander ? "★" : "☆"
            accessibleName: root.card.commander
                            ? qsTr("Remove commander")
                            : qsTr("Designate commander")
            Layout.preferredWidth: Theme.size(36)
            ToolTip.visible: hovered
            ToolTip.text: root.card.commander
                          ? qsTr("Remove commander")
                          : qsTr("Designate commander")
            onClicked: root.commanderRequested()
        }

        AppButton {
            visible: !root.sideboard
            compact: true
            variant: "ghost"
            text: "−"
            accessibleName: qsTr("Decrease card count")
            Layout.preferredWidth: Theme.size(34)
            onClicked: root.decrementRequested()
        }

        Text {
            textFormat: Text.PlainText
            visible: !root.sideboard
            text: root.card.count
            color: Theme.text
            font.pixelSize: Theme.fontSize(13)
            font.weight: Font.DemiBold
            Layout.preferredWidth: Theme.size(24)
            horizontalAlignment: Text.AlignHCenter
        }

        AppButton {
            visible: !root.sideboard
            compact: true
            variant: "ghost"
            text: "+"
            accessibleName: qsTr("Increase card count")
            Layout.preferredWidth: Theme.size(34)
            enabled: root.incrementEnabled
            onClicked: root.incrementRequested()
        }

        AppButton {
            visible: !root.sideboard && root.sideboardEnabled
            compact: true
            variant: "ghost"
            text: qsTr("To side")
            Layout.preferredWidth: Theme.size(112)
            Layout.minimumWidth: Theme.size(112)
            onClicked: root.moveRequested()
        }

        ColumnLayout {
            visible: root.sideboard
            Layout.preferredWidth: Theme.size(202)
            Layout.minimumWidth: Theme.size(190)
            Layout.fillHeight: true
            spacing: Theme.size(2)

            AppButton {
                objectName: "sideboardPrintingButton"
                visible: root.printingEnabled
                compact: true
                variant: "ghost"
                text: root.printingLabel
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.size(24)
                ToolTip.visible: hovered
                ToolTip.delay: 500
                ToolTip.text: text
                onClicked: root.printingRequested()
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignBottom
                spacing: Theme.size(3)

                AppButton {
                    compact: true
                    variant: "ghost"
                    text: "−"
                    accessibleName: qsTr("Decrease card count")
                    Layout.preferredWidth: Theme.size(30)
                    Layout.preferredHeight: Theme.size(28)
                    onClicked: root.decrementRequested()
                }

                Text {
                    textFormat: Text.PlainText
                    text: root.card.count
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(12)
                    font.weight: Font.DemiBold
                    Layout.preferredWidth: Theme.size(20)
                    horizontalAlignment: Text.AlignHCenter
                }

                AppButton {
                    compact: true
                    variant: "ghost"
                    text: "+"
                    accessibleName: qsTr("Increase card count")
                    Layout.preferredWidth: Theme.size(30)
                    Layout.preferredHeight: Theme.size(28)
                    enabled: root.incrementEnabled
                    onClicked: root.incrementRequested()
                }

                AppButton {
                    compact: true
                    variant: "ghost"
                    text: qsTr("To main")
                    Layout.fillWidth: true
                    Layout.minimumWidth: Theme.size(104)
                    Layout.preferredHeight: Theme.size(28)
                    onClicked: root.moveRequested()
                }
            }
        }
    }
}
