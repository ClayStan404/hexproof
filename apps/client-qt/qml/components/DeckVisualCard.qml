// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Surface {
    id: root

    required property var card
    property var catalogModel: null
    property bool incrementEnabled: true
    property bool commanderEnabled: false
    property bool printingEnabled: false
    property bool customArtEnabled: false
    property bool considerEnabled: false
    property string moveText: ""
    signal incrementRequested()
    signal decrementRequested()
    signal commanderRequested()
    signal printingRequested()
    signal customArtRequested()
    signal considerRequested()
    signal moveRequested()
    signal previewRequested(var card, string imageSource)
    signal previewEnded()

    readonly property string resolvedImageSource: {
        if (!root.visible)
            return ""
        const current = root.card
        if (!current)
            return ""
        if (root.catalogModel && typeof root.catalogModel.customImageSource === "function") {
            void root.catalogModel.imageRevision
            const custom = root.catalogModel.customImageSource(
                String(current.name || ""), String(current.setCode || ""),
                String(current.collectorNumber || ""))
            if (custom)
                return custom
        }
        if (root.catalogModel && typeof root.catalogModel.imageSource === "function") {
            if (typeof root.catalogModel.imageRevision !== "undefined")
                void root.catalogModel.imageRevision
            const resolved = root.catalogModel.imageSource(String(current.name || ""),
                                             String(current.setCode || ""),
                                             String(current.collectorNumber || ""))
            if (resolved)
                return resolved
        }
        return current.imageSourceResolved ? "" : String(current.imageSource || "")
    }

    readonly property bool commanderCard: card && card.commander === true

    implicitWidth: Theme.size(184)
    implicitHeight: Theme.size(284)
    radius: Theme.radiusMedium
    color: cardHover.hovered ? Theme.surfaceHover : Theme.surfaceMuted
    border.width: commanderCard || cardHover.hovered ? 2 : 1
    border.color: commanderCard ? Theme.accent
                  : (cardHover.hovered ? Theme.primary : Theme.border)
    clip: true

    HoverHandler {
        id: cardHover
        onHoveredChanged: {
            if (hovered)
                root.previewRequested(root.card, root.resolvedImageSource)
            else
                root.previewEnded()
        }
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onDoubleTapped: {
            if (root.printingEnabled)
                root.printingRequested()
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        enabled: root.printingEnabled || root.customArtEnabled
        onTapped: actionsMenu.popup()
    }

    DeckCardActionsMenu {
        id: actionsMenu
        printingEnabled: root.printingEnabled
        customArtEnabled: root.customArtEnabled
        onPrintingRequested: root.printingRequested()
        onCustomArtRequested: root.customArtRequested()
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
                sourceSize.width: Math.ceil(Theme.size(184) * Screen.devicePixelRatio)
                smooth: true
                mipmap: false
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

            Rectangle {
                objectName: "deckVisualCommanderBadge"
                visible: root.commanderCard
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Theme.size(6)
                implicitWidth: commanderBadgeLabel.implicitWidth + Theme.size(12)
                implicitHeight: Theme.size(22)
                radius: height / 2
                color: Theme.accentMuted
                border.width: 1
                border.color: Theme.accent

                Text {
                    id: commanderBadgeLabel
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: qsTr("Commander")
                    color: Theme.accent
                    font.pixelSize: Theme.fontSize(10)
                    font.weight: Font.DemiBold
                }
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
                objectName: "deckCardActionsButton"
                visible: root.customArtEnabled
                compact: true
                variant: "ghost"
                text: "⋯"
                accessibleName: qsTr("Card actions")
                Layout.preferredWidth: Theme.size(30)
                onClicked: actionsMenu.popup()
            }

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
