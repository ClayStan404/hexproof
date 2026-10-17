// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "RulesNumberPrompt"
    when: windowShown

    ApplicationWindow { id: window; width: 680; height: 220; visible: true }
    QtObject {
        id: transport
        property var responses: []
        function respondRulesPromptWithNumber(promptId, number) {
            responses = responses.concat([{promptId: promptId, number: number}])
        }
    }
    Component {
        id: component
        RulesNumberPrompt { wsModel: transport; width: 600; height: 120 }
    }

    function init() {
        testTranslations.setLanguage("en")
        transport.responses = []
    }
    function test_displaySimplificationPreservesAuthoritativeBounds_data() {
        return [
            {tag: "finite", minimum: 0, maximum: 5, label: "Choose from 0 to 5"},
            {tag: "unbounded", minimum: 0, maximum: 2147483647,
                label: "Choose a number of at least 0"},
            {tag: "unbounded-positive-minimum", minimum: 2, maximum: 2147483647,
                label: "Choose a number of at least 2"},
            {tag: "large-finite", minimum: 1, maximum: 2147483646,
                label: "Choose from 1 to 2147483646"}
        ]
    }
    function test_displaySimplificationPreservesAuthoritativeBounds(data) {
        const prompt = createTemporaryObject(component, window.contentItem,
            {promptId: 41, minimum: data.minimum, maximum: data.maximum})
        verify(prompt !== null)
        const input = findChild(prompt, "rulesNumberInput")
        compare(findChild(prompt, "rulesNumberRange").text, data.label)
        compare(input.from, data.minimum)
        compare(input.to, data.maximum)
        compare(input.value, data.minimum)
        mouseClick(input.up.indicator)
        compare(input.value, data.minimum + 1)
        mouseClick(findChild(prompt, "rulesConfirmNumber"))
        compare(transport.responses, [{promptId: 41, number: data.minimum + 1}])

        input.value = data.maximum
        mouseClick(findChild(prompt, "rulesConfirmNumber"))
        compare(transport.responses[1], {promptId: 41, number: data.maximum})
        prompt.promptId = 42
        compare(input.value, data.minimum)
    }
}
