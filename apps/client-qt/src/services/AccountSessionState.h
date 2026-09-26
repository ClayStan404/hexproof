// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "AccountVault.h"

#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QThreadPool>
#include <QTimer>
#include <QVariantList>
#include <functional>

namespace hexproof::client {

class AccountSessionState final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool supported READ supported NOTIFY changed)
    Q_PROPERTY(bool authenticated READ authenticated NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(bool vaultAvailable READ vaultAvailable NOTIFY changed)
    Q_PROPERTY(QString accountId READ accountId NOTIFY changed)
    Q_PROPERTY(QString displayName READ displayName NOTIFY changed)
    Q_PROPERTY(QString loginCode READ loginCode NOTIFY changed)
    Q_PROPERTY(QString recoveryCode READ recoveryCode NOTIFY changed)
    Q_PROPERTY(QString lastError READ lastError NOTIFY changed)
    Q_PROPERTY(QVariantList devices READ devices NOTIFY changed)
    Q_PROPERTY(QVariantList resources READ resources NOTIFY changed)
    Q_PROPERTY(int pendingClaims READ pendingClaims NOTIFY changed)

  public:
    using VaultRead = std::function<AccountVaultResult(const QString &)>;
    using VaultWrite = std::function<bool(const QString &, const QString &)>;
    explicit AccountSessionState(QObject *parent = nullptr);
    AccountSessionState(const QString &profile, VaultRead read, VaultWrite write,
                        QObject *parent = nullptr);
    ~AccountSessionState() override;

    bool supported() const
    {
        return m_supported;
    }
    bool authenticated() const
    {
        return !m_accountId.isEmpty();
    }
    bool busy() const
    {
        return !m_pending.isEmpty() || m_sending;
    }
    bool vaultAvailable() const
    {
        return m_vaultAvailable;
    }
    QString accountId() const
    {
        return m_accountId;
    }
    QString displayName() const
    {
        return m_displayName;
    }
    QString loginCode() const
    {
        return m_loginCode;
    }
    QString recoveryCode() const
    {
        return m_recoveryCode;
    }
    QString lastError() const
    {
        return m_lastError;
    }
    QVariantList devices() const
    {
        return m_devices;
    }
    QVariantList resources() const
    {
        return m_resources;
    }
    int pendingClaims() const
    {
        return m_claimQueue.size() + (m_operation == QStringLiteral("claim") && busy() ? 1 : 0);
    }

    void prepareRealm(const QString &realm);
    void setLoginIntent(const QString &operation, const QString &value);
    QString helloToken(const QString &realm) const;
    bool requiresAccountLogin() const
    {
        return !m_loginOperation.isEmpty() && !m_guestMode;
    }
    void welcome(const QString &realm, const QString &accountId, const QString &name,
                 bool recoverRoom = false);
    void setTransportReady(bool ready);
    void commandQueued(const QString &id);
    void acceptState(const QString &id, const QJsonObject &state);
    void acceptError(const QString &id, const QString &code, const QString &message);

    Q_INVOKABLE void createAccount(const QString &name);
    Q_INVOKABLE void login(const QString &code);
    Q_INVOKABLE void recover(const QString &code);
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void rename(const QString &name);
    Q_INVOKABLE void rotateLoginCode();
    Q_INVOKABLE void revokeSession(const QString &id);
    Q_INVOKABLE void revokeOtherSessions();
    Q_INVOKABLE void logout();
    Q_INVOKABLE void acknowledgeBackup();
    Q_INVOKABLE void resumeRoom(const QString &id);
    Q_INVOKABLE void requestReplays();
    void claim(const QString &kind, const QString &id, const QString &credential);
    void claimAll(const QList<QJsonObject> &claims);

  signals:
    void changed();
    void commandRequested(const QJsonObject &command);
    void replayGranted(const QJsonObject &grant);
    void loggedOut();
    void accountPageRequested();

  private:
    void request(const QString &operation, QJsonObject extra = {});
    void tryAutomaticLogin();
    void saveSession(const QString &token);
    void clearIdentity();
    void nextClaim();
    QString vaultKey(const QString &realm) const;

    QString m_profile;
    VaultRead m_read;
    VaultWrite m_write;
    QThreadPool m_vaultPool;
    QTimer m_timeout;
    QHash<QString, QString> m_tokens;
    QHash<QString, bool> m_loaded;
    QString m_realm;
    QString m_accountId;
    QString m_displayName;
    QString m_sessionId;
    QString m_loginCode;
    QString m_recoveryCode;
    QString m_lastError;
    QString m_pending;
    QString m_operation;
    QString m_loginOperation;
    QString m_loginValue;
    QVariantList m_devices;
    QVariantList m_resources;
    QList<QJsonObject> m_claimQueue;
    QJsonObject m_activeClaim;
    int m_claimFailures = 0;
    bool m_guestMode = false;
    bool m_supported = false;
    bool m_ready = false;
    bool m_vaultAvailable = true;
    bool m_sending = false;
    bool m_autoAttempted = false;
    bool m_refreshAfterWelcome = false;
    bool m_recoverRoomAfterStatus = false;
};

} // namespace hexproof::client
