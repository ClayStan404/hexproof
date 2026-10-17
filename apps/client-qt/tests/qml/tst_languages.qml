// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"
import "../../qml/screens"

TestCase {
    name: "Languages"
    when: windowShown

    ApplicationWindow {
        id: window
        width: 1280
        height: 800
        visible: true
    }

    Component {
        id: languageSettingsComponent
        LanguageSettings { }
    }

    // Every shipped interface language except source English. The codes and
    // native labels mirror src/UiLanguages.h; the settings list comes from the
    // same table through the uiLanguages context property.
    property var languageCodes: ["zh", "zh_TW", "ja", "fr", "de", "es", "it", "pt_BR"]
    property var nativeLabels: ["English", "简体中文", "日本語", "Français", "Deutsch",
                                "Español", "Italiano", "Português (Brasil)", "繁體中文"]

    function init() {
        testTranslations.setLanguage("en")
    }

    function cleanup() {
        testTranslations.setLanguage("en")
    }

    function uiCatalogProbe() {
        // Stable literal in the LanguageSettings context of the main catalog.
        return qsTranslate("LanguageSettings", "Interface language")
    }

    function dynamicCatalogProbe() {
        // Stable literal from the hand-maintained dynamic template list.
        return I18n.tr("Card-art migration does not follow symbolic links or special files.")
    }

    function test_settingsLanguageListMatchesRegistry() {
        const instance = languageSettingsComponent.createObject(window.contentItem)
        verify(instance !== null)
        const selector = findChild(instance, "settingsLanguageSelector")
        verify(selector !== null)
        compare(uiLanguages.length, 9)
        compare(selector.model.length, 9)
        for (let index = 0; index < uiLanguages.length; ++index)
            compare(selector.model[index].label, nativeLabels[index])
        const stored = preferences.uiLanguage
        let expectedIndex = 0
        for (let index = 0; index < uiLanguages.length; ++index) {
            if (uiLanguages[index].code === stored)
                expectedIndex = index
        }
        compare(selector.currentIndex, expectedIndex)
        compare(selector.currentValue, stored)
        compare(selector.displayText, nativeLabels[expectedIndex])
        instance.destroy()
    }

    function test_everyLanguageTranslatesRepresentativeMessages() {
        for (const code of languageCodes) {
            testTranslations.setLanguage(code)
            const interfaceLabel = uiCatalogProbe()
            const dynamicMessage = dynamicCatalogProbe()
            verify(interfaceLabel !== "Interface language", code)
            verify(dynamicMessage !==
                   "Card-art migration does not follow symbolic links or special files.",
                   code)
            testTranslations.setLanguage("en")
            compare(uiCatalogProbe(), "Interface language")
            compare(dynamicCatalogProbe(),
                    "Card-art migration does not follow symbolic links or special files.")
        }
    }

    function test_unknownLanguageFallsBackToEnglish() {
        testTranslations.setLanguage("zh")
        verify(uiCatalogProbe() !== "Interface language")
        testTranslations.setLanguage("xx")
        compare(uiCatalogProbe(), "Interface language")
        compare(dynamicCatalogProbe(),
                "Card-art migration does not follow symbolic links or special files.")
        testTranslations.setLanguage("")
        compare(uiCatalogProbe(), "Interface language")
    }

    function test_scryUsesMagicTerminology_data() {
        return [
            {tag: "fr", title: "Regard", prompt: "Voulez-vous appliquer le regard ?"},
            {tag: "de", title: "Hellsicht", prompt: "Möchten Sie Hellsicht anwenden?"},
            {tag: "it", title: "Profetizzare", prompt: "Vuoi profetizzare?"},
            {tag: "pt_BR", title: "Vidência", prompt: "Você quer usar vidência?"},
        ]
    }

    function test_scryUsesMagicTerminology(data) {
        testTranslations.setLanguage(data.tag)
        compare(RulesText.text("Scry"), data.title)
        compare(RulesText.text("Do you want to scry?"), data.prompt)
        // Unknown engine text and response labels are not rewritten by a
        // terminology correction to the known templates.
        compare(RulesText.text("Unknown effect %2"), "Unknown effect %2")
        testTranslations.setLanguage("en")
        compare(RulesText.text("Scry"), "Scry")
        compare(RulesText.text("Do you want to scry?"), "Do you want to scry?")
    }

    function test_gameTermsAgreeAcrossCatalogs() {
        testTranslations.setLanguage("de")
        compare(I18n.tr("Token"), "Spielstein")
        compare(I18n.tr("Battlefield"), "Spielfeld")
        compare(qsTranslate("RulesTable", "Battlefield"), "Spielfeld")
        compare(qsTranslate("CardCounterEditor", "Add ability counter"),
                "Fähigkeitsmarke hinzufügen")
        compare(I18n.tr("Add ability counter"), "Fähigkeitsmarke hinzufügen")
        // The owner's arbitrary numeric tally is distinct from a card marker.
        compare(qsTranslate("PlayerCounterPip", "Counter"), "Zähler")

        testTranslations.setLanguage("it")
        compare(RulesText.choice("", "Library", "", ""), "Grimorio")
        compare(I18n.tr("Library"), "Grimorio")
        compare(RulesText.text("Put Example on the top or bottom of your library?"),
                "Mettere Example in cima o in fondo al tuo grimorio?")

        testTranslations.setLanguage("zh_TW")
        compare(qsTranslate("CardWorkbench", "Sorcery"), "巫術")
        compare(I18n.tr("Sorcery"), "巫術")
        compare(qsTranslate("RulesTable", "Command zone"), "統帥區")
        compare(I18n.tr("Command"), "統帥區")
        compare(RulesText.choice("", "Graveyard", "", ""), "墳墓場")
        compare(I18n.tr("Graveyard"), "墳墓場")
    }

    function test_draftPracticeTranslatesQmlAndCppMessages() {
        for (const code of languageCodes) {
            testTranslations.setLanguage(code)
            verify(qsTranslate("DraftPractice", "Draft practice") !== "Draft practice", code)
            verify(qsTranslate("hexproof::client::DraftSimulator",
                               "A practice deck needs at least 40 cards.")
                   !== "A practice deck needs at least 40 cards.", code)
        }
        testTranslations.setLanguage("en")
        compare(qsTranslate("DraftPractice", "Draft practice"), "Draft practice")
        compare(qsTranslate("hexproof::client::DraftSimulator",
                            "A practice deck needs at least 40 cards."),
                "A practice deck needs at least 40 cards.")
    }

    function test_switchingLeavesNoPreviousTranslation() {
        testTranslations.setLanguage("ja")
        const japanese = uiCatalogProbe()
        verify(japanese !== "Interface language")
        testTranslations.setLanguage("de")
        const german = uiCatalogProbe()
        verify(german !== "Interface language")
        verify(german !== japanese)
        testTranslations.setLanguage("ja")
        compare(uiCatalogProbe(), japanese)
        testTranslations.setLanguage("zh")
        compare(uiCatalogProbe(), "界面语言")
        testTranslations.setLanguage("en")
        compare(uiCatalogProbe(), "Interface language")
    }

    function test_pluralSelectionFollowsLanguageRules_data() {
        return [
            // Qt rules: German/Spanish/Italian plural for n != 1, French and
            // Portuguese (Brazil) singular for n <= 1, Japanese/Chinese one
            // single form.
            {tag: "de", singulars: [1], plurals: [0, 2, 10]},
            {tag: "fr", singulars: [0, 1], plurals: [2, 10]},
            {tag: "es", singulars: [1], plurals: [0, 2, 10]},
            {tag: "it", singulars: [1], plurals: [0, 2, 10]},
            {tag: "pt_BR", singulars: [0, 1], plurals: [2, 10]},
            {tag: "ja", singulars: [0, 1, 2, 10], plurals: []},
            {tag: "zh", singulars: [0, 1, 2, 10], plurals: []},
            {tag: "zh_TW", singulars: [0, 1, 2, 10], plurals: []},
        ]
    }

    function test_pluralSelectionFollowsLanguageRules(data) {
        testTranslations.setLanguage(data.tag)
        // All singular counts render the same form (ignoring the number),
        // all plural counts render the same other form.
        const reduced = form => form.replace(/[0-9]+/g, "#")
        for (const count of data.singulars)
            compare(reduced(I18n.count("deck", count)), reduced(I18n.count("deck", data.singulars[0])))
        if (data.plurals.length > 0) {
            for (const count of data.plurals)
                compare(reduced(I18n.count("deck", count)), reduced(I18n.count("deck", data.plurals[0])))
            verify(reduced(I18n.count("deck", data.plurals[0]))
                   !== reduced(I18n.count("deck", data.singulars[0])), data.tag)
        }
        testTranslations.setLanguage("en")
        compare(I18n.count("deck", 0), "0 deck(s)")
        compare(I18n.count("deck", 1), "1 deck(s)")
        compare(I18n.count("deck", 2), "2 deck(s)")
    }

    function test_playerNamesKeepLiteralPlaceholderText() {
        const source = "Alice %2 drew 3 cards."
        for (const code of languageCodes) {
            testTranslations.setLanguage(code)
            const localized = I18n.status(source)
            verify(localized.indexOf("%2") >= 0, code + " -> " + localized)
            verify(localized.indexOf("Alice") >= 0, code + " -> " + localized)
        }
        testTranslations.setLanguage("en")
        compare(I18n.status(source), "Alice %2 drew 3 cards.")
    }
}
