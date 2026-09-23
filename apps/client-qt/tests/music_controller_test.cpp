// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/BackgroundMusicController.h"

#include <QSignalSpy>
#include <QStringList>
#include <QTest>

#include <limits>

using hexproof::client::BackgroundMusicController;
using namespace Qt::StringLiterals;

namespace {

class FakeBackend final : public BackgroundMusicController::Backend
{
  public:
    bool available() const override
    {
        return outputAvailable;
    }
    void setAvailabilityChangedCallback(std::function<void()> callback) override
    {
        availabilityChanged = std::move(callback);
    }
    void play(const QUrl &source) override
    {
        events.append(u"play:%1"_s.arg(source.toString()));
        playing = source;
    }
    void stop() override
    {
        events.append(u"stop"_s);
        playing = QUrl();
    }
    void setVolume(qreal nextVolume) override
    {
        volume = nextVolume;
    }
    void setOutputAvailable(bool available)
    {
        outputAvailable = available;
        if (availabilityChanged)
            availabilityChanged();
    }

    bool outputAvailable = true;
    qreal volume = -1.0;
    QUrl playing;
    QStringList events;
    std::function<void()> availabilityChanged;
};

struct Fixture
{
    Fixture()
        : backend(new FakeBackend),
          music(std::unique_ptr<BackgroundMusicController::Backend>(backend),
                {{u"gitana"_s, u"Gitana"_s, QUrl(u"qrc:/music/Gitana.mp3"_s)},
                 {u"second"_s, u"Second Track"_s, QUrl(u"qrc:/music/Second.mp3"_s)}})
    {
    }

    FakeBackend *backend;
    BackgroundMusicController music;
};

} // namespace

class TestMusicController final : public QObject
{
    Q_OBJECT

  private slots:
    void savedPreferencesAreAppliedBeforePlaybackStarts();
    void savedMuteAndZeroVolumeKeepStartupSilent();
    void applicationActivationStartsAndStopsOnce();
    void disablingMusicAndZeroVolumeStopImmediately();
    void volumeIsBoundedWithoutRestartingMusic();
    void switchingTracksStopsTheOldTrackBeforePlayingTheNewOne();
    void arbitrarySourcesAreRejected();
    void deviceRestorationRespectsActivationAndPreferences();
};

void TestMusicController::savedPreferencesAreAppliedBeforePlaybackStarts()
{
    Fixture fixture;
    QVERIFY(fixture.music.enabled());
    QVERIFY(!fixture.music.active());
    QCOMPARE(fixture.music.volume(), 0.20);
    QCOMPARE(fixture.backend->volume, 0.20);
    QCOMPARE(fixture.music.track(), u"gitana"_s);
    QCOMPARE(fixture.music.tracks(),
             (QVariantList{QVariantMap{{u"id"_s, u"gitana"_s}, {u"title"_s, u"Gitana"_s}},
                           QVariantMap{{u"id"_s, u"second"_s}, {u"title"_s, u"Second Track"_s}}}));

    fixture.music.setTrack(u"second"_s);
    fixture.music.setVolume(0.6);
    fixture.music.setEnabled(false);
    fixture.music.setEnabled(true);
    QVERIFY(fixture.backend->events.isEmpty());
    fixture.music.setActive(true);
    QCOMPARE(fixture.backend->playing, QUrl(u"qrc:/music/Second.mp3"_s));
}

void TestMusicController::applicationActivationStartsAndStopsOnce()
{
    Fixture fixture;
    QSignalSpy changes(&fixture.music, &BackgroundMusicController::activeChanged);
    fixture.music.setActive(true);
    fixture.music.setActive(true);
    QCOMPARE(fixture.backend->events, QStringList{u"play:qrc:/music/Gitana.mp3"_s});
    fixture.music.setActive(false);
    fixture.music.setActive(false);
    QVERIFY(fixture.backend->playing.isEmpty());
    QCOMPARE(fixture.backend->events, (QStringList{u"play:qrc:/music/Gitana.mp3"_s, u"stop"_s}));
    QCOMPARE(changes.count(), 2);
    fixture.music.setActive(true);
    QCOMPARE(fixture.backend->playing, QUrl(u"qrc:/music/Gitana.mp3"_s));
    QCOMPARE(fixture.backend->events.size(), 3);
}

void TestMusicController::savedMuteAndZeroVolumeKeepStartupSilent()
{
    Fixture muted;
    muted.music.setEnabled(false);
    muted.music.setTrack(u"second"_s);
    muted.music.setActive(true);
    QVERIFY(muted.backend->events.isEmpty());
    muted.music.setEnabled(true);
    QCOMPARE(muted.backend->events, QStringList{u"play:qrc:/music/Second.mp3"_s});

    Fixture zeroVolume;
    zeroVolume.music.setVolume(0.0);
    zeroVolume.music.setActive(true);
    QVERIFY(zeroVolume.backend->events.isEmpty());
    zeroVolume.music.setVolume(0.2);
    QCOMPARE(zeroVolume.backend->events, QStringList{u"play:qrc:/music/Gitana.mp3"_s});
}

