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
    QJsonObject result{{u"schemaVersion"_s, 1},
                       {u"submissionId"_s, r.id},
                       {u"createdAt"_s, r.frozenAt.toString(Qt::ISODateWithMs)},
                       {u"category"_s, r.category},
                       {u"description"_s, r.description},
                       {u"context"_s, r.context},
                       {u"attachments"_s, attachments}};
    if (!r.email.isEmpty())
        result.insert(u"replyEmail"_s, r.email);
    return result;
}
QJsonObject encode(const Record &r, bool privateFields)
{
    QJsonArray attachments;
    for (const auto &a : r.attachments)
        attachments.append(QJsonObject{{u"descriptor"_s, a.descriptor},
                                       {u"data"_s, QString::fromLatin1(a.bytes.toBase64())}});
    QJsonObject out{{u"schemaVersion"_s, 1},
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
    if (privateFields) {
        out.insert(u"secret"_s,
                   QString::fromLatin1(r.secret.toBase64(QByteArray::Base64UrlEncoding |
                                                         QByteArray::OmitTrailingEquals)));
        out.insert(u"manifest"_s, QString::fromLatin1(r.manifest.toBase64()));
        out.insert(u"endpoint"_s, r.endpoint);
        out.insert(u"authorized"_s, r.authorized);
        out.insert(u"dispatched"_s, r.dispatched);
        out.insert(u"attempts"_s, r.attempts);
        out.insert(u"queries"_s, r.queries);
        out.insert(u"nextAttempt"_s, r.nextAttempt.toString(Qt::ISODateWithMs));
        out.insert(u"lastQuery"_s, r.lastQuery.toString(Qt::ISODateWithMs));
    }
    return out;
}
std::optional<Record> decode(const QJsonObject &o)
{
    Record r;
    r.id = o.value(u"id"_s).toString();
    if (o.value(u"schemaVersion"_s).toInt() != 1 || QUuid(r.id).isNull() ||
        QUuid(r.id).toString(QUuid::WithoutBraces) != r.id)
        return {};
    r.state = o.value(u"state"_s).toString();
    if (!QStringList{u"draft"_s, u"queued"_s, u"sending"_s, u"unconfirmed"_s, u"received"_s,
                     u"needs_attention"_s}
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
    if (r.attempts < 0 || r.attempts > 20 || r.queries < 0 || r.queries > 40)
        return {};
    r.secret = QByteArray::fromBase64(o.value(u"secret"_s).toString().toLatin1(),
                                      QByteArray::Base64UrlEncoding);
    r.manifest = QByteArray::fromBase64(o.value(u"manifest"_s).toString().toLatin1());
    if (r.manifest.size() > 16384 ||
        (!r.manifest.isEmpty() && (!r.frozenAt.isValid() || r.secret.size() != 32)))
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
