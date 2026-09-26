// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "WsClient.h"

#include "ProtocolSession.h"
#include "ReconnectController.h"
#include "ServerDirectory.h"

#include <QJsonArray>
#include <QRegularExpression>
#include <QSettings>

namespace hexproof::client {
using namespace hexproof::protocol;
using namespace Qt::StringLiterals;

bool WsClient::clusterAvailable() const
{
    return !m_clusterNode.isEmpty();
}

void WsClient::connectToOfficial(const QString &operation, const QString &value)
{
    // Continuing an existing device's room keeps its original node, including
    // legacy guest credentials. Explicit account login can discover it globally.
    const QString savedUrl = m_reconnectController->serverUrl();
    if (operation.isEmpty() && m_reconnectController->hasCredentials() &&
        m_reconnectController->matches(savedUrl, value.trimmed()) &&
        !m_serverDirectory->accountRealmForUrl(savedUrl).isEmpty()) {
        connectToServer(m_serverDirectory->indexForUrl(savedUrl), value);
        return;
    }
    const auto latencies = m_serverDirectory->latencies();
    QString realm;
    int best = -1;
    int bestLatency = 100000;
    for (int i = 0; i < m_serverDirectory->configuredServerCount(); ++i) {
        const QString url = m_serverDirectory->serverUrl(i);
        const QString candidateRealm = m_serverDirectory->accountRealmForUrl(url);
        if (candidateRealm.isEmpty() || (!realm.isEmpty() && candidateRealm != realm))
            continue;
        realm = candidateRealm;
        const int measured = i < latencies.size() ? latencies[i].toInt() : -2;
        const int score = measured >= 0 ? measured : measured == -1 ? 50000 : 10000;
        if (score < bestLatency) {
            best = i;
            bestLatency = score;
        }
    }
    if (best < 0) {
        setLastError(kErrClusterUnavailable, tr("No official entry node is configured."));
        return;
    }
    if (operation.isEmpty())
        connectToServer(best, value);
    else
        connectAccountToServer(best, operation, value);
}

void WsClient::rememberClusterNode()
{
    static const QRegularExpression pattern(u"^[A-Z0-9]{2,8}$"_s);
    if (!pattern.match(m_clusterNode).hasMatch()) {
        m_clusterNode.clear();
        return;
    }
    const QString realm = m_serverDirectory->accountRealmForUrl(m_serverUrl);
    if (!realm.isEmpty())
        QSettings().setValue(u"officialNodes/"_s + realm + u'/' + m_clusterNode, m_serverUrl);
}

QString WsClient::globalCode(const QString &localCode) const
{
    if (localCode.isEmpty() || localCode.contains(u':') || !clusterAvailable())
        return localCode;
    return m_clusterNode + u':' + localCode;
}

QJsonArray WsClient::clusterLatencies() const
{
    QJsonArray result;
    const auto latencies = m_serverDirectory->latencies();
    const QString realm = m_serverDirectory->accountRealmForUrl(m_serverUrl);
    for (int i = 0; i < latencies.size() && i < 16; ++i) {
        const QString url = m_serverDirectory->serverUrl(i);
        if (!realm.isEmpty() && m_serverDirectory->accountRealmForUrl(url) == realm &&
            latencies[i].toInt() >= -1)
            result.append(QJsonObject{{u"url"_s, url},
                                      {u"milliseconds"_s, qMin(2000, latencies[i].toInt())}});
    }
    return result;
}

bool WsClient::clusterCommand(const QString &type, const QJsonObject &payload) const
{
    if (!clusterAvailable())
        return false;
    if (type == kTypeRoomCreate || type == kTypeRoomJoin || type == kTypeTournamentCreate ||
        type == kTypeTournamentEnter)
        return true;
    return type == kTypeAccountCommand && (payload.value(u"operation"_s) == u"resume"_s ||
                                           (payload.value(u"operation"_s) == u"claim"_s &&
                                            (payload.value(u"kind"_s) == u"cube"_s ||
                                             payload.value(u"kind"_s) == u"tournament"_s)));
}

void WsClient::clearClusterCommand()
{
    m_clusterTimer.stop();
    m_clusterRequestId.clear();
    m_clusterCommandType.clear();
    m_clusterWire.clear();
    m_clusterTicket.clear();
    m_clusterDestination.clear();
    m_clusterAccountId.clear();
    m_clusterRouting = false;
}

void WsClient::failClusterRoute(const QString &message)
{
    const QString requestId = m_clusterRequestId;
    clearClusterCommand();
    setLastError(kErrClusterUnavailable, message);
    m_account->acceptError(requestId, kErrClusterUnavailable, message);
    m_protocolSession->resolveFailure(requestId, m_lastError);
    disconnectFromHub();
}

void WsClient::handleClusterRoute(const Envelope &env)
{
    const QString realm = m_serverDirectory->accountRealmForUrl(m_serverUrl);
    const QString url = env.payload.value(u"url"_s).toString();
    const QString node = env.payload.value(u"nodeId"_s).toString();
    const QString ticket = env.payload.value(u"ticket"_s).toString();
    static const QRegularExpression nodePattern(u"^[A-Z0-9]{2,8}$"_s);
    static const QRegularExpression ticketPattern(u"^[a-f0-9]{64}$"_s);
    if (env.id.isEmpty() || env.id != m_clusterRequestId || !clusterAvailable() ||
        !m_clusterDestination.isEmpty() || !roomId().isEmpty() || realm.isEmpty() ||
        env.payload.value(u"realm"_s).toString() != realm ||
        m_serverDirectory->accountRealmForUrl(url) != realm || url == m_serverUrl ||
        !nodePattern.match(node).hasMatch() || !ticketPattern.match(ticket).hasMatch()) {
        failClusterRoute(tr("The official node transfer could not be verified. Please reconnect."));
        return;
    }
    m_clusterRouting = true;
    m_clusterDestination = node;
    m_clusterAccountId = m_account->accountId();
    m_clusterTicket = ticket;
    m_clusterTimer.start(30000);
    // Keep this command's original correlation; other old-node requests have
    // ended. No command is retried if transmission to the destination fails.
    m_protocolSession->failAllExcept(m_clusterRequestId,
                                     tr("The connection moved to another official node."));
    connectTo(url, m_displayName);
}

bool WsClient::finishClusterRoute(const Envelope &welcome)
{
    if (!m_clusterRouting)
        return false;
    if (m_clusterNode != m_clusterDestination ||
        welcome.payload.value(u"accountId"_s).toString() != m_clusterAccountId ||
        welcome.payload.value(u"resumed"_s).toBool()) {
        failClusterRoute(tr("The official node transfer could not be verified. Please reconnect."));
        return true;
    }
    if (m_ws.sendTextMessage(QString::fromUtf8(m_clusterWire)) <= 0) {
        failClusterRoute(tr("Could not send the request to the selected official node."));
        return true;
    }
    if (m_clusterCommandType == kTypeAccountCommand)
        m_account->commandQueued(m_clusterRequestId);
    m_clusterRouting = false;
    m_clusterTicket.clear();
    setState(Connected);
    return true;
}

} // namespace hexproof::client
