// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "WsClient.h"

#include "ProtocolSession.h"
#include <QJsonArray>
#include <QJsonDocument>
#include <algorithm>

namespace hexproof::client {
using namespace Qt::StringLiterals;
using namespace hexproof::protocol;

void WsClient::initializePeerTransport()
{
    m_peerTransport = new PeerTransportService(this);
    connect(this, &WsClient::peerTransportChanged, this, [this]() {
        m_forgeHost->setTransportDiagnostics(peerTransportState(), m_directPeerDecisions,
                                             m_peerFallbacks);
    });
    connect(m_roomSession, &RoomSessionState::snapshotChanged, this, [this]() {
        if (m_roomSession->hostStatus().value(u"migrating"_s).toBool()) {
            // Transfer restores the last confirmed position and rotates prompts.
            // Do not submit a speculative old input while that position is frozen.
            m_peerFallbackTimer.stop();
            m_peerFallbackWire.clear();
            m_peerTransport->stop();
        } else if (m_roomSession->hostConnected() && !m_peerTransport->ready()) {
            fallbackPeerDecision();
        }
        emit peerTransportChanged();
    });
    connect(this, &WsClient::connectionStateChanged, this, &WsClient::peerTransportChanged);
    m_peerFallbackTimer.setSingleShot(true);
    m_peerFallbackTimer.setInterval(1500);
    connect(&m_peerFallbackTimer, &QTimer::timeout, this, &WsClient::fallbackPeerDecision);
    connect(m_peerTransport, &PeerTransportService::changed, this, [this]() {
        if (!m_peerTransport->ready())
            fallbackPeerDecision();
        emit peerTransportChanged();
    });
    connect(m_peerTransport, &PeerTransportService::localSignal, this,
            [this](const QJsonObject &signal) {
                if (!m_peerConsent || !inRoom() || m_ws.state() != QAbstractSocket::ConnectedState)
                    return;
                Envelope envelope;
                envelope.type = kTypeForgePeerSignal;
                envelope.payload = {{u"roomId"_s, roomId()},
                                    {u"bindingId"_s, m_peerTransport->bindingId()},
                                    {u"data"_s, QString::fromUtf8(QJsonDocument(signal).toJson(
                                                    QJsonDocument::Compact))}};
                m_ws.sendTextMessage(QString::fromUtf8(serialize(envelope)));
            });
    connect(m_peerTransport, &PeerTransportService::messageReceived, this,
            &WsClient::handlePeerMessage);
    connect(m_forgeHost, &ForgeHostService::peerReply, this, [this](const QJsonObject &reply) {
        if (m_peerConsent &&
            reply.value(u"bindingId"_s).toString() == m_peerTransport->bindingId() &&
            m_roomSession->seatIndex() == m_peerTransport->hostSeat())
            m_peerTransport->send(reply);
    });
}

QString WsClient::peerTransportState() const
{
    if (!m_peerConsent)
        return u"off"_s;
    if (m_roomSession->hostStatus().value(u"migrating"_s).toBool())
        return u"migrating"_s;
    if (m_state == Reconnecting)
        return u"reconnecting"_s;
    if (!m_peerOtherEnabled)
        return u"waiting"_s;
    return m_peerTransport ? m_peerTransport->state() : u"relay"_s;
}

QVariantMap WsClient::peerTransportMetrics() const
{
    QList<qint64> ordered = m_peerLatencies;
    std::sort(ordered.begin(), ordered.end());
    return {{u"confirmedDecisions"_s, m_directPeerDecisions},
            {u"fallbacks"_s, m_peerFallbacks},
            {u"samples"_s, ordered.size()},
            {u"p50Ms"_s, ordered.isEmpty() ? 0 : ordered[(ordered.size() - 1) / 2]},
            {u"p95Ms"_s, ordered.isEmpty() ? 0 : ordered[(ordered.size() - 1) * 95 / 100]}};
}

void WsClient::setDirectPeerPreferred(bool enabled)
{
    m_directPeerPreferred = enabled;
    if (enabled != m_peerConsent)
        setDirectPeerEnabled(enabled);
}

void WsClient::setDirectPeerEnabled(bool enabled, bool retry)
{
    if (!m_peerTransportAvailable || !inRoom() || m_roomSession->role() != kRolePlayer ||
        m_roomSession->hostingMode() != kHostingModePlayer || m_roomSession->seatIndex() < 0 ||
        m_roomSession->seatIndex() > 1 || !m_roomSession->aiSource().isEmpty())
        return;
    m_peerConsent = enabled;
    if (!enabled) {
        fallbackPeerDecision();
        m_peerTransport->stop();
    }
    send(kTypeForgePeerRequest, {{u"enabled"_s, enabled}, {u"retry"_s, retry}});
    emit peerTransportChanged();
}

void WsClient::handlePeerEnvelope(const Envelope &env)
{
    if (env.payload.value(u"roomId"_s).toString() != roomId() ||
        m_roomSession->role() != kRolePlayer)
        return;
    if (env.type == kTypeForgePeerGrant) {
        if (m_peerConsent && m_roomSession->hostingMode() == kHostingModePlayer)
            m_peerTransport->start(env.payload);
    } else if (env.type == kTypeForgePeerSignaled) {
        if (m_peerConsent &&
            env.payload.value(u"bindingId"_s).toString() == m_peerTransport->bindingId())
            m_peerTransport->signal(
                QJsonDocument::fromJson(env.payload.value(u"data"_s).toString().toUtf8()).object());
    } else if (env.type == kTypeForgePeerStatus) {
        m_peerOtherEnabled = env.payload.value(u"otherEnabled"_s).toBool();
        if (env.payload.value(u"bindingId"_s).toString().isEmpty())
            m_peerTransport->stop();
        emit peerTransportChanged();
    }
}

void WsClient::handlePeerMessage(const QJsonObject &message)
{
    if (!m_peerConsent || !inRoom() || m_ws.state() != QAbstractSocket::ConnectedState ||
        message.value(u"bindingId"_s).toString() != m_peerTransport->bindingId())
        return;
    if (m_roomSession->seatIndex() == m_peerTransport->hostSeat()) {
        if (message.value(u"request"_s).isObject() &&
            message.value(u"operationId"_s).toString().size() <= 128)
            m_forgeHost->submitPeerAction(message);
        return;
    }
    if (message.value(u"operationId"_s).toString() != m_peerRequestId || m_peerRequestId.isEmpty())
        return;
    if (!message.value(u"error"_s).toString().isEmpty()) {
        fallbackPeerDecision();
        return;
    }
    const QJsonArray values = message.value(u"envelopes"_s).toArray();
    if (values.size() != 3) {
        fallbackPeerDecision();
        return;
    }
    QList<Envelope> envelopes;
    const QStringList types{kTypeRulesResponded, kTypeRulesSnapshot, kTypeRulesPrompt};
    for (qsizetype i = 0; i < values.size(); ++i) {
        bool ok = false;
        const Envelope envelope =
            parse(QJsonDocument(values[i].toObject()).toJson(QJsonDocument::Compact), &ok);
        if (!ok || envelope.type != types[i] ||
            envelope.payload.value(u"roomId"_s).toString() != roomId() ||
            (i > 0 &&
             envelope.payload.value(u"gameId"_s).toString() != m_peerTransport->gameId()) ||
            (i == 0 && envelope.id != m_peerRequestId)) {
            fallbackPeerDecision();
            return;
        }
        envelopes.append(envelope);
    }
    // A host action may already have arrived over WS while this packet was in
    // flight. Resolve its acknowledgement without rolling the board backwards.
    if (envelopes[1].hasSeq && envelopes[1].seq > m_lastRulesSnapshotSeq &&
        m_rulesSession->gameId() == m_peerTransport->gameId()) {
        dispatch(envelopes[1], {});
        dispatch(envelopes[2], {});
    }
    dispatch(envelopes[0], {});
    m_peerFallbackTimer.stop();
    m_peerFallbackWire.clear();
    m_peerRequestId.clear();
    ++m_directPeerDecisions;
    if (m_peerDecisionClock.isValid()) {
        m_peerLatencies.append(m_peerDecisionClock.elapsed());
        if (m_peerLatencies.size() > 128)
            m_peerLatencies.removeFirst();
    }
    emit peerTransportChanged();
}

void WsClient::fallbackPeerDecision()
{
    if (m_peerFallbackWire.isEmpty() || m_ws.state() != QAbstractSocket::ConnectedState ||
        m_peerRequestId != m_rulesResponseRequestId || !m_roomSession->hostConnected() ||
        m_roomSession->hostStatus().value(u"migrating"_s).toBool())
        return;
    const QByteArray wire = m_peerFallbackWire;
    m_peerFallbackWire.clear();
    m_peerFallbackTimer.stop();
    // Preserve the same operation ID and binding. The server/engine reuse the
    // committed result if the direct operation already executed.
    if (m_ws.sendTextMessage(QString::fromUtf8(wire)) > 0) {
        ++m_peerFallbacks;
        emit peerTransportChanged();
    }
}
} // namespace hexproof::client
