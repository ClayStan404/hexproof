// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
#include "FeedbackService.h"
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QHostAddress>
#include <QJsonArray>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QSaveFile>
#include <QUuid>

namespace hexproof::client::feedback {
using namespace Qt::StringLiterals;
QByteArray digest(const QByteArray &bytes)
{
    return QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex();
}
QByteArray manifestDigest(const Record &r)
{
    return digest((r.parentId.isEmpty() ? QByteArray("hexproof-feedback-v2\n")
                                        : QByteArray("hexproof-feedback-reply-v2\n")) +
                  r.manifest);
}
QByteArray revocationDigest(const Record &r)
{
    return digest(r.parentId.isEmpty() ? r.secret
                                       : QByteArray("hexproof-feedback-reply-authorization\n") +
                                             r.authorizationNonce);
}
bool validClosure(const QJsonObject &object)
{
    for (const auto &key :
         {u"caseState"_s, u"closurePublicationState"_s, u"closedAt"_s, u"closureReason"_s})
        if (object.contains(key) && !object.value(key).isString())
            return false;
    const auto state = object.value(u"caseState"_s).toString(u"open"_s);
    const auto publication = object.value(u"closurePublicationState"_s).toString(u"none"_s);
    if (!QStringList{u"open"_s, u"closed"_s}.contains(state) ||
        !QStringList{u"none"_s, u"pending"_s, u"closed"_s, u"stalled"_s}.contains(
            object.value(u"closurePublicationState"_s).toString(u"none"_s)) ||
        object.value(u"closureReason"_s).toString().toUtf8().size() > 80)
        return false;
    if (state == u"open")
        return publication == u"none" && !object.contains(u"closedAt"_s) &&
               object.value(u"closureReason"_s).toString().isEmpty();
    const auto value = object.value(u"closedAt"_s).toString();
    return publication != u"none" && value.endsWith(u'Z') &&
           QDateTime::fromString(value, Qt::ISODateWithMs).isValid();
}
QUrl safeEndpoint(const QString &value, bool allowLoopback)
{
    const QUrl url(value, QUrl::StrictMode);
    const auto host = QHostAddress(url.host());
    if (!url.isValid() || url.host().isEmpty() || !url.userInfo().isEmpty() || url.hasQuery() ||
        url.hasFragment() ||
        (url.scheme() != u"https" &&
         !(allowLoopback && url.scheme() == u"http" && host.isLoopback())) ||
        url.path().contains(u"..") || url.path().contains(u"//") || value.contains(u'%'))
        return {};
    QUrl clean(url);
    auto path = clean.path();
    while (path.endsWith(u'/'))
        path.chop(1);
    clean.setPath(path);
    return clean;
}
QJsonObject safeContext(const QVariantMap &values)
{
    QJsonObject result;
    const QSet<QString> keys{
        u"appVersion"_s, u"osFamily"_s, u"architecture"_s, u"uiLanguage"_s,     u"feature"_s,
        u"gameMode"_s,   u"format"_s,   u"priorityMode"_s, u"catalogVersion"_s, u"runtimeId"_s};
    static const QRegularExpression safe(u"^[A-Za-z0-9_.$<>:+-]*$"_s);
    for (auto it = values.begin(); it != values.end(); ++it) {
        if (!keys.contains(it.key()) || it.value().metaType().id() != QMetaType::QString)
            continue;
        const auto text = it.value().toString();
        if (text.size() > (it.key() == u"runtimeId" ? 256 : 64) || !safe.match(text).hasMatch())
            continue;
        if (it.key() == u"osFamily" &&
            !QStringList{u"windows"_s, u"macos"_s, u"linux"_s, u"other"_s}.contains(text))
            continue;
        if (it.key() == u"gameMode" && !QStringList{u"manual"_s, u"forge"_s}.contains(text))
            continue;
        result.insert(it.key(), text);
    }
    return result;
}
QJsonObject manifest(const Record &r)
{
    QJsonArray attachments;
    for (const auto &a : r.attachments)
        attachments.append(a.descriptor);
    QJsonObject result{{u"schemaVersion"_s, r.apiVersion},
                       {u"submissionId"_s, r.id},
                       {u"createdAt"_s, r.frozenAt.toString(Qt::ISODateWithMs)},
                       {u"category"_s, r.category},
                       {u"description"_s, r.description},
                       {u"context"_s, r.context},
                       {u"attachments"_s, attachments}};
    if (r.apiVersion == 1 && !r.email.isEmpty())
        result.insert(u"replyEmail"_s, r.email);
    if (r.apiVersion == 2)
        result.insert(u"disclosure"_s, r.disclosure);
    if (!r.parentId.isEmpty()) {
        result.insert(u"parentSubmissionId"_s, r.parentId);
        if (!r.questionId.isEmpty()) {
            result.insert(u"questionId"_s, r.questionId);
            result.insert(u"questionRevision"_s, r.questionRevision);
        }
    }
    return result;
}
QJsonObject encode(const Record &r, bool privateFields)
{
    QJsonArray attachments;
    for (const auto &a : r.attachments)
        attachments.append(QJsonObject{{u"descriptor"_s, a.descriptor},
                                       {u"data"_s, QString::fromLatin1(a.bytes.toBase64())}});
    QJsonObject out{{u"schemaVersion"_s, 2},
                    {u"apiVersion"_s, r.apiVersion},
                    {u"id"_s, r.id},
                    {u"state"_s, r.state},
                    {u"category"_s, r.category},
                    {u"description"_s, r.description},
                    {u"replyEmail"_s, r.email},
                    {u"context"_s, r.context},
                    {u"attachments"_s, attachments},
                    {u"draftCreatedAt"_s, r.draftCreated.toString(Qt::ISODateWithMs)},
                    {u"createdAt"_s, r.frozenAt.toString(Qt::ISODateWithMs)},
                    {u"receipt"_s, r.receipt},
                    {u"acceptedAt"_s, r.acceptedAt.toString(Qt::ISODateWithMs)},
                    {u"contentExpiresAt"_s, r.expiresAt.toString(Qt::ISODateWithMs)},
                    {u"payloadAvailable"_s, r.payloadAvailable},
                    {u"reason"_s, r.reason}};
    if (!r.parentId.isEmpty()) {
        out.insert(u"parentSubmissionId"_s, r.parentId);
        out.insert(u"questionId"_s, r.questionId);
        out.insert(u"questionRevision"_s, r.questionRevision);
        out.insert(u"question"_s, r.question);
    }
    if (r.apiVersion == 2) {
        out.remove(u"replyEmail"_s);
        out.insert(u"disclosure"_s, r.disclosure);
        out.insert(u"publicationState"_s, r.publicationState);
        out.insert(u"removalState"_s, r.removalState);
        out.insert(u"caseState"_s, r.caseState);
        out.insert(u"closurePublicationState"_s, r.closurePublicationState);
        out.insert(u"closureReason"_s, r.closureReason);
        out.insert(u"closureRequestState"_s, r.closureRequestState);
        if (r.closedAt.isValid())
            out.insert(u"closedAt"_s, r.closedAt.toString(Qt::ISODateWithMs));
        out.insert(u"issueUrl"_s, r.issueUrl);
        out.insert(u"accessExpiresAt"_s, r.accessExpiresAt.toString(Qt::ISODateWithMs));
    }
    if (privateFields) {
        out.insert(u"threadPage"_s, r.threadPage);
        out.insert(u"threadSyncedAt"_s, r.threadSyncedAt.toString(Qt::ISODateWithMs));
        out.insert(u"threadNextAttempt"_s, r.threadNextAttempt.toString(Qt::ISODateWithMs));
        out.insert(u"secret"_s,
                   QString::fromLatin1(r.secret.toBase64(QByteArray::Base64UrlEncoding |
                                                         QByteArray::OmitTrailingEquals)));
        out.insert(u"manifest"_s, QString::fromLatin1(r.manifest.toBase64()));
        out.insert(u"authorizationNonce"_s, QString::fromLatin1(r.authorizationNonce.toBase64()));
        out.insert(u"endpoint"_s, r.endpoint);
        out.insert(u"authorized"_s, r.authorized);
        out.insert(u"dispatched"_s, r.dispatched);
        out.insert(u"attempts"_s, r.attempts);
        out.insert(u"queries"_s, r.queries);
        out.insert(u"nextAttempt"_s, r.nextAttempt.toString(Qt::ISODateWithMs));
        out.insert(u"lastQuery"_s, r.lastQuery.toString(Qt::ISODateWithMs));
        out.insert(u"removalAuthorized"_s, r.removalAuthorized);
        out.insert(u"removalAttempts"_s, r.removalAttempts);
        out.insert(u"removalRequestedAt"_s, r.removalRequestedAt.toString(Qt::ISODateWithMs));
        out.insert(u"closureAuthorized"_s, r.closureAuthorized);
        out.insert(u"closureAttempts"_s, r.closureAttempts);
        out.insert(u"closureRequestedAt"_s, r.closureRequestedAt.toString(Qt::ISODateWithMs));
    }
    return out;
}
std::optional<Record> decode(const QJsonObject &o)
{
    Record r;
    r.id = o.value(u"id"_s).toString();
    const int schemaVersion = o.value(u"schemaVersion"_s).toInt();
    if ((schemaVersion != 1 && schemaVersion != 2) || QUuid(r.id).isNull() ||
        QUuid(r.id).toString(QUuid::WithoutBraces) != r.id)
        return {};
    r.apiVersion = schemaVersion == 1 ? 1 : o.value(u"apiVersion"_s).toInt();
    if (r.apiVersion != 1 && r.apiVersion != 2)
        return {};
    r.parentId = o.value(u"parentSubmissionId"_s).toString();
    r.questionId = o.value(u"questionId"_s).toString();
    r.questionRevision = o.value(u"questionRevision"_s).toInt();
    r.question = o.value(u"question"_s).toObject();
    r.threadPage = o.value(u"threadPage"_s).toObject();
    if ((!r.parentId.isEmpty() &&
         (r.apiVersion != 2 || QUuid(r.parentId).isNull() ||
          QUuid(r.parentId).toString(QUuid::WithoutBraces) != r.parentId || r.parentId == r.id)) ||
        (r.questionId.isEmpty() != (r.questionRevision == 0)) ||
        (!r.questionId.isEmpty() &&
         (QUuid(r.questionId).isNull() ||
          QUuid(r.questionId).toString(QUuid::WithoutBraces) != r.questionId ||
          r.parentId.isEmpty())) ||
        r.questionRevision < 0 || r.questionRevision > 1000000 ||
        QJsonDocument(r.question).toJson().size() > 16384 ||
        QJsonDocument(r.threadPage).toJson(QJsonDocument::Compact).size() > 1024 * 1024)
        return {};
    r.disclosure = o.value(u"disclosure"_s).toObject();
    r.publicationState = o.value(u"publicationState"_s).toString();
    r.removalState = o.value(u"removalState"_s).toString(u"none"_s);
    if (!validClosure(o))
        return {};
    r.caseState = o.value(u"caseState"_s).toString(u"open"_s);
    r.closurePublicationState = o.value(u"closurePublicationState"_s).toString(u"none"_s);
    r.closureReason = o.value(u"closureReason"_s).toString();
    r.closureRequestState = o.value(u"closureRequestState"_s).toString(u"none"_s);
    if (!QStringList{u"none"_s, u"requested"_s, u"stalled"_s}.contains(r.closureRequestState))
        return {};
    r.issueUrl = o.value(u"issueUrl"_s).toString();
    if (!QStringList{u""_s, u"pending"_s, u"stalled"_s, u"published"_s, u"rejected"_s, u"partial"_s}
             .contains(r.publicationState) ||
        !QStringList{u"none"_s, u"requested"_s, u"pending"_s, u"stalled"_s, u"removed"_s}.contains(
            r.removalState))
        return {};
    r.state = o.value(u"state"_s).toString();
    if (!QStringList{u"draft"_s, u"queued"_s, u"sending"_s, u"unconfirmed"_s, u"received"_s,
                     u"needs_attention"_s, u"accepted"_s}
             .contains(r.state))
        return {};
    r.category = o.value(u"category"_s).toString();
    if (!QStringList{u"problem"_s, u"suggestion"_s, u"other"_s}.contains(r.category))
        return {};
    r.description = o.value(u"description"_s).toString();
    r.email = o.value(u"replyEmail"_s).toString();
    if (r.description.toUtf8().size() > 8192 || r.email.toUtf8().size() > 254)
        return {};
    r.context = safeContext(o.value(u"context"_s).toObject().toVariantMap());
    auto time = [&](const QString &key) {
        return QDateTime::fromString(o.value(key).toString(), Qt::ISODateWithMs).toUTC();
    };
    r.draftCreated = time(u"draftCreatedAt"_s);
    r.frozenAt = time(u"createdAt"_s);
    r.acceptedAt = time(u"acceptedAt"_s);
    r.expiresAt = time(u"contentExpiresAt"_s);
    r.nextAttempt = time(u"nextAttempt"_s);
    r.lastQuery = time(u"lastQuery"_s);
    r.threadSyncedAt = time(u"threadSyncedAt"_s);
    r.threadNextAttempt = time(u"threadNextAttempt"_s);
    r.accessExpiresAt = time(u"accessExpiresAt"_s);
    r.removalRequestedAt = time(u"removalRequestedAt"_s);
    r.closureRequestedAt = time(u"closureRequestedAt"_s);
    r.closedAt = time(u"closedAt"_s);
    if (!r.draftCreated.isValid())
        return {};
    r.endpoint = o.value(u"endpoint"_s).toString();
    r.reason = o.value(u"reason"_s).toString().left(80);
    r.receipt = o.value(u"receipt"_s).toString();
    if (!r.receipt.isEmpty() && r.receipt != r.id)
        return {};
    r.authorized = o.value(u"authorized"_s).toBool();
    r.dispatched = o.value(u"dispatched"_s).toBool();
    r.payloadAvailable = o.value(u"payloadAvailable"_s).toBool(true);
    r.attempts = o.value(u"attempts"_s).toInt();
    r.queries = o.value(u"queries"_s).toInt();
    r.removalAttempts = o.value(u"removalAttempts"_s).toInt();
    r.removalAuthorized = o.value(u"removalAuthorized"_s).toBool();
    r.closureAttempts = o.value(u"closureAttempts"_s).toInt();
    r.closureAuthorized = o.value(u"closureAuthorized"_s).toBool();
    if (r.attempts < 0 || r.attempts > 20 || r.queries < 0 || r.queries > 40 ||
        r.removalAttempts < 0 || r.removalAttempts > 20 || r.closureAttempts < 0 ||
        r.closureAttempts > 20)
        return {};
    r.secret = QByteArray::fromBase64(o.value(u"secret"_s).toString().toLatin1(),
                                      QByteArray::Base64UrlEncoding);
    if (!r.parentId.isEmpty() && !r.secret.isEmpty())
        return {};
    r.authorizationNonce =
        QByteArray::fromBase64(o.value(u"authorizationNonce"_s).toString().toLatin1());
    if ((!r.authorizationNonce.isEmpty() && r.authorizationNonce.size() != 32) ||
        (r.parentId.isEmpty() && !r.authorizationNonce.isEmpty()) ||
        (!r.parentId.isEmpty() && r.authorized && r.authorizationNonce.size() != 32))
        return {};
    r.manifest = QByteArray::fromBase64(o.value(u"manifest"_s).toString().toLatin1());
    if (r.manifest.size() > 16384 ||
        (!r.manifest.isEmpty() &&
         (!r.frozenAt.isValid() ||
          (r.parentId.isEmpty() ? r.secret.size() != 32 : !r.secret.isEmpty()))))
        return {};
    const auto attachments = o.value(u"attachments"_s).toArray();
    if (attachments.size() > 4)
        return {};
    QSet<QString> ids;
    int images = 0, crashes = 0, hosting = 0;
    for (const auto &v : attachments) {
        Attachment a;
        a.descriptor = v.toObject().value(u"descriptor"_s).toObject();
        const auto id = a.descriptor.value(u"id"_s).toString();
        if (!QRegularExpression(u"^[a-z0-9_-]{1,32}$"_s).match(id).hasMatch() || ids.contains(id))
            return {};
        ids.insert(id);
        const auto kind = a.descriptor.value(u"kind"_s).toString();
        int limit = 0;
        if (kind == u"screenshot" && ++images <= 2)
            limit = MaxImageBytes;
        if (kind == u"forge_crash" && ++crashes <= 1)
            limit = 65536;
        if (kind == u"hosting_diagnostics" && ++hosting <= 1)
            limit = 524288;
        if (!limit)
            return {};
        a.bytes = QByteArray::fromBase64(v.toObject().value(u"data"_s).toString().toLatin1());
        if (a.bytes.size() > limit ||
            a.bytes.size() != a.descriptor.value(u"byteLength"_s).toInteger() ||
            digest(a.bytes) != a.descriptor.value(u"sha256"_s).toString().toLatin1())
            return {};
        r.attachments.append(a);
    }
    if (r.payloadAvailable && !r.manifest.isEmpty() &&
        QJsonDocument::fromJson(r.manifest).object() != manifest(r))
        return {};
    if (r.authorized && (r.manifest.isEmpty() || !r.payloadAvailable))
        return {};
    if (r.removalAuthorized &&
        (r.apiVersion != 2 || r.secret.size() != 32 || !r.removalRequestedAt.isValid()))
        return {};
    if (r.closureAuthorized && (r.apiVersion != 2 || !r.parentId.isEmpty() ||
                                r.secret.size() != 32 || !r.closureRequestedAt.isValid()))
        return {};
    return r;
}
bool writePrivate(const QString &path, const QByteArray &data, bool secureDirectory)
{
    const auto dir = QFileInfo(path).absolutePath();
    if (!QDir().mkpath(dir))
        return false;
    if (secureDirectory &&
        !QFile::setPermissions(dir, QFileDevice::ReadOwner | QFileDevice::WriteOwner |
                                        QFileDevice::ExeOwner))
        return false;
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return false;
    if (!file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner))
        return false;
    return file.write(data) == data.size() && file.commit();
}
} // namespace hexproof::client::feedback
