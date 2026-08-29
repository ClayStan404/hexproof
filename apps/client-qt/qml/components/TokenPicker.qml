// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    required property var catalogModel
    property var preferredTokens: []
    property string titleText: qsTr("Create token")
    property string actionText: qsTr("Create")
    property bool existingTokensDisabled: false
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
        if (root.catalogAvailable)
            catalogModel.searchTokens("")
        searchField.forceActiveFocus()
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
                    text: root.titleText
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(20)
                    font.weight: Font.DemiBold
                }

                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Search by English or Chinese name, or by set and number · English token art")
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
                text: qsTr("Install the token catalog to create tokens.")
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
                placeholderText: qsTr("Search tokens or TUNF #1…")
                enabled: root.catalogAvailable
                onTextChanged: searchTimer.restart()
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                visible: !root.catalogAvailable && root.hasPreferredTokens
                text: qsTr("Install the token catalog to search beyond this deck's saved tokens.")
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

                    width: ListView.view.width
                    height: Theme.size(74)
                    radius: Theme.radiusMedium
                    color: Theme.surfaceMuted

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.size(10)
                        spacing: Theme.size(12)

                        Rectangle {
                            Layout.preferredWidth: Theme.size(62)
                            Layout.fillHeight: true
                            radius: Theme.radiusSmall
                            color: Theme.surfaceElevated
                            border.width: 1
                            border.color: Theme.borderStrong

                            Image {
                                anchors.fill: parent
                                anchors.margins: 2
                                fillMode: Image.PreserveAspectCrop
                                source: root.catalogModel
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

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.size(3)

                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: tokenRow.modelData.displayName
                                      ? tokenRow.modelData.displayName
                                      : tokenRow.modelData.name
                                color: Theme.text
                                font.pixelSize: Theme.fontSize(14)
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                textFormat: Text.PlainText
                                objectName: "tokenResultDetails"
                                Layout.fillWidth: true
                                text: root.tokenDetails(tokenRow.modelData)
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSize(10)
                                elide: Text.ElideRight
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
                            enabled: !root.existingTokensDisabled
                                     || tokenRow.modelData.preferred !== true
                            onClicked: {
                                root.catalogModel.cacheToken(tokenRow.modelData)
                                root.tokenSelected(tokenRow.modelData)
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
                text: qsTr("No tokens found")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize(12)
            }
        }
    }

    Timer {
        id: searchTimer
        interval: 180
        onTriggered: {
            if (root.catalogAvailable)
                root.catalogModel.searchTokens(searchField.text)
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
        const details = []
        const power = String(token.power ? token.power : "").trim()
        const toughness = String(token.toughness ? token.toughness : "").trim()
        if (power.length > 0 && toughness.length > 0)
            details.push(power + "/" + toughness)
        const oracleText = String(token.oracleText ? token.oracleText : "")
                           .trim().replace(/\s*\n\s*/g, " · ")
        if (oracleText.length > 0)
            details.push(oracleText)
        else if (details.length === 0 && token.typeLine)
            details.push(token.typeLine)
        details.push(String(token.setCode ? token.setCode : "").toUpperCase()
                     + " #" + String(token.collectorNumber
                                      ? token.collectorNumber : ""))
        return details.join(" · ")
    }

    function mergeTokens(preferred, catalogResults, searchText) {
        const merged = []
        const seen = {}
        const query = String(searchText ? searchText : "")
                      .trim().toLocaleLowerCase()
        const append = function(token, isPreferred) {
            if (!token || !root.tokenMatches(token, query))
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
