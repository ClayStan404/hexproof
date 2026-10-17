// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "RulesLaneSlotModel.h"

#include "RulesStateModels.h"

#include <QMetaObject>
#include <QRegularExpression>
#include <QStringList>

#include <algorithm>
#include <utility>

namespace hexproof::client {
namespace {
using namespace Qt::StringLiterals;

bool containsLand(const QString &typeLine)
{
    static const QRegularExpression land(u"\\bland\\b"_s);
    return typeLine.contains(land) || typeLine.contains(u"地"_s);
}

QString printedCategory(QString typeLine)
{
    typeLine = typeLine.toLower();
    const int face = typeLine.indexOf(u" // "_s);
    if (face >= 0)
        typeLine = typeLine.left(face);
    static const QRegularExpression dash(u"[—–～〜]"_s);
    typeLine = typeLine.section(dash, 0, 0);
    if (containsLand(typeLine))
        return u"land"_s;
    static const QRegularExpression planeswalker(u"\\bplaneswalker\\b"_s);
    if (typeLine.contains(planeswalker) || typeLine.contains(u"鹏洛客"_s) ||
        typeLine.contains(u"鵬洛客"_s) || typeLine.contains(u"旅法师"_s) ||
        typeLine.contains(u"旅法師"_s))
        return u"planeswalker"_s;
    return u"other"_s;
}

bool namesMatch(const QString &left, const QString &right)
{
    const QString a = left.simplified().toCaseFolded();
    const QString b = right.simplified().toCaseFolded();
    if (a.isEmpty() || b.isEmpty())
        return false;
    if (a == b)
        return true;
    const QStringList leftFaces = a.split(u" // "_s, Qt::SkipEmptyParts);
    const QStringList rightFaces = b.split(u" // "_s, Qt::SkipEmptyParts);
    return std::any_of(leftFaces.cbegin(), leftFaces.cend(),
                       [&rightFaces](const QString &face) { return rightFaces.contains(face); });
}

// Roles that decide lane membership, pile keys or member order. Any other
// source change is forwarded to the affected rows without re-piling.
bool affectsSlots(const QList<int> &roles)
{
    if (roles.isEmpty())
        return true;
    return std::any_of(roles.cbegin(), roles.cend(), [](int role) {
        switch (role) {
        case RulesCardModel::IdRole:
        case RulesCardModel::ZoneRole:
        case RulesCardModel::ZoneOwnerSeatRole:
        case RulesCardModel::VisibleRole:
        case RulesCardModel::NameRole:
        case RulesCardModel::SetCodeRole:
        case RulesCardModel::CollectorNumberRole:
        case RulesCardModel::TokenRole:
        case RulesCardModel::ControllerSeatRole:
        case RulesCardModel::TappedRole:
        case RulesCardModel::FaceDownRole:
        case RulesCardModel::PowerRole:
        case RulesCardModel::ToughnessRole:
        case RulesCardModel::DamageRole:
        case RulesCardModel::AttachedToRole:
        case RulesCardModel::ExiledCardCountRole:
        case RulesCardModel::ChosenCardIdsRole:
        case RulesCardModel::AnnotationsRole:
        case RulesCardModel::CountersSummaryRole:
            return true;
        default:
            return false;
        }
    });
}

bool presentationOnly(const QList<int> &roles)
{
    return !roles.isEmpty() && std::all_of(roles.cbegin(), roles.cend(), [](int role) {
        return role >= RulesCardModel::ActionCountRole && role <= RulesCardModel::LinksRole;
    });
}
} // namespace

RulesLaneSlotModel::RulesLaneSlotModel(QAbstractItemModel *source, int seat, const QString &zone,
                                       const QString &category, QObject *parent)
    : QAbstractListModel(parent),
      m_source(source),
      m_seat(seat),
      m_zone(zone),
      m_category(category)
{
    if (!m_source)
        return;
    connect(m_source, &QAbstractItemModel::modelReset, this, &RulesLaneSlotModel::noteStructure);
    connect(m_source, &QAbstractItemModel::rowsInserted, this, &RulesLaneSlotModel::noteStructure);
    connect(m_source, &QAbstractItemModel::rowsRemoved, this, &RulesLaneSlotModel::noteStructure);
    connect(m_source, &QAbstractItemModel::rowsMoved, this, &RulesLaneSlotModel::noteStructure);
    connect(m_source, &QAbstractItemModel::layoutChanged, this, &RulesLaneSlotModel::noteStructure);
    connect(m_source, &QAbstractItemModel::dataChanged, this, &RulesLaneSlotModel::noteSourceData);
    rebuild();
}

int RulesLaneSlotModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_rows.size();
}

