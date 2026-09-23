// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QList>
#include <QObject>
#include <QString>
#include <QUrl>
#include <QVariantList>

#include <functional>
#include <memory>

namespace hexproof::client {

class BackgroundMusicController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(qreal volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(QString track READ track WRITE setTrack NOTIFY trackChanged)
    Q_PROPERTY(QVariantList tracks READ tracks CONSTANT)

  public:
    struct Track
    {
        QString id;
        QString title;
        QUrl source;
    };

    // Keep playback policy testable without a media decoder or audio device.
    class Backend
    {
      public:
        virtual ~Backend() = default;
        virtual bool available() const = 0;
        virtual void setAvailabilityChangedCallback(std::function<void()> callback) = 0;
        virtual void play(const QUrl &source) = 0;
        virtual void stop() = 0;
        virtual void setVolume(qreal volume) = 0;
    };

    explicit BackgroundMusicController(QObject *parent = nullptr);
    BackgroundMusicController(std::unique_ptr<Backend> backend, QList<Track> catalog,
                              QObject *parent = nullptr);
    ~BackgroundMusicController() override;

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
    bool active() const
    {
        return m_active;
    }
    void setActive(bool active);
    QString track() const
    {
        return m_track;
    }
    void setTrack(const QString &track);
    QVariantList tracks() const;

  signals:
    void enabledChanged();
    void volumeChanged();
    void activeChanged();
    void trackChanged();

  private:
    void updatePlayback();

    std::unique_ptr<Backend> m_backend;
    QList<Track> m_catalog;
    QString m_track;
    QUrl m_playingSource;
    bool m_enabled = true;
    bool m_active = false;
    bool m_playing = false;
    qreal m_volume = 0.20;
};

} // namespace hexproof::client
