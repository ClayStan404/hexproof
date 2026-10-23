// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
#include "FeedbackService.h"
#include <QBuffer>
#include <QImageReader>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QRegularExpression>
#include <QUrlQuery>
#include <QUuid>

namespace hexproof::client {
using namespace Qt::StringLiterals;
namespace {
constexpr qsizetype MaxThreadBytes = 1024 * 1024;
bool canonicalId(const QString &id)
{
    return !QUuid(id).isNull() && QUuid(id).toString(QUuid::WithoutBraces) == id;
}
QJsonObject fields(const QJsonObject &source, const QStringList &keys)
{
    QJsonObject result;
    for (const auto &key : keys)
        if (source.contains(key))
            result.insert(key, source.value(key));
    return result;
}
bool boundedText(const QJsonObject &object, const QString &key, qsizetype limit)
{
    const auto value = object.value(key);
    return value.isString() && value.toString().toUtf8().size() <= limit;
}
bool validDate(const QJsonObject &object, const QString &key)
{
    return QDateTime::fromString(object.value(key).toString(), Qt::ISODateWithMs).isValid();
}
std::optional<QJsonObject> publicOutcome(const QJsonValue &value, const QString &repository)
{
    if (!value.isObject())
        return {};
    const auto raw = value.toObject();
    auto outcome = fields(
        raw, {u"kind"_s, u"repository"_s, u"issueNumber"_s, u"commit"_s, u"tag"_s, u"version"_s});
    const auto kind = outcome.value(u"kind"_s).toString();
    if (repository.isEmpty() || outcome.value(u"repository"_s).toString() != repository)
        return {};
    if (kind == u"duplicate") {
        const auto number = outcome.value(u"issueNumber"_s).toInteger(-1);
        if (number < 1 || number > 2147483647 || outcome.contains(u"commit"_s) ||
            outcome.contains(u"tag"_s) || outcome.contains(u"version"_s))
            return {};
    } else if (kind == u"source" || kind == u"release") {
        if (!QRegularExpression(u"^[a-f0-9]{40}$"_s)
                 .match(outcome.value(u"commit"_s).toString())
                 .hasMatch() ||
            outcome.contains(u"issueNumber"_s))
            return {};
        if (kind == u"release") {
            const auto version = outcome.value(u"version"_s).toString();
            if (version.size() > 64 ||
                !QRegularExpression(
                     u"^(0|[1-9][0-9]{0,8})\\.(0|[1-9][0-9]{0,8})\\.(0|[1-9][0-9]{0,8})$"_s)
                     .match(version)
                     .hasMatch() ||
                outcome.value(u"tag"_s).toString() != u"v"_s + version)
                return {};
        } else if (outcome.contains(u"tag"_s) || outcome.contains(u"version"_s)) {
            return {};
        }
    } else {
        return {};
    }
    return outcome;
}
std::optional<QJsonObject> threadPage(const QJsonObject &source, const QString &repository)
{
    auto page =
        fields(source, {u"schemaVersion"_s, u"submissionId"_s, u"revision"_s, u"nextCursor"_s,
                        u"workState"_s, u"summary"_s, u"workflowRevision"_s, u"projectionState"_s,
                        u"removalState"_s, u"reason"_s, u"accessExpiresAt"_s, u"contentExpiresAt"_s,
                        u"assessmentDeliveryState"_s, u"assessmentDeliveryReason"_s});
    if (!feedback::validClosure(source))
        return {};
    for (const auto &key :
         {u"caseState"_s, u"closurePublicationState"_s, u"closedAt"_s, u"closureReason"_s})
        if (source.contains(key))
            page.insert(key, source.value(key));
    if (!boundedText(page, u"summary"_s, 4096) || !boundedText(page, u"workState"_s, 64) ||
        !boundedText(page, u"projectionState"_s, 32) || !boundedText(page, u"nextCursor"_s, 64) ||
        page.value(u"workflowRevision"_s).toInteger(-1) < 0 ||
        !validDate(page, u"accessExpiresAt"_s) || !validDate(page, u"contentExpiresAt"_s) ||
        !QStringList{u"none"_s, u"requested"_s, u"pending"_s, u"stalled"_s, u"removed"_s}.contains(
            page.value(u"removalState"_s).toString()) ||
        (page.contains(u"reason"_s) && !boundedText(page, u"reason"_s, 80)) ||
        (page.contains(u"assessmentDeliveryState"_s) &&
         (!boundedText(page, u"assessmentDeliveryState"_s, 16) ||
          !QStringList{u""_s, u"available"_s, u"unavailable"_s}.contains(
              page.value(u"assessmentDeliveryState"_s).toString()))) ||
        (page.contains(u"assessmentDeliveryReason"_s) &&
         !boundedText(page, u"assessmentDeliveryReason"_s, 80)))
        return {};
    if (source.contains(u"question"_s) && !source.value(u"question"_s).isNull()) {
        const auto question = fields(source.value(u"question"_s).toObject(),
                                     {u"id"_s, u"revision"_s, u"code"_s, u"description"_s,
                                      u"publishedAt"_s, u"answerDeadline"_s});
        if (!canonicalId(question.value(u"id"_s).toString()) ||
            question.value(u"revision"_s).toInteger() < 1 ||
            question.value(u"revision"_s).toInteger() > 1000000 ||
            !boundedText(question, u"description"_s, 4096) ||
            !boundedText(question, u"code"_s, 64) || !validDate(question, u"publishedAt"_s) ||
            !validDate(question, u"answerDeadline"_s))
            return {};
        page.insert(u"question"_s, question);
    }
    if (source.contains(u"outcome"_s) && !source.value(u"outcome"_s).isNull()) {
        const auto outcome = publicOutcome(source.value(u"outcome"_s), repository);
        if (!outcome)
            return {};
        page.insert(u"outcome"_s, *outcome);
    }
    QJsonArray deliveries;
    if (source.contains(u"deliveryHistory"_s) && !source.value(u"deliveryHistory"_s).isArray())
        return {};
    QSet<QString> deliveryIds;
    for (const auto &value : source.value(u"deliveryHistory"_s).toArray()) {
        const auto raw = value.toObject();
        auto delivery = fields(
            raw, {u"projectionId"_s, u"inputRevision"_s, u"workflowRevision"_s, u"publishedAt"_s});
        const auto id = delivery.value(u"projectionId"_s).toString();
        const auto outcome = publicOutcome(raw.value(u"outcome"_s), repository);
        if (!canonicalId(id) || deliveryIds.contains(id) ||
            delivery.value(u"inputRevision"_s).toInteger(-1) < 1 ||
            delivery.value(u"workflowRevision"_s).toInteger(-1) < 1 ||
            !validDate(delivery, u"publishedAt"_s) ||
            !delivery.value(u"publishedAt"_s).toString().endsWith(u'Z') || !outcome ||
            outcome->value(u"kind"_s).toString() == u"duplicate" || deliveries.size() >= 32)
            return {};
        deliveryIds.insert(id);
        delivery.insert(u"outcome"_s, *outcome);
        deliveries.append(delivery);
    }
    page.insert(u"deliveryHistory"_s, deliveries);
    if (!source.value(u"items"_s).isArray())
        return {};
    QJsonArray items;
    for (const auto &value : source.value(u"items"_s).toArray()) {
        const auto original = value.toObject();
        auto item = fields(original, {u"submissionId"_s, u"parentSubmissionId"_s, u"sequence"_s,
                                      u"kind"_s, u"category"_s, u"description"_s, u"acceptedAt"_s,
                                      u"publishedAt"_s, u"publicationState"_s, u"reason"_s,
                                      u"questionId"_s, u"questionRevision"_s});
        if (!canonicalId(item.value(u"submissionId"_s).toString()) ||
            !boundedText(item, u"description"_s, 8192) ||
            !QStringList{u"pending"_s, u"stalled"_s, u"published"_s, u"rejected"_s, u"partial"_s}
                 .contains(item.value(u"publicationState"_s).toString()) ||
            !validDate(item, u"acceptedAt"_s) ||
            (item.contains(u"publishedAt"_s) && !validDate(item, u"publishedAt"_s)) ||
            (item.contains(u"reason"_s) && !boundedText(item, u"reason"_s, 80)))
            return {};
        item.insert(u"context"_s,
                    feedback::safeContext(original.value(u"context"_s).toObject().toVariantMap()));
        QJsonArray attachments;
        const auto rawAttachments = original.value(u"attachments"_s);
        if (!rawAttachments.isArray() && !rawAttachments.isNull())
            return {};
        for (const auto &attachment : rawAttachments.toArray())
            attachments.append(
                fields(attachment.toObject(),
                       {u"id"_s, u"kind"_s, u"mediaType"_s, u"byteLength"_s, u"sha256"_s, u"url"_s,
                        u"reportId"_s, u"revision"_s, u"capturedAt"_s}));
        item.insert(u"attachments"_s, attachments);
        if (original.contains(u"disclosure"_s))
            item.insert(u"disclosure"_s, fields(original.value(u"disclosure"_s).toObject(),
                                                {u"revision"_s, u"sha256"_s, u"repository"_s,
                                                 u"providerPolicyRevision"_s}));
        if (original.contains(u"outcome"_s) && !original.value(u"outcome"_s).isNull()) {
            const auto outcome = publicOutcome(original.value(u"outcome"_s), repository);
            if (!outcome)
                return {};
            item.insert(u"outcome"_s, *outcome);
        }
        items.append(item);
    }
    page.insert(u"items"_s, items);
    return page;
}
} // namespace
QByteArray FeedbackService::capability(const feedback::Record &record) const
{
    if (record.parentId.isEmpty())
        return record.secret;
    const auto parent = m_records.constFind(record.parentId);
    if (parent == m_records.cend() || !parent->parentId.isEmpty() || parent->apiVersion != 2 ||
        parent->endpoint != record.endpoint)
        return {};
    return parent->secret;
}
bool FeedbackService::replyAllowed(const feedback::Record &record) const
{
    if (record.parentId.isEmpty())
        return record.caseState == u"open" && record.closureRequestState == u"none";
    const auto parent = m_records.constFind(record.parentId);
    return parent != m_records.cend() && parent->parentId.isEmpty() && parent->apiVersion == 2 &&
           parent->state == u"accepted" && parent->secret.size() == 32 &&
           parent->removalState == u"none" && !parent->removalAuthorized &&
           parent->caseState == u"open" && parent->closureRequestState == u"none" &&
           !parent->closureAuthorized &&
           (!parent->accessExpiresAt.isValid() ||
            parent->accessExpiresAt > QDateTime::currentDateTimeUtc()) &&
           !m_deleting.contains(parent->id) &&
           (record.endpoint.isEmpty() || record.endpoint == parent->endpoint);
}
void FeedbackService::stopReplies(const QString &caseId)
{
    const auto parentRemoval = m_records.value(caseId).removalState;
    const auto parent = m_records.value(caseId);
    const auto ids = m_records.keys();
    for (const auto &id : ids) {
        auto &record = m_records[id];
        if (record.parentId != caseId)
            continue;
        bool changed = false;
        if (record.caseState != parent.caseState ||
            record.closureRequestState != parent.closureRequestState ||
            record.closurePublicationState != parent.closurePublicationState ||
            record.closedAt != parent.closedAt || record.closureReason != parent.closureReason) {
            record.caseState = parent.caseState;
            record.closureRequestState = parent.closureRequestState;
            record.closurePublicationState = parent.closurePublicationState;
            record.closedAt = parent.closedAt;
            record.closureReason = parent.closureReason;
            changed = true;
        }
        if (parentRemoval != u"none" && record.removalState != u"removed" &&
            record.removalState != parentRemoval) {
            record.removalState = parentRemoval;
            changed = true;
        }
        const bool wasAuthorized = record.authorized;
        if (wasAuthorized) {
            record.authorized = false;
            record.reason = u"parent_unavailable"_s;
            if (record.state != u"accepted")
                record.state = record.dispatched ? u"unconfirmed"_s : u"needs_attention"_s;
            changed = true;
        }
        if (changed)
            changedRecord(id);
        if (wasAuthorized && m_dispatchId == id) {
            m_dispatchId.clear();
            if (m_reply)
                m_reply->abort();
        }
    }
}
QString FeedbackService::createReplyDraft(const QString &caseId, const QString &questionId,
                                          int questionRevision)
{
    const auto parent = m_records.value(caseId);
    feedback::Record candidate;
    candidate.parentId = caseId;
    if (!replyAllowed(candidate) || !trustedQuery(parent.endpoint)) {
        fail(u"parent_unavailable"_s);
        return {};
    }
    QJsonObject question;
    if (!questionId.isEmpty()) {
        const auto current = parent.threadPage.value(u"question"_s).toObject();
        if (current.value(u"id"_s).toString() == questionId &&
            current.value(u"revision"_s).toInt() == questionRevision)
            question = current;
        for (const auto &item : parent.threadPage.value(u"items"_s).toArray()) {
            if (!question.isEmpty())
                break;
            const auto entry = item.toObject();
            if (entry.value(u"kind"_s).toString() == u"question" &&
                entry.value(u"questionId"_s).toString() == questionId &&
                entry.value(u"questionRevision"_s).toInt() == questionRevision)
                question = entry;
        }
        if (question.isEmpty()) {
            fail(u"question_unavailable"_s);
            return {};
        }
    } else if (questionRevision != 0) {
        fail(u"question_unavailable"_s);
        return {};
    }
    const auto id = createDraft({{u"feature"_s, u"feedback_reply"_s}});
    if (id.isEmpty())
        return {};
    auto &record = m_records[id];
    record.parentId = caseId;
    record.category = parent.category;
    record.questionId = questionId;
    record.questionRevision = questionRevision;
    record.question = question;
    record.endpoint = parent.endpoint;
    m_threadCase = caseId;
    changedRecord(id);
    return id;
}
QVariantMap FeedbackService::thread() const
{
    const auto parent = m_records.value(m_threadCase);
    auto result = parent.threadPage.toVariantMap();
    feedback::Record candidate;
    candidate.parentId = m_threadCase;
    result.insert(u"caseId"_s, m_threadCase);
    result.insert(u"caseState"_s, parent.caseState);
    result.insert(u"closurePublicationState"_s, parent.closurePublicationState);
    result.insert(u"closureRequestState"_s, parent.closureRequestState);
    result.insert(u"loading"_s, !m_threadReply.isNull() &&
                                    m_threadAttachment.value(u"loading"_s).toBool() == false);
    result.insert(u"errorCode"_s, m_threadError);
    result.insert(u"syncedAt"_s,
                  m_records.value(m_threadCase).threadSyncedAt.toString(Qt::ISODateWithMs));
    result.insert(u"replyAllowed"_s,
                  replyAllowed(candidate) && m_enabled && parent.endpoint == m_apiBase &&
                      !parent.threadPage.isEmpty() && m_threadError != u"thread_unsupported" &&
                      m_threadError != u"content_unavailable");
    QSet<QString> acceptedReplies;
    for (const auto &value : parent.threadPage.value(u"items"_s).toArray())
        acceptedReplies.insert(value.toObject().value(u"submissionId"_s).toString());
    QVariantList localReplies;
    for (const auto &value : records()) {
        const auto reply = value.toMap();
        if (reply.value(u"parentSubmissionId"_s).toString() != m_threadCase)
            continue;
        if (reply.value(u"state"_s).toString() != u"accepted" ||
            !acceptedReplies.contains(reply.value(u"id"_s).toString()))
            localReplies.append(reply);
    }
    result.insert(u"localReplies"_s, localReplies);
    return result;
}
bool FeedbackService::refreshThread(const QString &caseId, const QString &cursor)
{
    const auto record = m_records.value(caseId);
    if (!cursor.isEmpty() || record.apiVersion != 2 || !record.parentId.isEmpty() ||
        record.secret.size() != 32 || record.state != u"accepted")
        return fail(u"record_unavailable"_s);
    if (busy())
        return fail(u"busy"_s);
    if (!trustedQuery(record.endpoint))
        return fail(u"endpoint_untrusted"_s);
    if (m_storageFailed)
        return fail(u"storage_unavailable"_s);
    if (record.threadNextAttempt > QDateTime::currentDateTimeUtc())
        return fail(u"rate_limited"_s);
    m_records[caseId].threadNextAttempt = QDateTime::currentDateTimeUtc().addSecs(5);
    changedRecord(caseId);
    m_threadCase = caseId;
    m_threadError.clear();
    m_threadAttachment.clear();
    readThreadPage(caseId, {});
    return true;
}
void FeedbackService::startThreadRead(const QString &caseId, const QUrl &url, qsizetype limit,
                                      const std::function<void(int, const QByteArray &)> &complete,
                                      bool authenticate)
{
    QNetworkRequest request(url);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::ManualRedirectPolicy);
    request.setAttribute(QNetworkRequest::CookieLoadControlAttribute, QNetworkRequest::Manual);
    request.setAttribute(QNetworkRequest::CookieSaveControlAttribute, QNetworkRequest::Manual);
    request.setAttribute(QNetworkRequest::AuthenticationReuseAttribute, QNetworkRequest::Manual);
    request.setAttribute(QNetworkRequest::CacheLoadControlAttribute,
                         QNetworkRequest::AlwaysNetwork);
    if (authenticate)
        request.setRawHeader("Authorization", "Feedback " + m_records.value(caseId).secret.toBase64(
                                                                QByteArray::Base64UrlEncoding |
                                                                QByteArray::OmitTrailingEquals));
    request.setTransferTimeout(15000);
    auto *reply = m_network.get(request);
    m_threadReply = reply;
    auto bytes = std::make_shared<QByteArray>();
    reply->setReadBufferSize(limit + 1);
    connect(reply, &QIODevice::readyRead, this, [reply, bytes, limit] {
        bytes->append(reply->read(limit + 1 - bytes->size()));
        if (bytes->size() > limit)
            reply->abort();
    });
    connect(
        reply, &QNetworkReply::finished, this,
        [this, reply, bytes, limit, caseId, complete, authenticate] {
            if (reply->isOpen())
                bytes->append(reply->read(limit + 1 - bytes->size()));
            const auto status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            if (authenticate && m_records.contains(caseId) && (status == 429 || status == 503)) {
                const auto now = QDateTime::currentDateTimeUtc();
                const auto header = reply->rawHeader("Retry-After");
                bool number = false;
                auto seconds = header.toLongLong(&number);
                if (!number)
                    seconds = now.secsTo(
                        QDateTime::fromString(QString::fromLatin1(header), Qt::RFC2822Date));
                m_records[caseId].threadNextAttempt =
                    now.addSecs(qBound(qint64(5), seconds, qint64(21600)));
                changedRecord(caseId);
            }
            const bool valid = bytes->size() <= limit &&
                               (reply->error() == QNetworkReply::NoError || status >= 400);
            m_threadReply.clear();
            reply->deleteLater();
            if (m_records.contains(caseId) && m_threadCase == caseId)
                complete(valid ? status : 0, *bytes);
            emit changed();
            emit statusChanged();
            pump();
        });
    QTimer::singleShot(15000, reply, [reply] {
        if (!reply->isFinished())
            reply->abort();
    });
    emit changed();
    emit statusChanged();
}
void FeedbackService::readThreadPage(const QString &caseId, const QString &cursor,
                                     QJsonObject accumulated)
{
    const auto record = m_records.value(caseId);
    QUrl url(record.endpoint + u"/submissions/"_s + caseId + u"/thread"_s);
    QUrlQuery query;
    query.addQueryItem(u"limit"_s, u"5"_s);
    if (!cursor.isEmpty())
        query.addQueryItem(u"cursor"_s, cursor);
    url.setQuery(query);
    startThreadRead(
        caseId, url, 262144,
        [this, caseId, cursor, accumulated](int status, const QByteArray &raw) mutable {
            if (status != 200) {
                m_threadError = status == 404 || status == 405 ? u"thread_unsupported"_s
                                : status == 409                ? u"thread_changed"_s
                                : status == 410                ? u"content_unavailable"_s
                                : status == 429                ? u"rate_limited"_s
                                                               : u"network_error"_s;
                return;
            }
            const auto repository =
                m_records.value(caseId).disclosure.value(u"repository"_s).toString();
            const auto parsed = threadPage(QJsonDocument::fromJson(raw).object(), repository);
            if (!parsed) {
                m_threadError = u"response_invalid"_s;
                return;
            }
            const auto page = *parsed;
            const auto revision = page.value(u"revision"_s).toInteger(-1);
            const auto items = page.value(u"items"_s).toArray();
            if (page.value(u"schemaVersion"_s).toInt() != 2 ||
                page.value(u"submissionId"_s).toString() != caseId || revision < 0 ||
                !page.value(u"items"_s).isArray() || items.size() > 5 ||
                (!cursor.isEmpty() && revision != accumulated.value(u"revision"_s).toInteger())) {
                m_threadError = u"response_invalid"_s;
                return;
            }
            auto previous = accumulated.value(u"items"_s).toArray();
            qint64 sequence = previous.isEmpty()
                                  ? -1
                                  : previous.last().toObject().value(u"sequence"_s).toInteger();
            for (const auto &value : items) {
                const auto item = value.toObject();
                const auto nextSequence = item.value(u"sequence"_s).toInteger(-1);
                if (!QStringList{u"submission"_s, u"reply"_s, u"assessment"_s, u"question"_s}
                         .contains(item.value(u"kind"_s).toString()) ||
                    nextSequence <= sequence ||
                    item.value(u"description"_s).toString().toUtf8().size() > 8192 ||
                    item.value(u"attachments"_s).toArray().size() > 4) {
                    m_threadError = u"response_invalid"_s;
                    return;
                }
                sequence = nextSequence;
                previous.append(item);
            }
            if (previous.size() > 49) {
                m_threadError = u"response_invalid"_s;
                return;
            }
            accumulated = page;
            accumulated.insert(u"items"_s, previous);
            if (QJsonDocument(accumulated).toJson(QJsonDocument::Compact).size() > MaxThreadBytes) {
                m_threadError = u"response_invalid"_s;
                return;
            }
            const auto next = page.value(u"nextCursor"_s).toString();
            if (!next.isEmpty()) {
                if (items.isEmpty() || next == cursor ||
                    next != QString::number(revision) + u":"_s + QString::number(sequence)) {
                    m_threadError = u"response_invalid"_s;
                    return;
                }
                readThreadPage(caseId, next, accumulated);
                return;
            }
            auto &parent = m_records[caseId];
            if (revision < parent.threadPage.value(u"revision"_s).toInteger(-1)) {
                m_threadError = u"thread_changed"_s;
                return;
            }
            const auto size = QJsonDocument(accumulated).toJson(QJsonDocument::Compact).size();
            if (payloadBytes() -
                    QJsonDocument(parent.threadPage).toJson(QJsonDocument::Compact).size() + size >
                feedback::MaxStoreBytes) {
                m_threadError = u"storage_full"_s;
                return;
            }
            parent.threadPage = accumulated;
            parent.threadSyncedAt = QDateTime::currentDateTimeUtc();
            if (accumulated.value(u"caseState"_s).toString() == u"closed") {
                parent.caseState = u"closed"_s;
                parent.closureAuthorized = false;
                parent.closureRequestState = u"none"_s;
                if (parent.closurePublicationState != u"closed") {
                    parent.closurePublicationState =
                        accumulated.value(u"closurePublicationState"_s).toString(u"none"_s);
                    parent.closureReason = accumulated.value(u"closureReason"_s).toString();
                }
                const auto closed =
                    QDateTime::fromString(accumulated.value(u"closedAt"_s).toString(),
                                          Qt::ISODateWithMs)
                        .toUTC();
                if (closed.isValid())
                    parent.closedAt = closed;
                stopReplies(caseId);
            }
            const auto removalState = accumulated.value(u"removalState"_s).toString();
            if (removalState != u"none" && !removalState.isEmpty()) {
                if ((!parent.removalAuthorized && parent.removalState != u"removed") ||
                    removalState == u"removed")
                    parent.removalState = removalState;
                if (removalState == u"removed")
                    parent.removalAuthorized = false;
                stopReplies(caseId);
            }
            m_threadError.clear();
            changedRecord(caseId);
        },
        true);
}
bool FeedbackService::fetchThreadAttachment(const QString &contributionId,
                                            const QString &attachmentId)
{
    if (busy())
        return fail(u"busy"_s);
    const auto parent = m_records.value(m_threadCase);
    if (!trustedQuery(parent.endpoint) || parent.secret.size() != 32 ||
        !canonicalId(contributionId))
        return fail(u"record_unavailable"_s);
    QJsonObject descriptor;
    for (const auto &entry : parent.threadPage.value(u"items"_s).toArray()) {
        const auto item = entry.toObject();
        if (item.value(u"submissionId"_s).toString() != contributionId)
            continue;
        for (const auto &a : item.value(u"attachments"_s).toArray())
            if (a.toObject().value(u"id"_s).toString() == attachmentId)
                descriptor = a.toObject();
    }
    const auto hash = descriptor.value(u"sha256"_s).toString();
    const auto length = descriptor.value(u"byteLength"_s).toInteger(-1);
    const auto media = descriptor.value(u"mediaType"_s).toString();
    if (!QRegularExpression(u"^[a-z0-9_-]{1,32}$"_s).match(attachmentId).hasMatch() ||
        !QRegularExpression(u"^[a-f0-9]{64}$"_s).match(hash).hasMatch() || length < 1 ||
        length > feedback::MaxImageBytes ||
        !QStringList{u"image/png"_s, u"application/json"_s}.contains(media))
        return fail(u"invalid_attachment"_s);
    const auto suffix =
        contributionId == parent.id ? parent.id : parent.id + u"/replies/"_s + contributionId;
    const auto expected =
        parent.endpoint + u"/assets/"_s + suffix + u"/"_s + attachmentId + u"/"_s + hash;
    if (descriptor.value(u"url"_s).toString() != expected)
        return fail(u"endpoint_untrusted"_s);
    m_threadAttachment = {{u"contributionId"_s, contributionId},
                          {u"attachmentId"_s, attachmentId},
                          {u"mediaType"_s, media},
                          {u"loading"_s, true},
                          {u"errorCode"_s, QString{}},
                          {u"content"_s, QString{}}};
    startThreadRead(
        parent.id, QUrl(expected), length,
        [this, hash, length, media](int status, const QByteArray &bytes) {
            m_threadAttachment.insert(u"loading"_s, false);
            if (status != 200 || bytes.size() != length ||
                feedback::digest(bytes) != hash.toLatin1()) {
                m_threadAttachment.insert(u"errorCode"_s, status == 404 ? u"content_unavailable"_s
                                                                        : u"invalid_attachment"_s);
                return;
            }
            QString content;
            if (media == u"image/png") {
                QBuffer buffer;
                buffer.setData(bytes);
                buffer.open(QIODevice::ReadOnly);
                QImageReader reader(&buffer, "png");
                const auto size = reader.size();
                if (size.width() < 1 || size.height() < 1 || size.width() > 8192 ||
                    size.height() > 8192 || qint64(size.width()) * size.height() > 16000000 ||
                    reader.read().isNull()) {
                    m_threadAttachment.insert(u"errorCode"_s, u"invalid_attachment"_s);
                    return;
                }
                content = u"data:image/png;base64,"_s + QString::fromLatin1(bytes.toBase64());
            } else {
                const auto document = QJsonDocument::fromJson(bytes);
                if (!document.isObject()) {
                    m_threadAttachment.insert(u"errorCode"_s, u"invalid_attachment"_s);
                    return;
                }
                content = QString::fromUtf8(document.toJson(QJsonDocument::Indented));
            }
            m_threadAttachment.insert(u"content"_s, content);
        },
        false);
    return true;
}
} // namespace hexproof::client