QVariant RulesLaneSlotModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size() || !m_source)
        return {};
    const Entry &entry = m_rows.at(index.row());
    switch (role) {
    case SlotIndexRole:
        return entry.slot;
    case MemberRankRole:
        return entry.rank;
    case SlotSizeRole:
        return entry.size;
    default:
        return m_source->data(m_source->index(entry.sourceRow, 0), role);
    }
}

QHash<int, QByteArray> RulesLaneSlotModel::roleNames() const
{
    QHash<int, QByteArray> names = m_source ? m_source->roleNames() : QHash<int, QByteArray>{};
    names.insert(SlotIndexRole, "slotIndex");
    names.insert(MemberRankRole, "memberRank");
    names.insert(SlotSizeRole, "slotSize");
    return names;
}

void RulesLaneSlotModel::setCatalog(QObject *catalog)
{
    if (m_catalog == catalog)
        return;
    if (m_catalog)
        disconnect(m_catalog, nullptr, this, nullptr);
    m_catalog = catalog;
    m_typeLineMethod = QMetaMethod();
    m_categoryCache.clear();
    if (m_catalog) {
        const QMetaObject *meta = m_catalog->metaObject();
        const QMetaMethod available =
            metaObject()->method(metaObject()->indexOfSlot("noteCardAvailable(QString)"));
        const QMetaMethod language =
            metaObject()->method(metaObject()->indexOfSlot("noteLanguage()"));
        for (int index = 0; index < meta->methodCount(); ++index) {
            const QMetaMethod method = meta->method(index);
            const QByteArray name = method.name();
            if (method.methodType() == QMetaMethod::Signal && name == "cardAvailable")
                connect(m_catalog, method, this, available);
            else if (method.methodType() == QMetaMethod::Signal && name == "languageChanged")
                connect(m_catalog, method, this, language);
            else if (name == "cardTypeLine" &&
                     (!m_typeLineMethod.isValid() ||
                      method.parameterCount() > m_typeLineMethod.parameterCount()))
                m_typeLineMethod = method;
        }
    }
    if (m_batchDepth > 0)
        m_batchStructure = true;
    else
        rebuild();
}

void RulesLaneSlotModel::beginBatch()
{
    ++m_batchDepth;
}

void RulesLaneSlotModel::endBatch()
{
    if (m_batchDepth <= 0 || --m_batchDepth > 0)
        return;
    if (!m_batchStructure && m_batchChangedIds.isEmpty())
        return;
    const QSet<QString> changed = std::exchange(m_batchChangedIds, {});
    m_batchStructure = false;
    rebuild(changed);
}

void RulesLaneSlotModel::noteStructure()
{
    if (m_batchDepth > 0) {
        m_batchStructure = true;
        return;
    }
    rebuild();
}

void RulesLaneSlotModel::noteCardAvailable(const QString &requestedName)
{
    if (!m_catalog || m_zone != u"battlefield"_s)
        return;
    bool changed = false;
    for (auto cached = m_categoryCache.begin(); cached != m_categoryCache.end(); ++cached) {
        if (!namesMatch(cached->name, requestedName))
            continue;
        const QString typeLine =
            typeLineFor(cached->name, cached->setCode, cached->collectorNumber);
        const QString category = typeLine.isEmpty() ? u"other"_s : printedCategory(typeLine);
        if (category == cached->category)
            continue;
        cached->category = category;
        changed = true;
    }
    if (!changed)
        return;
    if (m_batchDepth > 0)
        m_batchStructure = true;
    else
        rebuild();
}

