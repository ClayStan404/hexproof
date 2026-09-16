// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "ApplicationPaths.h"
#include "models/ClientPreferencesModel.h"
#include "models/DeckLibraryModel.h"
#include "models/GameTableModel.h"
#include "models/OptimisticCommandModel.h"
#include "models/SideboardTableModel.h"
#include "protocol/Message.h"
#include "services/AppUpdateService.h"
#include "services/CardArtManager.h"
#include "services/CardArtStorage.h"
#include "services/CardCatalog.h"
#include "services/CardImageProvider.h"
#include "services/CustomCardArtStore.h"
#include "services/DeckLegalityService.h"
#include "services/LimitedDeckDraftStore.h"
#include "services/LimitedSessionState.h"
#include "services/MatchCardCacheBinding.h"
#include "services/MatchLoadCoordinator.h"
#include "services/NetworkRequestFactory.h"
#include "services/ProfileLock.h"
#include "services/TournamentSessionState.h"
#include "services/TranslationController.h"
#include "services/WsClient.h"
#include "testing/LocalTestSession.h"
#ifdef HEXPROOF_NATIVE_AUDIT
#include "testing/NativeAudit.h"
#endif

#include <QCommandLineParser>
#include <QDebug>
#include <QFile>
#include <QGuiApplication>
#include <QIcon>
#include <QJsonDocument>
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
    QCommandLineOption serverUrlOption(
        QStringLiteral("server-url"),
        QStringLiteral(
            "Prefill the connection endpoint without connecting (requires --display-name)."),
        QStringLiteral("url"));
    QCommandLineOption displayNameOption(
        QStringLiteral("display-name"),
        QStringLiteral("Prefill the player name (requires --server-url)."), QStringLiteral("name"));
    commandLine.addOption(instanceLabelOption);
    commandLine.addOption(windowedOption);
    commandLine.addOption(serverUrlOption);
    commandLine.addOption(displayNameOption);
    hexproof::client::LocalTestSession::addOptions(commandLine);
    commandLine.process(app);
    if (commandLine.isSet(serverUrlOption) != commandLine.isSet(displayNameOption)) {
        qCritical() << "--server-url and --display-name must be provided together.";
        return 2;
    }
    const bool localTestRequested = hexproof::client::LocalTestSession::requested(commandLine);
    const auto localTestOptions = hexproof::client::LocalTestSession::readOptions(commandLine);
    if (localTestRequested && (!localTestOptions.valid() || !commandLine.isSet(serverUrlOption))) {
        qCritical() << "Local test setup requires valid event, source, group, player and seat "
                       "options, --server-url, and --display-name.";
        return 2;
    }

    const QString instanceLabel = commandLine.value(instanceLabelOption).simplified().left(80);
    QGuiApplication::setApplicationDisplayName(
        instanceLabel.isEmpty() ? QStringLiteral("Hexproof")
                                : QStringLiteral("Hexproof — %1").arg(instanceLabel));

    const QString storageRoot = hexproof::client::defaultStorageRoot();
#ifdef HEXPROOF_NATIVE_AUDIT
    if (!hexproof::client::NativeAudit::validateEnvironment(storageRoot))
        return 2;
