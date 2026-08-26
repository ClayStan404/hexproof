// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "protocol/Message.h"

#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTest>

using namespace Qt::StringLiterals;
using hexproof::protocol::Envelope;
using hexproof::protocol::parse;
using hexproof::protocol::serialize;

// P0 protocol unit tests (C++ side). Mirrors the Go-side guarantees:
//   - session.hello carries no top-level `v`
//   - session.welcome carries `v` ONLY in its payload
//   - post-welcome messages parse without `v`
//   - id correlation round-trips
class TestProtocol : public QObject
{
    Q_OBJECT

  private slots:
    void helloRoundTrip() const;
    void helloHasNoTopLevelV() const;
    void welcomeCarriesVOnlyInPayload() const;
    void postWelcomeParsesWithoutV() const;
    void errorRoundTrip() const;
    void parseRejectsGarbage() const;
    void parseRejectsMissingType() const;
    void parsesSharedGoldenFixtures() const;
};

void TestProtocol::helloRoundTrip() const
{
    Envelope env;
    env.type = hexproof::protocol::kTypeSessionHello;
    env.id = u"req-1"_s;
    env.payload = QJsonObject{
        {u"displayName"_s, u"Alice"_s},
        {u"clientVersion"_s, u"0.1.0"_s},
        {u"protocol"_s, hexproof::protocol::kProtocolVersion},
    };

    const QByteArray data = serialize(env);
    bool ok = false;
    const Envelope got = parse(data, &ok);
    QVERIFY(ok);
    QCOMPARE(got.type, hexproof::protocol::kTypeSessionHello);
    QCOMPARE(got.id, u"req-1"_s);
    QCOMPARE(got.payload.value(u"displayName"_s).toString(), u"Alice"_s);
}

void TestProtocol::helloHasNoTopLevelV() const
{
    Envelope env;
    env.type = hexproof::protocol::kTypeSessionHello;
    env.payload = QJsonObject{{u"protocol"_s, hexproof::protocol::kProtocolVersion}};

    const QByteArray data = serialize(env);
    QVERIFY(!QJsonDocument::fromJson(data).object().contains(u"v"_s));
}

void TestProtocol::welcomeCarriesVOnlyInPayload() const
{
    Envelope env;
    env.type = hexproof::protocol::kTypeSessionWelcome;
    env.id = u"req-1"_s;
    env.payload = QJsonObject{
        {u"v"_s, hexproof::protocol::kProtocolVersion},
        {u"connectionId"_s, u"conn-7F3A"_s},
        {u"serverVersion"_s, u"0.1.0"_s},
    };

    const QByteArray data = serialize(env);
    const QJsonObject top = QJsonDocument::fromJson(data).object();
    QVERIFY(!top.contains(u"v"_s)); // no top-level v
    QCOMPARE(top.value(u"payload"_s).toObject().value(u"v"_s).toString(),
             hexproof::protocol::kProtocolVersion);

    bool ok = false;
    const Envelope got = parse(data, &ok);
    QVERIFY(ok);
    QVERIFY(!got.hasSeq);
}

void TestProtocol::postWelcomeParsesWithoutV() const
{
    const QByteArray raw =
        R"({"type":"room.create","id":"c1","payload":{"name":"Friday EDH","format":"edh","maxSeats":4}})";
    bool ok = false;
    const Envelope env = parse(raw, &ok);
    QVERIFY(ok);
    QCOMPARE(env.type, u"room.create"_s);
    QCOMPARE(env.id, u"c1"_s);
    QCOMPARE(env.payload.value(u"maxSeats"_s).toInt(), 4);
}

void TestProtocol::errorRoundTrip() const
{
    Envelope env;
    env.type = u"error"_s;
    env.id = u"req-9"_s;
    env.payload = QJsonObject{
        {u"code"_s, u"room_full"_s},
        {u"message"_s, u"All seats are taken"_s},
    };

    const QByteArray data = serialize(env);
    bool ok = false;
    const Envelope got = parse(data, &ok);
    QVERIFY(ok);
    QCOMPARE(got.type, u"error"_s);
    QCOMPARE(got.id, u"req-9"_s); // id correlation echo
    QCOMPARE(got.payload.value(u"code"_s).toString(), u"room_full"_s);
}

void TestProtocol::parseRejectsGarbage() const
{
    bool ok = true;
    const Envelope env = parse("{not json", &ok);
    QVERIFY(!ok);
    QVERIFY(env.type.isEmpty());
}

void TestProtocol::parseRejectsMissingType() const
{
    bool ok = true;
    const Envelope env = parse(R"({"payload":{}})", &ok);
    QVERIFY(!ok);
    QVERIFY(env.type.isEmpty());
}

void TestProtocol::parsesSharedGoldenFixtures() const
{
    const QDir fixtures(QStringLiteral(HEXPROOF_PROTOCOL_FIXTURE_DIR));
    const QStringList files = fixtures.entryList({u"*.json"_s}, QDir::Files, QDir::Name);
    QVERIFY2(!files.isEmpty(), qPrintable(fixtures.absolutePath()));
    for (const QString &name : files) {
        QFile file(fixtures.filePath(name));
        QVERIFY2(file.open(QIODevice::ReadOnly), qPrintable(name));
        const QByteArray bytes = file.readAll();
        QJsonParseError jsonError;
        const QJsonDocument document = QJsonDocument::fromJson(bytes, &jsonError);
        QVERIFY2(jsonError.error == QJsonParseError::NoError && document.isObject(),
                 qPrintable(name + u": "_s + jsonError.errorString()));
        const QJsonObject top = document.object();
        QVERIFY2(!top.contains(u"v"_s), qPrintable(name));

        bool ok = false;
        const Envelope envelope = parse(bytes, &ok);
        QVERIFY2(ok, qPrintable(name));
        QCOMPARE(envelope.type, top.value(u"type"_s).toString());
        QCOMPARE(envelope.id, top.value(u"id"_s).toString());
        QCOMPARE(envelope.hasSeq, top.value(u"seq"_s).isDouble());
        if (envelope.hasSeq)
            QCOMPARE(envelope.seq, top.value(u"seq"_s).toInteger());

        bool roundTripOk = false;
        const Envelope roundTrip = parse(serialize(envelope), &roundTripOk);
        QVERIFY2(roundTripOk, qPrintable(name));
        QCOMPARE(roundTrip.type, envelope.type);
        QCOMPARE(roundTrip.id, envelope.id);
        QCOMPARE(roundTrip.payload, envelope.payload);
    }
}

QTEST_GUILESS_MAIN(TestProtocol)
#include "protocol_test.moc"
