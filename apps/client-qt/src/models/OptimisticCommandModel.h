// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>

class QTimer;

namespace hexproof::client {

class OptimisticCommandModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantMap lifeValues READ lifeValues WRITE setLifeValues NOTIFY lifeValuesChanged)
    Q_PROPERTY(
        QVariantMap tappedValues READ tappedValues WRITE setTappedValues NOTIFY tappedValuesChanged)
    Q_PROPERTY(QVariantMap counterValues READ counterValues WRITE setCounterValues NOTIFY
                   counterValuesChanged)
    Q_PROPERTY(QVariantMap commanderTaxValues READ commanderTaxValues WRITE setCommanderTaxValues
                   NOTIFY commanderTaxValuesChanged)
    Q_PROPERTY(int landPlayCount READ landPlayCount NOTIFY landPlayCountChanged)
    Q_PROPERTY(QVariantMap cardMoves READ cardMoves NOTIFY cardMovesChanged)
    Q_PROPERTY(QVariantMap battlefieldMove READ battlefieldMove NOTIFY battlefieldMoveChanged)
    Q_PROPERTY(QString phase READ phase NOTIFY phaseChanged)
    Q_PROPERTY(int timeoutMs READ timeoutMs WRITE setTimeoutMs NOTIFY timeoutMsChanged)

  public:
    explicit OptimisticCommandModel(QObject *parent = nullptr);

    QVariantMap lifeValues() const;
    QVariantMap tappedValues() const;
    QVariantMap counterValues() const;
    QVariantMap commanderTaxValues() const;
    int landPlayCount() const;
    QVariantMap cardMoves() const;
    QVariantMap battlefieldMove() const;
    QString phase() const;
    int timeoutMs() const;

    void setLifeValues(const QVariantMap &values);
    void setTappedValues(const QVariantMap &values);
    void setCounterValues(const QVariantMap &values);
    void setCommanderTaxValues(const QVariantMap &values);
    void setTimeoutMs(int timeoutMs);

    Q_INVOKABLE bool contains(const QString &kind, const QString &key) const;
    Q_INVOKABLE QVariant value(const QString &kind, const QString &key) const;
    Q_INVOKABLE void setValue(const QString &kind, const QString &key, const QVariant &value);
    Q_INVOKABLE void removeValue(const QString &kind, const QString &key);
    Q_INVOKABLE void trackValues(const QString &kind, const QVariantList &keys);
    Q_INVOKABLE void bindRequest(const QString &kind, const QString &key, const QString &requestId);
    Q_INVOKABLE void rollback(const QString &kind, const QString &key,
                              const QString &requestId = {});
    Q_INVOKABLE void beginCardMoves(const QVariantList &moves);
    Q_INVOKABLE void clearCardMoves();
    Q_INVOKABLE void setBattlefieldMove(const QVariantMap &move);
    Q_INVOKABLE void clearBattlefieldMove();
    Q_INVOKABLE void beginPhase(const QString &phase);
    Q_INVOKABLE void bindPhaseRequest(const QString &requestId);
    Q_INVOKABLE void rollbackPhase(const QString &requestId = {});
    Q_INVOKABLE void clearPhase();
    Q_INVOKABLE void beginLandPlayCount(int value);
    Q_INVOKABLE void bindLandPlayCountRequest(const QString &requestId);
    Q_INVOKABLE void rollbackLandPlayCount(const QString &requestId = {});
    Q_INVOKABLE void clearLandPlayCount();
    Q_INVOKABLE void clear();

  signals:
    void lifeValuesChanged();
    void tappedValuesChanged();
    void counterValuesChanged();
    void commanderTaxValuesChanged();
    void cardMovesChanged();
    void battlefieldMoveChanged();
    void phaseChanged();
    void landPlayCountChanged();
    void timeoutMsChanged();
    void valuesExpired(int count);

  private:
    QVariantMap *valuesForKind(const QString &kind);
    const QVariantMap *valuesForKind(const QString &kind) const;
    void setValues(const QString &kind, const QVariantMap &values);
    void emitValuesChanged(const QString &kind);
    void pruneMetadata();
    void expireValues();
    void updateTimerInterval();
    static QString compositeKey(const QString &kind, const QString &key);

    QVariantMap m_lifeValues;
    QVariantMap m_tappedValues;
    QVariantMap m_counterValues;
    QVariantMap m_commanderTaxValues;
    QVariantMap m_landPlayValues;
    QVariantMap m_cardMoves;
    QVariantMap m_battlefieldMove;
    QString m_phase;
    QVariantMap m_expiries;
    QVariantMap m_requests;
    QTimer *m_timer = nullptr;
    int m_timeoutMs = 2500;
};

} // namespace hexproof::client