void RulesLaneSlotModel::noteLanguage()
{
    m_categoryCache.clear();
    noteStructure();
}

QVariant RulesLaneSlotModel::sourceValue(int sourceRow, int role) const
{
    if (!m_source || sourceRow < 0)
        return {};
    return m_source->data(m_source->index(sourceRow, 0), role);
}

QSet<QString> RulesLaneSlotModel::idsInRange(int first, int last) const
{
    QSet<QString> ids;
    for (int row = std::max(0, first); row <= last; ++row) {
        const QString id = sourceValue(row, RulesCardModel::IdRole).toString();
        if (!id.isEmpty())
            ids.insert(id);
    }
    return ids;
}

QString RulesLaneSlotModel::typeLineFor(const QString &name, const QString &setCode,
                                        const QString &collectorNumber) const
{
    if (!m_catalog || name.isEmpty() || !m_typeLineMethod.isValid())
        return {};
    const QMetaMethod &chosen = m_typeLineMethod;
    const bool stringReturn = chosen.returnType() == QMetaType::QString;
    const bool stringArgs =
        chosen.parameterCount() == 0 || chosen.parameterType(0) == QMetaType::QString;
    QObject *catalog = m_catalog.data();
    QString typed;
    QVariant generic;
    bool invoked = false;
    if (stringReturn && chosen.parameterCount() >= 3 && stringArgs) {
        invoked = chosen.invoke(catalog, Qt::DirectConnection, Q_RETURN_ARG(QString, typed),
                                Q_ARG(QString, name), Q_ARG(QString, setCode),
                                Q_ARG(QString, collectorNumber));
    } else if (stringReturn && chosen.parameterCount() >= 3) {
        invoked = chosen.invoke(catalog, Qt::DirectConnection, Q_RETURN_ARG(QString, typed),
                                Q_ARG(QVariant, name), Q_ARG(QVariant, setCode),
                                Q_ARG(QVariant, collectorNumber));
    } else if (stringReturn && chosen.parameterCount() == 1 && stringArgs) {
        invoked = chosen.invoke(catalog, Qt::DirectConnection, Q_RETURN_ARG(QString, typed),
                                Q_ARG(QString, name));
    } else if (stringReturn && chosen.parameterCount() == 1) {
        invoked = chosen.invoke(catalog, Qt::DirectConnection, Q_RETURN_ARG(QString, typed),
                                Q_ARG(QVariant, name));
    } else if (stringReturn) {
        invoked = chosen.invoke(catalog, Qt::DirectConnection, Q_RETURN_ARG(QString, typed));
    } else if (chosen.parameterCount() >= 3 && stringArgs) {
        invoked = chosen.invoke(catalog, Qt::DirectConnection, Q_RETURN_ARG(QVariant, generic),
                                Q_ARG(QString, name), Q_ARG(QString, setCode),
                                Q_ARG(QString, collectorNumber));
    } else if (chosen.parameterCount() >= 3) {
        invoked = chosen.invoke(catalog, Qt::DirectConnection, Q_RETURN_ARG(QVariant, generic),
                                Q_ARG(QVariant, name), Q_ARG(QVariant, setCode),
                                Q_ARG(QVariant, collectorNumber));
    } else if (chosen.parameterCount() == 1 && stringArgs) {
        invoked = chosen.invoke(catalog, Qt::DirectConnection, Q_RETURN_ARG(QVariant, generic),
                                Q_ARG(QString, name));
    } else if (chosen.parameterCount() == 1) {
        invoked = chosen.invoke(catalog, Qt::DirectConnection, Q_RETURN_ARG(QVariant, generic),
                                Q_ARG(QVariant, name));
    } else {
        invoked = chosen.invoke(catalog, Qt::DirectConnection, Q_RETURN_ARG(QVariant, generic));
    }
    if (!invoked)
        return {};
    return stringReturn ? typed : generic.toString();
}

