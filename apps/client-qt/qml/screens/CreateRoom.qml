// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root
    objectName: "createRoomPage"

    readonly property bool wideLayout: width >= Theme.size(1000)
    readonly property var appWindow: ApplicationWindow.window
    readonly property var formatOptions: I18n.deckFormatOptions()
    readonly property var selectableFormatOptions:
        root.playtestMode
        ? root.formatOptions.filter(option => option.value !== "cube")
        : root.formatOptions
    readonly property bool isCubeFormat: root.deckFormat === "cube"
    property var wsModel
    property var deckLibraryModel
    readonly property var hub: wsModel ? wsModel : ws
    readonly property var decks: deckLibraryModel ? deckLibraryModel : deckLibrary
    readonly property var cubeDecks: {
        void root.decks.count
        void root.decks.currentDeckId
        return root.decks.matchDecks("cube", true)
    }
    readonly property var selectedCube: root.cubeById(root.selectedCubeDeckId,
                                                       root.cubeDecks)

    property bool playtestMode: false
    property string roomName: ""
    property string roomFormat: "modern"
    property string deckFormat: "modern"
    property bool allowSpectators: true
    property bool spectatorsSeeHands: false
    property string matchMode: "bo1"
    property string cardLoadMode: "preload"
    property string rulesMode: "manual"
    property string roomPassword: ""
    property string selectedCubeDeckId: ""
    property bool commanderCube: false
    property int commanderPackCount: 6
    property bool commanderDoublePacks: true
    readonly property var commanderPackOptions: [3, 4, 5, 6, 8]

    onCommanderCubeChanged: if (commanderCube && cubePlayerCap() > 4) cubePlayerCapField.text = "4"

    background: AppBackground { }

    Component.onCompleted: {
        root.ensureSelectedCube()
    }

    ScreenHeader {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(22)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        title: root.playtestMode ? qsTr("Playtest")
               : root.isCubeFormat ? (root.commanderCube ? qsTr("Create Commander Cube room") : qsTr("Create Cube room"))
               : qsTr("Create room")
        subtitle: root.playtestMode
                  ? qsTr("Practice alone on a full tabletop")
                  : root.isCubeFormat
                    ? qsTr("Draft the Cube, build decks, then play together")
                  : qsTr("Set the table, then share its room code")
        onBackRequested: root.appWindow.popScreen()
    }

    Flickable {
        id: formBody
        objectName: "createRoomBody"
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(14)
        anchors.bottomMargin: Theme.size(24)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: Math.max(height, formCard.height)
        ScrollBar.vertical: ScrollBar {
            policy: formBody.contentHeight > formBody.height
                    ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        }

        Surface {
            id: formCard
            objectName: "createRoomCard"
            width: Math.min(Theme.size(1120), formBody.width - 2 * Theme.pageMargin)
            implicitHeight: form.implicitHeight + Theme.size(48)
            height: implicitHeight
            x: Math.max(0, Math.round((formBody.width - width) / 2))
            elevated: true

            ColumnLayout {
                id: form
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.size(24)
                spacing: Theme.size(10)

                GridLayout {
                    objectName: "createRoomColumns"
                    Layout.fillWidth: true
                    columns: root.wideLayout ? 2 : 1
                    columnSpacing: Theme.size(28)
                    rowSpacing: Theme.size(16)
                    uniformCellWidths: true

                    ColumnLayout {
                        objectName: "createRoomDetails"
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: Theme.size(12)

                        Text {
                            textFormat: Text.PlainText
                            visible: !root.playtestMode
                            text: qsTr("ROOM NAME")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(11)
                            font.weight: Font.Bold
                            font.letterSpacing: 1.1
                        }

                        AppTextField {
                            id: nameField
                            objectName: "roomNameField"
                            Layout.fillWidth: true
                            visible: !root.playtestMode
                            maximumLength: 80
                            text: root.roomName
                            onTextEdited: root.roomName = text
                        }

                        RowLayout {
                            Layout.fillWidth: true
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
                                    objectName: "roomFormatSelector"
                                    Layout.fillWidth: true
                                    model: root.selectableFormatOptions
                                    textRole: "label"
                                    valueRole: "value"
                                    currentIndex: 0
                                    onActivated: index => {
                                        const option = root.selectableFormatOptions[index]
                                        root.deckFormat = option.value
                                        root.roomFormat = option.tableMode
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
                                    objectName: "roomMatchModeControl"
                                    Layout.fillWidth: true
                                    options: root.roomFormat === "edh" || (root.isCubeFormat && root.commanderCube)
                                             ? [qsTr("BO 1")]
                                             : [qsTr("BO 1"),
                                                qsTr("BO 3")]
                                    currentIndex: root.isCubeFormat && root.commanderCube ? 0 : root.matchMode === "bo3" ? 1 : 0
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
                            visible: !root.playtestMode && !root.isCubeFormat
                            implicitHeight: rulesModeColumn.implicitHeight + Theme.size(28)
                            radius: Theme.radiusMedium
                            color: Theme.surfaceMuted

                            ColumnLayout {
                                id: rulesModeColumn
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Theme.size(14)
                                spacing: Theme.size(8)

                                Text {
                                    textFormat: Text.PlainText
                                    text: qsTr("GAMEPLAY RULES")
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fontSize(10)
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.0
                                }

                                SegmentedControl {
                                    Layout.fillWidth: true
                                    options: [qsTr("Manual tabletop"),
                                              qsTr("Forge rules")]
                                    currentIndex: root.rulesMode === "forge" ? 1 : 0
                                    onActivated: index => {
                                        root.rulesMode = index === 1 ? "forge" : "manual"
                                    }
                                }

                                Text {
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: root.rulesMode === "forge"
                                          ? (root.hub.forgeRulesAvailable
                                             ? qsTr("Forge validates legal actions, priority, the stack, triggers, combat, and state-based actions. Two-player rooms support BO1 and BO3.")
                                             : qsTr("This server does not provide the Forge rules runtime."))
                                          : qsTr("Players control every move and resolve unusual interactions together.")
                                    color: root.rulesMode === "forge" && !root.hub.forgeRulesAvailable
                                           ? Theme.warning : Theme.textMuted
                                    font.pixelSize: Theme.fontSize(10)
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        objectName: "createRoomOptions"
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: Theme.size(12)

                        SegmentedControl {
                            objectName: "cubeVariantControl"
                            Layout.fillWidth: true
                            visible: root.isCubeFormat
                            options: [qsTr("Regular Cube"), qsTr("Commander Cube")]
                            currentIndex: root.commanderCube ? 1 : 0
                            onActivated: index => {
                                root.commanderCube = index === 1
                                if (root.commanderCube) root.matchMode = "bo1"
                            }
                        }

                        Surface {
                            Layout.fillWidth: true
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

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.size(8)

                                    Text {
                                        textFormat: Text.PlainText
                                        Layout.fillWidth: true
                                        text: qsTr("PLAYER CAP")
                                        color: Theme.textMuted
                                        font.pixelSize: Theme.fontSize(10)
                                        font.weight: Font.Bold
                                    }

                                    AppTextField {
                                        id: cubePlayerCapField
                                        objectName: "cubePlayerCapField"
                                        Layout.preferredWidth: Theme.size(110)
                                        text: "8"
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        validator: IntValidator { bottom: 2; top: 8 }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: root.commanderCube && root.cubePlayerCap() <= 4
                                    Text {
                                        textFormat: Text.PlainText
                                        Layout.fillWidth: true
                                        text: qsTr("Packs per player")
                                        color: Theme.textSecondary
                                        font.pixelSize: Theme.fontSize(13)
                                    }
                                    AppComboBox {
                                        objectName: "commanderPackCountSelector"
                                        Layout.preferredWidth: Theme.size(160)
                                        model: root.commanderPackOptions.map(count => count === 6
                                            ? qsTr("%1 (recommended)").arg(count) : String(count))
                                        currentIndex: root.commanderPackOptions.indexOf(root.commanderPackCount)
                                        enabledForIndex: index => Number(root.selectedCube.mainCount || 0)
                                            >= root.cubePlayerCap() * root.commanderPackOptions[index] * root.commanderCardsPerPack()
                                        onActivated: {
                                            if (enabledForIndex(currentIndex))
                                                root.commanderPackCount = root.commanderPackOptions[currentIndex]
                                            else currentIndex = root.commanderPackOptions.indexOf(root.commanderPackCount)
                                        }
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: root.commanderCube
                                    Text {
                                        textFormat: Text.PlainText
                                        Layout.fillWidth: true
                                        text: qsTr("Cards per pack (10–40)")
                                        color: Theme.textSecondary
                                        font.pixelSize: Theme.fontSize(13)
                                    }
                                    AppTextField {
                                        id: commanderCardsPerPackField
                                        objectName: "commanderCardsPerPackField"
                                        Layout.preferredWidth: Theme.size(110)
                                        text: "20"
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        validator: IntValidator { bottom: 10; top: 40 }
                                        Accessible.name: qsTr("Cards per pack (10–40)")
                                    }
                                }
                                AppToggle {
                                    objectName: "commanderDoublePacksCheckBox"
                                    Layout.fillWidth: true
                                    visible: root.commanderCube && root.cubePlayerCap() <= 4
                                    text: qsTr("Open two packs together; choose two cards from each")
                                    checked: root.commanderDoublePacks
                                    onClicked: root.commanderDoublePacks = checked
                                }

                                Text {
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: !root.selectedCube.deckId
                                          ? qsTr("Import a Cube-format deck before creating this room.")
                                          : (root.commanderCube
                                             ? qsTr("Each player drafts %4 packs of %6 cards and keeps %5 cards. Build at least 60 cards including commanders. Submitted players enter balanced tables of up to four. A %1-seat room needs %2 Cube cards; this Cube contains %3.")
                                             : qsTr("Start when everyone is ready (at least two players). Each player drafts three 15-card packs. A %1-seat room needs %2 Cube cards; this Cube contains %3."))
                                            .arg(root.cubePlayerCap())
                                            .arg(root.cubeCardsRequired())
                                            .arg(root.selectedCube.mainCount)
                                            .replace("%4", root.cubeDraftSettings().packsPerPlayer)
                                            .replace("%5", root.cubeDraftSettings().packsPerPlayer * root.commanderCardsPerPack())
                                            .replace("%6", root.commanderCardsPerPack())
                                    color: root.cubeReady() ? Theme.textMuted : Theme.warning
                                    font.pixelSize: Theme.fontSize(10)
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        InfoBanner {
                            Layout.fillWidth: true
                            visible: root.playtestMode
                            tone: "success"
                            message: qsTr("Playtest uses one private seat with no opponent or spectators. Commander-free 1v1 and Duel Commander start at 20 life; commander formats include a command zone.")
                        }

                        Surface {
                            Layout.fillWidth: true
                            visible: !root.playtestMode && !root.isCubeFormat
                            implicitHeight: Theme.size(52)
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
                                }

                                Item { Layout.fillWidth: true }

                                AppToggle {
                                    objectName: "allowSpectatorsToggle"
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
                            implicitHeight: Theme.size(52)
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
                                        text: qsTr("Spectators can see hands")
                                        color: Theme.text
                                        font.pixelSize: Theme.fontSize(14)
                                        font.weight: Font.Medium
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                AppToggle {
                                    objectName: "spectatorsSeeHandsToggle"
                                    checked: root.spectatorsSeeHands
                                    onToggled: root.spectatorsSeeHands = checked
                                }
                            }
                        }

                        Surface {
                            Layout.fillWidth: true
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
                            visible: !root.playtestMode && !root.isCubeFormat
                            text: qsTr("ROOM PASSWORD · OPTIONAL")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(11)
                            font.weight: Font.Bold
                            font.letterSpacing: 1.1
                        }

                        AppTextField {
                            id: passwordField
                            objectName: "roomPasswordField"
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

                    }
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
                        objectName: "createRoomSubmitButton"
                        variant: "primary"
                        text: root.playtestMode ? qsTr("Create playtest")
                              : root.isCubeFormat
                                ? (root.commanderCube ? qsTr("Create Commander Cube room") : qsTr("Create Cube room"))
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
        if (!playtestMode && !root.isCubeFormat && !passwordField.withinUtf8ByteLimit) {
            errorBanner.message =
                qsTr("Password cannot exceed 72 UTF-8 bytes.")
            return
        }
        errorBanner.message = ""
        const submittedName = playtestMode
                              ? qsTr("Solo playtest")
                              : roomName.trim()
        if (root.isCubeFormat) {
            const product = root.decks.cubeProduct(
                                root.selectedCubeDeckId)
            if (!product.id)
                return
            if (root.commanderCube)
                root.hub.createCasualLimitedEvent(submittedName, "commander_cube", "bo1",
                    root.cubePlayerCap(), product, root.cubeDraftSettings())
            else
                root.hub.createCasualLimitedEvent(submittedName, "cube_draft", matchMode,
                    root.cubePlayerCap(), product)
            return
        }
        const submittedMatchMode = root.roomFormat === "edh" ? "bo1" : matchMode
        root.hub.createRoom(submittedName, roomFormat, deckFormat,
                      playtestMode ? false : allowSpectators,
                      playtestMode ? false : spectatorsSeeHands,
                      playtestMode ? "bo1" : submittedMatchMode,
                      cardLoadMode,
                      playtestMode ? "" : roomPassword,
                      playtestMode,
                      playtestMode ? "manual" : rulesMode)
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
        if (root.isCubeFormat && !cubePlayerCapField.acceptableInput)
            return root.commanderCube ? qsTr("Choose a Commander Cube player cap from 2 to 8")
                                      : qsTr("Choose a Cube player cap from 2 to 8")
        if (root.isCubeFormat && root.commanderCube && !commanderCardsPerPackField.acceptableInput)
            return qsTr("Choose 10 to 40 cards per pack")
        if (root.isCubeFormat
                && Number(root.selectedCube.mainCount) < root.cubeCardsRequired())
            return qsTr("A %1-player Cube draft needs at least %2 cards")
                .arg(root.cubePlayerCap()).arg(root.cubeCardsRequired())
        if (root.isCubeFormat && Number(root.selectedCube.sideboardCount) > 0)
            return qsTr("Move every Cube card into the main pool")
        if (!root.isCubeFormat && root.rulesMode === "forge" && !root.hub.forgeRulesAvailable)
            return qsTr("Forge rules are unavailable on this server")
        if (!root.isCubeFormat && !passwordField.withinUtf8ByteLimit)
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

    function cubePlayerCap() {
        return cubePlayerCapField.numberValue()
    }

    function cubeDraftSettings() {
        return root.cubePlayerCap() > 4
            ? {packsPerPlayer: 3, packsPerBatch: 1, cardsPerPack: root.commanderCardsPerPack()}
            : {packsPerPlayer: root.commanderPackCount, packsPerBatch: root.commanderDoublePacks ? 2 : 1,
               cardsPerPack: root.commanderCardsPerPack()}
    }

    function commanderCardsPerPack() {
        return commanderCardsPerPackField.acceptableInput ? commanderCardsPerPackField.numberValue() : 20
    }

    function cubeCardsRequired() {
        return root.cubePlayerCap() * (root.commanderCube
            ? root.cubeDraftSettings().packsPerPlayer * root.commanderCardsPerPack() : 45)
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
                && cubePlayerCapField.acceptableInput
                && (!root.commanderCube || commanderCardsPerPackField.acceptableInput)
                && Number(root.selectedCube.mainCount)
                   >= root.cubeCardsRequired()
    }

    Connections {
        target: root.decks
        function onCountChanged() { root.ensureSelectedCube() }
        function onCurrentDeckChanged() { root.ensureSelectedCube() }
    }

    Connections {
        target: root.hub
        function onLastErrorChanged() {
            if (!root.hub.inRoom)
                errorBanner.message = I18n.status(root.hub.lastError)
        }
    }
}
