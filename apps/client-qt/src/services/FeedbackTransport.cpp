// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
#include "FeedbackService.h"
#include <QHttpMultiPart>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QRandomGenerator>
#include <QRegularExpression>

namespace hexproof::client {
using namespace Qt::StringLiterals;
bool FeedbackService::trustedQuery(const QString &endpoint) const
{
    return !endpoint.isEmpty() && m_queryEndpoints.contains(endpoint) &&
           !feedback::safeEndpoint(endpoint, m_allowLoopback).isEmpty();
}
void FeedbackService::pump()
{
    if (m_loading || m_storageFailed || m_reply || m_threadReply || !m_dispatchId.isEmpty())
        return;
    const auto now = QDateTime::currentDateTimeUtc();
    for (auto it = m_records.begin(); it != m_records.end(); ++it) {
        auto &r = it.value();
        if (m_dirty.contains(r.id) || m_deleting.contains(r.id))
            continue;
        if (r.authorized && !replyAllowed(r)) {
            r.authorized = false;
            r.reason = u"parent_unavailable"_s;
            r.state = r.dispatched ? u"unconfirmed"_s : u"needs_attention"_s;
            changedRecord(r.id);
            return;
        }
        if (r.removalAuthorized) {
            if (!trustedQuery(r.endpoint) || r.removalAttempts >= 20 ||
                r.removalRequestedAt.addDays(7) <= now) {
                r.removalAuthorized = false;
                r.removalState = u"stalled"_s;
                r.reason =
                    trustedQuery(r.endpoint) ? u"retry_exhausted"_s : u"endpoint_untrusted"_s;
                changedRecord(r.id);
                return;
            }
            if (!r.nextAttempt.isValid() || r.nextAttempt <= now) {
                prepareRequest(r.id, false, false, true);
                return;
            }
            continue;
        }
        if (r.closureAuthorized) {
            if (!trustedQuery(r.endpoint) || r.closureAttempts >= 20 ||
                r.closureRequestedAt.addDays(7) <= now) {
                r.closureAuthorized = false;
                r.closureRequestState = u"stalled"_s;
                r.reason =
                    trustedQuery(r.endpoint) ? u"retry_exhausted"_s : u"endpoint_untrusted"_s;
                changedRecord(r.id);
                return;
            }
            if (!r.nextAttempt.isValid() || r.nextAttempt <= now) {
                prepareRequest(r.id, false, false, false, true);
                return;
            }
            continue;
        }
        if (r.state == u"accepted" && r.removalState != u"removed" && r.queries < 40 &&
            capability(r).size() == 32 && trustedQuery(r.endpoint) &&
            (r.publicationState == u"pending" || r.publicationState == u"stalled" ||
             r.publicationState == u"partial" || r.removalState == u"pending" ||
             r.removalState == u"requested" || r.removalState == u"stalled" ||
             r.closurePublicationState == u"pending" || r.closurePublicationState == u"stalled") &&
            (!r.nextAttempt.isValid() || r.nextAttempt <= now)) {
            prepareRequest(r.id, true, true);
            return;
        }
        if (!r.authorized || r.state == u"received" || r.state == u"accepted")
            continue;
        if (r.apiVersion != 2 || !m_enabled || r.endpoint != m_apiBase) {
            r.authorized = false;
            r.reason = u"endpoint_changed"_s;
            r.state = r.dispatched ? u"unconfirmed"_s : u"needs_attention"_s;
            changedRecord(r.id);
            return;
        }
        if (r.frozenAt.addDays(7) <= now || (r.state == u"queued" && r.attempts >= 20) ||
            (r.state == u"unconfirmed" && r.queries >= 40)) {
            r.authorized = false;
            r.reason = u"retry_exhausted"_s;
            r.state = u"needs_attention"_s;
            changedRecord(r.id);
            return;
        }
        if (r.nextAttempt.isValid() && r.nextAttempt > now)
            continue;
        if (r.state == u"queued" || r.state == u"unconfirmed") {
            prepareRequest(r.id, r.state == u"unconfirmed");
            return;
        }
    }
}
bool FeedbackService::queryReceipt(const QString &id)
{
    if (m_loading || !m_records.contains(id) || capability(m_records[id]).size() != 32)
        return fail(u"record_unavailable"_s);
    if (m_reply || m_threadReply || !m_dispatchId.isEmpty())
        return fail(u"busy"_s);
    if (!trustedQuery(m_records[id].endpoint))
        return fail(u"endpoint_untrusted"_s);
    if (m_storageFailed)
        return fail(u"storage_unavailable"_s);
    if (m_records[id].lastQuery.msecsTo(QDateTime::currentDateTimeUtc()) < 5000 &&
        m_records[id].lastQuery.isValid())
        return fail(u"rate_limited"_s);
    prepareRequest(id, true, true);
    return true;
}
void FeedbackService::prepareRequest(const QString &id, bool query, bool manual, bool removal,
                                     bool closure)
{
    if (!m_records.contains(id))
        return;
    auto &r = m_records[id];
    if (query && !trustedQuery(r.endpoint)) {
        r.authorized = false;
        r.reason = u"endpoint_untrusted"_s;
        r.state = u"needs_attention"_s;
        changedRecord(id);
        return;
    }
    m_dispatchId = id;
    m_dispatchQuery = query;
    m_dispatchManual = manual;
    m_dispatchRemoval = removal;
    m_dispatchClosure = closure;
    if (closure) {
        ++r.closureAttempts;
    } else if (removal) {
        ++r.removalAttempts;
    } else if (query) {
        r.queries = qMin(40, r.queries + 1);
        r.lastQuery = QDateTime::currentDateTimeUtc();
    } else {
        r.dispatched = true;
        r.state = u"sending"_s;
        ++r.attempts;
    }
    changedRecord(id);
}
void FeedbackService::dispatch()
{
    const auto id = m_dispatchId;
    if (id.isEmpty() || m_reply)
        return;
    if (!m_records.contains(id) || m_deleting.contains(id)) {
        m_dispatchId.clear();
        emit statusChanged();
        return;
    }
    const auto &r = m_records[id];
    if (m_storageFailed || m_dirty.contains(id) || m_generation.value(id) != m_persisted.value(id))
        return;
    const bool upload = !m_dispatchQuery && !m_dispatchRemoval && !m_dispatchClosure;
    if ((upload && !replyAllowed(r)) || capability(r).size() != 32 ||
        (m_dispatchClosure &&
         (!r.closureAuthorized || r.removalAuthorized || !trustedQuery(r.endpoint))) ||
        (m_dispatchRemoval && (!r.removalAuthorized || !trustedQuery(r.endpoint))) ||
        (upload && (!r.authorized || r.apiVersion != 2 || !m_enabled || r.endpoint != m_apiBase)) ||
        (m_dispatchQuery && (!trustedQuery(r.endpoint) || (!r.authorized && !m_dispatchManual)))) {
        m_dispatchId.clear();
        emit statusChanged();
        return;
    }
    const auto path = r.parentId.isEmpty() ? r.id : r.parentId + u"/replies/"_s + r.id;
    const QUrl url(r.endpoint + u"/submissions/"_s + path +
                   (m_dispatchClosure ? u"/close"_s : QString{}));
    QNetworkRequest request(url);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::ManualRedirectPolicy);
    request.setAttribute(QNetworkRequest::CookieLoadControlAttribute, QNetworkRequest::Manual);
    request.setAttribute(QNetworkRequest::CookieSaveControlAttribute, QNetworkRequest::Manual);
    request.setAttribute(QNetworkRequest::AuthenticationReuseAttribute, QNetworkRequest::Manual);
    request.setAttribute(QNetworkRequest::CacheLoadControlAttribute,
                         QNetworkRequest::AlwaysNetwork);
    request.setRawHeader("Authorization",
                         "Feedback " + capability(r).toBase64(QByteArray::Base64UrlEncoding |
                                                              QByteArray::OmitTrailingEquals));
    request.setRawHeader("Accept", "application/json");
    request.setTransferTimeout(60000);
    const bool query = m_dispatchQuery;
    const bool removal = m_dispatchRemoval;
    const bool closure = m_dispatchClosure;
    if (closure) {
        request.setHeader(QNetworkRequest::ContentTypeHeader, u"application/json"_s);
        m_reply = m_network.post(request, QByteArray{});
    } else if (removal)
        m_reply = m_network.deleteResource(request);
    else if (query)
        m_reply = m_network.get(request);
    else {
        request.setRawHeader("X-Feedback-Digest", feedback::manifestDigest(r));
        auto *parts = new QHttpMultiPart(QHttpMultiPart::FormDataType);
        QHttpPart first;
        first.setHeader(QNetworkRequest::ContentTypeHeader, u"application/json"_s);
        first.setHeader(QNetworkRequest::ContentDispositionHeader,
                        u"form-data; name=\"manifest\""_s);
        first.setBody(r.manifest);
        parts->append(first);
        for (const auto &a : r.attachments) {
            QHttpPart part;
            part.setHeader(QNetworkRequest::ContentTypeHeader,
                           a.descriptor.value(u"mediaType"_s).toString());
            part.setHeader(QNetworkRequest::ContentDispositionHeader,
                           u"form-data; name=\"%1\""_s.arg(a.descriptor.value(u"id"_s).toString()));
            part.setBody(a.bytes);
            parts->append(part);
        }
        m_reply = m_network.put(request, parts);
        parts->setParent(m_reply);
    }
    m_response.clear();
    m_responseOversized = false;
    m_reply->setReadBufferSize(8193);
    connect(m_reply, &QIODevice::readyRead, this, [this] {
        if (!m_reply)
            return;
        m_response.append(m_reply->read(8193 - m_response.size()));
        if (m_response.size() > 8192) {
            m_responseOversized = true;
            m_reply->abort();
        }
    });
    connect(m_reply, &QNetworkReply::finished, this,
            [this, id, query, removal, closure] { finishRequest(id, query, removal, closure); });
    QTimer::singleShot(60000, m_reply, [reply = m_reply] {
        if (reply && !reply->isFinished())
            reply->abort();
    });
    emit changed();
    emit statusChanged();
}
void FeedbackService::finishRequest(const QString &id, bool query, bool removal, bool closure)
{
    if (!m_reply)
        return;
    auto *reply = m_reply.data();
    if (reply->isOpen())
        m_response.append(reply->read(8193 - m_response.size()));
    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const auto networkError = reply->error();
    const auto retryHeader = reply->rawHeader("Retry-After");
    reply->deleteLater();
    m_reply.clear();
    m_dispatchId.clear();
    if (!m_records.contains(id)) {
        emit statusChanged();
        pump();
        return;
    }
    auto &r = m_records[id];
    const auto now = QDateTime::currentDateTimeUtc();
    const auto response = QJsonDocument::fromJson(m_response).object();
    const auto accepted =
        QDateTime::fromString(response.value(u"acceptedAt"_s).toString(), Qt::ISODateWithMs)
            .toUTC();
    const auto expires =
        QDateTime::fromString(response.value(u"contentExpiresAt"_s).toString(), Qt::ISODateWithMs)
            .toUTC();
    const auto accessExpires =
        QDateTime::fromString(response.value(u"accessExpiresAt"_s).toString(), Qt::ISODateWithMs)
            .toUTC();
    const auto publication = response.value(u"publicationState"_s).toString();
    const auto removalState = response.value(u"removalState"_s).toString();
    const auto issueUrl = response.value(u"issueUrl"_s).toString();
    const QString repository = r.disclosure.value(u"repository"_s).toString();
    const bool validIssue =
        issueUrl.isEmpty() ||
        QRegularExpression(u"^https://github\\.com/"_s + QRegularExpression::escape(repository) +
                           u"/issues/[1-9][0-9]*$"_s)
            .match(issueUrl)
            .hasMatch();
    const bool legacy = r.apiVersion == 1 && response.value(u"state"_s).toString() == u"received";
    const bool publicReceipt =
        r.apiVersion == 2 && response.value(u"state"_s).toString() == u"accepted" &&
        accessExpires > accepted &&
        QStringList{u"pending"_s, u"stalled"_s, u"published"_s, u"rejected"_s, u"partial"_s}
            .contains(publication) &&
        QStringList{u"none"_s, u"requested"_s, u"pending"_s, u"stalled"_s, u"removed"_s}.contains(
            removalState) &&
        validIssue && (publication != u"published" || !issueUrl.isEmpty()) &&
        feedback::validClosure(response);
    if ((status == 200 || status == 201 || (status == 202 && r.apiVersion == 2)) &&
        !m_responseOversized && m_response.size() <= 8192 &&
        networkError == QNetworkReply::NoError &&
        response.value(u"schemaVersion"_s).toInt() == r.apiVersion &&
        response.value(u"submissionId"_s) == id && response.value(u"receipt"_s) == id &&
        response.value(u"parentSubmissionId"_s).toString() == r.parentId &&
        (!closure || (status == 200 && response.value(u"caseState"_s).toString() == u"closed")) &&
        (legacy || publicReceipt) && accepted.isValid() && expires > accepted) {
        r.authorized = false;
        r.state = r.apiVersion == 2 ? u"accepted"_s : u"received"_s;
        r.reason = response.value(u"reason"_s).toString().left(80);
        r.receipt = id;
        r.acceptedAt = accepted;
        r.expiresAt = expires;
        if (publicReceipt) {
            if (response.value(u"caseState"_s).toString() == u"closed") {
                r.caseState = u"closed"_s;
                r.closureAuthorized = false;
                r.closureRequestState = u"none"_s;
                if (r.closurePublicationState != u"closed") {
                    r.closurePublicationState =
                        response.value(u"closurePublicationState"_s).toString(u"none"_s);
                    r.closureReason = response.value(u"closureReason"_s).toString();
                }
                const auto closed = QDateTime::fromString(response.value(u"closedAt"_s).toString(),
                                                          Qt::ISODateWithMs)
                                        .toUTC();
                if (closed.isValid())
                    r.closedAt = closed;
                if (r.parentId.isEmpty())
                    stopReplies(id);
            }
            r.accessExpiresAt = accessExpires;
            r.publicationState = publication;
            r.issueUrl = issueUrl;
            // A lookup started before the user's removal request cannot
            // acknowledge that request or postpone its DELETE. Only a terminal
            // removed result can complete it without a DELETE acknowledgement.
            const bool pendingRemoval =
                !removal && r.removalAuthorized && removalState != u"removed";
            if (!pendingRemoval && (!r.removalAuthorized || removalState != u"none"))
                r.removalState = removalState;
            if (!pendingRemoval && removalState != u"none")
                r.removalAuthorized = false;
            // A child's lookup may have started before the whole-case request.
            // It cannot undo removal already known from the parent receipt.
            const auto parentRemoval = m_records.value(r.parentId).removalState;
            if (!r.parentId.isEmpty() && parentRemoval != u"none" && r.removalState != u"removed")
                r.removalState = parentRemoval;
            const auto interval = qMin<qint64>(21600, 30LL << qMin(10, r.queries));
            r.nextAttempt = pendingRemoval ? now : now.addSecs(interval);
            if (r.parentId.isEmpty() && r.removalState != u"none")
                stopReplies(id);
        }
        m_error.clear();
    } else if (query && status == 404) {
        if (r.authorized) {
            r.state = u"queued"_s;
            r.nextAttempt = now;
        } else {
            if (r.state != u"received" && r.state != u"accepted")
                r.state = u"unconfirmed"_s;
            if (r.reason.isEmpty())
                r.reason = u"content_unavailable"_s;
            r.nextAttempt = now.addSecs(300);
        }
    } else if (status == 429 || status >= 500 || (!m_responseOversized && status == 0)) {
        if (r.state != u"received" && r.state != u"accepted")
            r.state = u"unconfirmed"_s;
        if (r.reason != u"stopped" && r.reason != u"parent_unavailable")
            r.reason = status == 429 ? u"rate_limited"_s : u"network_error"_s;
        qint64 seconds =
            qMin<qint64>(21600, 5LL << qBound(0,
                                              qMax(qMax(r.attempts, r.queries),
                                                   qMax(r.removalAttempts, r.closureAttempts)) -
                                                  1,
                                              12));
        seconds += QRandomGenerator::global()->bounded(qMax(1, int(seconds / 4)));
        bool number = false;
        const auto retry = retryHeader.toLongLong(&number);
        if (number)
            seconds = qMax(seconds, qBound(qint64(0), retry, qint64(21600)));
        else {
            const auto date =
                QDateTime::fromString(QString::fromLatin1(retryHeader), Qt::RFC2822Date);
            if (date.isValid())
                seconds = qMax(seconds, qBound(qint64(0), now.secsTo(date), qint64(21600)));
        }
        r.nextAttempt = now.addSecs(qMin<qint64>(21600, seconds));
    } else {
        r.authorized = false;
        if (removal) {
            r.removalAuthorized = false;
            r.removalState = u"stalled"_s;
        }
        if (closure) {
            r.closureAuthorized = false;
            r.closureRequestState = u"stalled"_s;
        }
        if (r.state != u"received" && r.state != u"accepted")
            r.state = u"needs_attention"_s;
        r.reason = status == 409   ? u"content_conflict"_s
                   : status == 410 ? u"content_unavailable"_s
                   : (status == 400 || status == 413 || status == 415 || status == 422)
                       ? u"unsupported_content"_s
                       : u"response_invalid"_s;
        r.nextAttempt = now.addSecs(300);
    }
    // A stale receipt/thread read cannot postpone an explicitly journaled close request.
    if (r.closureAuthorized && !closure)
        r.nextAttempt = now;
    changedRecord(id);
    prune();
    emit statusChanged();
    pump();
}
} // namespace hexproof::client