QString RulesLaneSlotModel::categoryFor(int sourceRow)
{
    const QString power = sourceValue(sourceRow, RulesCardModel::PowerRole).toString();
    const QString toughness = sourceValue(sourceRow, RulesCardModel::ToughnessRole).toString();
    if (!power.isEmpty() || !toughness.isEmpty())
        return u"creature"_s;
    if (!sourceValue(sourceRow, RulesCardModel::VisibleRole).toBool() ||
        sourceValue(sourceRow, RulesCardModel::FaceDownRole).toBool())
        return u"other"_s;
    const QString name = sourceValue(sourceRow, RulesCardModel::NameRole).toString();
    if (name.isEmpty() || !m_catalog)
        return u"other"_s;
    const QString setCode = sourceValue(sourceRow, RulesCardModel::SetCodeRole).toString();
    const QString collectorNumber =
        sourceValue(sourceRow, RulesCardModel::CollectorNumberRole).toString();
    const QString key = QStringList{name, setCode, collectorNumber}.join(u'\u001f');
    const auto cached = m_categoryCache.constFind(key);
    if (cached != m_categoryCache.cend())
        return cached->category;
    const QString typeLine = typeLineFor(name, setCode, collectorNumber);
    const QString category = typeLine.isEmpty() ? u"other"_s : printedCategory(typeLine);
    m_categoryCache.insert(key, PrintedCategory{name, setCode, collectorNumber, category});
    return category;
}

QString RulesLaneSlotModel::stackKeyFor(int sourceRow, const QSet<QString> &hosts,
                                        bool ignoreTapped) const
{
    const QString id = sourceValue(sourceRow, RulesCardModel::IdRole).toString();
    if (m_zone != u"battlefield"_s || hosts.contains(id))
        return u"id:"_s + id;
    const bool visible = sourceValue(sourceRow, RulesCardModel::VisibleRole).toBool();
    const bool faceDown = sourceValue(sourceRow, RulesCardModel::FaceDownRole).toBool();
    const QString name = sourceValue(sourceRow, RulesCardModel::NameRole).toString();
    if (!visible || faceDown || name.isEmpty())
        return u"id:"_s + id;
    const int exiled = sourceValue(sourceRow, RulesCardModel::ExiledCardCountRole).toInt();
    const int annotations = sourceValue(sourceRow, RulesCardModel::AnnotationsRole).toList().size();
    const int chosen =
        sourceValue(sourceRow, RulesCardModel::ChosenCardIdsRole).toStringList().size();
    if (exiled > 0 || annotations > 0 || chosen > 0)
        return u"id:"_s + id;
    const QStringList parts{
        name.trimmed().toLower(),
        sourceValue(sourceRow, RulesCardModel::TokenRole).toBool() ? u"token"_s : u"card"_s,
        sourceValue(sourceRow, RulesCardModel::PowerRole).toString(),
        sourceValue(sourceRow, RulesCardModel::ToughnessRole).toString(),
        sourceValue(sourceRow, RulesCardModel::CountersSummaryRole).toString(),
        QString::number(sourceValue(sourceRow, RulesCardModel::DamageRole).toInt()),
        sourceValue(sourceRow, RulesCardModel::AttachedToRole).toString(),
        QString::number(exiled),
        !ignoreTapped && sourceValue(sourceRow, RulesCardModel::TappedRole).toBool() ? u"1"_s
                                                                                     : u"0"_s};
    return parts.join(u'\u001f');
}

void RulesLaneSlotModel::noteSourceData(const QModelIndex &topLeft, const QModelIndex &bottomRight,
                                        const QList<int> &roles)
{
    const QSet<QString> ids = idsInRange(topLeft.row(), bottomRight.row());
    if (m_batchDepth > 0) {
        m_batchChangedIds.unite(ids);
        if (affectsSlots(roles))
            m_batchStructure = true;
        return;
    }
    if (!presentationOnly(roles) && affectsSlots(roles)) {
        rebuild(ids);
        return;
    }
    for (const QString &id : ids) {
        const auto row = m_rowOfId.constFind(id);
        if (row != m_rowOfId.cend())
            emit dataChanged(index(*row, 0), index(*row, 0), roles);
    }
}

