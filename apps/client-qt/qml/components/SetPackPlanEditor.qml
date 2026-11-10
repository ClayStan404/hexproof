// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    required property var sets
    required property var cardCatalogModel
    property string eventType: "set_sealed"
    property string defaultSetId: ""
    property bool custom: false
    property var rows: []
    property var cachedProducts: ({})
    readonly property bool draft: eventType === "set_draft"
    readonly property var canonicalEntries: normalizedEntries()
    readonly property int totalPacks: canonicalEntries.reduce((sum, entry) => sum + entry.count, 0)
    readonly property bool valid: !custom || (rows.length > 0 && rows.length <= 12
        && (!draft || rows.length === 3)
        && rows.every(row => !!selectedSet(row.setId) && /^[1-9][0-9]*$/.test(String(row.count))
                      && Number(row.count) <= 12 && (!draft || Number(row.count) === 1))
        && totalPacks >= 1 && totalPacks <= 12)

    spacing: Theme.size(9)

    function selectedSet(setId) {
        return (sets || []).find(entry => String(entry.id) === String(setId)) || null
    }

    function resetRows() {
        rows = draft ? [{setId: defaultSetId, count: "1"},
                        {setId: defaultSetId, count: "1"},
                        {setId: defaultSetId, count: "1"}]
                     : [{setId: defaultSetId, count: "6"}]
    }

    function updateRow(index, key, value) {
        if (index < 0 || index >= rows.length || rows[index][key] === value)
            return
        const next = rows.slice()
        next[index] = Object.assign({}, next[index])
        next[index][key] = value
        rows = next
    }

    function normalizedEntries() {
        const entries = []
        for (const row of rows) {
            const selected = selectedSet(row.setId)
            if (!selected || !/^[1-9][0-9]*$/.test(String(row.count)))
                continue
            const count = Number(row.count)
            if (!Number.isSafeInteger(count) || count > 12)
                continue
            const existing = !draft ? entries.find(entry => entry.productId === selected.productId) : null
            if (existing)
                existing.count += count
            else
                entries.push({productId: selected.productId, count: count})
        }
        return entries
    }

    function refreshProducts() {
        const next = ({})
        for (const entry of canonicalEntries || []) {
            const cached = cachedProducts[entry.productId]
            if (!next[entry.productId] || next[entry.productId].id !== entry.productId)
                next[entry.productId] = cached && cached.id === entry.productId ? cached
                    : cardCatalogModel ? cardCatalogModel.limitedProduct(entry.productId) : ({})
        }
        // Keep only the selected definitions: changing counts does not reread
        // full recipes, and browsing products cannot grow an unbounded cache.
        cachedProducts = next
    }

    function makePlan() {
        if (!custom || !valid)
            return ({})
        const products = []
        for (const entry of canonicalEntries) {
            if (products.some(product => product.id === entry.productId))
                continue
            const product = cachedProducts[entry.productId]
            if (!product || !product.id)
                return ({})
            products.push(product)
        }
        return {products: products, entries: canonicalEntries}
    }

    function entryLabel(entry, index) {
        const selected = (sets || []).find(value => value.productId === entry.productId) || ({})
        const name = selected.productName || selected.name || entry.productId
        const product = cachedProducts[entry.productId] || ({})
        const size = Number(selected.cardsPerPack || product.cardsPerPack || 0)
        return (draft ? qsTr("Round %1 · %2").arg(index + 1).arg(name)
                      : qsTr("%1 × %2").arg(entry.count).arg(name))
            + (size > 0 ? qsTr(" · %1 cards per pack").arg(size) : "")
            + (selected.authentic === true ? "" : qsTr(" · approximate"))
    }

    onDraftChanged: resetRows()
    onDefaultSetIdChanged: if (!custom) resetRows()
    onCanonicalEntriesChanged: refreshProducts()
    onSetsChanged: {
        cachedProducts = ({})
        refreshProducts()
    }
    Component.onCompleted: {
        resetRows()
        refreshProducts()
    }

    AppToggle {
        objectName: "setPackPlanCustomToggle"
        Layout.fillWidth: true
        text: root.draft ? qsTr("Choose each of the three rounds") : qsTr("Customize sets and pack counts")
        checked: root.custom
        onToggled: {
            root.custom = checked
            if (root.custom && root.rows.length === 0)
                root.resetRows()
        }
    }

    Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        visible: !root.custom
        text: root.draft ? qsTr("Three boosters of the selected set · left / right / left")
                         : qsTr("Six boosters of the selected set per player")
        color: Theme.textMuted
        font.pixelSize: Theme.fontSize(11)
        wrapMode: Text.WordWrap
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: root.custom
        spacing: Theme.size(12)

        Repeater {
            model: root.rows.length
            delegate: ColumnLayout {
                id: planRow
                required property int index
                readonly property var row: root.rows[index] || ({setId: "", count: ""})
                Layout.fillWidth: true
                spacing: Theme.size(5)
                onRowChanged: {
                    // User edits replace the controls' initial QML bindings.
                    // Keep later mode resets and external model updates visible.
                    if (setChoice && setChoice.selectedId !== row.setId)
                        setChoice.selectedId = row.setId
                    if (countField && countField.text !== String(row.count))
                        countField.text = String(row.count)
                }

                Text {
                    textFormat: Text.PlainText
                    text: root.draft ? qsTr("Round %1 · pass %2").arg(planRow.index + 1)
                                       .arg(planRow.index === 1 ? qsTr("right") : qsTr("left"))
                                     : qsTr("Product %1").arg(planRow.index + 1)
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(11)
                    font.weight: Font.DemiBold
                }

                LimitedSetPicker {
                    id: setChoice
                    objectName: "setPackPlanSet-" + planRow.index
                    Layout.fillWidth: true
                    sets: root.sets
                    selectedId: planRow.row.setId
                    onSelectedIdChanged: root.updateRow(planRow.index, "setId", selectedId)
                }

                RowLayout {
                    visible: !root.draft
                    Layout.fillWidth: true
                    Text {
                        textFormat: Text.PlainText
                        text: qsTr("Packs per player")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSize(12)
                    }
                    AppTextField {
                        id: countField
                        objectName: "setPackPlanCount-" + planRow.index
                        Layout.preferredWidth: Theme.size(70)
                        text: planRow.row.count
                        inputMethodHints: Qt.ImhDigitsOnly
                        maximumLength: 3
                        validator: IntValidator { bottom: 1; top: 12 }
                        onTextChanged: root.updateRow(planRow.index, "count", text)
                    }
                    Item { Layout.fillWidth: true }
                    AppButton {
                        objectName: "setPackPlanRemove-" + planRow.index
                        compact: true
                        variant: "ghost"
                        text: qsTr("Remove")
                        enabled: root.rows.length > 1
                        onClicked: root.rows = root.rows.filter((row, index) => index !== planRow.index)
                    }
                }
            }
        }

        AppButton {
            objectName: "setPackPlanAdd"
            visible: !root.draft
            compact: true
            text: qsTr("Add another set")
            enabled: root.rows.length < 12
            onClicked: root.rows = root.rows.concat([{setId: root.defaultSetId, count: "1"}])
        }

        Text {
            objectName: "setPackPlanValidation"
            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: !root.valid
            text: root.draft ? qsTr("Choose one product for each of the three rounds.")
                             : qsTr("Use positive whole pack counts, totaling 1–12 packs per player.")
            color: Theme.warning
            font.pixelSize: Theme.fontSize(12)
            wrapMode: Text.WordWrap
        }

        Text {
            objectName: "setPackPlanSummary"
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: (root.draft ? qsTr("Final round order")
                             : root.totalPacks === 6 ? qsTr("Final recipe · 6 packs per player")
                             : qsTr("Custom recipe · %1 packs per player").arg(root.totalPacks))
                  + "\n" + root.canonicalEntries.map((entry, index) => root.entryLabel(entry, index)).join("\n")
            color: Theme.text
            font.pixelSize: Theme.fontSize(12)
            wrapMode: Text.WordWrap
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.draft ? qsTr("Every seat uses this round order. Each player receives independently sampled packs.")
                             : qsTr("Every player uses this recipe with independently sampled packs. Build at least 40 cards; custom pack counts are not an official format.")
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize(11)
            wrapMode: Text.WordWrap
        }
    }
}
