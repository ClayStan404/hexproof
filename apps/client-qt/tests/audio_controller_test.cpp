// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/AudioController.h"

#include <QSet>
#include <QSignalSpy>
#include <QStringList>
#include <QTest>

#include <limits>

using hexproof::client::AudioController;
using namespace Qt::StringLiterals;

namespace {

class FakeBackend final : public AudioController::Backend
{
  public:
    bool play(const QString &cue) override
    {
        ++attempts;
        if (!ready || playing.contains(cue))
            return false;
        played.append(cue);
        playing.insert(cue);
        return true;
    }

    int activeVoiceCount() const override
    {
        return playing.size();
    }
    void stopAll() override
    {
        ++stops;
        playing.clear();
    }
    void setVolume(qreal nextVolume) override
    {
        volume = nextVolume;
    }

    QStringList played;
    QSet<QString> playing;
    bool ready = true;
    int attempts = 0;
    int stops = 0;
    qreal volume = -1.0;
};

struct Fixture
{
    Fixture()
        : backend(new FakeBackend),
          audio(std::unique_ptr<AudioController::Backend>(backend), [this]() { return now; })
    {
    }

    qint64 now = 0;
    FakeBackend *backend;
    AudioController audio;
};

} // namespace

class TestAudioController final : public QObject
{
    Q_OBJECT

  private slots:
    void acceptsOnlyKnownCues();
    void muteStopsPlaybackAndDiscardsNewRequests();
    void volumeIsBoundedAndAppliedToActivePlayback();
    void cooldownIsPerCueAndUsesElapsedTime();
    void unavailablePlaybackDoesNotQueueOrConsumeCooldown();
    void voiceLimitDropsExcessRequestsWithoutDelayingThem();
    void previewReplacesEffectsAndAllowsImmediateReplay();
    void previewRespectsMuteVolumeAndKnownCues();
};

void TestAudioController::acceptsOnlyKnownCues()
{
    Fixture fixture;
    QVERIFY(fixture.audio.enabled());
    QCOMPARE(fixture.audio.volume(), 0.35);
    QCOMPARE(fixture.backend->volume, 0.35);

    const QStringList cues{u"click"_s,   u"select"_s, u"draw"_s,    u"play"_s,   u"tap"_s,
                           u"shuffle"_s, u"attack"_s, u"block"_s,   u"cast"_s,   u"resolve"_s,
                           u"turn"_s,    u"damage"_s, u"confirm"_s, u"cancel"_s, u"error"_s};
    for (const QString &cue : cues) {
        QVERIFY(fixture.audio.play(cue));
        fixture.backend->playing.clear();
    }
    QCOMPARE(fixture.backend->played, cues);
    QVERIFY(!fixture.audio.play(QString()));
    QVERIFY(!fixture.audio.play(u"unknown"_s));
    QVERIFY(!fixture.audio.play(u"../outside"_s));
    QVERIFY(!fixture.audio.play(u"https://example.com/audio.wav"_s));
    QCOMPARE(fixture.backend->attempts, cues.size());
}

void TestAudioController::muteStopsPlaybackAndDiscardsNewRequests()
{
    Fixture fixture;
    QSignalSpy changes(&fixture.audio, &AudioController::enabledChanged);
    QVERIFY(fixture.audio.play(u"draw"_s));
    fixture.audio.setEnabled(false);
    fixture.audio.setEnabled(false);
    QCOMPARE(changes.count(), 1);
    QCOMPARE(fixture.backend->stops, 1);
    QVERIFY(fixture.backend->playing.isEmpty());
    QVERIFY(!fixture.audio.play(u"cast"_s));
    QCOMPARE(fixture.backend->attempts, 1);

    fixture.audio.setEnabled(true);
    QCOMPARE(changes.count(), 2);
    QCOMPARE(fixture.backend->played, QStringList{u"draw"_s});
    QVERIFY(fixture.audio.play(u"cast"_s));
    QCOMPARE(fixture.backend->played, (QStringList{u"draw"_s, u"cast"_s}));
}

void TestAudioController::volumeIsBoundedAndAppliedToActivePlayback()
{
    Fixture fixture;
    QSignalSpy changes(&fixture.audio, &AudioController::volumeChanged);
    QVERIFY(fixture.audio.play(u"shuffle"_s));
    fixture.audio.setVolume(0.7);
    QCOMPARE(fixture.audio.volume(), 0.7);
    QCOMPARE(fixture.backend->volume, 0.7);
    QVERIFY(fixture.backend->playing.contains(u"shuffle"_s));
    fixture.audio.setVolume(2.0);
    QCOMPARE(fixture.audio.volume(), 1.0);
    QCOMPARE(fixture.backend->volume, 1.0);
    fixture.audio.setVolume(std::numeric_limits<qreal>::quiet_NaN());
    fixture.audio.setVolume(std::numeric_limits<qreal>::infinity());
    fixture.audio.setVolume(-std::numeric_limits<qreal>::infinity());
    QCOMPARE(fixture.audio.volume(), 1.0);
    QCOMPARE(changes.count(), 2);

    fixture.audio.setVolume(-1.0);
    QCOMPARE(fixture.audio.volume(), 0.0);
    QCOMPARE(fixture.backend->volume, 0.0);
    QCOMPARE(fixture.backend->stops, 1);
    QVERIFY(fixture.backend->playing.isEmpty());
    QVERIFY(!fixture.audio.play(u"select"_s));
    fixture.audio.setVolume(0.35);
    QCOMPARE(fixture.backend->played, QStringList{u"shuffle"_s});
    QVERIFY(fixture.audio.play(u"select"_s));
    fixture.audio.setVolume(0.35);
    QCOMPARE(changes.count(), 4);
}

