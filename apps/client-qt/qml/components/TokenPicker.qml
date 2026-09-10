// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "TokenPresentation.js" as TokenPresentation

Popup {
    id: root

    required property var catalogModel
    property var preferredTokens: []
    property string titleText: qsTr("Tokens and emblems")
    property string actionText: qsTr("Create")
    property bool existingTokensDisabled: false
    property alias detailsPopup: detailsPopup
    property string kindFilter: "all"
    property bool allowEmblemRecipient: false
    property var players: []
    property int defaultRecipientSeat: -1
    property int recipientSeat: defaultRecipientSeat
    readonly property string cardLanguage: catalogModel && catalogModel.language || "en"
    readonly property bool catalogAvailable:
        catalogModel.tokenCatalogInstalled === true
    readonly property bool hasPreferredTokens:
        preferredTokens && preferredTokens.length > 0
    readonly property var displayedTokens:
        mergeTokens(preferredTokens,
                    catalogModel.tokenSearchResults
                    ? catalogModel.tokenSearchResults : [],
                    searchField.text)
    signal tokenSelected(var token)
    signal emblemSelected(var emblem, int seat)

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(760), parent.width - Theme.size(48))
    height: Math.min(Theme.size(650), parent.height - Theme.size(56))
    padding: Theme.size(24)
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

    onOpened: {
        searchField.text = ""
        kindFilter = "all"
        recipientSeat = defaultRecipientSeat
        if (root.catalogAvailable)
            catalogModel.searchTokens("", kindFilter)
        searchField.forceActiveFocus()
        cacheDisplayedTokens()
    }
    onClosed: {
        searchTimer.stop()
        preview.hide()
        detailsPopup.close()
    }
    onKindFilterChanged: searchTimer.restart()
    onCardLanguageChanged: if (opened) cacheDisplayedTokens()
    onDisplayedTokensChanged: if (opened) Qt.callLater(cacheDisplayedTokens)

    function cacheDisplayedTokens() {
        if (!opened || !catalogModel || typeof catalogModel.cacheToken !== "function") return
        for (const token of displayedTokens.slice(0, 60)) catalogModel.cacheToken(token)
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(14)

        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(3)

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: root.titleText
                    elide: Text.ElideRight
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(20)
                    font.weight: Font.DemiBold
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Search by name or set and number · Hover to enlarge · Click for rules")
                    wrapMode: Text.WordWrap
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(12)
                }
            }

            ActivityRing {
                visible: root.catalogModel.tokenSearching === true
                Layout.preferredWidth: Theme.size(18)
                Layout.preferredHeight: Theme.size(18)
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

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.catalogAvailable && !root.hasPreferredTokens
            spacing: Theme.size(14)

            Item { Layout.fillHeight: true }

            Text {
                textFormat: Text.PlainText
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("Install the token catalog to create tokens and emblems.")
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(14)
            }

            AppButton {
                objectName: "downloadTokenCatalogButton"
                Layout.alignment: Qt.AlignHCenter
                variant: "primary"
                text: root.catalogModel.busy === true
                      ? qsTr("Downloading…") : qsTr("Download token catalog")
                enabled: root.catalogModel.busy !== true
                onClicked: root.catalogModel.downloadTokenCatalog()
            }

            Text {
                textFormat: Text.PlainText
                Layout.alignment: Qt.AlignHCenter
                visible: String(root.catalogModel.status
                                ? root.catalogModel.status : "").length > 0
                text: I18n.status(root.catalogModel.status
                                  ? root.catalogModel.status : "")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(11)
            }

            Item { Layout.fillHeight: true }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.catalogAvailable || root.hasPreferredTokens
            spacing: Theme.size(12)

            AppTextField {
                id: searchField
                objectName: "tokenSearchField"
                Layout.fillWidth: true
                placeholderText: qsTr("Search tokens and emblems or TUNF #1…")
                onTextChanged: searchTimer.restart()
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.size(8)
                Repeater {
                    objectName: "tokenKindFilters"
                    model: [{kind: "all", label: qsTr("All")},
                            {kind: "token", label: qsTr("Tokens")},
                            {kind: "emblem", label: qsTr("Emblems")}]
                    delegate: AppButton {
                        required property var modelData
                        objectName: "tokenKindFilter" + modelData.kind
                        compact: true
                        text: modelData.label
                        variant: root.kindFilter === modelData.kind ? "highlight" : "secondary"
                        onClicked: root.kindFilter = modelData.kind
                    }
                }
                Item { Layout.fillWidth: true }
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                visible: !root.catalogAvailable && root.hasPreferredTokens
                text: qsTr("Install the token catalog to search beyond this deck's saved tokens and emblems.")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(11)
                wrapMode: Text.WordWrap
            }

            ListView {
                id: tokenResults
                objectName: "tokenSearchResults"
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: root.displayedTokens
                spacing: Theme.size(7)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Surface {
                    id: tokenRow
                    required property var modelData
                    readonly property var details: TokenPresentation.details(root.catalogModel, modelData)

                    width: ListView.view.width
                    height: Theme.size(root.allowEmblemRecipient
                                       && modelData.kind === "emblem" ? 112 : 74)
                    radius: Theme.radiusMedium
                    color: Theme.surfaceMuted

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.size(10)
                        spacing: Theme.size(12)

                        Rectangle {
                            id: tokenThumbnail
                            objectName: "tokenResultThumbnail"
                            Layout.preferredWidth: Theme.size(62)
                            Layout.fillHeight: true
                            radius: Theme.radiusSmall
                            color: Theme.surfaceElevated
                            border.width: 1
                            border.color: Theme.borderStrong

                            Image {
                                anchors.fill: parent
                                anchors.margins: 2
                                fillMode: Image.PreserveAspectFit
                                source: {
                                    void root.cardLanguage
                                    return root.catalogModel
                                        && (root.catalogModel.imageRevision
                                            === undefined
                                            || root.catalogModel.imageRevision >= 0)
                                        ? root.catalogModel.tokenImageSource(
                                              tokenRow.modelData.name,
                                              tokenRow.modelData.setCode,
                                              tokenRow.modelData.collectorNumber)
                                        : ""
                                }
                            }
                            HoverHandler {
                                onHoveredChanged: {
                                    if (hovered) {
                                        preview.inspect(tokenRow.modelData, tokenThumbnail)
                                    } else preview.hide(tokenThumbnail)
                                }
                            }
                            TapHandler {
                                acceptedButtons: Qt.LeftButton
                                onTapped: {
                                    preview.hide()
                                    detailsPopup.showCard(tokenRow.modelData)
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.size(3)

                            Text {
                                textFormat: Text.PlainText
                                objectName: "tokenResultName"
                                Layout.fillWidth: true
                                text: tokenRow.details.displayName
                                color: Theme.text
                                font.pixelSize: Theme.fontSize(14)
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                visible: root.allowEmblemRecipient
                                         && tokenRow.modelData.kind === "emblem"
                                Text {
                                    textFormat: Text.PlainText
                                    text: qsTr("Recipient")
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSize(11)
                                }
                                AppComboBox {
                                    objectName: "emblemRecipientSelector"
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    Layout.preferredHeight: Theme.size(32)
                                    model: root.players
                                    textRole: "label"
                                    valueRole: "seat"
                                    currentIndex: root.players.findIndex(player => player.seat === root.recipientSeat)
                                    onActivated: root.recipientSeat = currentValue
                                }
                            }

                            Text {
                                textFormat: Text.PlainText
                                objectName: "tokenResultDetails"
                                Layout.fillWidth: true
                                text: root.tokenDetails(tokenRow.modelData)
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSize(10)
                                elide: Text.ElideRight
                                TapHandler {
                                    acceptedButtons: Qt.LeftButton
                                    onTapped: {
                                        preview.hide()
                                        detailsPopup.showCard(tokenRow.modelData)
                                    }
                                }
                            }
                        }

                        StatusPill {
                            visible: tokenRow.modelData.preferred === true
                            text: qsTr("Deck")
                            statusColor: Theme.primary
                        }

                        AppButton {
                            objectName: "createTokenResultButton"
                            compact: true
                            variant: "primary"
                            text: root.existingTokensDisabled
                                  && tokenRow.modelData.preferred === true
                                  ? qsTr("Added") : root.actionText
                            enabled: (!root.existingTokensDisabled
                                      || tokenRow.modelData.preferred !== true)
                                     && (!root.allowEmblemRecipient
                                         || tokenRow.modelData.kind !== "emblem"
                                         || root.players.some(player => player.seat === root.recipientSeat))
                            onClicked: {
                                TokenPresentation.prioritize(root.catalogModel, tokenRow.modelData)
                                if (root.allowEmblemRecipient && tokenRow.modelData.kind === "emblem")
                                    root.emblemSelected(tokenRow.modelData, root.recipientSeat)
                                else root.tokenSelected(tokenRow.modelData)
                                root.close()
                            }
                        }
                    }
                }
            }

            Text {
                textFormat: Text.PlainText
                Layout.alignment: Qt.AlignHCenter
                visible: root.catalogModel.tokenSearching !== true
                         && tokenResults.count === 0
                text: qsTr("No tokens or emblems found")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
            }
        }
    }

    Timer {
        id: searchTimer
        interval: 180
        onTriggered: {
            if (root.opened && root.catalogAvailable)
                root.catalogModel.searchTokens(searchField.text, root.kindFilter)
        }
    }

    TokenDetailsPopup {
        id: detailsPopup
        catalogModel: root.catalogModel
    }

    Item {
        parent: root.contentItem ? root.contentItem.parent : null
        anchors.fill: parent
        anchors.margins: Theme.size(12)
        visible: root.opened
        enabled: false
        z: 1000
        // A sibling of the content layout: preview visibility must never
        // make ColumnLayout resize the search results or position the art.
        CardHoverPreview {
            id: preview
            objectName: "tokenArtPreview"
            catalogModel: root.catalogModel
            tokenArt: true
        }
    }

    function tokenKey(token) {
        return String(token.name ? token.name : "").toLocaleLowerCase()
                + "\u001f" + String(token.setCode ? token.setCode : "").toUpperCase()
                + "\u001f" + String(token.collectorNumber
                                      ? token.collectorNumber : "")
    }

    function tokenMatches(token, query) {
        if (query.length === 0)
            return true
        const identity = query.match(
                           /^([a-z0-9]{2,8})\s*#?\s*([a-z0-9._+*-]+)$/)
        if (identity) {
            const requestedSet = identity[1].toUpperCase()
            const tokenSet = String(token.setCode ? token.setCode : "")
                             .toUpperCase()
            const requestedNumber = identity[2].replace(/^0+(?=.)/, "")
            const tokenNumber = String(token.collectorNumber
                                       ? token.collectorNumber : "")
                                .replace(/^0+(?=.)/, "")
            if ((tokenSet === requestedSet
                 || tokenSet === "T" + requestedSet)
                    && tokenNumber.toLocaleLowerCase()
                       === requestedNumber.toLocaleLowerCase()) {
                return true
            }
        }
        const haystack = [
            token.name ? token.name : "",
            token.displayName ? token.displayName : "",
            token.typeLine ? token.typeLine : "",
            token.oracleText ? token.oracleText : "",
            token.setCode ? token.setCode : "",
            token.collectorNumber ? token.collectorNumber : ""
        ].join(" ").toLocaleLowerCase()
        return haystack.includes(query)
    }

    function copyToken(token, preferred) {
        return {
            "kind": token.kind === "emblem" ? "emblem" : "token",
            "name": token.name ? token.name : "",
            "displayName": token.displayName ? token.displayName
                                               : (token.name ? token.name : ""),
            "typeLine": token.typeLine ? token.typeLine : "",
            "setCode": token.setCode ? token.setCode : "",
            "collectorNumber": token.collectorNumber
                               ? token.collectorNumber : "",
            "imageUrl": token.imageUrl ? token.imageUrl : "",
            "power": token.power ? token.power : "",
            "toughness": token.toughness ? token.toughness : "",
            "oracleText": token.oracleText ? token.oracleText : "",
            "oracleId": token.oracleId ? token.oracleId : "",
            "preferred": preferred
        }
    }

    function tokenDetails(token) {
        return TokenPresentation.summary(catalogModel, token, true)
    }

    function mergeTokens(preferred, catalogResults, searchText) {
        const merged = []
        const seen = {}
        const query = String(searchText ? searchText : "")
                      .trim().toLocaleLowerCase()
        const append = function(token, isPreferred) {
            if (!token || !root.tokenMatches(token, query))
                return
            const kind = token.kind === "emblem" ? "emblem" : "token"
            if (root.kindFilter !== "all" && kind !== root.kindFilter)
                return
            const key = root.tokenKey(token)
            if (key.length === 2 || seen[key] === true)
                return
            seen[key] = true
            merged.push(root.copyToken(token, isPreferred))
        }
        const preferredList = preferred ? preferred : []
        for (let index = 0; index < preferredList.length; ++index)
            append(preferredList[index], true)
        const catalogList = catalogResults ? catalogResults : []
        for (let index = 0; index < catalogList.length; ++index)
            append(catalogList[index], false)
        return merged
    }
}
