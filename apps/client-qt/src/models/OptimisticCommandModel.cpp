// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "OptimisticCommandModel.h"

#include <QDateTime>
#include <QTimer>

#include <algorithm>

using namespace Qt::StringLiterals;

namespace hexproof::client {

namespace {
constexpr QChar kCompositeSeparator = u'\x1f';
const QString kPhaseKey = u"current"_s;
const QString kLandPlayKey = u"current"_s;
} // namespace

OptimisticCommandModel::OptimisticCommandModel(QObject *parent)
    : QObject(parent),
      m_timer(new QTimer(this))
{
    m_timer->setSingleShot(false);
    updateTimerInterval();
    connect(m_timer, &QTimer::timeout, this, &OptimisticCommandModel::expireValues);
}

QVariantMap OptimisticCommandModel::lifeValues() const
{
    return m_lifeValues;
}

QVariantMap OptimisticCommandModel::tappedValues() const
{
    return m_tappedValues;
}

QVariantMap OptimisticCommandModel::counterValues() const
{
    return m_counterValues;
}

QVariantMap OptimisticCommandModel::commanderTaxValues() const
{
    return m_commanderTaxValues;
}

int OptimisticCommandModel::landPlayCount() const
{
    return m_landPlayValues.contains(kLandPlayKey) ? m_landPlayValues.value(kLandPlayKey).toInt()
                                                   : -1;
}

QVariantMap OptimisticCommandModel::cardMoves() const
{
    return m_cardMoves;
}

QVariantMap OptimisticCommandModel::battlefieldMove() const
{
    return m_battlefieldMove;
}

QString OptimisticCommandModel::phase() const
{
    return m_phase;
}

int OptimisticCommandModel::timeoutMs() const
{
    return m_timeoutMs;
}

void OptimisticCommandModel::setLifeValues(const QVariantMap &values)
{
    setValues(u"life"_s, values);
}

void OptimisticCommandModel::setTappedValues(const QVariantMap &values)
{
    setValues(u"tapped"_s, values);
}

void OptimisticCommandModel::setCounterValues(const QVariantMap &values)
{
    setValues(u"counter"_s, values);
}

void OptimisticCommandModel::setCommanderTaxValues(const QVariantMap &values)
{
    setValues(u"tax"_s, values);
}

void OptimisticCommandModel::setTimeoutMs(int timeoutMs)
{
    const int nextTimeout = std::max(1, timeoutMs);
    if (m_timeoutMs == nextTimeout)
        return;
    m_timeoutMs = nextTimeout;
    updateTimerInterval();
    emit timeoutMsChanged();
}

bool OptimisticCommandModel::contains(const QString &kind, const QString &key) const
{
    if (kind == u"phase"_s)
        return key == kPhaseKey && !m_phase.isEmpty();
    const QVariantMap *values = valuesForKind(kind);
    return values && values->contains(key);
}

QVariant OptimisticCommandModel::value(const QString &kind, const QString &key) const
{
    if (kind == u"phase"_s && key == kPhaseKey)
        return m_phase;
    const QVariantMap *values = valuesForKind(kind);
    return values ? values->value(key) : QVariant{};
}

void OptimisticCommandModel::setValue(const QString &kind, const QString &key,
                                      const QVariant &value)
{
    QVariantMap *values = valuesForKind(kind);
    if (!values || key.isEmpty() || values->value(key) == value)
        return;
    values->insert(key, value);
    emitValuesChanged(kind);
}

void OptimisticCommandModel::removeValue(const QString &kind, const QString &key)
{
    QVariantMap *values = valuesForKind(kind);
    if (!values || key.isEmpty())
        return;

    const QString composite = compositeKey(kind, key);
    m_expiries.remove(composite);
    m_requests.remove(composite);
    if (values->remove(key) > 0) {
        emitValuesChanged(kind);
        if (kind == u"move"_s && m_battlefieldMove.value(u"cardId"_s).toString() == key) {
            m_battlefieldMove.clear();
            emit battlefieldMoveChanged();
        }
    }
    if (m_expiries.isEmpty())
        m_timer->stop();
}

void OptimisticCommandModel::trackValues(const QString &kind, const QVariantList &keys)
{
    const QVariantMap *values = valuesForKind(kind);
    if (!values || keys.isEmpty())
        return;

    const qint64 expiresAt = QDateTime::currentMSecsSinceEpoch() + m_timeoutMs;
    for (const QVariant &value : keys) {
        const QString key = value.toString();
        if (!key.isEmpty() && values->contains(key))
            m_expiries.insert(compositeKey(kind, key), expiresAt);
    }
    if (!m_expiries.isEmpty() && !m_timer->isActive())
        m_timer->start();
}

void OptimisticCommandModel::bindRequest(const QString &kind, const QString &key,
                                         const QString &requestId)
{
    if (!contains(kind, key) || requestId.isEmpty())
        return;
    m_requests.insert(compositeKey(kind, key), requestId);
}

void OptimisticCommandModel::rollback(const QString &kind, const QString &key,
                                      const QString &requestId)
{
    if (!contains(kind, key))
        return;
    const QString composite = compositeKey(kind, key);
    if (!requestId.isEmpty() && m_requests.value(composite).toString() != requestId)
        return;
    removeValue(kind, key);
}

void OptimisticCommandModel::beginCardMoves(const QVariantList &moves)
{
    const qint64 expiresAt = QDateTime::currentMSecsSinceEpoch() + m_timeoutMs;
    bool changed = false;
    for (const QVariant &value : moves) {
        const QVariantMap move = value.toMap();
        const QString cardId = move.value(u"cardId"_s).toString();
        if (cardId.isEmpty())
            continue;

        QVariantMap card = move.value(u"card"_s).toMap();
        if (card.value(u"id"_s).toString().isEmpty())
            card.insert(u"id"_s, cardId);
        card.insert(u"pending"_s, true);
        const QString fromZone = move.value(u"fromZone"_s).toString();
        card.insert(u"faceDown"_s,
                    fromZone == u"library"_s && card.value(u"name"_s).toString().isEmpty());
        if (fromZone == u"hand"_s && !card.contains(u"ownerSeat"_s))
            card.insert(u"ownerSeat"_s, move.value(u"fromSeat"_s, -1));

        QVariantMap normalized{
            {u"cardId"_s, cardId},
            {u"card"_s, card},
            {u"fromZone"_s, fromZone},
            {u"fromSeat"_s, move.value(u"fromSeat"_s, -1)},
            {u"toZone"_s, move.value(u"toZone"_s).toString()},
            {u"toSeat"_s, move.value(u"toSeat"_s, -1)},
            {u"x"_s, move.value(u"x"_s, 0)},
            {u"y"_s, move.value(u"y"_s, 0)},
            {u"tapped"_s, move.value(u"tapped"_s, false).toBool()},
            // Library tops carry the ids already on the target battlefield so
            // reconcile can recognize the newly placed permanent (the server
            // assigns a fresh instance id).
            {u"knownCardIds"_s, move.value(u"knownCardIds"_s)},
        };
        m_cardMoves.insert(cardId, normalized);
        const QString composite = compositeKey(u"move"_s, cardId);
        m_expiries.insert(composite, expiresAt);
        m_requests.remove(composite);
        changed = true;
    }
    if (!changed)
        return;
    emit cardMovesChanged();
    if (!m_timer->isActive())
        m_timer->start();
}

void OptimisticCommandModel::clearCardMoves()
{
    const bool movesChanged = !m_cardMoves.isEmpty();
    const bool battlefieldChanged = !m_battlefieldMove.isEmpty();
    m_cardMoves.clear();
    m_battlefieldMove.clear();

    const QStringList keys = m_expiries.keys();
    for (const QString &composite : keys) {
        if (composite.startsWith(u"move"_s + kCompositeSeparator)) {
            m_expiries.remove(composite);
            m_requests.remove(composite);
        }
    }
    if (movesChanged)
        emit cardMovesChanged();
    if (battlefieldChanged)
        emit battlefieldMoveChanged();
    if (m_expiries.isEmpty())
        m_timer->stop();
}

void OptimisticCommandModel::setBattlefieldMove(const QVariantMap &move)
{
    if (m_battlefieldMove == move)
        return;
    m_battlefieldMove = move;
    emit battlefieldMoveChanged();
}

void OptimisticCommandModel::clearBattlefieldMove()
{
    const QString cardId = m_battlefieldMove.value(u"cardId"_s).toString();
    if (!m_battlefieldMove.isEmpty()) {
        m_battlefieldMove.clear();
        emit battlefieldMoveChanged();
    }
    if (!cardId.isEmpty())
        removeValue(u"move"_s, cardId);
}

void OptimisticCommandModel::beginPhase(const QString &phase)
{
    if (phase.isEmpty())
        return;
    const bool changed = m_phase != phase;
    m_phase = phase;
    const QString composite = compositeKey(u"phase"_s, kPhaseKey);
    m_expiries.insert(composite, QDateTime::currentMSecsSinceEpoch() + m_timeoutMs);
    m_requests.remove(composite);
    if (changed)
        emit phaseChanged();
    if (!m_timer->isActive())
        m_timer->start();
}

void OptimisticCommandModel::bindPhaseRequest(const QString &requestId)
{
    if (m_phase.isEmpty() || requestId.isEmpty())
        return;
    m_requests.insert(compositeKey(u"phase"_s, kPhaseKey), requestId);
}

void OptimisticCommandModel::rollbackPhase(const QString &requestId)
{
    if (m_phase.isEmpty())
        return;
    const QString composite = compositeKey(u"phase"_s, kPhaseKey);
    if (!requestId.isEmpty() && m_requests.value(composite).toString() != requestId)
        return;
    clearPhase();
}

void OptimisticCommandModel::clearPhase()
{
    const QString composite = compositeKey(u"phase"_s, kPhaseKey);
    m_expiries.remove(composite);
    m_requests.remove(composite);
    if (!m_phase.isEmpty()) {
        m_phase.clear();
        emit phaseChanged();
    }
    if (m_expiries.isEmpty())
        m_timer->stop();
}

void OptimisticCommandModel::beginLandPlayCount(int value)
{
    if (value < 0)
        return;
    setValue(u"landPlay"_s, kLandPlayKey, value);
    trackValues(u"landPlay"_s, {kLandPlayKey});
}

void OptimisticCommandModel::bindLandPlayCountRequest(const QString &requestId)
{
    bindRequest(u"landPlay"_s, kLandPlayKey, requestId);
}

void OptimisticCommandModel::rollbackLandPlayCount(const QString &requestId)
{
    rollback(u"landPlay"_s, kLandPlayKey, requestId);
}

void OptimisticCommandModel::clearLandPlayCount()
{
    removeValue(u"landPlay"_s, kLandPlayKey);
}

void OptimisticCommandModel::clear()
{
    m_timer->stop();
    m_expiries.clear();
    m_requests.clear();

    const bool lifeChanged = !m_lifeValues.isEmpty();
    const bool tappedChanged = !m_tappedValues.isEmpty();
    const bool counterChanged = !m_counterValues.isEmpty();
    const bool taxChanged = !m_commanderTaxValues.isEmpty();
    const bool movesChanged = !m_cardMoves.isEmpty();
    const bool battlefieldChanged = !m_battlefieldMove.isEmpty();
    const bool phaseWasSet = !m_phase.isEmpty();
    const bool landPlayChanged = !m_landPlayValues.isEmpty();
    m_lifeValues.clear();
    m_tappedValues.clear();
    m_counterValues.clear();
    m_commanderTaxValues.clear();
    m_cardMoves.clear();
    m_battlefieldMove.clear();
    m_phase.clear();
    m_landPlayValues.clear();
    if (lifeChanged)
        emit lifeValuesChanged();
    if (tappedChanged)
        emit tappedValuesChanged();
    if (counterChanged)
        emit counterValuesChanged();
    if (taxChanged)
        emit commanderTaxValuesChanged();
    if (movesChanged)
        emit cardMovesChanged();
    if (battlefieldChanged)
        emit battlefieldMoveChanged();
    if (phaseWasSet)
        emit phaseChanged();
    if (landPlayChanged)
        emit landPlayCountChanged();
}

QVariantMap *OptimisticCommandModel::valuesForKind(const QString &kind)
{
    if (kind == u"life"_s)
        return &m_lifeValues;
    if (kind == u"tapped"_s)
        return &m_tappedValues;
    if (kind == u"counter"_s)
        return &m_counterValues;
    if (kind == u"tax"_s)
        return &m_commanderTaxValues;
    if (kind == u"move"_s)
        return &m_cardMoves;
    if (kind == u"landPlay"_s)
        return &m_landPlayValues;
    return nullptr;
}

const QVariantMap *OptimisticCommandModel::valuesForKind(const QString &kind) const
{
    if (kind == u"life"_s)
        return &m_lifeValues;
    if (kind == u"tapped"_s)
        return &m_tappedValues;
    if (kind == u"counter"_s)
        return &m_counterValues;
    if (kind == u"tax"_s)
        return &m_commanderTaxValues;
    if (kind == u"move"_s)
        return &m_cardMoves;
    if (kind == u"landPlay"_s)
        return &m_landPlayValues;
    return nullptr;
}

void OptimisticCommandModel::setValues(const QString &kind, const QVariantMap &values)
{
    QVariantMap *target = valuesForKind(kind);
    if (!target || *target == values)
        return;
    *target = values;
    pruneMetadata();
    emitValuesChanged(kind);
}

void OptimisticCommandModel::emitValuesChanged(const QString &kind)
{
    if (kind == u"life"_s)
        emit lifeValuesChanged();
    else if (kind == u"tapped"_s)
        emit tappedValuesChanged();
    else if (kind == u"counter"_s)
        emit counterValuesChanged();
    else if (kind == u"tax"_s)
        emit commanderTaxValuesChanged();
    else if (kind == u"move"_s)
        emit cardMovesChanged();
    else if (kind == u"landPlay"_s)
        emit landPlayCountChanged();
}

void OptimisticCommandModel::pruneMetadata()
{
    const QStringList keys = m_expiries.keys();
    for (const QString &composite : keys) {
        const qsizetype separator = composite.indexOf(kCompositeSeparator);
        if (separator < 1 || !contains(composite.left(separator), composite.mid(separator + 1))) {
            m_expiries.remove(composite);
            m_requests.remove(composite);
        }
    }
    if (m_expiries.isEmpty())
        m_timer->stop();
}

void OptimisticCommandModel::expireValues()
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    const QStringList keys = m_expiries.keys();
    int expiredCount = 0;
    for (const QString &composite : keys) {
        if (m_expiries.value(composite).toLongLong() > now)
            continue;
        const qsizetype separator = composite.indexOf(kCompositeSeparator);
        if (separator > 0) {
            const QString kind = composite.left(separator);
            const QString key = composite.mid(separator + 1);
            if (kind == u"phase"_s && key == kPhaseKey) {
                if (!m_phase.isEmpty())
                    ++expiredCount;
                clearPhase();
            } else {
                if (contains(kind, key))
                    ++expiredCount;
                removeValue(kind, key);
            }
        } else {
            m_expiries.remove(composite);
            m_requests.remove(composite);
        }
    }
    if (m_expiries.isEmpty())
        m_timer->stop();
    if (expiredCount > 0)
        emit valuesExpired(expiredCount);
}

void OptimisticCommandModel::updateTimerInterval()
{
    m_timer->setInterval(std::max(10, std::min(100, m_timeoutMs / 4)));
}

QString OptimisticCommandModel::compositeKey(const QString &kind, const QString &key)
{
    return kind + kCompositeSeparator + key;
}

} // namespace hexproof::client