void RulesLaneSlotModel::rebuild(const QSet<QString> &changedIds)
{
    if (!m_source)
        return;
    struct Candidate
    {
        int sourceRow = -1;
        QString id;
        QString name;
        QString key;
        bool plain = true;
        bool tapped = false;
        bool attached = false;
    };
    const bool battlefield = m_zone == u"battlefield"_s;
    const int count = m_source->rowCount();
    QSet<QString> hosts;
    if (battlefield) {
        for (int row = 0; row < count; ++row) {
            const QString host = sourceValue(row, RulesCardModel::AttachedToRole).toString();
            if (!host.isEmpty())
                hosts.insert(host);
        }
    }
    QVector<Candidate> accepted;
    accepted.reserve(count);
    QHash<QString, int> layoutGroups;
    for (int row = 0; row < count; ++row) {
        if (battlefield) {
            if (sourceValue(row, RulesCardModel::ControllerSeatRole).toInt() != m_seat)
                continue;
            if (categoryFor(row) != m_category)
                continue;
        } else if (sourceValue(row, RulesCardModel::ZoneOwnerSeatRole).toInt() != m_seat ||
                   sourceValue(row, RulesCardModel::ZoneRole).toString() != m_zone) {
            continue;
        }
        Candidate candidate;
        candidate.sourceRow = row;
        candidate.id = sourceValue(row, RulesCardModel::IdRole).toString();
        candidate.name = sourceValue(row, RulesCardModel::NameRole).toString();
        candidate.key = stackKeyFor(row, hosts);
        candidate.plain =
            sourceValue(row, RulesCardModel::CountersSummaryRole).toString().isEmpty() &&
            sourceValue(row, RulesCardModel::DamageRole).toInt() == 0;
        candidate.tapped = sourceValue(row, RulesCardModel::TappedRole).toBool();
        candidate.attached = !sourceValue(row, RulesCardModel::AttachedToRole).toString().isEmpty();
        if (!candidate.attached)
            ++layoutGroups[stackKeyFor(row, hosts, true)];
        accepted.append(candidate);
    }
    std::sort(accepted.begin(), accepted.end(), [](const Candidate &left, const Candidate &right) {
        const int names = QString::localeAwareCompare(left.name, right.name);
        return names != 0 ? names < 0 : QString::localeAwareCompare(left.id, right.id) < 0;
    });

    QHash<QString, int> slotOf;
    QVector<QVector<int>> groups;
    QVector<int> attachments;
    for (int index = 0; index < accepted.size(); ++index) {
        if (accepted.at(index).attached) {
            attachments.append(index);
            continue;
        }
        const QString &key = accepted.at(index).key;
        if (!slotOf.contains(key)) {
            slotOf.insert(key, groups.size());
            groups.append(QVector<int>());
        }
        groups[slotOf.value(key)].append(index);
    }
    // Within a name the plain pile leads, then its tapped copies. A counter or
    // damage on one copy adds a slot after those instead of sliding the plain copies.
    std::stable_sort(groups.begin(), groups.end(),
                     [&accepted](const QVector<int> &left, const QVector<int> &right) {
                         const Candidate &a = accepted.at(left.constFirst());
                         const Candidate &b = accepted.at(right.constFirst());
                         const int names = QString::localeAwareCompare(a.name, b.name);
                         if (names != 0)
                             return names < 0;
                         if (a.plain != b.plain)
                             return a.plain;
                         return a.key < b.key;
                     });
    for (QVector<int> &group : groups) {
        std::sort(group.begin(), group.end(), [&accepted](int left, int right) {
            if (accepted.at(left).tapped != accepted.at(right).tapped)
                return accepted.at(left).tapped;
            return QString::localeAwareCompare(accepted.at(left).id, accepted.at(right).id) < 0;
        });
    }

    QVector<Entry> rows;
    QVariantList stacks;
    rows.reserve(accepted.size());
    for (int slot = 0; slot < groups.size(); ++slot) {
        const QVector<int> &group = groups.at(slot);
        QVariantList ids;
        for (int rank = 0; rank < group.size(); ++rank) {
            const Candidate &candidate = accepted.at(group.at(rank));
            ids.append(candidate.id);
            Entry entry;
            entry.sourceRow = candidate.sourceRow;
            entry.id = candidate.id;
            entry.slot = slot;
            entry.rank = rank;
            entry.size = static_cast<int>(group.size());
            rows.append(entry);
        }
        stacks.append(QVariant(ids));
    }
    for (const int index : attachments) {
        Entry entry;
        entry.sourceRow = accepted.at(index).sourceRow;
        entry.id = accepted.at(index).id;
        entry.slot = -1;
        entry.rank = -1;
        rows.append(entry);
    }
    // Each public pile may split into ready/spent slots, but a hundred
    // identical copies must not reserve a hundred independent card positions.
    // The same key rules keep concealed objects and attachment hosts unique.
    int layoutStackCount = 0;
    for (const int size : std::as_const(layoutGroups))
        layoutStackCount += std::min(2, size);
    publish(rows, stacks, layoutStackCount, changedIds);
}

