// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/LimitedSessionState.h"
#include "services/TournamentSessionState.h"
#include "services/WsClient.h"
#include "testing/LocalTestSession.h"

#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSettings>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <QUuid>
#include <memory>
#include <vector>

using namespace Qt::StringLiterals;
using namespace hexproof::client;

namespace {

QVariantMap productForSource(const QString &source)
{
    const bool cube = source == u"Commander Cube"_s;
    if (source != u"TST"_s && !cube)
        return {};
    const QString setCode = u"TST"_s;
    QVariantList cards;
    for (int index = 1; index <= (cube ? 960 : 60); ++index)
        cards.append(QVariantMap{{u"name"_s, u"Card %1"_s.arg(index)},
                                 {u"setCode"_s, setCode},
                                 {u"collectorNumber"_s, QString::number(index)},
                                 {u"typeLine"_s, u"Creature — Test"_s},
                                 {u"rarity"_s, u"common"_s},
                                 {u"finish"_s, u"nonfoil"_s},
                                 {u"weight"_s, 1}});
    if (cube)
        return {{u"id"_s, u"test-cube"_s},
                {u"name"_s, source},
                {u"productType"_s, u"cube"_s},
                {u"sheets"_s,
                 QVariantList{QVariantMap{
                     {u"name"_s, u"main"_s}, {u"cards"_s, cards}, {u"withReplacement"_s, false}}}}};
    return {{u"id"_s, u"tst-play"_s},
            {u"name"_s, u"Test Play Booster"_s},
            {u"setCode"_s, setCode},
            {u"productType"_s, u"official"_s},
            {u"authentic"_s, true},
            {u"cardsPerPack"_s, 15},
            {u"sheets"_s,
             QVariantList{QVariantMap{
                 {u"name"_s, u"main"_s}, {u"withReplacement"_s, false}, {u"cards"_s, cards}}}},
            {u"variants"_s,
             QVariantList{QVariantMap{{u"weight"_s, 1},
                                      {u"slots"_s, QVariantList{QVariantMap{{u"sheet"_s, u"main"_s},
                                                                            {u"count"_s, 15}}}}}}}};
}

LocalTestSession::Options options(const QString &mode = u"draft"_s, int players = 2)
{
    LocalTestSession::Options config{mode, u"TST"_s, QUuid::createUuid().toString(QUuid::Id128),
                                     players, 1};
    if (config.commanderCube()) {
        config.setCode.clear();
        config.cube = u"Commander Cube"_s;
    }
    return config;
}

// Separate processes are essential: tournament credentials use QSettings and
// must not be shared by seats, just like the launcher's isolated profiles.
int runWorker(QCoreApplication &app)
{
    QCommandLineParser parser;
    LocalTestSession::addOptions(parser);
    parser.addOption({u"worker-dir"_s, u"Isolated worker directory."_s, u"path"_s});
    parser.addOption({u"server-url"_s, u"Test server."_s, u"url"_s});
    parser.process(app);
    const QString directory = parser.value(u"worker-dir"_s);
    QCoreApplication::setOrganizationName(u"HexproofTests"_s);
    QCoreApplication::setApplicationName(u"LocalTestWorker"_s);
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, directory);
    WsClient client;
    const auto config = LocalTestSession::readOptions(parser);
    if (!client.setInitialConnection(parser.value(u"server-url"_s),
                                     u"Test Seat %1"_s.arg(config.seat)))
        return 2;
    LocalTestSession setup(&client, config, productForSource);
    QTimer releasePoll;
    releasePoll.setInterval(20);
    QObject::connect(&releasePoll, &QTimer::timeout, &app, [&]() {
        if (QFileInfo::exists(directory + u"/release"_s)) {
            client.disconnectFromHub();
            app.quit();
        }
    });
    const auto publish = [&](const QString &error) {
        const auto *event = client.tournamentSession();
        const auto *limited = client.limitedSession();
        QJsonArray cards;
        const QVariantList privateCards = config.eventType == u"sealed"_s || config.autoDraft
                                              ? limited->pool()
                                              : limited->currentPack();
        for (const QVariant &card : privateCards)
            cards.append(card.toMap().value(u"instanceId"_s).toString());
        QJsonObject result{{u"error"_s, error},
                           {u"tournamentId"_s, event->tournamentId()},
                           {u"participantId"_s, event->participantId()},
                           {u"registered"_s, event->registered()},
                           {u"checkedIn"_s, event->checkedIn()},
                           {u"stage"_s, limited->stage()},
                           {u"cards"_s, cards},
                           {u"poolSize"_s, limited->pool().size()},
                           {u"cubeRoom"_s, event->cubeRoom()},
                           {u"packs"_s, limited->currentPacks().size()},
                           {u"picksRequired"_s, limited->picksRequired()},
                           {u"packsPerPlayer"_s, limited->packsPerPlayer()},
                           {u"optionalCards"_s, limited->optionalCards().size()},
                           {u"mainboardCards"_s, limited->mainboardInstanceIds().size()},
                           {u"commanderCards"_s, limited->commanderInstanceIds().size()},
                           {u"deckSubmitted"_s, limited->deckSubmitted()}};
        QSaveFile file(directory + u"/result.json"_s);
        const QByteArray json = QJsonDocument(result).toJson();
        const bool saved =
            file.open(QIODevice::WriteOnly) && file.write(json) == json.size() && file.commit();
        if (!saved || !error.isEmpty()) {
            client.disconnectFromHub();
            app.exit(1);
            return;
        }
        // Keep every seat connected until all workers have recorded setup.
        // Early Cube disconnects change the remaining seats' checked-in count.
        releasePoll.start();
    };
    QObject::connect(&setup, &LocalTestSession::failed, &app, publish);
    QObject::connect(&setup, &LocalTestSession::finished, &app,
                     [&]() { QTimer::singleShot(400, &app, [&]() { publish({}); }); });
    QTimer::singleShot(0, &setup, &LocalTestSession::start);
    return app.exec();
}

