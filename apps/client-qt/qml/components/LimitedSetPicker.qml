// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    property var sets: []
    property string selectedId: ""
    property string searchPlaceholder: qsTr("Search set name or code")
    property string noMatchesText: qsTr("No sets match this search.")
    property alias searchText: searchField.text
    readonly property var filteredSets: filterSets(sets, searchText)
    readonly property var selectedSet: findSet(sets, selectedId)
    readonly property bool hasSelection: selectedSet !== null

    spacing: Theme.size(7)

    function normalized(value) {
        return String(value === undefined || value === null ? "" : value)
                .trim().toLocaleLowerCase()
    }

    function filterSets(source, queryText) {
        const query = normalized(queryText)
        const result = []
        if (!source)
            return result
        for (let index = 0; index < source.length; ++index) {
            const entry = source[index]
            if (!entry)
                continue
            const searchable = [entry.id, entry.setCode, entry.name,
                                entry.productName, entry.releaseDate]
                    .map(normalized).join(" ")
            if (query.length === 0 || searchable.includes(query))
                result.push(entry)
        }
        return result
    }

    function findSet(source, id) {
        const wanted = normalized(id)
        if (!source || wanted.length === 0)
            return null
        for (let index = 0; index < source.length; ++index) {
            const entry = source[index]
            if (entry && normalized(entry.id) === wanted)
                return entry
        }
        return null
    }

    function indexOfSet(source, id) {
        const wanted = normalized(id)
        if (!source || wanted.length === 0)
            return -1
        for (let index = 0; index < source.length; ++index) {
            const entry = source[index]
            if (entry && normalized(entry.id) === wanted)
                return index
        }
        return -1
    }

    function ensureVisibleSelection() {
        if (indexOfSet(filteredSets, selectedId) >= 0)
            return
        selectedId = filteredSets.length > 0 ? String(filteredSets[0].id) : ""
    }

    onFilteredSetsChanged: ensureVisibleSelection()
    Component.onCompleted: ensureVisibleSelection()

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.size(7)

        AppTextField {
            id: searchField
            objectName: "limitedSetSearchField"
            Layout.fillWidth: true
            placeholderText: root.searchPlaceholder
            onAccepted: setSelector.forceActiveFocus()
        }

        AppButton {
            objectName: "limitedSetSearchClearButton"
            compact: true
            variant: "ghost"
            text: qsTr("Clear")
            visible: searchField.text.length > 0
            onClicked: {
                searchField.clear()
                searchField.forceActiveFocus()
            }
        }
    }

    AppComboBox {
        id: setSelector
        objectName: "limitedSetSelector"
        Layout.fillWidth: true
        enabled: root.filteredSets.length > 0
        model: root.filteredSets
        textRole: "name"
        valueRole: "id"
        currentIndex: root.indexOfSet(root.filteredSets, root.selectedId)
        onActivated: root.selectedId = String(currentValue)
    }

    Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        visible: root.filteredSets.length === 0
        text: root.noMatchesText
        color: Theme.warning
        font.pixelSize: Theme.fontSize(11)
        wrapMode: Text.WordWrap
    }
}
