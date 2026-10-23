// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/components"
TestCase {
    id: testCase
    name: "TablePhaseBinding"
    when: windowShown
    ApplicationWindow { id: window; width:500; height:500; visible:true }
    QtObject { id: session; property string currentPhase:"main_1"; property int activeSeat:0 }
    QtObject {
        id: controller
        property var gameSession:session
        readonly property string displayedPhase:session.currentPhase
        property var roomSession:({seatIndex:0})
        property bool isActivePlayer:true
        property bool canAct:true
        property var ownSeatData:({libraryCount:20})
        property int submittedActions:0
        property string lastPhase:""
        property var seatState:({seatData:seat=>({displayName:"Probe Player",responseStatus:"",libraryCount:20})})
        property var landPlay:({displayedCount:0,adjustCount:delta=>submittedActions++})
        property var rulesAssist:({requestSetPhase:phase=>{ lastPhase=phase; submittedActions++ },requestAdvancePhase:()=>submittedActions++,requestAdvanceTurn:()=>submittedActions++})
        property var gameValues:({hasTappedOwnPermanent:()=>false,hasUntappedDeclaredAttacker:()=>false,
            untapOwnBattlefield:()=>submittedActions++,tapDeclaredAttackers:()=>submittedActions++})
        property var wsModel:({drawCards:n=>submittedActions++,setResponseStatus:status=>submittedActions++})
    }
    function init() { session.currentPhase="main_1";controller.submittedActions=0;controller.lastPhase="";testTranslations.setLanguage("zh"); window.requestActivate();tryCompare(window,"active",true) }
    function cleanup() { testTranslations.setLanguage("en"); Theme.uiScale=1; window.height=500 }
    Component { id: barComponent; TableTurnBar { width:220; height:300; tableController:controller } }
    function makeBar() {
        const strip=createTemporaryObject(barComponent,window.contentItem)
        verify(strip!==null);verify(waitForPolish(window))
        const selector=findChild(strip,"compactPhaseSelector")
        verify(selector!==null);verify(selector.visible)
        tryCompare(selector,"currentIndex",3)
        return {strip:strip,selector:selector}
    }
    function assertPhase(value, phase) {
        const index=value.strip.phaseSteps.findIndex(row=>row.id===phase)
        tryCompare(value.selector,"currentIndex",index)
        compare(value.selector.displayText,I18n.tr(value.strip.phaseSteps[index].label))
        compare(session.currentPhase,phase)
        compare(controller.displayedPhase,phase)
    }
    function test_languageChangesKeepActualPhaseWithoutActions() {
        const value=makeBar()
        for (const language of ["en","de","zh","en","zh"]) {
            testTranslations.setLanguage(language)
            verify(waitForPolish(window))
            assertPhase(value,"main_1")
            compare(controller.submittedActions,0,"Retranslation is presentation only")
        }
        for (const phase of ["upkeep","draw","declare_attackers","main_2","end","main_1"]) {
            session.currentPhase=phase
            verify(waitForPolish(window))
            assertPhase(value,phase)
            compare(controller.submittedActions,0,"Snapshot phase changes are not user commands")
        }
    }
    function test_userActivationAfterLanguageChangeSubmitsOnce() {
        const value=makeBar(), selector=value.selector
        testTranslations.setLanguage("en");verify(waitForPolish(window))
        assertPhase(value,"main_1")
        selector.forceActiveFocus();tryCompare(selector,"activeFocus",true)
        mouseClick(selector);tryCompare(selector.popup,"opened",true)
        keyClick(Qt.Key_End);keyClick(Qt.Key_Return)
        tryCompare(controller,"submittedActions",1)
        compare(controller.lastPhase,"end")
        compare(session.currentPhase,"main_1","A request alone does not mutate the authoritative phase")
        session.currentPhase="end";verify(waitForPolish(window))
        assertPhase(value,"end")
        testTranslations.setLanguage("de");verify(waitForPolish(window))
        assertPhase(value,"end");compare(controller.submittedActions,1)
    }
    function test_resizeScaleAndLanguageTransitionsArePresentationOnly() {
        const value = makeBar()
        session.currentPhase = "main_2"
        const states = [
            {height: 561, scale: 1, language: "zh", selector: false},
            {height: 500, scale: 1, language: "en", selector: true},
            {height: 561, scale: 1.35, language: "de", selector: true},
            {height: 561, scale: 1, language: "de", selector: false},
            {height: 1000, scale: 1, language: "en", selector: false},
            {height: 300, scale: 1, language: "zh", selector: true}]
        for (const state of states) {
            Theme.uiScale = state.scale
            window.height = state.height
            value.strip.height = window.height
            testTranslations.setLanguage(state.language)
            verify(waitForPolish(window))
            compare(value.selector.visible, state.selector, "Navigation mode after " + JSON.stringify(state))
            assertPhase(value, "main_2")
            compare(controller.submittedActions, 0,
                    "Resizing, scaling and retranslation must not submit a phase command")
        }
        value.selector.forceActiveFocus()
        tryCompare(value.selector, "activeFocus", true)
        mouseClick(value.selector)
        tryCompare(value.selector.popup, "opened", true)
        keyClick(Qt.Key_End)
        keyClick(Qt.Key_Return)
        tryCompare(controller, "submittedActions", 1)
        compare(controller.lastPhase, "end")
        compare(session.currentPhase, "main_2", "Selection waits for authoritative confirmation")
    }
}
