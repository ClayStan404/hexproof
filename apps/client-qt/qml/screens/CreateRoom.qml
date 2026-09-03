// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root

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
        title: root.playtestMode ? qsTr("Playtest")
               : root.isCubeFormat ? qsTr("Create Cube tournament")
               : qsTr("Create room")
        subtitle: root.playtestMode
                  ? qsTr("Practice alone on a full tabletop")
                  : root.isCubeFormat
                    ? qsTr("Draft the Cube, build decks, then play Swiss rounds with standings")
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
            width: Math.min(Theme.size(650), formBody.width - Theme.size(72))
            implicitHeight: form.implicitHeight + Theme.size(60)
            height: implicitHeight
            x: Math.max(0, Math.round((formBody.width - width) / 2))
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
                    text: root.isCubeFormat ? qsTr("EVENT NAME")
                                            : qsTr("ROOM NAME")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                    font.weight: Font.Bold
                    font.letterSpacing: 1.1
                }

                AppTextField {
                    id: nameField
                    Layout.fillWidth: true
                    visible: !root.playtestMode
                    placeholderText: root.isCubeFormat
                                     ? qsTr("Friday Cube Draft")
                                     : qsTr("Friday game night")
                    maximumLength: 80
                    text: root.roomName
                    onTextEdited: root.roomName = text
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    visible: !root.playtestMode
                    text: root.isCubeFormat
                          ? qsTr("The selected Cube is locked when the draft starts.")
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
                            Layout.fillWidth: true
                            options: root.roomFormat === "edh"
                                     || root.rulesMode === "forge"
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
                                if (root.rulesMode === "forge")
                                    root.matchMode = "bo1"
                            }
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: root.rulesMode === "forge"
                                  ? (root.hub.forgeRulesAvailable
                                     ? qsTr("Forge validates legal actions, priority, the stack, triggers, combat, and state-based actions. The current preview supports BO1 only.")
                                     : qsTr("This server does not provide the Forge rules runtime."))
                                  : qsTr("Players control every move and resolve unusual interactions together.")
                            color: root.rulesMode === "forge" && !root.hub.forgeRulesAvailable
                                   ? Theme.warning : Theme.textMuted
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

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: !root.selectedCube.deckId
                                  ? qsTr("Import a Cube-format deck before creating this room.")
                                  : qsTr("A Cube draft starts with at least two checked-in players. Each player drafts three 15-card packs, passing left, right, then left. A full %1-player lobby needs %2 cards; this Cube contains %3.")
                                    .arg(root.cubePlayerCap())
                                    .arg(root.cubeCardsRequired())
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
                        objectName: "createRoomSubmitButton"
                        variant: "primary"
                        text: root.playtestMode ? qsTr("Create playtest")
                              : root.isCubeFormat
                                ? qsTr("Create Cube tournament")
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
            const product = root.decks.cubeProduct(
                                root.selectedCubeDeckId)
            if (!product.id)
                return
            root.hub.createLimitedTournament(
                        submittedName, "cube_draft", matchMode,
                        50, root.cubePlayerCap(), 0, product)
            return
        }
        const submittedMatchMode = root.rulesMode === "forge"
                                   ? "bo1" : matchMode
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
            return qsTr("Choose a Cube player cap from 2 to 8")
        if (root.isCubeFormat
                && Number(root.selectedCube.mainCount) < root.cubeCardsRequired())
            return qsTr("A %1-player Cube draft needs at least %2 cards")
                .arg(root.cubePlayerCap()).arg(root.cubeCardsRequired())
        if (root.isCubeFormat && Number(root.selectedCube.sideboardCount) > 0)
            return qsTr("Move every Cube card into the main pool")
        if (root.rulesMode === "forge" && !root.hub.forgeRulesAvailable)
            return qsTr("Forge rules are unavailable on this server")
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

    function cubePlayerCap() {
        return Number(cubePlayerCapField.text)
    }

    function cubeCardsRequired() {
        return root.cubePlayerCap() * 3 * 15
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
