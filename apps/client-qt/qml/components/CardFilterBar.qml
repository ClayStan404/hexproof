// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
pragma Translator: "CardWorkbench"
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root
    required property var filters
    property Component extraFilters: null
    property string placeholderText: qsTranslate("CardWorkbench", "Search cards…")
    property bool filtersAvailable: true
    property bool compact: false
    function focusSearch() {
        searchField.forceActiveFocus()
        searchField.selectAll()
    }
    signal resetRequested()
    readonly property var colorOptions: [
        {value: "W", label: qsTranslate("CardWorkbench", "White"), symbol: "W", tint: "#eee4c4"},
        {value: "U", label: qsTranslate("CardWorkbench", "Blue"), symbol: "U", tint: "#77b5d9"},
        {value: "B", label: qsTranslate("CardWorkbench", "Black"), symbol: "B", tint: "#aaa4b3"},
        {value: "R", label: qsTranslate("CardWorkbench", "Red"), symbol: "R", tint: "#db896f"},
        {value: "G", label: qsTranslate("CardWorkbench", "Green"), symbol: "G", tint: "#81b59a"},
        {value: "C", label: qsTranslate("CardWorkbench", "Colorless"), symbol: "◇", tint: "#c5c9c9"},
        {value: "M", label: qsTranslate("CardWorkbench", "Multicolor"), symbol: "◉", tint: "#d6ba72"}
    ]
    readonly property var sections: [
        {label: qsTranslate("CardWorkbench", "Mana value"), key: "manaValues", options: [
            {value: "0", label: "0"}, {value: "1", label: "1"}, {value: "2", label: "2"},
            {value: "3", label: "3"}, {value: "4", label: "4"}, {value: "5", label: "5"},
            {value: "6", label: "6"}, {value: "7+", label: "7+"}]},
        {label: qsTranslate("CardWorkbench", "Rarity"), key: "rarities", options: [
            {value: "common", label: qsTranslate("CardWorkbench", "Common")}, {value: "uncommon", label: qsTranslate("CardWorkbench", "Uncommon")},
            {value: "rare", label: qsTranslate("CardWorkbench", "Rare")}, {value: "mythic", label: qsTranslate("CardWorkbench", "Mythic rare")}]},
        {label: qsTranslate("CardWorkbench", "Card type"), key: "types", options: [
            {value: "Creature", label: qsTranslate("CardWorkbench", "Creature")}, {value: "Planeswalker", label: qsTranslate("CardWorkbench", "Planeswalker")},
            {value: "Instant", label: qsTranslate("CardWorkbench", "Instant")}, {value: "Sorcery", label: qsTranslate("CardWorkbench", "Sorcery")},
            {value: "Artifact", label: qsTranslate("CardWorkbench", "Artifact")}, {value: "Enchantment", label: qsTranslate("CardWorkbench", "Enchantment")},
            {value: "Battle", label: qsTranslate("CardWorkbench", "Battle")}, {value: "Land", label: qsTranslate("CardWorkbench", "Land")}]}
    ]
    implicitHeight: toolbar.implicitHeight
    GridLayout {
        id: toolbar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        columns: root.width < Theme.size(root.compact ? 500 : 680) ? 1 : 2
        rowSpacing: Theme.size(6)
        AppTextField {
            id: searchField
            objectName: "workbenchSearch"
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            implicitHeight: Theme.size(38)
            placeholderText: root.placeholderText
            text: root.filters.query
            onTextEdited: root.filters.query = text
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(4)
            Repeater {
                model: root.colorOptions
                delegate: Button {
                    id: colorButton
                    required property var modelData
                    objectName: "filterColor-" + modelData.value
                    Layout.preferredWidth: Theme.size(30)
                    Layout.preferredHeight: Theme.size(30)
                    enabled: root.filtersAvailable
                    checkable: true
                    autoExclusive: false
                    checked: root.filters.colors.includes(modelData.value)
                    onClicked: root.filters.toggle("colors", modelData.value)
                    Accessible.name: modelData.label
                    background: Rectangle {
                        radius: width / 2
                        color: colorButton.checked ? colorButton.modelData.tint : Theme.surfaceMuted
                        border.width: colorButton.checked ? 2 : 1
                        border.color: colorButton.checked ? Theme.accent : Theme.borderStrong
                    }
                    contentItem: Text {
                        textFormat: Text.PlainText
                        readonly property string glyph: ManaSymbols.glyph(colorButton.modelData.value)
                        text: glyph || colorButton.modelData.symbol
                        color: colorButton.checked ? "#15191a" : colorButton.modelData.tint
                        font.family: glyph ? ManaSymbols.name : "sans-serif"
                        font.pixelSize: Theme.fontSize(17)
                        font.bold: !glyph
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    ToolTip.visible: hovered
                    ToolTip.text: modelData.label
                    ToolTip.delay: 400
                }
            }
            Item { Layout.fillWidth: true }
            AppButton {
                objectName: "advancedCardFiltersButton"
                compact: true
                implicitWidth: Theme.size(40)
                text: root.filters.activeCount > 0 ? "☷ " + root.filters.activeCount : "☷"
                accessibleName: qsTranslate("CardWorkbench", "Advanced filters")
                variant: root.filters.activeCount ? "highlight" : "secondary"
                enabled: root.filtersAvailable
                onClicked: advanced.open()
                ToolTip.visible: hovered
                ToolTip.text: qsTranslate("CardWorkbench", "Advanced filters")
            }
        }
    }
    Popup {
        id: advanced
        objectName: "advancedCardFilters"
        parent: Overlay.overlay
        width: Math.min(Theme.size(850), parent ? parent.width - Theme.size(24) : 850)
        height: Math.min(Theme.size(640), parent ? parent.height - Theme.size(24) : 640)
        x: parent ? (parent.width - width) / 2 : 0
        y: parent ? (parent.height - height) / 2 : 0
        modal: true
        focus: true
        padding: Theme.size(20)
        background: Surface { elevated: true }
        contentItem: ColumnLayout {
            spacing: Theme.size(14)
            Text {
                textFormat: Text.PlainText
                text: qsTranslate("CardWorkbench", "Advanced filters")
                color: Theme.text
                font.pixelSize: Theme.fontSize(24)
                font.bold: true
            }
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTranslate("CardWorkbench", "Cards must include every selected color. Other options match any selection in their category; different categories combine.")
                color: Theme.textMuted
                wrapMode: Text.WordWrap
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ColumnLayout {
                    width: parent.width
                    spacing: Theme.size(18)
                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.size(6)
                        Repeater {
                            model: root.colorOptions
                            delegate: AppButton {
                                required property var modelData
                                objectName: "filter-colors-" + modelData.value
                                compact: true
                                text: modelData.label
                                checkable: true
                                autoExclusive: false
                                checked: root.filters.colors.includes(modelData.value)
                                leadingText: checked ? "☑" : "☐"
                                variant: checked ? "primary" : "secondary"
                                onClicked: root.filters.toggle("colors", modelData.value)
                            }
                        }
                    }
                    Repeater {
                        model: root.sections
                        delegate: ColumnLayout {
                            id: section
                            required property var modelData
                            Layout.fillWidth: true
                            Text {
                                textFormat: Text.PlainText
                                text: section.modelData.label
                                color: Theme.text
                                font.pixelSize: Theme.fontSize(17)
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: Theme.size(6)
                                Repeater {
                                    model: section.modelData.options
                                    delegate: AppButton {
                                        required property var modelData
                                        objectName: "filter-" + section.modelData.key + "-" + modelData.value
                                        compact: true
                                        text: modelData.label
                                        checkable: true
                                        autoExclusive: false
                                        checked: root.filters[section.modelData.key].includes(modelData.value)
                                        leadingText: checked ? "☑" : "☐"
                                        variant: checked ? "primary" : "secondary"
                                        onClicked: root.filters.toggle(section.modelData.key, modelData.value)
                                    }
                                }
                            }
                        }
                    }
                    Loader {
                        Layout.fillWidth: true
                        sourceComponent: root.extraFilters
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                AppButton {
                    objectName: "resetAdvancedCardFiltersButton"
                    text: qsTranslate("CardWorkbench", "Reset filters")
                    onClicked: {
                        root.filters.reset()
                        root.resetRequested()
                    }
                }
                Item { Layout.fillWidth: true }
                AppButton {
                    objectName: "closeAdvancedCardFilters"
                    text: qsTranslate("CardWorkbench", "Done")
                    variant: "primary"
                    onClicked: advanced.close()
                }
            }
        }
    }
}
