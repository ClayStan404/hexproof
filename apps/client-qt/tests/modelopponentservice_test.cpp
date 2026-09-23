// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/ModelOpponentService.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QPointer>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QTest>
#include <QUrlQuery>
#include <QtWebSockets/QWebSocket>
#include <QtWebSockets/QWebSocketServer>
#include <functional>

using namespace hexproof::client;
using namespace Qt::StringLiterals;

namespace {
QByteArray json(const QJsonObject &value)
{
    return QJsonDocument(value).toJson(QJsonDocument::Compact);
}
QJsonObject answer(int promptId = 7, const QString &response = u"action:play"_s)
{
    return {{u"promptId"_s, promptId}, {u"responseId"_s, response}};
}
QByteArray completion(const QByteArray &content)
{
    return json(
        {{u"choices"_s, QJsonArray{QJsonObject{
                            {u"message"_s, QJsonObject{{u"role"_s, u"assistant"_s},
                                                       {u"content"_s, QString::fromUtf8(content)}}},
                            {u"finish_reason"_s, u"stop"_s}}}}});
}
QJsonObject decision(const QString &request = u"request-1"_s, const QString &game = u"game-1"_s)
{
    return {{u"requestId"_s, request},
            {u"gameId"_s, game},
            {u"seatIndex"_s, 1},
            {u"prompt"_s,
             QJsonObject{{u"roomId"_s, u"room-1"_s},
                         {u"gameId"_s, game},
                         {u"pending"_s, true},
                         {u"supported"_s, true},
                         {u"promptId"_s, 7},
                         {u"kind"_s, u"chooseAction"_s},
                         {u"options"_s, QJsonArray{QJsonObject{{u"responseId"_s, u"action:play"_s},
                                                               {u"kind"_s, u"play"_s},
                                                               {u"label"_s, u"Play a land"_s}}}}}},
            {u"snapshot"_s, QJsonObject{{u"roomId"_s, u"room-1"_s},
                                        {u"gameId"_s, game},
                                        {u"turn"_s, 1},
                                        {u"step"_s, u"main1"_s},
                                        {u"zones"_s, QJsonArray{}}}}};
}

class HttpFixture : public QObject
{
  public:
    struct Request
    {
        QByteArray headers;
        QJsonObject body;
        QPointer<QTcpSocket> socket;
    };
    QTcpServer server;
    QList<Request> requests;
    std::function<void(const Request &)> handler;
    HttpFixture()
    {
        server.listen(QHostAddress::LocalHost, 0);
        connect(&server, &QTcpServer::newConnection, this, [this]() {
            while (server.hasPendingConnections()) {
                auto *socket = server.nextPendingConnection();
                connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
                connect(socket, &QTcpSocket::readyRead, this, [this, socket]() {
                    auto bytes = socket->property("buffer").toByteArray() + socket->readAll();
                    socket->setProperty("buffer", bytes);
                    const qsizetype boundary = bytes.indexOf("\r\n\r\n");
                    if (boundary < 0 || socket->property("handled").toBool())
                        return;
                    const auto headers = bytes.left(boundary);
                    int length = 0;
                    for (const auto &line : headers.split('\n'))
                        if (line.toLower().startsWith("content-length:"))
                            length = line.mid(15).trimmed().toInt();
                    if (bytes.size() < boundary + 4 + length)
                        return;
                    socket->setProperty("handled", true);
                    requests.append(
                        {headers, QJsonDocument::fromJson(bytes.mid(boundary + 4, length)).object(),
                         socket});
                    if (handler)
                        handler(requests.last());
                });
            }
        });
    }
    QString endpoint() const
    {
        return u"http://127.0.0.1:%1/v1"_s.arg(server.serverPort());
    }
    static void respond(const Request &request, const QByteArray &body, int status = 200,
                        const QByteArray &extraHeaders = {})
    {
        if (!request.socket)
            return;
        request.socket->write("HTTP/1.1 " + QByteArray::number(status) +
                              " Result\r\nContent-Type: application/json\r\nContent-Length: " +
                              QByteArray::number(body.size()) + "\r\nConnection: close\r\n" +
                              extraHeaders + "\r\n" + body);
        request.socket->disconnectFromHost();
    }
    void validResponses()
    {
        handler = [](const Request &request) {
            const auto messages = request.body.value(u"messages"_s).toArray();
            const auto input =
                QJsonDocument::fromJson(
                    messages.last().toObject().value(u"content"_s).toString().toUtf8())
                    .object();
            const auto prompt = input.value(u"prompt"_s).toObject();
            const auto options = prompt.value(u"options"_s).toArray();
            const auto result =
                answer(prompt.value(u"promptId"_s).toInt(),
                       options.first().toObject().value(u"responseId"_s).toString());
            respond(request, completion(json(result)));
        };
    }
};

class WorkerFixture : public QObject
{
  public:
    QWebSocketServer server{u"Model worker fixture"_s, QWebSocketServer::NonSecureMode};
    QPointer<QWebSocket> socket;
    QList<QJsonObject> messages;
    QUrl requestUrl;
    WorkerFixture()
    {
        server.listen(QHostAddress::LocalHost, 0);
        connect(&server, &QWebSocketServer::newConnection, this, [this]() {
            auto *peer = server.nextPendingConnection();
            socket = peer;
            requestUrl = peer->requestUrl();
            connect(peer, &QWebSocket::disconnected, peer, &QObject::deleteLater);
            connect(peer, &QWebSocket::textMessageReceived, this, [this](const QString &text) {
                const auto message = QJsonDocument::fromJson(text.toUtf8()).object();
                messages.append(message);
                if (message.value(u"type"_s).toString() == u"ai.attach"_s)
                    send(u"ai.attached"_s, {{u"roomId"_s, u"room-1"_s}});
            });
        });
    }
    ~WorkerFixture() override
    {
        if (socket) {
            socket->disconnect(this);
            socket->abort();
        }
    }
    QString url() const
    {
        return u"ws://127.0.0.1:%1/proxy/ws?existing=value&engine=1"_s.arg(server.serverPort());
    }
    QJsonObject grant(const QString &source = u"local"_s) const
    {
        return {{u"roomId"_s, u"room-1"_s}, {u"source"_s, source}, {u"token"_s, QString(64, u'a')}};
    }
    void send(const QString &type, const QJsonObject &payload)
    {
        if (socket)
            socket->sendTextMessage(
                QString::fromUtf8(json({{u"type"_s, type}, {u"payload"_s, payload}})));
    }
    int count(const QString &type) const
    {
        int result = 0;
        for (const auto &message : messages)
            result += message.value(u"type"_s).toString() == type;
        return result;
    }
    QJsonObject last(const QString &type) const
    {
        for (auto it = messages.crbegin(); it != messages.crend(); ++it)
            if (it->value(u"type"_s).toString() == type)
                return it->value(u"payload"_s).toObject();
        return {};
    }
};

bool configure(ModelOpponentService &service, HttpFixture &http, const QVariantMap &extra = {},
               const QString &key = u"session-secret"_s)
{
    auto value = service.profile(u"local"_s);
    value[u"endpoint"_s] = http.endpoint();
    value[u"model"_s] = u"test-model"_s;
    for (auto it = extra.cbegin(); it != extra.cend(); ++it)
        value[it.key()] = it.value();
    return service.saveProfile(u"local"_s, value, key);
}

class CatalogFixture : public QObject
{
    Q_OBJECT
  public:
    mutable QVariantList lookedUp;
    Q_INVOKABLE QVariantList enrichLimitedCards(const QVariantList &cards) const
    {
        lookedUp = cards;
        auto result = cards;
        for (auto &value : result) {
            auto card = value.toMap();
            card[u"oracleText"_s] = u"Visible oracle text"_s;
            card[u"privateExtra"_s] = u"CATALOG_PRIVATE_SENTINEL"_s;
            value = card;
        }
        result.append(QVariantMap{{u"name"_s, u"Unrequested card"_s},
                                  {u"oracleText"_s, u"UNREQUESTED_SENTINEL"_s}});
        return result;
    }
};
} // namespace

