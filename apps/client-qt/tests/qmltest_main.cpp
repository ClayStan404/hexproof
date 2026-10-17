// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "UiLanguages.h"
#include "models/ClientPreferencesModel.h"
#include "models/GameTableModel.h"
#include "models/OptimisticCommandModel.h"
#include "models/SideboardTableModel.h"
#include "services/DraftSimulator.h"
#include "services/ForgeReplayService.h"
#include "services/LimitedDeckDraftStore.h"
#include "services/PublicContentService.h"
#include "services/RulesCombatModel.h"
#include "services/RulesSessionState.h"
#include "services/TranslationController.h"

#include <QFile>
#include <QFontDatabase>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlError>
#include <QStringList>
#include <QTemporaryDir>
#include <QVariantList>
#include <QVariantMap>
#include <QtQuickTest>

#include <cstdio>

// Match WsClient's shared notification signal: there is no connectedChanged.
class LimitedDraftTransportStub : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool connected READ connected NOTIFY connectionStateChanged)
    Q_PROPERTY(int pickCount READ pickCount NOTIFY pickCountChanged)

  public:
    explicit LimitedDraftTransportStub(QObject *parent = nullptr)
        : QObject(parent)
    {
    }

    bool connected() const
    {
        return m_connected;
    }
    int pickCount() const
    {
        return m_pickCount;
    }
    Q_INVOKABLE void setConnected(bool connected)
    {
        if (m_connected == connected)
            return;
        m_connected = connected;
        emit connectionStateChanged();
    }
    Q_INVOKABLE void pickLimitedCard(const QString &)
    {
        ++m_pickCount;
        emit pickCountChanged();
    }
    Q_INVOKABLE void reset()
    {
        setConnected(true);
        m_pickCount = 0;
        emit pickCountChanged();
    }

  signals:
    void connectionStateChanged();
    void pickCountChanged();

  private:
    bool m_connected = true;
    int m_pickCount = 0;
};

// Mirrors WsClient::roomList: a Q_PROPERTY(QVariantList) sequence. QML's
// Array.isArray() is false for these, even though .length and indexing work.
class RoomListSequenceStub : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList roomList READ roomList CONSTANT)

  public:
    explicit RoomListSequenceStub(QObject *parent = nullptr)
        : QObject(parent)
    {
        m_rooms.append(QVariantMap{
            {QStringLiteral("roomId"), QStringLiteral("WAIT01")},
            {QStringLiteral("name"), QStringLiteral("Friday Modern")},
            {QStringLiteral("format"), QStringLiteral("modern")},
            {QStringLiteral("phase"), QStringLiteral("waiting")},
            {QStringLiteral("hasPassword"), false},
            {QStringLiteral("playerJoinable"), true},
            {QStringLiteral("spectatorJoinable"), true},
            {QStringLiteral("playerCount"), 1},
            {QStringLiteral("maxSeats"), 2},
        });
    }

    QVariantList roomList() const
    {
        return m_rooms;
    }

  private:
    QVariantList m_rooms;
};

