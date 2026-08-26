// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "ConditionalMenuItems"
    when: windowShown

    ApplicationWindow {
        width: 320
        height: 240
        visible: true

        Menu {
            id: testMenu

            ConditionalMenuItem {
                id: hiddenItem
                text: "Hidden"
                visible: false
            }
            ConditionalMenuSeparator {
                id: hiddenSeparator
                visible: false
            }
            ConditionalMenuItem {
                id: shownItem
                text: "Shown"
            }
        }
    }

    function test_hiddenRowsCollapse() {
        testMenu.open()
        tryVerify(() => testMenu.opened)
        compare(hiddenItem.height, 0)
        compare(hiddenSeparator.height, 0)
        verify(shownItem.height > 0)
        testMenu.close()
    }
}