class ModelOpponentServiceTest : public QObject
{
    Q_OBJECT
  private slots:
    void profilesPersistWithoutSecrets();
    void syntheticTestRequiresEnumeratedDecision();
    void attachesOnlyArmedSourceAndKeepsProxyRoute();
    void repairsOnceAndStopsAfterHubRejection();
    void oneHubRepairCanSucceed();
    void staleRequestsAndDisconnectAreCancelled();
    void budgetsSurviveRetryAndReconnect();
    void tokenBudgetIsReservedBeforeFirstCall();
    void errorsAreSafeAndRedirectsAreBlocked_data();
    void errorsAreSafeAndRedirectsAreBlocked();
    void responseAndPromptAreBounded();
    void onlySeatVisibleDataAndRequestedOracleReachProvider();
    void meaningfulSingleOptionUsesModelAndForcedPassDoesNot();
    void structuredChoicesUseTypedResponse();
    void openingChoiceCannotUseCandidateAsTopLevelResponse();
    void timeoutCancelsReply();
    void newGrantReplacesInflightRequest();
    void explicitCancelOptionIsAccepted();
    void scryRequiresEveryDestinationInOrder();
    void cardChoicesRejectReadOnlyDisclosures();
};

void ModelOpponentServiceTest::profilesPersistWithoutSecrets()
{
    QTemporaryDir dir;
    HttpFixture http;
    const auto path = dir.filePath(u"profiles.json"_s);
    ModelOpponentService service(path);
    QVERIFY(!service.configured(u"local"_s));
    QCOMPARE(service.profile(u"local"_s).value(u"timeoutSeconds"_s).toInt(), 60);
    QVERIFY(configure(service, http, {{u"unknownSecret"_s, u"EXTRA_SECRET"_s}}));
    QVERIFY(service.profile(u"local"_s).value(u"hasKey"_s).toBool());
    QFile file(path);
    QVERIFY(file.open(QIODevice::ReadOnly));
    const auto stored = file.readAll();
    QVERIFY(!stored.contains("session-secret"));
    QVERIFY(!stored.contains("EXTRA_SECRET"));
    QVERIFY(!stored.contains("hasKey"));
    ModelOpponentService reloaded(path);
    QVERIFY(reloaded.configured(u"local"_s));
    QVERIFY(!reloaded.profile(u"local"_s).value(u"hasKey"_s).toBool());
    auto online = service.profile(u"online"_s);
    online[u"model"_s] = u"online-test"_s;
    online[u"endpoint"_s] = http.endpoint();
    QVERIFY(!service.saveProfile(u"online"_s, online, {}));
    online[u"endpoint"_s] = u"https://provider.example/v1"_s;
    QVERIFY(service.saveProfile(u"online"_s, online, u"memory-only"_s));
    QCOMPARE(service.profile(u"online"_s).value(u"tokenParameter"_s).toString(),
             u"max_completion_tokens"_s);
    QVERIFY(service.saveProfile(u"online"_s, online, {}));
    QVERIFY(!service.profile(u"online"_s).value(u"hasKey"_s).toBool());
    online[u"endpoint"_s] = u"https://secret@provider.example/v1"_s;
    QVERIFY(!service.saveProfile(u"online"_s, online, {}));
}