struct Worker
{
    QProcess process;
    QTemporaryDir directory;
    ~Worker()
    {
        if (process.state() == QProcess::NotRunning)
            return;
        process.terminate();
        if (!process.waitForFinished(1000)) {
            process.kill();
            process.waitForFinished(1000);
        }
    }
};

class Server final
{
  public:
    ~Server()
    {
        process.terminate();
        if (!process.waitForFinished(3000)) {
            process.kill();
            process.waitForFinished(1000);
        }
    }
    bool start()
    {
        QString binary = qEnvironmentVariable("HEXPROOF_SERVER_BINARY");
        if (binary.isEmpty())
            binary = QStringLiteral(HEXPROOF_DEFAULT_SERVER_BINARY);
        if (!directory.isValid() || !QFileInfo(binary).isExecutable())
            return false;
        process.setProcessChannelMode(QProcess::MergedChannels);
        process.start(binary, {u"-bind"_s, u"127.0.0.1"_s, u"-port"_s, u"0"_s, u"-retention-dir"_s,
                               directory.path()});
        if (!process.waitForStarted(3000))
            return false;
        QElapsedTimer elapsed;
        elapsed.start();
        QByteArray output;
        while (elapsed.elapsed() < 3000) {
            process.waitForReadyRead(100);
            output += process.readAll();
            const auto match = QRegularExpression(u"listening on 127\\.0\\.0\\.1:(\\d+)"_s)
                                   .match(QString::fromUtf8(output));
            if (match.hasMatch()) {
                url = u"ws://127.0.0.1:%1/ws"_s.arg(match.captured(1));
                return true;
            }
        }
        return false;
    }
    QTemporaryDir directory;
    QProcess process;
    QString url;
};

} // namespace

