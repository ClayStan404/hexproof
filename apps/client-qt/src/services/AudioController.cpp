// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "AudioController.h"

#include <QAudioDevice>
#include <QMediaDevices>
#include <QSoundEffect>
#include <QUrl>

#include <algorithm>
#include <chrono>
#include <cmath>

namespace hexproof::client {

namespace {

using namespace Qt::StringLiterals;

const QHash<QString, int> &cueCooldowns()
{
    static const QHash<QString, int> cues{
        {u"click"_s, 80},    {u"select"_s, 80},   {u"draw"_s, 120},   {u"play"_s, 100},
        {u"tap"_s, 80},      {u"shuffle"_s, 150}, {u"attack"_s, 120}, {u"block"_s, 120},
        {u"cast"_s, 120},    {u"resolve"_s, 120}, {u"turn"_s, 150},   {u"damage"_s, 150},
        {u"confirm"_s, 100}, {u"cancel"_s, 100},  {u"error"_s, 150},
    };
    return cues;
}

class SoundEffectBackend final : public QObject, public AudioController::Backend
{
  public:
    SoundEffectBackend()
    {
        connect(&m_devices, &QMediaDevices::audioOutputsChanged, this,
                [this]() { refreshOutput(); });
        refreshOutput();
    }

    bool play(const QString &cue) override
    {
        QSoundEffect *effect = m_effects.value(cue);
        // Loading and missing-device requests are discarded, never played late.
        if (!effect || effect->status() != QSoundEffect::Ready || effect->isPlaying())
            return false;
        effect->play();
        return true;
    }

    int activeVoiceCount() const override
    {
        int count = 0;
        for (const QSoundEffect *effect : m_effects)
            count += effect->isPlaying() ? 1 : 0;
        return count;
    }

    void stopAll() override
    {
        for (QSoundEffect *effect : m_effects)
            effect->stop();
    }

    void setVolume(qreal volume) override
    {
        m_volume = volume;
        for (QSoundEffect *effect : m_effects)
            effect->setVolume(static_cast<float>(m_volume));
    }

  private:
    void refreshOutput()
    {
        const QAudioDevice device = QMediaDevices::defaultAudioOutput();
        if (device == m_device)
            return;
        m_device = device;
        qDeleteAll(m_effects);
        m_effects.clear();
        if (device.isNull())
            return;
        for (auto cue = cueCooldowns().cbegin(); cue != cueCooldowns().cend(); ++cue) {
            auto *effect = new QSoundEffect(device, this);
            effect->setVolume(static_cast<float>(m_volume));
            effect->setSource(QUrl(u"qrc:/audio/%1.wav"_s.arg(cue.key())));
            m_effects.insert(cue.key(), effect);
        }
    }

    QMediaDevices m_devices;
    QAudioDevice m_device;
    QHash<QString, QSoundEffect *> m_effects;
    qreal m_volume = 0.35;
};

AudioController::Clock monotonicClock()
{
    return [origin = std::chrono::steady_clock::now()]() {
        return std::chrono::duration_cast<std::chrono::milliseconds>(
                   std::chrono::steady_clock::now() - origin)
            .count();
    };
}

} // namespace

AudioController::AudioController(QObject *parent)
    : AudioController(std::make_unique<SoundEffectBackend>(), monotonicClock(), parent)
{
}

AudioController::AudioController(std::unique_ptr<Backend> backend, Clock clock, QObject *parent)
    : QObject(parent),
      m_backend(std::move(backend)),
      m_clock(std::move(clock))
{
    Q_ASSERT(m_backend && m_clock);
    m_backend->setVolume(m_volume);
}

AudioController::~AudioController() = default;

void AudioController::setEnabled(bool enabled)
{
    if (m_enabled == enabled)
        return;
    m_enabled = enabled;
    if (!m_enabled)
        m_backend->stopAll();
    emit enabledChanged();
}

void AudioController::setVolume(qreal volume)
{
    if (!std::isfinite(volume))
        return;
    const qreal bounded = std::clamp(volume, 0.0, 1.0);
    if (bounded == m_volume)
        return;
    m_volume = bounded;
    m_backend->setVolume(m_volume);
    if (m_volume == 0.0)
        m_backend->stopAll();
    emit volumeChanged();
}

bool AudioController::play(const QString &cue)
{
    const auto cooldown = cueCooldowns().constFind(cue);
    if (!m_enabled || m_volume <= 0.0 || cooldown == cueCooldowns().cend())
        return false;
    const qint64 now = m_clock();
    const auto previous = m_lastPlayed.constFind(cue);
    if (previous != m_lastPlayed.cend() && now - *previous < *cooldown)
        return false;
    if (m_backend->activeVoiceCount() >= 4 || !m_backend->play(cue))
        return false;
    m_lastPlayed.insert(cue, now);
    return true;
}

bool AudioController::preview(const QString &cue)
{
    if (!m_enabled || m_volume <= 0.0 || !cueCooldowns().contains(cue))
        return false;
    m_backend->stopAll();
    m_lastPlayed.remove(cue);
    return play(cue);
}

} // namespace hexproof::client