void ModelOpponentServiceTest::syntheticTestRequiresEnumeratedDecision()
{
    QTemporaryDir dir;
    HttpFixture http;
    ModelOpponentService service(dir.filePath(u"profiles.json"_s));
    QVERIFY(configure(service, http));
    http.handler = [](const HttpFixture::Request &request) {
        HttpFixture::respond(request, completion(json(answer(1, u"invented"_s))));
    };
    service.testProfile(u"local"_s);
    QTRY_COMPARE(service.testStatus(), u"invalid_response"_s);
    QCOMPARE(http.requests.size(), 2);
    QCOMPARE(service.lastError(), u"invalid_response"_s);
    http.validResponses();
    service.testProfile(u"local"_s);
    QTRY_COMPARE(service.testStatus(), u"passed"_s);
    QVERIFY(service.lastError().isEmpty());
    const auto request = http.requests.last();
    QVERIFY(request.headers.startsWith("POST /v1/chat/completions HTTP/1.1"));
    QVERIFY(request.headers.contains("Authorization: Bearer session-secret"));
    QVERIFY(!json(request.body).contains("session-secret"));
    QCOMPARE(request.body.value(u"max_tokens"_s).toInt(), 1024);
    QVERIFY(!request.body.contains(u"tools"_s));
    QVERIFY(!request.body.value(u"stream"_s).toBool());
}

void ModelOpponentServiceTest::attachesOnlyArmedSourceAndKeepsProxyRoute()
{
    QTemporaryDir dir;
    HttpFixture http;
    WorkerFixture worker;
    ModelOpponentService service(dir.filePath(u"profiles.json"_s));
    QVERIFY(configure(service, http));
    service.start(worker.url(), worker.grant());
    QCOMPARE(service.status(), u"invalid_config"_s);
    QVERIFY(service.arm(u"local"_s));
    service.start(worker.url(), worker.grant(u"online"_s));
    QCOMPARE(service.status(), u"invalid_config"_s);
    QCOMPARE(worker.messages.size(), 0);
    service.start(worker.url(), worker.grant());
    QTRY_VERIFY(service.active());
    QCOMPARE(worker.requestUrl.path(), u"/proxy/ws"_s);
    const QUrlQuery query(worker.requestUrl);
    QCOMPARE(query.queryItemValue(u"existing"_s), u"value"_s);
    QCOMPARE(query.queryItemValue(u"ai"_s), u"1"_s);
    QVERIFY(!query.hasQueryItem(u"engine"_s));
    QCOMPARE(worker.count(u"ai.attach"_s), 1);
    QCOMPARE(worker.messages.first().value(u"payload"_s).toObject().size(), 2);
    QVERIFY(!configure(service, http));
    service.stop();
    QVERIFY(!service.active());
    QVERIFY(service.armedSource().isEmpty());
}

void ModelOpponentServiceTest::repairsOnceAndStopsAfterHubRejection()
{
    QTemporaryDir dir;
    HttpFixture http;
    WorkerFixture worker;
    ModelOpponentService service(dir.filePath(u"profiles.json"_s));
    QVERIFY(configure(service, http));
    int attempt = 0;
    http.handler = [&attempt](const HttpFixture::Request &request) {
        HttpFixture::respond(request,
                             completion(++attempt == 1 ? QByteArray("not json") : json(answer())));
    };
    QVERIFY(service.arm(u"local"_s));
    service.start(worker.url(), worker.grant());
    QTRY_VERIFY(service.active());
    worker.send(u"ai.decision"_s, decision());
    QTRY_COMPARE(worker.count(u"ai.answer"_s), 1);
    QCOMPARE(http.requests.size(), 2);
    QVERIFY(!service.busy());
    const auto timers = service.findChildren<QTimer *>();
    for (auto *timer : timers)
        QVERIFY(!timer->isActive());
    worker.send(u"ai.rejected"_s,
                {{u"requestId"_s, u"request-1"_s}, {u"code"_s, u"invalid_response"_s}});
    QTRY_COMPARE(worker.count(u"ai.failure"_s), 1);
    QCOMPARE(service.failureCode(), u"invalid_response"_s);
    QCOMPARE(http.requests.size(), 2);
    QCOMPARE(service.callsUsed(), 2);
}

