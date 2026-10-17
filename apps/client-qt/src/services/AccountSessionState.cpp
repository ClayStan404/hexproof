// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "AccountSessionState.h"

#include "ApplicationPaths.h"

#include <QCryptographicHash>
#include <QFutureWatcher>
#include <QJsonArray>
#include <QSysInfo>
#include <QtConcurrentRun>

namespace hexproof::client {
using namespace Qt::StringLiterals;

AccountSessionState::AccountSessionState(QObject *parent)
    : AccountSessionState(defaultStorageRoot(), readAccountVault, writeAccountVault, parent)
{
}

AccountSessionState::AccountSessionState(const QString &profile, VaultRead read, VaultWrite write,
                                         QObject *parent)
    : QObject(parent),
      m_profile(profile),
      m_read(std::move(read)),
      m_write(std::move(write))
{
    m_vaultPool.setMaxThreadCount(1);
    m_timeout.setSingleShot(true);
    m_timeout.setInterval(15000);
    connect(&m_timeout, &QTimer::timeout, this, [this] {
        m_pending.clear();
        m_sending = false;
        m_lastError = tr("Account request timed out. Reconnect and retry.");
        emit changed();
    });
}

AccountSessionState::~AccountSessionState()
{
    m_vaultPool.waitForDone();
}

QString AccountSessionState::vaultKey(const QString &realm) const
{
    return QString::fromLatin1(
        QCryptographicHash::hash((m_profile + u'\n' + realm).toUtf8(), QCryptographicHash::Sha256)
            .toHex());
}

void AccountSessionState::prepareRealm(const QString &realm)
{
    if (realm != m_realm) {
        clearIdentity();
        m_loginCode.clear();
        m_recoveryCode.clear();
    }
    m_realm = realm;
    m_supported = false;
    m_ready = false;
    m_autoAttempted = false;
    if (realm.isEmpty() || m_loaded.contains(realm)) {
        emit changed();
        return;
    }
    m_loaded.insert(realm, false);
    const QString key = vaultKey(realm);
    auto *watcher = new QFutureWatcher<AccountVaultResult>(this);
    connect(watcher, &QFutureWatcher<AccountVaultResult>::finished, this, [this, watcher, realm] {
        const auto result = watcher->result();
        watcher->deleteLater();
        // A manual login can finish before a locked/unavailable vault responds.
        if (!m_tokens.contains(realm) && result.token.size() <= 128)
            m_tokens.insert(realm, result.token);
        m_loaded[realm] = true;
        if (realm == m_realm) {
            m_vaultAvailable = result.available;
            emit changed();
            tryAutomaticLogin();
        }
    });
    watcher->setFuture(QtConcurrent::run(&m_vaultPool, [read = m_read, key] { return read(key); }));
    emit changed();
}

QString AccountSessionState::helloToken(const QString &realm) const
{
    return !m_guestMode && m_loginOperation.isEmpty() && !realm.isEmpty() && realm == m_realm
               ? m_tokens.value(realm)
               : QString{};
}

void AccountSessionState::setLoginIntent(const QString &operation, const QString &value)
{
    m_guestMode = operation == u"guest"_s;
    m_loginOperation = operation;
    m_loginValue = value;
}

void AccountSessionState::welcome(const QString &realm, const QString &accountId,
                                  const QString &name, bool recoverRoom)
{
    m_recoverRoomAfterStatus = recoverRoom;
    m_supported = !m_realm.isEmpty() && realm == m_realm;
    if (!m_supported && !m_loginOperation.isEmpty()) {
        m_loginOperation.clear();
        m_loginValue.clear();
        m_lastError = tr("This server does not offer official accounts.");
    }
    m_autoAttempted = false;
    m_refreshAfterWelcome = false;
    if (m_supported && !accountId.isEmpty() && !m_tokens.value(m_realm).isEmpty()) {
        m_accountId = accountId;
        m_displayName = name;
        m_refreshAfterWelcome = true;
    } else {
        clearIdentity();
    }
    emit changed();
    tryAutomaticLogin();
}

void AccountSessionState::setTransportReady(bool ready)
{
    m_ready = ready;
    if (!ready) {
        m_pending.clear();
        m_sending = false;
        m_timeout.stop();
    }
    emit changed();
    if (ready)
        tryAutomaticLogin();
}

void AccountSessionState::tryAutomaticLogin()
{
    if (!m_ready || !m_supported || busy() || m_autoAttempted)
        return;
    if (!m_loginOperation.isEmpty()) {
        const QString operation = m_loginOperation;
        const QString value = m_loginValue;
        m_loginOperation.clear();
        m_loginValue.clear();
        m_autoAttempted = true;
        if (operation == u"guest"_s)
            return;
        if (operation == u"create"_s)
            createAccount(value);
        else if (operation == u"recover"_s)
            recover(value);
        else
            login(value);
    } else if (m_refreshAfterWelcome) {
        m_autoAttempted = true;
        m_refreshAfterWelcome = false;
        request(u"status"_s);
    } else if (!m_guestMode && !authenticated() && m_loaded.value(m_realm) &&
               !m_tokens.value(m_realm).isEmpty()) {
        m_autoAttempted = true;
        request(u"attach"_s, {{u"credential"_s, m_tokens.value(m_realm)}});
    }
}

void AccountSessionState::request(const QString &operation, QJsonObject extra)
{
    if (!m_supported || !m_ready || busy())
        return;
    m_lastError.clear();
    m_operation = operation;
    m_sending = true;
    extra.insert(u"operation"_s, operation);
    emit changed();
    emit commandRequested(extra);
    if (operation == u"create"_s || operation == u"login"_s || operation == u"recover"_s)
        QTimer::singleShot(0, this, &AccountSessionState::accountPageRequested);
}

void AccountSessionState::commandQueued(const QString &id)
{
    m_pending = id;
    m_sending = false;
    if (!id.isEmpty())
        m_timeout.start();
    else
        m_lastError = tr("Connect to the official server before managing your account.");
    emit changed();
}

void AccountSessionState::saveSession(const QString &token)
{
    m_tokens[m_realm] = token;
    const QString realm = m_realm;
    const QString key = vaultKey(realm);
    auto *watcher = new QFutureWatcher<bool>(this);
    connect(watcher, &QFutureWatcher<bool>::finished, this, [this, watcher, realm] {
        const bool available = watcher->result();
        watcher->deleteLater();
        if (realm == m_realm) {
            m_vaultAvailable = available;
            emit changed();
        }
    });
    watcher->setFuture(QtConcurrent::run(
        &m_vaultPool, [write = m_write, key, token] { return write(key, token); }));
}

void AccountSessionState::clearIdentity()
{
    m_accountId.clear();
    m_displayName.clear();
    m_sessionId.clear();
    m_loginCode.clear();
    m_recoveryCode.clear();
    m_devices.clear();
    m_resources.clear();
    m_claimQueue.clear();
    m_activeClaim = {};
    m_claimFailures = 0;
}

void AccountSessionState::acceptState(const QString &id, const QJsonObject &state)
{
    if (id.isEmpty() || id != m_pending || !m_supported)
        return;
    m_timeout.stop();
    m_pending.clear();
    m_sending = false;
    const QString operation = state.value(u"operation"_s).toString();
    m_accountId = state.value(u"accountId"_s).toString();
    m_displayName = state.value(u"displayName"_s).toString();
    m_sessionId = state.value(u"sessionId"_s).toString();
    m_devices = state.value(u"devices"_s).toArray().toVariantList();
    m_resources = state.value(u"resources"_s).toArray().toVariantList();
    if (state.contains(u"loginCode"_s))
        m_loginCode = state.value(u"loginCode"_s).toString();
    if (state.contains(u"recoveryCode"_s))
        m_recoveryCode = state.value(u"recoveryCode"_s).toString();
    if (state.contains(u"sessionToken"_s))
        saveSession(state.value(u"sessionToken"_s).toString());
    bool currentSessionPresent = false;
    for (const auto &device : m_devices)
        currentSessionPresent |= device.toMap().value(u"current"_s).toBool();
    if (operation == u"logout"_s || (operation == u"revoke"_s && !currentSessionPresent)) {
        saveSession({});
        clearIdentity();
        m_loginCode.clear();
        m_recoveryCode.clear();
        emit changed();
        emit loggedOut();
        return;
    }
    for (const auto &grant : state.value(u"replays"_s).toArray())
        emit replayGranted(grant.toObject());
    emit changed();
    if (operation == u"claim"_s) {
        QTimer::singleShot(45, this, &AccountSessionState::nextClaim);
    } else if (operation == u"replays"_s && state.value(u"hasMore"_s).toBool()) {
        request(u"replays"_s, {{u"offset"_s, state.value(u"offset"_s).toInt() +
                                                 state.value(u"replays"_s).toArray().size()}});
    } else if (operation == u"login"_s || operation == u"attach"_s ||
               (operation == u"status"_s && m_recoverRoomAfterStatus)) {
        m_recoverRoomAfterStatus = false;
        QStringList rooms;
        for (const auto &value : m_resources) {
            const auto resource = value.toMap();
            if (resource.value(u"kind"_s).toString() == u"room"_s)
                rooms.append(resource.value(u"id"_s).toString());
        }
        rooms.removeDuplicates();
        if (rooms.size() == 1)
            resumeRoom(rooms.first());
        else if (rooms.size() > 1)
            emit accountPageRequested();
    }
}

void AccountSessionState::acceptError(const QString &id, const QString &code,
                                      const QString &message)
{
    const bool credentialRejected = code == u"account_invalid"_s;
    if (id != m_pending && !credentialRejected)
        return;
    const bool helloRejected = !m_ready && !m_tokens.value(m_realm).isEmpty();
    m_timeout.stop();
    m_pending.clear();
    m_sending = false;
    if (credentialRejected && (m_operation == u"attach"_s || authenticated() || helloRejected)) {
        saveSession({});
        clearIdentity();
        m_autoAttempted = true;
        emit loggedOut();
    }
    m_lastError = message;
    emit changed();
    if (m_operation == u"claim"_s && authenticated()) {
        if (code == u"rate_limited"_s && !m_activeClaim.isEmpty()) {
            m_claimQueue.prepend(m_activeClaim);
            QTimer::singleShot(60000, this, &AccountSessionState::nextClaim);
        } else {
            ++m_claimFailures;
            QTimer::singleShot(45, this, &AccountSessionState::nextClaim);
        }
        emit changed();
    }
}

void AccountSessionState::createAccount(const QString &name)
{
    m_guestMode = false;
    request(u"create"_s, {{u"name"_s, name.trimmed()},
                          {u"deviceName"_s, QSysInfo::prettyProductName().left(80)}});
}
void AccountSessionState::login(const QString &code)
{
    m_guestMode = false;
    request(u"login"_s, {{u"loginCode"_s, code.trimmed()},
                         {u"deviceName"_s, QSysInfo::prettyProductName().left(80)}});
}
void AccountSessionState::recover(const QString &code)
{
    m_guestMode = false;
    request(u"recover"_s, {{u"recoveryCode"_s, code.trimmed()},
                           {u"deviceName"_s, QSysInfo::prettyProductName().left(80)}});
}
void AccountSessionState::refresh()
{
    request(u"status"_s);
}
void AccountSessionState::rename(const QString &name)
{
    request(u"rename"_s, {{u"name"_s, name.trimmed()}});
}
void AccountSessionState::rotateLoginCode()
{
    request(u"rotate"_s);
}
void AccountSessionState::revokeSession(const QString &id)
{
    request(u"revoke"_s, {{u"sessionId"_s, id}});
}
void AccountSessionState::revokeOtherSessions()
{
    request(u"revoke_others"_s);
}
void AccountSessionState::logout()
{
    request(u"logout"_s);
}
void AccountSessionState::acknowledgeBackup()
{
    m_loginCode.clear();
    m_recoveryCode.clear();
    emit changed();
}
void AccountSessionState::resumeRoom(const QString &id)
{
    request(u"resume"_s, {{u"resourceId"_s, id}});
}
void AccountSessionState::requestReplays()
{
    request(u"replays"_s);
}
void AccountSessionState::claim(const QString &kind, const QString &id, const QString &credential)
{
    request(u"claim"_s, {{u"kind"_s, kind}, {u"resourceId"_s, id}, {u"credential"_s, credential}});
}

void AccountSessionState::claimAll(const QList<QJsonObject> &claims)
{
    if (busy() || !authenticated() || !m_claimQueue.isEmpty())
        return;
    m_claimFailures = 0;
    m_claimQueue = claims;
    nextClaim();
}

void AccountSessionState::nextClaim()
{
    if (busy() || !authenticated() || !m_ready)
        return;
    if (m_claimQueue.isEmpty()) {
        if (m_claimFailures > 0)
            m_lastError = tr("Some saved identities could not be linked. They may have expired or "
                             "belong to another account.");
        emit changed();
        return;
    }
    m_activeClaim = m_claimQueue.takeFirst();
    request(u"claim"_s, m_activeClaim);
}

} // namespace hexproof::client
