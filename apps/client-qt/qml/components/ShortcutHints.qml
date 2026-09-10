// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma Singleton

import QtQuick

QtObject {
    function suffix(actionIds) {
        void preferences.shortcutRevision
        const ids = Array.isArray(actionIds) ? actionIds : [actionIds]
        const bindings = []
        for (const id of ids) {
            const sequences = preferences.shortcutSequences(id)
            for (let index = 0; index < sequences.length; ++index) {
                if (!bindings.includes(sequences[index]))
                    bindings.push(sequences[index])
            }
        }
        return bindings.length > 0 ? " · " + bindings.join(" / ") : ""
    }
}