void ModelOpponentServiceTest::oneHubRepairCanSucceed()
{
    QTemporaryDir dir;
    HttpFixture http;
    http.validResponses();
    WorkerFixture worker;
    ModelOpponentService service(dir.filePath(u"profiles.json"_s));
    QVERIFY(configure(service, http));
    QVERIFY(service.arm(u"local"_s));
    service.start(worker.url(), worker.grant());
    QTRY_VERIFY(service.active());
    worker.send(u"ai.decision"_s, decision());
    QTRY_COMPARE(worker.count(u"ai.answer"_s), 1);
    worker.send(u"ai.rejected"_s,
                {{u"requestId"_s, u"request-1"_s}, {u"code"_s, u"invalid_response"_s}});
    QTRY_COMPARE(worker.count(u"ai.answer"_s), 2);
    QCOMPARE(http.requests.size(), 2);
    worker.send(u"ai.cancel"_s, {{u"requestId"_s, u"request-1"_s}});
    QTRY_COMPARE(service.status(), u"ready"_s);
    worker.send(u"ai.rejected"_s, {{u"requestId"_s, u"request-1"_s}});
    QTest::qWait(20);
    QCOMPARE(http.requests.size(), 2);
    QCOMPARE(worker.count(u"ai.failure"_s), 0);
}

void ModelOpponentServiceTest::staleRequestsAndDisconnectAreCancelled()
{
    QTemporaryDir dir;
    HttpFixture http;
    WorkerFixture worker;
    ModelOpponentService service(dir.filePath(u"profiles.json"_s));
    QVERIFY(configure(service, http));
    QVERIFY(service.arm(u"local"_s));
    service.start(worker.url(), worker.grant());
    QTRY_VERIFY(service.active());
    worker.send(u"ai.decision"_s, decision());
    QTRY_COMPARE(http.requests.size(), 1);
    worker.send(u"ai.decision"_s, decision());
    QTest::qWait(20);
    QCOMPARE(http.requests.size(), 1);
    const auto cancelled = http.requests.first();
    worker.send(u"ai.cancel"_s, {{u"requestId"_s, u"request-1"_s}});
    QTRY_VERIFY(!service.busy());
    HttpFixture::respond(cancelled, completion(json(answer())));
    http.validResponses();
    worker.send(u"ai.decision"_s, decision(u"request-2"_s));
    QTRY_COMPARE(worker.count(u"ai.answer"_s), 1);
    QCOMPARE(worker.last(u"ai.answer"_s).value(u"requestId"_s).toString(), u"request-2"_s);
    http.handler = {};
    worker.send(u"ai.decision"_s, decision(u"request-3"_s));
    QTRY_COMPARE(http.requests.size(), 3);
    const auto stopped = http.requests.last();
    service.stop();
    HttpFixture::respond(stopped, completion(json(answer())));
    QTest::qWait(20);
    QCOMPARE(worker.count(u"ai.answer"_s), 1);
    QCOMPARE(service.callsUsed(), 3);
}

void ModelOpponentServiceTest::budgetsSurviveRetryAndReconnect()
{
    QTemporaryDir dir;
    HttpFixture http;
    http.validResponses();
    WorkerFixture worker;
    ModelOpponentService service(dir.filePath(u"profiles.json"_s));
    QVERIFY(configure(service, http, {{u"maxCalls"_s, 1}}));
    QVERIFY(service.arm(u"local"_s));
    service.start(worker.url(), worker.grant());
    QTRY_VERIFY(service.active());
    worker.send(u"ai.decision"_s, decision());
    QTRY_COMPARE(worker.count(u"ai.answer"_s), 1);
    const auto reserved = service.reservedTokens();
    QVERIFY(reserved > 1024);
    service.stop();
    QVERIFY(service.arm(u"local"_s));
    service.start(worker.url(), worker.grant());
    QTRY_VERIFY(service.active());
    worker.send(u"ai.decision"_s, decision(u"retry"_s));
    QTRY_COMPARE(worker.count(u"ai.failure"_s), 1);
    QCOMPARE(service.failureCode(), u"budget_exhausted"_s);
    QCOMPARE(http.requests.size(), 1);
    QCOMPARE(service.reservedTokens(), reserved);
    worker.send(u"ai.decision"_s, decision(u"new-game"_s, u"game-2"_s));
    QTRY_COMPARE(worker.count(u"ai.answer"_s), 2);
    QCOMPARE(service.callsUsed(), 1);
}

