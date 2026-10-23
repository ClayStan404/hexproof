// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Observe actual geometry; some native wheel sequences leave Flickable.moving
// true after the content stops. Never write view positions or animation state.
var positions = {};
var stopped = {};
function scrolled(view) {
    if (view) { delete positions[view.objectName]; delete stopped[view.objectName]; }
}
function stopNeeded(view) {
    if (!view || !view.moving || stopped[view.objectName]) return false;
    stopped[view.objectName] = true;
    return true;
}
function settled(view) {
    if (!view) return true;
    if (!view.moving) { scrolled(view); return true; }
    const key = view.objectName;
    // The stop press can leave a short rebound animation after the geometry
    // stops changing. Wait for Qt to finish it before delivering a card press.
    if (stopped[key]) return false;
    const now = Date.now(), x = view.contentX, y = view.contentY;
    const previous = positions[key];
    if (!previous || previous.x !== x || previous.y !== y) {
        positions[key] = {x:x, y:y, since:now};
        return false;
    }
    return !view.dragging && !view.flicking && now - previous.since >= 250;
}
