// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QCommandLineParser>
#include <QElapsedTimer>
#include <QObject>
#include <QTimer>
#include <QVariantMap>
#include <functional>

namespace hexproof::client {

class WsClient;

// Opt-in workstation automation. All actions use the ordinary client facade;
// optional Cube auto-draft uses server-owned picks. Deck construction stays manual.
class LocalTestSession final : public QObject
{
    Q_OBJECT

  public:
    struct Options
    {
        QString eventType;
        QString setCode;
        QString group;
        int players = 0;
        int seat = 0;
        int timeoutMs = 90'000;
        QString cube = {};
        bool autoDraft = false;
        bool commanderCube() const;
        QString eventName() const;
        bool valid() const;
    };
    using ProductProvider = std::function<QVariantMap(const QString &)>;

    static void addOptions(QCommandLineParser &parser);
    static Options readOptions(const QCommandLineParser &parser);
    static bool requested(const QCommandLineParser &parser);

    LocalTestSession(WsClient *client, Options options, ProductProvider productProvider,
                     QObject *parent = nullptr);
    void start();

  signals:
    void finished();
    void failed(const QString &message);

  private:
    void advance();
    void fail(const QString &reason);
    WsClient *m_client;
    Options m_options;
    ProductProvider m_productProvider;
    QVariantMap m_product;
    QTimer m_timer;
    QElapsedTimer m_elapsed;
    QString m_tournamentId;
    bool m_active = false;
    bool m_started = false;
    bool m_createSent = false;
    bool m_enterSent = false;
    bool m_registerSent = false;
    bool m_checkInSent = false;
    bool m_startSent = false;
    bool m_autoDraftSent = false;
    qint64 m_lastListAt = -1'000;
};

} // namespace hexproof::client