class DeckEditorModelStub : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString currentDeckId READ currentDeckId CONSTANT)
    Q_PROPERTY(QString currentDeckName READ currentDeckName CONSTANT)
    Q_PROPERTY(QString currentDeckFormat READ currentDeckFormat CONSTANT)
    Q_PROPERTY(QString currentDeckTableMode READ currentDeckTableMode WRITE setCurrentDeckTableMode
                   NOTIFY currentDeckChanged)
    Q_PROPERTY(QVariantList mainCards READ mainCards CONSTANT)
    Q_PROPERTY(QVariantList sideboardCards READ sideboardCards CONSTANT)
    Q_PROPERTY(QVariantList considerCards READ considerCards CONSTANT)
    Q_PROPERTY(QVariantList currentTokens READ currentTokens CONSTANT)
    Q_PROPERTY(int currentMainCount READ currentMainCount CONSTANT)
    Q_PROPERTY(int currentSideboardCount READ currentSideboardCount CONSTANT)
    Q_PROPERTY(int currentConsiderCount READ currentConsiderCount CONSTANT)
    Q_PROPERTY(bool currentReady READ currentReady CONSTANT)
    Q_PROPERTY(bool currentValidationVerified READ currentValidationVerified CONSTANT)
    Q_PROPERTY(QStringList currentValidationWarnings READ currentValidationWarnings CONSTANT)
    Q_PROPERTY(QStringList currentValidationIssues READ currentValidationIssues CONSTANT)
    Q_PROPERTY(QString currentStatus READ currentStatus CONSTANT)
    Q_PROPERTY(QString lastError READ lastError CONSTANT)
    Q_PROPERTY(QVariantList lastMove READ lastMove NOTIFY capturedCallsChanged)
    Q_PROPERTY(QVariantList lastCountChange READ lastCountChange NOTIFY capturedCallsChanged)
    Q_PROPERTY(QVariantList lastPrintingChange READ lastPrintingChange NOTIFY capturedCallsChanged)
    Q_PROPERTY(QString lastRename READ lastRename NOTIFY capturedCallsChanged)

  public:
    explicit DeckEditorModelStub(QObject *parent = nullptr)
        : QObject(parent)
    {
        m_mainCards = {
            QVariantMap{{QStringLiteral("name"), QStringLiteral("Lightning Bolt")},
                        {QStringLiteral("displayName"), QStringLiteral("Lightning Bolt")},
                        {QStringLiteral("typeLine"), QStringLiteral("Instant")},
                        {QStringLiteral("category"), QStringLiteral("Spells")},
                        {QStringLiteral("setCode"), QStringLiteral("M11")},
                        {QStringLiteral("collectorNumber"), QStringLiteral("149")},
                        {QStringLiteral("count"), 1},
                        {QStringLiteral("manaValue"), 1.0},
                        {QStringLiteral("commander"), false}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("Lightning Bolt")},
                        {QStringLiteral("displayName"), QStringLiteral("Lightning Bolt")},
                        {QStringLiteral("typeLine"), QStringLiteral("Instant")},
                        {QStringLiteral("category"), QStringLiteral("Spells")},
                        {QStringLiteral("setCode"), QStringLiteral("2X2")},
                        {QStringLiteral("collectorNumber"), QStringLiteral("117")},
                        {QStringLiteral("count"), 1},
                        {QStringLiteral("manaValue"), 1.0},
                        {QStringLiteral("commander"), false}},
        };
        m_sideboardCards = {
            QVariantMap{{QStringLiteral("name"), QStringLiteral("Counterspell")},
                        {QStringLiteral("displayName"), QStringLiteral("Counterspell")},
                        {QStringLiteral("typeLine"), QStringLiteral("Instant")},
                        {QStringLiteral("category"), QStringLiteral("Spells")},
                        {QStringLiteral("setCode"), QStringLiteral("MH2")},
                        {QStringLiteral("collectorNumber"), QStringLiteral("267")},
                        {QStringLiteral("count"), 2},
                        {QStringLiteral("manaValue"), 2.0},
                        {QStringLiteral("commander"), false}},
        };
    }

    QString currentDeckId() const
    {
        return QStringLiteral("qml-editor-test");
    }
    QString currentDeckName() const
    {
        return QStringLiteral("QML editor test");
    }
    QString currentDeckFormat() const
    {
        return QStringLiteral("modern");
    }
    QString currentDeckTableMode() const
    {
        return m_tableMode;
    }
    void setCurrentDeckTableMode(const QString &mode)
    {
        if (m_tableMode == mode)
            return;
        m_tableMode = mode;
        emit currentDeckChanged();
    }
    QVariantList mainCards() const
    {
        return m_mainCards;
    }
    QVariantList sideboardCards() const
    {
        return m_sideboardCards;
    }
    Q_INVOKABLE QVariantList cardArtExportRequests(const QString &id) const
    {
        return id == currentDeckId() ? mainCards() + sideboardCards() : QVariantList{};
    }
    QVariantList considerCards() const
    {
        return {};
    }
    QVariantList currentTokens() const
    {
        return {};
    }
    int currentMainCount() const
    {
        return 2;
    }
    int currentSideboardCount() const
    {
        return 2;
    }
    int currentConsiderCount() const
    {
        return 0;
    }
    bool currentReady() const
    {
        return true;
    }
    bool currentValidationVerified() const
    {
        return true;
    }
    QStringList currentValidationWarnings() const
    {
        return {};
    }
    QStringList currentValidationIssues() const
    {
        return {};
    }
    QString currentStatus() const
    {
        return QStringLiteral("Playable");
    }
    QString lastError() const
    {
        return {};
    }
    QVariantList lastMove() const
    {
        return m_lastMove;
    }
    QVariantList lastCountChange() const
    {
        return m_lastCountChange;
    }
    QVariantList lastPrintingChange() const
    {
        return m_lastPrintingChange;
    }
    QString lastRename() const
    {
        return m_lastRename;
    }

    Q_INVOKABLE bool canAddCard(const QString &, const QString &) const
    {
        return true;
    }
    Q_INVOKABLE QVariantList matchDecks(const QString &, bool) const
    {
        return {};
    }
    Q_INVOKABLE bool moveCard(const QString &name, const QString &setCode,
                              const QString &collectorNumber, bool toSideboard)
    {
        m_lastMove = {name, setCode, collectorNumber, toSideboard};
        emit capturedCallsChanged();
        return true;
    }
    Q_INVOKABLE bool changeCardCount(const QString &name, const QString &setCode,
                                     const QString &collectorNumber, bool sideboard, int delta)
    {
        m_lastCountChange = {name, setCode, collectorNumber, sideboard, delta};
        emit capturedCallsChanged();
        return true;
    }
    Q_INVOKABLE bool setCardPrinting(const QString &name, const QString &currentSetCode,
                                     const QString &currentCollectorNumber, bool sideboard,
                                     const QString &localizedName, const QString &typeLine,
                                     const QString &setCode, const QString &collectorNumber)
    {
        m_lastPrintingChange = {name,      currentSetCode, currentCollectorNumber,
                                sideboard, localizedName,  typeLine,
                                setCode,   collectorNumber};
        emit capturedCallsChanged();
        return true;
    }
    Q_INVOKABLE bool renameCurrentDeck(const QString &name)
    {
        m_lastRename = name.trimmed();
        emit capturedCallsChanged();
        return !m_lastRename.isEmpty();
    }
    Q_INVOKABLE void resetCapturedCalls()
    {
        m_lastMove.clear();
        m_lastCountChange.clear();
        m_lastPrintingChange.clear();
        m_lastRename.clear();
        emit capturedCallsChanged();
    }

  signals:
    void currentDeckCardsAboutToChange();
    void currentDeckCardsChanged();
    void currentDeckChanged();
    void capturedCallsChanged();

  private:
    QVariantList m_mainCards;
    QVariantList m_sideboardCards;
    QVariantList m_lastMove;
    QVariantList m_lastCountChange;
    QVariantList m_lastPrintingChange;
    QString m_lastRename;
    QString m_tableMode = QStringLiteral("modern");
};

