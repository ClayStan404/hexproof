// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"
import "../../qml/components"

TestCase {
    name: "SetArtDownload"
    when: windowShown

    ApplicationWindow {
        id: window
        width: 900
        height: 720
        visible: true
        function popScreen() { }
    }

    QtObject {
        id: catalog
        signal catalogChanged()
        property bool installed: true
        property bool busy: false
        property string lastError: ""
        property bool limitedArtCaching: false
        property string limitedArtProductId: ""
        property int limitedArtTotal: 0
        property int limitedArtCompleted: 0
        property int limitedArtFailed: 0
        property var products: [
            {id: "fdn-play", name: "Foundations Play Boosters",
             setCode: "FDN", productType: "set", authentic: true},
            {id: "cube-home", name: "Home Cube",
             setCode: "", productType: "cube", authentic: true}
        ]
        property string cachedProductId: ""

        function limitedProducts() { return products }
        function limitedProduct(productId) {
            for (let index = 0; index < products.length; ++index) {
                if (products[index].id === productId)
                    return products[index]
            }
            return ({})
        }
        function cacheLimitedProductArt(productId) { cachedProductId = productId }
    }

    QtObject {
        id: prefs
        property string cardArtProvider: "auto"
        property string cardLanguage: "zh"
    }

    Component {
        id: pageComponent
        SetArtDownload {
            property var cardCatalog: catalog
            property var preferences: prefs
        }
    }

    function cleanup() {
        Theme.uiScale = 1
        catalog.installed = true
        catalog.cachedProductId = ""
        catalog.limitedArtCaching = false
        catalog.products = [
            {id: "fdn-play", name: "Foundations Play Boosters",
             setCode: "FDN", productType: "set", authentic: true},
            {id: "cube-home", name: "Home Cube",
             setCode: "", productType: "cube", authentic: true}
        ]
    }

    function createPage() {
        const page = createTemporaryObject(pageComponent, window.contentItem,
                                           {width: window.width, height: window.height})
        verify(page !== null)
        waitForRendering(page)
        return page
    }

    function test_filtersCubeAndDownloadsSelectedProduct() {
        const page = createPage()
        compare(page.products.length, 1)
        compare(page.products[0].id, "fdn-play")
        const button = findChild(page, "downloadLimitedProductArtButton")
        verify(button !== null)
        verify(button.enabled)
        mouseClick(button)
        compare(catalog.cachedProductId, "fdn-play")
    }

    function test_requiresInstalledCatalog() {
        catalog.installed = false
        const page = createPage()
        compare(page.products.length, 0)
        const button = findChild(page, "downloadLimitedProductArtButton")
        verify(button !== null)
        verify(!button.enabled)
    }
}
