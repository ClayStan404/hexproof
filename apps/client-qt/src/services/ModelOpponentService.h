// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QElapsedTimer>
#include <QHash>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>
#include <QTimer>
#include <QVariantMap>

class QNetworkReply;
class QWebSocket;

namespace hexproof::client {

// A separately authorized AI-seat worker. This service never receives the
// privileged Forge hosting bundle and never persists credentials or decisions.
class ModelOpponentService : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int revision READ revision NOTIFY profilesChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString testStatus READ testStatus NOTIFY statusChanged)
    Q_PROPERTY(QString failureCode READ failureCode NOTIFY statusChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY statusChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY statusChanged)
    Q_PROPERTY(bool active READ active NOTIFY statusChanged)
    Q_PROPERTY(QString armedSource READ armedSource NOTIFY statusChanged)
    Q_PROPERTY(int callsUsed READ callsUsed NOTIFY statusChanged)
    Q_PROPERTY(qint64 reservedTokens READ reservedTokens NOTIFY statusChanged)
    Q_PROPERTY(QObject *cardCatalog READ cardCatalog WRITE setCardCatalog NOTIFY cardCatalogChanged)

  public:
    explicit ModelOpponentService(QObject *parent = nullptr);
    explicit ModelOpponentService(const QString &profileFile, QObject *parent = nullptr);
    ~ModelOpponentService() override;

    int revision() const
    {
        return m_revision;
    }
    QString status() const
    {
        return m_status;
    }
    QString testStatus() const
    {
        return m_testStatus;
    }
    QString failureCode() const
    {
        return m_failureCode;
    }
    QString lastError() const
    {
        return m_lastError;
    }
    bool busy() const
    {
        return !m_reply.isNull();
    }
    bool active() const
    {
        return m_active;
    }
    QString roomId() const
    {
        return m_roomId;
    }
    QString armedSource() const
    {
        return m_armedSource;
    }
    int callsUsed() const;
    qint64 reservedTokens() const;
    QObject *cardCatalog() const
    {
        return m_catalog;
    }
    void setCardCatalog(QObject *catalog);

    Q_INVOKABLE QVariantMap profile(const QString &source) const;
    Q_INVOKABLE bool saveProfile(const QString &source, const QVariantMap &configuration,
                                 const QString &key);
    Q_INVOKABLE bool configured(const QString &source) const;
    Q_INVOKABLE void testProfile(const QString &source);
    Q_INVOKABLE bool arm(const QString &source);
    void start(const QString &serverUrl, const QJsonObject &grant);
    Q_INVOKABLE void stop();

  signals:
    void profilesChanged();
    void statusChanged();
    void cardCatalogChanged();

  private:
    struct Budget
    {
        int calls = 0;
        qint64 tokens = 0;
    };
    static QVariantMap defaults(const QString &source);
    static bool validProfile(const QString &source, const QVariantMap &profile);
    static bool validAnswer(const QJsonObject &answer, const QJsonObject &prompt);
    void loadProfiles();
    void closeWorker();
    void cancelRequest();
    void receive(const QString &message);
    void decide(const QJsonObject &decision);
    void callProvider(bool repair);
    void providerFinished(QNetworkReply *reply, quint64 generation);
    void repairOrFail();
    void fail(const QString &code);
    void sendWorker(const QString &type, const QJsonObject &payload);
    QJsonObject observation() const;
    QJsonObject forcedAnswer() const;
    void setStatus(const QString &status);

    QString m_profileFile;
    QHash<QString, QVariantMap> m_profiles;
    QHash<QString, QString> m_keys;
    int m_revision = 0;
    QPointer<QObject> m_catalog;
    QNetworkAccessManager m_network;
    QPointer<QWebSocket> m_socket;
    QPointer<QNetworkReply> m_reply;
    QTimer m_deadline;
    QElapsedTimer m_requestClock;
    quint64 m_generation = 0;
    QString m_status = QStringLiteral("idle");
    QString m_testStatus = QStringLiteral("untested");
    QString m_failureCode;
    QString m_lastError;
    QString m_armedSource;
    QVariantMap m_armedProfile;
    QString m_armedKey;
    QString m_roomId;
    QString m_origin;
    QString m_requestId;
    QString m_budgetKey;
    QString m_gameId;
    QString m_testingSource;
    QJsonObject m_decision;
    QHash<QString, Budget> m_budgets;
    bool m_active = false;
    bool m_repaired = false;
    bool m_answerSent = false;
};

} // namespace hexproof::client