class DeckEditorCatalogStub : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool installed READ installed CONSTANT)
    Q_PROPERTY(bool busy READ busy CONSTANT)
    Q_PROPERTY(bool searching READ searching CONSTANT)
    Q_PROPERTY(bool enhancedIndexInstalled READ enhancedIndexInstalled CONSTANT)
    Q_PROPERTY(bool chineseIndexInstalled READ chineseIndexInstalled CONSTANT)
    Q_PROPERTY(bool tokenCatalogInstalled READ tokenCatalogInstalled CONSTANT)
    Q_PROPERTY(int imageRevision READ imageRevision CONSTANT)
    Q_PROPERTY(QString status READ status CONSTANT)
    Q_PROPERTY(QString printingsError READ printingsError CONSTANT)
    Q_PROPERTY(QVariantList searchResults READ searchResults CONSTANT)

  public:
    explicit DeckEditorCatalogStub(QObject *parent = nullptr)
        : QObject(parent)
    {
    }

    bool installed() const
    {
        return true;
    }
    bool busy() const
    {
        return false;
    }
    bool searching() const
    {
        return false;
    }
    bool enhancedIndexInstalled() const
    {
        return true;
    }
    bool chineseIndexInstalled() const
    {
        return true;
    }
    bool tokenCatalogInstalled() const
    {
        return false;
    }
    int imageRevision() const
    {
        return -1;
    }
    QString status() const
    {
        return {};
    }
    QString printingsError() const
    {
        return {};
    }
    QVariantList searchResults() const
    {
        return {};
    }
    Q_INVOKABLE QString imageSource(const QString &, const QString &, const QString &) const
    {
        return {};
    }
    Q_INVOKABLE QVariantList printings(const QString &) const
    {
        return {
            QVariantMap{{QStringLiteral("name"), QStringLiteral("Lightning Bolt")},
                        {QStringLiteral("displayName"), QStringLiteral("Lightning Bolt M11")},
                        {QStringLiteral("typeLine"), QStringLiteral("Instant M11")},
                        {QStringLiteral("setCode"), QStringLiteral("M11")},
                        {QStringLiteral("collectorNumber"), QStringLiteral("149")}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("Lightning Bolt")},
                        {QStringLiteral("displayName"), QStringLiteral("Lightning Bolt 2X2")},
                        {QStringLiteral("typeLine"), QStringLiteral("Instant 2X2")},
                        {QStringLiteral("setCode"), QStringLiteral("2X2")},
                        {QStringLiteral("collectorNumber"), QStringLiteral("117")}},
        };
    }
    Q_INVOKABLE void cacheCardsIncrementally(const QVariantList &) {}

  signals:
    void cardCacheFinished(const QString &name, const QString &setCode,
                           const QString &collectorNumber, bool success);
};

