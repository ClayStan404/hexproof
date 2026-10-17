// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma ComponentBehavior: Bound
import QtQuick

// Flies a few public zone changes. The table underneath is already at the
// new positions; these proxies are paint only.
Item {
    id: root
    required property var tableController
    required property var surface
    anchors.fill: surface
    z: 190
    enabled: false
    readonly property real unit: surface.unit !== undefined ? surface.unit : 1
    readonly property int maxFlights: 6
    readonly property int stageStep: 150
    readonly property int stageLimit: 1200
    readonly property var stageOrder: ({stack: 0, move: 1, combat: 2, damage: 3, death: 4})
    property var origins: ({})
    property var handBefore: ({})
    property var changedIds: []
    property var plan: null
    property int flights: 0
    property int stagedFlights: 0
    // Automatic passes wait only for another player's flights still in the air.
    readonly property bool staging: stagedFlights > 0
    property bool ownResponseArmed: false
    property bool ownUpdate: false

    readonly property var trackedPrefixes: ["forgeCard-", "forgeHandCard-", "forgeStackEntry-",
        "forgeZone-", "forgeOpponentZone-", "forgePlayerZones-", "forgeSeatZone-"]
    // Cards contain no tracked items, so a scan does not descend into them.
    readonly property var cardPrefixes: ["forgeCard-", "forgeHandCard-", "forgeStackEntry-"]
    function tracked(name) {
        return name === "forgeHand" || trackedPrefixes.some(prefix => name.indexOf(prefix) === 0)
    }
    function scan() {
        const found = ({})
        function walk(item) {
            if (!item || !item.visible)
                return
            const name = item.objectName || ""
            if (name && tracked(name)) {
                if (found[name] === undefined) {
                    const point = item.mapToItem(root, item.width / 2, item.height / 2)
                    found[name] = {x: point.x, y: point.y}
                }
                if (cardPrefixes.some(prefix => name.indexOf(prefix) === 0))
                    return
            }
            const children = item.children || []
            for (let index = 0; index < children.length; ++index)
                walk(children[index])
        }
        walk(surface)
        return found
    }
    function capture() {
        if (!Theme.motionEnabled) {
            origins = ({})
            return
        }
        origins = scan()
        const counts = ({})
        for (const seat of surface.playerSeats || [])
            counts[seat] = tableController.zoneCount(seat, "hand")
        handBefore = counts
    }

    function bottomSeat() {
        return surface.bottomSeat !== undefined ? surface.bottomSeat : tableController.localSeat
    }
    function pileNames(zone, seat) {
        if (!zone || zone === "battlefield" || zone === "stack")
            return []
        const own = seat === bottomSeat()
        if (zone === "hand")
            return own ? ["forgeHand", "forgePlayerZones-" + seat] : ["forgePlayerZones-" + seat]
        if (surface.multiplayer)
            return ["forgeSeatZone-" + seat + "-" + zone]
        return [own ? "forgeZone-" + zone : "forgeOpponentZone-" + zone]
    }
    function locate(map, id, zone, seat) {
        if (id) {
            for (const name of ["forgeCard-" + id, "forgeHandCard-" + id, "forgeStackEntry-" + id]) {
                if (map[name])
                    return map[name]
            }
        }
        for (const name of pileNames(zone, seat)) {
            if (map[name])
                return map[name]
        }
        return null
    }
    // Resolved when the flight starts, from the layout the update produced.
    function destination(event) {
        if (event.toZone === "battlefield" && event.id && surface.pointFor) {
            const point = surface.pointFor(event.id)
            if (point.x !== 0 || point.y !== 0)
                return {x: point.x, y: point.y}
        }
        return locate(scan(), event.id, event.toZone, event.ownerSeat)
    }

    // Who caused the update: the controller of a resolving stack object, the
    // attacker for combat damage, the local player right after their own
    // answer, otherwise the active player.
    function causeSeat(events) {
        const session = tableController.rulesSession
        const resolved = events.find(event => event.fromZone === "stack" && event.toZone !== "stack")
        if (resolved)
            return resolved.controllerSeat
        if (session.step === "combat_damage"
                && events.some(event => event.category === "damage" || event.category === "death"))
            return session.activeSeat
        if (ownUpdate)
            return tableController.localSeat
        return session.activeSeat
    }
    function currentPlan() {
        if (plan)
            return plan
        const session = tableController.rulesSession
        const events = session.transitionSnap ? [] : session.transitions
        const staged = events.length > 0 && causeSeat(events) !== tableController.localSeat
        const budget = ({})
        for (const seat in handBefore)
            budget[seat] = handBefore[seat] - tableController.zoneCount(Number(seat), "hand")
        const entries = []
        const arrivals = ({})
        const highlighted = []
        let flightCount = 0
        for (const event of events) {
            const delay = staged ? Math.min(stageLimit, (stageOrder[event.category] ?? 0) * stageStep) : 0
            let fromZone = event.fromZone
            let flies = event.flight === true
            if (!flies && (event.kind === "enter" || event.kind === "stackPush")
                    && (event.toZone === "stack" || event.toZone === "battlefield")
                    && event.ownerSeat !== bottomSeat() && (budget[event.ownerSeat] || 0) > 0) {
                budget[event.ownerSeat] -= 1
                fromZone = "hand"
                flies = true
            }
            const origin = flies && flightCount < maxFlights
                ? locate(origins, event.id, fromZone, event.ownerSeat) : null
            if (origin)
                ++flightCount
            if (event.id && event.toZone)
                arrivals[event.id] = delay + (origin ? Theme.motionSlow : 0)
            if (staged && event.id)
                highlighted.push(event.id)
            entries.push({event: event, origin: origin, delay: delay})
        }
        plan = {created: Date.now(), staged: staged, entries: entries, arrivals: arrivals,
            highlighted: highlighted}
        return plan
    }
    // How long a newly created card waits before it fades in, or -1 when it
    // did not arrive in this update and should simply appear.
    function arrivalDelay(id) {
        if (!Theme.motionEnabled || Theme.motionSnap || !id)
            return -1
        const current = currentPlan()
        if (Date.now() - current.created > stageLimit + Theme.motionSlow * 2)
            return -1
        const delay = current.arrivals[id]
        return delay === undefined ? -1 : delay
    }

    function launch() {
        finish()
        if (!Theme.motionEnabled)
            return
        const current = currentPlan()
        for (const entry of current.entries) {
            if (!entry.origin)
                continue
            const proxy = flightComponent.createObject(flightHost, {
                overlay: root,
                event: entry.event,
                fromX: entry.origin.x,
                fromY: entry.origin.y,
                delay: entry.delay,
                staged: current.staged,
                label: entry.event.name || ""
            }) as FlightProxy
            if (!proxy)
                continue
            ++flights
            if (current.staged)
                ++stagedFlights
            proxy.start()
        }
        setChangedIds(current.highlighted)
        if (current.highlighted.length)
            highlightTimer.restart()
    }
    // Every card binds to this list; an empty list is not reassigned.
    function setChangedIds(ids) {
        if (ids.length || changedIds.length)
            changedIds = ids
    }

    function land(proxy) {
        if (!proxy || proxy.landed)
            return
        proxy.landed = true
        proxy.halt()
        flights = Math.max(0, flights - 1)
        if (proxy.staged)
            stagedFlights = Math.max(0, stagedFlights - 1)
        proxy.destroy()
    }

    function finish() {
        const live = flightHost.children
        for (let index = live.length - 1; index >= 0; --index) {
            const proxy = live[index] as FlightProxy
            if (proxy && !proxy.landed) {
                proxy.landed = true
                proxy.halt()
                proxy.destroy()
            }
        }
        flights = 0
        stagedFlights = 0
        setChangedIds([])
        highlightTimer.stop()
    }

    Item { id: flightHost; objectName: "forgeMotionFlights"; anchors.fill: parent }
    Timer {
        id: highlightTimer
        interval: 1500
        onTriggered: root.setChangedIds([])
    }
    Connections {
        target: root.tableController.interaction || null
        ignoreUnknownSignals: true
        function onWaitingForResponseChanged() {
            if (root.tableController.interaction.waitingForResponse)
                root.ownResponseArmed = true
        }
    }
    Connections {
        target: root.tableController.rulesSession
        function onAboutToApplySnapshot(snap) {
            root.ownUpdate = root.ownResponseArmed
            root.ownResponseArmed = false
            root.plan = null
            root.capture()
            Theme.motionSnap = snap
        }
        function onTransitionsChanged() {
            Qt.callLater(() => {
                Theme.motionSnap = false
                if (root.tableController.rulesSession.transitionSnap)
                    root.finish()
                else
                    root.launch()
            })
        }
    }
    Connections {
        target: Theme
        function onMotionEpochChanged() { root.finish() }
    }
    component FlightProxy: Item {
        id: proxy
        property var overlay: null
        property var event: ({})
        property real fromX: 0
        property real fromY: 0
        property real toX: 0
        property real toY: 0
        property int delay: 0
        property bool staged: false
        property bool landed: false
        property string label: ""
        width: 54 * (overlay ? overlay.unit : 1)
        height: 76 * (overlay ? overlay.unit : 1)
        enabled: false
        opacity: 0
        function start() {
            x = fromX - width / 2
            y = fromY - height / 2
            // Waiting at least a frame lets the new layout settle first.
            wait.interval = Math.max(16, delay)
            wait.start()
        }
        function halt() {
            wait.stop()
            travel.stop()
        }
        function fly() {
            if (!overlay)
                return
            const to = overlay.destination(event)
            if (!to || Math.hypot(to.x - fromX, to.y - fromY) < width / 2) {
                overlay.land(proxy)
                return
            }
            toX = to.x
            toY = to.y
            opacity = 1
            travel.start()
        }
        Timer {
            id: wait
            onTriggered: proxy.fly()
        }
        ParallelAnimation {
            id: travel
            NumberAnimation {
                target: proxy
                property: "x"
                to: proxy.toX - proxy.width / 2
                duration: Theme.motionSlow
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: proxy
                property: "y"
                to: proxy.toY - proxy.height / 2
                duration: Theme.motionSlow
                easing.type: Easing.OutCubic
            }
            onFinished: {
                if (proxy.overlay)
                    proxy.overlay.land(proxy)
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: 5
            antialiasing: true
            color: proxy.label.length ? Theme.withAlpha("#101820", 0.94) : Theme.withAlpha(Theme.primary, 0.85)
            border.width: 1
            border.color: proxy.label.length ? Theme.primary : "#f3f1e9"
            Rectangle {
                visible: proxy.label.length === 0
                anchors.fill: parent
                anchors.margins: 5
                radius: 3
                color: "transparent"
                border.width: 1
                border.color: Theme.withAlpha("#f3f1e9", 0.6)
            }
            Text {
                anchors.fill: parent
                anchors.margins: 4
                visible: proxy.label.length > 0
                textFormat: Text.PlainText
                text: proxy.label
                color: "#f3f1e9"
                font.pixelSize: 10
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
    Component { id: flightComponent; FlightProxy {} }
}
