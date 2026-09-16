// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "TableBackgrounds"
    when: windowShown

    ApplicationWindow {
        id: testWindow
        visible: true
        width: 900
        height: 620
    }

    Binding {
        target: TableBackgrounds
        property: "currentId"
        value: preferences.tableBackground
    }

    Component {
        id: backgroundComponent
        AppBackground { width: 720; height: 480; variant: "playmat" }
    }

    Component {
        id: pickerComponent
        TableBackgroundPicker {
            width: 720
            selectedId: preferences.tableBackground
            onBackgroundSelected: key => preferences.tableBackground = key
        }
    }

    Component {
        id: popupComponent
        TableBackgroundPopup { preferencesModel: preferences }
    }

    Component {
        id: settingsComponent
        TableSettingsPopup { }
    }

    function init() {
        preferences.tableBackground = "default"
        Theme.uiTheme = "classic"
        Theme.uiScale = 1
        testTranslations.setLanguage("en")
    }

    function cleanup() {
        preferences.tableBackground = "default"
        Theme.uiTheme = "classic"
        Theme.uiScale = 1
        testTranslations.setLanguage("en")
    }

    function test_allBackgroundsLoadAcrossThemes() {
        const background = createTemporaryObject(backgroundComponent, testWindow.contentItem)
        const rendered = findChild(background, "tableBackgroundImage")
        const picker = createTemporaryObject(pickerComponent, testWindow.contentItem)
        const plain = findChild(background, "tableDefaultBackground")
        for (const entry of [...TableBackgrounds.entries, TableBackgrounds.entries[0]]) {
            const hasImage = entry.key !== "default"
            const button = findChild(picker, "tableBackgroundChoice-" + entry.key)
            const thumbnail = findChild(picker, "tableBackgroundThumbnail-" + entry.key)
            tryCompare(thumbnail, "status", hasImage ? Image.Ready : Image.Null)
            mouseClick(button)
            compare(preferences.tableBackground, entry.key)
            verify(button.selected)
            for (const theme of ["classic", "glass", "classic"]) {
                Theme.uiTheme = theme
                compare(preferences.tableBackground, entry.key)
                compare(rendered.source, entry.source)
                tryCompare(rendered, "status", hasImage ? Image.Ready : Image.Null)
                compare(rendered.visible, hasImage)
                compare(plain.visible, !hasImage && theme === "classic")
                compare(rendered.fillMode, Image.PreserveAspectCrop)
            }
        }
    }

    function test_defaultRestoresGlassBackdropAfterImage() {
        Theme.uiTheme = "glass"
        const background = createTemporaryObject(backgroundComponent, testWindow.contentItem)
        const plainBackdrop = Theme.backdropScene
        verify(plainBackdrop !== null)
        const image = findChild(background, "tableBackgroundImage")
        preferences.tableBackground = "forest"
        tryCompare(image, "status", Image.Ready)
        verify(Theme.backdropScene !== plainBackdrop)
        preferences.tableBackground = "default"
        tryCompare(image, "status", Image.Null)
        verify(!image.visible)
        compare(Theme.backdropScene, plainBackdrop)
        compare(Theme.backdropBlur, plainBackdrop)
    }

    function test_keyboardSelectionAndTranslation() {
        testWindow.requestActivate()
        tryVerify(() => testWindow.active)
        const picker = createTemporaryObject(pickerComponent, testWindow.contentItem)
        const button = findChild(picker, "tableBackgroundChoice-forest")
        button.forceActiveFocus(Qt.TabFocusReason)
        tryCompare(button, "activeFocus", true)
        keyClick(Qt.Key_Space)
        compare(preferences.tableBackground, "forest")
        testTranslations.setLanguage("zh")
        const translated = findChild(picker, "tableBackgroundChoice-forest")
        tryCompare(translated, "text", "翡翠秘境")
        verify(translated.selected)
        const defaultButton = findChild(picker, "tableBackgroundChoice-default")
        compare(defaultButton.text, "默认背景")
        verify(waitForPolish(testWindow))
        mouseClick(defaultButton)
        compare(preferences.tableBackground, "default")
    }

    function test_unknownBackgroundFallsBack() {
        compare(TableBackgrounds.entry("removed-background").key, "default")
        compare(TableBackgrounds.entry("removed-background").source, "")
    }

    function test_popupScrollsAtLargeScale() {
        Theme.uiScale = 1.5
        const popup = createTemporaryObject(popupComponent, testWindow.contentItem)
        popup.open()
        tryCompare(popup, "opened", true)
        verify(waitForPolish(testWindow))
        verify(popup.width <= testWindow.width && popup.height <= testWindow.height)
        const scroll = findChild(popup, "tableBackgroundScroll")
        verify(scroll.contentHeight > scroll.availableHeight)
        scroll.contentItem.contentY = scroll.contentHeight - scroll.availableHeight
        verify(waitForPolish(testWindow))
        const woven = findChild(popup.contentItem, "tableBackgroundChoice-woven")
        const point = woven.mapToItem(scroll, 0, 0)
        verify(point.y >= -1 && point.y + woven.height <= scroll.height + 1)
        mouseClick(woven)
        compare(preferences.tableBackground, "woven")
        const done = findChild(popup, "closeTableBackgroundButton")
        mouseClick(done)
        tryCompare(popup, "opened", false)
    }

    function test_tableSettingsRemainReachableAtLargeScale() {
        Theme.uiScale = 1.8
        const popup = createTemporaryObject(settingsComponent, testWindow.contentItem)
        popup.showFor(false, true, false, 7, true, true)
        tryCompare(popup, "opened", true)
        verify(waitForPolish(testWindow))
        verify(popup.height <= testWindow.height)
        const scroll = findChild(popup, "tableSettingsScroll")
        verify(scroll.contentHeight > scroll.availableHeight)
        scroll.contentItem.contentY = scroll.contentHeight - scroll.availableHeight
        verify(waitForPolish(testWindow))
        const apply = findChild(popup.contentItem, "applyTableSettingsButton")
        const point = apply.mapToItem(scroll, 0, 0)
        verify(point.y >= -1 && point.y + apply.height <= scroll.height + 1)
        mouseClick(apply)
        tryCompare(popup, "opened", false)
    }
}