void ModelOpponentServiceTest::tokenBudgetIsReservedBeforeFirstCall()
{
    QTemporaryDir dir;
    HttpFixture http;
    ModelOpponentService service(dir.filePath(u"profiles.json"_s));
    QVERIFY(configure(service, http, {{u"maxTokenBudget"_s, 1024}}));
    service.testProfile(u"local"_s);
    QCOMPARE(service.testStatus(), u"budget_exhausted"_s);
    QCOMPARE(http.requests.size(), 0);
    QCOMPARE(service.callsUsed(), 0);
}

void ModelOpponentServiceTest::errorsAreSafeAndRedirectsAreBlocked_data()
{
    QTest::addColumn<int>("httpStatus");
    QTest::addColumn<QString>("expected");
    QTest::newRow("unauthorized") << 401 << u"authentication_failed"_s;
    QTest::newRow("forbidden") << 403 << u"authentication_failed"_s;
    QTest::newRow("missing-model") << 404 << u"endpoint_or_model_not_found"_s;
    QTest::newRow("rate-limit") << 429 << u"rate_limited"_s;
    QTest::newRow("provider") << 500 << u"provider_error"_s;
    QTest::newRow("redirect") << 302 << u"redirect_blocked"_s;
}

void ModelOpponentServiceTest::errorsAreSafeAndRedirectsAreBlocked()
{
    QFETCH(int, httpStatus);
    QFETCH(QString, expected);
    QTemporaryDir dir;
    HttpFixture http;
    HttpFixture redirectTarget;
    ModelOpponentService service(dir.filePath(u"profiles.json"_s));
    QVERIFY(configure(service, http));
    http.handler = [&](const HttpFixture::Request &request) {
        HttpFixture::respond(request, "RAW_SECRET_PROVIDER_ERROR", httpStatus,
                             "Location: " + redirectTarget.endpoint().toUtf8() + "\r\n");
    };
    service.testProfile(u"local"_s);
    QTRY_COMPARE(service.lastError(), expected);
    QCOMPARE(service.testStatus(), expected);
    QCOMPARE(service.failureCode(), u"provider_error"_s);
    QCOMPARE(http.requests.size(), 1);
    QCOMPARE(redirectTarget.requests.size(), 0);
}

void ModelOpponentServiceTest::responseAndPromptAreBounded()
{
    QTemporaryDir dir;
    HttpFixture http;
    WorkerFixture worker;
    ModelOpponentService service(dir.filePath(u"profiles.json"_s));
    QVERIFY(configure(service, http));
    http.handler = [](const HttpFixture::Request &request) {
        HttpFixture::respond(request, QByteArray(1024 * 1024 + 1, 'x'));
    };
    service.testProfile(u"local"_s);
    QTRY_COMPARE(service.lastError(), u"response_too_large"_s);
    QCOMPARE(http.requests.size(), 1);
    QVERIFY(service.arm(u"local"_s));
    service.start(worker.url(), worker.grant());
    QTRY_VERIFY(service.active());
    auto large = decision();
    auto prompt = large.value(u"prompt"_s).toObject();
    prompt[u"detail"_s] = QString(128 * 1024, u'x');
    large[u"prompt"_s] = prompt;
    worker.send(u"ai.decision"_s, large);
    QTRY_COMPARE(worker.count(u"ai.failure"_s), 1);
    QCOMPARE(service.failureCode(), u"unsupported_prompt"_s);
    QCOMPARE(http.requests.size(), 1);
}

void ModelOpponentServiceTest::onlySeatVisibleDataAndRequestedOracleReachProvider()
{
    QTemporaryDir dir;
    HttpFixture http;
    http.validResponses();
    WorkerFixture worker;
    CatalogFixture catalog;
    ModelOpponentService service(dir.filePath(u"profiles.json"_s));
    service.setCardCatalog(&catalog);
    QVERIFY(configure(service, http));
    QVERIFY(service.arm(u"local"_s));
    service.start(worker.url(), worker.grant());
    QTRY_VERIFY(service.active());
    auto value = decision();
    const QJsonObject visibleIdentity{
        {u"name"_s, u"Visible card"_s}, {u"setCode"_s, u"TST"_s}, {u"collectorNumber"_s, u"1"_s}};
    auto snapshot = value.value(u"snapshot"_s).toObject();
    snapshot[u"chat"_s] = u"CHAT_SENTINEL"_s;
    snapshot[u"hostBundle"_s] = u"BUNDLE_SENTINEL"_s;
    snapshot[u"zones"_s] = QJsonArray{QJsonObject{
        {u"zone"_s, u"hand"_s},
        {u"ownerSeat"_s, 1},
        {u"cards"_s,
         QJsonArray{
             QJsonObject{
                 {u"id"_s, u"visible"_s}, {u"visible"_s, true}, {u"identity"_s, visibleIdentity}},
             QJsonObject{{u"id"_s, u"hidden"_s},
                         {u"visible"_s, false},
                         {u"identity"_s, QJsonObject{{u"name"_s, u"HIDDEN_SENTINEL"_s}}}}}}}};
    value[u"snapshot"_s] = snapshot;
    auto prompt = value.value(u"prompt"_s).toObject();
    prompt[u"chat"_s] = u"PROMPT_CHAT_SENTINEL"_s;
    prompt[u"contextCards"_s] = QJsonArray{QJsonObject{{u"id"_s, u"context:1"_s},
                                                       {u"name"_s, u"Candidate"_s},
                                                       {u"setCode"_s, u"TST"_s},
                                                       {u"collectorNumber"_s, u"2"_s}}};
    value[u"prompt"_s] = prompt;
    worker.send(u"ai.decision"_s, value);
    QTRY_COMPARE(worker.count(u"ai.answer"_s), 1);
    const auto bytes = json(http.requests.last().body);
    QVERIFY(bytes.contains("Visible oracle text"));
    QVERIFY(bytes.contains("Candidate"));
    QVERIFY(!bytes.contains("SENTINEL"));
    QVERIFY(!bytes.contains("room-1"));
    QVERIFY(!bytes.contains("game-1"));
    QVERIFY(!bytes.contains("session-secret"));
    QVERIFY(!bytes.contains(QString(64, u'a').toUtf8()));
    QCOMPARE(catalog.lookedUp.size(), 2);
}