#endif
    hexproof::client::ProfileLock profileLock(storageRoot);
    if (!profileLock.tryLock()) {
        qCritical() << "Cannot acquire Hexproof profile:" << storageRoot;
        // No persistent models or network clients are constructed on this path.
        QQmlApplicationEngine errorEngine;
        hexproof::client::TranslationController translations(&errorEngine);
        QFile settings(QDir(storageRoot).filePath(QStringLiteral("settings.json")));
        if (settings.open(QIODevice::ReadOnly)) {
            const QJsonObject object = QJsonDocument::fromJson(settings.readAll()).object();
            translations.setLanguage(
                object.value(QStringLiteral("uiLanguage"))
                    .toString(object.value(QStringLiteral("language")).toString()));
        }
        errorEngine.setInitialProperties(
            {{QStringLiteral("profileOccupied"), profileLock.occupied()},
             {QStringLiteral("windowTitle"), QGuiApplication::applicationDisplayName()}});
        errorEngine.load(QUrl(QStringLiteral("qrc:/qml/ProfileUnavailable.qml")));
        if (errorEngine.rootObjects().isEmpty())
            return 2;
        app.exec();
        return 2;
    }

    qInfo().noquote() << "Hexproof protocol:" << hexproof::protocol::kProtocolVersion;

    // Destroy network services and models after the QML engine but before the
    // QGuiApplication tears down its event dispatcher.
    QObject runtimeOwner;
    // Expose WsClient to QML as a context property `ws` (owned by runtimeOwner).
    // QML pages reference it directly (e.g. ws.connected, ws.createRoom(...)).
    auto *ws = new hexproof::client::WsClient(&runtimeOwner);
    if (commandLine.isSet(serverUrlOption) &&
        !ws->setInitialConnection(commandLine.value(serverUrlOption),
                                  commandLine.value(displayNameOption))) {
        qCritical() << "Launch defaults require a valid ws:// or wss:// URL and a non-empty name.";
        return 2;
    }
    auto *preferences = new hexproof::client::ClientPreferencesModel(&runtimeOwner);
    auto *limitedDeckDrafts =
        new hexproof::client::LimitedDeckDraftStore(storageRoot, &runtimeOwner);
    auto *deckLibrary = new hexproof::client::DeckLibraryModel(&runtimeOwner);
    auto *gameTable = new hexproof::client::GameTableModel(&runtimeOwner);
    auto *optimisticCommands = new hexproof::client::OptimisticCommandModel(&runtimeOwner);
    auto *sideboardTable = new hexproof::client::SideboardTableModel(&runtimeOwner);
    auto *cardCatalog = new hexproof::client::CardCatalog(&runtimeOwner);
    auto *appUpdater = new hexproof::client::AppUpdateService(&runtimeOwner);
    auto *deckLegality = new hexproof::client::DeckLegalityService(&runtimeOwner);
    auto *matchLoader = new hexproof::client::MatchLoadCoordinator(&runtimeOwner);
    auto *matchCardCache = new hexproof::client::MatchCardCacheBinding(
        gameTable, ws->rulesSession(), ws->roomSession(), matchLoader, &runtimeOwner);
    auto *cardArtManager = cardCatalog->artManager();
    cardArtManager->setAuditRequestProvider(
        [deckLibrary]() { return deckLibrary->cardArtAuditRequests(); },
        [preferences]() { return preferences->cardLanguage(); });
    cardCatalog->setLanguage(preferences->cardLanguage());
    cardCatalog->setCardArtProvider(preferences->cardArtProvider());
    cardCatalog->setReuseLocalCardArt(preferences->reuseLocalCardArt());
    // A saved Cube can contain thousands of printings. Resolve its presentation
    // incrementally after startup instead of delaying the first window/frame.
    deckLibrary->setImagePathResolver(
        [cardCatalog](const hexproof::client::DeckCard &card) {
            return QUrl(cardCatalog->imageSource(card.name, card.setCode, card.collectorNumber))
                .toLocalFile();
        },
        true);
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
    QObject::connect(cardCatalog, &hexproof::client::CardCatalog::customArtContentsChanged,
                     deckLibrary, &hexproof::client::DeckLibraryModel::refreshCustomCardArt);
    deckLibrary->hydrateCatalogMetadata();
    QObject::connect(cardCatalog, &hexproof::client::CardCatalog::tokenMetadataAvailable,
                     deckLibrary, &hexproof::client::DeckLibraryModel::applyTokenMetadata);
    QObject::connect(cardCatalog, &hexproof::client::CardCatalog::catalogChanged, deckLibrary,
                     &hexproof::client::DeckLibraryModel::refreshTokenMetadata);
    QObject::connect(cardCatalog, &hexproof::client::CardCatalog::catalogChanged, deckLibrary,
                     &hexproof::client::DeckLibraryModel::refreshDeckValidation);
    QTimer::singleShot(0, deckLibrary, &hexproof::client::DeckLibraryModel::refreshDeckValidation);
    QObject::connect(ws, &hexproof::client::WsClient::loadRequired, matchLoader,
                     [ws, matchLoader](qint64 loadId, const QVariantList &cardKeys) {
                         if (ws->cardLoadMode() == hexproof::protocol::kCardLoadBackground)
                             matchLoader->prepareBackground(loadId, cardKeys);
                         else
                             matchLoader->preparePreload(loadId, cardKeys);
                     });
    QObject::connect(ws, &hexproof::client::WsClient::gameSnapshotDataChanged, gameTable,
                     &hexproof::client::GameTableModel::applySnapshot);
    QObject::connect(matchCardCache,
                     &hexproof::client::MatchCardCacheBinding::visibleRulesCardsRequested,
                     cardCatalog, &hexproof::client::CardCatalog::prioritizeCards);
    QObject::connect(cardCatalog, &hexproof::client::CardCatalog::languageChanged, matchCardCache,
                     &hexproof::client::MatchCardCacheBinding::refreshVisibleCards);
    QObject::connect(cardCatalog, &hexproof::client::CardCatalog::cardArtProviderChanged,
                     matchCardCache, &hexproof::client::MatchCardCacheBinding::refreshVisibleCards);
    QObject::connect(cardCatalog, &hexproof::client::CardCatalog::reuseLocalCardArtChanged,
                     matchCardCache, &hexproof::client::MatchCardCacheBinding::refreshVisibleCards);
    QObject::connect(
        matchLoader, &hexproof::client::MatchLoadCoordinator::cardFaceExpansionRequested,
        cardCatalog, &hexproof::client::CardCatalog::expandCardFaceRequestsIncrementally);
    QObject::connect(cardCatalog, &hexproof::client::CardCatalog::cardFaceRequestsExpanded,
                     matchLoader, &hexproof::client::MatchLoadCoordinator::adoptExpandedCards);
    QObject::connect(matchLoader, &hexproof::client::MatchLoadCoordinator::cardsRequested,
                     cardCatalog, &hexproof::client::CardCatalog::cacheMatchCardsIncrementally);
    QObject::connect(matchLoader, &hexproof::client::MatchLoadCoordinator::cardsRetryRequested,
                     cardCatalog, &hexproof::client::CardCatalog::retryMatchCards);
    QObject::connect(matchLoader,
                     &hexproof::client::MatchLoadCoordinator::matchCardSubscriptionsInvalidated,
                     cardCatalog, &hexproof::client::CardCatalog::cancelMatchCardSubscriptions);
    QObject::connect(cardCatalog, &hexproof::client::CardCatalog::matchCardCacheFinished,
                     matchLoader,
                     &hexproof::client::MatchLoadCoordinator::handleMatchCardCacheFinished);
    QObject::connect(cardCatalog, &hexproof::client::CardCatalog::languageChanged, matchLoader,
                     &hexproof::client::MatchLoadCoordinator::handleCardLanguageChanged);
    QObject::connect(matchLoader, &hexproof::client::MatchLoadCoordinator::loadComplete, ws,
                     [ws](qint64 loadId) {
                         if (ws->cardLoadMode() == hexproof::protocol::kCardLoadPreload)
                             ws->completeLoad(loadId);
                     });
    QObject::connect(ws, &hexproof::client::WsClient::loadCancelled, matchLoader,
                     &hexproof::client::MatchLoadCoordinator::cancel);
    QObject::connect(ws, &hexproof::client::WsClient::inRoomChanged, matchCardCache,
                     [ws, matchCardCache]() { matchCardCache->setInRoom(ws->inRoom()); });

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
    engine.rootContext()->setContextProperty(QStringLiteral("localTestMode"), localTestRequested);
    engine.rootContext()->setContextProperty(QStringLiteral("tournament"), ws->tournamentSession());
    engine.rootContext()->setContextProperty(QStringLiteral("limited"), ws->limitedSession());
    engine.rootContext()->setContextProperty(QStringLiteral("limitedDeckDrafts"),
                                             limitedDeckDrafts);
    engine.rootContext()->setContextProperty(QStringLiteral("preferences"), preferences);
    engine.rootContext()->setContextProperty(QStringLiteral("deckLibrary"), deckLibrary);
    engine.rootContext()->setContextProperty(QStringLiteral("gameTable"), gameTable);
    engine.rootContext()->setContextProperty(QStringLiteral("optimisticCommands"),
                                             optimisticCommands);
    engine.rootContext()->setContextProperty(QStringLiteral("sideboardTable"), sideboardTable);
    engine.rootContext()->setContextProperty(QStringLiteral("cardCatalog"), cardCatalog);
    engine.rootContext()->setContextProperty(QStringLiteral("cardArtManager"), cardArtManager);
    engine.rootContext()->setContextProperty(QStringLiteral("customCardArtStore"),
                                             cardCatalog->customArtStore());
    engine.rootContext()->setContextProperty(QStringLiteral("cardArtStorage"),
                                             cardCatalog->artStorage());
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
#ifdef HEXPROOF_NATIVE_AUDIT
    auto *nativeAudit = new hexproof::client::NativeAudit(&engine);
    Q_UNUSED(nativeAudit);
    engine.rootContext()->setContextProperty(QStringLiteral("localTestMode"), true);
