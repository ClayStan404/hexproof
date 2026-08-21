// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "protocol/Message.h"
#include "services/ProtocolSession.h"

#include <QJsonObject>
#include <QSet>
#include <QSignalSpy>
#include <QTest>

using namespace Qt::StringLiterals;
using hexproof::client::ProtocolSession;

class TestProtocolSession : public QObject
{
    Q_OBJECT

  private slots:
    void preparesWireWithMonotonicIds() const;
    void queuesAndResolvesSuccess() const;
    void resolvesFailures() const;
    void failsOrDiscardsAllPendingCommands() const;
};

void TestProtocolSession::preparesWireWithMonotonicIds() const
{
    ProtocolSession session;
    const QJsonObject payload{{u"count"_s, 2}};

    const ProtocolSession::OutboundCommand first = session.prepare(u"game.draw"_s, payload);
    const ProtocolSession::OutboundCommand second = session.prepare(u"game.shuffle_library"_s);

    QCOMPARE(first.id, u"1"_s);
    QCOMPARE(second.id, u"2"_s);
    QCOMPARE(session.pendingCount(), 0);

    bool ok = false;
    const hexproof::protocol::Envelope envelope = hexproof::protocol::parse(first.wire, &ok);
    QVERIFY(ok);
    QCOMPARE(envelope.type, first.type);
    QCOMPARE(envelope.id, first.id);
    QCOMPARE(envelope.payload, payload);
}

void TestProtocolSession::queuesAndResolvesSuccess() const
{
    ProtocolSession session;
    QSignalSpy queued(&session, &ProtocolSession::commandQueued);
    QSignalSpy succeeded(&session, &ProtocolSession::commandSucceeded);
    QSignalSpy failed(&session, &ProtocolSession::commandFailed);

    const ProtocolSession::OutboundCommand command = session.prepare(
        u"game.set_tapped"_s, QJsonObject{{u"cardId"_s, u"card-a"_s}, {u"tapped"_s, true}});
    session.markQueued(command);

    QCOMPARE(session.pendingCount(), 1);
    QCOMPARE(queued.count(), 1);
    QCOMPARE(queued.at(0).at(0).toString(), command.id);
    QCOMPARE(queued.at(0).at(1).toString(), command.type);
    QCOMPARE(queued.at(0).at(2).toMap().value(u"cardId"_s).toString(), u"card-a"_s);

    QVERIFY(!session.resolveSuccess(u"unknown"_s));
    QVERIFY(session.resolveSuccess(command.id));
    QVERIFY(!session.resolveSuccess(command.id));
    QCOMPARE(session.pendingCount(), 0);
    QCOMPARE(succeeded.count(), 1);
    QCOMPARE(failed.count(), 0);
}

void TestProtocolSession::resolvesFailures() const
{
    ProtocolSession session;
    QSignalSpy failed(&session, &ProtocolSession::commandFailed);

    const ProtocolSession::OutboundCommand command =
        session.prepare(u"game.set_counter"_s, QJsonObject{{u"counter"_s, u"life"_s}});
    session.markQueued(command);

    QVERIFY(session.resolveFailure(command.id, u"invalid_counter: invalid counter"_s));
    QCOMPARE(session.pendingCount(), 0);
    QCOMPARE(failed.count(), 1);
    QCOMPARE(failed.at(0).at(0).toString(), command.id);
    QCOMPARE(failed.at(0).at(1).toString(), command.type);
    QCOMPARE(failed.at(0).at(2).toMap().value(u"counter"_s).toString(), u"life"_s);
    QCOMPARE(failed.at(0).at(3).toString(), u"invalid_counter: invalid counter"_s);

    session.reportUnqueuedFailure(u"room.create"_s, QJsonObject{{u"name"_s, u"Table"_s}},
                                  u"connection unavailable"_s);
    QCOMPARE(failed.count(), 2);
    QVERIFY(failed.at(1).at(0).toString().isEmpty());
    QCOMPARE(failed.at(1).at(1).toString(), u"room.create"_s);
}

void TestProtocolSession::failsOrDiscardsAllPendingCommands() const
{
    ProtocolSession session;
    QSignalSpy failed(&session, &ProtocolSession::commandFailed);

    const ProtocolSession::OutboundCommand first = session.prepare(u"game.draw"_s);
    const ProtocolSession::OutboundCommand second = session.prepare(u"game.mulligan"_s);
    session.markQueued(first);
    session.markQueued(second);
    session.failAll(u"connection closed"_s);

    QCOMPARE(session.pendingCount(), 0);
    QCOMPARE(failed.count(), 2);
    const QSet<QString> failedIds{
        failed.at(0).at(0).toString(),
        failed.at(1).at(0).toString(),
    };
    QCOMPARE(failedIds.size(), 2);
    QVERIFY(failedIds.contains(first.id));
    QVERIFY(failedIds.contains(second.id));

    const ProtocolSession::OutboundCommand discarded = session.prepare(u"room.list"_s);
    session.markQueued(discarded);
    session.discardAll();
    QCOMPARE(session.pendingCount(), 0);
    QCOMPARE(failed.count(), 3);
    QCOMPARE(failed.at(2).at(0).toString(), discarded.id);
    QCOMPARE(failed.at(2).at(1).toString(), discarded.type);
    QCOMPARE(failed.at(2).at(3).toString(),
             u"room session ended before the server replied"_s);

    const ProtocolSession::OutboundCommand next = session.prepare(u"replay.list"_s);
    QCOMPARE(next.id, u"4"_s);
}

QTEST_MAIN(TestProtocolSession)
#include "protocolsession_test.moc"
