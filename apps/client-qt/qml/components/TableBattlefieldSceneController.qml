// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: root

    required property var tableRoot
    required property var sceneView

    // Repeater delegates register while the QML engine is finalizing them.
    // A Map avoids changing a plain object's shape for every dynamic card ID.
    readonly property var cardItems: new Map()
    readonly property var seatItems: new Map()
    property var cardPoints: ({})
    property var seatPoints: ({})
    property var seatBounds: ({})
    property bool pointRefreshScheduled: false

    function selectedAttachment(cardId) {
        if (!cardId)
            return ({})
        return tableRoot.gameTableModel.attachmentForSource(cardId)
    }

    function arrowForSource(cardId) {
        if (!cardId)
            return ({})
        return tableRoot.gameTableModel.arrowForSource(cardId)
    }

    function registerCard(cardId, item) {
        if (!cardId || !item)
            return
        cardItems.set(cardId, item)
        schedulePointRefresh()
    }

    function unregisterCard(cardId, item) {
        if (cardItems.get(cardId) !== item)
            return
        cardItems.delete(cardId)
        schedulePointRefresh()
    }

    function registerSeat(seat, item) {
        if (seat < 0 || !item)
            return
        seatItems.set(seat, item)
        schedulePointRefresh()
    }

    function unregisterSeat(seat, item) {
        if (seatItems.get(seat) !== item)
            return
        seatItems.delete(seat)
        schedulePointRefresh()
    }

    function battlefieldSize(seat) {
        const item = seatItems.get(seat)
        if (!item || !item.parent)
            return ({"width": 0, "height": 0})
        return {
            "width": Math.max(0, item.parent.width - Theme.size(12)),
            "height": Math.max(0, item.parent.height - Theme.size(12))
        }
    }

    function cardAtRootPoint(rootX, rootY) {
        let found = false
        cardItems.forEach(function(item) {
            if (found || !item || !item.visible || !item.parent)
                return
            const localPoint = item.mapFromItem(
                                   tableRoot, rootX, rootY)
            if (localPoint.x >= 0 && localPoint.x <= item.width
                    && localPoint.y >= 0
                    && localPoint.y <= item.height) {
                found = true
            }
        })
        return found
    }

    function schedulePointRefresh() {
        if (pointRefreshScheduled)
            return
        pointRefreshScheduled = true
        Qt.callLater(function() {
            pointRefreshScheduled = false
            refreshCardPoints()
        })
    }

    function refreshCardPoints() {
        const points = ({})
        const playerPoints = ({})
        const playerBounds = ({})
        cardItems.forEach(function(item, cardId) {
            if (!item || !item.visible || !item.parent)
                return
            const point = sceneView.mapFromItem(
                              item, item.width / 2, item.height / 2)
            points[cardId] = {"x": point.x, "y": point.y}
        })
        seatItems.forEach(function(item, seat) {
            if (!item || !item.visible || !item.parent)
                return
            const point = sceneView.mapFromItem(
                              item, item.width / 2, item.height / 2)
            const battlefieldOrigin = sceneView.mapFromItem(
                                          item.parent, 0, 0)
            playerPoints[seat] = {"x": point.x, "y": point.y}
            playerBounds[seat] = {
                "x": battlefieldOrigin.x,
                "y": battlefieldOrigin.y,
                "width": item.parent.width,
                "height": item.parent.height
            }
        })
        cardPoints = points
        seatPoints = playerPoints
        seatBounds = playerBounds
        if (sceneView && sceneView.requestPaint)
            sceneView.requestPaint()
    }
}