class RulesPromptFixture : public QObject
{
    Q_OBJECT
    Q_PROPERTY(hexproof::client::RulesSessionState *session READ session CONSTANT)

  public:
    explicit RulesPromptFixture(QObject *parent = nullptr)
        : QObject(parent),
          m_session(this)
    {
    }

    hexproof::client::RulesSessionState *session()
    {
        return &m_session;
    }

    Q_INVOKABLE void clear()
    {
        m_session.clear();
    }

    Q_INVOKABLE bool applySnapshot(const QVariantMap &snapshot)
    {
        return m_session.applySnapshot(QJsonObject::fromVariantMap(snapshot));
    }

    Q_INVOKABLE bool applyPrompt(const QVariantMap &prompt)
    {
        return m_session.applyPrompt(QJsonObject::fromVariantMap(prompt));
    }

    Q_INVOKABLE QVariantList corpusCases()
    {
        m_corpus.clear();
        QVariantList cases;
        const auto path = qEnvironmentVariable("HEXPROOF_FORGE_CORPUS_UI");
        if (path.isEmpty())
            return cases;
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly))
            qFatal("Cannot open Forge corpus UI evidence");
        while (!file.atEnd()) {
            const auto line = file.readLine();
            const auto value = QJsonDocument::fromJson(line).object();
            if (value.isEmpty())
                qFatal("Invalid Forge corpus UI record");
            const auto tag = value.value(QStringLiteral("card")).toString() + QStringLiteral("/") +
                             value.value(QStringLiteral("case")).toString();
            cases.append(QVariantMap{{QStringLiteral("tag"), tag},
                                     {QStringLiteral("index"), m_corpus.size()}});
            m_corpus.append(line);
        }
        return cases;
    }

    Q_INVOKABLE QVariantMap corpusCase(int index) const
    {
        return QJsonDocument::fromJson(m_corpus.value(index)).object().toVariantMap();
    }

    Q_INVOKABLE QString corpusEnvironment(const QString &name) const
    {
        return name.startsWith(QStringLiteral("HEXPROOF_FORGE_CORPUS_"))
                   ? qEnvironmentVariable(name.toUtf8().constData())
                   : QString();
    }

  private:
    hexproof::client::RulesSessionState m_session;
    QList<QByteArray> m_corpus;
};

class QmlTestSetup : public QObject
{
    Q_OBJECT

  public:
    const QStringList &qmlWarnings() const
    {
        return m_qmlWarnings;
    }

  public slots:
    void applicationAvailable()
    {
        if (QFontDatabase::families().isEmpty())
            qFatal("QML layout tests require an installed font database");
    }