void TestAudioController::cooldownIsPerCueAndUsesElapsedTime()
{
    Fixture fixture;
    QVERIFY(fixture.audio.play(u"click"_s));
    fixture.backend->playing.clear();
    QVERIFY(!fixture.audio.play(u"click"_s));
    QVERIFY(fixture.audio.play(u"select"_s));
    fixture.backend->playing.clear();
    fixture.now = 79;
    QVERIFY(!fixture.audio.play(u"click"_s));
    fixture.now = 80;
    QVERIFY(fixture.audio.play(u"click"_s));
    QCOMPARE(fixture.backend->played, (QStringList{u"click"_s, u"select"_s, u"click"_s}));
    fixture.backend->playing.clear();
    QVERIFY(fixture.audio.play(u"error"_s));
    fixture.backend->playing.clear();
    fixture.now += 149;
    QVERIFY(!fixture.audio.play(u"error"_s));
    ++fixture.now;
    QVERIFY(fixture.audio.play(u"error"_s));
}

void TestAudioController::unavailablePlaybackDoesNotQueueOrConsumeCooldown()
{
    Fixture fixture;
    fixture.backend->ready = false;
    QVERIFY(!fixture.audio.play(u"draw"_s));
    QVERIFY(fixture.backend->played.isEmpty());
    fixture.backend->ready = true;
    QCoreApplication::processEvents();
    QVERIFY(fixture.backend->played.isEmpty());
    QVERIFY(fixture.audio.play(u"draw"_s));
    QCOMPARE(fixture.backend->played, QStringList{u"draw"_s});

    fixture.now = 500;
    QVERIFY(!fixture.audio.play(u"draw"_s));
    fixture.backend->playing.clear();
    QVERIFY(fixture.audio.play(u"draw"_s));
    QCOMPARE(fixture.backend->played, (QStringList{u"draw"_s, u"draw"_s}));
}

void TestAudioController::voiceLimitDropsExcessRequestsWithoutDelayingThem()
{
    Fixture fixture;
    QVERIFY(fixture.audio.play(u"draw"_s));
    QVERIFY(fixture.audio.play(u"cast"_s));
    QVERIFY(fixture.audio.play(u"attack"_s));
    QVERIFY(fixture.audio.play(u"damage"_s));
    QVERIFY(!fixture.audio.play(u"turn"_s));
    QCOMPARE(fixture.backend->attempts, 4);
    fixture.backend->playing.remove(u"draw"_s);
    QCoreApplication::processEvents();
    QCOMPARE(fixture.backend->played.size(), 4);
    QVERIFY(fixture.audio.play(u"turn"_s));
    QCOMPARE(fixture.backend->played.size(), 5);
    QCOMPARE(fixture.backend->activeVoiceCount(), 4);
}

void TestAudioController::previewReplacesEffectsAndAllowsImmediateReplay()
{
    Fixture fixture;
    QVERIFY(fixture.audio.play(u"draw"_s));
    QVERIFY(fixture.audio.play(u"cast"_s));
    QVERIFY(fixture.audio.preview(u"draw"_s));
    QCOMPARE(fixture.backend->stops, 1);
    QCOMPARE(fixture.backend->playing, QSet<QString>{u"draw"_s});
    QVERIFY(fixture.audio.preview(u"draw"_s));
    QCOMPARE(fixture.backend->stops, 2);
    QCOMPARE(fixture.backend->playing, QSet<QString>{u"draw"_s});
    QVERIFY(fixture.audio.preview(u"turn"_s));
    QCOMPARE(fixture.backend->playing, QSet<QString>{u"turn"_s});
    QCOMPARE(fixture.backend->played,
             (QStringList{u"draw"_s, u"cast"_s, u"draw"_s, u"draw"_s, u"turn"_s}));
    QCOMPARE(fixture.audio.volume(), 0.35);
    QCOMPARE(fixture.backend->volume, 0.35);
    QVERIFY(fixture.audio.enabled());
}

void TestAudioController::previewRespectsMuteVolumeAndKnownCues()
{
    Fixture fixture;
    QVERIFY(fixture.audio.play(u"draw"_s));
    QVERIFY(!fixture.audio.preview(u"unknown"_s));
    QCOMPARE(fixture.backend->stops, 0);
    QCOMPARE(fixture.backend->playing, QSet<QString>{u"draw"_s});
    fixture.audio.setEnabled(false);
    QVERIFY(!fixture.audio.preview(u"turn"_s));
    QCOMPARE(fixture.backend->stops, 1);
    fixture.audio.setEnabled(true);
    fixture.audio.setVolume(0);
    QVERIFY(!fixture.audio.preview(u"turn"_s));
    QCOMPARE(fixture.backend->attempts, 1);
    fixture.audio.setVolume(0.2);
    fixture.backend->ready = false;
    QVERIFY(!fixture.audio.preview(u"turn"_s));
    fixture.backend->ready = true;
    QCoreApplication::processEvents();
    QCOMPARE(fixture.backend->played, QStringList{u"draw"_s});
    QVERIFY(fixture.audio.preview(u"turn"_s));
    QCOMPARE(fixture.backend->volume, 0.2);
}

QTEST_GUILESS_MAIN(TestAudioController)
#include "audio_controller_test.moc"