void ModelOpponentServiceTest::meaningfulSingleOptionUsesModelAndForcedPassDoesNot()
{
    QTemporaryDir dir;
    HttpFixture http;
    http.validResponses();
    WorkerFixture worker;
    ModelOpponentService service(dir.filePath(u"profiles.json"_s));
    QVERIFY(configure(service, http));
    QVERIFY(service.arm(u"local"_s));
    service.start(worker.url(), worker.grant());
    QTRY_VERIFY(service.active());
    worker.send(u"ai.decision"_s, decision());
    QTRY_COMPARE(worker.count(u"ai.answer"_s), 1);
    QCOMPARE(http.requests.size(), 1);
    auto forced = decision(u"forced"_s);
    auto prompt = forced.value(u"prompt"_s).toObject();
    prompt[u"autoPassEligible"_s] = true;
    prompt[u"options"_s] =
        QJsonArray{QJsonObject{{u"responseId"_s, u"$pass"_s}, {u"kind"_s, u"pass"_s}},
                   QJsonObject{{u"responseId"_s, u"$pass-stack"_s}, {u"kind"_s, u"pass"_s}}};
    forced[u"prompt"_s] = prompt;
    worker.send(u"ai.decision"_s, forced);
    QTRY_COMPARE(worker.count(u"ai.answer"_s), 2);
    QCOMPARE(http.requests.size(), 1);
    QCOMPARE(worker.last(u"ai.answer"_s)
                 .value(u"response"_s)
                 .toObject()
                 .value(u"responseId"_s)
                 .toString(),
             u"$pass"_s);
}

void ModelOpponentServiceTest::structuredChoicesUseTypedResponse()
{
    QTemporaryDir dir;
    HttpFixture http;
    WorkerFixture worker;
    ModelOpponentService service(dir.filePath(u"profiles.json"_s));
    QVERIFY(configure(service, http));
    int attempts = 0;
    http.handler = [&attempts](const HttpFixture::Request &request) {
        auto result = answer(7, u"$submit"_s);
        result[u"choiceIds"_s] = QJsonArray{++attempts == 1 ? u"invented"_s : u"choice:yes"_s};
        HttpFixture::respond(request, completion(json(result)));
    };
    QVERIFY(service.arm(u"local"_s));
    service.start(worker.url(), worker.grant());
    QTRY_VERIFY(service.active());
    auto value = decision();
    auto prompt = value.value(u"prompt"_s).toObject();
    prompt[u"kind"_s] = u"chooseBoolean"_s;
    prompt[u"options"_s] = QJsonArray{};
    prompt[u"choices"_s] = QJsonArray{
        QJsonObject{{u"responseId"_s, u"choice:yes"_s}, {u"weight"_s, 1}, {u"canRepeat"_s, false}}};
    prompt[u"minChoiceTotal"_s] = 1;
    prompt[u"maxChoiceTotal"_s] = 1;
    value[u"prompt"_s] = prompt;
    worker.send(u"ai.decision"_s, value);
    QTRY_COMPARE(worker.count(u"ai.answer"_s), 1);
    QCOMPARE(http.requests.size(), 2);
    QCOMPARE(
        worker.last(u"ai.answer"_s).value(u"response"_s).toObject().value(u"choiceIds"_s).toArray(),
        QJsonArray{u"choice:yes"_s});
}