void RulesLaneSlotModel::publish(QVector<Entry> next, QVariantList stacks, int layoutStackCount,
                                 const QSet<QString> &changedIds)
{
    QHash<QString, int> nextIndex;
    nextIndex.reserve(next.size());
    for (int row = 0; row < next.size(); ++row)
        nextIndex.insert(next.at(row).id, row);

    // Surviving rows read the new source rows before any delegate can ask.
    QHash<QString, Entry> before;
    for (Entry &entry : m_rows) {
        const auto found = nextIndex.constFind(entry.id);
        if (found == nextIndex.cend())
            continue;
        before.insert(entry.id, entry);
        entry = next.at(*found);
    }

    for (int row = m_rows.size() - 1; row >= 0; --row) {
        if (nextIndex.contains(m_rows.at(row).id))
            continue;
        beginRemoveRows({}, row, row);
        m_rows.removeAt(row);
        endRemoveRows();
    }

    // Moves keep delegates, so a tap inside a pile reorders without
    // recreating every card in the lane.
    for (int target = 0; target < next.size(); ++target) {
        const QString &id = next.at(target).id;
        if (target < m_rows.size() && m_rows.at(target).id == id)
            continue;
        int source = -1;
        for (int look = target + 1; look < m_rows.size(); ++look) {
            if (m_rows.at(look).id == id) {
                source = look;
                break;
            }
        }
        if (source < 0) {
            beginInsertRows({}, target, target);
            m_rows.insert(target, next.at(target));
            endInsertRows();
            continue;
        }
        beginMoveRows({}, source, source, {}, target);
        m_rows.move(source, target);
        endMoveRows();
    }

    m_rowOfId.clear();
    m_rowOfId.reserve(m_rows.size());
    for (int row = 0; row < m_rows.size(); ++row)
        m_rowOfId.insert(m_rows.at(row).id, row);

    static const QList<int> slotRoles{SlotIndexRole, MemberRankRole, SlotSizeRole};
    for (int row = 0; row < m_rows.size(); ++row) {
        const Entry &entry = m_rows.at(row);
        const auto previous = before.constFind(entry.id);
        if (previous == before.cend())
            continue;
        if (changedIds.contains(entry.id))
            emit dataChanged(index(row, 0), index(row, 0));
        else if (previous->slot != entry.slot || previous->rank != entry.rank ||
                 previous->size != entry.size)
            emit dataChanged(index(row, 0), index(row, 0), slotRoles);
    }
    const bool stacksUpdated = m_stacks != stacks;
    const bool layoutUpdated = m_layoutStackCount != layoutStackCount;
    m_stacks = std::move(stacks);
    m_layoutStackCount = layoutStackCount;
    if (stacksUpdated)
        emit stacksChanged();
    if (layoutUpdated)
        emit layoutStackCountChanged();
}

} // namespace hexproof::client
