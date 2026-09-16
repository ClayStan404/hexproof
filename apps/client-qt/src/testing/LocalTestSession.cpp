// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "LocalTestSession.h"
#include "services/LimitedSessionState.h"
#include "services/TournamentSessionState.h"
#include "services/WsClient.h"

#include <QHostAddress>
#include <QRegularExpression>
#include <QUrl>

namespace hexproof::client {
using namespace Qt::StringLiterals;

bool LocalTestSession::Options::commanderCube() const
{
    return eventType == u"commander-cube"_s;
}

QString LocalTestSession::Options::eventName() const
{
    if (commanderCube())
        return u"Local Commander Cube %1"_s.arg(group);
    return u"Local %1 %2 %3"_s.arg(eventType, setCode, group);
}

bool LocalTestSession::Options::valid() const
{
    const bool validSource =
        commanderCube()
            ? setCode.isEmpty() && !cube.trimmed().isEmpty()
            : cube.isEmpty() && QRegularExpression(u"^[A-Z0-9]{2,8}$"_s).match(setCode).hasMatch();
    return (eventType == u"draft"_s || eventType == u"sealed"_s || commanderCube()) &&
           players >= 2 && players <= (eventType == u"sealed"_s ? 16 : 8) && seat >= 1 &&
           seat <= players && timeoutMs > 0 && validSource && (!autoDraft || commanderCube()) &&
           QRegularExpression(u"^[a-f0-9]{32}$"_s).match(group).hasMatch();
}

void LocalTestSession::addOptions(QCommandLineParser &parser)
{
    parser.addOption({u"test-event"_s,
                      u"Automate local Limited setup: draft, sealed, or commander-cube."_s,
                      u"mode"_s});
    parser.addOption({u"test-set"_s, u"Installed Limited set code for local setup."_s, u"code"_s});
    parser.addOption(
        {u"test-cube"_s, u"Saved Cube name or ID for local Commander Cube setup."_s, u"cube"_s});
    parser.addOption(
        {u"test-auto-draft"_s,
         u"Finish local Commander Cube draft with random server picks; stop at deck building."_s});
    parser.addOption(
        {u"test-group"_s, u"Unique launcher group (32 lowercase hex digits)."_s, u"id"_s});
    parser.addOption({u"test-players"_s, u"Number of local test participants."_s, u"count"_s});
    parser.addOption(
        {u"test-seat"_s, u"Local participant number; seat 1 creates the event."_s, u"seat"_s});
}

LocalTestSession::Options LocalTestSession::readOptions(const QCommandLineParser &parser)
{
    Options options{parser.value(u"test-event"_s), parser.value(u"test-set"_s).toUpper(),
                    parser.value(u"test-group"_s), parser.value(u"test-players"_s).toInt(),
                    parser.value(u"test-seat"_s).toInt()};
    options.cube = parser.value(u"test-cube"_s).trimmed();
    options.autoDraft = parser.isSet(u"test-auto-draft"_s);
    return options;
}

bool LocalTestSession::requested(const QCommandLineParser &parser)
{
    for (const QString &name : {u"test-event"_s, u"test-set"_s, u"test-cube"_s, u"test-group"_s,
                                u"test-players"_s, u"test-seat"_s, u"test-auto-draft"_s}) {
        if (parser.isSet(name))
            return true;
    }
    return false;
}

LocalTestSession::LocalTestSession(WsClient *client, Options options,
                                   ProductProvider productProvider, QObject *parent)
    : QObject(parent),
      m_client(client),
      m_options(std::move(options)),
      m_productProvider(std::move(productProvider))
{
    m_timer.setInterval(100);
    connect(&m_timer, &QTimer::timeout, this, &LocalTestSession::advance);
    connect(m_client, &WsClient::lastErrorChanged, this, [this]() {
        if (m_active && !m_client->lastError().isEmpty())
            fail(m_client->lastError());
    });
}

void LocalTestSession::start()
{
    if (m_started)
        return;
    m_started = true;
    m_active = true;
    const QUrl url(m_client->serverUrl());
    if (!m_options.valid() || m_client->connectionState() != WsClient::Disconnected ||
        (url.scheme() != u"ws"_s && url.scheme() != u"wss"_s) ||
        (url.host() != u"localhost"_s && !QHostAddress(url.host()).isLoopback())) {
        fail(u"Invalid local test options or non-loopback server address."_s);
        return;
    }
    if (m_options.seat == 1) {
        m_product =
            m_productProvider(m_options.commanderCube() ? m_options.cube : m_options.setCode);
        if (m_product.isEmpty()) {
            if (m_options.commanderCube()) {
                fail(
                    u"No unique ready Cube matches %1; use a saved Cube name or ID in a fresh profile template."_s
                        .arg(m_options.cube));
                return;
            }
            fail(
                u"No installed Limited product for %1; update the profile's card database or use a fresh template."_s
                    .arg(m_options.setCode));
            return;
        }
    }
    // A new launch group is a new event, never an implicit resume of an old room.
    m_client->disconnectFromHub();
    m_elapsed.start();
    m_timer.start();
    m_client->connectToCustomServer(m_client->serverUrl(), m_client->displayName());
}

void LocalTestSession::fail(const QString &reason)
{
    if (!m_active)
        return;
    m_active = false;
    m_timer.stop();
    emit failed(u"Local test setup stopped: "_s + reason);
}

void LocalTestSession::advance()
{
    if (m_elapsed.elapsed() >= m_options.timeoutMs) {
        fail(
            u"Timed out waiting for connection, event, or all participants. Check the client logs; setup can be completed manually."_s);
        return;
    }
    if (m_client->connectionState() == WsClient::Disconnected || m_client->reconnecting()) {
        fail(u"Connection lost during setup. Restart the test group or finish setup manually."_s);
        return;
    }
    if (!m_client->connected())
        return;

    auto *event = m_client->tournamentSession();
    if (!event->inTournament()) {
        if (m_options.seat == 1) {
            if (!m_createSent) {
                m_createSent = true;
                if (m_options.commanderCube())
                    m_client->createCasualLimitedEvent(m_options.eventName(), u"commander_cube"_s,
                                                       u"bo1"_s, m_options.players, m_product);
                else
                    m_client->createLimitedTournament(m_options.eventName(),
                                                      u"set_"_s + m_options.eventType, u"bo3"_s, 50,
                                                      m_options.players, m_product);
            }
        } else if (!m_enterSent) {
            const QVariantList entries =
                m_options.commanderCube() ? m_client->roomList() : event->tournamentList();
            for (const QVariant &value : entries) {
                const QVariantMap entry = value.toMap();
                if (entry.value(u"name"_s).toString() != m_options.eventName())
                    continue;
                m_tournamentId =
                    entry.value(m_options.commanderCube() ? u"roomId"_s : u"tournamentId"_s)
                        .toString();
                m_enterSent = true;
                if (m_options.commanderCube())
                    m_client->joinRoom(m_tournamentId, false, {});
                else
                    m_client->enterTournament(m_tournamentId);
                return;
            }
            if (m_elapsed.elapsed() - m_lastListAt >= 1'000) {
                m_lastListAt = m_elapsed.elapsed();
                if (m_options.commanderCube())
                    m_client->requestRoomList();
                else
                    m_client->requestTournamentList();
            }
        }
        return;
    }
    if (event->status().isEmpty())
        return; // Wait for the authoritative snapshot after created/entered.
    if (event->name() != m_options.eventName() ||
        event->eventType() !=
            (m_options.commanderCube() ? u"commander_cube"_s : u"set_"_s + m_options.eventType) ||
        event->maxPlayers() != m_options.players ||
        (!m_tournamentId.isEmpty() && event->tournamentId() != m_tournamentId)) {
        fail(u"The active event does not match this launch group."_s);
        return;
    }
    m_tournamentId = event->tournamentId();
    const auto *limited = m_client->limitedSession();
    if (!event->participantId().isEmpty() && limited->tournamentId() == m_tournamentId) {
        const QString expectedStage = m_options.eventType == u"sealed"_s || m_options.autoDraft
                                          ? u"deck_building"_s
                                          : u"draft"_s;
        if (limited->stage() == expectedStage &&
            (expectedStage != u"draft"_s || !limited->currentPack().isEmpty())) {
            m_active = false;
            m_timer.stop();
            emit finished();
            return;
        }
        if (m_options.autoDraft && limited->stage() == u"draft"_s && !m_autoDraftSent &&
            !limited->currentPack().isEmpty()) {
            m_autoDraftSent = true;
            m_client->setLimitedDraftControl(event->participantId(), true);
            return;
        }
    }
    if (event->status() != u"registration"_s) {
        if (event->status() != u"running"_s)
            fail(u"The event was closed before setup completed."_s);
        return;
    }
    if (event->participantId().isEmpty()) {
        if (!m_registerSent) {
            m_registerSent = true;
            m_client->registerTournament();
        }
        return;
    }
    for (const QVariant &value : event->participants()) {
        const QVariantMap participant = value.toMap();
        if (participant.value(u"participantId"_s).toString() == event->participantId() &&
            !participant.value(u"checkedIn"_s).toBool() && !m_checkInSent) {
            m_checkInSent = true;
            m_client->setTournamentCheckedIn(true);
            return;
        }
    }
    if (m_options.seat == 1 && !m_startSent && event->registered() == m_options.players &&
        event->checkedIn() == m_options.players) {
        m_startSent = true;
        m_client->startTournament();
    }
}

} // namespace hexproof::client
