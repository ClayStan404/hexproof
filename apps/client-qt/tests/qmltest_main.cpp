// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "models/ClientPreferencesModel.h"
#include "models/GameTableModel.h"
#include "models/OptimisticCommandModel.h"
#include "models/SideboardTableModel.h"
#include "services/TranslationController.h"

#include <QQmlContext>
#include <QQmlEngine>
#include <QTemporaryDir>
#include <QVariantList>
#include <QVariantMap>
#include <QtQuickTest>

// Mirrors WsClient::roomList: a Q_PROPERTY(QVariantList) sequence. QML's
// Array.isArray() is false for these, even though .length and indexing work.
class RoomListSequenceStub : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList roomList READ roomList CONSTANT)

  public:
    explicit RoomListSequenceStub(QObject *parent = nullptr)
        : QObject(parent)
    {
        m_rooms.append(QVariantMap{
            {QStringLiteral("roomId"), QStringLiteral("WAIT01")},
            {QStringLiteral("name"), QStringLiteral("Friday Modern")},
            {QStringLiteral("format"), QStringLiteral("modern")},
            {QStringLiteral("phase"), QStringLiteral("waiting")},
            {QStringLiteral("hasPassword"), false},
            {QStringLiteral("playerJoinable"), true},
            {QStringLiteral("spectatorJoinable"), true},
            {QStringLiteral("playerCount"), 1},
            {QStringLiteral("maxSeats"), 2},
        });
    }

    QVariantList roomList() const
    {
        return m_rooms;
    }

  private:
    QVariantList m_rooms;
};

class QmlTestSetup : public QObject
{
    Q_OBJECT

  public slots:
    void qmlEngineAvailable(QQmlEngine *engine)
    {
        auto *translations = new hexproof::client::TranslationController(engine, engine);
        engine->rootContext()->setContextProperty(QStringLiteral("testTranslations"), translations);
        engine->rootContext()->setContextProperty(
            QStringLiteral("preferences"),
            new hexproof::client::ClientPreferencesModel(m_preferencesStorage.path(), engine));
        engine->rootContext()->setContextProperty(QStringLiteral("testRoomList"),
                                                  new RoomListSequenceStub(engine));
        auto *optimisticCommands = new hexproof::client::OptimisticCommandModel(engine);
        engine->rootContext()->setContextProperty(QStringLiteral("testOptimisticCommands"),
                                                  optimisticCommands);
        auto *sideboardTable = new hexproof::client::SideboardTableModel(engine);
        engine->rootContext()->setContextProperty(QStringLiteral("testSideboardTable"),
                                                  sideboardTable);
        auto *gameTable = new hexproof::client::GameTableModel(engine);
        engine->rootContext()->setContextProperty(QStringLiteral("testGameTable"), gameTable);
    }

  private:
    QTemporaryDir m_preferencesStorage;
};

QUICK_TEST_MAIN_WITH_SETUP(hexproof_qml, QmlTestSetup)

#include "qmltest_main.moc"
