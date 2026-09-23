// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "BackgroundMusicController.h"

#include <QAudioDevice>
#include <QAudioOutput>
#include <QMediaDevices>
#include <QMediaPlayer>
#include <QVariantMap>

#include <algorithm>
#include <cmath>

namespace hexproof::client {

namespace {

using namespace Qt::StringLiterals;

QList<BackgroundMusicController::Track> bundledTracks()
{
    return {{u"gitana"_s, u"Gitana"_s, QUrl(u"qrc:/music/Gitana.mp3"_s)},
            {u"bgm2"_s, u"BGM 2"_s, QUrl(u"qrc:/music/bgm2.ogg"_s)},
            {u"bgm3"_s, u"BGM 3"_s, QUrl(u"qrc:/music/bgm3.ogg"_s)}};
}

class MediaPlayerBackend final : public QObject, public BackgroundMusicController::Backend
{
  public:
    MediaPlayerBackend()
        : m_device(QMediaDevices::defaultAudioOutput())
    {
        connect(&m_devices, &QMediaDevices::audioOutputsChanged, this, [this]() {
            const QAudioDevice device = QMediaDevices::defaultAudioOutput();
            if (m_device == device)
                return;
            m_device = device;
            if (m_output && !m_device.isNull())
                m_output->setDevice(m_device);
            if (m_availabilityChanged)
                m_availabilityChanged();
        });
    }

    bool available() const override
    {
        return !m_device.isNull();
    }

    void setAvailabilityChangedCallback(std::function<void()> callback) override
    {
        m_availabilityChanged = std::move(callback);
    }

    void play(const QUrl &source) override
    {
        if (!available())
            return;
        if (!m_player) {
            m_output = std::make_unique<QAudioOutput>(m_device);
            m_output->setVolume(static_cast<float>(m_volume));
            m_player = std::make_unique<QMediaPlayer>();
            m_player->setAudioOutput(m_output.get());
            m_player->setLoops(QMediaPlayer::Infinite);
        }
        if (m_player->source() != source)
            m_player->setSource(source);
        m_player->play();
    }

    void stop() override
    {
        if (m_player)
            m_player->stop();
    }

    void setVolume(qreal volume) override
    {
        m_volume = volume;
        if (m_output)
            m_output->setVolume(static_cast<float>(m_volume));
    }

  private:
    QMediaDevices m_devices;
    QAudioDevice m_device;
    std::function<void()> m_availabilityChanged;
    std::unique_ptr<QAudioOutput> m_output;
    std::unique_ptr<QMediaPlayer> m_player;
    qreal m_volume = 0.20;
};

} // namespace

BackgroundMusicController::BackgroundMusicController(QObject *parent)
    : BackgroundMusicController(std::make_unique<MediaPlayerBackend>(), bundledTracks(), parent)
{
}

BackgroundMusicController::BackgroundMusicController(std::unique_ptr<Backend> backend,
                                                     QList<Track> catalog, QObject *parent)
    : QObject(parent),
      m_backend(std::move(backend)),
      m_catalog(std::move(catalog))
{
    Q_ASSERT(m_backend && !m_catalog.isEmpty());
    m_track = m_catalog.constFirst().id;
    m_backend->setVolume(m_volume);
    m_backend->setAvailabilityChangedCallback([this]() { updatePlayback(); });
}

BackgroundMusicController::~BackgroundMusicController()
{
    m_backend->setAvailabilityChangedCallback({});
    if (m_playing)
        m_backend->stop();
}

void BackgroundMusicController::setEnabled(bool enabled)
{
    if (m_enabled == enabled)
        return;
    m_enabled = enabled;
    updatePlayback();
    emit enabledChanged();
}

void BackgroundMusicController::setVolume(qreal volume)
{
    if (!std::isfinite(volume))
        return;
    const qreal bounded = std::clamp(volume, 0.0, 1.0);
    if (bounded == m_volume)
        return;
    m_volume = bounded;
    m_backend->setVolume(m_volume);
    updatePlayback();
    emit volumeChanged();
}

void BackgroundMusicController::setActive(bool active)
{
    if (m_active == active)
        return;
    m_active = active;
    updatePlayback();
    emit activeChanged();
}

void BackgroundMusicController::setTrack(const QString &track)
{
    const auto found = std::find_if(m_catalog.cbegin(), m_catalog.cend(),
                                    [&track](const Track &entry) { return entry.id == track; });
    // Persisted or QML-supplied strings select catalog IDs, never URLs or paths.
    if (found == m_catalog.cend() || track == m_track)
        return;
    m_track = track;
    updatePlayback();
    emit trackChanged();
}

QVariantList BackgroundMusicController::tracks() const
{
    QVariantList tracks;
    for (const Track &entry : m_catalog)
        tracks.append(QVariantMap{{u"id"_s, entry.id}, {u"title"_s, entry.title}});
    return tracks;
}

void BackgroundMusicController::updatePlayback()
{
    const bool shouldPlay = m_active && m_enabled && m_volume > 0.0 && m_backend->available();
    if (!shouldPlay) {
        if (m_playing) {
            m_backend->stop();
            m_playing = false;
        }
        return;
    }

    const auto found = std::find_if(m_catalog.cbegin(), m_catalog.cend(),
                                    [this](const Track &entry) { return entry.id == m_track; });
    if (found == m_catalog.cend())
        return;
    if (m_playing && m_playingSource == found->source)
        return;
    if (m_playing)
        m_backend->stop();
    m_playingSource = found->source;
    m_backend->play(m_playingSource);
    m_playing = true;
}

} // namespace hexproof::client
