// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../qml/screens"
import "../../qml/components"

TestCase {
    name: "AudioSettings"
    when: windowShown

    ApplicationWindow {
        id: window
        width: 1280
        height: 800
        visible: true
        function popScreen() { }
    }
    QtObject {
        id: audioPrefs
        property bool audioEnabled: true
        property real audioVolume: 0.35
        property bool musicEnabled: true
        property real musicVolume: 0.20
        property string musicTrack: "gitana"
        property string lastError: ""
    }
    QtObject {
        id: musicBackend
        property var tracks: [{id: "gitana", title: "Gitana"}]
    }
    QtObject {
        id: audioBackend
        property var cues: []
        function preview(cue) { cues = cues.concat([cue]) }
    }
    SignalSpy { id: volumeChanges; target: audioPrefs; signalName: "audioVolumeChanged" }
    SignalSpy { id: musicVolumeChanges; target: audioPrefs; signalName: "musicVolumeChanged" }
    Component { id: pageComponent; AudioSettings { settings: audioPrefs; music: musicBackend } }
    property var page: null
    property var oldBackend: null

    function init() {
        testTranslations.setLanguage("en")
        Theme.uiScale = 1
        window.width = 1280
        window.height = 800
        audioPrefs.audioEnabled = true
        audioPrefs.audioVolume = 0.35
        audioPrefs.musicEnabled = true
        audioPrefs.musicVolume = 0.20
        audioPrefs.musicTrack = "gitana"
        musicBackend.tracks = [{id: "gitana", title: "Gitana"}]
        audioPrefs.lastError = ""
        audioBackend.cues = []
        oldBackend = SoundEffects.backend
        SoundEffects.backend = audioBackend
        page = pageComponent.createObject(window.contentItem)
        verify(page !== null)
        page.anchors.fill = window.contentItem
        waitForRendering(page)
        volumeChanges.clear()
        musicVolumeChanges.clear()
    }
    function cleanup() {
        page.destroy()
        page = null
        SoundEffects.backend = oldBackend
        oldBackend = null
        Theme.uiScale = 1
        testTranslations.setLanguage("en")
    }
    function test_muteRetainsVolumeAndDisablesPreviews() {
        const mute = findChild(page, "settingsAudioMute")
        const volume = findChild(page, "settingsAudioVolume")
        const draw = findChild(page, "settingsAudioPreviewDraw")
        mouseClick(draw)
        compare(audioBackend.cues, ["draw"])
        mouseClick(mute)
        verify(!audioPrefs.audioEnabled)
        verify(mute.checked)
        compare(audioPrefs.audioVolume, 0.35)
        verify(!draw.enabled)
        mouseClick(draw)
        compare(audioBackend.cues.length, 1)
        mouseClick(mute)
        verify(audioPrefs.audioEnabled)
        verify(!mute.checked)
        compare(volume.value, 0.35)
        mouseClick(findChild(page, "settingsAudioPreviewCast"))
        mouseClick(findChild(page, "settingsAudioPreviewTurn"))
        compare(audioBackend.cues, ["draw", "cast", "turn"])
        audioPrefs.audioVolume = 0
        verify(!draw.enabled)
        verify(!findChild(page, "settingsAudioPreviewCast").enabled)
        verify(!findChild(page, "settingsAudioPreviewTurn").enabled)
    }
    function test_allCuesCanBeAuditionedAndMuted() {
        const cues = ["click", "select", "draw", "play", "tap", "shuffle", "attack",
                      "block", "cast", "resolve", "turn", "damage", "confirm", "cancel", "error"]
        const body = findChild(page, "settingsBody").contentItem
        for (const cue of cues) {
            const button = findChild(page, "settingsAudioPreview"
                                     + cue.charAt(0).toUpperCase() + cue.slice(1))
            verify(button !== null, cue)
            const y = button.mapToItem(body.contentItem, 0, 0).y
            body.contentY = Math.max(0, Math.min(y, body.contentHeight - body.height))
            waitForRendering(page)
            mouseClick(button)
            compare(audioBackend.cues[audioBackend.cues.length - 1], cue)
            audioPrefs.audioEnabled = false
            verify(!button.enabled)
            mouseClick(button)
            audioPrefs.audioEnabled = true
            audioPrefs.audioVolume = 0
            verify(!button.enabled)
            mouseClick(button)
            audioPrefs.audioVolume = 0.35
        }
        compare(audioBackend.cues, cues)
        verify(audioPrefs.musicEnabled)
        compare(audioPrefs.musicVolume, 0.20)
        compare(audioPrefs.musicTrack, "gitana")
        page.soundPreviewEnabled = false
        verify(!findChild(page, "settingsAudioPreviews").visible)
        verify(!findChild(page, "settingsAudioPreviewHint").visible)
        verify(findChild(page, "settingsAudioVolume").visible)
        verify(findChild(page, "settingsMusicMute").visible)
    }
    function test_dragCommitsOnceAndKeyboardUpdatesVolume() {
        const slider = findChild(page, "settingsAudioVolume")
        mousePress(slider, slider.width * 0.35, slider.height / 2)
        mouseMove(slider, slider.width * 0.6, slider.height / 2)
        mouseMove(slider, slider.width * 0.8, slider.height / 2)
        compare(audioPrefs.audioVolume, 0.35)
        compare(volumeChanges.count, 0)
        verify(slider.value > 0.75)
        mouseRelease(slider, slider.width * 0.8, slider.height / 2)
        compare(volumeChanges.count, 1)
        compare(audioPrefs.audioVolume, slider.value)
        const previous = slider.value
        window.requestActivate()
        tryCompare(window, "active", true)
        slider.forceActiveFocus()
        waitForRendering(slider)
        tryCompare(window, "activeFocusItem", slider)
        keyPress(Qt.Key_Left)
        verify(slider.pressed, "Keyboard press reaches the focused slider")
        verify(slider.value < previous, "Keyboard press lowers the current slider value")
        keyRelease(Qt.Key_Left)
        verify(audioPrefs.audioVolume < previous,
                JSON.stringify({previous:previous, preference:audioPrefs.audioVolume,
                                value:slider.value, pressed:slider.pressed,
                                focus:slider.activeFocus, changes:volumeChanges.count}))
        compare(audioPrefs.audioVolume, slider.value)
        compare(volumeChanges.count, 2)
        compare(findChild(page, "settingsAudioVolumeValue").text,
                Math.round(slider.value * 100) + "%")
        audioPrefs.audioVolume = 0.2
        compare(slider.value, 0.2)
        audioPrefs.audioEnabled = false
        verify(findChild(page, "settingsAudioMute").checked)
    }
    function scrollToMusic() {
        const body = findChild(page, "settingsBody").contentItem
        body.contentY = Math.max(0, body.contentHeight - body.height)
        waitForRendering(page)
    }
    function test_musicMuteIsIndependentAndRetainsVolume() {
        const soundMute = findChild(page, "settingsAudioMute")
        mouseClick(soundMute)
        verify(!audioPrefs.audioEnabled)
        verify(audioPrefs.musicEnabled)
        mouseClick(soundMute)
        scrollToMusic()
        const musicMute = findChild(page, "settingsMusicMute")
        mouseClick(musicMute)
        verify(!audioPrefs.musicEnabled)
        verify(musicMute.checked)
        verify(audioPrefs.audioEnabled)
        compare(audioPrefs.musicVolume, 0.20)
        verify(findChild(page, "settingsAudioPreviewTurn").enabled)
        mouseClick(musicMute)
        verify(audioPrefs.musicEnabled)
        verify(!musicMute.checked)
        compare(audioPrefs.musicVolume, 0.20)
        compare(audioPrefs.audioVolume, 0.35)
        audioPrefs.musicEnabled = false
        verify(musicMute.checked)
    }
    function test_musicVolumeCommitsOnReleaseAndPreservesEffectsVolume() {
        scrollToMusic()
        const slider = findChild(page, "settingsMusicVolume")
        mousePress(slider, slider.width * 0.2, slider.height / 2)
        mouseMove(slider, slider.width * 0.4, slider.height / 2)
        mouseMove(slider, slider.width * 0.6, slider.height / 2)
        compare(audioPrefs.musicVolume, 0.20)
        compare(musicVolumeChanges.count, 0)
        verify(slider.value > 0.55)
        mouseRelease(slider, slider.width * 0.6, slider.height / 2)
        compare(musicVolumeChanges.count, 1)
        compare(audioPrefs.musicVolume, slider.value)
        compare(audioPrefs.audioVolume, 0.35)
        compare(volumeChanges.count, 0)
        const previous = slider.value
        window.requestActivate()
        tryCompare(window, "active", true)
        slider.forceActiveFocus()
        waitForRendering(slider)
        tryCompare(window, "activeFocusItem", slider)
        keyPress(Qt.Key_Left)
        compare(musicVolumeChanges.count, 1)
        keyRelease(Qt.Key_Left)
        compare(musicVolumeChanges.count, 2)
        verify(audioPrefs.musicVolume < previous)
        compare(audioPrefs.musicVolume, slider.value)
        compare(findChild(page, "settingsMusicVolumeValue").text,
                Math.round(slider.value * 100) + "%")
        audioPrefs.musicVolume = 0.12
        compare(slider.value, 0.12)
    }
    function test_trackSelectionSupportsMoreTracksAndExternalUpdates() {
        scrollToMusic()
        const selector = findChild(page, "settingsMusicTrack")
        compare(selector.currentText, "Gitana")
        compare(selector.count, 1)
        musicBackend.tracks = [{id: "gitana", title: "Gitana"},
                               {id: "next-track", title: "Next Track"}]
        tryCompare(selector, "count", 2)
        selector.currentIndex = 1
        selector.activated(1)
        compare(audioPrefs.musicTrack, "next-track")
        compare(selector.currentText, "Next Track")
        audioPrefs.musicTrack = "gitana"
        compare(selector.currentIndex, 0)
        compare(selector.currentText, "Gitana")
        compare(audioPrefs.audioVolume, 0.35)
        verify(audioPrefs.musicEnabled)
    }
    function test_localizedCompactLayout_data() {
        return [{tag: "english", language: "en", scale: 1},
                {tag: "chinese-large", language: "zh", scale: 1.5}]
    }
    function test_localizedCompactLayout(data) {
        window.width = 900
        window.height = 620
        Theme.uiScale = data.scale
        testTranslations.setLanguage(data.language)
        waitForRendering(page)
        compare(findChild(page, "settingsAudioMute").text,
                data.language === "zh" ? "静音" : "Mute sound effects")
        compare(findChild(page, "settingsMusicMute").text,
                data.language === "zh" ? "静音背景音乐" : "Mute background music")
        const controls = ["settingsAudioVolume", "settingsMusicTrack", "settingsMusicMute",
                          "settingsMusicVolume"]
        for (const entry of page.previewCues)
            controls.push("settingsAudioPreview" + entry.cue.charAt(0).toUpperCase()
                          + entry.cue.slice(1))
        for (const name of controls) {
            const control = findChild(page, name)
            const point = control.mapToItem(page, 0, 0)
            verify(control.width > 0)
            verify(point.x >= 0 && point.x + control.width <= page.width, name)
        }
        audioPrefs.lastError = "Could not save settings."
        const error = findChild(page, "settingsAudioError")
        verify(error.visible)
        verify(error.message.length > 0)
    }
}