class TestLocalTestSession final : public QObject
{
    Q_OBJECT
  private slots:
    void initTestCase()
    {
        QVERIFY(m_settings.isValid());
        QCoreApplication::setOrganizationName(u"HexproofTests"_s);
        QCoreApplication::setApplicationName(u"LocalTestSession"_s);
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_settings.path());
    }
    void cleanup()
    {
        QSettings().clear();
    }
    void validatesOptions()
    {
        QCommandLineParser parser;
        LocalTestSession::addOptions(parser);
        QVERIFY(parser.parse({u"hexproof"_s}));
        QVERIFY(!LocalTestSession::requested(parser));
        QVERIFY(parser.parse({u"hexproof"_s, u"--test-event"_s, u"draft"_s}));
        QVERIFY(LocalTestSession::requested(parser));
        QVERIFY(!LocalTestSession::readOptions(parser).valid());
        QVERIFY(parser.parse({u"hexproof"_s, u"--test-auto-draft"_s}));
        QVERIFY(LocalTestSession::requested(parser));
        QVERIFY(LocalTestSession::readOptions(parser).autoDraft);
        QVERIFY(!LocalTestSession::readOptions(parser).valid());
        auto config = options();
        QVERIFY(config.valid());
        config.players = 9;
        QVERIFY(!config.valid());
        config.eventType = u"sealed"_s;
        QVERIFY(config.valid());
        config.seat = 10;
        QVERIFY(!config.valid());
        config = options(u"commander-cube"_s, 4);
        QVERIFY(config.valid());
        config.autoDraft = true;
        QVERIFY(config.valid());
        config.players = 8;
        QVERIFY(config.valid());
        config.players = 9;
        QVERIFY(!config.valid());
        config.players = 4;
        config.setCode = u"TST"_s;
        QVERIFY(!config.valid());
        config.setCode.clear();
        config.cube = u" "_s;
        QVERIFY(!config.valid());
        for (const QString &mode : {u"draft"_s, u"sealed"_s}) {
            config = options(mode);
            config.autoDraft = true;
            QVERIFY(!config.valid());
        }
    }
    void refusesRemoteServerAndMissingProduct()
    {
        WsClient client;
        QVERIFY(client.setInitialConnection(u"ws://192.0.2.1:57320/ws"_s, u"Seat 1"_s));
        LocalTestSession remote(&client, options(), productForSource);
        QSignalSpy remoteFailure(&remote, &LocalTestSession::failed);
        remote.start();
        QCOMPARE(remoteFailure.count(), 1);
        QCOMPARE(client.connectionState(), WsClient::Disconnected);
        QVERIFY(client.setInitialConnection(u"ws://127.0.0.1:57320/ws"_s, u"Seat 1"_s));
        auto config = options();
        config.setCode = u"MISSING"_s;
        LocalTestSession missing(&client, config, productForSource);
        QSignalSpy missingFailure(&missing, &LocalTestSession::failed);
        missing.start();
        QCOMPARE(missingFailure.count(), 1);
        QVERIFY(
            missingFailure.first().first().toString().contains(u"No installed Limited product"_s));
        QCOMPARE(client.connectionState(), WsClient::Disconnected);
        config = options(u"commander-cube"_s, 4);
        config.cube = u"Missing Cube"_s;
        LocalTestSession missingCube(&client, config, productForSource);
        QSignalSpy cubeFailure(&missingCube, &LocalTestSession::failed);
        missingCube.start();
        QCOMPARE(cubeFailure.count(), 1);
        QVERIFY(cubeFailure.first().first().toString().contains(u"No unique ready Cube"_s));
        QCOMPARE(client.connectionState(), WsClient::Disconnected);
    }
    void preparesRealEvent_data()
    {
        QTest::addColumn<QString>("mode");
        QTest::addColumn<int>("players");
        QTest::addColumn<bool>("autoDraft");
        QTest::newRow("two-player-draft") << u"draft"_s << 2 << false;
        QTest::newRow("eight-player-draft") << u"draft"_s << 8 << false;
        QTest::newRow("four-player-sealed") << u"sealed"_s << 4 << false;
        QTest::newRow("four-player-commander-cube") << u"commander-cube"_s << 4 << false;
        QTest::newRow("eight-player-commander-cube") << u"commander-cube"_s << 8 << false;
        QTest::newRow("four-player-commander-auto-draft") << u"commander-cube"_s << 4 << true;
        QTest::newRow("eight-player-commander-auto-draft") << u"commander-cube"_s << 8 << true;
    }
    void preparesRealEvent()
    {
        QFETCH(QString, mode);
        QFETCH(int, players);
        QFETCH(bool, autoDraft);
        Server server;
        QVERIFY2(server.start(),
                 "Build the Go server before running local setup integration tests.");
        auto config = options(mode, players);
        config.autoDraft = autoDraft;
        std::vector<std::unique_ptr<Worker>> workers;
        // Followers must also find a leader that has not connected yet.
        for (int seat = players; seat >= 1; --seat) {
            auto worker = std::make_unique<Worker>();
            QVERIFY(worker->directory.isValid());
            QStringList arguments{u"--worker-dir"_s,   worker->directory.path(),
                                  u"--server-url"_s,   server.url,
                                  u"--test-event"_s,   mode,
                                  u"--test-group"_s,   config.group,
                                  u"--test-players"_s, QString::number(players),
                                  u"--test-seat"_s,    QString::number(seat)};
            if (config.commanderCube())
                arguments.append({u"--test-cube"_s, config.cube});
            else
                arguments.append({u"--test-set"_s, config.setCode});
            if (autoDraft)
                arguments.append(u"--test-auto-draft"_s);
            worker->process.start(QCoreApplication::applicationFilePath(), arguments);
            QVERIFY(worker->process.waitForStarted(2000));
            workers.push_back(std::move(worker));
        }
        QString id;
        QSet<QString> participantIds;
        QSet<QString> cardInstanceIds;
        for (const auto &worker : workers) {
            QTRY_VERIFY_WITH_TIMEOUT(
                QFileInfo::exists(worker->directory.filePath(u"result.json"_s)), 8000);
        }
        for (const auto &worker : workers) {
            QFile release(worker->directory.filePath(u"release"_s));
            QVERIFY(release.open(QIODevice::WriteOnly));
        }
        for (const auto &worker : workers) {
            if (worker->process.state() != QProcess::NotRunning)
                QVERIFY2(worker->process.waitForFinished(8000), "Local setup worker timed out.");
            QFile file(worker->directory.filePath(u"result.json"_s));
            QVERIFY2(file.open(QIODevice::ReadOnly),
                     worker->process.readAllStandardError().constData());
            const auto result = QJsonDocument::fromJson(file.readAll()).object();
            QVERIFY2(result.value(u"error"_s).toString().isEmpty(),
                     qPrintable(result.value(u"error"_s).toString()));
            QCOMPARE(worker->process.exitCode(), 0);
            const QString eventId = result.value(u"tournamentId"_s).toString();
            QVERIFY(!eventId.isEmpty());
            if (id.isEmpty())
                id = eventId;
            QCOMPARE(eventId, id);
            QCOMPARE(result.value(u"registered"_s).toInt(), players);
            QCOMPARE(result.value(u"checkedIn"_s).toInt(), players);
            const QString participantId = result.value(u"participantId"_s).toString();
            QVERIFY(!participantId.isEmpty());
            QVERIFY(!participantIds.contains(participantId));
            participantIds.insert(participantId);
            QCOMPARE(result.value(u"stage"_s).toString(),
                     mode == u"sealed"_s || autoDraft ? u"deck_building"_s : u"draft"_s);
            const auto cards = result.value(u"cards"_s).toArray();
            const int openingCards =
                config.commanderCube() ? (players <= 4 ? 40 : 20) : (mode == u"draft"_s ? 15 : 90);
            const int expectedCards = autoDraft ? (players <= 4 ? 120 : 60) : openingCards;
            QCOMPARE(cards.size(), expectedCards);
            QVERIFY(!result.value(u"deckSubmitted"_s).toBool());
            if (mode != u"sealed"_s && !autoDraft)
                QCOMPARE(result.value(u"poolSize"_s).toInt(), 0);
            if (config.commanderCube()) {
                QVERIFY(result.value(u"cubeRoom"_s).toBool());
                QCOMPARE(result.value(u"packs"_s).toInt(), autoDraft ? 0 : (players <= 4 ? 2 : 1));
                if (!autoDraft)
                    QCOMPARE(result.value(u"picksRequired"_s).toInt(), players <= 4 ? 4 : 2);
                QCOMPARE(result.value(u"packsPerPlayer"_s).toInt(), players <= 4 ? 6 : 3);
                if (autoDraft) {
                    QCOMPARE(result.value(u"poolSize"_s).toInt(), expectedCards);
                    QCOMPARE(result.value(u"optionalCards"_s).toInt(), 3);
                    QCOMPARE(result.value(u"mainboardCards"_s).toInt(), 0);
                    QCOMPARE(result.value(u"commanderCards"_s).toInt(), 0);
                }
            }
            for (const auto &card : cards) {
                const QString cardId = card.toString();
                QVERIFY(!cardId.isEmpty());
                QVERIFY(!cardInstanceIds.contains(cardId));
                cardInstanceIds.insert(cardId);
            }
        }
    }
    void waitsForMissingSeatsAndTimesOut()
    {
        Server server;
        QVERIFY(server.start());
        WsClient client;
        QVERIFY(client.setInitialConnection(server.url, u"Organizer"_s));
        auto config = options();
        config.timeoutMs = 1200;
        LocalTestSession setup(&client, config, productForSource);
        QSignalSpy failure(&setup, &LocalTestSession::failed);
        QSignalSpy completed(&setup, &LocalTestSession::finished);
        setup.start();
        QTRY_COMPARE_WITH_TIMEOUT(failure.count(), 1, 3000);
        QCOMPARE(completed.count(), 0);
        QCOMPARE(client.tournamentSession()->status(), u"registration"_s);
        QCOMPARE(client.tournamentSession()->checkedIn(), 1);
        QVERIFY(client.limitedSession()->currentPack().isEmpty());
        QVERIFY(failure.first().first().toString().contains(u"Timed out"_s));
        setup.start();
        QTest::qWait(200);
        QCOMPARE(failure.count(), 1);
        client.disconnectFromHub();
    }

  private:
    QTemporaryDir m_settings;
};

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    if (app.arguments().contains(u"--worker-dir"_s))
        return runWorker(app);
    TestLocalTestSession test;
    return QTest::qExec(&test, argc, argv);
}
#include "localtestsession_test.moc"
