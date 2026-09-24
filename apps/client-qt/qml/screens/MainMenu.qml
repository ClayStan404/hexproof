// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root

    readonly property var appWindow: ApplicationWindow.window
    readonly property bool compactLayout: Theme.isCompactWidth(width)
    readonly property bool suppressStartupNotices: typeof localTestMode !== "undefined"
                                                   && localTestMode

    background: AppBackground {
        variant: TableBackgrounds.hasImage ? "playmat" : "menu"
    }

    Component.onCompleted: Qt.callLater(function() {
        if (root.suppressStartupNotices)
            return
        root.considerStartupNotices()
    })

    Item {
        id: topBar
        objectName: "mainMenuTopBar"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(26)
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        readonly property real spacing: Theme.size(12)
        readonly property real actionsWidth: {
            let total = 0
            let count = 0
            for (const child of headerActions.children) {
                if (!child.visible)
                    continue
                total += child.implicitWidth
                count += 1
            }
            return total + Math.max(0, count - 1) * spacing
        }
        readonly property bool inlineActions: brand.implicitWidth + spacing + actionsWidth <= width
        height: inlineActions ? Math.max(brand.implicitHeight, headerActions.implicitHeight)
                              : brand.implicitHeight + spacing + headerActions.implicitHeight

        RowLayout {
            id: brand
            objectName: "mainMenuBrand"
            anchors.left: parent.left
            y: topBar.inlineActions ? (topBar.height - height) / 2 : 0
            spacing: Theme.size(12)
            BrandMark { markSize: Theme.size(36) }

            Text {
                textFormat: Text.PlainText
                text: "HEXPROOF"
                color: Theme.text
                font.pixelSize: Theme.fontSize(14)
                font.weight: Font.Bold
                font.letterSpacing: 2.2
            }
        }

        Flow {
            id: headerActions
            objectName: "mainMenuHeaderActions"
            anchors.right: parent.right
            y: topBar.inlineActions ? (topBar.height - height) / 2
                                    : brand.height + topBar.spacing
            width: Math.min(topBar.width, topBar.actionsWidth)
            spacing: topBar.spacing
            layoutDirection: Qt.RightToLeft

            // Start with the trailing control so every wrapped row stays
            // attached to the right edge, including the connection status.
            AppButton {
                objectName: "mainMenuDisconnectButton"
                visible: ws.connected
                variant: "ghost"
                compact: true
                text: qsTr("Disconnect")
                onClicked: ws.disconnectFromHub()
            }

            StatusPill {
                objectName: "connectedServerStatus"
                visible: ws.connected
                text: root.connectedServerLabel()
                      + (I18n.serverTransportLabel(ws.serverTransportState).length > 0
                         ? " · " + I18n.serverTransportLabel(ws.serverTransportState) : "")
                statusColor: Theme.accent
                maximumWidth: topBar.width
            }

            StatusPill {
                objectName: "connectedPlayerStatus"
                text: ws.connected ? ws.displayName : qsTr("Offline")
                statusColor: ws.connected ? Theme.success : Theme.textMuted
                maximumWidth: Math.min(Theme.size(220), topBar.width)
                ToolTip.visible: playerStatusHover.hovered
                ToolTip.text: text
                ToolTip.delay: 350
                HoverHandler { id: playerStatusHover }
            }

            AppButton {
                objectName: "mainMenuSettingsButton"
                variant: "ghost"
                compact: true
                text: qsTr("Settings")
                onClicked: root.appWindow.pushScreen("screens/Settings.qml")
            }

            AppButton {
                objectName: "mainMenuUpdateButton"
                visible: appUpdater.updateAvailable
                variant: "secondary"
                compact: true
                text: qsTr("Update %1 available").arg(appUpdater.targetVersion)
                onClicked: root.appWindow.pushScreen("screens/UpdatesSettings.qml")
            }
        }
    }

    function connectedServerLabel() {
        const index = ws.serverIndex
        const entries = ws.serverEntries
        if (index < 0 || index >= entries.length || entries[index].id === "custom")
            return qsTr("Custom server")
        const name = String(entries[index].name || "")
        const numbered = /^Server ([0-9]+)$/.exec(name)
        return numbered ? qsTr("Server %1").arg(numbered[1]) : name
    }

    Flickable {
        id: menuBody
        objectName: "mainMenuBody"
        anchors.top: topBar.bottom
        anchors.bottom: footer.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.size(root.compactLayout ? 12 : 22)
        anchors.bottomMargin: Theme.size(18)
        anchors.leftMargin: root.compactLayout
                            ? Theme.pageMargin
                            : Math.max(Theme.size(48), root.width * 0.085)
        anchors.rightMargin: root.compactLayout
                             ? Theme.pageMargin
                             : Math.max(Theme.size(48), root.width * 0.085)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: menuLayoutWrap.height

        ScrollBar.vertical: ScrollBar {
            policy: menuBody.contentHeight > menuBody.height
                    ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        }

        Item {
            id: menuLayoutWrap
            width: menuBody.width
            height: Math.max(menuBody.height, menuLayout.implicitHeight)

            GridLayout {
                id: menuLayout
                objectName: "mainMenuLayout"
                anchors.fill: parent
                columns: root.compactLayout ? 1 : 2
                columnSpacing: Math.max(Theme.size(24), root.compactLayout ? 0 : root.width * 0.08)
                rowSpacing: Theme.size(18)

            ColumnLayout {
                objectName: "mainMenuHero"
                visible: !root.compactLayout
                Layout.fillWidth: true
                Layout.fillHeight: !root.compactLayout
                Layout.maximumWidth: root.compactLayout ? menuBody.width
                                                        : Theme.size(600)
                spacing: 0

                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Native desktop")
                    color: Theme.primary
                    font.pixelSize: Theme.fontSize(12)
                    font.weight: Font.DemiBold
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.size(root.compactLayout ? 10 : 18)
                    text: qsTr("Play Magic,\nyour way.")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(
                        root.compactLayout
                        ? Math.min(42, Math.max(32, root.width * 0.06))
                        : Math.min(64, Math.max(46, root.width * 0.052)))
                    font.weight: Font.DemiBold
                    font.letterSpacing: -1.8
                    lineHeight: 0.95
                    wrapMode: Text.WordWrap
                }

                Flow {
                    objectName: "mainMenuHeroCapabilities"
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.size(32)
                    spacing: Theme.size(28)

                    Column {
                        spacing: Theme.size(4)
                        Text {
                            objectName: "mainMenuHeroManualTitle"
                            textFormat: Text.PlainText
                            text: qsTr("Manual")
                            color: Theme.accent
                            font.pixelSize: Theme.fontSize(20)
                            font.weight: Font.DemiBold
                        }
                    }

                    Column {
                        spacing: Theme.size(4)
                        Text {
                            objectName: "mainMenuHeroForgeTitle"
                            textFormat: Text.PlainText
                            text: qsTr("Forge")
                            color: Theme.accent
                            font.pixelSize: Theme.fontSize(20)
                            font.weight: Font.DemiBold
                        }
                    }

                    Column {
                        spacing: Theme.size(4)
                        Text {
                            textFormat: Text.PlainText
                            text: qsTr("Limited")
                            color: Theme.accent
                            font.pixelSize: Theme.fontSize(20)
                            font.weight: Font.DemiBold
                        }
                        Text {
                            objectName: "mainMenuHeroLimitedDetail"
                            textFormat: Text.PlainText
                            text: qsTr("Sealed · Draft · Cube")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSize(12)
                        }
                    }
                }
            }

            Surface {
                objectName: "mainMenuPanel"
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredWidth: root.compactLayout ? menuBody.width : Theme.size(410)
                Layout.minimumWidth: root.compactLayout ? menuBody.width : Theme.size(280)
                Layout.maximumWidth: root.compactLayout ? menuBody.width : Theme.size(430)
                Layout.alignment: root.compactLayout ? Qt.AlignTop : Qt.AlignVCenter
                implicitHeight: panelContent.implicitHeight + Theme.size(56)
                elevated: true
                color: Theme.useGlass ? "transparent" : Theme.surface
                border.width: Theme.useGlass ? 1 : 2
                border.color: Theme.useGlass ? "transparent" : "#8FB8A4"

            ColumnLayout {
                id: panelContent
                anchors.fill: parent
                anchors.margins: Theme.size(28)
                spacing: Theme.size(12)

                Text {
                    textFormat: Text.PlainText
                    objectName: "mainMenuHeading"
                    text: qsTr("Start playing")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(24)
                    font.weight: Font.DemiBold
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    Layout.bottomMargin: Theme.size(10)
                    objectName: "mainMenuIntro"
                    visible: !ws.connected
                    text: qsTr("Connect to a room hub, or manage your decks locally.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(13)
                    lineHeight: 1.35
                    wrapMode: Text.WordWrap
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Ready check: %1 · %2 · %3")
                          .arg(cardCatalog.installed
                               ? qsTr("card data installed")
                               : qsTr("card data missing"))
                          .arg(I18n.count("deck", deckLibrary.count))
                          .arg(ws.connected
                               ? qsTr("hub connected")
                               : qsTr("hub offline"))
                    color: cardCatalog.installed
                           && deckLibrary.count > 0
                           && ws.connected ? Theme.success : Theme.warning
                    font.pixelSize: Theme.fontSize(11)
                    wrapMode: Text.WordWrap
                }

                AppButton {
                    Layout.fillWidth: true
                    variant: ws.connected ? "secondary" : "primary"
                    objectName: "mainMenuConnectButton"
                    text: ws.connected ? qsTr("Server connected") : qsTr("Connect to server")
                    leadingText: ws.connected ? "✓" : "↗"
                    enabled: !ws.connected
                    disabledReason: qsTr("Already connected to a server")
                    onClicked: root.appWindow.pushScreen("screens/Connect.qml")
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.size(8)

                    AppButton {
                        Layout.fillWidth: true
                        objectName: "mainMenuCreateRoomButton"
                        variant: ws.connected ? "primary" : "secondary"
                        text: qsTr("Create room")
                        leadingText: "+"
                        enabled: ws.connected && !ws.inRoom
                        disabledReason: root.serverActionBlockerReason()
                        onClicked: root.appWindow.pushScreen("screens/CreateRoom.qml")
                    }

                    AppButton {
                        Layout.fillWidth: true
                        variant: "secondary"
                        text: qsTr("Playtest")
                        leadingText: "▶"
                        enabled: ws.connected && !ws.inRoom
                        disabledReason: root.serverActionBlockerReason()
                        onClicked: root.appWindow.pushScreen(
                                       "screens/CreateRoom.qml",
                                       {"playtestMode": true})
                    }
                }

                AppButton {
                    Layout.fillWidth: true
                    text: qsTr("Join with room code")
                    objectName: "mainMenuJoinRoomButton"
                    leadingText: "→"
                    enabled: ws.connected && !ws.inRoom
                    disabledReason: root.serverActionBlockerReason()
                    onClicked: root.appWindow.pushScreen("screens/JoinRoom.qml")
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.size(8)

                    AppButton {
                        objectName: "mainMenuBrowseHubButton"
                        Layout.fillWidth: true
                        text: qsTr("Browse hub")
                        leadingText: "⌘"
                        enabled: ws.connected && !ws.inRoom
                        disabledReason: root.serverActionBlockerReason()
                        onClicked: root.appWindow.pushScreen(
                                       "screens/RoomBrowser.qml")
                    }

                    AppButton {
                        objectName: "mainMenuPackSimulatorButton"
                        Layout.fillWidth: true
                        text: qsTr("Pack simulator")
                        leadingText: "✦"
                        onClicked: root.appWindow.pushScreen(
                                       "screens/LimitedHub.qml")
                    }
                }

                AppButton {
                    objectName: "mainMenuEventsButton"
                    Layout.fillWidth: true
                    text: qsTr("Events")
                    enabled: ws.connected && !ws.inRoom
                    disabledReason: root.serverActionBlockerReason()
                    onClicked: root.appWindow.pushScreen(
                                   "screens/TournamentBrowser.qml")
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.size(6)
                    Layout.bottomMargin: Theme.size(6)
                    implicitHeight: 1
                    color: Theme.divider
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.size(8)
                    AppButton {
                        objectName: "mainMenuDeckLibraryButton"
                        Layout.fillWidth: true
                        text: qsTr("Deck library")
                        leadingText: "◇"
                        onClicked: root.appWindow.pushScreen("screens/DeckLibrary.qml")
                    }
                    AppButton {
                        objectName: "mainMenuForgeReplaysButton"
                        Layout.fillWidth: true
                        text: qsTr("Forge replays")
                        onClicked: root.appWindow.pushScreen("screens/ForgeReplayLibrary.qml")
                    }
                }

                AppButton {
                    objectName: "mainMenuAnnouncementsButton"
                    Layout.fillWidth: true
                    variant: publicContent.unreadCount > 0 ? "highlight" : "ghost"
                    compact: true
                    text: publicContent.unreadCount > 0
                          ? qsTr("Announcements · %1 unread").arg(publicContent.unreadCount)
                          : qsTr("Announcements")
                    leadingText: publicContent.unreadCount > 0 ? "●" : "◇"
                    onClicked: root.appWindow.pushScreen("screens/Announcements.qml")
                }

                Text {
                    objectName: "mainMenuUnreadAnnouncement"
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    visible: publicContent.unreadCount > 0
                    text: publicContent.latestUnreadTitle
                    color: Theme.primary
                    font.pixelSize: Theme.fontSize(12)
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                AppButton {
                    objectName: "mainMenuSponsorsButton"
                    Layout.fillWidth: true
                    variant: "ghost"
                    compact: true
                    text: qsTr("Sponsors & thanks")
                    leadingText: "♥"
                    onClicked: root.appWindow.pushScreen("screens/Sponsors.qml")
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: deckLibrary.count === 0
                          ? qsTr("Available offline · Import your first deck")
                          : I18n.count("deck", deckLibrary.count)
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                    horizontalAlignment: Text.AlignHCenter
                }

                AppButton {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.size(4)
                    variant: "ghost"
                    compact: true
                    text: qsTr("Quit Hexproof")
                    onClicked: Qt.quit()
                }
            }
        }
            }
        }
    }

    RowLayout {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        anchors.bottomMargin: Theme.size(22)

        Text {
            textFormat: Text.PlainText
            text: "HEXPROOF " + Qt.application.version
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize(10)
            font.letterSpacing: 1.1
        }

        Item { Layout.fillWidth: true }

        Text {
            textFormat: Text.PlainText
            text: qsTr("No accounts · Manual or Forge")
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize(11)
        }
    }

    function serverActionBlockerReason() {
        if (!ws.connected)
            return qsTr("Connect to a server first")
        if (ws.inRoom)
            return qsTr("Leave the current room first")
        return ""
    }

    SponsorAnnouncementPopup {
        id: sponsorAnnouncement
        onViewSponsorsRequested: root.appWindow.pushScreen(
                                     "screens/Sponsors.qml")
    }

    function considerStartupNotices() {
        if (root.suppressStartupNotices || !publicContent.startupReady)
            return
        if (root.StackView.status === StackView.Inactive
                || root.StackView.status === StackView.Deactivating || ws.inRoom) {
            publicContent.deferSponsorAnnouncement()
            return
        }
        if (!cardArtRepairNotice.opened)
            sponsorAnnouncement.openIfNeeded()
        cardArtRepairNoticeTimer.restart()
    }

    Connections {
        target: publicContent
        function onStartupReadyChanged() { root.considerStartupNotices() }
    }

    CardArtRepairNoticePopup {
        id: cardArtRepairNotice
        preferencesModel: preferences
        artManagerModel: cardArtManager
        onReviewRequested: root.appWindow.pushScreen(
                               "screens/CardArtManager.qml")
    }

    Timer {
        id: cardArtRepairNoticeTimer
        interval: 200
        onTriggered: {
            if (!root.suppressStartupNotices && publicContent.startupReady
                    && !sponsorAnnouncement.opened && !ws.inRoom
                    && root.StackView.status !== StackView.Inactive)
                cardArtRepairNotice.openIfNeeded()
        }
    }

    Connections {
        target: cardArtManager
        function onRepairNeededChanged() {
            cardArtRepairNoticeTimer.restart()
        }
    }

    Connections {
        target: sponsorAnnouncement
        function onClosed() {
            cardArtRepairNoticeTimer.restart()
        }
    }
}