void ModelOpponentServiceTest::openingChoiceCannotUseCandidateAsTopLevelResponse()
{
    QTemporaryDir dir;
    HttpFixture http;
    WorkerFixture worker;
    ModelOpponentService service(dir.filePath(u"profiles.json"_s));
    QVERIFY(configure(service, http));
    int attempts = 0;
    http.handler = [&attempts](const HttpFixture::Request &request) {
        // Reproduce the real provider's syntactically valid but structurally
        // invalid opening-choice response; only the repaired shape may reach Forge.
        auto result = answer(1, ++attempts == 1 ? u"choice:1"_s : u"$submit"_s);
        if (attempts > 1)
            result[u"choiceIds"_s] = QJsonArray{u"choice:1"_s};
        HttpFixture::respond(request, completion(json(result)));
    };
    QVERIFY(service.arm(u"local"_s));
    service.start(worker.url(), worker.grant());
    QTRY_VERIFY(service.active());
    auto value = decision();
    auto prompt = value.value(u"prompt"_s).toObject();
    prompt[u"promptId"_s] = 1;
    prompt[u"kind"_s] = u"chooseBoolean"_s;
    prompt[u"options"_s] = QJsonArray{};
    prompt[u"choices"_s] = QJsonArray{QJsonObject{{u"responseId"_s, u"choice:0"_s},
                                                  {u"label"_s, u"Draw"_s},
                                                  {u"weight"_s, 1},
                                                  {u"canRepeat"_s, false}},
                                      QJsonObject{{u"responseId"_s, u"choice:1"_s},
                                                  {u"label"_s, u"Play"_s},
                                                  {u"weight"_s, 1},
                                                  {u"canRepeat"_s, false}}};
    prompt[u"minChoiceTotal"_s] = 1;
    prompt[u"maxChoiceTotal"_s] = 1;
    value[u"prompt"_s] = prompt;
    worker.send(u"ai.decision"_s, value);
    QTRY_COMPARE(worker.count(u"ai.answer"_s), 1);
    QCOMPARE(http.requests.size(), 2);
    const auto forwarded = worker.last(u"ai.answer"_s).value(u"response"_s).toObject();
    QCOMPARE(forwarded, QJsonObject({{u"promptId"_s, 1},
                                     {u"responseId"_s, u"$submit"_s},
                                     {u"choiceIds"_s, QJsonArray{u"choice:1"_s}}}));
    const auto messages = http.requests.first().body.value(u"messages"_s).toArray();
    const auto system = messages.first().toObject().value(u"content"_s).toString();
    const auto contract =
        QJsonDocument::fromJson(system.mid(system.indexOf(u'\n') + 1).toUtf8()).object();
    const auto properties = contract.value(u"properties"_s).toObject();
    QCOMPARE(properties.value(u"promptId"_s).toObject().value(u"const"_s).toInt(), 1);
    QCOMPARE(properties.value(u"responseId"_s).toObject().value(u"const"_s).toString(),
             u"$submit"_s);
    QCOMPARE(properties.value(u"choiceIds"_s).toObject().value(u"type"_s).toString(), u"array"_s);
    QCOMPARE(properties.size(), 3);
    QVERIFY(contract.value(u"required"_s).toArray().contains(u"choiceIds"_s));
    QVERIFY(!contract.value(u"additionalProperties"_s).toBool(true));
    QVERIFY(system.contains(u"NEVER as the top-level"_s));
    // Output guidance describes the shape without preferring either legal choice.
    QVERIFY(!system.contains(u"choice:0"_s));
    QVERIFY(!system.contains(u"choice:1"_s));
}

void ModelOpponentServiceTest::timeoutCancelsReply()
{
    QTemporaryDir dir;
    HttpFixture http;
    ModelOpponentService service(dir.filePath(u"profiles.json"_s));
    QVERIFY(configure(service, http, {{u"timeoutSeconds"_s, 5}}));
    service.testProfile(u"local"_s);
    QTRY_COMPARE(http.requests.size(), 1);
    // Exercise the real timer expiration and abort path without sleeping for the
    // minimum user-configurable five seconds in every test run.
    auto *timer = service.findChild<QTimer *>(u"modelDecisionDeadline"_s);
    QVERIFY(timer);
    QVERIFY(timer->isActive());
    QVERIFY(QMetaObject::invokeMethod(timer, "timeout", Qt::DirectConnection));
    QCOMPARE(service.lastError(), u"timeout"_s);
    QVERIFY(!service.busy());
    QCOMPARE(service.callsUsed(), 1);
    QCOMPARE(http.requests.size(), 1);
}

void ModelOpponentServiceTest::newGrantReplacesInflightRequest()
{
    QTemporaryDir dir;
    HttpFixture http;
    WorkerFixture worker;
    ModelOpponentService service(dir.filePath(u"profiles.json"_s));
    QVERIFY(configure(service, http));
    QVERIFY(service.arm(u"local"_s));
    service.start(worker.url(), worker.grant());
    QTRY_VERIFY(service.active());
    worker.send(u"ai.decision"_s, decision());
    QTRY_COMPARE(http.requests.size(), 1);
    QVERIFY(service.busy());
    auto replacement = worker.grant();
    replacement[u"token"_s] = QString(64, u'b');
    service.start(worker.url(), replacement);
    QTRY_COMPARE(worker.count(u"ai.attach"_s), 2);
    QTRY_VERIFY(service.active());
    QVERIFY(!service.busy());
    QCOMPARE(service.callsUsed(), 1);
    http.validResponses();
    worker.send(u"ai.decision"_s, decision(u"replacement"_s));
    QTRY_COMPARE(worker.count(u"ai.answer"_s), 1);
    QCOMPARE(service.callsUsed(), 2);
}

