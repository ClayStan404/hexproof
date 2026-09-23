// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "PublicContentSchema.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QHostAddress>
#include <QJsonArray>
#include <QRegularExpression>
#include <QSet>

namespace hexproof::client::public_content {
namespace {
using namespace Qt::StringLiterals;

bool integer(const QJsonValue &value, qint64 minimum, qint64 maximum)
{
    return value.isDouble() && value.toDouble() == value.toInteger(-1) &&
           value.toInteger(-1) >= minimum && value.toInteger(-1) <= maximum;
}

bool revision(const QJsonValue &value)
{
    return integer(value, 1, 9007199254740991LL);
}

bool id(const QJsonValue &value)
{
    static const QRegularExpression pattern(u"^[a-z0-9][a-z0-9_-]{0,63}$"_s);
    return value.isString() && pattern.match(value.toString()).hasMatch();
}

bool text(const QJsonValue &value, int maximum, bool empty = false)
{
    return value.isString() && (empty || !value.toString().trimmed().isEmpty()) &&
           value.toString().size() <= maximum && !value.toString().contains(QChar::Null);
}

bool translation(const QJsonValue &value, int maximum)
{
    if (!value.isObject())
        return false;
    const auto object = value.toObject();
    if (!text(object.value(u"en"_s), maximum))
        return false;
    for (auto it = object.begin(); it != object.end(); ++it) {
        if ((it.key() != u"en"_s && it.key() != u"zh"_s) || !text(it.value(), maximum))
            return false;
    }
    return true;
}

bool timestamp(const QJsonValue &value, bool optional = false)
{
    if (optional && value.isUndefined())
        return true;
    const auto string = value.toString();
    // Require an explicit UTC timestamp so display windows are not locale-dependent.
    return string.size() <= 32 && string.endsWith(u'Z') &&
           QDateTime::fromString(string, Qt::ISODate).isValid();
}

bool ids(const QJsonValue &value)
{
    if (!value.isArray() || value.toArray().size() > 2000)
        return false;
    QSet<QString> seen;
    for (const auto &entry : value.toArray()) {
        if (!id(entry) || seen.contains(entry.toString()))
            return false;
        seen.insert(entry.toString());
    }
    return true;
}
} // namespace

bool validSource(const QUrl &url)
{
    return url.isValid() && !url.host().isEmpty() && url.port(-1) != 0 &&
           url.userInfo().isEmpty() && !url.hasQuery() && !url.hasFragment() &&
           url.toString().size() <= 2048 &&
           (url.scheme() == u"https"_s ||
            (url.scheme() == u"http"_s &&
             (url.host() == u"localhost"_s || QHostAddress(url.host()).isLoopback())));
}

bool validPath(const QString &path)
{
    static const QRegularExpression pattern(u"^[a-zA-Z0-9][a-zA-Z0-9_./-]{0,511}$"_s);
    if (!pattern.match(path).hasMatch())
        return false;
    for (const auto &part : path.split(u'/')) {
        if (part.isEmpty() || part == u"."_s || part == u".."_s)
            return false;
    }
    return true;
}

bool validHash(const QString &hash)
{
    static const QRegularExpression pattern(u"^[a-f0-9]{64}$"_s);
    return pattern.match(hash).hasMatch();
}

bool validIndex(const QJsonObject &object)
{
    if (object.value(u"schemaVersion"_s) != 1 || !revision(object.value(u"revision"_s)))
        return false;
    for (const auto &kind : {u"sponsors"_s, u"announcements"_s}) {
        const auto entry = object.value(kind).toObject();
        if (!revision(entry.value(u"revision"_s)) ||
            !validPath(entry.value(u"path"_s).toString()) ||
            !validHash(entry.value(u"sha256"_s).toString()))
            return false;
    }
    return true;
}

bool validAnnouncement(const QJsonObject &object)
{
    if (!id(object.value(u"id"_s)) || !revision(object.value(u"notificationRevision"_s)) ||
        !translation(object.value(u"title"_s), 200) ||
        !translation(object.value(u"body"_s), 32768) ||
        !timestamp(object.value(u"publishedAt"_s)) ||
        !timestamp(object.value(u"startsAt"_s), true) ||
        !timestamp(object.value(u"expiresAt"_s), true))
        return false;
    for (const auto &key : {u"pinned"_s, u"withdrawn"_s}) {
        if (object.contains(key) && !object.value(key).isBool())
            return false;
    }
    const auto start = QDateTime::fromString(
        object.value(u"startsAt"_s).toString(object.value(u"publishedAt"_s).toString()),
        Qt::ISODate);
    const auto end = QDateTime::fromString(object.value(u"expiresAt"_s).toString(), Qt::ISODate);
    return !end.isValid() || end > start;
}

bool validDocument(const QString &kind, const QJsonObject &object)
{
    if (object.value(u"schemaVersion"_s) != 1 || !revision(object.value(u"revision"_s)) ||
        !object.value(kind).isArray())
        return false;
    const auto entries = object.value(kind).toArray();
    if ((kind != u"sponsors"_s && kind != u"announcements"_s) ||
        entries.size() > (kind == u"sponsors"_s ? 512 : 2000))
        return false;
    QSet<QString> seen;
    for (const auto &value : entries) {
        if (!value.isObject())
            return false;
        const auto entry = value.toObject();
        if (!id(entry.value(u"id"_s)) || seen.contains(entry.value(u"id"_s).toString()))
            return false;
        seen.insert(entry.value(u"id"_s).toString());
        if (kind == u"announcements"_s) {
            if (!validAnnouncement(entry))
                return false;
            continue;
        }
        const auto tier = entry.value(u"tier"_s).toString();
        if (!text(entry.value(u"name"_s), 120) ||
            (tier != u"omniscience"_s && tier != u"dockside"_s && tier != u"ragavan"_s) ||
            (entry.contains(u"featured"_s) && !entry.value(u"featured"_s).isBool()) ||
            (entry.contains(u"description"_s) && !translation(entry.value(u"description"_s), 2000)))
            return false;
        const auto profile = entry.value(u"profileUrl"_s);
        const QUrl profileUrl(profile.toString(), QUrl::StrictMode);
        if (!text(profile, 2048, true) ||
            (!profile.toString().isEmpty() &&
             (!profileUrl.isValid() || profileUrl.scheme() != u"https"_s ||
              profileUrl.host().isEmpty() || profileUrl.port(-1) == 0 ||
              !profileUrl.userInfo().isEmpty())))
            return false;
        if (entry.contains(u"avatar"_s)) {
            const auto avatar = entry.value(u"avatar"_s).toObject();
            if (!validPath(avatar.value(u"path"_s).toString()) ||
                !validHash(avatar.value(u"sha256"_s).toString()))
                return false;
        }
    }
    if (kind == u"announcements"_s) {
        const auto policy = object.value(u"display"_s).toObject();
        const auto mode = policy.value(u"mode"_s).toString();
        if ((mode != u"all"_s && mode != u"recent"_s && mode != u"selected"_s) ||
            !integer(policy.value(u"recentDays"_s), 1, 36500) ||
            !ids(policy.value(u"selectedIds"_s)))
            return false;
        for (const auto &selected : policy.value(u"selectedIds"_s).toArray()) {
            if (!seen.contains(selected.toString()))
                return false;
        }
    }
    return true;
}

QString localized(const QJsonValue &value, const QString &language)
{
    const auto text = value.toObject();
    return text.value(language).toString(text.value(u"en"_s).toString());
}

QByteArray digest(const QByteArray &bytes)
{
    return QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex();
}
} // namespace hexproof::client::public_content
