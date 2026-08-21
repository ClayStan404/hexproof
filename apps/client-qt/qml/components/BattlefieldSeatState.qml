// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick

QtObject {
    id: root

    required property var tableRoot

    property int seat: -1
    property string displayName: ""
    property int life: 0
    property var counters: []
    property int counterCount: 0
    property int libraryCount: 0
    property int handCount: 0
    property int mulliganCount: 0
    property var battlefieldModel: null
    property var graveyardModel: null
    property var exileModel: null
    property var commandZoneModel: null
    property int commanderTax: 0
    property var commanderTaxes: ({})
    property bool eliminated: false
    property double modelRevision: -1

    function updateFrom(source) {
        const sourceSeat = source.seat !== undefined ? source.seat : -1
        battlefieldModel = tableRoot.zoneState.zoneModelForSeat(sourceSeat, "battlefield")
        graveyardModel = tableRoot.zoneState.zoneModelForSeat(sourceSeat, "graveyard")
        exileModel = tableRoot.zoneState.zoneModelForSeat(sourceSeat, "exile")
        commandZoneModel = tableRoot.zoneState.zoneModelForSeat(sourceSeat, "command")
        const sourceRevision = source.modelRevision !== undefined
                             ? source.modelRevision : -1
        if (sourceRevision >= 0 && modelRevision === sourceRevision)
            return
        modelRevision = sourceRevision
        seat = sourceSeat
        displayName = source.displayName ? source.displayName : ""
        life = source.life !== undefined ? source.life : 0
        counterCount = source.counterCount !== undefined
                     ? source.counterCount : 0
        libraryCount = source.libraryCount !== undefined
                     ? source.libraryCount : 0
        handCount = source.handCount !== undefined ? source.handCount : 0
        mulliganCount = source.mulliganCount !== undefined
                      ? source.mulliganCount : 0
        commanderTax = source.commanderTax !== undefined
                     ? source.commanderTax : 0
        commanderTaxes = source.commanderTaxes ? source.commanderTaxes : ({})
        eliminated = source.eliminated === true
        counters = source.counters ? source.counters : []
    }
}