void TestMusicController::disablingMusicAndZeroVolumeStopImmediately()
{
    Fixture fixture;
    QSignalSpy changes(&fixture.music, &BackgroundMusicController::enabledChanged);
    fixture.music.setActive(true);
    fixture.music.setEnabled(false);
    fixture.music.setEnabled(false);
    QVERIFY(fixture.backend->playing.isEmpty());
    QCOMPARE(fixture.backend->events.size(), 2);
    QCOMPARE(changes.count(), 1);
    fixture.music.setTrack(u"second"_s);
    fixture.music.setVolume(0.5);
    QCOMPARE(fixture.backend->events.size(), 2);
    fixture.music.setEnabled(true);
    QCOMPARE(fixture.backend->playing, QUrl(u"qrc:/music/Second.mp3"_s));

    fixture.music.setVolume(0.0);
    QVERIFY(fixture.backend->playing.isEmpty());
    QCOMPARE(fixture.backend->volume, 0.0);
    fixture.music.setEnabled(false);
    fixture.music.setEnabled(true);
    QVERIFY(fixture.backend->playing.isEmpty());
    fixture.music.setVolume(0.4);
    QCOMPARE(fixture.backend->playing, QUrl(u"qrc:/music/Second.mp3"_s));

    fixture.music.setActive(false);
    const qsizetype events = fixture.backend->events.size();
    fixture.music.setVolume(0.0);
    fixture.music.setVolume(0.4);
    fixture.music.setEnabled(false);
    fixture.music.setEnabled(true);
    QCOMPARE(fixture.backend->events.size(), events);
}

void TestMusicController::volumeIsBoundedWithoutRestartingMusic()
{
    Fixture fixture;
    QSignalSpy changes(&fixture.music, &BackgroundMusicController::volumeChanged);
    fixture.music.setActive(true);
    fixture.music.setVolume(0.7);
    QCOMPARE(fixture.backend->volume, 0.7);
    fixture.music.setVolume(2.0);
    QCOMPARE(fixture.music.volume(), 1.0);
    QCOMPARE(fixture.backend->volume, 1.0);
    fixture.music.setVolume(std::numeric_limits<qreal>::quiet_NaN());
    fixture.music.setVolume(std::numeric_limits<qreal>::infinity());
    fixture.music.setVolume(-std::numeric_limits<qreal>::infinity());
    QCOMPARE(fixture.music.volume(), 1.0);
    QCOMPARE(changes.count(), 2);
    QCOMPARE(fixture.backend->events.size(), 1);

    fixture.music.setVolume(-0.1);
    QCOMPARE(fixture.music.volume(), 0.0);
    QCOMPARE(fixture.backend->volume, 0.0);
    QVERIFY(fixture.backend->playing.isEmpty());
    QCOMPARE(changes.count(), 3);
}

void TestMusicController::switchingTracksStopsTheOldTrackBeforePlayingTheNewOne()
{
    Fixture fixture;
    QSignalSpy changes(&fixture.music, &BackgroundMusicController::trackChanged);
    fixture.music.setActive(true);
    fixture.music.setTrack(u"second"_s);
    fixture.music.setTrack(u"second"_s);
    QCOMPARE(fixture.music.track(), u"second"_s);
    QCOMPARE(fixture.backend->events, (QStringList{u"play:qrc:/music/Gitana.mp3"_s, u"stop"_s,
                                                   u"play:qrc:/music/Second.mp3"_s}));
    QCOMPARE(changes.count(), 1);
    fixture.music.setTrack(u"gitana"_s);
    QCOMPARE(fixture.backend->events.last(), u"play:qrc:/music/Gitana.mp3"_s);
    QCOMPARE(fixture.backend->events.at(3), u"stop"_s);
}

void TestMusicController::arbitrarySourcesAreRejected()
{
    Fixture fixture;
    QSignalSpy changes(&fixture.music, &BackgroundMusicController::trackChanged);
    const QStringList invalid{QString(),
                              u"removed-track"_s,
                              u"../outside.mp3"_s,
                              u"file:///tmp/music.mp3"_s,
                              u"https://example.com/music.mp3"_s,
                              u"qrc:/music/Gitana.mp3"_s};
    for (const QString &track : invalid)
        fixture.music.setTrack(track);
    QCOMPARE(fixture.music.track(), u"gitana"_s);
    QCOMPARE(changes.count(), 0);
    QVERIFY(fixture.backend->events.isEmpty());

    fixture.music.setActive(true);
    fixture.music.setTrack(u"second"_s);
    const qsizetype events = fixture.backend->events.size();
    for (const QString &track : invalid)
        fixture.music.setTrack(track);
    QCOMPARE(fixture.music.track(), u"second"_s);
    QCOMPARE(fixture.backend->events.size(), events);
}

void TestMusicController::deviceRestorationRespectsActivationAndPreferences()
{
    Fixture fixture;
    fixture.backend->setOutputAvailable(false);
    fixture.music.setActive(true);
    fixture.music.setTrack(u"second"_s);
    QVERIFY(fixture.backend->events.isEmpty());
    fixture.backend->setOutputAvailable(true);
    QCOMPARE(fixture.backend->playing, QUrl(u"qrc:/music/Second.mp3"_s));
    fixture.backend->setOutputAvailable(false);
    QVERIFY(fixture.backend->playing.isEmpty());
    fixture.music.setActive(false);
    fixture.backend->setOutputAvailable(true);
    QCOMPARE(fixture.backend->events.size(), 2);

    fixture.music.setActive(true);
    fixture.backend->setOutputAvailable(false);
    fixture.music.setEnabled(false);
    fixture.backend->setOutputAvailable(true);
    QVERIFY(fixture.backend->playing.isEmpty());
    fixture.music.setEnabled(true);
    QCOMPARE(fixture.backend->playing, QUrl(u"qrc:/music/Second.mp3"_s));
    fixture.backend->setOutputAvailable(false);
    fixture.music.setVolume(0.0);
    const qsizetype events = fixture.backend->events.size();
    fixture.backend->setOutputAvailable(true);
    QCOMPARE(fixture.backend->events.size(), events);
}

QTEST_GUILESS_MAIN(TestMusicController)
#include "music_controller_test.moc"
