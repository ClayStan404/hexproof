// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
import QtQuick

// Bumps only when this card's own art or printed type arrives. A global
// image counter must not re-evaluate every card on the table. Item, rather
// than QtObject, so the signal listener can live as a child.
Item {
    id: root
    visible: false
    width: 0
    height: 0
    enabled: false

    required property var catalog
    required property string name
    property int stamp: 0

    function consider(arrived) {
        if (name.length && arrived === name)
            ++stamp
    }

    Connections {
        target: root.catalog || null
        ignoreUnknownSignals: true
        function onCardAvailable(requestedName) { root.consider(requestedName) }
        function onCardCacheFinished(requestedName) { root.consider(requestedName) }
        function onCardArtCropAvailable(requestedName) { root.consider(requestedName) }
        function onLanguageChanged() { ++root.stamp }
        function onCatalogChanged() { ++root.stamp }
        function onArtCacheContentsChanged() { ++root.stamp }
        function onCustomArtContentsChanged() { ++root.stamp }
        function onReuseLocalCardArtChanged() { ++root.stamp }
    }
}
