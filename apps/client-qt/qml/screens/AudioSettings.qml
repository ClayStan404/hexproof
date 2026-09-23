// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "../components"

Page {
    id: root
    objectName: "audioSettingsScreen"
    property var settings: preferences
    property var music: backgroundMusic
    readonly property bool canPreview: settings.audioEnabled && settings.audioVolume > 0
    // Temporary audition catalog; disable after the replacement sound pack is finalized.
    property bool soundPreviewEnabled: true
    readonly property var previewCues: [
        {cue: "click", title: qsTr("Button click")},
        {cue: "select", title: qsTr("Select a card")},
        {cue: "draw", title: qsTr("Draw a card")},
        {cue: "play", title: qsTr("Play a card")},
        {cue: "tap", title: qsTr("Tap / untap")},
        {cue: "shuffle", title: qsTr("Shuffle")},
        {cue: "attack", title: qsTr("Declare an attacker")},
        {cue: "block", title: qsTr("Assign a blocker")},
        {cue: "cast", title: qsTr("Cast a spell")},
        {cue: "resolve", title: qsTr("Resolve a spell / ability")},
        {cue: "turn", title: qsTr("Your turn")},
        {cue: "damage", title: qsTr("Life loss")},
        {cue: "confirm", title: qsTr("Confirm")},
        {cue: "cancel", title: qsTr("Cancel")},
        {cue: "error", title: qsTr("Error")}
    ]
    background: AppBackground { }

    function saveVolume() {
        settings.audioVolume = volumeSlider.value
        volumeSlider.value = Qt.binding(function() { return root.settings.audioVolume })
    }

    function saveMusicVolume() {
        settings.musicVolume = musicVolumeSlider.value
        musicVolumeSlider.value = Qt.binding(function() { return root.settings.musicVolume })
    }

    function musicTrackIndex() {
        for (let index = 0; index < music.tracks.length; ++index) {
            if (music.tracks[index].id === settings.musicTrack)
                return index
        }
        return music.tracks.length > 0 ? 0 : -1
    }

    SettingsPage {
        anchors.fill: parent
        title: qsTr("Audio")
        subtitle: qsTr("Soft card sounds and brief magic accents for long games")

        Surface {
            Layout.fillWidth: true
            implicitHeight: audioContent.implicitHeight + Theme.size(48)
            elevated: true

            ColumnLayout {
                id: audioContent
                anchors.fill: parent
                anchors.margins: Theme.size(24)
                spacing: Theme.size(16)

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Operation sounds")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(20)
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }

                AppToggle {
                    objectName: "settingsAudioMute"
                    Layout.fillWidth: true
                    text: qsTr("Mute sound effects")
                    checked: !root.settings.audioEnabled
                    onToggled: {
                        root.settings.audioEnabled = !checked
                        checked = Qt.binding(function() { return !root.settings.audioEnabled })
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: qsTr("Volume")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(14)
                    }
                    Text {
                        objectName: "settingsAudioVolumeValue"
                        textFormat: Text.PlainText
                        text: Math.round(volumeSlider.value * 100) + "%"
                        color: Theme.primary
                        font.pixelSize: Theme.fontSize(16)
                        font.weight: Font.DemiBold
                    }
                }

                Slider {
                    id: volumeSlider
                    objectName: "settingsAudioVolume"
                    Layout.fillWidth: true
                    from: 0
                    to: 1
                    stepSize: 0.01
                    value: root.settings.audioVolume
                    implicitHeight: Theme.size(32)
                    Accessible.name: qsTr("Sound effects volume")
                    // Persist each pointer or key gesture on release instead of every drag update.
                    onPressedChanged: if (!pressed) root.saveVolume()
                    onMoved: if (!pressed) root.saveVolume()
                    background: Rectangle {
                        x: volumeSlider.leftPadding
                        y: volumeSlider.topPadding + (volumeSlider.availableHeight - height) / 2
                        width: volumeSlider.availableWidth
                        height: Theme.size(4)
                        radius: height / 2
                        color: Theme.surfaceMuted
                        Rectangle {
                            width: volumeSlider.visualPosition * parent.width
                            height: parent.height
                            radius: height / 2
                            color: Theme.primaryStrong
                        }
                    }
                    handle: Rectangle {
                        x: volumeSlider.leftPadding
                           + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                        y: volumeSlider.topPadding + (volumeSlider.availableHeight - height) / 2
                        implicitWidth: Theme.size(20)
                        implicitHeight: Theme.size(20)
                        radius: width / 2
                        color: volumeSlider.pressed ? Theme.primaryStrong : Theme.primary
                        border.width: volumeSlider.activeFocus ? Theme.size(2) : 0
                        border.color: Theme.text
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    visible: root.soundPreviewEnabled
                    text: qsTr("Preview all sound effects (%1)").arg(root.previewCues.length)
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(14)
                    font.weight: Font.DemiBold
                }

                Text {
                    objectName: "settingsAudioPreviewHint"
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    visible: root.soundPreviewEnabled
                    text: root.canPreview
                          ? qsTr("Click a sound to listen. Each preview stops the previous sound.")
                          : qsTr("Unmute sound effects and raise the volume to preview.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(14)
                    wrapMode: Text.WordWrap
                }

                Flow {
                    objectName: "settingsAudioPreviews"
                    Layout.fillWidth: true
                    visible: root.soundPreviewEnabled
                    spacing: Theme.size(10)
                    Repeater {
                        model: root.previewCues
                        AppButton {
                            required property var modelData
                            objectName: "settingsAudioPreview"
                                        + modelData.cue.charAt(0).toUpperCase()
                                        + modelData.cue.slice(1)
                            text: modelData.title
                            enabled: root.canPreview
                            onClicked: SoundEffects.preview(modelData.cue)
                        }
                    }
                }

            }
        }

        Surface {
            Layout.fillWidth: true
            implicitHeight: musicContent.implicitHeight + Theme.size(48)
            elevated: true

            ColumnLayout {
                id: musicContent
                anchors.fill: parent
                anchors.margins: Theme.size(24)
                spacing: Theme.size(16)

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Background music")
                    color: Theme.text
                    font.pixelSize: Theme.fontSize(20)
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: qsTr("Plays on repeat while Hexproof is open, across menus and matches.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSize(14)
                    wrapMode: Text.WordWrap
                }

                AppComboBox {
                    id: musicTrackSelector
                    objectName: "settingsMusicTrack"
                    Layout.fillWidth: true
                    model: root.music.tracks
                    textRole: "title"
                    valueRole: "id"
                    currentIndex: root.musicTrackIndex()
                    Accessible.name: qsTr("Music track")
                    onActivated: {
                        root.settings.musicTrack = currentValue
                        currentIndex = Qt.binding(function() { return root.musicTrackIndex() })
                    }
                }

                AppToggle {
                    objectName: "settingsMusicMute"
                    Layout.fillWidth: true
                    text: qsTr("Mute background music")
                    checked: !root.settings.musicEnabled
                    onToggled: {
                        root.settings.musicEnabled = !checked
                        checked = Qt.binding(function() { return !root.settings.musicEnabled })
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: qsTr("Volume")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSize(14)
                    }
                    Text {
                        objectName: "settingsMusicVolumeValue"
                        textFormat: Text.PlainText
                        text: Math.round(musicVolumeSlider.value * 100) + "%"
                        color: Theme.primary
                        font.pixelSize: Theme.fontSize(16)
                        font.weight: Font.DemiBold
                    }
                }

                Slider {
                    id: musicVolumeSlider
                    objectName: "settingsMusicVolume"
                    Layout.fillWidth: true
                    from: 0
                    to: 1
                    stepSize: 0.01
                    value: root.settings.musicVolume
                    implicitHeight: Theme.size(32)
                    Accessible.name: qsTr("Background music volume")
                    onPressedChanged: if (!pressed) root.saveMusicVolume()
                    onMoved: if (!pressed) root.saveMusicVolume()
                    background: Rectangle {
                        x: musicVolumeSlider.leftPadding
                        y: musicVolumeSlider.topPadding + (musicVolumeSlider.availableHeight - height) / 2
                        width: musicVolumeSlider.availableWidth
                        height: Theme.size(4)
                        radius: height / 2
                        color: Theme.surfaceMuted
                        Rectangle {
                            width: musicVolumeSlider.visualPosition * parent.width
                            height: parent.height
                            radius: height / 2
                            color: Theme.primaryStrong
                        }
                    }
                    handle: Rectangle {
                        x: musicVolumeSlider.leftPadding
                           + musicVolumeSlider.visualPosition * (musicVolumeSlider.availableWidth - width)
                        y: musicVolumeSlider.topPadding + (musicVolumeSlider.availableHeight - height) / 2
                        implicitWidth: Theme.size(20)
                        implicitHeight: Theme.size(20)
                        radius: width / 2
                        color: musicVolumeSlider.pressed ? Theme.primaryStrong : Theme.primary
                        border.width: musicVolumeSlider.activeFocus ? Theme.size(2) : 0
                        border.color: Theme.text
                    }
                }
            }
        }

        InfoBanner {
            objectName: "settingsAudioError"
            Layout.fillWidth: true
            message: I18n.status(root.settings.lastError)
        }
    }
}
