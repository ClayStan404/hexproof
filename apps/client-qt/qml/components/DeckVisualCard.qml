// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Surface {
    id: root

    required property var card
    property var catalogModel: null
    property bool incrementEnabled: true
    property bool commanderEnabled: false
    property bool printingEnabled: false
    property bool considerEnabled: false
    property string moveText: ""
    signal incrementRequested()
    signal decrementRequested()
    signal commanderRequested()
    signal printingRequested()
    signal considerRequested()
    signal moveRequested()
    signal previewRequested(var card, string imageSource)

    readonly property string resolvedImageSource: {
        const current = root.card
        if (!current)
            return ""
        if (current.imageSource && String(current.imageSource).length > 0)
            return String(current.imageSource)
        if (!root.catalogModel || typeof root.catalogModel.imageSource !== "function")
            return ""
        if (typeof root.catalogModel.imageRevision !== "undefined")
            void root.catalogModel.imageRevision
        return root.catalogModel.imageSource(String(current.name || ""),
                                             String(current.setCode || ""),
                                             String(current.collectorNumber || ""))
    }

    implicitWidth: Theme.size(184)
    implicitHeight: Theme.size(284)
    radius: Theme.radiusMedium
    color: cardHover.hovered ? Theme.surfaceHover : Theme.surfaceMuted
    border.width: cardHover.hovered ? 2 : 1
    border.color: cardHover.hovered ? Theme.primary : Theme.border
    clip: true

    HoverHandler {
        id: cardHover
        onHoveredChanged: {
            if (hovered)
                root.previewRequested(root.card, root.resolvedImageSource)
        }
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onDoubleTapped: {
            if (root.printingEnabled)
                root.printingRequested()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.size(6)
        spacing: Theme.size(5)

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Image {
                id: cardImage
                anchors.fill: parent
                source: root.resolvedImageSource
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: false
            }

            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Theme.size(5)
                width: countText.implicitWidth + Theme.size(12)
                height: Theme.size(28)
                radius: Theme.size(14)
                color: "#D9141C18"
                border.width: 1
                border.color: Theme.borderStrong

                Text {
                    textFormat: Text.PlainText
                    id: countText
                    anchors.centerIn: parent
                    text: "×" + root.card.count
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(12)
                    font.weight: Font.Bold
                }
            }

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                visible: cardImage.status !== Image.Ready
                width: parent.width - Theme.size(16)
                text: root.card.displayName || root.card.name || qsTr("Card art unavailable")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(12)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.card.displayName || root.card.name
            color: Theme.text
            font.pixelSize: Theme.fontSize(11)
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(3)

            AppButton {
                compact: true
                variant: "ghost"
                text: "−"
                accessibleName: qsTr("Decrease card count")
                Layout.preferredWidth: Theme.size(30)
                onClicked: root.decrementRequested()
            }

            Text {
                textFormat: Text.PlainText
                text: root.card.count
                color: Theme.text
                font.pixelSize: Theme.fontSize(11)
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
                enabled: root.incrementEnabled
                onClicked: root.incrementRequested()
            }

            Item { Layout.fillWidth: true }

            AppButton {
                visible: root.commanderEnabled
                compact: true
                variant: "ghost"
                text: root.card.commander ? "★" : "☆"
                accessibleName: root.card.commander
                                ? qsTr("Remove commander")
                                : qsTr("Designate commander")
                Layout.preferredWidth: Theme.size(30)
                onClicked: root.commanderRequested()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.considerEnabled || root.moveText.length > 0
            spacing: Theme.size(4)

            AppButton {
                visible: root.considerEnabled
                compact: true
                variant: "ghost"
                text: qsTr("Consider")
                Layout.fillWidth: true
                onClicked: root.considerRequested()
            }

            AppButton {
                visible: root.moveText.length > 0
                compact: true
                variant: "ghost"
                text: root.moveText
                Layout.fillWidth: true
                onClicked: root.moveRequested()
            }
        }
    }
}
