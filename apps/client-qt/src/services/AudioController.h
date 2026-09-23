// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QHash>
#include <QObject>
#include <QString>

#include <functional>
#include <memory>

namespace hexproof::client {

class AudioController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(qreal volume READ volume WRITE setVolume NOTIFY volumeChanged)

  public:
    // Keep playback independent from cue policy so tests need no audio device.
    class Backend
    {
      public:
        virtual ~Backend() = default;
        virtual bool play(const QString &cue) = 0;
        virtual int activeVoiceCount() const = 0;
        virtual void stopAll() = 0;
        virtual void setVolume(qreal volume) = 0;
    };

    using Clock = std::function<qint64()>;

    explicit AudioController(QObject *parent = nullptr);
    AudioController(std::unique_ptr<Backend> backend, Clock clock, QObject *parent = nullptr);
    ~AudioController() override;

    bool enabled() const
    {
        return m_enabled;
    }
    void setEnabled(bool enabled);
    qreal volume() const
    {
        return m_volume;
    }
    void setVolume(qreal volume);

    Q_INVOKABLE bool play(const QString &cue);
    Q_INVOKABLE bool preview(const QString &cue);

  signals:
    void enabledChanged();
    void volumeChanged();

  private:
    std::unique_ptr<Backend> m_backend;
    Clock m_clock;
    QHash<QString, qint64> m_lastPlayed;
    bool m_enabled = true;
    qreal m_volume = 0.35;
};

} // namespace hexproof::client
