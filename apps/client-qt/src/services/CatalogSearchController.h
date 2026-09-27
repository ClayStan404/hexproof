// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantList>

namespace hexproof::client {

// Two independent latest-wins search channels. Each retains one running task
// and one replaceable request; workers capture values and never access the UI.
class CatalogSearchController : public QObject
{
    Q_OBJECT

  public:
    struct Query
    {
        QString text, type, set, language, color, rarity, legality, mana;
        bool empty() const;
    };
    explicit CatalogSearchController(QObject *parent = nullptr);
    void setContext(const QString &databasePath, const QString &language, bool cardsAvailable,
                    bool tokensAvailable);
    void search(Query query);
    void searchTokens(const QString &text, const QString &kind, const QStringList &sets);
    void refresh();
    QVariantList cards() const
    {
        return m_cards.results;
    }
    QVariantList tokens() const
    {
        return m_tokens.results;
    }
    bool searching() const
    {
        return m_cards.searching;
    }
    bool tokenSearching() const
    {
        return m_tokens.searching;
    }

  signals:
    void cardsChanged();
    void tokensChanged();
    void searchingChanged();
    void tokenSearchingChanged();
    void cardSearchFinished(const QString &error);
    void tokenSearchFinished(const QString &error);

  private:
    struct Channel
    {
        QVariantList results;
        quint64 generation = 0;
        bool requested = false;
        bool searching = false;
        bool running = false;
    };
    void request(bool tokens, bool enabled);
    void startLatest(bool tokens);
    void notifySearching(bool tokens);
    void notifyResults(bool tokens);
    QString m_databasePath;
    QString m_language;
    Query m_query;
    QString m_tokenText;
    QString m_tokenKind;
    QStringList m_tokenSets;
    bool m_cardsAvailable = false;
    bool m_tokensAvailable = false;
    Channel m_cards, m_tokens;
};

} // namespace hexproof::client
