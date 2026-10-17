// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
#include "forgecrashreport_fixture.h"
#include "services/FeedbackService.h"
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
        return u"http://127.0.0.1:%1/feedback/v1"_s.arg(server.serverPort());
    }
    QJsonObject config() const
    {
        return {{u"schemaVersion"_s, 1},
                {u"enabled"_s, true},
                {u"apiBase"_s, base()},
                {u"supportLabel"_s, u"Test support"_s},
                {u"privacyUrl"_s, u"https://example.invalid/privacy"_s},
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
        const auto id = QString::fromLatin1(r.path.mid(r.path.lastIndexOf('/') + 1));
        const auto now = QDateTime::currentDateTimeUtc();
        return QJsonDocument(
                   QJsonObject{
                       {u"schemaVersion"_s, 1},
                       {u"submissionId"_s, id},
                       {u"receipt"_s, id},
                       {u"state"_s, u"received"_s},
                       {u"acceptedAt"_s,
                        now.toString(u"yyyy-MM-dd'T'HH:mm:ss"_s) + u".123456789Z"_s},
                       {u"contentExpiresAt"_s, now.addDays(90).toString(Qt::ISODateWithMs)}})
            .toJson(QJsonDocument::Compact);
    }
};
class FeedbackServiceTest : public QObject
{
    Q_OBJECT
  private slots:
    void draftRestoresAndExportsWithoutSecrets()
    {
        QTemporaryDir dir;
        QString id;
        {
            FeedbackService service(dir.path());
            QTRY_VERIFY(!service.saving());
            QVERIFY(!service.enabled());
            id = service.createDraft({{u"feature"_s, u"forge_table"_s},
                                      {u"roomId"_s, u"SECRET"_s},
                                      {u"runtimeId"_s, u"/private/path"_s}});
            QVERIFY(!id.isEmpty());
            QVERIFY(service.updateDraft({{u"description"_s, u"A problem"_s},
                                         {u"replyEmail"_s, u"contact@example.invalid"_s}}));
            QVERIFY(!service.submit());
            QCOMPARE(service.errorCode(), u"disabled"_s);
            QTRY_VERIFY(!service.saving());
        }
        FeedbackService restored(dir.path());
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
        QVERIFY(service.submit());
        QVERIFY(!service.updateDraft({{u"description"_s, u"mutated"_s}}));
        QTRY_COMPARE(service.draft().value(u"state"_s).toString(), u"received"_s);
        QCOMPARE(receiver.requests.size(), 1);
        const auto request = receiver.requests.first();
        QCOMPARE(request.method, QByteArray("PUT"));
        QCOMPARE(request.path, QString(u"/feedback/v1/submissions/"_s + id).toLatin1());
        QCOMPARE(request.headers.value("authorization"),
                 "Feedback " + service.m_records[id].secret.toBase64(
                                   QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals));
        QCOMPARE(request.headers.value("x-feedback-digest"),
                 feedback::digest("hexproof-feedback-v1\n" + service.m_records[id].manifest));
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
            QVERIFY(service.submit());
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
            service.submit();
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
            service.submit();
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
        QTRY_COMPARE(restored.draft().value(u"state"_s).toString(), u"received"_s);
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
            QVERIFY(service.submit());
            QVERIFY(service.stop(id));
            QTRY_VERIFY(!service.saving());
            QCOMPARE(service.draft().value(u"state"_s).toString(), u"draft"_s);
            QCOMPARE(receiver.requests.size(), 0);
            service.m_timer.stop();
            service.submit();
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
        service.submit();
        QTRY_COMPARE(service.draft().value(u"state"_s).toString(), u"needs_attention"_s);
        QCOMPARE(other.requests.size(), 0);
        receiver.handler = [](const auto &r) {
            FeedbackReceiver::respond(r, 200, QByteArray(9000, 'x'));
        };
        service.createDraft();
        service.updateDraft({{u"description"_s, u"Oversized response"_s}});
        service.submit();
        QTRY_COMPARE(service.draft().value(u"reason"_s).toString(), u"response_invalid"_s);
    }
    void attachmentsFrozenSanitizedAndImagesStripped()
    {
        QTemporaryDir dir;
        FeedbackService service(dir.path());
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
        FeedbackService service(dir.path());
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
            QCOMPARE(service.errorCode(), u"invalid_attachment"_s);
        }
        QTRY_VERIFY(!service.saving());
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
        QVERIFY(!service.submit());
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
        QVERIFY(feedback::safeEndpoint(u"https://example.invalid/feedback/v1?token=x"_s, false)
                    .isEmpty());
        QVERIFY(
            feedback::safeEndpoint(u"https://user@example.invalid/feedback/v1"_s, false).isEmpty());
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
            QVERIFY(service.submit());
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
            QVERIFY(service.submit());
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
            FeedbackService service(dir.path());
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
        FeedbackService recovered(dir.path());
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
        QVERIFY(service.submit());
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
                     queryStatus == 200 ? u"received"_s : u"needs_attention"_s);
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
        QVERIFY(service.submit());
        QTRY_COMPARE(service.draft().value(u"state"_s).toString(), u"unconfirmed"_s);
        QTRY_VERIFY(!service.saving());
        service.m_records[id].nextAttempt = QDateTime::currentDateTimeUtc();
        service.pump();
        QTRY_COMPARE(service.draft().value(u"state"_s).toString(), u"received"_s);
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
