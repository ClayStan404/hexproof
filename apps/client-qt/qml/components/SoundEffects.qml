// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma Singleton
import QtQuick

QtObject {
    property var backend: null

    function play(cue) {
        if (cue && backend && typeof backend.play === "function")
            backend.play(cue)
    }

    function preview(cue) {
        if (cue && backend && typeof backend.preview === "function")
            backend.preview(cue)
    }
}
