// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    id: testCase
    name: "NumericEditors"
    when: windowShown
    property int submitted: -1

    ApplicationWindow {
        id: window
        width: 900
        height: 620
        visible: true
    }
    Component { id: numberComponent; NumberInputPopup { maximumValue: 2000 } }
    Component { id: lifeComponent; LifeEditorPopup { } }
    Component { id: counterComponent; CardCounterEditor { } }
    Component { id: diceComponent; DiceRollPopup { } }
    Component { id: positionComponent; LibraryPositionPopup { } }

    function init() { submitted = -1 }
    function test_submitsValidatedLocalizedInteger_data() {
        const rows = []
        const editors = [
            {name: "number", component: numberComponent, field: "numberInputField"},
            {name: "life", component: lifeComponent, field: "lifeEditorField"},
            {name: "counter", component: counterComponent, field: "cardCounterValueField"},
            {name: "dice", component: diceComponent, field: "diceSidesField"},
            {name: "position", component: positionComponent, field: "libraryPositionField"}
        ]
        for (const editor of editors) {
            for (const locale of ["en_US", "de_DE", "ar_EG"]) {
                rows.push({tag: editor.name + "-" + locale, editor: editor, locale: locale})
            }
        }
        return rows
    }
    function test_submitsValidatedLocalizedInteger(data) {
        const editor = createTemporaryObject(data.editor.component, window.contentItem)
        verify(editor !== null)
        if (data.editor.name === "number") {
            editor.valueRequested.connect(value => testCase.submitted = value)
            editor.showFor(1)
        } else if (data.editor.name === "life") {
            editor.lifeRequested.connect(value => testCase.submitted = value)
            editor.showFor("Player", 20)
        } else if (data.editor.name === "counter") {
            editor.counterRequested.connect((id, kind, label, value) => testCase.submitted = value)
            editor.showNumber("Card", 1)
        } else if (data.editor.name === "dice") {
            editor.rollRequested.connect((sides, count) => testCase.submitted = sides)
            editor.showFor(6, 1)
        } else {
            editor.positionRequested.connect(value => testCase.submitted = value)
            editor.showFor("Card")
        }
        tryVerify(() => editor.opened)
        const field = findChild(editor, data.editor.field)
        field.validator.locale = data.locale
        field.text = Number(1000).toLocaleString(Qt.locale(data.locale), "f", 0)
        verify(field.acceptableInput)
        editor.submit()
        compare(submitted, 1000)
        tryVerify(() => !editor.visible)
    }
}
