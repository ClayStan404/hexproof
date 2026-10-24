// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "RulesCardInspector"
    when: windowShown
    property var snapshot

    ApplicationWindow {
        id: testWindow
        width: 1000
        height: 850
        visible: true

        QtObject {
            id: catalog
            property int imageRevision: 0
            property url imageUrl: ""
            property var requestedNames: []
            property var requestedFaces: []
            property var faceImages: ({})
            property string backRules: ""
            function imageSource(name, setCode, collectorNumber) {
                requestedNames.push(name)
                return faceImages[name] || imageUrl
            }
            function cardFaces(name, set, number) {
                requestedFaces.push(name)
                if (!["Delver of Secrets", "Insectile Aberration"].includes(name)) return []
                return [{name:"Delver of Secrets", faceName:"", displayName:"Delver of Secrets", setCode:"ISD", collectorNumber:"51"},
                    {name:"Insectile Aberration", faceName:"Insectile Aberration", displayName:"Insectile Aberration", setCode:"ISD", collectorNumber:"51", oracleText:backRules}]
            }
            function tableImageSource(name, setCode, collectorNumber) {
                return ""
            }
        }

        // A source anchor is enough for inspector state tests. Production card
        // hover, keyboard and click routing is exercised by ForgeDuelInspection.
        Item { id: card; x: 20; y: 20; width: 100; height: 140 }
        Item { id: otherSource; x: 160; y: 20; width: 100; height: 100 }
        RulesCardInspector {
            id: inspector
            x: 300; y: 20; width: 410; height: 700
            rulesSession: testRulesPrompt.session
            cardCatalogModel: catalog
            cardBackSource: ""
        }
    }

    function init() {
        testTranslations.setLanguage("en")
        testWindow.requestActivate()
        tryCompare(testWindow, "active", true)
        Theme.uiScale = 1
        testRulesPrompt.clear()
        inspector.clear()
        inspector.width = 410
        inspector.height = 700
        card.focus = false
        mouseMove(otherSource)
        catalog.requestedNames = []
        catalog.requestedFaces = []
        catalog.faceImages = ({})
        catalog.backRules = ""
        catalog.imageUrl = ""
        snapshot = {
            roomId: "INSPECT", gameId: "inspection-game", turn: 4, step: "main1",
            activeSeat: 0, prioritySeat: 0, players: [],
            zones: [{zone: "battlefield", ownerSeat: 0, count: 2, cards: [
                {id: "ballista", visible: true, identity: {name: "Walking Ballista"},
                 ownerSeat: 0, controllerSeat: 0, power: "4", toughness: "4", damage: 2,
                 counters: [{name: "+1/+1", value: 4}], attachedTo: "hidden"},
                {id: "hidden", visible: false, identity: {name: "Secret creature"},
                 faceDown: true, ownerSeat: 0, controllerSeat: 0, power: "2", toughness: "2", damage: 1}
            ]}, {zone: "hand", ownerSeat: 0, count: 1, cards: [
                {id: "hand-card", visible: true, identity: {name: "Lightning Bolt"}}
            ]}, {zone: "hand", ownerSeat: 1, count: 1, cards: [
                {id: "private-hand", visible: false, identity: {name: "Secret hand"}}
            ]}, {zone: "library", ownerSeat: 0, count: 1, cards: [
                {id: "library-card", visible: false, identity: {name: "Secret library"}}
            ]}],
            stack: [{id: "trigger", controllerSeat: 0, ownerSeat: 0,
                     text: "Put a +1/+1 counter on target creature."}]
        }
        verify(testRulesPrompt.applySnapshot(snapshot))
    }

    function test_linkedExileDistinguishesCopiesAndClearsReturnedCards() {
        snapshot.zones[0].cards = [
            {id: "labyrinth-a", visible: true, identity: {name: "Ugin's Labyrinth"},
                ownerSeat: 0, controllerSeat: 0, exiledCardCount: 2, exiledCardIds: ["imprinted"]},
            {id: "labyrinth-b", visible: true, identity: {name: "Ugin's Labyrinth"},
                ownerSeat: 0, controllerSeat: 0}
        ]
        snapshot.zones.push({zone: "exile", ownerSeat: 0, count: 2, cards: [
            {id: "imprinted", visible: true, identity: {name: "Devourer of Destiny"}},
            {id: "face-down-exile", visible: false, faceDown: true}
        ]})
        verify(testRulesPrompt.applySnapshot(snapshot))
        verify(inspector.showCard("labyrinth-a"))
        compare(inspector.card.exiledCardCount, 2)
        verify(inspector.exiledSummary.includes("Devourer of Destiny"))
        verify(inspector.exiledSummary.includes("1 hidden card(s)"))
        verify(inspector.showCard("labyrinth-b"))
        compare(inspector.exiledSummary, "")
        verify(inspector.showCard("labyrinth-a"))
        snapshot.zones[0].cards[0].exiledCardCount = 0
        snapshot.zones[0].cards[0].exiledCardIds = []
        verify(testRulesPrompt.applySnapshot(snapshot))
        compare(inspector.exiledSummary, "")
    }

    function test_revealedChoicesFollowCurrentObjectAndZone() {
        const choices = [{kind:"namedCard", value:"Lightning Bolt"}, {kind:"chosenType", value:"Elf"},
            {kind:"chosenColor", value:"Blue"}, {kind:"chosenColor", value:"Red"},
            {kind:"chosenNumber", value:"0"}, {kind:"chosenMode", value:"Khans"},
            {kind:"classLevel", value:"2"}, {kind:"dungeonRoom", value:"Cave Entrance"}]
        snapshot.zones[0].cards[0].annotations = choices
        snapshot.zones[0].cards[1].annotations = choices
        snapshot.zones[1].cards[0].annotations = choices
        verify(testRulesPrompt.applySnapshot(snapshot))
        verify(inspector.showCard("ballista"))
        compare(inspector.persistentSummary,
            "Attached to Hidden card\nNamed: Lightning Bolt\nType: Elf\nColor: Blue, Red\nNumber: 0\nMode: Khans\nClass level: 2")
        verify(findChild(inspector, "rulesCardInspectorState").text.includes(inspector.persistentSummary))
        verify(inspector.showCard("hidden"))
        compare(inspector.persistentSummary, "Attachment: Walking Ballista")
        verify(inspector.showCard("hand-card"))
        compare(inspector.persistentSummary, "")
        verify(inspector.showCard("ballista"))
        snapshot.zones[0].cards[0].faceDown = true
        verify(testRulesPrompt.applySnapshot(snapshot))
        compare(inspector.persistentSummary, "Attached to Hidden card")
        snapshot.zones[0].cards[0].faceDown = false
        snapshot.zones[0].cards[0].annotations = []
        verify(testRulesPrompt.applySnapshot(snapshot))
        compare(inspector.persistentSummary, "Attached to Hidden card")
        snapshot.zones[0].cards[0].attachedTo = ""
        verify(testRulesPrompt.applySnapshot(snapshot))
        compare(inspector.persistentSummary, "")
    }

    function cleanup() {
        inspector.clear()
        card.focus = false
        mouseMove(otherSource)
        testRulesPrompt.clear()
    }

    function test_newHoverRestoresPinnedCardAndIgnoresOldSourceExit() {
        verify(inspector.showCard("ballista"))
        verify(inspector.previewCard("hand-card", otherSource))
        compare(inspector.card.name, "Lightning Bolt")
        inspector.hidePreview(card)
        compare(inspector.cardId, "hand-card")
        inspector.hidePreview(otherSource)
        compare(inspector.cardId, "ballista")
        verify(inspector.pinned)
        verify(!inspector.previewCard("private-hand", otherSource))
        compare(inspector.cardId, "ballista")
    }

    function test_currentProjectionUpdatesAndHidesUnavailableIdentity() {
        verify(inspector.showCard("ballista"))
        const state = findChild(inspector, "rulesCardInspectorState")
        verify(state.text.includes("Damage marked: 2"))
        compare(state.text.split("Attached to Hidden card").length, 2)
        verify(!state.text.includes("Secret creature"))
        snapshot.zones[0].cards[0].damage = 0
        snapshot.zones[0].cards[0].power = "5"
        verify(testRulesPrompt.applySnapshot(snapshot))
        tryVerify(() => state.text.includes("Damage marked: 0"))
        verify(state.text.includes("5 / 4"))
        snapshot.zones[0].cards[0].visible = false
        snapshot.zones[0].cards[0].faceDown = true
        verify(testRulesPrompt.applySnapshot(snapshot))
        compare(inspector.hasIdentity, false)
        compare(findChild(inspector, "rulesCardInspectorTitle").text, "Face-down card")
        compare(findChild(inspector, "rulesCardInspectorArt").source.toString(), "")
        snapshot.zones[0].cards.shift()
        verify(testRulesPrompt.applySnapshot(snapshot))
        tryCompare(inspector, "hasCard", false)
        compare(inspector.pinnedCardId, "")
    }

    function test_hiddenCardsNeverRequestCatalogIdentity() {
        verify(inspector.showCard("hidden"))
        verify(inspector.hasCard)
        verify(!inspector.hasIdentity)
        verify(findChild(inspector, "rulesCardInspectorState").text.includes("Damage marked: 1"))
        verify(!inspector.showCard("private-hand"))
        verify(!inspector.showCard("library-card"))
        verify(!inspector.showCard("missing"))
        compare(catalog.requestedNames.length, 0)
        compare(catalog.requestedFaces.length, 0)
    }
    function doubleFacedCard() {
        snapshot.zones[0].cards[0].identity = {name:"Delver of Secrets", setCode:"ISD", collectorNumber:"51"}
        verify(testRulesPrompt.applySnapshot(snapshot))
    }
    function test_bothFacesDoNotChangeAuthoritativeCard() {
        doubleFacedCard()
        const front = "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="63" height="88"><rect width="63" height="88" fill="red"/></svg>')
        const back = "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="63" height="88"><rect width="63" height="88" fill="blue"/></svg>')
        catalog.faceImages = ({"Delver of Secrets":front, "Insectile Aberration":back})
        verify(inspector.showCard("ballista"))
        compare(findChild(inspector, "viewOtherFaceButton"), null)
        const gallery = findChild(inspector, "rulesCardInspectorGallery")
        compare(gallery.faceCount, 2)
        const frontArt = findChild(inspector, "rulesCardInspectorArt")
        const backArt = findChild(inspector, "rulesCardInspectorArt-1")
        verify(frontArt.visible && backArt.visible)
        tryCompare(frontArt, "status", Image.Ready)
        tryCompare(backArt, "status", Image.Ready)
        compare(decodeURIComponent(String(frontArt.source)), decodeURIComponent(front))
        compare(decodeURIComponent(String(backArt.source)), decodeURIComponent(back))
        compare(inspector.card.name, "Delver of Secrets")
        compare(snapshot.zones[0].cards[0].identity.name, "Delver of Secrets")
        snapshot.zones[0].cards[0].damage = 5
        verify(testRulesPrompt.applySnapshot(snapshot))
        compare(gallery.faceCount, 2)
        compare(inspector.facePreview.displayFaces.map(face => face.name), ["Delver of Secrets", "Insectile Aberration"])
        verify(findChild(inspector, "rulesCardInspectorState").text.includes("Damage marked: 5"))
    }
    function test_differentPhysicalCopyResetsLocalFace() {
        doubleFacedCard()
        snapshot.zones[0].cards[1] = {id:"other-copy", visible:true, ownerSeat:0, controllerSeat:0,
            identity:{name:"Delver of Secrets", setCode:"ISD", collectorNumber:"51"}}
        verify(testRulesPrompt.applySnapshot(snapshot))
        verify(inspector.showCard("ballista"))
        inspector.facePreview.nextFace()
        compare(inspector.facePreview.faceIndex, 1)
        verify(inspector.showCard("other-copy"))
        compare(inspector.facePreview.faceIndex, 0)
    }
    function test_narrowPinnedGalleryReservesHeightForBothFaces() {
        inspector.width = 300
        inspector.height = 820
        doubleFacedCard()
        catalog.imageUrl = "data:image/svg+xml," + encodeURIComponent(
            '<svg xmlns="http://www.w3.org/2000/svg" width="63" height="88"><rect width="63" height="88" fill="red"/></svg>')
        verify(inspector.showCard("ballista"))
        const gallery = findChild(inspector, "rulesCardInspectorGallery")
        const front = gallery.faceArt(0)
        const back = gallery.faceArt(1)
        tryCompare(gallery, "columnCount", 1)
        compare(gallery.rowCount, 2)
        for (const art of [front, back]) {
            tryCompare(art, "status", Image.Ready)
            verify(art.height >= 250, "Each face retains readable height in the tall reserved dock")
            const point = art.mapToItem(inspector, 0, 0)
            verify(point.x >= 0 && point.y >= 0)
            verify(point.x + art.width <= inspector.width)
            verify(point.y + art.height <= inspector.height)
        }
        const frontPoint = front.mapToItem(inspector, 0, 0)
        const backPoint = back.mapToItem(inspector, 0, 0)
        verify(backPoint.y >= frontPoint.y + front.height)
        const scroll = findChild(inspector, "rulesCardInspectorScroll")
        verify(scroll.height >= 100, "Current state retains its own visible area")
        compare(inspector.card.name, "Delver of Secrets")
    }
    function test_missingFaceArtKeepsLongFallbackInsideArtArea() {
        doubleFacedCard()
        catalog.backRules = "Back rules. ".repeat(100)
        inspector.width = 270
        inspector.height = 600
        verify(inspector.showCard("ballista"))
        const gallery = findChild(inspector, "rulesCardInspectorGallery")
        compare(gallery.faceCount, 2)
        const art = findChild(inspector, "rulesCardInspectorArt-1")
        const fallback = findChild(inspector, "rulesCardInspectorArtFallback-1")
        compare(art.status, Image.Null)
        verify(fallback.visible)
        verify(fallback.text.includes("Back rules."))
        verify(fallback.clip)
        verify(fallback.height <= art.height)
        verify(fallback.mapToItem(gallery, 0, fallback.height).y <= gallery.height)
        compare(inspector.card.name, "Delver of Secrets")
        compare(findChild(inspector, "viewOtherFaceButton"), null)
    }
    function test_multifaceHoverDepartureAndForceHide() {
        doubleFacedCard()
        verify(inspector.previewCard("ballista", card))
        inspector.hidePreview(card)
        wait(140)
        verify(inspector.hasCard)
        inspector.previewHeld = true
        wait(380)
        verify(inspector.hasCard)
        inspector.previewHeld = false
        tryCompare(inspector, "hasCard", false)
        verify(inspector.previewCard("ballista", card))
        inspector.hidePreview(card)
        inspector.hidePreview()
        compare(inspector.previewCardId, "")
    }
    function test_multifaceHiddenIdentityClearsPreviewImmediately() {
        doubleFacedCard()
        verify(inspector.previewCard("ballista", card))
        inspector.facePreview.nextFace()
        catalog.requestedNames.splice(0)
        catalog.requestedFaces.splice(0)
        snapshot.zones[0].cards[0].visible = false
        snapshot.zones[0].cards[0].faceDown = true
        verify(testRulesPrompt.applySnapshot(snapshot))
        tryCompare(inspector, "previewCardId", "")
        verify(!inspector.facePreview.canSwitch)
        compare(inspector.facePreview.displayFaces.length, 0)
        compare(catalog.requestedNames.length, 0)
        compare(catalog.requestedFaces.length, 0)
    }

    function test_gameReplacementCannotReusePinnedIdentity() {
        verify(inspector.showCard("ballista"))
        verify(inspector.previewCard("hand-card", otherSource))
        snapshot.gameId = "replacement-game"
        verify(testRulesPrompt.applySnapshot(snapshot))
        tryCompare(inspector, "hasCard", false)
        compare(inspector.pinnedCardId, "")
        compare(inspector.previewCardId, "")
    }

    function test_stackAbilityUsesCurrentTextWithoutLookingUpIdentity() {
        verify(inspector.showCard("trigger"))
        compare(findChild(inspector, "rulesCardInspectorTitle").text, "Stack ability")
        verify(findChild(inspector, "rulesCardInspectorState").text.includes(snapshot.stack[0].text))
        compare(catalog.requestedNames.length, 0)
    }

    function test_fullArtAndStateStayInsideReservedDock_data() {
        return [
            {tag: "tall-dock", dockWidth: 410, dockHeight: 700},
            {tag: "decision-dock", dockWidth: 410, dockHeight: 500},
            {tag: "compact-dock", dockWidth: 300, dockHeight: 240},
            {tag: "wide-short-dock", dockWidth: 660, dockHeight: 260}
        ]
    }

    function test_fullArtAndStateStayInsideReservedDock(data) {
        inspector.width = data.dockWidth
        inspector.height = data.dockHeight
        catalog.imageUrl = "data:image/svg+xml," + encodeURIComponent(
                    '<svg xmlns="http://www.w3.org/2000/svg" width="1344" height="1872"><rect width="100%" height="100%" fill="#41634e"/></svg>')
        verify(inspector.showCard("ballista"))
        const art = findChild(inspector, "rulesCardInspectorArt")
        const scroll = findChild(inspector, "rulesCardInspectorScroll")
        const unpin = findChild(inspector, "clearRulesCardInspectorButton")
        tryCompare(art, "status", Image.Ready)
        waitForRendering(inspector)
        // Full-face previews decode for their displayed physical size rather
        // than retaining the original 1344-pixel source in every small dock.
        const physicalWidth = art.width * testWindow.screen.devicePixelRatio
        verify(art.sourceSize.width > 0 && art.sourceSize.width < 1344)
        fuzzyCompare(art.sourceSize.width, physicalWidth, 2)
        for (const item of [art, scroll, unpin]) {
            const point = item.mapToItem(inspector, 0, 0)
            verify(item.width > 0 && item.height > 0, item.objectName + " needs nonzero space")
            verify(point.x >= 0 && point.y >= 0, item.objectName + " stays in the dock")
            verify(point.x + item.width <= inspector.width + 1, item.objectName + " fits horizontally")
            verify(point.y + item.height <= inspector.height + 1, item.objectName + " fits vertically")
        }
        verify(scroll.width >= 100)
        verify(scroll.height >= 50)
        mouseClick(unpin)
        tryCompare(inspector, "hasCard", false)
    }
}
