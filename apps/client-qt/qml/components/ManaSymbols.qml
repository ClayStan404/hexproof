// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma Singleton
import QtQuick

FontLoader {
    source: "../assets/mana/mana.ttf"

    function glyph(symbol) {
        // Code points from the pinned Mana 1.18 font, not the system text font.
        const codes = {W: 0xe600, U: 0xe601, B: 0xe602, R: 0xe603, G: 0xe604,
            X: 0xe615, Y: 0xe616, Z: 0xe617, P: 0xe618, S: 0xe619,
            C: 0xe904, E: 0xe907, T: 0xe61a, Q: 0xe61b,
            "½": 0xe902, "∞": 0xe903, "100": 0xe900, "1000000": 0xe901}
        if (/^(?:[0-9]|1[0-5])$/.test(symbol)) return String.fromCharCode(0xe605 + Number(symbol))
        if (/^(?:1[6-9]|20)$/.test(symbol)) return String.fromCharCode(0xe62a + Number(symbol) - 16)
        return codes[symbol] ? String.fromCharCode(codes[symbol]) : ""
    }

    function tint(symbol) {
        return ({W: "#f5edcf", U: "#acd2e5", B: "#b6aab3", R: "#edaa91", G: "#a2c9ad"})[symbol]
                || "#ccc9c1"
    }
}
