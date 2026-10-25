// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
#include "forgecrashreport_fixture.h"
#include "services/FeedbackService.h"
#include <QColorSpace>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QTest>

namespace hexproof::client {
using namespace Qt::StringLiterals;
class FeedbackReceiver final : public QObject
{
  public:
    struct Request
    {
        QByteArray method, path, body;
        QHash<QByteArray, QByteArray> headers;
        QPointer<QTcpSocket> socket;
    };
    QTcpServer server;
    QList<Request> requests;
    std::function<void(const Request &)> handler;
    FeedbackReceiver()
    {
        server.listen(QHostAddress::LocalHost);
        connect(&server, &QTcpServer::newConnection, this, [this] {
            while (auto *socket = server.nextPendingConnection()) {
                connect(socket, &QTcpSocket::readyRead, this, [this, socket] {
                    QByteArray buffer =
                        socket->property("received").toByteArray() + socket->readAll();
                    socket->setProperty("received", buffer);
                    const auto end = buffer.indexOf("\r\n\r\n");
                    if (end < 0 || socket->property("handled").toBool())
                        return;
                    Request request;
                    const auto lines = buffer.left(end).split('\n');
                    const auto first = lines.first().split(' ');
                    request.method = first.value(0);
                    request.path = first.value(1);
                    request.socket = socket;
                    for (const auto &line : lines.mid(1)) {
                        const int at = line.indexOf(':');
                        if (at > 0)
                            request.headers.insert(line.left(at).toLower(),
                                                   line.mid(at + 1).trimmed());
                    }
                    const auto length = request.headers.value("content-length").toLongLong();
                    if (buffer.size() - end - 4 < length)
                        return;
                    request.body = buffer.mid(end + 4, length);
                    socket->setProperty("handled", true);
                    requests.append(request);
                    if (handler)
                        handler(request);
                });
                connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
            }
        });
    }
    QString base() const
    {
        return u"http://127.0.0.1:%1/feedback/v2"_s.arg(server.serverPort());
    }
    QJsonObject config() const
    {
        return {{u"schemaVersion"_s, 2},
                {u"enabled"_s, true},
                {u"apiBase"_s, base()},
                {u"supportLabel"_s, u"Test support"_s},
                {u"privacyUrl"_s, u"https://example.invalid/privacy"_s},
                {u"publicRepository"_s, u"example/feedback"_s},
                {u"noticeRevision"_s, u"public-v1"_s},
                {u"noticeText"_s, u"All submitted content is public."_s},
                {u"providerPolicyRevision"_s, u"providers-v1"_s},
                {u"receiptOnlyApiBases"_s, QJsonArray{}}};
    }
    static void respond(const Request &r, int status, const QByteArray &data = {},
                        const QByteArray &headers = {})
    {
        if (!r.socket)
            return;
        r.socket->write(
            "HTTP/1.1 " + QByteArray::number(status) +
            " Result\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: " +
            QByteArray::number(data.size()) + "\r\n" + headers + "\r\n" + data);
        r.socket->disconnectFromHost();
    }
    static QByteArray receipt(const Request &r)
    {
        const auto parts = r.path.split('/');
        const auto id =
            QString::fromLatin1(parts.last() == "close" ? parts.value(4) : parts.last());
        const auto now = QDateTime::currentDateTimeUtc();
        QJsonObject response{
            {u"schemaVersion"_s, 2},
            {u"submissionId"_s, id},
            {u"receipt"_s, id},
            {u"state"_s, u"accepted"_s},
            {u"publicationState"_s, u"pending"_s},
            {u"removalState"_s, u"none"_s},
            {u"accessExpiresAt"_s, now.addDays(365).toString(Qt::ISODateWithMs)},
            {u"acceptedAt"_s, now.toString(u"yyyy-MM-dd'T'HH:mm:ss"_s) + u".123456789Z"_s},
            {u"contentExpiresAt"_s, now.addDays(90).toString(Qt::ISODateWithMs)}};
        if (r.method == "POST" && parts.last() == "close") {
            response.insert(u"caseState"_s, u"closed"_s);
            response.insert(u"closurePublicationState"_s, u"pending"_s);
            response.insert(u"closedAt"_s, now.toString(Qt::ISODateWithMs));
        }
        if (parts.size() == 7 && parts[5] == "replies")
            response.insert(u"parentSubmissionId"_s, QString::fromLatin1(parts[4]));
        return QJsonDocument(response).toJson(QJsonDocument::Compact);
    }
};
class FeedbackServiceTest : public QObject
{
    Q_OBJECT
  private:
    static QJsonObject disabledConfig()
    {
        return {{u"schemaVersion"_s, 1},  {u"enabled"_s, false},
                {u"apiBase"_s, u""_s},    {u"supportLabel"_s, u""_s},
                {u"privacyUrl"_s, u""_s}, {u"receiptOnlyApiBases"_s, QJsonArray{}}};
    }

    static bool confirm(FeedbackService &service)
    {
        const auto preview = service.previewSubmission();
        return !preview.isEmpty() &&
               service.confirmSubmission(preview.value(u"digest"_s).toString());
    }
    static QString acceptedCase(FeedbackService &service, const FeedbackReceiver &receiver)
    {
        const auto id = service.createDraft();
        auto &record = service.m_records[id];
        const auto now = QDateTime::currentDateTimeUtc();
        record.state = u"accepted"_s;
        record.receipt = id;
        record.description = u"Root report"_s;
        record.endpoint = receiver.base();
        record.secret = QByteArray(32, 's');
        record.dispatched = true;
        record.frozenAt = now;
        record.acceptedAt = now;
        record.expiresAt = now.addDays(365);
        record.accessExpiresAt = now.addDays(365);
        record.publicationState = u"published"_s;
        record.issueUrl = u"https://github.com/example/feedback/issues/1"_s;
        record.disclosure = {
            {u"revision"_s, service.noticeRevision()},
            {u"sha256"_s, QString::fromLatin1(feedback::digest(service.noticeText().toUtf8()))},
            {u"repository"_s, service.publicRepository()},
            {u"providerPolicyRevision"_s, service.providerPolicyRevision()}};
        record.manifest = QJsonDocument(feedback::manifest(record)).toJson(QJsonDocument::Compact);
        service.changedRecord(id);
        return id;
    }
    static QJsonObject threadItem(const QString &id, int sequence, const QString &kind)
    {
        return {{u"submissionId"_s, id},
                {u"sequence"_s, sequence},
                {u"kind"_s, kind},
                {u"description"_s, u"Public content"_s},
                {u"context"_s, QJsonObject{}},
                {u"attachments"_s, QJsonArray{}},
                {u"acceptedAt"_s, QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)},
                {u"publicationState"_s, u"published"_s}};
    }
    static QJsonObject threadPage(const QString &id, int revision, const QJsonArray &items)
    {
        return {{u"schemaVersion"_s, 2},
                {u"submissionId"_s, id},
                {u"revision"_s, revision},
                {u"items"_s, items},
                {u"nextCursor"_s, u""_s},
                {u"workState"_s, u"new"_s},
                {u"summary"_s, u""_s},
                {u"workflowRevision"_s, 0},
                {u"projectionState"_s, u"none"_s},
                {u"removalState"_s, u"none"_s},
                {u"accessExpiresAt"_s,
                 QDateTime::currentDateTimeUtc().addDays(365).toString(Qt::ISODateWithMs)},
                {u"contentExpiresAt"_s,
                 QDateTime::currentDateTimeUtc().addDays(365).toString(Qt::ISODateWithMs)}};
    }

