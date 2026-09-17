// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "ForgeHostService.h"
#include "PeerTransportService.h"
#include <QElapsedTimer>
#include <QObject>
#include <QString>
#include <QThread>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QtWebSockets/QWebSocket>

#include "GameSessionState.h"
#include "RoomSessionState.h"
#include "RulesSessionState.h"
#include "WsMessageParser.h"
#include "protocol/Message.h"

namespace hexproof::client {

class ProtocolSession;
class LimitedSessionState;
class ReconnectController;
class ServerDirectory;
class TournamentSessionState;

// WsClient owns the WebSocket connection to the hub and exposes session/room
// operations to QML. State transitions drive page switching in the UI.
//
// State machine:
//   Disconnected -> Connecting -> Connected (welcome) -> InRoom
//   InRoom -> Reconnecting -> InRoom on an unexpected socket close.
//   Explicit disconnect or an expired resume window -> Disconnected.
//
// `youAreHost` is derived from create vs join (not display name), per spec.
class WsClient : public QObject
{
    // Native audit fault injection is linked only by the test executable.
    friend class NativeAudit;
    Q_OBJECT
    Q_PROPERTY(ConnectionState connectionState READ connectionState NOTIFY connectionStateChanged)
    Q_PROPERTY(bool connected READ connected NOTIFY connectionStateChanged)
    Q_PROPERTY(bool connecting READ connecting NOTIFY connectionStateChanged)
    Q_PROPERTY(bool reconnecting READ reconnecting NOTIFY connectionStateChanged)
    Q_PROPERTY(int reconnectSecondsRemaining READ reconnectSecondsRemaining NOTIFY
                   reconnectSecondsRemainingChanged)
    Q_PROPERTY(bool inRoom READ inRoom NOTIFY inRoomChanged)
    Q_PROPERTY(QString serverUrl READ serverUrl NOTIFY serverUrlChanged)
    Q_PROPERTY(int serverIndex READ serverIndex NOTIFY serverUrlChanged)
    Q_PROPERTY(int customServerIndex READ customServerIndex NOTIFY serverDirectoryChanged)
    Q_PROPERTY(QVariantList serverEntries READ serverEntries NOTIFY serverDirectoryChanged)
    Q_PROPERTY(QString serverDirectorySource READ serverDirectorySource NOTIFY
                   serverDirectoryStatusChanged)
    Q_PROPERTY(bool serverDirectoryRefreshing READ serverDirectoryRefreshing NOTIFY
                   serverDirectoryStatusChanged)
    Q_PROPERTY(bool serverDirectoryRefreshFailed READ serverDirectoryRefreshFailed NOTIFY
                   serverDirectoryStatusChanged)
    Q_PROPERTY(QString customServerUrl READ customServerUrl NOTIFY customServerUrlChanged)
    Q_PROPERTY(QVariantList serverLatencies READ serverLatencies NOTIFY serverLatenciesChanged)
    Q_PROPERTY(QString displayName READ displayName NOTIFY displayNameChanged)
    Q_PROPERTY(QVariantList roomList READ roomList NOTIFY roomListChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(QString clientVersion READ clientVersion CONSTANT)
    Q_PROPERTY(bool versionMismatch READ versionMismatch NOTIFY versionMismatchChanged)
    Q_PROPERTY(QString requiredVersion READ requiredVersion NOTIFY versionMismatchChanged)
    Q_PROPERTY(QString releaseDownloadUrl READ releaseDownloadUrl CONSTANT)
    Q_PROPERTY(bool forgeRulesAvailable READ forgeRulesAvailable NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool playerHostingAvailable READ playerHostingAvailable NOTIFY capabilitiesChanged)
    Q_PROPERTY(ForgeHostService *forgeHost READ forgeHost CONSTANT)
    Q_PROPERTY(bool peerTransportAvailable READ peerTransportAvailable NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool directPeerEnabled READ directPeerEnabled NOTIFY peerTransportChanged)
    Q_PROPERTY(QString peerTransportState READ peerTransportState NOTIFY peerTransportChanged)
    Q_PROPERTY(int directPeerDecisions READ directPeerDecisions NOTIFY peerTransportChanged)
    Q_PROPERTY(int peerFallbacks READ peerFallbacks NOTIFY peerTransportChanged)
    Q_PROPERTY(
        QVariantMap peerTransportMetrics READ peerTransportMetrics NOTIFY peerTransportChanged)
    Q_PROPERTY(RoomSessionState *roomSession READ roomSession CONSTANT)
    Q_PROPERTY(GameSessionState *gameSession READ gameSession CONSTANT)
    Q_PROPERTY(RulesSessionState *rulesSession READ rulesSession CONSTANT)
    Q_PROPERTY(
        bool rulesResponsePending READ rulesResponsePending NOTIFY rulesResponsePendingChanged)
    Q_PROPERTY(LimitedSessionState *limitedSession READ limitedSession CONSTANT)

  public:
    enum ConnectionState
    {
        Disconnected,
        Connecting,
        Connected,
        InRoom,
        Reconnecting
    };
    Q_ENUM(ConnectionState)

    explicit WsClient(QObject *parent = nullptr);
    ~WsClient() override;

    bool rulesResponsePending() const
    {
        return !m_rulesResponseRequestId.isEmpty();
    }

    ConnectionState connectionState() const
    {
        return m_state;
    }
    bool connected() const
    {
        return m_state == Connected || m_state == InRoom;
    }
    bool connecting() const
    {
        return m_state == Connecting;
    }
    bool reconnecting() const
    {
        return m_state == Reconnecting;
    }
    int reconnectSecondsRemaining() const;
    bool inRoom() const
    {
        return m_state == InRoom;
    }
    RoomSessionState *roomSession() const
    {
        return m_roomSession;
    }
    GameSessionState *gameSession() const
    {
        return m_gameSession;
    }
    RulesSessionState *rulesSession() const
    {
        return m_rulesSession;
    }
    LimitedSessionState *limitedSession() const
    {
        return m_limitedSession;
    }
    bool youAreHost() const
    {
        return m_roomSession->host();
    }
    QString roomRole() const
    {
        return m_roomSession->role();
    }
    int seatIndex() const
    {
        return m_roomSession->seatIndex();
    }
    QString selectedDeckName() const
    {
        return m_roomSession->selectedDeckName();
    }
    QString serverUrl() const
    {
        return m_serverUrl;
    }
    bool setInitialConnection(const QString &url, const QString &displayName);
    int serverIndex() const;
    int customServerIndex() const;
    QVariantList serverEntries() const;
    QString serverDirectorySource() const;
    bool serverDirectoryRefreshing() const;
    bool serverDirectoryRefreshFailed() const;
    QString customServerUrl() const;
    QVariantList serverLatencies() const;
    QString displayName() const
    {
        return m_displayName;
    }
    QString roomId() const
    {
        return m_roomSession->roomId();
    }
    QString roomName() const
    {
        return m_roomSession->roomName();
    }
    QString format() const
    {
        return m_roomSession->format();
    }
    QString deckFormat() const
    {
        return m_roomSession->deckFormat();
    }
    bool playtest() const
    {
        return m_roomSession->playtest();
    }
    QString matchMode() const
    {
        return m_roomSession->matchMode();
    }
    QString cardLoadMode() const
    {
        return m_roomSession->cardLoadMode();
    }
    int maxSeats() const
    {
        return m_roomSession->maxSeats();
    }
    QString roomPhase() const
    {
        return m_roomSession->phase();
    }
    qint64 loadId() const
    {
        return m_roomSession->loadId();
    }
    QVariantList seats() const
    {
        return m_roomSession->seats();
    }
    QVariantList spectators() const
    {
        return m_roomSession->spectators();
    }
    QVariantList roomList() const
    {
        return m_roomList;
    }
    int gameNumber() const
    {
        return m_gameSession->gameNumber();
    }
    int startingSeat() const
    {
        return m_gameSession->startingSeat();
    }
    int activeSeat() const
    {
        return m_gameSession->activeSeat();
    }
    QString currentPhase() const
    {
        return m_gameSession->currentPhase();
    }
    QVariantList gameSeats() const
    {
        return m_gameSession->seats();
    }
    QVariantList gameStack() const
    {
        return m_gameSession->stack();
    }
    QVariantList gameRevealed() const
    {
        return m_gameSession->revealed();
    }
    QVariantList gameArrows() const
    {
        return m_gameSession->arrows();
    }
    QVariantList gameAttachments() const
    {
        return m_gameSession->attachments();
    }
    QVariantList gameLog() const
    {
        return m_gameSession->log();
    }
    QVariantList matchScore() const
    {
        return m_gameSession->score();
    }
    QVariantMap gameResult() const
    {
        return m_gameSession->result();
    }
    QVariantMap sideboardState() const
    {
        return m_gameSession->sideboard();
    }
    bool sideboarding() const
    {
        return m_gameSession->sideboarding();
    }
    bool gameFinished() const
    {
        return m_gameSession->finished();
    }
    QString lastError() const
    {
        return m_lastError;
    }
    QString clientVersion() const;
    bool versionMismatch() const
    {
        return m_versionMismatch;
    }
    QString requiredVersion() const
    {
        return m_requiredVersion;
    }
    QString releaseDownloadUrl() const;
    bool forgeRulesAvailable() const
    {
        return m_forgeRulesAvailable;
    }
    bool playerHostingAvailable() const
    {
        return m_playerHostingAvailable;
    }
    ForgeHostService *forgeHost() const
    {
        return m_forgeHost;
    }
    bool peerTransportAvailable() const
    {
        return m_peerTransportAvailable;
    }
    bool directPeerEnabled() const
    {
        return m_peerConsent;
    }
    QString peerTransportState() const;
    int directPeerDecisions() const
    {
        return m_directPeerDecisions;
    }
    int peerFallbacks() const
    {
        return m_peerFallbacks;
    }
    QVariantMap peerTransportMetrics() const;
    Q_INVOKABLE void setDirectPeerEnabled(bool enabled, bool retry = false);
    Q_INVOKABLE void preparePlayerHosting();
    Q_INVOKABLE void playerHostingAction(const QString &action);
    TournamentSessionState *tournamentSession() const
    {
        return m_tournamentSession;
    }

    // Native test and development entry point. The production QML connection
    // screen uses the fixed server selector below instead of exposing URLs.
    void connectTo(const QString &url, const QString &displayName);

    // QML-invokable operations.
    Q_INVOKABLE void connectToServer(int serverIndex, const QString &displayName);
    Q_INVOKABLE void connectToCustomServer(const QString &url, const QString &displayName);
    Q_INVOKABLE void refreshServerLatencies();
    Q_INVOKABLE void refreshServerDirectory(bool force = false);
    Q_INVOKABLE void disconnectFromHub();
    Q_INVOKABLE void createRoom(const QString &name, const QString &format,
                                const QString &deckFormat, bool allowSpectators,
                                bool spectatorsSeeHands, const QString &matchMode,
                                const QString &cardLoadMode, const QString &password,
                                bool playtest = false,
                                const QString &rulesMode = QStringLiteral("manual"),
                                const QString &hostingMode = QString());
    Q_INVOKABLE void requestRoomList();
    Q_INVOKABLE void requestTournamentList();
    Q_INVOKABLE QString sendTournamentChat(const QString &text);
    Q_INVOKABLE void createTournament(const QString &name, const QString &format,
                                      const QString &matchMode, int roundMinutes, int maxPlayers);
    Q_INVOKABLE void createLimitedTournament(const QString &name, const QString &eventType,
                                             const QString &matchMode, int roundMinutes,
                                             int maxPlayers, const QVariantMap &product);
    Q_INVOKABLE void createCasualLimitedEvent(const QString &name, const QString &eventType,
                                              const QString &matchMode, int maxPlayers,
                                              const QVariantMap &product,
                                              const QVariantMap &draftSettings = {});
    Q_INVOKABLE void createLimitedCasualMatch(const QString &playerAId, const QString &playerBId);
    Q_INVOKABLE void cancelLimitedCasualMatch(const QString &playerAId, const QString &playerBId);
    Q_INVOKABLE void pickLimitedCard(const QString &instanceId);
    Q_INVOKABLE void pickLimitedCards(const QVariantList &instanceIds);
    Q_INVOKABLE void setLimitedDraftControl(const QString &participantId, bool automatic);
    Q_INVOKABLE void setLimitedParticipation(bool participating);
    Q_INVOKABLE void inviteCommanderCubePlayers(const QVariantList &playerIds);
    Q_INVOKABLE void respondCommanderCubeInvitation(const QString &pairingId, bool accept);
    Q_INVOKABLE void submitLimitedCommanderDeck(const QString &name,
                                                const QVariantList &mainboardInstanceIds,
                                                const QVariantList &basicLands,
                                                const QVariantList &commanderInstanceIds,
                                                const QVariantList &commanderColors = {});
    Q_INVOKABLE void submitLimitedDeck(const QString &name,
                                       const QVariantList &mainboardInstanceIds,
                                       const QVariantList &basicLands);
    Q_INVOKABLE void enterTournament(const QString &tournamentId);
    Q_INVOKABLE void leaveTournament();
    Q_INVOKABLE void registerTournament();
    Q_INVOKABLE void unregisterTournament(const QString &participantId = {});
    Q_INVOKABLE void setTournamentCheckedIn(bool checkedIn, const QString &participantId = {});
    Q_INVOKABLE void startTournament();
    Q_INVOKABLE void dropTournament(const QString &participantId = {});
    Q_INVOKABLE void reportTournamentResult(const QString &pairingId, int playerAWins,
                                            int playerBWins, int drawnGames);
    Q_INVOKABLE void confirmTournamentResult(const QString &pairingId);
    Q_INVOKABLE void rejectTournamentResult(const QString &pairingId);
    Q_INVOKABLE void correctTournamentResult(const QString &pairingId, int playerAWins,
                                             int playerBWins, int drawnGames);
    Q_INVOKABLE void startNextTournamentRound();
    Q_INVOKABLE void openTournamentMatch(const QString &pairingId);
    Q_INVOKABLE void cancelTournament();
    Q_INVOKABLE void joinRoom(const QString &roomId, bool asSpectator, const QString &password,
                              bool acceptPlayerHost = false);
    Q_INVOKABLE bool hasCubeRoomCredential(const QString &roomId) const;
    Q_INVOKABLE void leaveRoom();
    Q_INVOKABLE void kickSeat(int seat);
    Q_INVOKABLE void kickSpectator(int index);
    Q_INVOKABLE void disbandRoom();
    Q_INVOKABLE void selectDeck(const QVariantMap &deck);
    Q_INVOKABLE void setReady(bool ready);
    Q_INVOKABLE void completeLoad(qint64 loadId);
    Q_INVOKABLE void respondRulesPrompt(qint64 promptId, const QString &responseId);
    Q_INVOKABLE void respondRulesPromptWithCards(qint64 promptId, const QString &responseId,
                                                 const QVariantList &cardIds);
    Q_INVOKABLE void respondRulesPromptWithTargets(qint64 promptId, const QString &responseId,
                                                   const QVariantList &targetIds);
    Q_INVOKABLE void respondRulesPromptWithAssignments(qint64 promptId,
                                                       const QVariantList &assignments);
    Q_INVOKABLE void respondRulesPromptWithChoices(qint64 promptId, const QVariantList &choiceIds);
    Q_INVOKABLE void respondRulesPromptWithOrder(qint64 promptId, const QVariantList &orderedIds);
    Q_INVOKABLE void respondRulesPromptWithDamageOrder(qint64 promptId,
                                                       const QVariantList &orderedIds);
    Q_INVOKABLE void respondRulesPromptWithDamage(qint64 promptId, const QVariantList &assignments);
    Q_INVOKABLE void respondRulesPromptWithScry(qint64 promptId, const QVariantList &piles);
    Q_INVOKABLE void respondRulesPromptWithNumber(qint64 promptId, int chosenNumber);
    Q_INVOKABLE void respondRulesPromptWithName(qint64 promptId, const QString &name);
    Q_INVOKABLE void drawCards(int count = 1);
    Q_INVOKABLE void shuffleLibrary();
    Q_INVOKABLE void mulligan();
    Q_INVOKABLE void discardHand(bool all = false);
    Q_INVOKABLE void moveCard(const QString &cardId, const QString &fromZone, const QString &toZone,
                              const QVariantMap &position = {}, int toSeat = -1,
                              const QString &libraryPlacement = {}, int libraryIndex = -1,
                              int fromSeat = -1, const QString &faceName = {},
                              bool faceDown = false);
    Q_INVOKABLE void arrangeBattlefield(const QVariantList &cards);
    Q_INVOKABLE void setCardTapped(const QString &cardId, bool tapped);
    Q_INVOKABLE void setCardFace(const QString &cardId, const QString &faceName);
    Q_INVOKABLE void setCardFaceDown(const QString &cardId, bool faceDown);
    Q_INVOKABLE void setCardCounter(const QString &cardId, const QVariantMap &counter);
    Q_INVOKABLE void setPhase(const QString &phase);
    Q_INVOKABLE void playLand(const QString &cardId, const QVariantMap &position,
                              const QString &faceName = {});
    Q_INVOKABLE void setLandPlayCount(int value);
    Q_INVOKABLE void setResponseStatus(const QString &status);
    Q_INVOKABLE void setCounter(const QString &counter, int value);
    Q_INVOKABLE void adjustCounter(const QString &counter, int delta);
    Q_INVOKABLE void renameCounter(const QString &counter, const QString &label);
    Q_INVOKABLE void setCounterCount(int count);
    Q_INVOKABLE void concede();
    Q_INVOKABLE void declareDraw();
    Q_INVOKABLE void restartGame();
    Q_INVOKABLE void rollDice(int sides, int count = 1);
    Q_INVOKABLE void flipCoin();
    Q_INVOKABLE void randomSelectPlayer();
    Q_INVOKABLE void randomSelectCards(const QVariantList &cardIds);
    Q_INVOKABLE void returnToRoom();
    Q_INVOKABLE void sayGameMessage(const QString &message);
    Q_INVOKABLE void createToken(const QVariantMap &token, const QVariantMap &position);
    Q_INVOKABLE void createEmblem(int seat, const QVariantMap &emblem);
    Q_INVOKABLE void removeEmblem(const QString &emblemId);
    Q_INVOKABLE void adjustCommanderTax(const QString &commanderId, int delta);
    Q_INVOKABLE void castCommander(const QString &commanderId);
    Q_INVOKABLE void setCommanderDamage(const QString &commanderId, int targetSeat, int amount,
                                        bool exact = false, bool applyToLife = false);
    Q_INVOKABLE void setCombatArrows(const QVariantList &sourceCardIds, const QString &kind,
                                     const QString &targetCardId = {}, int targetSeat = -1,
                                     const QVariantList &tappedSourceCardIds = {});
    Q_INVOKABLE void clearCombatArrows(const QVariantList &sourceCardIds);
    Q_INVOKABLE void clearArrow();
    Q_INVOKABLE void setAttachment(const QString &sourceCardId, const QString &targetCardId = {});
    Q_INVOKABLE void moveSideboardCard(const QVariantMap &card, const QString &fromZone,
                                       const QString &toZone);
    Q_INVOKABLE void setSideboardCommander(const QString &name, bool designated);
    Q_INVOKABLE void setSideboardReady(bool ready);
    Q_INVOKABLE void nextTurn();
    Q_INVOKABLE void revealHand();
    Q_INVOKABLE void recallRevealed();
    Q_INVOKABLE void moveCards(const QVariantList &cardIds, const QString &fromZone,
                               const QString &toZone, const QString &libraryPlacement = {},
                               bool randomize = false, const QVariantMap &position = {},
                               int toSeat = -1);
    Q_INVOKABLE void movePublicCards(const QVariantList &cardIds, const QString &fromZone,
                                     int fromSeat, const QString &toZone, int toSeat,
                                     const QVariantMap &position = {},
                                     const QString &libraryPlacement = {}, bool randomize = false);
    Q_INVOKABLE void moveLibraryCards(int count, const QString &toZone);
    Q_INVOKABLE void dumpLibrary(int sourceSeat = -1, int topCount = 0);
    Q_INVOKABLE void respondZoneDump(const QString &approvalId, bool approved);
    Q_INVOKABLE void respondPublicZoneMove(const QString &approvalId, bool approved);
    Q_INVOKABLE void searchLibrary(const QString &cardId, const QString &toZone, bool reveal,
                                   const QVariantMap &position = {}, int sourceSeat = -1,
                                   const QString &approvalId = {}, int toSeat = -1,
                                   bool faceDown = false);
    Q_INVOKABLE void searchLibraryCards(const QVariantList &cardIds, const QString &toZone,
                                        bool reveal, bool randomize = false,
                                        const QVariantMap &position = {}, int sourceSeat = -1,
                                        const QString &approvalId = {}, int toSeat = -1,
                                        bool faceDown = false);
    Q_INVOKABLE void reorderLibrary(const QVariantList &cardIds);
    Q_INVOKABLE void resolveLibraryView(const QVariantList &selectedCardIds,
                                        const QVariantList &remainderCardIds, const QString &toZone,
                                        const QString &remainderPlacement, bool randomizeRemainder,
                                        bool faceDown = false, const QVariantMap &position = {},
                                        int sourceSeat = -1, const QString &approvalId = {});
    Q_INVOKABLE void resolveLibraryViewAssignments(const QVariantList &assignments,
                                                   bool randomizeTop, bool randomizeBottom,
                                                   const QVariantMap &position = {},
                                                   int sourceSeat = -1,
                                                   const QString &approvalId = {});
    Q_INVOKABLE void copyToClipboard(const QString &text);

  signals:
    void connectionStateChanged();
    void reconnectSecondsRemainingChanged();
    void inRoomChanged();
    void youAreHostChanged();
    void roomRoleChanged();
    void selectedDeckNameChanged();
    void serverUrlChanged();
    void customServerUrlChanged();
    void serverLatenciesChanged();
    void serverDirectoryChanged();
    void serverDirectoryStatusChanged();
    void displayNameChanged();
    void roomIdChanged();
    void snapshotChanged();
    void roomListChanged();
    void gameSnapshotChanged();
    void gameRestarted();
    void gameSnapshotDataChanged(const QVariantMap &snapshot);
    void lastErrorChanged();
    void versionMismatchChanged();
    void capabilitiesChanged();
    void peerTransportChanged();
    void rulesResponsePendingChanged();
    void commandQueued(const QString &requestId, const QString &commandType,
                       const QVariantMap &payload);
    void commandSucceeded(const QString &requestId, const QString &commandType,
                          const QVariantMap &payload);
    void commandFailed(const QString &requestId, const QString &commandType,
                       const QVariantMap &payload, const QString &error);

    // Semantic events for page transitions.
    void welcomeReceived();
    void kicked();        // server-push room.kicked (no echo id)
    void roomDisbanded(); // host or observer: room gone
    void leftRoom();      // non-host leave acked
    void reconnectExpired();
    void loadRequired(qint64 loadId, const QVariantList &cardKeys);
    void loadCancelled();
    void matchStarted();
    void matchReturnedToRoom();
    void sideboardCompleted(const QString &reason);
    void libraryDumped(const QVariantList &cards, int sourceSeat, const QString &approvalId,
                       int topCount);
    void libraryAccessRequested(const QString &approvalId, const QString &requesterName,
                                int requesterSeat, int topCount);
    void publicZoneMoveRequested(const QString &approvalId, const QString &requesterName,
                                 int requesterSeat, const QString &sourceZone, int cardCount,
                                 const QString &toZone);

  private slots:
    void onConnected();
    void onDisconnected(quint64 transportGeneration);
    void onMessageParsed(quint64 transportGeneration, const QString &type, const QString &id,
                         qint64 seq, bool hasSeq, const QJsonObject &payload,
                         const QVariantMap &gameSnapshot);
    void onMessageRejected(quint64 transportGeneration);
    void onErrorOccurred();

  private:
    void setState(ConnectionState s);
    void openTransport();
    QString send(const QString &type, const QJsonObject &payload = {});
    void dispatch(const protocol::Envelope &env, const QVariantMap &gameSnapshot = {});
    void handleWelcome(const protocol::Envelope &env);
    void handleCreated(const protocol::Envelope &env);
    void handleJoined(const protocol::Envelope &env);
    void handleSnapshot(const protocol::Envelope &env);
    void handleRoomListed(const protocol::Envelope &env);
    void handleTournamentListed(const protocol::Envelope &env);
    void handleTournamentCreated(const protocol::Envelope &env);
    void handleTournamentEntered(const protocol::Envelope &env);
    void handleTournamentRegistered(const protocol::Envelope &env);
    void handleTournamentSnapshot(const protocol::Envelope &env);
    void handleLimitedSnapshot(const protocol::Envelope &env);
    void handleTournamentLeft(const protocol::Envelope &env);
    void handleDeckSelected(const protocol::Envelope &env);
    void handleLoadRequired(const protocol::Envelope &env);
    void handleMatchStarted(const protocol::Envelope &env);
    void handleGameSnapshot(const QVariantMap &snapshot);
    void handleRulesSnapshot(const QJsonObject &snapshot);
    void handleRulesPrompt(const QJsonObject &prompt);
    void handleZoneDumpRequested(const protocol::Envelope &env);
    void handlePublicZoneMoveRequested(const protocol::Envelope &env);
    void handleZoneDumped(const protocol::Envelope &env);
    void handleLeft(const protocol::Envelope &env);
    void handleKicked(const protocol::Envelope &env);
    void handleDisbanded(const protocol::Envelope &env);
    void handleSideboardCompleted(const protocol::Envelope &env);
    void handleError(const protocol::Envelope &env);
    void setLastError(const QString &code, const QString &message);
    void clearLastError();
    void setVersionMismatch(const QString &requiredVersion);
    void clearVersionMismatch();
    void setForgeRulesAvailable(bool available);
    void clearGameState();
    void clearRulesResponse();
    void reconcileRulesResponse();
    void clearRoomState();
    QString tournamentCredential(const QString &tournamentId) const;
    void storeTournamentCredential(const QString &tournamentId, const QString &credential);
    void removeTournamentCredential(const QString &tournamentId);
    void resumeTournamentView();
    void sendLibraryViewResolution(const QVariantList &assignments,
                                   const QVariantList &selectedCardIds,
                                   const QVariantList &remainderCardIds, const QString &toZone,
                                   const QString &remainderPlacement, bool randomizeRemainder,
                                   bool randomizeTop, bool randomizeBottom, bool faceDown,
                                   const QVariantMap &position, int sourceSeat,
                                   const QString &approvalId);

    void initializePeerTransport();
    void handlePeerEnvelope(const hexproof::protocol::Envelope &env);
    void handlePeerMessage(const QJsonObject &message);
    void fallbackPeerDecision();
    PeerTransportService *m_peerTransport = nullptr;
    bool m_peerConsent = false;
    bool m_peerTransportAvailable = false;
    bool m_peerOtherEnabled = false;
    bool m_peerResumeNeeded = false;
    QTimer m_peerFallbackTimer;
    QByteArray m_peerFallbackWire;
    QString m_peerRequestId;
    qint64 m_lastRulesSnapshotSeq = 0;
    int m_directPeerDecisions = 0;
    int m_peerFallbacks = 0;
    QElapsedTimer m_peerDecisionClock;
    QList<qint64> m_peerLatencies;
    ProtocolSession *m_protocolSession = nullptr;
    ReconnectController *m_reconnectController = nullptr;
    RoomSessionState *m_roomSession = nullptr;
    GameSessionState *m_gameSession = nullptr;
    RulesSessionState *m_rulesSession = nullptr;
    ServerDirectory *m_serverDirectory = nullptr;
    TournamentSessionState *m_tournamentSession = nullptr;
    LimitedSessionState *m_limitedSession = nullptr;
    QWebSocket m_ws;
    QThread m_parserThread;
    WsMessageParser *m_messageParser = nullptr;
    quint64 m_transportGeneration = 0;
    ConnectionState m_state = Disconnected;
    QString m_displayName;
    QVariantList m_roomList;
    QString m_lastError;
    QString m_requiredVersion;
    bool m_versionMismatch = false;
    bool m_forgeRulesAvailable = false;
    bool m_playerHostingAvailable = false;
    bool m_playerHostingConsent = false;
    bool m_backupHostingConsent = false;
    ForgeHostService *m_forgeHost = nullptr;
    QTimer m_helloTimer; // handshake timeout while connecting or reconnecting
    QTimer m_keepAliveTimer;
    QTimer m_rulesResponseTimer;
    QString m_rulesResponseRequestId;
    QString m_rulesResponseGameId;
    qint64 m_rulesResponsePromptId = 0;
    QString m_serverUrl;
    bool m_resumeAttempted = false;
    bool m_intentionalDisconnect = false;
};

} // namespace hexproof::client
