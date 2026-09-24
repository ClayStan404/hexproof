// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "PublicContentService.h"

#include "PublicContentSchema.h"

#include <QFileInfo>
#include <QJsonArray>

#include <algorithm>

namespace hexproof::client {
namespace {
using namespace Qt::StringLiterals;
using namespace public_content;
} // namespace

void PublicContentService::setLanguage(const QString &language)
{
    const auto normalized = language == u"zh"_s ? u"zh"_s : u"en"_s;
    if (m_language == normalized)
        return;
    m_language = normalized;
    emit contentChanged();
}

QString PublicContentService::avatarSource(const QJsonObject &entry) const
{
    const auto hash = entry.value(u"avatar"_s).toObject().value(u"sha256"_s).toString();
    if (m_bundledAvatars.contains(hash))
        return m_bundledAvatars.value(hash);
    if (m_validAvatars.contains(hash) && QFileInfo::exists(avatarPath(hash)))
        return QUrl::fromLocalFile(avatarPath(hash)).toString();
    return {};
}

QVariantList PublicContentService::sponsors() const
{
    QVariantList result;
    for (const auto &value : m_documents.value(u"sponsors"_s).value(u"sponsors"_s).toArray()) {
        const auto entry = value.toObject();
        result.append(
            QVariantMap{{u"id"_s, entry.value(u"id"_s).toString()},
                        {u"name"_s, entry.value(u"name"_s).toString()},
                        {u"tier"_s, entry.value(u"tier"_s).toString()},
                        {u"featured"_s, entry.value(u"featured"_s).toBool()},
                        {u"description"_s, localized(entry.value(u"description"_s), m_language)},
                        {u"avatarSource"_s, avatarSource(entry)},
                        {u"profileUrl"_s, entry.value(u"profileUrl"_s).toString()}});
    }
    return result;
}

QStringList PublicContentService::newSponsorIds() const
{
    QStringList result;
    const auto seen = m_state.value(u"seenSponsors"_s).toObject();
    for (const auto &value : m_documents.value(u"sponsors"_s).value(u"sponsors"_s).toArray()) {
        const auto id = value.toObject().value(u"id"_s).toString();
        if (!seen.value(id).toBool())
            result.append(id);
    }
    return result;
}

QStringList PublicContentService::takeSponsorAnnouncement()
{
    if (!m_startupReady || m_sponsorPopupOffered)
        return {};
    m_sponsorPopupOffered = true;
    const bool versionUnseen =
        !m_applicationVersion.isEmpty() &&
        m_state.value(u"seenSponsorVersion"_s).toString() != m_applicationVersion;
    if (!versionUnseen && newSponsorIds().isEmpty())
        return {};
    // Capture the whole displayed roster; new-ID highlighting is independent of the trigger.
    for (const auto &value : m_documents.value(u"sponsors"_s).value(u"sponsors"_s).toArray())
        m_presentedSponsorIds.append(value.toObject().value(u"id"_s).toString());
    return m_presentedSponsorIds;
}

void PublicContentService::deferSponsorAnnouncement()
{
    m_sponsorPopupOffered = true;
}

bool PublicContentService::acknowledgeSponsors(const QStringList &ids)
{
    if (m_presentedSponsorIds.isEmpty())
        return false;
    auto seen = m_state.value(u"seenSponsors"_s).toObject();
    for (const auto &id : ids) {
        if (m_presentedSponsorIds.contains(id))
            seen.insert(id, true);
    }
    auto next = m_state;
    next.insert(u"seenSponsors"_s, seen);
    if (!m_applicationVersion.isEmpty() &&
        std::all_of(m_presentedSponsorIds.begin(), m_presentedSponsorIds.end(),
                    [&ids](const QString &id) { return ids.contains(id); }))
        next.insert(u"seenSponsorVersion"_s, m_applicationVersion);
    return saveState(next);
}

QVariantList PublicContentService::announcements(bool current) const
{
    const auto document = m_documents.value(u"announcements"_s);
    const auto policy = document.value(u"display"_s).toObject();
    const auto mode = policy.value(u"mode"_s).toString();
    const auto selected = policy.value(u"selectedIds"_s).toArray();
    const auto now = QDateTime::currentDateTimeUtc();
    const auto earliest = now.addDays(-policy.value(u"recentDays"_s).toInt(90));
    const auto read = m_state.value(u"readAnnouncements"_s).toObject();
    auto all = m_archive;
    QSet<QString> listed;
    for (const auto &value : document.value(u"announcements"_s).toArray()) {
        const auto id = value.toObject().value(u"id"_s).toString();
        all.insert(id, value);
        listed.insert(id);
    }
    QVariantList result;
    for (auto it = all.begin(); it != all.end(); ++it) {
        const auto entry = it.value().toObject();
        const auto id = it.key();
        const auto published =
            QDateTime::fromString(entry.value(u"publishedAt"_s).toString(), Qt::ISODate);
        const auto starts =
            QDateTime::fromString(entry.value(u"startsAt"_s).toString(), Qt::ISODate);
        const auto expires =
            QDateTime::fromString(entry.value(u"expiresAt"_s).toString(), Qt::ISODate);
        if (entry.value(u"withdrawn"_s).toBool() || published > now ||
            (starts.isValid() && starts > now))
            continue;
        const bool eligible =
            mode == u"all"_s ||
            (mode == u"recent"_s && (published >= earliest || entry.value(u"pinned"_s).toBool())) ||
            (mode == u"selected"_s && selected.contains(id));
        const bool active =
            listed.contains(id) && eligible && (!expires.isValid() || expires > now);
        if (active != current)
            continue;
        const bool unread = active && read.value(id).toInteger() <
                                          entry.value(u"notificationRevision"_s).toInteger();
        result.append(QVariantMap{{u"id"_s, id},
                                  {u"title"_s, localized(entry.value(u"title"_s), m_language)},
                                  {u"body"_s, localized(entry.value(u"body"_s), m_language)},
                                  {u"publishedAt"_s, published},
                                  {u"pinned"_s, entry.value(u"pinned"_s).toBool()},
                                  {u"unread"_s, unread}});
    }
    std::stable_sort(result.begin(), result.end(), [](const QVariant &left, const QVariant &right) {
        const auto a = left.toMap();
        const auto b = right.toMap();
        if (a.value(u"pinned"_s).toBool() != b.value(u"pinned"_s).toBool())
            return a.value(u"pinned"_s).toBool();
        return a.value(u"publishedAt"_s).toDateTime() > b.value(u"publishedAt"_s).toDateTime();
    });
    return result;
}

QVariantList PublicContentService::currentAnnouncements() const
{
    return announcements(true);
}

QVariantList PublicContentService::historicalAnnouncements() const
{
    return announcements(false);
}

int PublicContentService::unreadCount() const
{
    int count = 0;
    for (const auto &value : currentAnnouncements())
        count += value.toMap().value(u"unread"_s).toBool();
    return count;
}

QString PublicContentService::latestUnreadTitle() const
{
    for (const auto &value : currentAnnouncements()) {
        const auto item = value.toMap();
        if (item.value(u"unread"_s).toBool())
            return item.value(u"title"_s).toString();
    }
    return {};
}

bool PublicContentService::markRead(const QString &id)
{
    auto all = m_archive;
    for (const auto &entry :
         m_documents.value(u"announcements"_s).value(u"announcements"_s).toArray())
        all.insert(entry.toObject().value(u"id"_s).toString(), entry);
    if (!all.contains(id))
        return false;
    auto read = m_state.value(u"readAnnouncements"_s).toObject();
    read.insert(id, all.value(id).toObject().value(u"notificationRevision"_s));
    auto next = m_state;
    next.insert(u"readAnnouncements"_s, read);
    return saveState(next);
}

bool PublicContentService::markAllRead()
{
    auto read = m_state.value(u"readAnnouncements"_s).toObject();
    QSet<QString> current;
    for (const auto &entry : currentAnnouncements())
        current.insert(entry.toMap().value(u"id"_s).toString());
    for (const auto &value :
         m_documents.value(u"announcements"_s).value(u"announcements"_s).toArray()) {
        const auto entry = value.toObject();
        const auto id = entry.value(u"id"_s).toString();
        if (current.contains(id))
            read.insert(id, entry.value(u"notificationRevision"_s));
    }
    auto next = m_state;
    next.insert(u"readAnnouncements"_s, read);
    return saveState(next);
}
} // namespace hexproof::client
