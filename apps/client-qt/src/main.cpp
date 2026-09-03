// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "models/ClientPreferencesModel.h"
#include "models/DeckLibraryModel.h"
#include "models/GameTableModel.h"
#include "models/OptimisticCommandModel.h"
#include "models/SideboardTableModel.h"
#include "protocol/Message.h"
#include "services/AppUpdateService.h"
#include "services/CardArtManager.h"
#include "services/CardCatalog.h"
#include "services/CardImageProvider.h"
#include "services/DeckLegalityService.h"
#include "services/LimitedSessionState.h"
#include "services/MatchLoadCoordinator.h"
#include "services/NetworkRequestFactory.h"
#include "services/TournamentSessionState.h"
#include "services/TranslationController.h"
#include "services/WsClient.h"

#include <QCommandLineParser>
#include <QDebug>
#include <QGuiApplication>
#include <QIcon>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlNetworkAccessManagerFactory>
#include <QTimer>
#include <QUrl>

namespace {

class QmlNetworkAccessManager final : public QNetworkAccessManager
{
  public:
    using QNetworkAccessManager::QNetworkAccessManager;

  protected:
    QNetworkReply *createRequest(Operation op, const QNetworkRequest &original,
                                 QIODevice *outgoingData) override
    {
        QNetworkRequest request(original);
        hexproof::client::applyHttpVersionPolicy(request);
        return QNetworkAccessManager::createRequest(op, request, outgoingData);
    }
};

class QmlNetworkFactory final : public QQmlNetworkAccessManagerFactory
{
  public:
    QNetworkAccessManager *create(QObject *parent) override
    {
        return new QmlNetworkAccessManager(parent);
    }
};

} // namespace

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("Hexproof"));
    QGuiApplication::setOrganizationName(QStringLiteral("Hexproof"));
    QGuiApplication::setApplicationVersion(QStringLiteral(HEXPROOF_VERSION));
    // GNOME/Wayland resolves the taskbar/dock icon by matching the window's
    // app_id against an installed <name>.desktop file. Report the reverse-DNS
    // desktop file name so the match resolves to our hicolor icon.
    QGuiApplication::setDesktopFileName(QStringLiteral("io.github.claystan404.hexproof"));
    QGuiApplication::setWindowIcon(QIcon(QStringLiteral(":/assets/hexproof.png")));

    QCommandLineParser commandLine;
    commandLine.setApplicationDescription(QStringLiteral("Hexproof tabletop client"));
    commandLine.addHelpOption();
    commandLine.addVersionOption();
    QCommandLineOption instanceLabelOption(
        QStringLiteral("instance-label"),
        QStringLiteral("Append a label to the application window title."), QStringLiteral("label"));
    QCommandLineOption windowedOption(
        QStringLiteral("windowed"),
        QStringLiteral("Start in a normal window instead of maximized."));
    commandLine.addOption(instanceLabelOption);
    commandLine.addOption(windowedOption);
    commandLine.process(app);

    const QString instanceLabel = commandLine.value(instanceLabelOption).simplified().left(80);
    QGuiApplication::setApplicationDisplayName(
        instanceLabel.isEmpty() ? QStringLiteral("Hexproof")
                                : QStringLiteral("Hexproof — %1").arg(instanceLabel));

    qInfo().noquote() << "Hexproof protocol:" << hexproof::protocol::kProtocolVersion;

    // Destroy network services and models after the QML engine but before the
    // QGuiApplication tears down its event dispatcher.
    QObject runtimeOwner;
    // Expose WsClient to QML as a context property `ws` (owned by runtimeOwner).
    // QML pages reference it directly (e.g. ws.connected, ws.createRoom(...)).
    auto *ws = new hexproof::client::WsClient(&runtimeOwner);
    auto *preferences = new hexproof::client::ClientPreferencesModel(&runtimeOwner);
    auto *deckLibrary = new hexproof::client::DeckLibraryModel(&runtimeOwner);
    auto *gameTable = new hexproof::client::GameTableModel(&runtimeOwner);
    auto *optimisticCommands = new hexproof::client::OptimisticCommandModel(&runtimeOwner);
    auto *sideboardTable = new hexproof::client::SideboardTableModel(&runtimeOwner);
    auto *cardCatalog = new hexproof::client::CardCatalog(&runtimeOwner);
    auto *appUpdater = new hexproof::client::AppUpdateService(&runtimeOwner);
    auto *deckLegality = new hexproof::client::DeckLegalityService(&runtimeOwner);
    auto *matchLoader = new hexproof::client::MatchLoadCoordinator(&runtimeOwner);
    auto *cardArtManager = cardCatalog->artManager();
    cardArtManager->setAuditRequestProvider(
        [deckLibrary]() { return deckLibrary->cardArtAuditRequests(); },
        [preferences]() { return preferences->cardLanguage(); });
    cardCatalog->setLanguage(preferences->cardLanguage());
    cardCatalog->setCardArtProvider(preferences->cardArtProvider());
    cardCatalog->setReuseLocalCardArt(preferences->reuseLocalCardArt());
    QObject::connect(deckLibrary, &hexproof::client::DeckLibraryModel::cardsNeedCaching,
                     cardCatalog, &hexproof::client::CardCatalog::cacheCardsIncrementally);
    QObject::connect(deckLibrary, &hexproof::client::DeckLibraryModel::cardsNeedCachedArtLookup,
                     cardCatalog, &hexproof::client::CardCatalog::hydrateCachedCards,
                     Qt::QueuedConnection);
    QObject::connect(deckLibrary, &hexproof::client::DeckLibraryModel::cardsNeedRetry, cardCatalog,
                     &hexproof::client::CardCatalog::retryCards);
    QObject::connect(deckLibrary, &hexproof::client::DeckLibraryModel::tokensNeedMetadata,
                     cardCatalog, &hexproof::client::CardCatalog::enrichTokens);
    QObject::connect(deckLibrary, &hexproof::client::DeckLibraryModel::decksNeedValidation,
                     deckLegality, &hexproof::client::DeckLegalityService::validateDecks);
    QObject::connect(deckLegality, &hexproof::client::DeckLegalityService::validationReady,
                     deckLibrary, &hexproof::client::DeckLibraryModel::applyDeckValidation);
    QObject::connect(preferences, &hexproof::client::ClientPreferencesModel::cardLanguageChanged,
                     cardCatalog, [preferences, deckLibrary, cardCatalog]() {
                         cardCatalog->setLanguage(preferences->cardLanguage());
                         deckLibrary->refreshCardArt();
                     });
    QObject::connect(preferences, &hexproof::client::ClientPreferencesModel::cardArtProviderChanged,
                     cardCatalog, [preferences, cardCatalog]() {
                         cardCatalog->setCardArtProvider(preferences->cardArtProvider());
                     });
    QObject::connect(preferences,
                     &hexproof::client::ClientPreferencesModel::reuseLocalCardArtChanged,
                     cardCatalog, [preferences, deckLibrary, cardCatalog]() {
                         cardCatalog->setReuseLocalCardArt(preferences->reuseLocalCardArt());
                         deckLibrary->refreshCardArt();
                     });
    QObject::connect(cardCatalog, &hexproof::client::CardCatalog::cardAvailable, deckLibrary,
                     &hexproof::client::DeckLibraryModel::applyCardMetadata);
    QObject::connect(deckLibrary, &hexproof::client::DeckLibraryModel::cardsNeedMetadata,
                     cardCatalog, &hexproof::client::CardCatalog::enrichCardMetadata);
    QObject::connect(cardCatalog, &hexproof::client::CardCatalog::cardMetadataAvailable,
                     deckLibrary, &hexproof::client::DeckLibraryModel::applyCatalogMetadata);
    QObject::connect(cardCatalog, &hexproof::client::CardCatalog::catalogChanged, deckLibrary,
                     [deckLibrary]() { deckLibrary->hydrateCatalogMetadata(true); });
    QObject::connect(cardCatalog, &hexproof::client::CardCatalog::languageChanged, deckLibrary,
                     [deckLibrary]() { deckLibrary->hydrateCatalogMetadata(true); });
    QObject::connect(cardCatalog, &hexproof::client::CardCatalog::artCacheContentsChanged,
                     deckLibrary, &hexproof::client::DeckLibraryModel::refreshCachedCardArt);
    deckLibrary->hydrateCatalogMetadata();
    QObject::connect(cardCatalog, &hexproof::client::CardCatalog::tokenMetadataAvailable,
                     deckLibrary, &hexproof::client::DeckLibraryModel::applyTokenMetadata);
    QObject::connect(cardCatalog, &hexproof::client::CardCatalog::catalogChanged, deckLibrary,
                     &hexproof::client::DeckLibraryModel::refreshTokenMetadata);
    QObject::connect(cardCatalog, &hexproof::client::CardCatalog::catalogChanged, deckLibrary,
                     &hexproof::client::DeckLibraryModel::refreshDeckValidation);
    QTimer::singleShot(0, deckLibrary, &hexproof::client::DeckLibraryModel::refreshDeckValidation);
    QObject::connect(ws, &hexproof::client::WsClient::loadRequired, matchLoader,
                     [ws, matchLoader, cardCatalog](qint64 loadId, const QVariantList &cardKeys) {
                         if (ws->cardLoadMode() == hexproof::protocol::kCardLoadPreload) {
                             matchLoader->beginLoad(loadId,
                                                    cardCatalog->expandCardFaceRequests(cardKeys));
                             return;
                         }
                         // Let match.started construct and paint the table before
                         // background metadata/image work begins on the GUI thread.
                         QTimer::singleShot(
                             500, matchLoader, [ws, matchLoader, cardCatalog, loadId, cardKeys]() {
                                 if (ws->inRoom() && ws->loadId() == loadId)
                                     matchLoader->beginLoad(
                                         loadId, cardCatalog->expandCardFaceRequests(cardKeys));
                             });
                     });
    QObject::connect(ws, &hexproof::client::WsClient::gameSnapshotDataChanged, gameTable,
                     &hexproof::client::GameTableModel::applySnapshot);
    QObject::connect(matchLoader, &hexproof::client::MatchLoadCoordinator::cardsRequested,
                     cardCatalog, [ws, cardCatalog](const QVariantList &cards) {
                         if (ws->cardLoadMode() == hexproof::protocol::kCardLoadBackground) {
                             cardCatalog->cacheCardsIncrementally(cards);
                             return;
                         }
                         cardCatalog->cacheCards(cards);
                     });
    QObject::connect(cardCatalog, &hexproof::client::CardCatalog::cardCacheFinished, matchLoader,
                     &hexproof::client::MatchLoadCoordinator::handleCardCacheFinished);
    QObject::connect(matchLoader, &hexproof::client::MatchLoadCoordinator::loadComplete, ws,
                     [ws](qint64 loadId) {
                         if (ws->cardLoadMode() == hexproof::protocol::kCardLoadPreload)
                             ws->completeLoad(loadId);
                     });
    QObject::connect(ws, &hexproof::client::WsClient::loadCancelled, matchLoader,
                     &hexproof::client::MatchLoadCoordinator::cancel);
    QObject::connect(ws, &hexproof::client::WsClient::inRoomChanged, matchLoader,
                     [ws, matchLoader]() {
                         if (!ws->inRoom())
                             matchLoader->cancel();
                     });

    QmlNetworkFactory qmlNetworkFactory;
    QQmlApplicationEngine engine;
    engine.setNetworkAccessManagerFactory(&qmlNetworkFactory);
    auto *translations = new hexproof::client::TranslationController(&engine, &engine);
    translations->setLanguage(preferences->uiLanguage());
    QObject::connect(
        preferences, &hexproof::client::ClientPreferencesModel::uiLanguageChanged, translations,
        [preferences, translations]() { translations->setLanguage(preferences->uiLanguage()); });
    auto *cardImageProvider = new hexproof::client::CardImageProvider();
    engine.addImageProvider(QStringLiteral("card-table"), cardImageProvider);
    cardCatalog->setCardImageProvider(cardImageProvider);
    engine.rootContext()->setContextProperty(QStringLiteral("ws"), ws);
    engine.rootContext()->setContextProperty(QStringLiteral("tournament"), ws->tournamentSession());
    engine.rootContext()->setContextProperty(QStringLiteral("limited"), ws->limitedSession());
    engine.rootContext()->setContextProperty(QStringLiteral("preferences"), preferences);
    engine.rootContext()->setContextProperty(QStringLiteral("deckLibrary"), deckLibrary);
    engine.rootContext()->setContextProperty(QStringLiteral("gameTable"), gameTable);
    engine.rootContext()->setContextProperty(QStringLiteral("optimisticCommands"),
                                             optimisticCommands);
    engine.rootContext()->setContextProperty(QStringLiteral("sideboardTable"), sideboardTable);
    engine.rootContext()->setContextProperty(QStringLiteral("cardCatalog"), cardCatalog);
    engine.rootContext()->setContextProperty(QStringLiteral("cardArtManager"), cardArtManager);
    engine.rootContext()->setContextProperty(QStringLiteral("appUpdater"), appUpdater);
    engine.rootContext()->setContextProperty(QStringLiteral("matchLoader"), matchLoader);
    QObject::connect(&engine, &QQmlApplicationEngine::warnings,
                     [](const QList<QQmlError> &warnings) {
                         for (const QQmlError &e : warnings)
                             qWarning().noquote() << QStringLiteral("QML WARNING: %1:%2 %3")
                                                         .arg(e.url().toString())
                                                         .arg(e.line())
                                                         .arg(e.description());
                     });
    const QUrl url(QStringLiteral("qrc:/qml/Main.qml"));
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        []() { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.load(url);

    QTimer::singleShot(1'500, appUpdater, &hexproof::client::AppUpdateService::checkAutomatically);
    QTimer::singleShot(2'000, cardCatalog, &hexproof::client::CardCatalog::checkCatalogUpdateIfDue);
    QTimer::singleShot(750, cardArtManager,
                       [cardArtManager]() { cardArtManager->auditCardArt(false); });
    QObject::connect(cardCatalog, &hexproof::client::CardCatalog::catalogChanged, cardArtManager,
                     [cardArtManager]() {
                         QTimer::singleShot(250, cardArtManager, [cardArtManager]() {
                             cardArtManager->auditCardArt(false);
                         });
                     });
    QTimer::singleShot(0, deckLibrary, &hexproof::client::DeckLibraryModel::refreshTokenMetadata);

    const int exitCode = app.exec();
    cardCatalog->setCardImageProvider(nullptr);
    return exitCode;
}
