// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "models/ClientPreferencesModel.h"
#include "models/GameTableModel.h"
#include "models/OptimisticCommandModel.h"
#include "models/SideboardTableModel.h"
#include "services/LimitedDeckDraftStore.h"
#include "services/RulesCombatModel.h"
#include "services/RulesSessionState.h"
#include "services/TranslationController.h"

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
    Q_PROPERTY(QString currentDeckTableMode READ currentDeckTableMode CONSTANT)
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
        return QStringLiteral("modern");
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
    Q_INVOKABLE void resetCapturedCalls()
    {
        m_lastMove.clear();
        m_lastCountChange.clear();
        m_lastPrintingChange.clear();
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

class QmlTestSetup : public QObject
{
    Q_OBJECT

  public:
    const QStringList &qmlWarnings() const
    {
        return m_qmlWarnings;
    }

  public slots:
    void qmlEngineAvailable(QQmlEngine *engine)
    {
        // This also covers component construction before initTestCase(), when
        // per-test failOnWarning() handlers have not yet been installed.
        connect(engine, &QQmlEngine::warnings, this, [this](const QList<QQmlError> &warnings) {
            for (const QQmlError &warning : warnings)
                m_qmlWarnings.append(warning.toString());
        });
        auto *translations = new hexproof::client::TranslationController(engine, engine);
        engine->rootContext()->setContextProperty(QStringLiteral("testTranslations"), translations);
        engine->rootContext()->setContextProperty(
            QStringLiteral("preferences"),
            new hexproof::client::ClientPreferencesModel(m_preferencesStorage.path(), engine));
        engine->rootContext()->setContextProperty(QStringLiteral("testRoomList"),
                                                  new RoomListSequenceStub(engine));
        auto *optimisticCommands = new hexproof::client::OptimisticCommandModel(engine);
        engine->rootContext()->setContextProperty(QStringLiteral("testOptimisticCommands"),
                                                  optimisticCommands);
        auto *sideboardTable = new hexproof::client::SideboardTableModel(engine);
        engine->rootContext()->setContextProperty(QStringLiteral("testSideboardTable"),
                                                  sideboardTable);
        auto *gameTable = new hexproof::client::GameTableModel(engine);
        engine->rootContext()->setContextProperty(QStringLiteral("testGameTable"), gameTable);
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
    }

  private:
    QStringList m_qmlWarnings;
    QTemporaryDir m_preferencesStorage;
    QTemporaryDir m_draftStorage;
};

int main(int argc, char **argv)
{
    QTEST_SET_MAIN_SOURCE_PATH
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
