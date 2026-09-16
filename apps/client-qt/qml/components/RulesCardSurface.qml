// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic

Rectangle {
    id: root

    required property var cardCatalogModel
    required property url cardBackSource
    required property bool visibleIdentity
    required property string name
    required property string setCode
    required property string collectorNumber
    required property bool tapped
    required property bool faceDown
    required property bool attacking
    required property string power
    required property string toughness
    required property string countersSummary
    property int damageMarked: 0
    property string attachmentId: ""
    property bool inspectable: false
    property bool actionable: false
    property bool selected: false
    property bool pointerActivationEnabled: true
    property bool exclusiveTap: false
    property bool previewEnabled: inspectable
    readonly property bool previewActive: previewEnabled && visible && (hover.hovered || activeFocus)
    signal inspectRequested()
    signal activationRequested()
    signal previewRequested()
    signal previewEnded()

    property bool rotateTapped: true
    property string hiddenLabel: qsTr("Face-down card")

    onPreviewActiveChanged: {
        if (previewActive)
            previewRequested()
        else
            previewEnded()
    }
    Component.onDestruction: if (previewActive) previewEnded()

    function activate() {
        if (actionable)
            activationRequested()
        else if (inspectable)
            inspectRequested()
    }

    function imageSource() {
        if (!root.visibleIdentity || root.faceDown)
            return root.cardBackSource
        if (!root.name || !root.cardCatalogModel
                || typeof root.cardCatalogModel.tableImageSource !== "function")
            return ""
        void root.cardCatalogModel.imageRevision
        return root.cardCatalogModel.tableImageSource(
                    root.name, root.setCode || "", root.collectorNumber || "")
    }

    radius: Theme.radiusSmall
    color: Theme.surfaceHover
    border.width: selected ? Theme.size(3)
                  : actionable || attacking ? Theme.size(2) : 1
    border.color: selected ? Theme.primary
                  : actionable ? Theme.accent
                  : activeFocus ? Theme.primary
                  : attacking ? Theme.error : Theme.borderStrong
    rotation: rotateTapped && tapped ? 90 : 0
    transformOrigin: Item.Center
    clip: true

    Image {
        id: cardArt
        anchors.fill: parent
        anchors.margins: Theme.size(2)
        source: root.imageSource()
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
    }

    Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        width: parent.width - Theme.size(10)
        visible: cardArt.status !== Image.Ready
        text: root.visibleIdentity && !root.faceDown && root.name
              ? root.name : qsTr("Hidden card")
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSize(8)
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
    }

    Rectangle {
        id: nameStrip
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Theme.size(22)
        color: Theme.badgeBackground

        Text {
            textFormat: Text.PlainText
            anchors.fill: parent
            anchors.leftMargin: Theme.size(4)
            anchors.rightMargin: Theme.size(4)
            text: root.visibleIdentity && !root.faceDown
                  ? root.name : root.hiddenLabel
            color: Theme.text
            font.pixelSize: Theme.fontSize(8)
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
    }

    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.size(3)
        visible: root.power.length > 0 || root.toughness.length > 0
        width: powerText.implicitWidth + Theme.size(8)
        height: Theme.size(18)
        radius: Theme.size(3)
        color: Theme.badgeBackground
        Text {
            id: powerText
            objectName: "rulesCardPowerToughness"
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.power + "/" + root.toughness
            color: Theme.primary
            font.pixelSize: Theme.fontSize(10)
            font.weight: Font.Bold
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: Theme.size(3)
        visible: root.damageMarked > 0
        width: damageText.implicitWidth + Theme.size(6)
        height: Theme.size(18)
        radius: Theme.size(3)
        color: Theme.errorMuted
        Text {
            id: damageText
            objectName: "rulesCardDamage"
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: qsTr("%1 dmg").arg(root.damageMarked)
            color: Theme.error
            font.pixelSize: Theme.fontSize(8)
            font.weight: Font.Bold
        }
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: nameStrip.top
        Rectangle {
            width: parent.width
            height: visible ? Theme.size(17) : 0
            visible: root.attachmentId.length > 0
            color: Theme.badgeBackground
            Text {
                objectName: "rulesCardAttachment"
                anchors.fill: parent
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: qsTr("Attached")
                color: Theme.text
                font.pixelSize: Theme.fontSize(8)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
        Rectangle {
            width: parent.width
            height: visible ? Theme.size(19) : 0
            visible: root.countersSummary.length > 0
            color: Theme.badgeBackground
            Text {
                objectName: "rulesCardCounters"
                anchors.fill: parent
                anchors.leftMargin: Theme.size(3)
                anchors.rightMargin: Theme.size(3)
                textFormat: Text.PlainText
                text: root.countersSummary
                color: Theme.primary
                font.pixelSize: Theme.fontSize(9)
                font.weight: Font.Bold
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    TapHandler {
        enabled: root.pointerActivationEnabled && (root.inspectable || root.actionable)
        acceptedButtons: Qt.LeftButton
        gesturePolicy: root.exclusiveTap ? TapHandler.WithinBounds : TapHandler.DragThreshold
        onTapped: root.activate()
    }
    Rectangle {
        objectName: "rulesCardSelectedTarget"
        visible: root.selected
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Theme.size(3)
        width: Theme.size(22)
        height: width
        radius: width / 2
        color: Theme.primary
        Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "✓"
            color: Theme.primaryInk
            font.pixelSize: Theme.fontSize(14)
            font.weight: Font.Bold
        }
    }
    TapHandler {
        enabled: root.inspectable
        acceptedButtons: Qt.RightButton
        gesturePolicy: root.exclusiveTap ? TapHandler.WithinBounds : TapHandler.DragThreshold
        onTapped: root.inspectRequested()
    }
    activeFocusOnTab: inspectable || actionable
    Keys.onReturnPressed: activate()
    Keys.onSpacePressed: activate()
    Accessible.role: inspectable || actionable ? Accessible.Button : Accessible.Graphic
    Accessible.name: root.visibleIdentity && !root.faceDown ? root.name : root.hiddenLabel
    Accessible.onPressAction: root.activate()

    ToolTip {
        id: cardTooltip
        objectName: "rulesCardTooltip"
        visible: hover.hovered && !root.previewEnabled
        text: [root.visibleIdentity && !root.faceDown ? root.name : root.hiddenLabel,
               root.power.length > 0 || root.toughness.length > 0
               ? root.power + "/" + root.toughness : "",
               root.damageMarked > 0 ? qsTr("Damage marked: %1").arg(root.damageMarked) : "",
               root.countersSummary,
               root.attachmentId ? qsTr("Attached") : ""]
              .filter(value => value.length > 0).join(" · ")
        contentItem: Text {
            objectName: "rulesCardTooltipText"
            textFormat: Text.PlainText
            text: cardTooltip.text
            font: cardTooltip.font
            wrapMode: Text.Wrap
            color: cardTooltip.palette.toolTipText
        }
    }

    HoverHandler {
        id: hover
        cursorShape: root.inspectable || root.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
}
