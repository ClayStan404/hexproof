// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick

Text {
    property real unit: 1
    property real pointSize: 12
    textFormat: Text.PlainText
    color: "#bacbd4"
    font.pixelSize: pointSize * unit
    verticalAlignment: Text.AlignVCenter
}