#endif
    engine.setInitialProperties(
        {{QStringLiteral("windowTitle"), QGuiApplication::applicationDisplayName()}});
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        []() { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.load(url);

    if (localTestRequested) {
        auto *setup = new hexproof::client::LocalTestSession(
            ws, localTestOptions,
            [cardCatalog, deckLibrary, localTestOptions](const QString &source) {
                if (localTestOptions.commanderCube()) {
                    const QVariantMap byId = deckLibrary->cubeProduct(source);
                    if (!byId.isEmpty())
                        return byId;
                    QString cubeId;
                    for (const QVariant &value :
                         deckLibrary->matchDecks(QStringLiteral("cube"), true)) {
                        const QVariantMap cube = value.toMap();
                        if (cube.value(QStringLiteral("deckName")).toString() != source)
                            continue;
                        if (!cubeId.isEmpty())
                            return QVariantMap{};
                        cubeId = cube.value(QStringLiteral("deckId")).toString();
                    }
                    return cubeId.isEmpty() ? QVariantMap{} : deckLibrary->cubeProduct(cubeId);
                }
                for (const QVariant &value : cardCatalog->limitedSets()) {
                    const QVariantMap set = value.toMap();
                    if (set.value(QStringLiteral("setCode")).toString().toUpper() == source)
                        return cardCatalog->limitedProduct(
                            set.value(QStringLiteral("productId")).toString());
                }
                return QVariantMap{};
            },
            &runtimeOwner);
        QObject::connect(setup, &hexproof::client::LocalTestSession::failed, &engine,
                         [&engine](const QString &message) {
                             qCritical().noquote() << message;
                             if (!engine.rootObjects().isEmpty())
                                 QMetaObject::invokeMethod(engine.rootObjects().first(),
                                                           "showBanner",
                                                           Q_ARG(QVariant, QVariant(message)));
                         });
        QObject::connect(
            setup, &hexproof::client::LocalTestSession::finished, &app, [localTestOptions]() {
                if (localTestOptions.autoDraft)
                    qInfo() << "Local test setup complete; auto-draft finished and deck building "
                               "is now manual.";
                else
                    qInfo()
                        << "Local test setup complete; drafting and deck building are now manual.";
            });
        QTimer::singleShot(0, setup, &hexproof::client::LocalTestSession::start);
    }

    bool startupServicesEnabled = !localTestRequested;
#ifdef HEXPROOF_NATIVE_AUDIT
    startupServicesEnabled =
        startupServicesEnabled && qEnvironmentVariable("HEXPROOF_AUDIT_STARTUP_SERVICES") == "1";
#endif
    if (startupServicesEnabled) {
        QTimer::singleShot(1'500, appUpdater,
                           &hexproof::client::AppUpdateService::checkAutomatically);
        QTimer::singleShot(2'000, cardCatalog,
                           &hexproof::client::CardCatalog::checkCatalogUpdateIfDue);
        QTimer::singleShot(750, cardArtManager,
                           [cardArtManager]() { cardArtManager->auditCardArt(false); });
    }
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
