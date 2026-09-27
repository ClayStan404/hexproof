// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "LimitedSessionState.h"

#include <functional>

namespace hexproof::client {

// A local practice session. Its projection never belongs to an online event.
class DraftSimulator : public QObject
{
    Q_OBJECT
    Q_PROPERTY(LimitedSessionState *state READ state CONSTANT)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(QVariantMap constructionDraft MEMBER m_constructionDraft)

  public:
    using PackGenerator = std::function<QVariantList(const QVariantMap &, int)>;
    using DeckSaver = std::function<QString(const QString &, const QVariantMap &)>;

    explicit DraftSimulator(QObject *parent = nullptr);
    LimitedSessionState *state()
    {
        return &m_state;
    }
    QString lastError() const
    {
        return m_lastError;
    }
    void setPackGenerator(PackGenerator generator);
    void setDeckSaver(DeckSaver saver);

    Q_INVOKABLE bool start(const QVariantMap &product, int seats);
    Q_INVOKABLE bool pick(const QString &instanceId);
    Q_INVOKABLE bool saveDeck(const QString &name, const QVariantList &instanceIds,
                              const QVariantList &basicLands);
    Q_INVOKABLE void reset();

  signals:
    void lastErrorChanged();

  private:
    bool fail(const QString &message);
    void clearError();
    void openRound();
    void publish();
    int botChoice(int seat) const;

    LimitedSessionState m_state;
    PackGenerator m_generatePacks;
    DeckSaver m_saveDeck;
    QString m_lastError;
    QString m_sessionId;
    QVariantMap m_product;
    QVariantList m_unopenedPacks;
    QList<QVariantList> m_packs;
    QList<QVariantList> m_pools;
    QVariantMap m_constructionDraft;
    QVariantList m_savedIds;
    QVariantList m_savedBasics;
    int m_round = 0;
    bool m_finished = false;
    bool m_saved = false;
};

} // namespace hexproof::client