void ModelOpponentServiceTest::explicitCancelOptionIsAccepted()
{
    QTemporaryDir dir;
    HttpFixture http;
    http.validResponses();
    WorkerFixture worker;
    ModelOpponentService service(dir.filePath(u"profiles.json"_s));
    QVERIFY(configure(service, http));
    QVERIFY(service.arm(u"local"_s));
    service.start(worker.url(), worker.grant());
    QTRY_VERIFY(service.active());
    auto value = decision();
    auto prompt = value.value(u"prompt"_s).toObject();
    prompt[u"kind"_s] = u"payManaCost"_s;
    prompt[u"cancellable"_s] = false;
    prompt[u"options"_s] =
        QJsonArray{QJsonObject{{u"responseId"_s, u"$cancel"_s}, {u"kind"_s, u"cancel"_s}}};
    value[u"prompt"_s] = prompt;
    worker.send(u"ai.decision"_s, value);
    QTRY_COMPARE(worker.count(u"ai.answer"_s), 1);
    QCOMPARE(http.requests.size(), 1);
    QCOMPARE(worker.last(u"ai.answer"_s)
                 .value(u"response"_s)
                 .toObject()
                 .value(u"responseId"_s)
                 .toString(),
             u"$cancel"_s);
}

void ModelOpponentServiceTest::scryRequiresEveryDestinationInOrder()
{
    QTemporaryDir dir;
    HttpFixture http;
    WorkerFixture worker;
    ModelOpponentService service(dir.filePath(u"profiles.json"_s));
    QVERIFY(configure(service, http));
    int attempts = 0;
    http.handler = [&attempts](const HttpFixture::Request &request) {
        auto result = answer(7, u"$submit"_s);
        QJsonArray piles{QJsonObject{{u"destination"_s, u"libraryTop"_s},
                                     {u"cardIds"_s, QJsonArray{u"scry:1"_s}}}};
        if (++attempts > 1)
            piles.append(
                QJsonObject{{u"destination"_s, u"libraryBottom"_s}, {u"cardIds"_s, QJsonArray{}}});
        result[u"scryPiles"_s] = piles;
        HttpFixture::respond(request, completion(json(result)));
    };
    QVERIFY(service.arm(u"local"_s));
    service.start(worker.url(), worker.grant());
    QTRY_VERIFY(service.active());
    auto value = decision();
    auto prompt = value.value(u"prompt"_s).toObject();
    prompt[u"kind"_s] = u"scry"_s;
    prompt[u"options"_s] = QJsonArray{};
    prompt[u"cards"_s] = QJsonArray{QJsonObject{{u"id"_s, u"scry:1"_s}}};
    prompt[u"scryDestinations"_s] = QJsonArray{u"libraryTop"_s, u"libraryBottom"_s};
    value[u"prompt"_s] = prompt;
    worker.send(u"ai.decision"_s, value);
    QTRY_COMPARE(worker.count(u"ai.answer"_s), 1);
    QCOMPARE(http.requests.size(), 2);
    QCOMPARE(worker.last(u"ai.answer"_s)
                 .value(u"response"_s)
                 .toObject()
                 .value(u"scryPiles"_s)
                 .toArray()
                 .size(),
             2);
}

void ModelOpponentServiceTest::cardChoicesRejectReadOnlyDisclosures()
{
    QTemporaryDir dir;
    HttpFixture http;
    WorkerFixture worker;
    ModelOpponentService service(dir.filePath(u"profiles.json"_s));
    QVERIFY(configure(service, http));
    int attempts = 0;
    http.handler = [&attempts](const HttpFixture::Request &request) {
        auto result = answer(7, u"$submit"_s);
        result[u"cardIds"_s] = QJsonArray{++attempts == 1 ? u"reveal:0"_s : u"card-1"_s};
        HttpFixture::respond(request, completion(json(result)));
    };
    QVERIFY(service.arm(u"local"_s));
    service.start(worker.url(), worker.grant());
    QTRY_VERIFY(service.active());
    auto value = decision();
    auto prompt = value.value(u"prompt"_s).toObject();
    prompt[u"kind"_s] = u"chooseCards"_s;
    prompt[u"options"_s] = QJsonArray{};
    prompt[u"minCardSelections"_s] = 1;
    prompt[u"maxCardSelections"_s] = 1;
    prompt[u"cards"_s] = QJsonArray{QJsonObject{{u"id"_s, u"reveal:0"_s}, {u"readOnly"_s, true}},
                                    QJsonObject{{u"id"_s, u"card-1"_s}}};
    value[u"prompt"_s] = prompt;
    worker.send(u"ai.decision"_s, value);
    QTRY_COMPARE(worker.count(u"ai.answer"_s), 1);
    QCOMPARE(http.requests.size(), 2);
    QCOMPARE(
        worker.last(u"ai.answer"_s).value(u"response"_s).toObject().value(u"cardIds"_s).toArray(),
        QJsonArray{u"card-1"_s});
}

QTEST_GUILESS_MAIN(ModelOpponentServiceTest)
#include "modelopponentservice_test.moc"
