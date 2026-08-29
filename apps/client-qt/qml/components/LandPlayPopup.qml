// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    property var cardCatalogModel: null
    property var card: ({})
    property var faces: []
    property int recordedCount: 0
    property string phase: ""
    property int stackCount: 0
    signal playRequested(string faceName)

    readonly property var selectedFace:
        faces.length > 0 && facePicker.currentIndex >= 0
        ? faces[facePicker.currentIndex] : ({})
    readonly property string selectedFaceName:
        selectedFace.faceName ? selectedFace.faceName : ""
    readonly property string selectedTypeLine:
        selectedFace.typeLine ? selectedFace.typeLine : ""
    readonly property bool canCommit: recordedCount < 2147483647
    readonly property var warnings: {
        const result = []
        if (!canCommit) {
            result.push(qsTr("The recorded count has reached its storage limit."))
        }
        if (recordedCount > 0) {
            result.push(qsTr("A land play is already recorded for this turn."))
        }
        if (phase !== "main_1" && phase !== "main_2") {
            result.push(qsTr("The current phase is not a main phase."))
        }
        if (stackCount > 0)
            result.push(qsTr("The stack is not empty."))
        const type = selectedTypeLine.toLocaleLowerCase()
        if (!type.includes("land") && !type.includes("地")) {
            result.push(qsTr("The selected face is not identified as a land."))
        }
        return result
    }

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(600), parent.width - Theme.size(48))
    height: Math.min(contentColumn.implicitHeight + padding * 2,
                     parent.height - Theme.size(48))
    padding: Theme.size(22)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    Overlay.modal: Rectangle { color: "#A6050B09" }

    background: Rectangle {
        color: Theme.surfaceElevated
        radius: Theme.radiusLarge
        border.width: 1
        border.color: Theme.borderStrong
    }

    function faceImageRequests(candidate, availableFaces) {
        if (!candidate || !candidate.name)
            return []
        const result = []
        const values = availableFaces ? availableFaces : []
        for (let index = 0; index < values.length; ++index) {
            const face = values[index]
            result.push({
                "name": face.faceName ? face.faceName : candidate.name,
                "setCode": candidate.setCode ? candidate.setCode : "",
                "collectorNumber": candidate.collectorNumber
                                   ? candidate.collectorNumber : ""
            })
        }
        if (result.length === 0) {
            result.push({
                "name": candidate.name,
                "setCode": candidate.setCode ? candidate.setCode : "",
                "collectorNumber": candidate.collectorNumber
                                   ? candidate.collectorNumber : ""
            })
        }
        return result
    }

    function prioritizeFaceImages(candidate, availableFaces) {
        if (!cardCatalogModel)
            return
        const requests = faceImageRequests(candidate, availableFaces)
        if (typeof cardCatalogModel.prioritizeCards === "function") {
            cardCatalogModel.prioritizeCards(requests)
        } else if (typeof cardCatalogModel.cacheCards === "function") {
            cardCatalogModel.cacheCards(requests)
        }
    }

    function showFor(candidate, availableFaces, count, currentPhase,
                     currentStackCount) {
        card = candidate ? candidate : ({})
        faces = availableFaces ? availableFaces : []
        recordedCount = Math.max(0, count)
        phase = currentPhase ? currentPhase : ""
        stackCount = Math.max(0, currentStackCount)
        facePicker.currentIndex = 0
        prioritizeFaceImages(card, faces)
        open()
    }

    contentItem: ColumnLayout {
        id: contentColumn
        spacing: Theme.size(16)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(10)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(3)

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Record land play")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(20)
                    font.weight: Font.DemiBold
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: root.card.name ? root.card.name : ""
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(11)
                    elide: Text.ElideRight
                }
            }

            AppButton {
                compact: true
                variant: "ghost"
                text: "×"
                accessibleName: qsTr("Close")
                Layout.preferredWidth: Theme.size(40)
                onClicked: root.close()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(18)

            Surface {
                Layout.preferredWidth: Theme.size(126)
                Layout.preferredHeight: Theme.size(176)
                color: Theme.surfaceMuted

                Image {
                    anchors.fill: parent
                    anchors.margins: Theme.size(5)
                    source: root.cardCatalogModel
                            && (root.cardCatalogModel.imageRevision
                                === undefined
                                || root.cardCatalogModel.imageRevision >= 0)
                            && root.card.name
                            ? root.cardCatalogModel.imageSource(
                                  root.selectedFaceName.length > 0
                                  ? root.selectedFaceName : root.card.name,
                                  root.card.setCode ? root.card.setCode : "",
                                  root.card.collectorNumber
                                  ? root.card.collectorNumber : "")
                            : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(10)

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Recorded this turn: %1").arg(root.recordedCount)
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(13)
                    font.weight: Font.DemiBold
                }

                AppComboBox {
                    id: facePicker
                    objectName: "landPlayFacePicker"
                    Layout.fillWidth: true
                    visible: root.faces.length > 1
                    model: root.faces
                    textRole: "displayName"
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: root.selectedTypeLine
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(11)
                    wrapMode: Text.Wrap
                }

                Surface {
                    Layout.fillWidth: true
                    visible: root.warnings.length > 0
                    implicitHeight: warningColumn.implicitHeight + Theme.size(20)
                    color: Qt.rgba(Theme.warning.r, Theme.warning.g,
                                   Theme.warning.b, 0.14)
                    border.color: Theme.warning

                    ColumnLayout {
                        id: warningColumn
                        anchors.fill: parent
                        anchors.margins: Theme.size(10)
                        spacing: Theme.size(5)

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: qsTr("Check before continuing")
                            color: Theme.warning
                            font.pixelSize: Theme.fontSize(11)
                            font.weight: Font.DemiBold
                        }

                        Repeater {
                            model: root.warnings

                            delegate: Text {
                                textFormat: Text.PlainText
                                required property string modelData
                                Layout.fillWidth: true
                                text: "• " + modelData
                                color: Theme.text
                                font.pixelSize: Theme.fontSize(10)
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }
            }
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: qsTr("This helper records the move and count only; it does not enforce card rules.")
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize(10)
            wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(10)

            Item { Layout.fillWidth: true }

            AppButton {
                text: qsTr("Cancel")
                onClicked: root.close()
            }
            AppButton {
                objectName: "confirmLandPlayButton"
                variant: "primary"
                text: qsTr("Play land")
                enabled: root.canCommit
                onClicked: {
                    root.playRequested(root.selectedFaceName)
                    root.close()
                }
            }
        }
    }
}