    void qmlEngineAvailable(QQmlEngine *engine)
    {
        engine->rootContext()->setContextProperty(
            QStringLiteral("publicContent"),
            new hexproof::client::PublicContentService(m_preferencesStorage.path(), QStringList{},
                                                       engine));
        // This also covers component construction before initTestCase(), when
        // per-test failOnWarning() handlers have not yet been installed.
        connect(engine, &QQmlEngine::warnings, this, [this](const QList<QQmlError> &warnings) {
            for (const QQmlError &warning : warnings)
                m_qmlWarnings.append(warning.toString());
        });
        engine->rootContext()->setContextProperty(QStringLiteral("hexproofTestMotion"), false);
        engine->rootContext()->setContextProperty(QStringLiteral("hexproofMotion"), false);
        auto *translations = new hexproof::client::TranslationController(engine, engine);
        engine->rootContext()->setContextProperty(QStringLiteral("testTranslations"), translations);
        engine->rootContext()->setContextProperty(QStringLiteral("uiLanguages"),
                                                  hexproof::client::uiLanguages::qmlOptions());
        engine->rootContext()->setContextProperty(
            QStringLiteral("preferences"),
            new hexproof::client::ClientPreferencesModel(m_preferencesStorage.path(), engine));
        engine->rootContext()->setContextProperty(QStringLiteral("testRoomList"),
                                                  new RoomListSequenceStub(engine));
        engine->rootContext()->setContextProperty(QStringLiteral("testLimitedDraftTransport"),
                                                  new LimitedDraftTransportStub(engine));
        auto *optimisticCommands = new hexproof::client::OptimisticCommandModel(engine);
        engine->rootContext()->setContextProperty(QStringLiteral("testOptimisticCommands"),
                                                  optimisticCommands);
        auto *sideboardTable = new hexproof::client::SideboardTableModel(engine);
        engine->rootContext()->setContextProperty(QStringLiteral("testSideboardTable"),
                                                  sideboardTable);
        auto *gameTable = new hexproof::client::GameTableModel(engine);
        engine->rootContext()->setContextProperty(QStringLiteral("testGameTable"), gameTable);
        auto *replays = new hexproof::client::ForgeReplayService(engine, m_replayStorage.path());
        using namespace Qt::StringLiterals;
        // Exercise the production player against one shared service and two
        // locally saved archives, without an engine or network dependency.
        for (const QChar digit : {u'a', u'c'}) {
            const QString id(64, digit);
            const QString server = u"ws://localhost:57320"_s;
            replays->acceptGrant(server, {{u"replayId"_s, id},
                                          {u"token"_s, QString(64, u'b')},
                                          {u"roomName"_s, u"Replay controls test"_s},
                                          {u"players"_s, QJsonArray{u"Alice"_s, u"Bob"_s}},
                                          {u"finished"_s, true},
                                          {u"complete"_s, true}});
            replays->download(id);
            QJsonArray frames;
            for (int sequence = 1; sequence <= 3; ++sequence) {
                const QJsonObject snapshot{
                    {u"roomId"_s, u"REPLAY01"_s},
                    {u"gameId"_s, id},
                    {u"turn"_s, sequence},
                    {u"activeSeat"_s, 0},
                    {u"prioritySeat"_s, 0},
                    {u"players"_s, QJsonArray{QJsonObject{{u"seat"_s, 0}, {u"life"_s, 20}},
                                              QJsonObject{{u"seat"_s, 1}, {u"life"_s, 20}}}},
                    {u"zones"_s, QJsonArray{}},
                    {u"stack"_s, QJsonArray{}}};
                frames.append(QJsonObject{{u"sequence"_s, sequence},
                                          {u"gameNumber"_s, 1},
                                          {u"kind"_s, u"CardTapped"_s},
                                          {u"snapshot"_s, snapshot}});
            }
            replays->acceptPage(server, {{u"replayId"_s, id},
                                         {u"schemaVersion"_s, 1},
                                         {u"offset"_s, 0},
                                         {u"total"_s, frames.size()},
                                         {u"complete"_s, true},
                                         {u"frames"_s, frames}});
        }
        engine->rootContext()->setContextProperty(QStringLiteral("testReplays"), replays);
        auto *rulesSnapshot = new hexproof::client::RulesSessionState(engine);
        rulesSnapshot->applySnapshot(QJsonDocument::fromJson(R"json({
            "roomId": "RULE01", "gameId": "rules-stack-fixture", "players": [], "zones": [],
            "stack": [
                {"id": "hidden-spell", "controllerSeat": 1, "text": "Face-down spell"},
                {"id": "visible-spell", "controllerSeat": 0, "text": "Lightning Bolt",
                 "identity": {"name": "Lightning Bolt", "setCode": "M11", "collectorNumber": "149"}}
            ]
        })json")
                                         .object());
        engine->rootContext()->setContextProperty(QStringLiteral("testRulesSnapshot"),
                                                  rulesSnapshot);
        engine->rootContext()->setContextProperty(QStringLiteral("testRulesPrompt"),
                                                  new RulesPromptFixture(engine));
        auto *combatSources = new hexproof::client::RulesCombatModel(engine);
        QVector<hexproof::client::RulesCombatSourceRow> sources;
        for (int index = 0; index < 8; ++index) {
            hexproof::client::RulesCombatSourceRow source;
            source.responseId = QStringLiteral("attacker:%1").arg(index);
            source.label = QStringLiteral("Raging Goblin %1").arg(index);
            source.name = QStringLiteral("Raging Goblin");
            source.setCode = QStringLiteral("M10");
            source.collectorNumber = QStringLiteral("154");
            source.validTargetIds = {QStringLiteral("player:1")};
            sources.append(source);
        }
        hexproof::client::RulesCombatTargetRow defender;
        defender.responseId = QStringLiteral("player:1");
        defender.kind = QStringLiteral("player");
        defender.label = QStringLiteral("Opponent");
        combatSources->replace(sources, {defender});
        engine->rootContext()->setContextProperty(QStringLiteral("testRulesCombatSources"),
                                                  combatSources);
        engine->rootContext()->setContextProperty(QStringLiteral("deckLibrary"),
                                                  new DeckEditorModelStub(engine));
        engine->rootContext()->setContextProperty(QStringLiteral("cardCatalog"),
                                                  new DeckEditorCatalogStub(engine));
        engine->rootContext()->setContextProperty(
            QStringLiteral("testLimitedDraftStore"),
            new hexproof::client::LimitedDeckDraftStore(m_draftStorage.path(), engine));
        auto *simulator = new hexproof::client::DraftSimulator(engine);
        simulator->setPackGenerator([](const QVariantMap &product, int count) {
            QVariantList packs;
            for (int pack = 0; pack < count; ++pack) {
                QVariantList cards;
                for (int card = 0; card < product.value(QStringLiteral("cardsPerPack")).toInt();
                     ++card)
                    cards.append(QVariantMap{{"name", "Test creature"},
                                             {"setCode", "TST"},
                                             {"collectorNumber", QString::number(card)},
                                             {"typeLine", "Creature"},
                                             {"rarity", "common"},
                                             {"cardColors", "U"},
                                             {"manaCost", "{1}{U}"},
                                             {"manaValue", 2}});
                packs.append(QVariantMap{{"cards", cards}});
            }
            return packs;
        });
        simulator->setDeckSaver([](const QString &, const QVariantMap &) { return QString{}; });
        engine->rootContext()->setContextProperty(QStringLiteral("testDraftSimulator"), simulator);
    }

  private:
    QStringList m_qmlWarnings;
    QTemporaryDir m_preferencesStorage;
    QTemporaryDir m_draftStorage;
    QTemporaryDir m_replayStorage;
};

int main(int argc, char **argv)
{
    QTEST_SET_MAIN_SOURCE_PATH
#ifdef Q_OS_WIN
    // Windows offscreen uses FreeType instead of the native font database.
    // Without this directory it searches Qt's empty lib/fonts installation.
    if (qEnvironmentVariableIsEmpty("QT_QPA_FONTDIR")) {
        const QByteArray windowsRoot = qgetenv("SystemRoot");
        if (!windowsRoot.isEmpty())
            qputenv("QT_QPA_FONTDIR", windowsRoot + "/Fonts");
    }
#endif
    QmlTestSetup setup;
    const int result = quick_test_main_with_setup(argc, argv, "hexproof_qml", nullptr, &setup);
    if (!setup.qmlWarnings().isEmpty()) {
        std::fprintf(stderr, "QML runtime warnings caused test failure:\n%s\n",
                     setup.qmlWarnings().join(u'\n').toUtf8().constData());
        return result == 0 ? 1 : result;
    }
    return result;
}

#include "qmltest_main.moc"
