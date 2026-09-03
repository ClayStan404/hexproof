// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "LimitedProductArtPanel"
    when: windowShown

    ApplicationWindow {
        width: 720
        height: 220
        visible: true

        LimitedProductArtPanel {
            id: panel
            anchors.fill: parent
            tournamentModel: mockTournament
            cardCatalogModel: mockCatalog
            preferencesModel: mockPreferences
        }
    }

    QtObject {
        id: mockTournament
        property var product: ({"id": "fdn-play", "name": "Foundations Play Boosters"})
    }

    QtObject {
        id: mockCatalog
        property bool installed: true
        property bool limitedArtCaching: false
        property string limitedArtProductId: ""
        property int limitedArtTotal: 0
        property int limitedArtCompleted: 0
        property int limitedArtFailed: 0

        function limitedProduct(productId) { return ({}) }
        function cacheLimitedProductArt(productId) { }
    }

    QtObject {
        id: mockPreferences
        property string cardArtProvider: "auto"
        property string cardLanguage: "zh"
    }

    function test_missingLocalProductDisablesDownload() {
        const button = findChild(panel, "downloadLimitedProductArtButton")
        verify(button !== null)
        compare(panel.hasLocalProduct, false)
        compare(button.enabled, false)
    }
}
