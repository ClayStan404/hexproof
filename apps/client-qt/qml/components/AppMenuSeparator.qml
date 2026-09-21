// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic

MenuSeparator {
    id: control

    leftPadding: Theme.size(10)
    rightPadding: Theme.size(10)
    topPadding: Theme.size(4)
    bottomPadding: Theme.size(4)
    implicitHeight: Theme.size(9)

    contentItem: Rectangle {
        implicitHeight: 1
        color: Theme.divider
    }
}
