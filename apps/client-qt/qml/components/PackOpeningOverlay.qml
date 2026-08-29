// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: root

    property var cardCatalogModel: null
    property var packs: []
    property string productName: ""
    property int currentPackIndex: 0
    property var revealedCardIndices: []
    property int stage: 0
    property bool reducedMotion: false
    property url cardBackSource: "qrc:/qml/assets/card-back.jpg"

    readonly property var currentCards: sortedCardsForPack(currentPackIndex)
    readonly property int revealedCount: revealedCardIndices.length
    readonly property bool currentPackRevealed: currentCards.length > 0
                                                && revealedCount >= currentCards.length

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(Theme.size(1220), parent.width - Theme.size(32))
    height: Math.min(Theme.size(780), parent.height - Theme.size(32))
    padding: Theme.size(22)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape

    Overlay.modal: Rectangle { color: "#EC030806" }

    background: Rectangle {
        color: Theme.backgroundRaised
        radius: Theme.radiusLarge
        border.width: 1
        border.color: Theme.borderStrong
    }

    onClosed: {
        packIntro.stop()
        packBurst.stop()
    }

    function rarityRank(rarity) {
        const normalized = (rarity || "").toLowerCase()
        if (normalized === "mythic")
            return 3
        if (normalized === "rare")
            return 2
        if (normalized === "uncommon")
            return 1
        return 0
    }

    function rarityColor(rarity) {
        const rank = rarityRank(rarity)
        if (rank === 3)
            return "#E88943"
        if (rank === 2)
            return Theme.accent
        if (rank === 1)
            return "#C4CFCA"
        return Theme.borderStrong
    }

    function rarityLabel(rarity) {
        const normalized = (rarity || "").toLowerCase()
        if (normalized === "mythic")
            return qsTr("Mythic rare")
        if (normalized === "rare")
            return qsTr("Rare")
        if (normalized === "uncommon")
            return qsTr("Uncommon")
        return qsTr("Common")
    }

    function sortedCardsForPack(packIndex) {
        if (!packs || packIndex < 0 || packIndex >= packs.length)
            return []
        const sourceCards = packs[packIndex].cards || []
        const indexedCards = []
        for (let index = 0; index < sourceCards.length; ++index) {
            indexedCards.push({"card": sourceCards[index], "sourceIndex": index})
        }
        indexedCards.sort((left, right) => {
            const difference = rarityRank(left.card.rarity)
                               - rarityRank(right.card.rarity)
            return difference !== 0 ? difference
                                    : left.sourceIndex - right.sourceIndex
        })
        const result = []
        for (let index = 0; index < indexedCards.length; ++index)
            result.push(indexedCards[index].card)
        return result
    }

    function imageSourceFor(card) {
        if (!cardCatalogModel || !card || !card.name)
            return ""
        void cardCatalogModel.imageRevision
        return cardCatalogModel.tableImageSource(
                    card.name, card.setCode || "", card.collectorNumber || "")
    }

    function showPacks(openedPacks, displayName) {
        if (!openedPacks || openedPacks.length === 0)
            return
        packs = openedPacks
        productName = displayName || ""
        currentPackIndex = 0
        revealedCardIndices = []
        stage = 0
        packShell.scale = 1
        packShell.opacity = 1
        packShell.rotation = 0
        packAura.scale = 1
        open()
        if (!reducedMotion)
            Qt.callLater(packIntro.restart)
    }

    function beginCurrentPack() {
        if (stage !== 0)
            return
        if (reducedMotion) {
            stage = 1
            return
        }
        packBurst.restart()
    }

    function revealNext() {
        if (stage !== 1 || currentPackRevealed)
            return
        for (let index = 0; index < currentCards.length; ++index) {
            if (!isCardRevealed(index)) {
                revealCard(index)
                return
            }
        }
    }

    function isCardRevealed(cardIndex) {
        return revealedCardIndices.indexOf(cardIndex) >= 0
    }

    function revealCard(cardIndex) {
        if (stage !== 1 || cardIndex < 0 || cardIndex >= currentCards.length
                || isCardRevealed(cardIndex)) {
            return
        }
        const next = revealedCardIndices.slice()
        next.push(cardIndex)
        revealedCardIndices = next
    }

    function revealAll() {
        if (stage === 0)
            stage = 1
        const allIndices = []
        for (let index = 0; index < currentCards.length; ++index)
            allIndices.push(index)
        revealedCardIndices = allIndices
    }

    function advanceOrFinish() {
        if (!currentPackRevealed)
            return
        if (currentPackIndex + 1 >= packs.length) {
            close()
            return
        }
        currentPackIndex += 1
        revealedCardIndices = []
        stage = 0
        if (!reducedMotion)
            Qt.callLater(packIntro.restart)
    }

    contentItem: ColumnLayout {
        spacing: Theme.size(14)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.size(12)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.size(3)

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: root.productName.length > 0
                          ? root.productName : qsTr("Booster pack")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(22)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    textFormat: Text.PlainText
                    text: qsTr("Pack %1 of %2")
                          .arg(root.currentPackIndex + 1).arg(root.packs.length)
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize(12)
                }
            }

            StatusPill {
                visible: root.stage === 1
                text: root.currentPackRevealed
                      ? qsTr("Pack revealed")
                      : qsTr("%1 of %2 revealed")
                        .arg(root.revealedCount).arg(root.currentCards.length)
                statusColor: root.currentPackRevealed
                             ? Theme.success : Theme.accent
            }

            AppButton {
                objectName: "packOpeningSkipButton"
                compact: true
                variant: "ghost"
                text: qsTr("Skip animation")
                onClicked: root.close()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.divider
        }

        Item {
            id: sealedStage
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.stage === 0

            Rectangle {
                id: packAura
                anchors.centerIn: packShell
                width: packShell.width + Theme.size(72)
                height: packShell.height + Theme.size(72)
                radius: width / 2
                color: "transparent"
                border.width: Theme.size(2)
                border.color: Theme.accent
                opacity: root.reducedMotion ? 0.35 : 0.25
            }

            SequentialAnimation {
                running: root.opened && root.stage === 0 && !root.reducedMotion
                loops: Animation.Infinite
                NumberAnimation {
                    target: packAura
                    property: "opacity"
                    from: 0.2
                    to: 0.78
                    duration: 720
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: packAura
                    property: "opacity"
                    from: 0.78
                    to: 0.2
                    duration: 720
                    easing.type: Easing.InOutSine
                }
            }

            Rectangle {
                id: packShell
                objectName: "packOpeningBooster"
                anchors.centerIn: parent
                width: Math.min(Theme.size(270), parent.width * 0.38)
                height: width * 1.38
                radius: Theme.radiusMedium
                border.width: Theme.size(2)
                border.color: Theme.accent
                scale: 1
                opacity: 1
                rotation: 0

                gradient: Gradient {
                    GradientStop { position: 0; color: "#244E40" }
                    GradientStop { position: 0.48; color: Theme.surfaceElevated }
                    GradientStop { position: 1; color: "#18251F" }
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: Theme.size(12)
                    radius: Theme.radiusSmall
                    color: "transparent"
                    border.width: 1
                    border.color: "#80E0BD78"
                }

                Column {
                    anchors.centerIn: parent
                    width: parent.width - Theme.size(44)
                    spacing: Theme.size(10)

                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: "◇"
                        color: Theme.primary
                        font.pixelSize: Theme.fontSize(54)
                        font.weight: Font.Light
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: "HEXPROOF"
                        color: Theme.text
                        font.pixelSize: Theme.fontSize(23)
                        font.weight: Font.Bold
                        font.letterSpacing: Theme.size(2)
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: root.productName
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(11)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Open booster")
                    onClicked: root.beginCurrentPack()
                }
            }

            SequentialAnimation {
                id: packIntro
                ParallelAnimation {
                    NumberAnimation {
                        target: packShell
                        property: "scale"
                        from: 0.72
                        to: 1
                        duration: Theme.motionSlow
                        easing.type: Easing.OutBack
                    }
                    NumberAnimation {
                        target: packShell
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: Theme.motionNormal
                    }
                    NumberAnimation {
                        target: packShell
                        property: "rotation"
                        from: -4
                        to: 0
                        duration: Theme.motionSlow
                        easing.type: Easing.OutCubic
                    }
                }
            }

            SequentialAnimation {
                id: packBurst
                ParallelAnimation {
                    NumberAnimation {
                        target: packShell
                        property: "scale"
                        from: 1
                        to: 1.13
                        duration: Theme.motionNormal
                        easing.type: Easing.InCubic
                    }
                    NumberAnimation {
                        target: packShell
                        property: "opacity"
                        from: 1
                        to: 0
                        duration: Theme.motionNormal
                    }
                    NumberAnimation {
                        target: packAura
                        property: "scale"
                        from: 0.85
                        to: 1.45
                        duration: Theme.motionNormal
                        easing.type: Easing.OutCubic
                    }
                }
                ScriptAction {
                    script: {
                        packShell.scale = 1
                        packShell.opacity = 1
                        packAura.scale = 1
                        root.stage = 1
                    }
                }
            }

            Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.size(18)
                text: qsTr("Click the booster to open it")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSize(13)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.stage === 1
            spacing: Theme.size(10)

            GridView {
                id: cardGrid
                objectName: "packOpeningCardGrid"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.currentCards

                readonly property int columnCount: Math.max(
                    1, Math.min(root.currentCards.length,
                                Math.floor(width / Theme.size(138))))
                readonly property real cardWidth: Math.min(
                    Theme.size(146), Math.max(Theme.size(72),
                                              cellWidth - Theme.size(10)))
                readonly property real cardHeight: cardWidth * 1.4
                cellWidth: width / columnCount
                cellHeight: cardHeight + Theme.size(12)
                cacheBuffer: contentHeight

                delegate: Item {
                    id: cardCell
                    required property var modelData
                    required property int index

                    width: cardGrid.cellWidth
                    height: cardGrid.cellHeight

                    Item {
                        id: openedCard
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: cardGrid.cardWidth
                        height: cardGrid.cardHeight
                        property var modelData: cardCell.modelData
                        property int cardIndex: cardCell.index
                        property bool revealed: root.isCardRevealed(cardIndex)
                        property real flipAngle: revealed ? 180 : 0

                        transform: Rotation {
                            origin.x: openedCard.width / 2
                            origin.y: openedCard.height / 2
                            axis.x: 0
                            axis.y: 1
                            axis.z: 0
                            angle: openedCard.flipAngle
                        }

                        Behavior on flipAngle {
                            enabled: !root.reducedMotion
                            NumberAnimation {
                                duration: Theme.motionSlow
                                easing.type: Easing.InOutCubic
                            }
                        }

                        SequentialAnimation {
                            running: root.stage === 1 && !root.reducedMotion
                            PauseAnimation {
                                duration: Math.min(openedCard.cardIndex, 20) * 28
                            }
                            ParallelAnimation {
                                NumberAnimation {
                                    target: openedCard
                                    property: "opacity"
                                    from: 0
                                    to: 1
                                    duration: Theme.motionNormal
                                }
                                NumberAnimation {
                                    target: openedCard
                                    property: "scale"
                                    from: 0.82
                                    to: 1
                                    duration: Theme.motionNormal
                                    easing.type: Easing.OutBack
                                }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: openedCard.flipAngle <= 90
                            radius: Theme.radiusSmall
                            color: Theme.surfaceMuted
                            border.width: 1
                            border.color: Theme.borderStrong
                            clip: true

                            Image {
                                anchors.fill: parent
                                source: root.cardBackSource
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                smooth: true
                            }
                        }

                        Rectangle {
                            id: cardFace
                            anchors.fill: parent
                            visible: openedCard.flipAngle > 90
                            radius: Theme.radiusSmall
                            color: Theme.surfaceElevated
                            border.width: Theme.size(2)
                            border.color: root.rarityColor(openedCard.modelData.rarity)
                            clip: true

                            transform: Rotation {
                                origin.x: cardFace.width / 2
                                origin.y: cardFace.height / 2
                                axis.x: 0
                                axis.y: 1
                                axis.z: 0
                                angle: 180
                            }

                            Image {
                                id: faceArt
                                anchors.fill: parent
                                source: root.imageSourceFor(openedCard.modelData)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: true
                                smooth: true
                            }

                            Rectangle {
                                anchors.fill: parent
                                visible: faceArt.status !== Image.Ready
                                color: Theme.surfaceElevated

                                Text {
                                    textFormat: Text.PlainText
                                    anchors.centerIn: parent
                                    width: parent.width - Theme.size(20)
                                    text: openedCard.modelData.name
                                          || qsTr("Loading card art…")
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSize(12)
                                    font.weight: Font.DemiBold
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                }
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: Theme.size(38)
                                color: "#E608110E"

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: Theme.size(5)
                                    spacing: 1

                                    Text {
                                        textFormat: Text.PlainText
                                        width: parent.width
                                        text: openedCard.modelData.name || ""
                                        color: "white"
                                        font.pixelSize: Theme.fontSize(9)
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        width: parent.width
                                        text: root.rarityLabel(
                                                  openedCard.modelData.rarity)
                                        color: root.rarityColor(
                                                   openedCard.modelData.rarity)
                                        font.pixelSize: Theme.fontSize(8)
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }

                        MouseArea {
                            objectName: "packOpeningCard-" + openedCard.cardIndex
                            anchors.fill: parent
                            enabled: !openedCard.revealed
                            cursorShape: enabled ? Qt.PointingHandCursor
                                                 : Qt.ArrowCursor
                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("Reveal card %1")
                                             .arg(openedCard.cardIndex + 1)
                            onClicked: root.revealCard(openedCard.cardIndex)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.size(10)

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: root.currentPackRevealed
                          ? qsTr("This pack is fully revealed.")
                          : qsTr("Click a card back or reveal the next card.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(12)
                    elide: Text.ElideRight
                }

                AppButton {
                    objectName: "packOpeningRevealNextButton"
                    compact: true
                    text: qsTr("Reveal next")
                    visible: !root.currentPackRevealed
                    onClicked: root.revealNext()
                }

                AppButton {
                    objectName: "packOpeningRevealAllButton"
                    compact: true
                    variant: "ghost"
                    text: qsTr("Reveal all")
                    visible: !root.currentPackRevealed
                    onClicked: root.revealAll()
                }

                AppButton {
                    objectName: "packOpeningContinueButton"
                    compact: true
                    variant: "primary"
                    visible: root.currentPackRevealed
                    text: root.currentPackIndex + 1 < root.packs.length
                          ? qsTr("Next pack") : qsTr("Done")
                    onClicked: root.advanceOrFinish()
                }
            }
        }
    }
}
