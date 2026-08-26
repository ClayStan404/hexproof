// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root

    readonly property var appWindow: ApplicationWindow.window
    readonly property var formatOptions: [
        {"label": I18n.formatLabel("custom"), "value": "custom", "tableMode": "modern"},
        {"label": I18n.formatLabel("standard"), "value": "standard", "tableMode": "modern"},
        {"label": I18n.formatLabel("pioneer"), "value": "pioneer", "tableMode": "modern"},
        {"label": I18n.formatLabel("modern"), "value": "modern", "tableMode": "modern"},
        {"label": I18n.formatLabel("legacy"), "value": "legacy", "tableMode": "modern"},
        {"label": I18n.formatLabel("vintage"), "value": "vintage", "tableMode": "modern"},
        {"label": I18n.formatLabel("pauper"), "value": "pauper", "tableMode": "modern"},
        {"label": I18n.formatLabel("duel"), "value": "duel", "tableMode": "duel"},
        {"label": I18n.formatLabel("commander"), "value": "commander", "tableMode": "edh"},
        {"label": I18n.formatLabel("cube"), "value": "cube", "tableMode": "modern"}
    ]
    readonly property bool isCubeFormat: root.deckFormat === "cube"
    readonly property var cubeDecks: {
        void deckLibrary.count
        void deckLibrary.currentDeckId
        return deckLibrary.matchDecks("cube", true)
    }
    readonly property var selectedCube: root.cubeById(root.selectedCubeDeckId,
                                                       root.cubeDecks)

    property bool playtestMode: false
    property string roomName: ""
    property string roomFormat: "modern"
    property string deckFormat: "custom"
    property bool allowSpectators: true
    property bool spectatorsSeeHands: false
    property string matchMode: "bo1"
    property string cardLoadMode: "preload"
    property string roomPassword: ""
    property string selectedCubeDeckId: ""

    background: AppBackground { }

    Component.onCompleted: root.ensureSelectedCube()

    ScreenHeader {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(22)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        title: root.playtestMode ? qsTr("Playtest") : qsTr("Create room")
        subtitle: root.playtestMode
                  ? qsTr("Practice alone on a full tabletop")
                  : qsTr("Set the table, then share its room code")
        onBackRequested: root.appWindow.popScreen()
    }

    ScrollView {
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(14)
        anchors.bottomMargin: Theme.size(24)
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Surface {
            width: Math.min(Theme.size(650), parent.width - Theme.size(72))
            height: form.implicitHeight + Theme.size(60)
            anchors.horizontalCenter: parent.horizontalCenter
            elevated: true

            ColumnLayout {
                id: form
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.size(30)
                spacing: Theme.size(10)

                RowLayout {
                    Layout.fillWidth: true

                    ColumnLayout {
                        spacing: Theme.size(3)
                        Text {
                            textFormat: Text.PlainText
                            text: root.playtestMode
                                  ? qsTr("Solo tabletop")
                                  : qsTr("New tabletop")
                            color: Theme.text
                            font.pixelSize: Theme.fontSize(26)
                            font.weight: Font.DemiBold
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: root.playtestMode
                                  ? qsTr("Choose a format, then select any ready deck.")
                                  : root.isCubeFormat
                                    ? qsTr("You will enter as organizer; register if you also want to draft.")
                                    : qsTr("You will enter as the host in seat one.")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSize(13)
                        }
                    }

                    Item { Layout.fillWidth: true }

                    StatusPill {
                        text: root.playtestMode
                              ? qsTr("One player")
                              : qsTr("Connected")
                        statusColor: Theme.success
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.topMargin: Theme.size(16)
                    visible: !root.playtestMode
                    text: qsTr("ROOM NAME")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                    font.weight: Font.Bold
                    font.letterSpacing: 1.1
                }

                AppTextField {
                    id: nameField
                    Layout.fillWidth: true
                    visible: !root.playtestMode
                    placeholderText: qsTr("Friday game night")
                    maximumLength: 80
                    text: root.roomName
                    onTextEdited: root.roomName = text
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    visible: !root.playtestMode
                    text: root.isCubeFormat
                          ? qsTr("The selected Cube is locked when the eight-player draft starts.")
                          : qsTr("Include the exact format in the room name so players know which card pool to bring.")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(10)
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.size(10)
                    spacing: Theme.size(20)

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.size(8)

                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("FORMAT")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(11)
                            font.weight: Font.Bold
                            font.letterSpacing: 1.1
                        }

                        AppComboBox {
                            id: formatSelector
                            Layout.fillWidth: true
                            model: root.playtestMode
                                   ? root.formatOptions.slice(0, 9)
                                   : root.formatOptions
                            textRole: "label"
                            valueRole: "value"
                            currentIndex: 0
                            onActivated: index => {
                                root.deckFormat = root.formatOptions[index].value
                                root.roomFormat = root.formatOptions[index].tableMode
                                if (root.roomFormat === "edh")
                                    root.matchMode = "bo1"
                                if (root.isCubeFormat)
                                    root.ensureSelectedCube()
                            }
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            visible: root.deckFormat === "custom"
                            text: qsTr("Custom 1v1 keeps manual deck construction and card-pool decisions.")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(10)
                            wrapMode: Text.WordWrap
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            visible: root.roomFormat === "duel"
                            text: qsTr("A two-player commander table at 20 life with command zones and manual commander tax.")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(10)
                            wrapMode: Text.WordWrap
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            visible: root.roomFormat === "edh"
                            text: qsTr("A four-seat Commander table that can start with three or four players.")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(10)
                            wrapMode: Text.WordWrap
                        }
                    }

                    ColumnLayout {
                        Layout.preferredWidth: Theme.size(170)
                        visible: !root.playtestMode
                        spacing: Theme.size(8)

                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("MATCH")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(11)
                            font.weight: Font.Bold
                            font.letterSpacing: 1.1
                        }

                        SegmentedControl {
                            Layout.fillWidth: true
                            options: root.roomFormat === "edh"
                                     ? [qsTr("BO 1")]
                                     : [qsTr("BO 1"),
                                        qsTr("BO 3")]
                            currentIndex: root.matchMode === "bo3" ? 1 : 0
                            onActivated: index => root.matchMode = index === 1 ? "bo3" : "bo1"
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            visible: root.roomFormat === "edh"
                            text: qsTr("Commander is a single multiplayer game.")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(10)
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Surface {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.size(8)
                    implicitHeight: cubeSelection.implicitHeight + Theme.size(28)
                    visible: root.isCubeFormat
                    color: Theme.surfaceMuted

                    ColumnLayout {
                        id: cubeSelection
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.size(14)
                        spacing: Theme.size(8)

                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("CUBE POOL")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(10)
                            font.weight: Font.Bold
                            font.letterSpacing: 1.0
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.size(8)

                            AppComboBox {
                                id: cubeSelector
                                Layout.fillWidth: true
                                model: root.cubeDecks
                                textRole: "deckName"
                                valueRole: "deckId"
                                onActivated: root.selectedCubeDeckId = currentValue
                            }

                            AppButton {
                                compact: true
                                variant: "ghost"
                                text: qsTr("Open deck library")
                                onClicked: root.appWindow.pushScreen(
                                               "screens/DeckLibrary.qml")
                            }
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: !root.selectedCube.deckId
                                  ? qsTr("Import a Cube-format deck before creating this room.")
                                  : qsTr("Eight players draft three 15-card packs, passing left, right, then left. This Cube contains %1 cards.")
                                    .arg(root.selectedCube.mainCount)
                            color: root.cubeReady() ? Theme.textMuted : Theme.warning
                            font.pixelSize: Theme.fontSize(10)
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                InfoBanner {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.size(8)
                    visible: root.playtestMode
                    tone: "success"
                    message: qsTr("Playtest uses one private seat with no opponent or spectators. Commander-free 1v1 and Duel Commander start at 20 life; commander formats include a command zone.")
                }

                Surface {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.size(12)
                    visible: !root.playtestMode && !root.isCubeFormat
                    implicitHeight: Theme.size(64)
                    radius: Theme.radiusMedium
                    color: Theme.surfaceMuted

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.size(16)
                        anchors.rightMargin: Theme.size(14)

                        ColumnLayout {
                            spacing: Theme.size(2)
                            Text {
                                textFormat: Text.PlainText
                                text: qsTr("Allow spectators")
                                color: Theme.text
                                font.pixelSize: Theme.fontSize(14)
                                font.weight: Font.Medium
                            }
                            Text {
                                textFormat: Text.PlainText
                                text: qsTr("Up to eight people can watch public information.")
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSize(11)
                            }
                        }

                        Item { Layout.fillWidth: true }

                        AppToggle {
                            checked: root.allowSpectators
                            onToggled: {
                                root.allowSpectators = checked
                                if (!checked)
                                    root.spectatorsSeeHands = false
                            }
                        }
                    }
                }

                Surface {
                    Layout.fillWidth: true
                    visible: !root.playtestMode && !root.isCubeFormat
                             && root.allowSpectators
                    implicitHeight: Theme.size(68)
                    radius: Theme.radiusMedium
                    color: Theme.surfaceMuted

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.size(16)
                        anchors.rightMargin: Theme.size(14)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.size(2)
                            Text {
                                textFormat: Text.PlainText
                                text: qsTr("Spectators can see hands")
                                color: Theme.text
                                font.pixelSize: Theme.fontSize(14)
                                font.weight: Font.Medium
                            }
                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: qsTr("All spectators can continuously inspect every player's hand. Players still cannot see each other's hands.")
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSize(11)
                                wrapMode: Text.WordWrap
                            }
                        }

                        AppToggle {
                            objectName: "spectatorsSeeHandsToggle"
                            checked: root.spectatorsSeeHands
                            onToggled: root.spectatorsSeeHands = checked
                        }
                    }
                }

                Surface {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.size(4)
                    visible: !root.isCubeFormat
                    implicitHeight: cardLoadingColumn.implicitHeight + Theme.size(28)
                    radius: Theme.radiusMedium
                    color: Theme.surfaceMuted

                    ColumnLayout {
                        id: cardLoadingColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.size(14)
                        spacing: Theme.size(8)

                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("CARD IMAGES")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(10)
                            font.weight: Font.Bold
                            font.letterSpacing: 1.0
                        }

                        SegmentedControl {
                            Layout.fillWidth: true
                            options: [qsTr("Preload before game"),
                                      qsTr("Load in background")]
                            currentIndex: root.cardLoadMode === "background" ? 1 : 0
                            onActivated: index => root.cardLoadMode =
                                                         index === 1 ? "background" : "preload"
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: root.cardLoadMode === "background"
                                  ? qsTr("Enter immediately. Visible cards load first while the rest download in the background.")
                                  : qsTr("Wait until every player has downloaded all match card images.")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(10)
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.topMargin: Theme.size(10)
                    visible: !root.playtestMode && !root.isCubeFormat
                    text: qsTr("ROOM PASSWORD · OPTIONAL")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                    font.weight: Font.Bold
                    font.letterSpacing: 1.1
                }

                AppTextField {
                    id: passwordField
                    Layout.fillWidth: true
                    visible: !root.playtestMode && !root.isCubeFormat
                    placeholderText: qsTr("Leave blank for code-only access")
                    echoMode: TextInput.Password
                    maximumLength: 72
                    maximumUtf8Bytes: 72
                    text: root.roomPassword
                    onTextEdited: root.roomPassword = text
                    onAccepted: root.submit()
                }

                InfoBanner {
                    id: errorBanner
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.size(4)
                }

                Text {
                    textFormat: Text.PlainText
                    objectName: "createRoomBlockerText"
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.createBlockerReason()
                    color: Theme.warning
                    font.pixelSize: Theme.fontSize(12)
                    horizontalAlignment: Text.AlignRight
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.size(12)
                    spacing: Theme.size(10)

                    AppButton {
                        variant: "ghost"
                        text: qsTr("Cancel")
                        onClicked: root.appWindow.popScreen()
                    }

                    Item { Layout.fillWidth: true }

                    AppButton {
                        variant: "primary"
                        text: root.playtestMode
                              ? qsTr("Create playtest")
                              : qsTr("Create room")
                        leadingText: root.playtestMode ? "▶" : "+"
                        enabled: root.playtestMode
                                 || root.createBlockerReason().length === 0
                        disabledReason: root.createBlockerReason()
                        onClicked: root.submit()
                    }
                }
            }
        }
    }

    function submit() {
        if (!playtestMode && roomName.trim().length === 0)
            return
        if (!playtestMode && !passwordField.withinUtf8ByteLimit) {
            errorBanner.message =
                qsTr("Password cannot exceed 72 UTF-8 bytes.")
            return
        }
        errorBanner.message = ""
        const submittedName = playtestMode
                              ? qsTr("Solo playtest")
                              : roomName.trim()
        if (root.isCubeFormat) {
            const product = deckLibrary.cubeProduct(
                                root.selectedCubeDeckId)
            if (!product.id)
                return
            ws.createCasualLimitedEvent(
                        submittedName, "cube_draft", matchMode, 8,
                        product)
            return
        }
        ws.createRoom(submittedName, roomFormat, deckFormat,
                      playtestMode ? false : allowSpectators,
                      playtestMode ? false : spectatorsSeeHands,
                      playtestMode ? "bo1" : matchMode,
                      cardLoadMode,
                      playtestMode ? "" : roomPassword,
                      playtestMode)
    }

    function createBlockerReason() {
        if (root.playtestMode)
            return ""
        if (root.roomName.trim().length === 0)
            return qsTr("Enter a room name")
        if (root.isCubeFormat && !root.selectedCube.deckId)
            return qsTr("Import and select a Cube-format deck")
        if (root.isCubeFormat && !root.selectedCube.exactPrintings)
            return qsTr("Every Cube card needs an exact printing")
        if (root.isCubeFormat && Number(root.selectedCube.mainCount) < 360)
            return qsTr("An eight-player Cube draft needs at least 360 cards")
        if (root.isCubeFormat && Number(root.selectedCube.sideboardCount) > 0)
            return qsTr("Move every Cube card into the main pool")
        if (!passwordField.withinUtf8ByteLimit)
            return qsTr("Password cannot exceed 72 UTF-8 bytes.")
        return ""
    }

    function cubeById(cubeId, cubes) {
        for (let index = 0; index < cubes.length; ++index) {
            if (cubes[index].deckId === cubeId)
                return cubes[index]
        }
        return ({})
    }

    function ensureSelectedCube() {
        if (!root.cubeById(root.selectedCubeDeckId, root.cubeDecks).deckId)
            root.selectedCubeDeckId = root.cubeDecks.length > 0
                                      ? root.cubeDecks[0].deckId : ""
        if (cubeSelector.currentValue !== root.selectedCubeDeckId) {
            for (let index = 0; index < root.cubeDecks.length; ++index) {
                if (root.cubeDecks[index].deckId
                        === root.selectedCubeDeckId) {
                    cubeSelector.currentIndex = index
                    break
                }
            }
        }
    }

    function cubeReady() {
        return root.selectedCube.ready === true
    }

    Connections {
        target: deckLibrary
        function onCountChanged() { root.ensureSelectedCube() }
        function onCurrentDeckChanged() { root.ensureSelectedCube() }
    }

    Connections {
        target: ws
        function onLastErrorChanged() {
            if (!ws.inRoom)
                errorBanner.message = I18n.status(ws.lastError)
        }
    }
}
