// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick
import QtQuick.Controls.Basic

Rectangle {
    id: root
    required property var entries
    property string assetRoot: ""
    property real unit: 1
    property real maximumHeight: 365 * unit
    signal targetRequested(string id)
    readonly property Item scrollArea: viewport
    signal inspected(var card)
    objectName: "studyStack"
    width: 274 * unit
    height: Math.min(maximumHeight, column.height + 28 * unit)
    radius: 12 * unit
    color: "#f2132029"
    border.color: "#53616a"
    visible: entries.length > 0
    onEntriesChanged: viewport.contentY = 0
    Flickable {
        id: viewport
        anchors.fill: parent
        anchors.margins: 3 * root.unit
        contentWidth: width
        contentHeight: column.height + 22 * root.unit
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { objectName: "studyStackScroll" }
        Column {
            id: column
            x: 11 * root.unit
            y: 11 * root.unit
            width: root.width - 28 * root.unit
            spacing: 9 * root.unit
            Item {
                width: parent.width
                height: 24 * root.unit
                Text {
                    textFormat: Text.PlainText
                    text: "STACK  /  " + root.entries.length
                    color: "#d0dbe0"
                    font.pixelSize: 11 * root.unit
                    font.letterSpacing: 1.8
                    font.weight: Font.DemiBold
                }
                Text {
                    textFormat: Text.PlainText
                    anchors.right: parent.right
                    text: "Top resolves first"
                    color: "#92a5b4"
                    font.pixelSize: 10 * root.unit
                }
            }
            Repeater {
                model: root.entries.slice().reverse()
                delegate: Rectangle {
                    id: entry
                    required property var modelData
                    required property int index
                    width: column.width
                    height: (index === 0 ? 193 : 95) * root.unit
                    radius: 8 * root.unit
                    clip: true
                    color: "#22323f"
                    border.color: index === 0 ? "#b39a6f" : "#465460"
                    Image {
                        width: parent.width - 4 * root.unit
                        height: entry.index === 0 ? 91 * root.unit : parent.height
                        x: 2 * root.unit
                        y: 2 * root.unit
                        source: root.assetRoot ? root.assetRoot + entry.modelData.key + "-art.jpg" : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        opacity: entry.index === 0 ? 0.9 : 0.2
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 3 * root.unit
                        color: entry.modelData.owner === "You" ? "#78b8c5" : "#c78578"
                    }
                    Column {
                        x: 12 * root.unit
                        y: (entry.index === 0 ? 98 : 10) * root.unit
                        width: parent.width - 24 * root.unit
                        spacing: 5 * root.unit
                        Text {
                            textFormat: Text.PlainText
                            width: parent.width
                            text: entry.modelData.name
                            color: "#f0eee6"
                            font.pixelSize: 14 * root.unit
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: entry.modelData.owner + "  ·  " + entry.modelData.kind
                            color: "#a7b7c4"
                            font.pixelSize: 10 * root.unit
                        }
                        StudyButton {
                            objectName: "studyStackTarget-" + entry.modelData.id
                            visible: !!entry.modelData.targetId
                            width: parent.width
                            implicitHeight: 27 * root.unit
                            text: "↗ " + entry.modelData.targetName
                            quiet: true
                            unit: root.unit
                            onClicked: root.targetRequested(entry.modelData.targetId)
                        }
                        StudyLabel {
                            visible: !entry.modelData.targetId
                            width: parent.width
                            text: entry.modelData.description
                            pointSize: 10
                            wrapMode: Text.WordWrap
                            color: "#e4c58c"
                            unit: root.unit
                        }
                    }
                    Rectangle {
                        visible: entry.index === 0
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 7 * root.unit
                        width: 49 * root.unit
                        height: 21 * root.unit
                        radius: 4 * root.unit
                        color: "#e0be81"
                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: "NEXT"
                            color: "#1d2429"
                            font.pixelSize: 9 * root.unit
                            font.weight: Font.Bold
                        }
                    }
                    TapHandler { acceptedButtons: Qt.RightButton; onTapped: root.inspected(entry.modelData) }
                }
            }
        }
    }
}