  private slots:
    void historyProjectionUsesCurrentQuestionAndProtectsRefreshAuthority()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        FeedbackService service(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!service.saving());
        const auto id = acceptedCase(service, receiver);
        QTRY_VERIFY(!service.saving());
        auto &record = service.m_records[id];
        record.threadPage = threadPage(id, 1, {});
        record.threadPage.insert(u"workState"_s, u"needs-information"_s);
        record.threadPage.insert(u"summary"_s, u"Please describe <b>the result</b>"_s);
        record.threadSyncedAt = QDateTime::currentDateTimeUtc().addSecs(-60);
        record.threadNextAttempt = QDateTime::currentDateTimeUtc().addSecs(600);
        auto row = [&] { return service.cases().first().toMap(); };
        QVERIFY(!row().value(u"needsReply"_s).toBool());
        record.threadPage.insert(u"question"_s, QJsonObject{{u"id"_s, id}, {u"revision"_s, 1}});
        QVERIFY(row().value(u"needsReply"_s).toBool());
        QVERIFY(row().value(u"threadRefreshAllowed"_s).toBool());
        QCOMPARE(row().value(u"summary"_s).toString(), u"Please describe <b>the result</b>"_s);
        QCOMPARE(row().value(u"syncedAt"_s).toString(),
                 record.threadSyncedAt.toString(Qt::ISODateWithMs));
        QCOMPARE(row().value(u"threadNextAttempt"_s).toString(),
                 record.threadNextAttempt.toString(Qt::ISODateWithMs));
        QVERIFY(!row().contains(u"secret"_s));
        QVERIFY(!row().contains(u"endpoint"_s));
        record.closureRequestState = u"requested"_s;
        QVERIFY(!row().value(u"needsReply"_s).toBool());
        QVERIFY(!row().value(u"threadRefreshAllowed"_s).toBool());
        record.closureRequestState = u"none"_s;
        record.caseState = u"closed"_s;
        QVERIFY(!row().value(u"needsReply"_s).toBool());
        QVERIFY(!row().value(u"threadRefreshAllowed"_s).toBool());
        record.caseState = u"open"_s;
        record.removalAuthorized = true;
        QVERIFY(!row().value(u"needsReply"_s).toBool());
        QVERIFY(!row().value(u"threadRefreshAllowed"_s).toBool());
        record.removalAuthorized = false;
        record.threadPage.remove(u"question"_s);
        QVERIFY(!row().value(u"needsReply"_s).toBool());
        record.endpoint = u"https://untrusted.invalid/feedback/v2"_s;
        QVERIFY(!row().value(u"threadRefreshAllowed"_s).toBool());
        record.endpoint = receiver.base();
        record.secret.clear();
        QVERIFY(!row().value(u"threadRefreshAllowed"_s).toBool());
        QCOMPARE(receiver.requests.size(), 0);
    }
    void retryProjectionDoesNotPromiseStoppedOrExhaustedUploads()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        FeedbackService service(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!service.saving());
        const auto id = service.createDraft();
        QTRY_VERIFY(!service.saving());
        auto &record = service.m_records[id];
        record.authorized = true;
        record.state = u"queued"_s;
        record.endpoint = receiver.base();
        record.frozenAt = QDateTime::currentDateTimeUtc();
        record.nextAttempt = record.frozenAt.addSecs(600);
        auto retry = [&] { return service.draft().value(u"automaticRetryPending"_s).toBool(); };
        QVERIFY(retry());
        QCOMPARE(service.draft().value(u"nextAttempt"_s).toString(),
                 record.nextAttempt.toString(Qt::ISODateWithMs));
        const auto eligible = record;
        record.authorized = false;
        QVERIFY(!retry());
        record = eligible;
        record.attempts = 20;
        QVERIFY(!retry());
        record.state = u"unconfirmed"_s;
        QVERIFY(retry()); // The final upload still permits receipt recovery.
        record.queries = 40;
        QVERIFY(!retry());
        record = eligible;
        record.frozenAt = QDateTime::currentDateTimeUtc().addDays(-7);
        QVERIFY(!retry());
        record.frozenAt = {};
        QVERIFY(!retry());
        for (const auto &state : {u"accepted"_s, u"received"_s, u"needs_attention"_s}) {
            record = eligible;
            record.state = state;
            QVERIFY(!retry());
        }
        record = eligible;
        record.endpoint = u"https://untrusted.invalid/feedback/v2"_s;
        QVERIFY(!retry());
        record = eligible;
        service.m_storageFailed = true;
        QVERIFY(!retry());
        service.m_storageFailed = false;
        service.m_deleting.insert(id);
        QVERIFY(!retry());
        service.m_deleting.remove(id);
        const auto parent = acceptedCase(service, receiver);
        service.m_records[id] = eligible;
        service.m_records[id].parentId = parent;
        service.selectRecord(id);
        QVERIFY(retry());
        service.m_records[parent].caseState = u"closed"_s;
        QVERIFY(!retry());
        QCOMPARE(receiver.requests.size(), 0);
    }
    void summaryRefreshKeepsSelectedDraftAndThreadContext()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        FeedbackService service(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!service.saving());
        const auto parent = acceptedCase(service, receiver);
        const auto draft = service.createDraft();
        QVERIFY(service.updateDraft({{u"description"_s, u"Unsent draft"_s}}));
        QTRY_VERIFY(!service.saving());
        service.m_threadError = u"existing_thread_error"_s;
        service.m_error = u"existing_operation_error"_s;
        service.m_threadAttachment = {{u"content"_s, u"existing preview"_s}};
        const auto selectedDraft = service.draft();
        const auto selectedThread = service.thread();
        const auto attachment = service.threadAttachmentPreview();
        QVERIFY(service.refreshCaseSummary(parent));
        QVERIFY(!service.refreshCaseSummary(parent));
        QCOMPARE(service.draft(), selectedDraft);
        QCOMPARE(service.thread(), selectedThread);
        QTRY_COMPARE(receiver.requests.size(), 1);
        auto page = threadPage(parent, 2, {threadItem(parent, 0, u"submission"_s)});
        page.insert(u"summary"_s, u"Please provide reproduction steps"_s);
        FeedbackReceiver::respond(receiver.requests.last(), 200, QJsonDocument(page).toJson());
        QTRY_VERIFY(!service.busy() && !service.saving());
        QCOMPARE(service.draft(), selectedDraft);
        QCOMPARE(service.thread(), selectedThread);
        QCOMPARE(service.threadAttachmentPreview(), attachment);
        QCOMPARE(service.errorCode(), u"existing_operation_error"_s);
        QCOMPARE(service.caseRefresh().value(u"caseId"_s).toString(), parent);
        QVERIFY(service.caseRefresh().value(u"errorCode"_s).toString().isEmpty());
        const auto record = service.m_records[parent];
        QCOMPARE(record.threadPage.value(u"summary"_s).toString(),
                 u"Please provide reproduction steps"_s);
        QVERIFY(record.threadSyncedAt.isValid());
        QVERIFY(!service.refreshCaseSummary(parent));
        QCOMPARE(service.caseRefresh().value(u"errorCode"_s).toString(), u"rate_limited"_s);
        service.m_records[parent].threadNextAttempt = {};
        QVERIFY(service.refreshCaseSummary(parent));
        QTRY_COMPARE(receiver.requests.size(), 2);
        FeedbackReceiver::respond(receiver.requests.last(), 503, {}, "Retry-After: 600\r\n");
        QTRY_VERIFY(!service.busy() && !service.saving());
        QCOMPARE(service.caseRefresh().value(u"errorCode"_s).toString(), u"network_error"_s);
        QCOMPARE(service.m_records[parent].threadPage, record.threadPage);
        QCOMPARE(service.m_records[parent].threadSyncedAt, record.threadSyncedAt);
        QVERIFY(service.m_records[parent].threadNextAttempt >
                QDateTime::currentDateTimeUtc().addSecs(590));
        QCOMPARE(service.draft().value(u"id"_s).toString(), draft);
        QCOMPARE(service.thread(), selectedThread);
        QCOMPARE(service.errorCode(), u"existing_operation_error"_s);
    }
    void sharedAIConversationFixtures_data()
    {
        QTest::addColumn<QString>("fileName");
        QTest::addColumn<QString>("state");
        QTest::addColumn<int>("deliveries");
        QTest::newRow("specific-question")
            << u"thread-custom-question.json"_s << u"needs-information"_s << 0;
        QTest::newRow("new-input-keeps-delivery-history")
            << u"thread-delivery-history.json"_s << u"assessing"_s << 2;
    }
    void sharedAIConversationFixtures()
    {
        QFETCH(QString, fileName);
        QFETCH(QString, state);
        QFETCH(int, deliveries);
        QFile fixture(QFINDTESTDATA("../../../testdata/feedback/v2/" + fileName));
        QVERIFY(fixture.open(QIODevice::ReadOnly));
        const auto source = QJsonDocument::fromJson(fixture.readAll()).object();
        QVERIFY(!source.isEmpty());
        auto page = source;
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        auto config = receiver.config();
        config.insert(u"publicRepository"_s, u"example/project"_s);
        FeedbackService service(dir.path(), config, true);
        QTRY_VERIFY(!service.saving());
        const auto parent = acceptedCase(service, receiver);
        // Local receipt identity is generated by the test; retain every new wire field.
        page.insert(u"submissionId"_s, parent);
        auto items = page.value(u"items"_s).toArray();
        for (qsizetype index = 0; index < items.size(); ++index) {
            auto item = items[index].toObject();
            if (item.value(u"submissionId"_s) == source.value(u"submissionId"_s))
                item.insert(u"submissionId"_s, parent);
            if (item.contains(u"parentSubmissionId"_s))
                item.insert(u"parentSubmissionId"_s, parent);
            items[index] = item;
        }
        page.insert(u"items"_s, items);
        receiver.handler = [page](const auto &request) {
            FeedbackReceiver::respond(request, 200, QJsonDocument(page).toJson());
        };
        QTRY_VERIFY(!service.saving());
        QVERIFY(service.refreshThread(parent));
        QTRY_VERIFY(!service.busy());
        QCOMPARE(service.thread().value(u"errorCode"_s).toString(), QString{});
        QCOMPARE(service.thread().value(u"workState"_s).toString(), state);
        const auto history = service.thread().value(u"deliveryHistory"_s).toList();
        QCOMPARE(history.size(), deliveries);
        QVERIFY(!service.thread().contains(u"outcome"_s));
        if (deliveries == 0) {
            const auto question = service.thread().value(u"question"_s).toMap();
            QCOMPARE(question.value(u"code"_s).toString(), u"custom"_s);
            QCOMPARE(question.value(u"description"_s).toString(),
                     source.value(u"question"_s).toObject().value(u"description"_s).toString());
        } else {
            QCOMPARE(history, source.value(u"deliveryHistory"_s).toArray().toVariantList());
            const auto released = history.last().toMap().value(u"outcome"_s).toMap();
            QCOMPARE(released.value(u"version"_s).toString(), u"3.1.0"_s);
            QCOMPARE(released.value(u"repository"_s).toString(), u"example/project"_s);
        }
    }
    void casesKeepReplyDraftsAccessibleAndRetainOrphans()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        FeedbackService service(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!service.saving());
        const auto parent = acceptedCase(service, receiver);
        const auto reply = service.createReplyDraft(parent);
        QVERIFY(!reply.isEmpty());
        QVERIFY(service.updateDraft({{u"description"_s, u"An unfinished answer"_s}}));
        QCOMPARE(service.records().size(), 2);
        QCOMPARE(service.cases().size(), 1);
        QCOMPARE(service.cases().first().toMap().value(u"id"_s).toString(), parent);
        QCOMPARE(service.cases().first().toMap().value(u"localReplyCount"_s).toInt(), 1);
        QVERIFY(service.selectRecord(parent));
        QCOMPARE(service.thread().value(u"localReplies"_s).toList().size(), 1);
        QCOMPARE(service.thread()
                     .value(u"localReplies"_s)
                     .toList()
                     .first()
                     .toMap()
                     .value(u"id"_s)
                     .toString(),
                 reply);
        service.m_records[parent].caseState = u"closed"_s;
        service.m_records[parent].closurePublicationState = u"pending"_s;
        service.m_records[parent].closedAt = QDateTime::currentDateTimeUtc();
        service.stopReplies(parent);
        QCOMPARE(service.thread().value(u"localReplies"_s).toList().size(), 1);
        QVERIFY(service.selectRecord(reply));
        QCOMPARE(service.draft().value(u"description"_s).toString(), u"An unfinished answer"_s);
        QVERIFY(!confirm(service));
        QVERIFY(service.deleteRecord(parent));
        QTRY_VERIFY(!service.saving());
        QCOMPARE(service.cases().size(), 1);
        QCOMPARE(service.cases().first().toMap().value(u"id"_s).toString(), reply);
        QVERIFY(!service.cases().first().toMap().value(u"parentAvailable"_s).toBool());
        QVERIFY(service.selectRecord(reply));
        QCOMPARE(service.draft().value(u"description"_s).toString(), u"An unfinished answer"_s);
    }
    void typedOutcomesRetainDeliveryAcrossNewInputAndRestart()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        QString parent;
        const auto projection = u"22222222-2222-4222-8222-222222222222"_s;
        const QJsonObject outcome{{u"kind"_s, u"release"_s},
                                  {u"repository"_s, u"example/feedback"_s},
                                  {u"commit"_s, QString(40, u'a')},
                                  {u"tag"_s, u"v3.1.0"_s},
                                  {u"version"_s, u"3.1.0"_s}};
        const QJsonObject delivery{
            {u"projectionId"_s, projection},
            {u"inputRevision"_s, 1},
            {u"workflowRevision"_s, 3},
            {u"publishedAt"_s, QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)},
            {u"outcome"_s, outcome}};
        {
            FeedbackService service(dir.path(), receiver.config(), true);
            QTRY_VERIFY(!service.saving());
            parent = acceptedCase(service, receiver);
            auto item = threadItem(projection, 1, u"assessment"_s);
            item.insert(u"outcome"_s, outcome);
            auto page = threadPage(parent, 2, {threadItem(parent, 0, u"submission"_s), item});
            page.insert(u"workState"_s, u"released"_s);
            page.insert(u"outcome"_s, outcome);
            page.insert(u"deliveryHistory"_s, QJsonArray{delivery});
            receiver.handler = [&](const auto &request) {
                FeedbackReceiver::respond(request, 200, QJsonDocument(page).toJson());
            };
            QTRY_VERIFY(!service.saving());
            QVERIFY(service.refreshThread(parent));
            QTRY_VERIFY(!service.busy());
            QCOMPARE(service.thread().value(u"outcome"_s).toMap(), outcome.toVariantMap());
            QCOMPARE(service.thread().value(u"deliveryHistory"_s).toList().size(), 1);
            page.insert(u"revision"_s, 3);
            page.insert(u"workState"_s, u"new"_s);
            page.remove(u"outcome"_s);
            service.m_records[parent].threadNextAttempt = {};
            QVERIFY(service.refreshThread(parent));
            QTRY_VERIFY(!service.busy());
            QCOMPARE(service.thread().value(u"workState"_s).toString(), u"new"_s);
            QVERIFY(!service.thread().contains(u"outcome"_s));
            QCOMPARE(service.thread().value(u"deliveryHistory"_s).toList().first().toMap(),
                     delivery.toVariantMap());
            QCOMPARE(service.thread()
                         .value(u"items"_s)
                         .toList()
                         .last()
                         .toMap()
                         .value(u"outcome"_s)
                         .toMap(),
                     outcome.toVariantMap());
            QTRY_VERIFY(!service.saving());
        }
        FeedbackService recovered(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!recovered.saving());
        QVERIFY(recovered.selectRecord(parent));
        QCOMPARE(recovered.thread().value(u"workState"_s).toString(), u"new"_s);
        QCOMPARE(recovered.thread().value(u"deliveryHistory"_s).toList().first().toMap(),
                 delivery.toVariantMap());
    }
    void malformedTypedOutcomeDoesNotReplaceCachedConversation()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        FeedbackService service(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!service.saving());
        const auto parent = acceptedCase(service, receiver);
        auto page = threadPage(parent, 1, {threadItem(parent, 0, u"submission"_s)});
        const QJsonObject outcome{{u"kind"_s, u"duplicate"_s},
                                  {u"repository"_s, u"example/feedback"_s},
                                  {u"issueNumber"_s, 12}};
        page.insert(u"outcome"_s, outcome);
        receiver.handler = [&](const auto &request) {
            FeedbackReceiver::respond(request, 200, QJsonDocument(page).toJson());
        };
        QTRY_VERIFY(!service.saving());
        QVERIFY(service.refreshThread(parent));
        QTRY_VERIFY(!service.busy());
        QCOMPARE(service.thread().value(u"outcome"_s).toMap(), outcome.toVariantMap());
        const QList<QJsonObject> invalid{{{u"kind"_s, u"duplicate"_s},
                                          {u"repository"_s, u"private/repository"_s},
                                          {u"issueNumber"_s, 12}},
                                         {{u"kind"_s, u"duplicate"_s},
                                          {u"repository"_s, u"example/feedback"_s},
                                          {u"issueNumber"_s, 1.5}},
                                         {{u"kind"_s, u"release"_s},
                                          {u"repository"_s, u"example/feedback"_s},
                                          {u"commit"_s, QString(40, u'a')},
                                          {u"version"_s, u"3.1.0"_s},
                                          {u"tag"_s, u"v3.2.0"_s}},
                                         {{u"kind"_s, u"source"_s},
                                          {u"repository"_s, u"example/feedback"_s},
                                          {u"commit"_s, u"not-a-commit"_s}}};
        for (const auto &bad : invalid) {
            page.insert(u"revision"_s, 2);
            page.insert(u"outcome"_s, bad);
            service.m_records[parent].threadNextAttempt = {};
            QVERIFY(service.refreshThread(parent));
            QTRY_VERIFY(!service.busy());
            QCOMPARE(service.thread().value(u"errorCode"_s).toString(), u"response_invalid"_s);
            QCOMPARE(service.thread().value(u"revision"_s).toInt(), 1);
            QCOMPARE(service.thread().value(u"outcome"_s).toMap(), outcome.toVariantMap());
        }
    }
    void closeFeedbackRetainsReadableHistoryAndRemovalRemainsSeparate()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        receiver.handler = [](const auto &request) {
            if (request.path.contains("/thread")) {
                const auto id = QString::fromLatin1(request.path.split('/').value(4));
                auto page = threadPage(id, 1, {threadItem(id, 1, u"submission"_s)});
                page.insert(u"caseState"_s, u"closed"_s);
                page.insert(u"closurePublicationState"_s, u"stalled"_s);
                page.insert(u"closedAt"_s,
                            QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
                page.insert(u"closureReason"_s, u"github_unavailable"_s);
                FeedbackReceiver::respond(request, 200, QJsonDocument(page).toJson());
                return;
            }
            auto response = QJsonDocument::fromJson(FeedbackReceiver::receipt(request)).object();
            if (request.method == "DELETE")
                response.insert(u"removalState"_s, u"removed"_s);
            FeedbackReceiver::respond(request, 200, QJsonDocument(response).toJson());
        };
        FeedbackService service(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!service.saving());
        const auto id = acceptedCase(service, receiver);
        QTRY_VERIFY(!service.saving());
        const auto retained = service.m_records[id].manifest;
        QVERIFY(service.closeFeedback(id));
        QVERIFY(QFile::exists(dir.filePath(u"feedback/"_s + id + u".closure"_s)));
        QTRY_COMPARE(service.m_records[id].caseState, u"closed"_s);
        QTRY_VERIFY(!service.saving() && !service.busy());
        QCOMPARE(receiver.requests.size(), 1);
        QCOMPARE(receiver.requests.first().method, QByteArray("POST"));
        QCOMPARE(receiver.requests.first().path,
                 "/feedback/v2/submissions/" + id.toUtf8() + "/close");
        QVERIFY(receiver.requests.first().body.isEmpty());
        QCOMPARE(receiver.requests.first().headers.value("authorization"),
                 "Feedback " + service.m_records[id].secret.toBase64(
                                   QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals));
        QCOMPARE(service.m_records[id].manifest, retained);
        QCOMPARE(service.m_records[id].removalState, u"none"_s);
        QVERIFY(service.createReplyDraft(id).isEmpty());
        QVERIFY(service.refreshThread(id));
        QTRY_COMPARE(service.thread().value(u"closurePublicationState"_s).toString(), u"stalled"_s);
        QVERIFY(!service.thread().value(u"items"_s).toList().isEmpty());
        QVERIFY(!service.thread().value(u"replyAllowed"_s).toBool());
        QTRY_VERIFY(!service.saving() && !service.busy());
        QVERIFY(service.requestRemoval(id));
        QTRY_COMPARE(service.m_records[id].removalState, u"removed"_s);
        QCOMPARE(receiver.requests.last().method, QByteArray("DELETE"));
        QVERIFY(!receiver.requests.last().path.endsWith("/close"));
        QCOMPARE(service.m_records[id].caseState, u"closed"_s);
        QTRY_VERIFY(!service.saving());
    }
    void closureJournalRecoversExplicitIntentWithoutMigratingOldRecords()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        QString id;
        QByteArray stale;
        {
            FeedbackService service(dir.path(), receiver.config(), true);
            QTRY_VERIFY(!service.saving());
            id = acceptedCase(service, receiver);
            QTRY_VERIFY(!service.saving());
            auto old = feedback::encode(service.m_records[id], true);
            for (const auto &key :
                 {u"caseState"_s, u"closurePublicationState"_s, u"closureRequestState"_s,
                  u"closureAuthorized"_s, u"closureRequestedAt"_s, u"closureAttempts"_s,
                  u"closureReason"_s})
                old.remove(key);
            stale = QJsonDocument(old).toJson();
        }
        QVERIFY(feedback::writePrivate(dir.filePath(u"feedback/"_s + id + u".json"_s), stale));
        {
            FeedbackService migrated(dir.path(), receiver.config(), true);
            QTRY_VERIFY(!migrated.saving());
            QCOMPARE(migrated.m_records[id].caseState, u"open"_s);
            QVERIFY(!migrated.m_records[id].closureAuthorized);
            QTest::qWait(30);
            QVERIFY(receiver.requests.isEmpty());
            migrated.m_writing =
                true; // Interrupt the full-record write after durable close intent.
            QVERIFY(migrated.closeFeedback(id));
        }
        QVERIFY(feedback::writePrivate(dir.filePath(u"feedback/"_s + id + u".json"_s), stale));
        receiver.handler = [](const auto &request) {
            FeedbackReceiver::respond(request, 200, FeedbackReceiver::receipt(request));
        };
        FeedbackService recovered(dir.path(), receiver.config(), true);
        QTRY_COMPARE(recovered.m_records[id].caseState, u"closed"_s);
        QCOMPARE(receiver.requests.size(), 1);
        QCOMPARE(receiver.requests.first().method, QByteArray("POST"));
        QTRY_VERIFY(!recovered.saving());
    }
    void staleLookupCannotAcknowledgeOrDelayClosure()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        receiver.handler = [](const auto &request) {
            if (request.method == "POST")
                FeedbackReceiver::respond(request, 200, FeedbackReceiver::receipt(request));
        };
        FeedbackService service(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!service.saving());
        const auto id = acceptedCase(service, receiver);
        QTRY_VERIFY(!service.saving());
        QVERIFY(service.queryReceipt(id));
        QTRY_COMPARE(receiver.requests.size(), 1);
        QTRY_VERIFY(!service.saving());
        QVERIFY(service.closeFeedback(id));
        FeedbackReceiver::respond(receiver.requests.first(), 200,
                                  FeedbackReceiver::receipt(receiver.requests.first()));
        QTRY_COMPARE_WITH_TIMEOUT(receiver.requests.size(), 2, 2000);
        QCOMPARE(receiver.requests.last().method, QByteArray("POST"));
        QTRY_COMPARE(service.m_records[id].caseState, u"closed"_s);
        QTRY_VERIFY(!service.saving());
        service.m_records[id].lastQuery = {};
        QVERIFY(service.queryReceipt(id));
        QTRY_COMPARE(receiver.requests.size(), 3);
        FeedbackReceiver::respond(receiver.requests.last(), 200,
                                  FeedbackReceiver::receipt(receiver.requests.last()));
        QTRY_VERIFY(!service.busy() && !service.saving());
        QCOMPARE(service.m_records[id].caseState, u"closed"_s);
        QCOMPARE(service.m_records[id].closurePublicationState, u"pending"_s);
    }
    void closureResponseMustConfirmClosedWithValidFields_data()
    {
        QTest::addColumn<QJsonObject>("fields");
        QTest::newRow("legacy-open-receipt")
            << QJsonObject{{u"caseState"_s, u"open"_s},
                           {u"closurePublicationState"_s, u"none"_s},
                           {u"omitClosedAt"_s, true}};
        QTest::newRow("bad-state") << QJsonObject{{u"caseState"_s, u"erased"_s}};
        QTest::newRow("bad-publication")
            << QJsonObject{{u"closurePublicationState"_s, u"erased"_s}};
        QTest::newRow("wrong-type") << QJsonObject{{u"caseState"_s, true}};
        QTest::newRow("bad-date") << QJsonObject{{u"closedAt"_s, u"tomorrow"_s}};
        QTest::newRow("non-utc-date")
            << QJsonObject{{u"closedAt"_s, u"2026-10-23T12:00:00+01:00"_s}};
        QTest::newRow("oversize-reason") << QJsonObject{{u"closureReason"_s, QString(81, u'x')}};
        QTest::newRow("closed-without-delivery")
            << QJsonObject{{u"closurePublicationState"_s, u"none"_s}};
        QTest::newRow("open-with-closed-delivery") << QJsonObject{
            {u"caseState"_s, u"open"_s}, {u"closurePublicationState"_s, u"closed"_s}};
        QTest::newRow("missing-closed-time") << QJsonObject{{u"omitClosedAt"_s, true}};
        QTest::newRow("open-with-closed-time")
            << QJsonObject{{u"caseState"_s, u"open"_s}, {u"closurePublicationState"_s, u"none"_s}};
    }
    void closureResponseMustConfirmClosedWithValidFields()
    {
        QFETCH(QJsonObject, fields);
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        receiver.handler = [fields](const auto &request) {
            auto receipt = QJsonDocument::fromJson(FeedbackReceiver::receipt(request)).object();
            for (auto it = fields.begin(); it != fields.end(); ++it) {
                if (it.key() == u"omitClosedAt")
                    receipt.remove(u"closedAt"_s);
                else
                    receipt.insert(it.key(), it.value());
            }
            FeedbackReceiver::respond(request, 200, QJsonDocument(receipt).toJson());
        };
        FeedbackService service(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!service.saving());
        const auto id = acceptedCase(service, receiver);
        QTRY_VERIFY(!service.saving());
        QVERIFY(service.closeFeedback(id));
        QTRY_COMPARE(service.m_records[id].closureRequestState, u"stalled"_s);
        QCOMPARE(service.m_records[id].caseState, u"open"_s);
        QVERIFY(!service.m_records[id].closureAuthorized);
        QCOMPARE(service.m_records[id].reason, u"response_invalid"_s);
        QCOMPARE(service.m_records[id].removalState, u"none"_s);
        QTRY_VERIFY(!service.saving());
    }
    void closedReplyMetadataSurvivesPersistenceAndParentRecovery()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        receiver.handler = [](const auto &request) {
            auto receipt = QJsonDocument::fromJson(FeedbackReceiver::receipt(request)).object();
            receipt.insert(u"closurePublicationState"_s, u"stalled"_s);
            receipt.insert(u"closureReason"_s, u"github_unavailable"_s);
            FeedbackReceiver::respond(request, 200, QJsonDocument(receipt).toJson());
        };
        QString parentId, replyId;
        QByteArray staleReply;
        {
            FeedbackService service(dir.path(), receiver.config(), true);
            QTRY_VERIFY(!service.saving());
            parentId = acceptedCase(service, receiver);
            QTRY_VERIFY(!service.saving());
            replyId = service.createReplyDraft(parentId);
            QVERIFY(!replyId.isEmpty());
            QTRY_VERIFY(!service.saving());
            staleReply = QJsonDocument(feedback::encode(service.m_records[replyId], true)).toJson();
            QVERIFY(service.closeFeedback(parentId));
            QTRY_COMPARE(service.m_records[parentId].caseState, u"closed"_s);
            QTRY_VERIFY(!service.saving());
            const auto &reply = service.m_records[replyId];
            QCOMPARE(reply.closedAt, service.m_records[parentId].closedAt);
            QCOMPARE(reply.closureReason, u"github_unavailable"_s);
            QVERIFY(feedback::decode(feedback::encode(reply, true)).has_value());
        }
        // Simulate an interrupted child write after the parent closure was committed.
        QVERIFY(feedback::writePrivate(dir.filePath(u"feedback/"_s + replyId + u".json"_s),
                                       staleReply));
        FeedbackService recovered(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!recovered.saving());
        QCOMPARE(recovered.m_records[replyId].caseState, u"closed"_s);
        QCOMPARE(recovered.m_records[replyId].closedAt, recovered.m_records[parentId].closedAt);
        QCOMPARE(recovered.m_records[replyId].closurePublicationState, u"stalled"_s);
        QCOMPARE(recovered.m_records[replyId].closureReason, u"github_unavailable"_s);
        QVERIFY(feedback::decode(feedback::encode(recovered.m_records[replyId], true)).has_value());
        QCOMPARE(receiver.requests.size(), 1);
    }
    void closureRetriesAreBoundedAndKeepTheirCapability()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        receiver.handler = [](const auto &request) { FeedbackReceiver::respond(request, 503); };
        QString id;
        {
            FeedbackService service(dir.path(), receiver.config(), true);
            QTRY_VERIFY(!service.saving());
            id = acceptedCase(service, receiver);
            QTRY_VERIFY(!service.saving());
            QVERIFY(service.closeFeedback(id));
            QTRY_COMPARE(receiver.requests.size(), 1);
            QTRY_VERIFY(!service.busy() && !service.saving());
            QVERIFY(service.m_records[id].closureAuthorized);
        }
        FeedbackService recovered(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!recovered.saving());
        recovered.m_records[id].nextAttempt = QDateTime::currentDateTimeUtc();
        recovered.pump();
        QTRY_COMPARE(receiver.requests.size(), 2);
        QTRY_VERIFY(!recovered.busy() && !recovered.saving());
        QCOMPARE(receiver.requests.first().headers.value("authorization"),
                 receiver.requests.last().headers.value("authorization"));
        QCOMPARE(recovered.m_records[id].closureAttempts, 2);
        recovered.m_records[id].closureAttempts = 20;
        recovered.m_records[id].nextAttempt = QDateTime::currentDateTimeUtc();
        recovered.pump();
        QCOMPARE(recovered.m_records[id].closureRequestState, u"stalled"_s);
        QVERIFY(!recovered.m_records[id].closureAuthorized);
        QCOMPARE(receiver.requests.size(), 2);
        QTRY_VERIFY(!recovered.saving());
    }
    void developmentStatesSurviveThreadRefresh_data()
    {
        QTest::addColumn<QString>("state");
        QTest::newRow("implementation") << u"implementing"_s;
        QTest::newRow("verification") << u"verifying"_s;
        QTest::newRow("awaiting-independent-review") << u"verified-awaiting-review"_s;
        QTest::newRow("independent-review") << u"reviewing"_s;
        QTest::newRow("integration-verification") << u"verifying-integration"_s;
        QTest::newRow("merge-ready") << u"merge-ready"_s;
        QTest::newRow("merging") << u"merging"_s;
        QTest::newRow("merged") << u"merged-awaiting-release"_s;
        QTest::newRow("source-published") << u"source-published-awaiting-release"_s;
        QTest::newRow("released") << u"released"_s;
    }
    void developmentStatesSurviveThreadRefresh()
    {
        QFETCH(QString, state);
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        FeedbackService service(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!service.saving());
        const auto parent = acceptedCase(service, receiver);
        auto page = threadPage(parent, 2, {threadItem(parent, 0, u"submission"_s)});
        page.insert(u"workState"_s, state);
        page.insert(u"workflowRevision"_s, 3);
        page.insert(u"projectionState"_s, u"published"_s);
        page.insert(u"summary"_s, u"Verified public progress and associated public links."_s);
        receiver.handler = [page](const auto &request) {
            FeedbackReceiver::respond(request, 200,
                                      QJsonDocument(page).toJson(QJsonDocument::Compact));
        };
        QTRY_VERIFY(!service.saving());
        QVERIFY(service.refreshThread(parent));
        QTRY_VERIFY(!service.busy());
        QCOMPARE(service.thread().value(u"workState"_s).toString(), state);
        QCOMPARE(service.thread().value(u"workflowRevision"_s).toInt(), 3);
        QCOMPARE(service.thread().value(u"projectionState"_s).toString(), u"published"_s);
        QCOMPARE(service.thread().value(u"summary"_s).toString(),
                 page.value(u"summary"_s).toString());
        QVERIFY(service.thread().value(u"replyAllowed"_s).toBool());
    }
    void repliesBindOwnPreviewQuestionAndParentCapability_data()
    {
        QTest::addColumn<QString>("questionCode");
        QTest::newRow("legacy-template") << u"reproduction_steps"_s;
        QTest::newRow("specific-ai-question") << u"custom"_s;
    }
    void repliesBindOwnPreviewQuestionAndParentCapability()
    {
        QFETCH(QString, questionCode);
        QFile fixtureFile(QFINDTESTDATA("../../../testdata/feedback/v2/reply-valid.json"));
        QFile contractFile(QFINDTESTDATA("../../../testdata/feedback/v2/reply-contract.json"));
        QVERIFY(fixtureFile.open(QIODevice::ReadOnly));
        QVERIFY(contractFile.open(QIODevice::ReadOnly));
        const auto fixtureBytes = fixtureFile.readAll();
        const auto fixture = QJsonDocument::fromJson(fixtureBytes).object();
        const auto contract = QJsonDocument::fromJson(contractFile.readAll()).object();
        feedback::Record shared;
        shared.id = fixture.value(u"submissionId"_s).toString();
        shared.parentId = fixture.value(u"parentSubmissionId"_s).toString();
        shared.questionId = fixture.value(u"questionId"_s).toString();
        shared.questionRevision = fixture.value(u"questionRevision"_s).toInt();
        shared.frozenAt =
            QDateTime::fromString(fixture.value(u"createdAt"_s).toString(), Qt::ISODateWithMs);
        shared.category = fixture.value(u"category"_s).toString();
        shared.description = fixture.value(u"description"_s).toString();
        shared.context = fixture.value(u"context"_s).toObject();
        shared.disclosure = fixture.value(u"disclosure"_s).toObject();
        shared.manifest = fixtureBytes;
        QCOMPARE(feedback::manifest(shared), fixture);
        QCOMPARE(feedback::manifestDigest(shared),
                 contract.value(u"manifestDigest"_s).toString().toLatin1());
        QCOMPARE(contract.value(u"digestDomain"_s).toString(), u"hexproof-feedback-reply-v2\n"_s);
        QCOMPARE(feedback::digest(contract.value(u"noticeText"_s).toString().toUtf8()),
                 shared.disclosure.value(u"sha256"_s).toString().toLatin1());
        QVERIFY(feedback::manifestDigest(shared) !=
                feedback::digest("hexproof-feedback-v2\n" + fixtureBytes));
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        FeedbackService service(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!service.saving());
        const auto parent = acceptedCase(service, receiver);
        const auto questionId = u"11111111-1111-4111-8111-111111111111"_s;
        auto page = threadPage(parent, 2, {threadItem(parent, 0, u"submission"_s)});
        const QJsonObject question{
            {u"id"_s, questionId},
            {u"revision"_s, 1},
            {u"code"_s, questionCode},
            {u"description"_s, u"Describe how to reproduce."_s},
            {u"publishedAt"_s,
             QDateTime::currentDateTimeUtc().addDays(-2).toString(Qt::ISODateWithMs)},
            {u"answerDeadline"_s,
             QDateTime::currentDateTimeUtc().addDays(-1).toString(Qt::ISODateWithMs)}};
        page.insert(u"question"_s, question);
        page.insert(u"workState"_s, u"needs-information"_s);
        page.insert(u"summary"_s, u"Unable to reproduce without steps."_s);
        page.insert(u"assessmentDeliveryState"_s, u"unavailable"_s);
        page.insert(u"assessmentDeliveryReason"_s, u"coordinator_unavailable"_s);
        page.insert(u"secret"_s, u"MUST_NOT_SURFACE"_s);
        receiver.handler = [page](const auto &request) {
            FeedbackReceiver::respond(request, 200,
                                      request.path.contains("/thread")
                                          ? QJsonDocument(page).toJson(QJsonDocument::Compact)
                                          : FeedbackReceiver::receipt(request));
        };
        QTRY_VERIFY(!service.saving());
        QVERIFY(service.refreshThread(parent));
        QTRY_VERIFY(!service.busy());
        QCOMPARE(service.thread().value(u"summary"_s).toString(),
                 page.value(u"summary"_s).toString());
        QVERIFY(!service.thread().contains(u"secret"_s));
        QCOMPARE(service.thread().value(u"assessmentDeliveryState"_s).toString(), u"unavailable"_s);
        QCOMPARE(service.thread().value(u"assessmentDeliveryReason"_s).toString(),
                 u"coordinator_unavailable"_s);
        QCOMPARE(service.thread().value(u"workState"_s).toString(), u"needs-information"_s);
        QVERIFY(service.thread().value(u"replyAllowed"_s).toBool());
        const auto replyId = service.createReplyDraft(parent, questionId, 1);
        QVERIFY(!replyId.isEmpty());
        QVERIFY(service.draft().value(u"isReply"_s).toBool());
        QCOMPARE(service.draft().value(u"parentSubmissionId"_s).toString(), parent);
        QCOMPARE(service.draft().value(u"questionText"_s).toString(),
                 question.value(u"description"_s).toString());
        QCOMPARE(service.draft().value(u"questionCode"_s).toString(), questionCode);
        QVERIFY(!service.updateDraft({{u"category"_s, u"suggestion"_s}}));
        QVERIFY(service.updateDraft({{u"description"_s, u"Late answer with exact steps."_s}}));
        QVERIFY(service.attachCrashReport(
            crashReportFixture(QDateTime::currentDateTimeUtc()).toVariantMap()));
        const auto preview = service.previewSubmission();
        QCOMPARE(preview.value(u"questionCode"_s).toString(), questionCode);
        const auto manifest = preview.value(u"manifest"_s).toString().toUtf8();
        const auto object = QJsonDocument::fromJson(manifest).object();
        QCOMPARE(object.value(u"submissionId"_s).toString(), replyId);
        QCOMPARE(object.value(u"parentSubmissionId"_s).toString(), parent);
        QCOMPARE(object.value(u"questionId"_s).toString(), questionId);
        QCOMPARE(object.value(u"questionRevision"_s).toInt(), 1);
        QCOMPARE(object.value(u"attachments"_s).toArray().size(), 1);
        QCOMPARE(preview.value(u"digest"_s).toString().toLatin1(),
                 feedback::digest("hexproof-feedback-reply-v2\n" + manifest));
        QVERIFY(service.confirmSubmission(preview.value(u"digest"_s).toString()));
        QTRY_COMPARE(service.draft().value(u"state"_s).toString(), u"accepted"_s);
        QCOMPARE(receiver.requests.last().path,
                 (u"/feedback/v2/submissions/"_s + parent + u"/replies/"_s + replyId).toUtf8());
        QCOMPARE(receiver.requests.last().headers.value("authorization"),
                 receiver.requests.first().headers.value("authorization"));
        QCOMPARE(receiver.requests.last().headers.value("x-feedback-digest"),
                 preview.value(u"digest"_s).toString().toLatin1());
        QVERIFY(receiver.requests.last().body.contains(
            service.m_records[replyId].attachments.first().bytes));
        QVERIFY(service.m_records[replyId].secret.isEmpty());
        QVERIFY(!preview.contains(u"authorizationNonce"_s));
        QVERIFY(
            !feedback::encode(service.m_records[replyId], false).contains(u"authorizationNonce"_s));
        QVERIFY(!QJsonDocument(feedback::encode(service.m_records[replyId], false))
                     .toJson()
                     .contains("secret"));
        QVERIFY(!service.requestRemoval(replyId));
        QTRY_VERIFY(!service.saving());
        const auto decoded = feedback::decode(feedback::encode(service.m_records[replyId], true));
        QVERIFY(decoded.has_value());
        QVERIFY(decoded->secret.isEmpty());
        QCOMPARE(decoded->question, question);
    }
    void threadPaginationKeepsOnlyCompleteSnapshot()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        FeedbackService service(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!service.saving());
        const auto parent = acceptedCase(service, receiver);
        const auto assessment = u"22222222-2222-4222-8222-222222222222"_s;
        int mode = 0;
        receiver.handler = [&, parent](const auto &request) {
            if (!request.path.contains("/thread")) {
                FeedbackReceiver::respond(request, 200, FeedbackReceiver::receipt(request));
                return;
            }
            if (mode == 2) {
                FeedbackReceiver::respond(request, 404);
                return;
            }
            const bool second = request.path.contains("cursor=");
            if (mode == 1 && second) {
                FeedbackReceiver::respond(request, 409, R"({"code":"thread_changed"})");
                return;
            }
            auto page = threadPage(parent, mode == 1 ? 3 : 2,
                                   second ? QJsonArray{threadItem(assessment, 1, u"assessment"_s)}
                                          : QJsonArray{threadItem(parent, 0, u"submission"_s)});
            if (!second)
                page.insert(u"nextCursor"_s, mode == 1 ? u"3:0"_s : u"2:0"_s);
            if (mode == 3)
                page.insert(u"assessmentDeliveryReason"_s, QString(81, u'x'));
            FeedbackReceiver::respond(request, 200,
                                      QJsonDocument(page).toJson(QJsonDocument::Compact));
        };
        QTRY_VERIFY(!service.saving());
        QVERIFY(service.refreshThread(parent));
        QTRY_VERIFY(!service.busy());
        QCOMPARE(service.thread().value(u"items"_s).toList().size(), 2);
        QCOMPARE(service.thread().value(u"revision"_s).toInt(), 2);
        QCOMPARE(receiver.requests.size(), 2);
        mode = 1;
        service.m_records[parent].threadNextAttempt = {};
        QVERIFY(service.refreshThread(parent));
        QTRY_VERIFY(!service.busy());
        QCOMPARE(service.thread().value(u"errorCode"_s).toString(), u"thread_changed"_s);
        QCOMPARE(service.thread().value(u"revision"_s).toInt(), 2);
        QCOMPARE(service.thread().value(u"items"_s).toList().size(), 2);
        mode = 3;
        service.m_records[parent].threadNextAttempt = {};
        QVERIFY(service.refreshThread(parent));
        QTRY_VERIFY(!service.busy());
        QCOMPARE(service.thread().value(u"errorCode"_s).toString(), u"response_invalid"_s);
        QCOMPARE(service.thread().value(u"revision"_s).toInt(), 2);
        mode = 2;
        service.m_records[parent].threadNextAttempt = {};
        QVERIFY(service.refreshThread(parent));
        QTRY_VERIFY(!service.busy());
        QCOMPARE(service.thread().value(u"errorCode"_s).toString(), u"thread_unsupported"_s);
        QVERIFY(!service.thread().value(u"replyAllowed"_s).toBool());
        QVERIFY(service.queryReceipt(parent));
        QTRY_VERIFY(!service.busy());
        QCOMPARE(service.m_records[parent].state, u"accepted"_s);
        QTRY_VERIFY(!service.saving());
    }
    void replyLostReceiptRecoversAfterRestartWithoutDuplicateUpload()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        receiver.handler = [](const auto &request) {
            if (request.method == "GET")
                FeedbackReceiver::respond(request, 200, FeedbackReceiver::receipt(request));
        };
        QString parent, replyId;
        {
            FeedbackService service(dir.path(), receiver.config(), true);
            QTRY_VERIFY(!service.saving());
            parent = acceptedCase(service, receiver);
            QTRY_VERIFY(!service.saving());
            replyId = service.createReplyDraft(parent);
            QVERIFY(!replyId.isEmpty());
            QVERIFY(service.updateDraft({{u"description"_s, u"Additional evidence"_s}}));
            QVERIFY(confirm(service));
            QTRY_COMPARE(receiver.requests.size(), 1);
            QTRY_VERIFY(!service.saving());
        }
        FeedbackService recovered(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!recovered.saving());
        QVERIFY(recovered.m_records.contains(replyId));
        QVERIFY(recovered.m_records[replyId].secret.isEmpty());
        QCOMPARE(recovered.m_records[replyId].parentId, parent);
        recovered.m_records[replyId].nextAttempt = {};
        recovered.pump();
        QTRY_COMPARE(recovered.m_records[replyId].state, u"accepted"_s);
        QCOMPARE(receiver.requests.size(), 2);
        QCOMPARE(receiver.requests.first().method, QByteArray("PUT"));
        QCOMPARE(receiver.requests.last().method, QByteArray("GET"));
        QCOMPARE(receiver.requests.first().path, receiver.requests.last().path);
        QCOMPARE(receiver.requests.first().headers.value("authorization"),
                 receiver.requests.last().headers.value("authorization"));
        QTRY_VERIFY(!recovered.saving());
    }
    void replyRevocationBindsOneConfirmationAcrossRestart_data()
    {
        QTest::addColumn<bool>("reconfirm");
        QTest::newRow("new-confirmation-survives-old-revocation") << true;
        QTest::newRow("old-confirmation-remains-revoked-after-crash") << false;
    }
    void replyRevocationBindsOneConfirmationAcrossRestart()
    {
        QFETCH(bool, reconfirm);
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        receiver.handler = [](const auto &request) {
            FeedbackReceiver::respond(request, 201, FeedbackReceiver::receipt(request));
        };
        QString replyId;
        QByteArray staleAuthorized;
        {
            FeedbackService service(dir.path(), receiver.config(), true);
            QTRY_VERIFY(!service.saving());
            const auto parent = acceptedCase(service, receiver);
            QTRY_VERIFY(!service.saving());
            replyId = service.createReplyDraft(parent);
            QVERIFY(service.updateDraft({{u"description"_s, u"First explicit confirmation"_s}}));
            QVERIFY(confirm(service));
            service.m_records[replyId].nextAttempt = QDateTime::currentDateTimeUtc().addDays(1);
            service.changedRecord(replyId);
            const auto oldNonce = service.m_records[replyId].authorizationNonce;
            QCOMPARE(oldNonce.size(), 32);
            staleAuthorized = QJsonDocument(feedback::encode(service.m_records[replyId], true))
                                  .toJson(QJsonDocument::Compact);
            QVERIFY(service.stop(replyId));
            QCOMPARE(service.m_records[replyId].state, u"draft"_s);
            QVERIFY(service.m_records[replyId].secret.isEmpty());
            if (reconfirm) {
                QVERIFY(
                    service.updateDraft({{u"description"_s, u"Second explicit confirmation"_s}}));
                QVERIFY(confirm(service));
                QVERIFY(service.m_records[replyId].authorizationNonce != oldNonce);
                QVERIFY(service.m_records[replyId].secret.isEmpty());
                service.m_records[replyId].nextAttempt = QDateTime::currentDateTimeUtc().addDays(1);
                service.changedRecord(replyId);
            }
            QTRY_VERIFY(!service.saving());
            QCOMPARE(receiver.requests.size(), 0);
        }
        if (!reconfirm)
            QVERIFY(feedback::writePrivate(dir.filePath(replyId + u".json"_s), staleAuthorized));
        FeedbackService recovered(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!recovered.saving());
        QVERIFY(recovered.m_records.contains(replyId));
        QCOMPARE(recovered.m_records[replyId].authorized, reconfirm);
        QVERIFY(recovered.m_records[replyId].secret.isEmpty());
        recovered.m_records[replyId].nextAttempt = {};
        recovered.pump();
        if (reconfirm) {
            QTRY_COMPARE(recovered.m_records[replyId].state, u"accepted"_s);
            QCOMPARE(receiver.requests.size(), 1);
            QCOMPARE(receiver.requests.first().method, QByteArray("PUT"));
        } else {
            QCOMPARE(recovered.m_records[replyId].reason, u"stopped"_s);
            QCOMPARE(receiver.requests.size(), 0);
        }
        QTRY_VERIFY(!recovered.saving());
    }
    void parentRevocationStopsQueuedReplyAcrossRestart_data()
    {
        QTest::addColumn<QString>("action");
        QTest::newRow("case-removal") << u"remove"_s;
        QTest::newRow("local-delete") << u"delete"_s;
        QTest::newRow("lost-capability") << u"lost"_s;
    }
    void parentRevocationStopsQueuedReplyAcrossRestart()
    {
        QFETCH(QString, action);
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        receiver.handler = [](const auto &request) {
            auto receipt = QJsonDocument::fromJson(FeedbackReceiver::receipt(request)).object();
            receipt.insert(u"removalState"_s, u"pending"_s);
            FeedbackReceiver::respond(request, 200,
                                      QJsonDocument(receipt).toJson(QJsonDocument::Compact));
        };
        QString parent, replyId;
        {
            FeedbackService service(dir.path(), receiver.config(), true);
            QTRY_VERIFY(!service.saving());
            parent = acceptedCase(service, receiver);
            QTRY_VERIFY(!service.saving());
            replyId = service.createReplyDraft(parent);
            QVERIFY(service.updateDraft({{u"description"_s, u"Queued reply"_s}}));
            QVERIFY(confirm(service));
            service.m_records[replyId].nextAttempt = QDateTime::currentDateTimeUtc().addDays(1);
            service.changedRecord(replyId);
            if (action == u"remove") {
                QVERIFY(service.requestRemoval(parent));
            } else if (action == u"delete") {
                QVERIFY(service.deleteRecord(parent));
            } else {
                // Simulate a capability becoming unavailable without retaining a
                // second copy in the child's durable record.
                service.m_records[parent].secret.clear();
                service.m_records[parent].manifest.clear();
                service.changedRecord(parent);
            }
            QTRY_VERIFY(!service.saving());
            QTRY_VERIFY(!service.busy());
            service.pump();
            QTRY_VERIFY(!service.m_records[replyId].authorized);
            QTRY_VERIFY(!service.saving());
        }
        FeedbackService recovered(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!recovered.saving());
        QVERIFY(recovered.m_records.contains(replyId));
        QVERIFY(!recovered.m_records[replyId].authorized);
        QVERIFY(recovered.m_records[replyId].secret.isEmpty());
        recovered.m_records[replyId].nextAttempt = {};
        recovered.pump();
        QVERIFY(recovered.createReplyDraft(parent).isEmpty());
        for (const auto &request : receiver.requests) {
            QVERIFY(request.method != "PUT");
            QVERIFY(!request.path.contains("/replies/"));
        }
    }
    void acceptedRepliesInheritCaseRemovalDespiteStaleLookup()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        receiver.handler = [](const auto &request) {
            if (request.method != "PUT")
                return;
            auto receipt = QJsonDocument::fromJson(FeedbackReceiver::receipt(request)).object();
            receipt.insert(u"publicationState"_s, u"published"_s);
            receipt.insert(u"issueUrl"_s, u"https://github.com/example/feedback/issues/1"_s);
            FeedbackReceiver::respond(request, 201,
                                      QJsonDocument(receipt).toJson(QJsonDocument::Compact));
        };
        QString parent, replyId;
        {
            FeedbackService service(dir.path(), receiver.config(), true);
            QTRY_VERIFY(!service.saving());
            parent = acceptedCase(service, receiver);
            QTRY_VERIFY(!service.saving());
            replyId = service.createReplyDraft(parent);
            QVERIFY(service.updateDraft({{u"description"_s, u"Published reply"_s}}));
            QVERIFY(confirm(service));
            QTRY_COMPARE(service.m_records[replyId].state, u"accepted"_s);
            QTRY_VERIFY(!service.saving());
            QVERIFY(service.queryReceipt(replyId));
            QTRY_COMPARE(receiver.requests.size(), 2);
            const auto pendingLookup = receiver.requests[1];
            QVERIFY(service.requestRemoval(parent));
            QCOMPARE(service.m_records[replyId].removalState, u"requested"_s);
            FeedbackReceiver::respond(pendingLookup, 200, FeedbackReceiver::receipt(pendingLookup));
            QTRY_COMPARE(receiver.requests.size(), 3);
            QCOMPARE(receiver.requests.last().method, QByteArray("DELETE"));
            QCOMPARE(service.m_records[replyId].removalState, u"requested"_s);
            auto removed =
                QJsonDocument::fromJson(FeedbackReceiver::receipt(receiver.requests.last()))
                    .object();
            removed.insert(u"removalState"_s, u"removed"_s);
            FeedbackReceiver::respond(receiver.requests.last(), 200,
                                      QJsonDocument(removed).toJson(QJsonDocument::Compact));
            QTRY_COMPARE(service.m_records[parent].removalState, u"removed"_s);
            QCOMPARE(service.m_records[replyId].removalState, u"removed"_s);
            QTRY_VERIFY(!service.saving());
        }
        FeedbackService recovered(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!recovered.saving());
        QCOMPARE(recovered.m_records[replyId].removalState, u"removed"_s);
        recovered.m_records[parent].acceptedAt = QDateTime::currentDateTimeUtc().addDays(-367);
        recovered.m_records[replyId].acceptedAt = QDateTime::currentDateTimeUtc().addDays(-366);
        recovered.m_records[parent].accessExpiresAt = QDateTime::currentDateTimeUtc().addDays(-1);
        recovered.m_records[replyId].accessExpiresAt = QDateTime::currentDateTimeUtc().addDays(-1);
        recovered.prune();
        QVERIFY(!recovered.m_records.contains(parent));
        QVERIFY(!recovered.m_records.contains(replyId));
        QTRY_VERIFY(!recovered.saving());
    }
    void threadAttachmentsUseReceiverIntegrityAndSurvivePayloadCleanup()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        const QByteArray content = R"({"schemaVersion":1,"public":"diagnostic"})";
        QString parent;
        const auto replyId = u"33333333-3333-4333-8333-333333333333"_s;
        bool corrupt = false;
        {
            FeedbackService service(dir.path(), receiver.config(), true);
            QTRY_VERIFY(!service.saving());
            parent = acceptedCase(service, receiver);
            auto rootItem = threadItem(parent, 0, u"submission"_s);
            auto replyItem = threadItem(replyId, 1, u"reply"_s);
            const auto hash = QString::fromLatin1(feedback::digest(content));
            const auto descriptor = [&](const QString &path) {
                return QJsonObject{
                    {u"id"_s, u"diagnostic"_s},
                    {u"kind"_s, u"hosting_diagnostics"_s},
                    {u"mediaType"_s, u"application/json"_s},
                    {u"byteLength"_s, content.size()},
                    {u"sha256"_s, hash},
                    {u"url"_s, receiver.base() + u"/assets/"_s + path + u"/diagnostic/"_s + hash}};
            };
            rootItem.insert(u"attachments"_s, QJsonArray{descriptor(parent)});
            replyItem.insert(u"attachments"_s,
                             QJsonArray{descriptor(parent + u"/replies/"_s + replyId)});
            const auto page = threadPage(parent, 1, {rootItem, replyItem});
            receiver.handler = [&, page](const auto &request) {
                FeedbackReceiver::respond(request, 200,
                                          request.path.contains("/thread")
                                              ? QJsonDocument(page).toJson(QJsonDocument::Compact)
                                          : corrupt ? QByteArray(content.size(), 'x')
                                                    : content);
            };
            QTRY_VERIFY(!service.saving());
            QVERIFY(service.refreshThread(parent));
            QTRY_VERIFY(!service.busy());
            service.m_records[parent].acceptedAt = QDateTime::currentDateTimeUtc().addDays(-31);
            service.prune();
            QVERIFY(!service.m_records[parent].payloadAvailable);
            QVERIFY(service.fetchThreadAttachment(parent, u"diagnostic"_s));
            QTRY_VERIFY(!service.busy());
            QVERIFY(service.threadAttachmentPreview()
                        .value(u"content"_s)
                        .toString()
                        .contains(u"diagnostic"));
            QVERIFY(!receiver.requests.last().headers.contains("authorization"));
            QVERIFY(service.fetchThreadAttachment(replyId, u"diagnostic"_s));
            QTRY_VERIFY(!service.busy());
            QVERIFY(receiver.requests.last().path.contains("/replies/"));
            QVERIFY(!receiver.requests.last().headers.contains("authorization"));
            corrupt = true;
            QVERIFY(service.fetchThreadAttachment(replyId, u"diagnostic"_s));
            QTRY_VERIFY(!service.busy());
            QCOMPARE(service.threadAttachmentPreview().value(u"errorCode"_s).toString(),
                     u"invalid_attachment"_s);
            QVERIFY(service.threadAttachmentPreview().value(u"content"_s).toString().isEmpty());
            auto items = service.m_records[parent].threadPage.value(u"items"_s).toArray();
            auto malicious = items[0].toObject();
            auto badAttachment = descriptor(parent);
            badAttachment.insert(u"url"_s, u"https://evil.invalid/exfiltrate"_s);
            malicious.insert(u"attachments"_s, QJsonArray{badAttachment});
            items[0] = malicious;
            service.m_records[parent].threadPage.insert(u"items"_s, items);
            const auto requests = receiver.requests.size();
            QVERIFY(!service.fetchThreadAttachment(parent, u"diagnostic"_s));
            QCOMPARE(service.errorCode(), u"endpoint_untrusted"_s);
            QCOMPARE(receiver.requests.size(), requests);
            service.changedRecord(parent);
            QTRY_VERIFY(!service.saving());
        }
        FeedbackService recovered(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!recovered.saving());
        QVERIFY(recovered.selectRecord(parent));
        QCOMPARE(recovered.thread().value(u"items"_s).toList().size(), 2);
        QVERIFY(!recovered.m_records[parent].payloadAvailable);
    }
    void threadCacheEvictionPreservesReceiptAuthority_data()
    {
        QTest::addColumn<bool>("expired");
        QTest::newRow("cache-expired") << true;
        QTest::newRow("storage-pressure") << false;
    }
    void threadCacheEvictionPreservesReceiptAuthority()
    {
        QFETCH(bool, expired);
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        receiver.handler = [](const auto &request) {
            FeedbackReceiver::respond(request, 200, FeedbackReceiver::receipt(request));
        };
        QString parent;
        {
            FeedbackService service(dir.path(), receiver.config(), true);
            QTRY_VERIFY(!service.saving());
            parent = acceptedCase(service, receiver);
            auto item = threadItem(parent, 0, u"submission"_s);
            item.insert(u"description"_s, QString(4000, u'x'));
            auto &record = service.m_records[parent];
            record.payloadAvailable = false;
            record.manifest.clear();
            record.threadPage = threadPage(parent, 1, {item});
            record.threadSyncedAt = QDateTime::currentDateTimeUtc().addDays(expired ? -31 : 0);
            service.changedRecord(parent);
            const auto before = service.payloadBytes();
            service.prune(expired ? 0 : feedback::MaxStoreBytes - before + 1);
            QVERIFY(service.payloadBytes() < before - 4000);
            QVERIFY(service.m_records[parent].threadPage.isEmpty());
            QVERIFY(!service.m_records[parent].threadSyncedAt.isValid());
            QCOMPARE(service.m_records[parent].secret.size(), 32);
            QTRY_VERIFY(!service.saving());
        }
        FeedbackService recovered(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!recovered.saving());
        QVERIFY(recovered.m_records[parent].threadPage.isEmpty());
        QCOMPARE(recovered.m_records[parent].secret.size(), 32);
        QVERIFY(recovered.queryReceipt(parent));
        QTRY_VERIFY(!recovered.busy());
        QCOMPARE(recovered.m_records[parent].state, u"accepted"_s);
        QCOMPARE(receiver.requests.size(), 1);
        QCOMPARE(receiver.requests.first().method, QByteArray("GET"));
        QTRY_VERIFY(!recovered.saving());
    }
    void threadRateLimitAndSelectionIsolation()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        FeedbackService service(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!service.saving());
        const auto first = acceptedCase(service, receiver);
        const auto second = acceptedCase(service, receiver);
        QTRY_VERIFY(!service.saving());
        QVERIFY(service.refreshThread(first));
        QTRY_COMPARE(receiver.requests.size(), 1);
        QVERIFY(service.selectRecord(second));
        FeedbackReceiver::respond(
            receiver.requests[0], 200,
            QJsonDocument(threadPage(first, 1, {threadItem(first, 0, u"submission"_s)}))
                .toJson(QJsonDocument::Compact));
        QTRY_VERIFY(!service.busy());
        QCOMPARE(service.thread().value(u"caseId"_s).toString(), second);
        QVERIFY(!service.thread().contains(u"items"_s));
        receiver.handler = [](const auto &request) {
            FeedbackReceiver::respond(request, 429, {}, "Retry-After: 600\r\n");
        };
        QVERIFY(service.refreshThread(second));
        QTRY_VERIFY(!service.busy());
        QCOMPARE(service.thread().value(u"errorCode"_s).toString(), u"rate_limited"_s);
        QVERIFY(service.m_records[second].threadNextAttempt >
                QDateTime::currentDateTimeUtc().addSecs(590));
        QVERIFY(!service.refreshThread(second));
        QCOMPARE(receiver.requests.size(), 2);
        QTRY_VERIFY(!service.saving());
    }
    void publicPreviewBindsContentAndNotice()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        FeedbackService service(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!service.saving());
        const auto id = service.createDraft();
        QVERIFY(service.updateDraft({{u"description"_s, u"Public report"_s}}));
        QVERIFY(!service.updateDraft({{u"replyEmail"_s, u"private@example.invalid"_s}}));
        QVERIFY(!service.submit());
        QCOMPARE(service.errorCode(), u"preview_required"_s);
        auto preview = service.previewSubmission();
        QCOMPARE(preview.value(u"noticeText"_s).toString(), service.noticeText());
        const auto manifest =
            QJsonDocument::fromJson(preview.value(u"manifest"_s).toString().toUtf8()).object();
        QCOMPARE(manifest.value(u"schemaVersion"_s).toInt(), 2);
        QVERIFY(!manifest.contains(u"replyEmail"_s));
        QCOMPARE(
            manifest.value(u"disclosure"_s).toObject().value(u"sha256"_s).toString().toLatin1(),
            feedback::digest(service.noticeText().toUtf8()));
        QVERIFY(!QJsonDocument::fromVariant(preview).toJson().contains("secret"));
        QVERIFY(service.updateDraft({{u"description"_s, u"Changed report"_s}}));
        QVERIFY(!service.confirmSubmission(preview.value(u"digest"_s).toString()));
        QCOMPARE(service.errorCode(), u"preview_changed"_s);
        QCOMPARE(receiver.requests.size(), 0);
        preview = service.previewSubmission();
        QVERIFY(!service.confirmSubmission(QString(64, u'0')));
        receiver.handler = [](const auto &r) {
            FeedbackReceiver::respond(r, 201, FeedbackReceiver::receipt(r));
        };
        QVERIFY(service.confirmSubmission(preview.value(u"digest"_s).toString()));
        QTRY_COMPARE(service.draft().value(u"state"_s).toString(), u"accepted"_s);
        QCOMPARE(service.m_records[id].manifest, preview.value(u"manifest"_s).toString().toUtf8());
        QCOMPARE(service.draft().value(u"publicationState"_s).toString(), u"pending"_s);
        QTRY_VERIFY(!service.saving());
    }
    void sharedPublicManifestFixture()
    {
        QFile manifestFile(
            QFINDTESTDATA("../../../testdata/feedback/v2/valid-no-attachments.json"));
        QFile contractFile(QFINDTESTDATA("../../../testdata/feedback/v2/contract.json"));
        QVERIFY(manifestFile.open(QIODevice::ReadOnly));
        QVERIFY(contractFile.open(QIODevice::ReadOnly));
        const auto raw = manifestFile.readAll();
        const auto manifest = QJsonDocument::fromJson(raw).object();
        const auto contract = QJsonDocument::fromJson(contractFile.readAll()).object();
        QCOMPARE(feedback::digest("hexproof-feedback-v2\n" + raw),
                 contract.value(u"manifestDigest"_s).toString().toLatin1());
        QCOMPARE(
            feedback::digest(contract.value(u"noticeText"_s).toString().toUtf8()),
            manifest.value(u"disclosure"_s).toObject().value(u"sha256"_s).toString().toLatin1());
        feedback::Record record;
        record.id = manifest.value(u"submissionId"_s).toString();
        record.frozenAt =
            QDateTime::fromString(manifest.value(u"createdAt"_s).toString(), Qt::ISODateWithMs);
        record.category = manifest.value(u"category"_s).toString();
        record.description = manifest.value(u"description"_s).toString();
        record.context = manifest.value(u"context"_s).toObject();
        record.disclosure = manifest.value(u"disclosure"_s).toObject();
        auto expected = manifest;
        expected.insert(u"createdAt"_s, record.frozenAt.toString(Qt::ISODateWithMs));
        QCOMPARE(feedback::manifest(record), expected);
    }
    void legacyPrivateRecordsNeverUploadOrMigrateSilently()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        feedback::Record old;
        old.id = u"83bd35d6-dd11-4a73-9f35-4ed43b6ab8b1"_s;
        old.apiVersion = 1;
        old.description = u"Previously private"_s;
        old.email = u"private@example.invalid"_s;
        old.endpoint = receiver.base().replace(u"/v2"_s, u"/v1"_s);
        old.state = u"queued"_s;
        old.authorized = true;
        old.secret = QByteArray(32, 's');
        old.draftCreated = old.frozenAt = QDateTime::currentDateTimeUtc();
        old.manifest = QJsonDocument(feedback::manifest(old)).toJson(QJsonDocument::Compact);
        auto encoded = feedback::encode(old, true);
        encoded.insert(u"schemaVersion"_s, 1);
        encoded.remove(u"apiVersion"_s);
        QVERIFY(feedback::writePrivate(dir.filePath(u"feedback/"_s + old.id + u".json"_s),
                                       QJsonDocument(encoded).toJson()));
        auto config = receiver.config();
        config.insert(u"receiptOnlyApiBases"_s, QJsonArray{old.endpoint});
        FeedbackService service(dir.path(), config, true);
        QTRY_VERIFY(!service.saving());
        QVERIFY(service.selectRecord(old.id));
        QVERIFY(!service.m_records[old.id].authorized);
        QVERIFY(!service.draft().value(u"isPublic"_s).toBool());
        QVERIFY(!service.draft().value(u"editable"_s).toBool());
        QVERIFY(service.previewSubmission().isEmpty());
        service.pump();
        QCOMPARE(receiver.requests.size(), 0);
        receiver.handler = [](const auto &r) {
            auto response = QJsonDocument::fromJson(FeedbackReceiver::receipt(r)).object();
            response.insert(u"schemaVersion"_s, 1);
            response.insert(u"state"_s, u"received"_s);
            FeedbackReceiver::respond(r, 200, QJsonDocument(response).toJson());
        };
        QVERIFY(service.queryReceipt(old.id));
        QTRY_COMPARE(service.draft().value(u"state"_s).toString(), u"received"_s);
        const auto copied = service.cloneDraft(old.id);
        QVERIFY(!copied.isEmpty());
        QVERIFY(service.draft().value(u"isPublic"_s).toBool());
        QVERIFY(service.m_records[copied].email.isEmpty());
        QVERIFY(service.m_records[copied].secret.isEmpty());
        QVERIFY(!service.m_records[copied].authorized);
        QVERIFY(!service.submit());
        QCOMPARE(receiver.requests.size(), 1);
        QTRY_VERIFY(!service.saving());
    }
    void removalIsDurableAndResumesWithoutUploading()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        QString id;
        QByteArray stale;
        receiver.handler = [](const auto &r) {
            if (r.method == "DELETE")
                FeedbackReceiver::respond(r, 503, "{}");
            else
                FeedbackReceiver::respond(r, 201, FeedbackReceiver::receipt(r));
        };
        {
            FeedbackService service(dir.path(), receiver.config(), true);
            QTRY_VERIFY(!service.saving());
            id = service.createDraft();
            QVERIFY(service.updateDraft({{u"description"_s, u"Remove public report"_s}}));
            QVERIFY(confirm(service));
            QTRY_COMPARE(service.draft().value(u"state"_s).toString(), u"accepted"_s);
            QTRY_VERIFY(!service.saving());
            stale = QJsonDocument(feedback::encode(service.m_records[id], true)).toJson();
            service.m_writing = true;
            QVERIFY(service.requestRemoval(id));
            QVERIFY(QFile::exists(dir.filePath(u"feedback/"_s + id + u".removal"_s)));
        }
        QVERIFY(feedback::writePrivate(dir.filePath(u"feedback/"_s + id + u".json"_s), stale));
        receiver.handler = [](const auto &r) {
            auto receipt = QJsonDocument::fromJson(FeedbackReceiver::receipt(r)).object();
            receipt.insert(u"removalState"_s, u"removed"_s);
            FeedbackReceiver::respond(r, 200, QJsonDocument(receipt).toJson());
        };
        FeedbackService recovered(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!recovered.saving());
        recovered.selectRecord(id);
        recovered.pump();
        QTRY_COMPARE(recovered.draft().value(u"removalState"_s).toString(), u"removed"_s);
        QCOMPARE(receiver.requests.size(), 2);
        QCOMPARE(receiver.requests.last().method, QByteArray("DELETE"));
        QCOMPARE(receiver.requests.first().headers.value("authorization"),
                 receiver.requests.last().headers.value("authorization"));
        QVERIFY(!recovered.m_records[id].removalAuthorized);
        QVERIFY(!QJsonDocument::fromVariant(recovered.draft()).toJson().contains("secret"));
        QTRY_VERIFY(!recovered.saving());
    }
    void pendingLookupDoesNotPostponeOrRevokeNewRemoval_data()
    {
        QTest::addColumn<QString>("previousRemovalState");
        QTest::addColumn<int>("lookupStatus");
        QTest::newRow("first-removal") << u"none"_s << 200;
        QTest::newRow("retry-stalled-removal") << u"stalled"_s << 200;
        QTest::newRow("lookup-throttled") << u"none"_s << 429;
    }
    void pendingLookupDoesNotPostponeOrRevokeNewRemoval()
    {
        QFETCH(QString, previousRemovalState);
        QFETCH(int, lookupStatus);
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        receiver.handler = [](const auto &request) {
            if (request.method == "GET")
                return;
            auto receipt = QJsonDocument::fromJson(FeedbackReceiver::receipt(request)).object();
            if (request.method == "DELETE")
                receipt.insert(u"removalState"_s, u"removed"_s);
            FeedbackReceiver::respond(request, request.method == "PUT" ? 201 : 200,
                                      QJsonDocument(receipt).toJson());
        };
        FeedbackService service(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!service.saving());
        const auto id = service.createDraft();
        QVERIFY(service.updateDraft({{u"description"_s, u"Remove while status is loading"_s}}));
        QVERIFY(confirm(service));
        QTRY_COMPARE(service.draft().value(u"state"_s).toString(), u"accepted"_s);
        QTRY_VERIFY(!service.saving());
        service.m_records[id].removalState = previousRemovalState;
        service.m_records[id].queries = 9;
        service.m_records[id].nextAttempt = QDateTime::currentDateTimeUtc();
        service.pump();
        QTRY_COMPARE(receiver.requests.size(), 2);
        QCOMPARE(receiver.requests[1].method, QByteArray("GET"));
        QTRY_VERIFY(!service.saving());
        QVERIFY(service.busy());
        QVERIFY(service.requestRemoval(id));
        QTRY_VERIFY(!service.saving());
        auto oldReceipt =
            QJsonDocument::fromJson(FeedbackReceiver::receipt(receiver.requests[1])).object();
        oldReceipt.insert(u"removalState"_s, previousRemovalState);
        FeedbackReceiver::respond(receiver.requests[1], lookupStatus,
                                  QJsonDocument(oldReceipt).toJson(), "Retry-After: 3600\r\n");
        if (lookupStatus == 429) {
            QTRY_VERIFY(!service.busy() && !service.saving());
            QVERIFY(service.m_records[id].removalAuthorized);
            QVERIFY(service.m_records[id].nextAttempt >
                    QDateTime::currentDateTimeUtc().addSecs(3500));
            service.pump();
            QCOMPARE(receiver.requests.size(), 2);
            service.m_records[id].nextAttempt = QDateTime::currentDateTimeUtc();
            service.pump();
        }
        QTRY_COMPARE_WITH_TIMEOUT(receiver.requests.size(), 3, 2000);
        QCOMPARE(receiver.requests.last().method, QByteArray("DELETE"));
        QTRY_COMPARE(service.draft().value(u"removalState"_s).toString(), u"removed"_s);
        QCOMPARE(service.m_records[id].removalAttempts, 1);
        QVERIFY(!service.m_records[id].removalAuthorized);
        QTRY_VERIFY(!service.saving());
    }
    void publicationStatusRejectsUntrustedIssueLinks_data()
    {
        QTest::addColumn<QString>("invalidUrl");
        QTest::newRow("wrong-repository") << u"https://github.com/other/repository/issues/1"_s;
        QTest::newRow("missing-mapping") << QString{};
    }
    void publicationStatusRejectsUntrustedIssueLinks()
    {
        QFETCH(QString, invalidUrl);
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        receiver.handler = [invalidUrl](const auto &r) {
            auto receipt = QJsonDocument::fromJson(FeedbackReceiver::receipt(r)).object();
            receipt.insert(u"publicationState"_s, u"published"_s);
            receipt.insert(u"issueUrl"_s, invalidUrl);
            FeedbackReceiver::respond(r, 201, QJsonDocument(receipt).toJson());
        };
        FeedbackService service(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!service.saving());
        const auto id = service.createDraft();
        QVERIFY(service.updateDraft({{u"description"_s, u"Validate issue destination"_s}}));
        QVERIFY(confirm(service));
        QTRY_COMPARE(service.draft().value(u"reason"_s).toString(), u"response_invalid"_s);
        QVERIFY(service.draft().value(u"issueUrl"_s).toString().isEmpty());
        receiver.handler = [](const auto &r) {
            auto receipt = QJsonDocument::fromJson(FeedbackReceiver::receipt(r)).object();
            receipt.insert(u"publicationState"_s, u"published"_s);
            receipt.insert(u"issueUrl"_s, u"https://github.com/example/feedback/issues/42"_s);
            FeedbackReceiver::respond(r, 200, QJsonDocument(receipt).toJson());
        };
        QVERIFY(service.queryReceipt(id));
        QTRY_COMPARE(service.draft().value(u"publicationState"_s).toString(), u"published"_s);
        QCOMPARE(service.draft().value(u"issueUrl"_s).toString(),
                 u"https://github.com/example/feedback/issues/42"_s);
        QTRY_VERIFY(!service.saving());
        service.pump();
        QCOMPARE(receiver.requests.size(), 2);
    }
    void partialPublicationContinuesPolling()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        receiver.handler = [&receiver](const auto &r) {
            if (receiver.requests.size() == 2) {
                FeedbackReceiver::respond(r, 200, "{}");
                return;
            }
            auto receipt = QJsonDocument::fromJson(FeedbackReceiver::receipt(r)).object();
            receipt.insert(u"publicationState"_s,
                           r.method == "PUT" ? u"partial"_s : u"published"_s);
            receipt.insert(u"issueUrl"_s, u"https://github.com/example/feedback/issues/42"_s);
            FeedbackReceiver::respond(r, r.method == "PUT" ? 201 : 200,
                                      QJsonDocument(receipt).toJson());
        };
        FeedbackService service(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!service.saving());
        const auto id = service.createDraft();
        QVERIFY(service.updateDraft({{u"description"_s, u"Recover partial publication"_s}}));
        QVERIFY(confirm(service));
        QTRY_COMPARE(service.draft().value(u"publicationState"_s).toString(), u"partial"_s);
        QTRY_VERIFY(!service.saving());
        service.m_records[id].nextAttempt = QDateTime::currentDateTimeUtc();
        service.pump();
        QTRY_COMPARE(service.draft().value(u"reason"_s).toString(), u"response_invalid"_s);
        QTRY_VERIFY(!service.saving());
        QCOMPARE(service.draft().value(u"state"_s).toString(), u"accepted"_s);
        QCOMPARE(service.draft().value(u"publicationState"_s).toString(), u"partial"_s);
        service.pump();
        QCOMPARE(receiver.requests.size(), 2);
        QVERIFY(service.m_records[id].nextAttempt > QDateTime::currentDateTimeUtc().addSecs(290));
        service.m_records[id].nextAttempt = QDateTime::currentDateTimeUtc();
        service.pump();
        QTRY_COMPARE(service.draft().value(u"publicationState"_s).toString(), u"published"_s);
        QCOMPARE(receiver.requests.size(), 3);
        QCOMPARE(receiver.requests.last().method, QByteArray("GET"));
        QTRY_VERIFY(!service.saving());
    }
    void removalRetryIsBoundedAndSurvivesRestart()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        receiver.handler = [](const auto &r) {
            if (r.method == "DELETE")
                FeedbackReceiver::respond(r, 503, "{}", "Retry-After: 3600\r\n");
            else
                FeedbackReceiver::respond(r, 201, FeedbackReceiver::receipt(r));
        };
        QString id;
        QDateTime nextAttempt;
        {
            FeedbackService service(dir.path(), receiver.config(), true);
            QTRY_VERIFY(!service.saving());
            id = service.createDraft();
            QVERIFY(service.updateDraft({{u"description"_s, u"Retry removal"_s}}));
            QVERIFY(confirm(service));
            QTRY_COMPARE(service.draft().value(u"state"_s).toString(), u"accepted"_s);
            QTRY_VERIFY(!service.saving());
            QVERIFY(service.requestRemoval(id));
            QTRY_COMPARE(receiver.requests.size(), 2);
            QTRY_VERIFY(!service.busy() && !service.saving());
            QVERIFY(service.m_records[id].removalAuthorized);
            QCOMPARE(service.m_records[id].removalAttempts, 1);
            nextAttempt = service.m_records[id].nextAttempt;
            QVERIFY(nextAttempt > QDateTime::currentDateTimeUtc().addSecs(3500));
        }
        FeedbackService service(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!service.saving());
        QCOMPARE(service.m_records[id].nextAttempt, nextAttempt);
        service.pump();
        QCOMPARE(receiver.requests.size(), 2);
        service.m_records[id].removalAttempts = 20;
        service.m_records[id].nextAttempt = QDateTime::currentDateTimeUtc();
        service.pump();
        QCOMPARE(service.m_records[id].removalState, u"stalled"_s);
        QVERIFY(!service.m_records[id].removalAuthorized);
        QCOMPARE(receiver.requests.size(), 2);
        QTRY_VERIFY(!service.saving());
    }
    void configurationErrorSurvivesDraftOperations_data()
    {
        QTest::addColumn<QJsonObject>("configuration");
        QTest::addColumn<QString>("configurationError");
        QTest::newRow("disabled-v2")
            << QJsonObject{{u"schemaVersion"_s, 2}, {u"enabled"_s, false}} << QString{};
        QTest::newRow("legacy-v1") << disabledConfig() << QString{};
        QTest::newRow("invalid-schema")
            << QJsonObject{{u"schemaVersion"_s, 99}, {u"enabled"_s, true}}
            << u"configuration_invalid"_s;
        QTest::newRow("invalid-v2") << QJsonObject{{u"schemaVersion"_s, 2}, {u"enabled"_s, true}}
                                    << u"configuration_invalid"_s;
    }
    void configurationErrorSurvivesDraftOperations()
    {
        QFETCH(QJsonObject, configuration);
        QFETCH(QString, configurationError);
        QTemporaryDir dir;
        QString id;
        {
            FeedbackService service(dir.path(), configuration);
            QTRY_VERIFY(!service.saving());
            QVERIFY(!service.enabled());
            QCOMPARE(service.configurationErrorCode(), configurationError);
            QCOMPARE(service.errorCode(), configurationError);
            id = service.createDraft();
            QVERIFY(!id.isEmpty());
            QVERIFY(service.errorCode().isEmpty());
            QVERIFY(service.updateDraft({{u"description"_s, u"Keep this local draft"_s}}));
            QVERIFY(!confirm(service));
            QCOMPARE(service.errorCode(), u"disabled"_s);
            QCOMPARE(service.configurationErrorCode(), configurationError);
            QVERIFY(!service.createDraft().isEmpty());
            QVERIFY(service.selectRecord(id));
            QVERIFY(service.errorCode().isEmpty());
            QCOMPARE(service.configurationErrorCode(), configurationError);
            QTRY_VERIFY(!service.saving());

            const auto path = dir.filePath(u"export.json"_s);
            QVERIFY(service.exportRecord(id, QUrl::fromLocalFile(path)));
            QTRY_COMPARE(service.operationCode(), u"exported"_s);
            QCOMPARE(service.configurationErrorCode(), configurationError);
            QFile file(path);
            QVERIFY(file.open(QIODevice::ReadOnly));
            QVERIFY(file.readAll().contains("Keep this local draft"));
        }
        FeedbackService restored(dir.path(), configuration);
        QTRY_VERIFY(!restored.saving());
        QVERIFY(restored.selectRecord(id));
        QVERIFY(restored.errorCode().isEmpty());
        QCOMPARE(restored.configurationErrorCode(), configurationError);
        QCOMPARE(restored.draft().value(u"description"_s).toString(), u"Keep this local draft"_s);
    }
    void draftRestoresAndExportsWithoutSecrets()
    {
        QTemporaryDir dir;
        QString id;
        {
            FeedbackService service(dir.path(), disabledConfig());
            QTRY_VERIFY(!service.saving());
            QVERIFY(!service.enabled());
            id = service.createDraft({{u"feature"_s, u"forge_table"_s},
                                      {u"roomId"_s, u"SECRET"_s},
                                      {u"runtimeId"_s, u"/private/path"_s}});
            QVERIFY(!id.isEmpty());
            QVERIFY(service.updateDraft({{u"description"_s, u"A problem"_s}}));
            QVERIFY(!confirm(service));
            QCOMPARE(service.errorCode(), u"disabled"_s);
            QTRY_VERIFY(!service.saving());
        }
        FeedbackService restored(dir.path(), disabledConfig());
        QTRY_VERIFY(!restored.saving());
        QCOMPARE(restored.records().size(), 1);
        QVERIFY(restored.selectRecord(id));
        QCOMPARE(restored.draft().value(u"description"_s).toString(), u"A problem"_s);
        const auto context = restored.draft().value(u"context"_s).toMap();
        QVERIFY(!context.contains(u"roomId"_s));
        QVERIFY(!context.contains(u"runtimeId"_s));
        const auto path = dir.filePath(u"export.json"_s);
        QVERIFY(restored.exportRecord(id, QUrl::fromLocalFile(path)));
        QTRY_COMPARE(restored.operationCode(), u"exported"_s);
        QFile file(path);
        QVERIFY(file.open(QIODevice::ReadOnly));
        const auto bytes = file.readAll();
        QVERIFY(!bytes.contains("secret"));
        QVERIFY(!bytes.contains("endpoint"));
        QVERIFY(bytes.contains("A problem"));
    }
    void sendRequiresSavedFrozenContentAndUsesReceipt()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        receiver.handler = [](const auto &r) {
            FeedbackReceiver::respond(r, 201, FeedbackReceiver::receipt(r));
        };
        FeedbackService service(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!service.saving());
        const auto id = service.createDraft();
        QVERIFY(service.updateDraft({{u"description"_s, u"Real test description"_s}}));
        service.m_records[id].draftCreated = QDateTime::currentDateTimeUtc().addDays(-30);
        QVERIFY(confirm(service));
        QVERIFY(!service.updateDraft({{u"description"_s, u"mutated"_s}}));
        QTRY_COMPARE(service.draft().value(u"state"_s).toString(), u"accepted"_s);
        QCOMPARE(receiver.requests.size(), 1);
        const auto request = receiver.requests.first();
        QCOMPARE(request.method, QByteArray("PUT"));
        QCOMPARE(request.path, QString(u"/feedback/v2/submissions/"_s + id).toLatin1());
        QCOMPARE(request.headers.value("authorization"),
                 "Feedback " + service.m_records[id].secret.toBase64(
                                   QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals));
        QCOMPARE(request.headers.value("x-feedback-digest"),
                 feedback::digest("hexproof-feedback-v2\n" + service.m_records[id].manifest));
        QVERIFY(request.body.contains(service.m_records[id].manifest));
        QVERIFY(!request.body.contains("mutated"));
        QVERIFY(service.m_records[id].frozenAt > QDateTime::currentDateTimeUtc().addSecs(-10));
        QVERIFY(!QJsonDocument::fromVariant(service.draft()).toJson().contains("secret"));
        QTRY_VERIFY(!service.saving());
    }
    void stoppedUnknownSubmissionDoesNotUploadAfterRestartOr404()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        QString id;
        {
            FeedbackService service(dir.path(), receiver.config(), true);
            QTRY_VERIFY(!service.saving());
            id = service.createDraft();
            service.updateDraft({{u"description"_s, u"Stop after dispatch"_s}});
            QVERIFY(confirm(service));
            QTRY_COMPARE(receiver.requests.size(), 1);
            QVERIFY(service.stop(id));
            QTRY_VERIFY(!service.saving());
            QVERIFY(!service.m_records[id].authorized);
        }
        receiver.handler = [](const auto &r) { FeedbackReceiver::respond(r, 404, "{}"); };
        FeedbackService restored(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!restored.saving());
        QVERIFY(restored.selectRecord(id));
        QVERIFY(!restored.m_records[id].authorized);
        QVERIFY(restored.queryReceipt(id));
        QTRY_COMPARE(receiver.requests.size(), 2);
        QTRY_VERIFY(!restored.busy());
        QCOMPARE(receiver.requests.last().method, QByteArray("GET"));
        restored.pump();
        QTest::qWait(80);
        QCOMPARE(receiver.requests.size(), 2);
    }
    void deleteDuringRequestCannotResurrect()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        QString id;
        {
            FeedbackService service(dir.path(), receiver.config(), true);
            QTRY_VERIFY(!service.saving());
            id = service.createDraft();
            service.updateDraft({{u"description"_s, u"Delete in flight"_s}});
            confirm(service);
            QTRY_COMPARE(receiver.requests.size(), 1);
            QVERIFY(service.deleteRecord(id));
            FeedbackReceiver::respond(receiver.requests.first(), 201,
                                      FeedbackReceiver::receipt(receiver.requests.first()));
            QTRY_VERIFY(!service.saving());
            QCOMPARE(service.records().size(), 0);
        }
        FeedbackService restored(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!restored.saving());
        QCOMPARE(restored.records().size(), 0);
    }
    void lostReceiptRecoveredByGetWithoutSecondUpload()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        QString id;
        {
            FeedbackService service(dir.path(), receiver.config(), true);
            QTRY_VERIFY(!service.saving());
            id = service.createDraft();
            service.updateDraft({{u"description"_s, u"Lost first receipt"_s}});
            confirm(service);
            QTRY_COMPARE(receiver.requests.size(), 1);
            QTRY_VERIFY(!service.saving());
        }
        receiver.handler = [](const auto &r) {
            FeedbackReceiver::respond(r, 200, FeedbackReceiver::receipt(r));
        };
        FeedbackService restored(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!restored.saving());
        restored.selectRecord(id);
        restored.m_records[id].nextAttempt = QDateTime::currentDateTimeUtc();
        restored.pump();
        QTRY_COMPARE(restored.draft().value(u"state"_s).toString(), u"accepted"_s);
        QCOMPARE(receiver.requests.size(), 2);
        QCOMPARE(receiver.requests.last().method, QByteArray("GET"));
    }
    void stopBeforeDispatchAndMigrationPreserveConsent()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        QString id;
        {
            FeedbackService service(dir.path(), receiver.config(), true);
            QTRY_VERIFY(!service.saving());
            id = service.createDraft();
            service.updateDraft({{u"description"_s, u"Queued"_s}});
            QVERIFY(confirm(service));
            QVERIFY(service.stop(id));
            QTRY_VERIFY(!service.saving());
            QCOMPARE(service.draft().value(u"state"_s).toString(), u"draft"_s);
            QCOMPARE(receiver.requests.size(), 0);
            service.m_timer.stop();
            confirm(service);
            service.m_storageFailed = true;
        }
        FeedbackReceiver changed;
        auto config = changed.config();
        config.insert(u"receiptOnlyApiBases"_s, QJsonArray{receiver.base()});
        FeedbackService restored(dir.path(), config, true);
        QTRY_VERIFY(!restored.saving());
        restored.selectRecord(id);
        QVERIFY(!restored.m_records[id].authorized);
        QCOMPARE(restored.draft().value(u"reason"_s).toString(), u"endpoint_changed"_s);
        const auto copy = restored.cloneDraft(id);
        QVERIFY(copy != id);
        QVERIFY(restored.m_records[copy].secret.isEmpty());
        QCOMPARE(changed.requests.size(), 0);
        QCOMPARE(receiver.requests.size(), 0);
    }
    void redirectsAndOversizedResponsesAreRejected()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver, other;
        receiver.handler = [&](const auto &r) {
            FeedbackReceiver::respond(r, 307, {}, "Location: " + other.base().toLatin1() + "\r\n");
        };
        FeedbackService service(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!service.saving());
        service.createDraft();
        service.updateDraft({{u"description"_s, u"Redirect"_s}});
        confirm(service);
        QTRY_COMPARE(service.draft().value(u"state"_s).toString(), u"needs_attention"_s);
        QCOMPARE(other.requests.size(), 0);
        receiver.handler = [](const auto &r) {
            FeedbackReceiver::respond(r, 200, QByteArray(9000, 'x'));
        };
        service.createDraft();
        service.updateDraft({{u"description"_s, u"Oversized response"_s}});
        confirm(service);
        QTRY_COMPARE(service.draft().value(u"reason"_s).toString(), u"response_invalid"_s);
    }
    void attachmentsFrozenSanitizedAndImagesStripped()
    {
        QTemporaryDir dir;
        FeedbackService service(dir.path(), disabledConfig());
        QTRY_VERIFY(!service.saving());
        service.createDraft();
        auto report = crashReportFixture(QDateTime::currentDateTimeUtc());
        report.insert(u"privateDeck"_s, u"SECRET"_s);
        QVERIFY(service.attachCrashReport(report.toVariantMap()));
        auto attachments = service.draft().value(u"attachments"_s).toList();
        const auto crashId = attachments.first().toMap().value(u"id"_s).toString();
        QVERIFY(!service.attachmentPreview(crashId).contains(u"SECRET"));
        QVERIFY(!service.attachCrashReport(report.toVariantMap()));
        QCOMPARE(service.errorCode(), u"attachment_limit"_s);
        QImage image(40, 40, QImage::Format_RGB32);
        image.fill(Qt::red);
        image.setText(u"private"_s, u"SECRET"_s);
        const auto path = dir.filePath(u"image.png"_s);
        QVERIFY(image.save(path));
        QVERIFY(service.attachImage(QUrl::fromLocalFile(path)));
        QTRY_VERIFY(!service.busy());
        attachments = service.draft().value(u"attachments"_s).toList();
        QCOMPARE(attachments.size(), 2);
        const auto imageId = attachments.last().toMap().value(u"id"_s).toString();
        const auto preview = service.attachmentPreview(imageId);
        const auto bytes =
            QByteArray::fromBase64(preview.mid(preview.indexOf(u',') + 1).toLatin1());
        QVERIFY(!bytes.contains("SECRET"));
        QVERIFY(!QImage::fromData(bytes).isNull());
        QVERIFY(!service.attachImage(QUrl(u"https://example.invalid/image.png"_s)));
        QTRY_VERIFY(!service.saving());
    }
    void imageDimensionsMatchReceiverLimits_data()
    {
        QTest::addColumn<QSize>("size");
        QTest::addColumn<bool>("accepted");
        QTest::newRow("decimal-16mp-boundary") << QSize(4000, 4000) << true;
        QTest::newRow("binary-16mp-rejected") << QSize(4096, 4096) << false;
        QTest::newRow("dimension-limit-rejected") << QSize(8193, 1) << false;
    }
    void imageDimensionsMatchReceiverLimits()
    {
        QFETCH(QSize, size);
        QFETCH(bool, accepted);
        QTemporaryDir dir;
        FeedbackService service(dir.path(), disabledConfig());
        QTRY_VERIFY(!service.saving());
        QVERIFY(!service.createDraft().isEmpty());
        QImage image(size, QImage::Format_RGB32);
        image.fill(Qt::red);
        const auto path = dir.filePath(u"boundary.png"_s);
        QVERIFY(image.save(path));
        QVERIFY(QFileInfo(path).size() < feedback::MaxImageBytes);
        QVERIFY(service.attachImage(QUrl::fromLocalFile(path)));
        QTRY_VERIFY(!service.busy());
        const auto attachments = service.draft().value(u"attachments"_s).toList();
        QCOMPARE(attachments.size(), accepted ? 1 : 0);
        if (accepted) {
            QVERIFY(service.errorCode().isEmpty());
            const auto &stored = service.m_records[service.m_selected].attachments.first();
            QCOMPARE(QImage::fromData(stored.bytes).size(), size);
            QCOMPARE(stored.descriptor.value(u"mediaType"_s).toString(), u"image/png"_s);
        } else {
            QCOMPARE(service.errorCode(), u"image_too_large"_s);
        }
        QTRY_VERIFY(!service.saving());
    }
    void largeImagesAreNormalizedBeforeApplyingUploadLimit_data()
    {
        QTest::addColumn<QByteArray>("format");
        QTest::addColumn<bool>("transparent");
        QTest::newRow("png-larger-than-upload-limit") << QByteArray("PNG") << false;
        QTest::newRow("png-preserves-transparency") << QByteArray("PNG") << true;
        QTest::newRow("jpeg-expands-when-normalized") << QByteArray("JPEG") << false;
    }
    void largeImagesAreNormalizedBeforeApplyingUploadLimit()
    {
        QFETCH(QByteArray, format);
        QFETCH(bool, transparent);
        QTemporaryDir dir;
        FeedbackService service(dir.path(), disabledConfig());
        QTRY_VERIFY(!service.saving());
        const auto id = service.createDraft();
        QVERIFY(!id.isEmpty());
        QImage image(1200, 1000, transparent ? QImage::Format_ARGB32 : QImage::Format_RGB32);
        quint32 random = 0x12345678;
        for (int y = 0; y < image.height(); ++y) {
            auto *row = reinterpret_cast<QRgb *>(image.scanLine(y));
            for (int x = 0; x < image.width(); ++x) {
                random ^= random << 13;
                random ^= random >> 17;
                random ^= random << 5;
                row[x] = (transparent ? 0x80000000 : 0xff000000) | (random & 0x00ffffff);
            }
        }
        image.setText(u"private"_s, u"PRIVATE_IMAGE_METADATA"_s);
        image.setColorSpace(QColorSpace::SRgb);
        const auto path = dir.filePath(u"source.image"_s);
        QVERIFY(image.save(path, format.constData(), 90));
        QFile source(path);
        QVERIFY(source.open(QIODevice::ReadOnly));
        const auto original = source.readAll();
        QVERIFY(original.size() < feedback::MaxImageInputBytes);
        QCOMPARE(original.size() > feedback::MaxImageBytes, format == "PNG");
        QVERIFY(service.attachImage(QUrl::fromLocalFile(path)));
        QTRY_VERIFY_WITH_TIMEOUT(!service.busy(), 30000);
        QVERIFY2(service.errorCode().isEmpty(), qPrintable(service.errorCode()));
        QCOMPARE(service.m_records[id].attachments.size(), 1);
        const auto &stored = service.m_records[id].attachments.first();
        QVERIFY(stored.bytes.size() <= feedback::MaxImageBytes);
        QCOMPARE(stored.descriptor.value(u"mediaType"_s).toString(), u"image/png"_s);
        QCOMPARE(stored.descriptor.value(u"byteLength"_s).toInteger(), stored.bytes.size());
        QCOMPARE(stored.descriptor.value(u"sha256"_s).toString(),
                 QString::fromLatin1(feedback::digest(stored.bytes)));
        const auto normalized = QImage::fromData(stored.bytes, "PNG");
        QVERIFY(!normalized.isNull());
        QVERIFY(normalized.width() < image.width());
        QVERIFY(normalized.height() < image.height());
        QVERIFY(qAbs(double(normalized.width()) / normalized.height() - 1.2) < 0.01);
        QVERIFY(normalized.textKeys().isEmpty());
        QVERIFY(!normalized.colorSpace().isValid());
        QCOMPARE(qAlpha(normalized.pixel(normalized.width() / 2, normalized.height() / 2)),
                 transparent ? 128 : 255);
        QVERIFY(!stored.bytes.contains("PRIVATE_IMAGE_METADATA"));
        const auto preview = service.attachmentPreview(stored.descriptor.value(u"id"_s).toString());
        QCOMPARE(QByteArray::fromBase64(preview.mid(preview.indexOf(u',') + 1).toLatin1()),
                 stored.bytes);
        source.seek(0);
        QCOMPARE(source.readAll(), original);
        QTRY_VERIFY(!service.saving());
    }
    void oversizedImageInputHasSizeError()
    {
        QTemporaryDir dir;
        FeedbackService service(dir.path(), disabledConfig());
        QTRY_VERIFY(!service.saving());
        QVERIFY(!service.createDraft().isEmpty());
        QFile source(dir.filePath(u"oversized.png"_s));
        QVERIFY(source.open(QIODevice::WriteOnly));
        QVERIFY(source.resize(feedback::MaxImageInputBytes + 1));
        source.close();
        QVERIFY(service.attachImage(QUrl::fromLocalFile(source.fileName())));
        QTRY_VERIFY(!service.busy());
        QCOMPARE(service.errorCode(), u"image_too_large"_s);
        QVERIFY(service.draft().value(u"attachments"_s).toList().isEmpty());
    }
    void storageFailurePreventsDispatchAndLimitsDoNotEvict()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        FeedbackService service(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!service.saving());
        for (int i = 0; i < 20; ++i)
            QVERIFY(!service.createDraft().isEmpty());
        QVERIFY(service.createDraft().isEmpty());
        QCOMPARE(service.records().size(), 20);
        QTRY_VERIFY(!service.saving());
        service.updateDraft({{u"description"_s, u"Storage fault"_s}});
        service.m_storageFailed = true;
        QVERIFY(!confirm(service));
        QCOMPARE(service.errorCode(), u"storage_unavailable"_s);
        QCOMPARE(receiver.requests.size(), 0);
    }
    void productionConfigurationRejectsLoopbackHttp()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        FeedbackService service(dir.path(), receiver.config());
        QTRY_VERIFY(!service.saving());
        QVERIFY(!service.enabled());
        QCOMPARE(service.errorCode(), u"configuration_invalid"_s);
        QVERIFY(feedback::safeEndpoint(u"https://example.invalid/feedback/v2?token=x"_s, false)
                    .isEmpty());
        QVERIFY(
            feedback::safeEndpoint(u"https://user@example.invalid/feedback/v2"_s, false).isEmpty());
    }
    void revocationJournalWinsOverStaleAuthorizedRecord()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        QString id;
        QByteArray stale;
        {
            FeedbackService service(dir.path(), receiver.config(), true);
            QTRY_VERIFY(!service.saving());
            id = service.createDraft();
            service.updateDraft({{u"description"_s, u"Interrupted revocation"_s}});
            QVERIFY(confirm(service));
            QTRY_COMPARE(receiver.requests.size(), 1);
            stale = QJsonDocument(feedback::encode(service.m_records[id], true)).toJson();
            service.m_writing = true;
            QVERIFY(service.stop(id));
            QVERIFY(QFile::exists(dir.filePath(u"feedback/"_s + id + u".revoked"_s)));
        }
        QVERIFY(feedback::writePrivate(dir.filePath(u"feedback/"_s + id + u".json"_s), stale));
        FeedbackService recovered(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!recovered.saving());
        QVERIFY(!recovered.m_records[id].authorized);
        recovered.pump();
        QTest::qWait(80);
        QCOMPARE(receiver.requests.size(), 1);
    }

    void retryAfterSurvivesRestart()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        receiver.handler = [](const auto &request) {
            FeedbackReceiver::respond(request, 429, "{}", "Retry-After: 3600\r\n");
        };
        QString id;
        QDateTime retry;
        {
            FeedbackService service(dir.path(), receiver.config(), true);
            QTRY_VERIFY(!service.saving());
            id = service.createDraft();
            service.updateDraft({{u"description"_s, u"Respect retry-after"_s}});
            QVERIFY(confirm(service));
            QTRY_COMPARE(service.draft().value(u"state"_s).toString(), u"unconfirmed"_s);
            QTRY_VERIFY(!service.saving());
            retry = service.m_records[id].nextAttempt;
            QVERIFY(retry > QDateTime::currentDateTimeUtc().addSecs(3500));
        }
        FeedbackService recovered(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!recovered.saving());
        QVERIFY(recovered.m_records[id].nextAttempt >= retry);
        recovered.pump();
        QTest::qWait(50);
        QCOMPARE(receiver.requests.size(), 1);
    }

    void deletionJournalWinsOverStaleRecordAndFailureIsReported()
    {
        QTemporaryDir dir;
        QString id;
        QByteArray stale;
        {
            FeedbackService service(dir.path(), disabledConfig());
            QTRY_VERIFY(!service.saving());
            id = service.createDraft();
            service.updateDraft({{u"description"_s, u"Interrupted deletion"_s}});
            QTRY_VERIFY(!service.saving());
            stale = QJsonDocument(feedback::encode(service.m_records[id], true)).toJson();
            service.m_writing = true;
            QVERIFY(service.deleteRecord(id));
            QVERIFY(QFile::exists(dir.filePath(u"feedback/"_s + id + u".deleted"_s)));
        }
        QVERIFY(feedback::writePrivate(dir.filePath(u"feedback/"_s + id + u".json"_s), stale));
        FeedbackService recovered(dir.path(), disabledConfig());
        QTRY_VERIFY(!recovered.saving());
        QVERIFY(recovered.records().isEmpty());
        const auto next = recovered.createDraft();
        QTRY_VERIFY(!recovered.saving());
        QVERIFY(QDir().mkpath(dir.filePath(u"feedback/"_s + next + u".deleted"_s)));
        QVERIFY(!recovered.deleteRecord(next));
        QCOMPARE(recovered.errorCode(), u"storage_unavailable"_s);
        QCOMPARE(recovered.records().size(), 1);
    }

    void finalUploadStillQueriesReceipt_data()
    {
        QTest::addColumn<int>("queryStatus");
        QTest::newRow("accepted-final-upload") << 200;
        QTest::newRow("missing-final-upload") << 404;
        QTest::newRow("query-budget-exhausted") << 503;
    }
    void finalUploadStillQueriesReceipt()
    {
        QFETCH(int, queryStatus);
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        receiver.handler = [queryStatus](const auto &request) {
            if (request.method == "PUT")
                FeedbackReceiver::respond(request, 503, "{}");
            else
                FeedbackReceiver::respond(request, queryStatus,
                                          queryStatus == 200 ? FeedbackReceiver::receipt(request)
                                                             : QByteArray("{}"));
        };
        FeedbackService service(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!service.saving());
        const auto id = service.createDraft();
        QVERIFY(service.updateDraft({{u"description"_s, u"Recover final upload receipt"_s}}));
        QVERIFY(confirm(service));
        // Restore the state immediately before the last permitted upload and
        // receipt query. Their independent budgets must each remain usable.
        service.m_records[id].attempts = 19;
        service.m_records[id].queries = 39;
        service.changedRecord(id);
        QTRY_COMPARE(service.draft().value(u"state"_s).toString(), u"unconfirmed"_s);
        QTRY_VERIFY(!service.saving());
        QCOMPARE(service.m_records[id].attempts, 20);
        QVERIFY(service.m_records[id].authorized);
        service.m_records[id].nextAttempt = QDateTime::currentDateTimeUtc();
        service.pump();
        QTRY_COMPARE(service.draft().value(u"state"_s).toString(),
                     queryStatus == 200 ? u"accepted"_s : u"needs_attention"_s);
        QTRY_VERIFY(!service.saving());
        QCOMPARE(receiver.requests.size(), 2);
        QCOMPARE(receiver.requests[0].method, QByteArray("PUT"));
        QCOMPARE(receiver.requests[1].method, QByteArray("GET"));
        QCOMPARE(service.m_records[id].attempts, 20);
        QCOMPARE(service.m_records[id].queries, 40);
        QVERIFY(!service.m_records[id].authorized);
        if (queryStatus != 200)
            QCOMPARE(service.m_records[id].reason, u"retry_exhausted"_s);
        service.pump();
        QTest::qWait(50);
        QCOMPARE(receiver.requests.size(), 2);
    }
    void retryKeepsFrozenIdentityAndContextIsAllowlisted()
    {
        QTemporaryDir dir;
        FeedbackReceiver receiver;
        receiver.handler = [&](const auto &request) {
            if (receiver.requests.size() == 1)
                FeedbackReceiver::respond(request, 503, "{}");
            else if (request.method == "GET")
                FeedbackReceiver::respond(request, 404, "{}");
            else
                FeedbackReceiver::respond(request, 201, FeedbackReceiver::receipt(request));
        };
        FeedbackService service(dir.path(), receiver.config(), true);
        QTRY_VERIFY(!service.saving());
        const auto id = service.createDraft({{u"appVersion"_s, u"2.5.0"_s}});
        QVERIFY(service.updateDraft({{u"description"_s, u"Retry intact"_s},
                                     {u"context"_s, QVariantMap{{u"feature"_s, u"forge_table"_s},
                                                                {u"serverUrl"_s, u"PRIVATE"_s}}}}));
        QCOMPARE(service.m_records[id].context.value(u"appVersion"_s).toString(), u"2.5.0"_s);
        QVERIFY(!service.m_records[id].context.contains(u"serverUrl"_s));
        const auto context = feedback::safeContext({{u"feature"_s, u"bad space"_s},
                                                    {u"gameMode"_s, u"unsupported"_s},
                                                    {u"runtimeId"_s, QString(200, u'a')},
                                                    {u"catalogVersion"_s, QString(65, u'b')}});
        QCOMPARE(context.size(), 1);
        QCOMPARE(context.value(u"runtimeId"_s).toString().size(), 200);
        QVERIFY(!service.updateDraft({{u"description"_s, u"Bad\u202e text"_s}}));
        QVERIFY(service.updateDraft({{u"description"_s, u"Retry intact"_s}}));
        QVERIFY(confirm(service));
        QTRY_COMPARE(service.draft().value(u"state"_s).toString(), u"unconfirmed"_s);
        QTRY_VERIFY(!service.saving());
        service.m_records[id].nextAttempt = QDateTime::currentDateTimeUtc();
        service.pump();
        QTRY_COMPARE(service.draft().value(u"state"_s).toString(), u"accepted"_s);
        QCOMPARE(receiver.requests.size(), 3);
        QCOMPARE(receiver.requests[0].headers.value("authorization"),
                 receiver.requests[2].headers.value("authorization"));
        QCOMPARE(receiver.requests[0].headers.value("x-feedback-digest"),
                 receiver.requests[2].headers.value("x-feedback-digest"));
    }
};
} // namespace hexproof::client
QTEST_MAIN(hexproof::client::FeedbackServiceTest)
#include "feedbackservice_test.moc"
