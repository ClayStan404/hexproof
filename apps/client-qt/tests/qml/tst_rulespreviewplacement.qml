// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"

TestCase {
    name: "RulesPreviewPlacement"
    when: windowShown
    ApplicationWindow { id: window; width:1920; height:1011; visible:true }
    Component {
        id: translatedSourceComponent
        Item {
            property alias glide: sourceGlide
            transform: Translate { id: sourceGlide }
            Item { objectName:"translatedPreviewSource"; width:130; height:180 }
        }
    }
    Item {
        id: viewport
        parent: window.contentItem
        width: window.width; height: window.height
        Item { id: source; x:800; y:650; width:180; height:250 }
        QtObject {
            id: controller
            property string inspectedId: ""
            function openCardDetails(id) { inspectedId = id }
            property bool roomConnected: true
            property bool sideboarding: false
            property bool priorityInputBlocked: false
            property url cardBackSource: "data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' width='63' height='88'><rect width='63' height='88' fill='brown'/></svg>"
        }
        QtObject {
            id: faces
            property var displayFaces: [{name:"Grizzly Bears", imageSource:controller.cardBackSource}]
        }
        QtObject {
            id: inspector
            property var previewSource: source
            property string previewCardId: "card"
            property bool hasCard: true
            property bool hasIdentity: true
            property bool previewHeld: false
            property bool previewNeedsInspection: false
            property string persistentSummary: ""
            property var facePreview: faces
            function hidePreview() { previewCardId = "" }
        }
        RulesCardHoverPreview { id: preview; tableController:controller; inspector:inspector }
    }
    function init() {
        window.width=1920; window.height=1011; Theme.uiScale=1
        Theme.motionEnabled=false
        controller.inspectedId=""
        controller.roomConnected=true; controller.priorityInputBlocked=false
        controller.sideboarding=false
        source.x=800; source.y=650; source.width=180; source.height=250
        source.visible=true
        inspector.previewSource=source
        inspector.hasIdentity=true; inspector.previewCardId="card"; inspector.hasCard=true
        inspector.persistentSummary=""
        faces.displayFaces=[{name:"Grizzly Bears", imageSource:controller.cardBackSource}]
        preview.obstacle=Qt.rect(1500,720,390,280)
        preview.avoidRects=[Qt.rect(480,866,970,145)]
        preview.protectedRects=[]
        preview.contentRects=[]
    }
    function cleanup() { inspector.previewSource=source; Theme.uiScale=1; Theme.motionEnabled=false }
    function overlaps(a,b) {
        return a.x < b.x+b.width-0.1 && a.x+a.width > b.x+0.1
            && a.y < b.y+b.height-0.1 && a.y+a.height > b.y+0.1
    }
    function assertHardBounds() {
        wait(0)
        waitForRendering(preview)
        tryCompare(preview,"visible",true)
        verify(preview.width > 0 && preview.height > 0)
        verify(preview.x>=0 && preview.y>=0)
        verify(preview.x+preview.width<=viewport.width+0.1)
        verify(preview.y+preview.height<=viewport.height+0.1)
        verify(!overlaps(preview,preview.obstacle),"covered a decision action")
        for (const rect of preview.avoidRects) verify(!overlaps(preview,rect),"covered the hand")
        verify(!overlaps(preview,preview.sourceGeometry.bounds),"covered the inspected source")
    }
    function test_readableCombatContext_data() {
        return [
            {tag:"max-primary",width:1920,height:1011,preference:1,faces:1},
            {tag:"max-scaled",width:1920,height:1011,preference:1.5,faces:1},
            {tag:"max-dfc",width:1920,height:1011,preference:1,faces:2},
            {tag:"max-scaled-dfc",width:1920,height:1011,preference:1.5,faces:2},
            {tag:"compact",width:900,height:620,preference:1.5,faces:1},
            {tag:"compact-dfc",width:900,height:620,preference:1.5,faces:2}]
    }
    function test_readableCombatContext(data) {
        window.width=data.width; window.height=data.height
        Theme.uiScale=Theme.effectiveScale(data.width,data.height,data.preference)
        source.x=data.width*0.42; source.y=data.height*0.61
        source.width=data.width*0.09; source.height=data.height*0.22
        preview.obstacle=Qt.rect(data.width*0.79,data.height*0.7,data.width*0.2,data.height*0.29)
        preview.avoidRects=[Qt.rect(data.width*0.22,data.height*0.85,data.width*0.55,data.height*0.15)]
        preview.protectedRects=[Qt.rect(data.width*0.33,data.height*0.2,data.width*0.34,data.height*0.6)]
        faces.displayFaces=Array.from({length:data.faces},(_,i)=>({name:"Face "+i,imageSource:controller.cardBackSource}))
        wait(0); assertHardBounds()
        verify(preview.placement.faceWidth>=Math.min(180,data.width*0.18))
        if (!preview.placement.fallback) {
            for (const rect of preview.protectedRects) verify(!overlaps(preview,rect))
            compare(preview.z,1000)
        } else {
            compare(preview.z,50)
            verify(preview.placement.faceWidth<=Theme.size(180)+0.1,
                "crowded fallback must not obscure public cards with full-size faces")
        }
        const gallery=findChild(preview,"rulesCardHoverPreviewGallery")
        compare(gallery.faceCount,data.faces)
        for(let i=0;i<data.faces;++i) {
            const art=gallery.faceArt(i)
            verify(art!==null && art.visible)
            tryCompare(art,"status",Image.Ready)
        }
    }
    function test_publicContentAndPhaseRemainVisible() {
        source.x=820; source.y=870; source.width=170; source.height=140
        preview.contentRects=[Qt.rect(20,460,1880,20),Qt.rect(700,240,400,190),Qt.rect(700,560,400,220)]
        assertHardBounds()
        compare(preview.inspectionRequired,false)
        for (const rect of preview.contentRects) verify(!overlaps(preview,rect))
        verify(preview.placement.faceWidth>=180)
    }
    function test_handPreviewPrefersReadableSpaceNearItsSource_data() {
        return [{tag:"single-face",faces:1}, {tag:"two-faces",faces:2},
            {tag:"scaled-summary",faces:1,scaled:true}, {tag:"scaled-two-face-summary",faces:2,scaled:true}]
    }
    function test_handPreviewPrefersReadableSpaceNearItsSource(data) {
        source.x=1100; source.y=900; source.width=130; source.height=180
        preview.obstacle=Qt.rect(1480,840,420,160)
        preview.avoidRects=[Qt.rect(480,880,980,131)]
        preview.contentRects=[Qt.rect(20,500,1880,46),Qt.rect(880,800,180,70),
            Qt.rect(880,30,180,110),Qt.rect(20,20,320,130)]
        if (data.scaled) {
            window.width=2300; window.height=1500; Theme.uiScale=1.5
            source.x=1250; source.y=1400; source.width=180; source.height=240
            preview.obstacle=Qt.rect(1900,1280,350,200)
            preview.avoidRects=[Qt.rect(600,1380,1500,120)]
            preview.contentRects=[Qt.rect(20,700,2260,46),Qt.rect(1050,1290,180,72),
                Qt.rect(1050,30,180,110),Qt.rect(20,20,320,130)]
            inspector.persistentSummary="Linked public card state must not change hover placement."
        }
        faces.displayFaces=Array.from({length:data.faces},(_,i)=>({name:"Face "+i,imageSource:controller.cardBackSource}))
        assertHardBounds()
        compare(preview.inspectionRequired,false)
        verify(preview.placement.faceWidth>=Theme.size(180))
        verify(preview.y>=preview.contentRects[0].y+preview.contentRects[0].height,
            "A readable lower-half candidate must win over a larger remote upper-half preview")
        verify(preview.y+preview.height>=source.y-Theme.size(48),"Preview stays close to the inspected hand card")
        const dx=Math.max(0,preview.x-source.x-source.width,source.x-preview.x-preview.width)
        const dy=Math.max(0,preview.y-source.y-source.height,source.y-preview.y-preview.height)
        verify(Math.hypot(dx,dy)<=Theme.size(132),"Preview must also stay near the source horizontally")
        for (const rect of preview.contentRects) verify(!overlaps(preview,rect))
        compare(findChild(preview,"rulesCardHoverPreviewGallery").faceCount,data.faces)
    }
    function test_unreadableNearbyAreaDoesNotReplaceReadableRemoteArt() {
        source.x=1100; source.y=950; source.width=130; source.height=180
        preview.obstacle=Qt.rect(1480,840,420,160)
        preview.avoidRects=[Qt.rect(480,880,980,131)]
        preview.contentRects=[Qt.rect(0,550,1920,290)]
        assertHardBounds()
        compare(preview.inspectionRequired,false)
        verify(preview.placement.faceWidth>=Theme.size(180))
        verify(preview.y+preview.height<=538,"Use readable remote art when the nearby strip is too short")
    }
    function test_boundedSearchRetainsNearbyReadableArea_data() {
        return [{tag:"ordinary",slivers:false}, {tag:"nearby-unreadable-slivers",slivers:true},
            {tag:"scaled-two-face-summary-slivers",slivers:true,scaled:true}]
    }
    function test_sourceGeometryFollowsAncestorTransforms() {
        const slot=createTemporaryObject(translatedSourceComponent,viewport,{x:700,y:600})
        verify(slot)
        const movingSource=findChild(slot,"translatedPreviewSource")
        inspector.previewSource=movingSource
        assertHardBounds()
        for (const offset of [Qt.point(74,12),Qt.point(0,0)]) {
            slot.glide.x=offset.x; slot.glide.y=offset.y
            tryVerify(()=>{
                const actual=movingSource.mapToItem(viewport,0,0,movingSource.width,movingSource.height)
                const tracked=preview.sourceGeometry.bounds
                return Math.abs(actual.x-tracked.x)<0.1 && Math.abs(actual.y-tracked.y)<0.1
                    && Math.abs(actual.width-tracked.width)<0.1 && Math.abs(actual.height-tracked.height)<0.1
            },1000,"A source must follow the painted ancestor translation in both directions")
            assertHardBounds()
        }
    }
    function test_boundedSearchRetainsNearbyReadableArea(data) {
        source.x=1100; source.y=900; source.width=130; source.height=180
        let near=Qt.rect(1250,560,230,328)
        let remote=Array.from({length:40},(_,i)=>Qt.rect(500+i*12,20,600,480))
        let slivers=data.slivers ? Array.from({length:12},(_,i)=>Qt.rect(1242,900+i,230,20)) : []
        if (data.scaled) {
            window.width=2300; window.height=1500; Theme.uiScale=1.5
            source.x=1250; source.y=1400; source.width=180; source.height=240
            faces.displayFaces=Array.from({length:2},(_,i)=>({name:"Face "+i,imageSource:controller.cardBackSource}))
            inspector.persistentSummary="Linked public card state must not resize either printed face."
            near=Qt.rect(1450,820,820,550)
            remote=Array.from({length:12},(_,i)=>Qt.rect(400+i*12,20,1100,750))
            slivers=Array.from({length:12},(_,i)=>Qt.rect(1448,1400+i,820,30))
        }
        const areas=slivers.concat(remote,[near])
        tryVerify(()=>preview.sourceGeometry.bounds.x===source.x && preview.sourceGeometry.bounds.y===source.y,
            1000,"Wait for the source map before directly probing the candidate search")
        verify(preview.fitAreas(areas).y>=near.y,"The unbounded candidates contain readable nearby art")
        const kept=preview.boundedAreas(areas)
        verify(kept.length<=24)
        verify(kept.includes(near),"Readable space near the hand must survive the bounded search")
        const fitted=preview.fitAreas(kept)
        verify(fitted.y>=near.y && fitted.faceWidth>=Theme.size(180))
        verify(fitted.x+fitted.size.width<=near.x+near.width+0.1)
    }
    function test_crowdedPublicContentOffersReadableInspection() {
        window.width=900; window.height=620
        source.x=40; source.y=490; source.width=100; source.height=40
        preview.obstacle=Qt.rect(0,0,0,0); preview.avoidRects=[]
        preview.contentRects=[Qt.rect(0,0,720,470),Qt.rect(0,550,900,70)]
        wait(0); assertHardBounds()
        compare(preview.inspectionRequired,true)
        compare(preview.inspectionIconOnly,false,"Keep the complete label whenever it fits")
        verify(preview.gallerySize.width<180)
        const button=findChild(preview,"rulesCardHoverInspect")
        verify(button.visible && button.enabled)
        compare(button.width,button.implicitWidth)
        verify(!findChild(preview,"rulesCardHoverPreviewGallery").visible)
        for (const rect of preview.contentRects) verify(!overlaps(preview,rect))
        mouseClick(button)
        compare(controller.inspectedId,"card")
        preview.contentRects=[]
        tryCompare(preview,"inspectionRequired",false)
        verify(findChild(preview,"rulesCardHoverPreviewGallery").visible)
    }
    function test_fullSizePreservedWithoutCombat() {
        source.x=20; source.y=50; source.width=100; source.height=140
        assertHardBounds()
        compare(preview.width,Theme.size(360))
        verify(preview.x>=source.x+source.width)
        compare(preview.placement.fallback,false)
    }
    function test_noCompleteIconSpaceKeepsSourceAvailableWithoutOverlay() {
        window.width=900; window.height=620; Theme.uiScale=1.5
        source.x=40; source.y=490; source.width=100; source.height=40
        preview.obstacle=Qt.rect(0,0,0,0); preview.avoidRects=[]
        preview.contentRects=[Qt.rect(0,0,900,470),Qt.rect(0,550,900,70)]
        waitForRendering(preview)
        tryCompare(preview,"inspectionRequired",true)
        compare(preview.visible,false)
        compare(preview.width,0)
        compare(preview.height,0)
        compare(inspector.previewCardId,"card")
        verify(source.visible && source.enabled)
        verify(preview.freeAreas(false).every(area=>area.width<preview.inspectionIconSize
            || area.height<preview.inspectionIconSize))
        compare(controller.inspectedId,"")
        // Restore space without re-entering the source: the same inspection
        // becomes available rather than leaving stale zero-size placement.
        preview.contentRects=[]
        tryCompare(preview,"visible",true)
        compare(inspector.previewCardId,"card")
        assertHardBounds()
    }
    function test_inspectionIconFitsWhenCompleteLabelCannot_data() {
        return [{tag:"public", hidden:false}, {tag:"concealed-after-dfc", hidden:true}]
    }
    function test_inspectionIconFitsWhenCompleteLabelCannot(data) {
        window.width=900; window.height=620; Theme.uiScale=1.5
        source.x=40; source.y=490; source.width=100; source.height=40
        preview.obstacle=Qt.rect(0,0,0,0); preview.avoidRects=[]
        preview.contentRects=[Qt.rect(0,0,720,470),Qt.rect(0,550,900,70)]
        faces.displayFaces=[{name:"Public front",imageSource:controller.cardBackSource},
                            {name:"Public back",imageSource:controller.cardBackSource}]
        inspector.hasIdentity=!data.hidden
        assertHardBounds()
        verify(preview.freeAreas(false).every(area=>area.width<preview.inspectionButtonWidth
            || area.height<Theme.controlHeight))
        compare(preview.inspectionRequired,true)
        compare(preview.inspectionIconOnly,true)
        compare(preview.width,Theme.size(38))
        compare(preview.height,Theme.size(38))
        for(const rect of preview.contentRects) verify(!overlaps(preview,rect))
        const button=findChild(preview,"rulesCardHoverInspect")
        verify(button.visible && button.enabled)
        compare(button.accessibleName,"Inspect card")
        compare(button.ToolTip.text,"Inspect card")
        verify(findChild(preview,"rulesCardHoverInspectIcon").visible)
        verify(!findChild(preview,"rulesCardHoverPreviewGallery").visible)
        mouseMove(button)
        wait(400)
        mouseClick(button)
        compare(controller.inspectedId,"card")
        controller.roomConnected=false
        tryCompare(preview,"visible",false)
        compare(inspector.previewCardId,"")
    }
    function test_inspectionHintAvoidsCombatAndStaysAboveArrows_data() {
        return [{tag:"clear-space", blocked:false}, {tag:"cross-board-arrows", blocked:true}]
    }
    function test_inspectionHintAvoidsCombatAndStaysAboveArrows(data) {
        window.width=900; window.height=620
        source.x=40; source.y=490; source.width=100; source.height=40
        preview.obstacle=Qt.rect(0,0,0,0); preview.avoidRects=[]
        preview.contentRects=[Qt.rect(0,0,720,470),Qt.rect(0,550,900,70)]
        preview.protectedRects=[data.blocked ? Qt.rect(0,0,900,620) : Qt.rect(150,475,400,65)]
        inspector.persistentSummary="Exiled with this card: Grizzly Bears"
        assertHardBounds()
        compare(preview.inspectionRequired,true)
        for (const rect of preview.contentRects) verify(!overlaps(preview,rect))
        compare(overlaps(preview,preview.protectedRects[0]),data.blocked)
        compare(preview.placement.fallback,data.blocked)
        compare(preview.z,1000,"Combat arrows must not cross the inspection button text")
        const hint=findChild(preview,"rulesCardHoverInspect")
        verify(hint.visible)
        compare(hint.height,Theme.controlHeight)
        compare(preview.height,hint.height,"State metadata must not expand the inspection button")
        mouseClick(hint)
        compare(controller.inspectedId,"card")
    }
    function test_sourceKeepsAdjacentPlacementBesideDock() {
        window.width=1100; window.height=850
        source.x=600; source.y=400; source.width=100; source.height=140
        preview.obstacle=Qt.rect(720,100,360,480)
        preview.avoidRects=[Qt.rect(100,600,900,250)]
        assertHardBounds()
        verify(preview.x+preview.width<=source.x || preview.y+preview.height<=source.y
            || preview.x>=source.x+source.width || preview.y>=source.y+source.height)
    }
    function test_crossBoardHullsUseReadableFallback() {
        preview.protectedRects=[Qt.rect(0,0,1920,860),Qt.rect(10,10,1890,850)]
        assertHardBounds()
        compare(preview.placement.fallback,true)
        compare(preview.z,50)
        verify(preview.placement.faceWidth>=180)
        verify(preview.placement.faceWidth<=Theme.size(180)+0.1)
        verify(overlaps(preview,preview.protectedRects[0]),"fallback must relax hulls, not hard hand/source/action bounds")
    }
    function test_crossBoardFallbackCapsFaces_data() {
        return [{tag:"normal-single",scale:1,faces:1},
                {tag:"normal-dfc",scale:1,faces:2},
                {tag:"scaled-single",scale:1.8,faces:1},
                {tag:"scaled-dfc",scale:1.8,faces:2}]
    }
    function test_crossBoardFallbackCapsFaces(data) {
        Theme.uiScale=data.scale
        faces.displayFaces=Array.from({length:data.faces},(_,i)=>({name:"Face "+i,imageSource:controller.cardBackSource}))
        preview.protectedRects=[Qt.rect(0,0,1920,860),Qt.rect(10,10,1890,850)]
        wait(0); assertHardBounds()
        compare(preview.placement.fallback,true)
        compare(preview.z,50)
        compare(preview.placement.faceWidth,Theme.size(180))
        verify(preview.width<=Theme.size(180)*data.faces+(data.faces-1)*Theme.size(8)+0.1)
        // The former 360-unit fallback fails this geometry cap. Ordinary
        // inspection keeps that larger limit in its independent regression.
        verify(preview.height<=Theme.size(180)*88/63+0.1)
        const preferred=preview.fitAreas(preview.freeAreas(true))
        verify(preview.placement.faceWidth>preferred.faceWidth,
            "fallback cannot replace a more readable preferred placement")
    }
    function test_sameInspectionTracksHandDockAndCombatMovement() {
        source.x=300; source.y=300
        assertHardBounds()
        const before=Qt.point(preview.x,preview.y)
        preview.protectedRects=[Qt.rect(preview.x-2,preview.y-2,preview.width+4,preview.height+4)]
        tryVerify(()=>Math.abs(preview.x-before.x)>1 || Math.abs(preview.y-before.y)>1)
        assertHardBounds()
        preview.avoidRects=[Qt.rect(preview.x-2,preview.y-2,preview.width+4,preview.height+4)]
        assertHardBounds()
        preview.obstacle=Qt.rect(preview.x-2,preview.y-2,preview.width+4,preview.height+4)
        assertHardBounds()
        preview.protectedRects=[]
        assertHardBounds()
        compare(inspector.previewCardId,"card")
    }
    function test_manyRelationshipsKeepSearchBounded() {
        preview.protectedRects=Array.from({length:100},(_,i)=>Qt.rect(250+(i%10)*85,100+Math.floor(i/10)*60,120,160))
        assertHardBounds()
        verify(preview.freeAreas(true).length<=24)
        verify(preview.freeAreas(false).length<=24)
        verify(preview.placement.faceWidth>=180)
    }
    function test_summariesDoNotChangeArtOnlyPreview_data() {
        return [
            {tag:"chinese-single-line",summary:"本回合进场",scale:1,faces:1},
            {tag:"english-single-line",summary:"Entered this turn",scale:1,faces:1},
            {tag:"scaled-chinese",summary:"本回合进场",scale:1.8,faces:1},
            {tag:"scaled-english",summary:"Entered this turn",scale:1.8,faces:1},
            {tag:"two-lines",summary:"Entered this turn\nSummoning sickness",scale:1,faces:1},
            {tag:"long-summary",summary:"Linked public card metadata that wraps over several lines. ".repeat(20),scale:1,faces:1},
            {tag:"small-chinese",summary:"本回合进场，关联的公开卡牌状态。".repeat(20),scale:0.75,faces:1},
            {tag:"large-chinese",summary:"本回合进场，关联的公开卡牌状态。".repeat(20),scale:1.8,faces:1},
            {tag:"scaled-two-face",summary:"Linked public card metadata that wraps over several lines. ".repeat(20),scale:1.5,faces:2}]
    }
    function test_summariesDoNotChangeArtOnlyPreview(data) {
        Theme.uiScale=data.scale
        faces.displayFaces=Array.from({length:data.faces},(_,i)=>({name:"Face "+i,imageSource:controller.cardBackSource}))
        assertHardBounds()
        compare(preview.inspectionRequired,false)
        const gallery=findChild(preview,"rulesCardHoverPreviewGallery")
        const bounds=Qt.rect(preview.x,preview.y,preview.width,preview.height)
        for (const summary of [data.summary,"本回合进场",""]) {
            inspector.persistentSummary=summary
            wait(0)
            compare(Qt.rect(preview.x,preview.y,preview.width,preview.height),bounds,
                "Adding, replacing or clearing state metadata must not resize or reposition hover art")
            compare(preview.width,gallery.width)
            compare(preview.height,gallery.height,"The hover frame must end with the complete card images")
            compare(gallery.faceCount,data.faces)
            compare(findChild(preview,"rulesCardHoverLinkedCards"),null,
                "Persistent state belongs on the battlefield card and pinned inspector, not below hover art")
            for (let index=0;index<data.faces;++index) {
                const art=gallery.faceArt(index)
                verify(art!==null && art.visible)
                tryCompare(art,"status",Image.Ready)
                const end=art.mapToItem(preview,art.width,art.height)
                verify(end.x<=preview.width+0.1 && end.y<=preview.height+0.1,
                    "Removing the metadata footer must retain every complete card face")
            }
        }
    }
    function test_multiFaceSummaryAndHiddenTransition() {
        faces.displayFaces=[{name:"Public front",imageSource:controller.cardBackSource},
                            {name:"Public back",imageSource:controller.cardBackSource}]
        inspector.persistentSummary="Linked public card metadata that wraps over several lines. ".repeat(5)
        preview.protectedRects=[Qt.rect(680,210,450,580)]
        assertHardBounds()
        const gallery=findChild(preview,"rulesCardHoverPreviewGallery")
        verify(gallery.visible)
        compare(gallery.faceCount,2)
        compare(preview.height,gallery.height)
        const publicBounds=Qt.rect(preview.x,preview.y,preview.width,preview.height)
        inspector.hasIdentity=false
        assertHardBounds()
        compare(preview.gallerySize.columns,1)
        verify(Math.abs(preview.height/preview.width-88/63)<0.001)
        verify(!gallery.visible)
        const hiddenArt=findChild(preview,"rulesCardHoverPreviewArt")
        verify(hiddenArt.visible)
        compare(hiddenArt.source,controller.cardBackSource)
        compare(hiddenArt.height,preview.height)
        const hiddenBounds=Qt.rect(preview.x,preview.y,preview.width,preview.height)
        for (const summary of ["", "本回合进场"]) {
            inspector.persistentSummary=summary
            wait(0)
            compare(Qt.rect(preview.x,preview.y,preview.width,preview.height),hiddenBounds,
                "A concealed card must stay one complete back regardless of stale state metadata")
            compare(findChild(preview,"rulesCardHoverLinkedCards"),null)
        }
        inspector.hasIdentity=true
        assertHardBounds()
        verify(gallery.visible)
        compare(preview.height,gallery.height)
        compare(Qt.rect(preview.x,preview.y,preview.width,preview.height),publicBounds)
        controller.roomConnected=false
        tryCompare(preview,"visible",false)
        compare(inspector.previewCardId,"")
    }
    function test_summariesDoNotChangeInspectionHint_data() {
        return [{tag:"public",hidden:false},{tag:"concealed",hidden:true}]
    }
    function test_summariesDoNotChangeInspectionHint(data) {
        window.width=900; window.height=620
        source.x=40; source.y=490; source.width=100; source.height=40
        preview.obstacle=Qt.rect(0,0,0,0); preview.avoidRects=[]
        preview.contentRects=[Qt.rect(0,0,720,470),Qt.rect(0,550,900,70)]
        inspector.hasIdentity=!data.hidden
        assertHardBounds()
        compare(preview.inspectionRequired,true)
        const hint=findChild(preview,"rulesCardHoverInspect")
        const bounds=Qt.rect(preview.x,preview.y,preview.width,preview.height)
        for (const summary of ["本回合进场","Public state metadata. ".repeat(30),""]) {
            inspector.persistentSummary=summary
            wait(0)
            compare(preview.inspectionRequired,true)
            compare(Qt.rect(preview.x,preview.y,preview.width,preview.height),bounds)
            compare(preview.height,hint.height)
            verify(hint.visible && hint.enabled)
            verify(!findChild(preview,"rulesCardHoverPreviewGallery").visible)
            compare(findChild(preview,"rulesCardHoverLinkedCards"),null)
        }
        mouseClick(hint)
        compare(controller.inspectedId,"card")
    }
}
